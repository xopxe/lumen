--- String streams.
-- Streams are similar to @{pipes}, but specialized for strings. They serve
-- the same purpose as LTN12, i.e. typically processing input from a socket.
-- @module stream
-- @usage local stream = require 'lumen.stream'
-- @alias M

local sched    = require 'lumen.sched'
local log      = require 'lumen.log'
--local queue=require 'lumen.lib.queue'

--get locals for some useful things
local tostring = tostring
local tonumber = tonumber
local t_concat = table.concat
local s_find   = string.find


local M = {}

-- Remove the first n bytes from the stream and return them (everything if n is
-- nil), unlocking writers if there is room. The buffer table is always replaced,
-- so a reader that sees the same table knows nothing was consumed meanwhile.
local function take(streamd, n)
	local buff_data = streamd.buff_data
	local s = buff_data[1]
	if #buff_data > 1 then
		--slow path
		s = t_concat(buff_data)
	end
	local rest
	if n and n < #s then
		rest = s:sub(n + 1)
		s = s:sub(1, n)
	end
	streamd.buff_data = { rest }
	streamd.len = rest and #rest or 0
	if streamd.wblocked > 0 and (not streamd.size or streamd.len <= streamd.size) then
		sched.signal(streamd.pipe_enable_signal) -- unlock writers
	end
	return s
end

--- Read from a stream.
-- Will block if there is no (or not enough) data to read, until it appears. Also accessible as streamd:read([len])
-- @param streamd the the stream descriptor to read from.
-- @param length optional length of string to be returned.
-- @return  a string if data is available, _nil,'timeout'_ on timeout, _nil, 'closed', err_ if
-- stream is closed and has not enough data (_err_ is the additinal error parameter provided on
-- @{close}). Data left in a closed stream can still be retrieved with read().
M.read          = function(streamd, length)
	if length == 0 then return '' end
	length = tonumber(length) or -1

	while streamd.len == 0 or (length > 0 and streamd.len < length) do
		if streamd.closed then
			return nil, 'closed', streamd.closed
		end
		streamd.rblocked = streamd.rblocked + 1
		local ev = sched.wait(streamd.waitd_data)
		streamd.rblocked = streamd.rblocked - 1
		if not ev then return nil, 'timeout' end
	end

	return take(streamd, length > 0 and length or nil)
end

--- Read a line from a stream.
-- Will block if there is not a whole line to return, until it arrives. Also accessible as streamd:read_line()
-- @param streamd the the stream descriptor to read from.
-- @return  a string if data is available, _nil,'timeout'_ on timeout, _nil, 'closed', err, partial_ if
-- stream is closed and has no whole line (_err_ is the additinal error parameter provided on
-- @{close}). _partial_ is the last unterminated line, or nil if there is none;
-- The trailing newline is not included in the returned string.
M.read_line     = function(streamd)
	local buff_data, scanned -- chunks of buff_data already searched for a newline
	local line_available, new_line_last
	while true do
		if streamd.buff_data ~= buff_data then
			-- first pass, or another reader consumed data: scan from the start
			buff_data, scanned = streamd.buff_data, 0
		end
		for i = scanned + 1, #buff_data do
			line_available, new_line_last = s_find(buff_data[i], '\r?\n')
			if line_available then break end
		end
		if line_available then break end
		scanned = #buff_data
		if streamd.closed then
			-- no newline will ever arrive: hand out what is left
			local partial = streamd.len > 0 and take(streamd) or nil
			return nil, 'closed', streamd.closed, partial
		end
		streamd.rblocked = streamd.rblocked + 1
		local ev = sched.wait(streamd.waitd_data)
		streamd.rblocked = streamd.rblocked - 1
		if not ev then return nil, 'timeout' end
	end

	if #buff_data > 1 then
		--slow path
		local s = t_concat(buff_data)
		streamd.buff_data = { [1] = s }
		line_available, new_line_last = s_find(s, '\r?\n')
	end

	return take(streamd, new_line_last):sub(1, line_available - 1)
end

