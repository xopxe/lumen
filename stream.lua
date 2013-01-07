--- String streams.
-- Streams are similar to @{pipes}, but specialized for strings. They serve
-- the same purpose as LTN12, i.e. typically processing input from a socket.
-- @module stream
-- @usage local stream = require 'stream'
-- @alias M

local sched = require 'sched'
local log=require 'log'
local queue=require 'lib/queue'

--get locals for some useful things
local setmetatable, tostring = setmetatable, tostring


local M = {}

--- Read from a stream.
-- Will block if there is no data to read, until it appears. Also accessible as streamd:read()
-- @param streamd the the stream descriptor to read from.
-- @return  a string if data is available, _nil,'timeout'_ on timeout, _nil, 'closed', err_ if 
-- stream is closed and empty (_err_ is the additinal error parameter provided on @{write}).
M.read = function (streamd)
	if streamd.closed and #streamd.buff_data == 0 then
		return nil, 'closed', streamd.closed
	end
	local emitter = sched.wait(streamd.waitd_data)
	if not emitter then return nil, 'timeout' end
	local s
	local buff_data = streamd.buff_data
	if #buff_data == 1 then 
		--fast path
		s = buff_data[1]
		buff_data[1] = nil
	else
		--slow path
		s = table.concat(buff_data)
		streamd.buff_data = {}
	end
	streamd.len = 0
	sched.signal(streamd.pipe_enable_signal)
	return s
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
		return true
	end
	if streamd.closed then --closing stream
		return nil, 'closed', streamd.closed 
	end
	if streamd.size and streamd.len > streamd.size then
		local emitter = sched.wait(streamd.waitd_enable)
		if not emitter then return nil, 'timeout' end
	end
	streamd.buff_data[#streamd.buff_data+1] = s
	streamd.len = streamd.len + #s
	sched.signal(streamd.pipe_data_signal) 
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
	
	--force unlock so new timeouts get applied.
	sched.signal(streamd.pipe_enable_signal)
	sched.signal(streamd.pipe_data_signal)
end

local n_streams=0
--- Create a new stream.
-- @param size When the buffered string length surpases this value, follwing attempts to
-- write will block. nil means no limit.
-- @param read_timeout timeout for blocking on stream reading operations. -1 or nil wait forever
-- timeout
-- @param write_timeout timeout for blocking on stream writing operations. -1 or nil wait forever
-- @return a stream descriptor
M.new = function(size, read_timeout, write_timeout)
	n_streams=n_streams+1
	local pipename = 'pipe: #'..tostring(n_streams)
	local streamd = setmetatable({}, {__tostring=function() return pipename end, __index=M})
	log('PIPES', 'INFO', 'pipe with name "%s" created', tostring(pipename))
	streamd.size=size
	streamd.pipe_enable_signal = {} --singleton event for pipe control
	streamd.pipe_data_signal = {} --singleton event for pipe data
	streamd.len = 0
	streamd.buff_data = {}
	streamd.waitd_data = sched.new_waitd({
		emitter='*', 
		buff_len=1, 
		timeout=read_timeout, 
		buff_mode='drop_last', 
		events = {streamd.pipe_data_signal}, 
		buff =queue:new(),
	})
	streamd.waitd_enable = sched.new_waitd({
		emitter='*', 
		buff_len=1, 
		timeout=write_timeout, 
		buff_mode='drop_last', 
		events = {streamd.pipe_enable_signal}, 
		buff = queue:new(),
	})
	
	return streamd
end

return M

