--- String streams.
-- Streams are similar to @{pipes}, but specialized for strings. They serve
-- the same purpose as LTN12, i.e. typically processing input from a socket.
-- @module stream
-- @usage local stream = require 'lumen.stream'
-- @alias M

local sched = require 'lumen.sched'
local log=require 'lumen.log'
local queue=require 'lumen.lib.queue'

--get locals for some useful things
local setmetatable, tostring = setmetatable, tostring

local M = {}

--- Read from a stream.
-- Will block if there is no (or not enough) data to read, until it appears. Also accessible as streamd:read([len])
-- @param streamd the the stream descriptor to read from.
-- @param length optional length of string to be returned.
-- @return  a string if data is available, _nil,'timeout'_ on timeout, _nil, 'closed', err_ if
-- stream is closed and empty (_err_ is the additinal error parameter provided on @{write} when closing).
M.read = function (streamd, length)
	if length == 0 then return '' end
	length = tonumber(length) or -1
	
	local buff_data = streamd.buff_data
	if streamd.closed and (streamd.len<length or streamd.len==0) then
		return nil, 'closed', streamd.closed
	end
	
	while streamd.len == 0 or (length>0 and streamd.len < length) do
    streamd.rblocked = true
		local ev = sched.wait(streamd.waitd_data)
    streamd.rblocked = false
		if not ev then return nil, 'timeout' end
		if streamd.closed and (streamd.len<length or streamd.len==0) then --and #streamd.buff_data == 0 then
			return nil, 'closed', streamd.closed
		end
	end
	
	if #buff_data > 1 then
		--slow path
		local s = table.concat(buff_data)
		streamd.buff_data = {[1] = s}
		buff_data = streamd.buff_data
	end
	
	local s =  buff_data[1]
	
	if length>0 then
		--cut len bytes
		local rlen = #s-length
		if rlen>0 then 
			buff_data[1] = s:sub(-rlen) 
		else
			buff_data[1] = nil
		end
		s=s:sub(1, length)
		streamd.len = rlen
    if streamd.wblocked and (not streamd.size or streamd.len <= streamd.size) then 
      sched.signal(streamd.pipe_enable_signal)  -- unlock writers
    end
	else
		--return everything
		buff_data[1] = nil
		streamd.len = 0
    if streamd.wblocked then 
      sched.signal(streamd.pipe_enable_signal)  -- unlock writers
    end
	end
	
	return s
end

--- Read a line from a stream.
-- Will block if there is not a whole line to return, until it arrives. Also accessible as streamd:read_line()
-- @param streamd the the stream descriptor to read from.
-- @return  a string if data is available, _nil,'timeout'_ on timeout, _nil, 'closed', err_ if 
-- stream is closed and empty (_err_ is the additinal error parameter provided on @{write} when closing). 
-- The trailing newline is not included in the returned string.
M.read_line = function (streamd)
	local buff_data = streamd.buff_data

	local line_available, new_line_last
	for i=1, #buff_data do
		line_available, new_line_last = string.find (buff_data[i] , '\r?\n')
		if line_available then break end
	end
	if streamd.closed and not line_available then
		return nil, 'closed', streamd.closed
	end

	while not line_available do
    streamd.rblocked = true
		local ev = sched.wait(streamd.waitd_data)
    streamd.rblocked = false
		if not ev then return nil, 'timeout' end
		line_available, new_line_last = string.find (buff_data[#buff_data] or '', '\r?\n')
		if streamd.closed and not line_available then
			return nil, 'closed', streamd.closed
		end
	end

	if #buff_data > 1 then
		--slow path
		local s = table.concat(buff_data)
		streamd.buff_data = {[1] = s}
		buff_data = streamd.buff_data
		line_available, new_line_last = string.find(s, '\r?\n')  --TODO keep count of positions to avoid rescanning
	end
	
	local s = buff_data[1]
	local line = s:sub(1, line_available-1)
	local remainder_length = #s - new_line_last
	if remainder_length>0 then
		local remainder = s:sub(-remainder_length)
		buff_data[1] = remainder
		streamd.len = remainder_length
    if streamd.wblocked and (not streamd.size or streamd.len <= streamd.size) then 
      sched.signal(streamd.pipe_enable_signal)  -- unlock writers
    end
  else
		buff_data[1] = nil
		streamd.len = 0
    if streamd.wblocked then 
      sched.signal(streamd.pipe_enable_signal)  -- unlock writers
    end
  end
  
	return line
end

--- Write to a stream.
-- Will block when writing to a full stream. Also accessible as streamd:write(s ,err)
-- @param streamd the the stream descriptor to write to.
-- @param s the string to write to the stream. false or nil closes the stream.
-- @param err optional error message to register on stream closing.
-- @return _true_ on success, _nil,'timeout'_ on timeout, _nil, 'closed', err_ if 
-- stream is closed
M.write = function (streamd, s, err)
	if not s then --closing stream
		streamd.closed=err or true
    if streamd.rblocked then sched.signal(streamd.pipe_data_signal) end -- unlock readers
		return true
	end
	if streamd.closed then --closing stream
		return nil, 'closed', streamd.closed 
	end
	if streamd.size and streamd.len > streamd.size then
    streamd.wblocked = true
		local ev = sched.wait(streamd.waitd_enable)
    streamd.wblocked = false
		if not ev then return nil, 'timeout' end
	end
	streamd.buff_data[#streamd.buff_data+1] = s
	streamd.len = streamd.len + #s
  if streamd.rblocked then -- unlock readers
    sched.signal(streamd.pipe_data_signal) 
  end
	return true
end

--- Change the timeout settings.
-- Can be invoked as streamd:set\_timeout(read\_timeout, write\_timeout)
-- @param streamd the the stream descriptor to configure.
-- @param read_timeout timeout for blocking on stream reading operations. -1 or nil wait forever
-- @param write_timeout timeout for blocking on stream writing operations. -1 or nil wait forever
M.set_timeout = function (streamd, read_timeout, write_timeout)
	streamd.waitd_data.timeout = read_timeout
	streamd.waitd_enable.timeout = write_timeout
	if streamd.wblocked then sched.signal(streamd.pipe_enable_signal) end
	if streamd.rblocked then sched.signal(streamd.pipe_data_signal) end
end

local n_streams=0
--- Create a new stream.
-- @param size When the buffered string length surpases this value, following attempts to
-- write will block. nil means no limit.
-- @param read_timeout timeout for blocking on stream reading operations. -1 or nil wait forever
-- timeout
-- @param write_timeout timeout for blocking on stream writing operations. -1 or nil wait forever
-- @return a stream descriptor
M.new = function(size, read_timeout, write_timeout)
	n_streams=n_streams+1
	local pipename = 'stream: #'..tostring(n_streams)
	local streamd = setmetatable({
      set_timeout = M.set_timeout,
      read = M.read,
      read_line = M.read_line,
      write = M.write,
  }, {__tostring=function() return pipename end--[[,__index=M]]})
	log('STREAM', 'DETAIL', 'stream with name "%s" created', tostring(pipename))
	streamd.size=size
	streamd.pipe_enable_signal = {} --singleton event for pipe control
	streamd.pipe_data_signal = {} --singleton event for pipe data
	streamd.len = 0
  streamd.rblocked, streamd.wblocked = false, false
	streamd.buff_data = {}
	streamd.waitd_data = {
    streamd.pipe_data_signal,
		timeout=read_timeout, 
		--buff_mode='keep_first', 
	}
	streamd.waitd_enable = {
    streamd.pipe_enable_signal,
		timeout=write_timeout, 
		--buff_mode='keep_first', 
	}
	
	return streamd
end

return M

