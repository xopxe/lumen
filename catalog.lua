--- A general purpose Catalog.
-- The catalog is used to give objects well known names for sharing purposes. 
-- It also allows synchronization, by blocking the requester until the object
-- is made available. Catalogs themselves are made available under a Well Known
-- Name. Typical catalogs are "tasks", "events", "mutexes" and "pipes".  
-- A name is associated to a single object, and an object has a single name.
-- Catalogs can be strong or weak, ie, they can keep objects from being garbage collected, or not.
-- @module catalog
-- @usage local tasks = require 'lumen.catalog'.get_catalog('tasks')
--...
--tasks:register('a task', sched.running_task)
--...
--local a_task=tasks:waitfor('a task')
-- @alias M

local sched = require 'lumen.sched'
local log = require 'lumen.log'

--get locals for some useful things
local next,  setmetatable, tostring = next,  setmetatable, tostring

local M = {}

local catalogs = {}

local register_events = setmetatable({}, {__mode = 'k'}) 

-- Creates a and queries singleton event for each queried name in a catalog, 
-- to be used to wake tasks waiting for it to appear.
local function get_register_event (catalogd, name)
	if register_events[catalogd] and register_events[catalogd][name] then 
		return register_events[catalogd][name]
	else
		local register_event = setmetatable({}, {
			--__tostring=function() return 'signal: register$'..tostring(catalogd.name)..'/'..tostring(name) end,
		})
		register_events[catalogd] = register_events[catalogd] or {}
		register_events[catalogd][name] = register_event
		return register_event
	end
end

--- Give a name to an object.
-- @param catalogd the catalog to use.
-- @param name a name for the object.
-- @param object the object to name.
-- @param force forces the renaming of the object if already present.
-- @return _true_ is successful; _nil, 'used'_ if the name is already used by another object; _nil, 'present'_ if the object 
-- is already in the catalog under a different name, and forcing is not enabled.
M.register = function ( catalogd, name, object, force )
	local direct = catalogd.direct
	if direct[name] and direct[name] ~= object then
		return nil, 'used'
	end
	local reverse = catalogd.reverse
	if not force and reverse[object] and reverse[object]~= name then
		return nil, 'present'
	end
	log('CATALOG', 'DETAIL', '%s registered in catalog %s as "%s"', 
		tostring(object), tostring(catalogd), tostring(name))
	direct[name] = object
	reverse[object] = name
	
	sched.signal(get_register_event(catalogd, name))
	return true
end

--- Removes an entry from the catalog.
-- @param catalogd the catalog to use.
-- @param name a name for the object.
-- @return _true_ on success, or _nil, 'missing'_ if the name was not registered previously.
M.unregister = function ( catalogd, name )
	local object = catalogd.direct[name]
	if not object then
		return nil, 'missing'
	end
	log('CATALOG', 'DETAIL', '%s unregistered in catalog %s as "%s"', 
		tostring(object), tostring(catalogd), tostring(name))
	catalogd.direct[name] = nil
	catalogd.reverse[object] = nil
	return true
end

--- Retrieve a object with a given name.
-- Can wait up to timeout until it appears.
-- @param catalogd the catalog to use.
-- @param name name of the object
-- @param timeout time to wait. nil or negative waits for ever.
-- @return the object if successful; on timeout expiration returns nil, 'timeout'.
M.waitfor = function ( catalogd, name, timeout )
	local object = catalogd.direct[name]
	log('CATALOG', 'DEBUG', 'catalog %s queried for name "%s", found %s', tostring(catalogd.name), tostring(name), tostring(object))
	if object then
		return object
	else
		local event = sched.wait({
      get_register_event(catalogd, name),
			timeout=timeout, 
		})
		if event then
			return catalogd.direct[name]
		else
			return nil, 'timeout'
		end
	end
end

--- Find the name of a given object.
-- @param catalogd the catalog to use.
-- @param object the object to lookup.
-- @return the object if successful; If the object has not been given a name, returns nil.
M.namefor = function ( catalogd, object )
	local name = catalogd.reverse[object]
	log('CATALOG', 'DEBUG', 'catalog queried for object %s, found name "%s"', tostring(object), tostring(name))
	return name 
end

--- Retrieve a catalog.
-- Catalogs are created on demand.
-- @param name the name of the catalog.
-- @param strong if true catalog will hold a reference to the object and avoid it from being garbage collected.
-- @return a catalog object.
M.get_catalog = function (name, strong)
	if catalogs[name] then 
		return catalogs[name] 
	else
		local catalogd = setmetatable(
			{ direct = {}, reverse = {}, name=name}, 
			{__index=M}
		)
    if not strong then 
			setmetatable( catalogd.direct,{__mode = 'kv'} )
			setmetatable( catalogd.reverse,{__mode = 'kv'} )
    end
		catalogs[name] = catalogd
		return catalogd
	end
end


--- Iterator for registered objects.
-- @param catalogd the catalog to use.
-- @return Iterator function
-- @usage local tasks = require 'lumen.catalog'.get_catalog('tasks')
--for name, task in tasks:iterator() do
--	print(name, task)
--end
M.iterator = function (catalogd)
	return function (_, v) return next(catalogd.direct, v) end
end

return M

