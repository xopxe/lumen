--- A general purpose Catalog.
-- The catalog is used to give objects well known names for sharing purposes. 
-- It also allows synchronization, by blocking the requester until the object
-- is made available. Catalogs themselves are made available under a Well Known
-- name. Typical catalogs are "tasks", "events", "mutexes" and "pipes".
-- The catalog does not check for multiple names per object.
-- @module catalog
-- @usage local tasks = require 'catalog'.get_catalog('tasks')
--...
--tasks:register('a task', sched.running_task)
--...
--local a_task=tasks:waitfor('a task')
-- @alias M

local sched = require 'sched'
local log=require 'log'

--get locals for some useful things
local next,  setmetatable, tostring, getmetatable
	= next,  setmetatable, tostring, getmetatable

local M = {}

local catalogs = {}

local register_events = {} -- setmetatable({}, {__mode = "kv"}) 

-- Creates a and queries singleton event for each queried name in a catalog, 
-- to be used to wake tasks waiting for it to appear.
local function get_register_event (catalogd, name)
	if register_events[catalogd] and register_events[catalogd][name] then 
		return register_events[catalogd][name]
	else
		local register_event = setmetatable({}, {
			__tostring=function() return 'signal: register$'..tostring(getmetatable(catalogd).name)..'/'..tostring(name) end,
		})
		register_events[catalogd] = register_events[catalogd] or {}
		register_events[catalogd][name] = register_event
		return register_event
	end
end

--- Register a name to a object.
-- @param catalogd the catalog to use.
-- @param name a name for the object
-- @param object the object to name.
-- @return true is successful; nil, 'used' if the name is already used by another object.
M.register = function ( catalogd, name, object )
	if catalogd[name] and catalogd[name] ~= object then
		return nil, 'used'
	end
	log('CATALOG', 'INFO', '%s registered in catalog %s as "%s"', 
		tostring(object), tostring(catalogd), tostring(name))
	catalogd[name] = object
	sched.signal(get_register_event(catalogd, name))
	return true
end

--- Retrieve a object with a given name.
-- Can wait up to timeout until it appears.
-- @param catalogd the catalog to use.
-- @param name name of the object
-- @param timeout time to wait. nil or negative waits for ever.
-- @return the object if successful; on timeout expiration returns nil, 'timeout'.
M.waitfor = function ( catalogd, name, timeout )
	local object = catalogd[name]
	log('CATALOG', 'INFO', 'catalog %s queried for name "%s", found %s', tostring(catalogd), tostring(name), tostring(object))
	if object then
		return object
	else
		local emitter, event = sched.wait({
			emitter='*', 
			timeout=timeout, 
			events={get_register_event(catalogd, name)}
		})
		if event then
			return catalogd[name]
		else
			return nil, 'timeout'
		end
	end
end

--- Find the name of a given object.
-- This does a linear search trough the catalog.
-- @param catalogd the catalog to use.
-- @param object the object to lookup.
-- @return the object if successful; If the object has not been given a name, returns nil.
M.namefor = function ( catalogd, object )
	for k, v in pairs(catalogd) do 
		if v==object then 
			log('CATALOG', 'INFO', 'catalog queried for object %s, found name "%s"', tostring(object), tostring(k))
			return k 
		end
	end
	log('CATALOG', 'INFO', 'catalog queried for object %s, name not found.', tostring(object))
end

--- Retrieve a catalog.
-- Catalogs are created on demand
-- @param name the name of the catalog.
M.get_catalog = function (name)
	if catalogs[name] then 
		return catalogs[name] 
	else
		local catalogd = setmetatable({}, { __mode = 'kv', __index=M, name=name})
		catalogs[name] = catalogd
		return catalogd
	end
end


--- Iterator for registered objects.
-- @param catalogd the catalog to use.
-- @return iterator
-- @usage local tasks = require 'catalog'.get_catalog('tasks')
--for name, task in tasks:iterator() do
--	print(name, task)
--end
M.iterator = function (catalogd)
	return function (_, v) return next(catalogd, v) end
end

return M

