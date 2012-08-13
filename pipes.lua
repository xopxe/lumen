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

local piped_read = function (self)
	local function format_signal(emitter, ev, ...)
		if not emitter then return nil, 'timeout' end
		return ...
	end
	if self.buff_data:len() == self.size-1 then
		sched.signal(self.pipe_enable_signal)
	end
	return format_signal(sched.wait(self.waitd_data))
end

local piped_write = function (self, ...)
	if self.buff_data:len() >= self.size then
		local emitter, _, _ = sched.wait(self.waitd_enable)
		if not emitter then return nil, 'timeout' end
	end
	sched.signal(self.pipe_data_signal, ...) 
	return true
end

--- Read from a pipe.
-- Will block on a empty pipe. Also accessible as piped:read()
-- @param piped the the pipe descriptor to read from.
-- @return  data if available, nil, 'timeout' on timeout
M.read = function (piped)
	--first run is a initialization, replaces functions with proper code
	piped.read = piped_read
	piped.write = piped_write
	sched.signal(piped.pipe_enable_signal)
	return piped_read(piped)
end

--- Write to a pipe.
-- Will block when writing to a full pipe. Also accessible as piped:write()
-- @param piped the the pipe descriptor to write to.
-- @param ... elements to write to pipe. All params are stored as a single entry.
-- @return true on success, nil, 'timeout' on timeout
M.write = function (piped, ...)
	--blocks on no-readers, replaced in piped.read
	local emitter, _, _ = sched.wait(piped.waitd_enable)
	if not emitter then return nil, 'timeout' end
	sched.signal(piped.pipe_data_signal, ...)
	return true
end

--- Number of entries in a pipe.
-- Also accessible as piped:len()
-- @param piped the the pipe descriptor.
-- @return number of entries
M.len = function (piped)
	return piped.buff_data:len()
end


--- Create a new pipe.
-- @param name a name for the pipe
-- @param size maximum number of signals in the pipe
-- @param timeout timeout for blocking on pipe operations. -1 or nil disable
-- timeout
-- @return a pipe descriptor on success, or nil,'exists' if a pipe
-- with the given name already exists
M.new = function(name, size, timeout)
	if pipes[name] then
		return nil, 'exists'
	end
	log('PIPES', 'INFO', 'pipe with name "%s" created', tostring(name))
	local piped = setmetatable({}, {__tostring=function() return 'PIPE:'..tostring(name) end})
	piped.size=size
	piped.pipe_enable_signal = {} --singleton event for pipe control
	piped.pipe_data_signal = {} --singleton event for pipe data
	piped.buff_data = queue:new()
	piped.waitd_data = sched.new_waitd({
		emitter='*', 
		buff_len=size+1, 
		timeout=timeout, 
		events = {piped.pipe_data_signal}, 
		buff = piped.buff_data,
	})
	piped.waitd_enable = sched.new_waitd({
		emitter='*', 
		buff_len=1, 
		timeout=timeout, 
		buff_mode='drop_last', 
		events = {piped.pipe_enable_signal}, 
		buff = queue:new(),
	})

	piped.read = M.read
	piped.write = M.write
	piped.len=M.len
	
	pipes[name]=piped
	--sched.wait_feed(piped.waitd_data)
	sched.signal(get_register_event (name), piped)
	--emit_signal(PIPES_EV, name, 'created', piped)
	return piped
end

--- Look for a pipe with the given name.
-- Can wait up to timeout until it appears.
-- @param name of the pipe to get
-- @param timeout max. time time to wait. -1 or nil disables timeout.
-- @return a pipe descriptor with the given name, or nil, 'timeout' on timeout
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

