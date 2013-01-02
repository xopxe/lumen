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
-- @return  a string if data is available, _nil,'timeout'_ on timeout
M.read = function (streamd)
	local emitter = sched.wait(streamd.waitd_data)
	if not emitter then return nil, 'timeout' end
	local s = table.concat(streamd.buff_data)
	streamd.buff_data = {}
	streamd.len = 0
	sched.signal(streamd.pipe_enable_signal)
	return s
end

--- Write to a stream.
-- Will block when writing to a full stream. Also accessible as streamd:write(s)
-- @param streamd the the stream descriptor to write to.
-- @param s the string to write to the stream. 
-- @return _true_ on success, _nil,'timeout'_ on timeout
M.write = function (streamd, s)
	if streamd.size and streamd.len > streamd.size then
		local emitter = sched.wait(streamd.waitd_enable)
		if not emitter then return nil, 'timeout' end
	end
	streamd.buff_data[#streamd.buff_data+1] = s
	streamd.len = streamd.len + #s
	sched.signal(streamd.pipe_data_signal) 
	return true
end

local n_streams=0
--- Create a new stream.
-- @param size When the buffered string length surpases this value, follwing attempts to
-- write will block. nil means no limit.
-- @param timeout timeout for blocking on stream operations. -1 or nil disable
-- timeout
-- @return a stream descriptor
M.new = function(size, timeout)
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
		timeout=timeout, 
		buff_mode='drop_last', 
		events = {streamd.pipe_data_signal}, 
		buff =queue:new(),
	})
	streamd.waitd_enable = sched.new_waitd({
		emitter='*', 
		buff_len=1, 
		timeout=timeout, 
		buff_mode='drop_last', 
		events = {streamd.pipe_enable_signal}, 
		buff = queue:new(),
	})
	
	return streamd
end

return M

