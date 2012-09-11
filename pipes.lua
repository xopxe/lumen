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

--- Read from a pipe.
-- Will block on a empty pipe. Also accessible as piped:read()
-- @param piped the the pipe descriptor to read from.
-- @return  _true,..._ if data is available, _nil,'timeout'_ on timeout
M.read = function (piped)
	local function format_signal(emitter, ev, ...)
		if not emitter then return nil, 'timeout' end
		return ...
	end
	if piped.buff_data:len() == piped.size-1 then
		sched.signal(piped.pipe_enable_signal)
	end
	return true, format_signal(sched.wait(piped.waitd_data))
end

--- Write to a pipe.
-- Will block when writing to a full pipe. Also accessible as piped:write()
-- @param piped the the pipe descriptor to write to.
-- @param ... elements to write to pipe. All params are stored as a single entry.
-- @return _true_ on success, _nil,'timeout'_ on timeout
M.write = function (piped, ...)
	if piped.buff_data:len() >= piped.size then
		local emitter, _, _ = sched.wait(piped.waitd_enable)
		if not emitter then return nil, 'timeout' end
	end
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
-- @param size maximum number of signals in the pipe
-- @param timeout timeout for blocking on pipe operations. -1 or nil disable
-- timeout
-- @return a pipe descriptor on success, or _nil,'exists'_ if a pipe
-- with the given name already exists
local n_pipes=0
M.new = function(size, timeout)
	n_pipes=n_pipes+1
	local pipename = 'pipe: #'..tostring(n_pipes)
	local piped = setmetatable({}, {__tostring=function() return pipename end})
	log('PIPES', 'INFO', 'pipe with name "%s" created', tostring(pipename))
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
	
	return piped
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