--- Write to a stream.
-- Will block when writing to a full stream. Also accessible as streamd:write(s ,err)
-- @param streamd the the stream descriptor to write to.
-- @param s the string to write to the stream. false or nil closes the stream, as
-- @{close}(streamd, err) does.
-- @param err optional error message to register on stream closing.
-- @return _true_ on success, _nil,'timeout'_ on timeout, _nil, 'closed', err_ if
-- stream is closed
M.write         = function(streamd, s, err)
	if not s then --closing stream
		return M.close(streamd, err)
	end
	if streamd.closed then --closing stream
		return nil, 'closed', streamd.closed
	end
	while streamd.size and streamd.len > streamd.size do
		streamd.wblocked = streamd.wblocked + 1
		local ev = sched.wait(streamd.waitd_enable)
		streamd.wblocked = streamd.wblocked - 1
		if not ev then return nil, 'timeout' end
		if streamd.closed then
			return nil, 'closed', streamd.closed
		end
	end
	streamd.buff_data[#streamd.buff_data + 1] = s
	streamd.len = streamd.len + #s
	if streamd.rblocked > 0 then -- unlock readers
		sched.signal(streamd.pipe_data_signal)
	end
	return true
end

--- Close a stream.
-- Blocked readers and writers are woken up. Data left in the stream can still
-- be read; after that, reads return _nil, 'closed', err_. Closing an already
-- closed stream does nothing, so the first error is kept. Also accessible as
-- streamd:close([err])
-- @param streamd the stream descriptor to close.
-- @param err optional error message, returned by following reads and writes
-- (defaults to true).
-- @return _true_
M.close         = function(streamd, err)
	if streamd.closed then return true end
	streamd.closed = err or true
	if streamd.rblocked > 0 then -- unlock readers
		sched.signal(streamd.pipe_data_signal)
	end
	if streamd.wblocked > 0 then -- unlock writers, so they fail
		sched.signal(streamd.pipe_enable_signal)
	end
	return true
end

--- Change the timeout settings.
-- Can be invoked as streamd:set\_timeout(read\_timeout, write\_timeout)
-- @param streamd the the stream descriptor to configure.
-- @param read_timeout timeout for blocking on stream reading operations. -1 or nil wait forever
-- @param write_timeout timeout for blocking on stream writing operations. -1 or nil wait forever
M.set_timeout   = function(streamd, read_timeout, write_timeout)
	streamd.waitd_data.timeout = read_timeout
	streamd.waitd_enable.timeout = write_timeout
	if streamd.wblocked > 0 then sched.signal(streamd.pipe_enable_signal) end
	if streamd.rblocked > 0 then sched.signal(streamd.pipe_data_signal) end
end

local n_streams = 0
--- Create a new stream.
-- @param size When the buffered string length surpases this value, following attempts to
-- write will block. nil means no limit.
-- @param read_timeout timeout for blocking on stream reading operations. -1 or nil wait forever
-- timeout
-- @param write_timeout timeout for blocking on stream writing operations. -1 or nil wait forever
-- @return a stream descriptor
M.new           = function(size, read_timeout, write_timeout)
	n_streams = n_streams + 1
	local pipename = 'stream: #' .. tostring(n_streams)
	local streamd = setmetatable({
		set_timeout = M.set_timeout,
		read = M.read,
		read_line = M.read_line,
		write = M.write,
		close = M.close,
	}, { __tostring = function() return pipename end --[[,__index=M]] })
	log('STREAM', 'DETAIL', 'stream with name "%s" created', tostring(pipename))
	streamd.size = size
	streamd.pipe_enable_signal = {}        --singleton event for pipe control
	streamd.pipe_data_signal = {}          --singleton event for pipe data
	streamd.len = 0
	streamd.rblocked, streamd.wblocked = 0, 0 -- number of blocked readers and writers
	streamd.buff_data = {}
	streamd.waitd_data = {
		streamd.pipe_data_signal,
		timeout = read_timeout,
		--buff_mode='keep_first',
	}
	streamd.waitd_enable = {
		streamd.pipe_enable_signal,
		timeout = write_timeout,
		--buff_mode='keep_first',
	}

	return streamd
end

return M
