--- Mutex operations.
-- mutexes are used to ensure portions of code are accessed by a single
-- task at a time. The module is a function that will return a new 
-- mutex object (see @{mutexd}) when invoked.
-- @module mutex
-- @usage local mutex = require 'mutex'()
--
--local function critical()
--  mutex.acquire()
--  ...
--  mutex.release()
--end
--
--local critical = mutex.synchronize(function() ... end) --other method
-- @alias M

local sched=require 'sched'
local log=require 'log'

table.pack=table.pack or function (...)
	return {n=select('#',...),...}
end

--get locals for some useful things
local coroutine, setmetatable = coroutine, setmetatable

local waitd_locks = setmetatable({}, {__mode = "kv"}) 

local n_mutex=0

local M = function()
	n_mutex=n_mutex+1
	local m = setmetatable({}, {__tostring=function() return 'MUTEX#'..n_mutex end})

	local event_release = {}
	local events_release = {event_release, sched.EVENT_DIE}
	local function get_waitd_lock (task) --memoize waitds
		if waitd_locks[task] then return waitd_locks[task] 
		else
			local waitd = {emitter=task, events=events_release}
			waitd_locks[task] = waitd
			return waitd
		end
	end
	
	m.acquire = function()
		if m.locker and coroutine.status(m.locker)~='dead' then 
			sched.wait(get_waitd_lock (m.locker))
		end
		local co = coroutine.running()
		m.locker = co
		log('MUTEX', 'DETAIL', '%s locked %s', tostring(co), tostring(m))
	end
	
	m.release = function()
		if coroutine.running()~=m.locker then
			error('Attempt to release a non-acquired lock')
		end
		log('MUTEX', 'DETAIL', '%s released %s', tostring(m.locker), tostring(m))
		m.locker = nil
		sched.signal(event_release)
	end

	m.synchronize = function (f)
		local wrapper = function(...)
			m.acquire()
			local ret = table.pack(f(...))
			m.release()
			return unpack(ret,1, ret.n)
		end
		log('MUTEX', 'INFO', '%s synchronized on mutex %s as %s'
			, tostring(f), tostring(m), tostring(wrapper))
		return wrapper
	end
	
	return m
end

------
-- Mutex object.
-- mutexes are used to ensure portions of code are accessed by a single
-- task at a time. Said portions are called "critical sections", and are delimited by
-- a lock acquisition at the beginning, and a lock release at the end. Only one task can acquire
-- a lock at a time, so there is only one task inside the critical section at a time.
-- @field acquire acquires a lock. If the lock is already acquired, will block until the task that 
-- holds it releases the lock or finshes
-- @field release releases the lock. A task can only release a lock it acquired before, otherwise a
-- error is triggered.
-- @field synchronize  a helper that takes a function, a returns a wrapper that is locked with 
-- the mutex.
-- @table mutexd

return M

