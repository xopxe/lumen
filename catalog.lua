--- Task catalog operations.
-- The catalog is used to give tasks names, and then query them.
-- @module catalog
-- @usage local catalog = require 'catalog'
-- @alias M

local sched = require 'sched'
local log=require 'log'

--get locals for some useful things
local next, coroutine, setmetatable, tostring
	= next, coroutine, setmetatable, tostring

local M = {}

--register of names for tasks
--tasknames[co]=name
local tasknames = setmetatable({}, { __mode = 'v' })
local namestask = setmetatable({}, { __mode = 'kv' })

local register_events = setmetatable({}, {__mode = "kv"}) 
function get_register_event (name)
	if register_events[name] then return register_events[name]
	else
		local register_event = {}
		register_events[name] = register_event
		return register_event
	end
end

--- Register a name for the current task
-- @param name a name for the task
-- @return true is successful; nil, 'used' if the name is already used by another task.
M.register = function ( name )
	local co = coroutine.running()
	if tasknames[name] and tasknames[name] ~= co then
		return nil, 'used'
	end
	log('CATALOG', 'INFO', '%s registered in catalog as "%s"', tostring(co), tostring(name))
	tasknames[name] = co
	namestask[co] = name
	sched.signal(get_register_event (name))
	return true
end

--- Find task with a given name.
-- Can wait up to timeout until it appears.
-- @param name name of the task
-- @param timeout time to wait. nil or negative waits for ever.
-- @return the task if successful; on timeout expiration returns nil, 'timeout'.
M.waitfor = function ( name, timeout )
	local co = tasknames[name]
	log('CATALOG', 'INFO', 'catalog queried for name "%s", found %s', tostring(name), tostring(co))
	if co then
		return co
	else
		local emitter, event = sched.wait({emitter='*', timeout=timeout, events={get_register_event (name)}})
		if event then
			return emitter
		else
			return nil, 'timeout'
		end
	end
end

--- Find the name of a given task.
-- @param task to lookup.
-- @return the name if successful; If the task has not been given a name, returns nil.
M.namefor = function ( task )
	return namestask[task]
end

--- Iterator for registered tasks.
-- @return iterator
-- @usage for name, task in catalog.iterator() do
--	print(name, task)
--end
M.iterator = function ()
	return function (_, v) return next(tasknames, v) end
end

return M

