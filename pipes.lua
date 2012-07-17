--- Named pipes.
-- Pipes allow can be used to communicate tasks. Unlike plain signals,
-- no message can get lost: writers get blocked when the pipe is full
-- @module pipes
-- @usage local pipes = require 'pipes'
-- @alias M

local sched = require 'sched'
local log=require 'log'
local queue=require 'lib/queue'

--get locals for some useful things
local next, setmetatable, tostring
	= next, setmetatable, tostring


local M = {}


------
-- Pipe descriptor.
-- A named pipe.
-- @field write writes to the pipe. Will block when writing to a full pipe.
-- Return true on success, nil, 'timeout' on timeout
-- @field read reads from the pipe. Will block on a empty pipe.
-- Return data if available, nil, 'timeout' on timeout
-- @table piped

--register of pipes
local pipes =  setmetatable({}, { __mode = 'kv' })

local register_events = setmetatable({}, {__mode = "kv"}) 
function get_register_event (name)
	if register_events[name] then return register_events[name]
	else
		local register_event = {}
		register_events[name] = register_event
		return register_event
	end
end

--- Create a new pipe.
-- @param name a name for the pipe
-- @param size maximum number of signals in the pipe
-- @param timeout timeout for blocking on pipe operations. -1 or nil disable
-- timeout
-- @return the pipe descriptor (see @{piped}) on success, or nil,'exists' if a pipe
-- with the given name already exists
M.new = function(name, size, timeout)
	if pipes[name] then
		return nil, 'exists'
	end
	log('PIPES', 'INFO', 'pipe with name "%s" created', tostring(name))
	local piped = {}
	local pipe_enable = {} --singleton event for pipe control
	local pipe_data = {} --singleton event for pipe data
	local buff_data = queue:new()
	local waitd_data={emitter='*', buff_len=size+1, timeout=timeout, events = {pipe_data}, buff = buff_data}
	local waitd_enable={emitter='*', buff_len=1, timeout=timeout, buff_mode='drop_last', events = {pipe_enable}, buff = queue:new()}
	local piped_read = function ()
		local function format_signal(emitter, ev, ...)
			if not emitter then return nil, 'timeout' end
			return ...
		end
		if buff_data:len() == size-1 then
			sched.signal(pipe_enable)
		end
		return format_signal(sched.wait(waitd_data))
	end
	local piped_write = function (...)
		if buff_data:len() >= size then
			local emitter, _, _ = sched.wait(waitd_enable)
			if not emitter then return nil, 'timeout' end
		end
		sched.signal(pipe_data, ...) --table.pack(...))
		return true
	end
	--first run is a initialization, replaces functions with proper code
	piped.read = function ()
		piped.read = piped_read
		piped.write = piped_write
		sched.signal(pipe_enable)
		return piped_read()
	end
	--blocks on no-readers, replaced in piped.read
	piped.write = function (...)
		local emitter, _, _ = sched.wait(waitd_enable)
		if not emitter then return nil, 'timeout' end
		sched.signal(pipe_data, ...)
		return true
	end
	piped.len=function ()
		return buff_data:len()
	end
	
	pipes[name]=piped
	sched.wait_feed(waitd_data)
	sched.signal(get_register_event (name), piped)
	--emit_signal(PIPES_EV, name, 'created', piped)
	return piped
end

--- Look for a pipe with the given name.
-- Can wait up to timeout until it appears.
-- @param name of the pipe to get
-- @param timeout max. time time to wait. -1 or nil disables timeout.
M.waitfor = function(name, timeout)
	local piped = pipes[name]
	log('PIPES', 'INFO', 'a pipe with name "%s" requested, found %s', tostring(name), tostring(piped))
	if piped then
		return piped
	else
		local _, event, received_piped= sched.wait({emitter='*', timeout=timeout, events={get_register_event (name)}})
		if event == 'created' then
			return received_piped
		else
			return nil, 'timeout'
		end
	end
end

--- Iterator for all pipes.
-- @return iterator
-- @usage for name, pipe in pipes.iterator() do
--	print(name, pipe)
--end
M.iterator = function ()
	return function (_, v) return next(pipes, v) end
end


return M

