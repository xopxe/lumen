--- Mutex operations.
-- Mutexes are used to ensure portions of code are accessed by a single
-- task at a time. Said portions are called "critical sections", and are delimited by
-- a lock acquisition at the beginning, and a lock release at the end. Only one task can acquire
-- a lock at a time, so there is only one task inside the critical section at a time.
-- Notice that Lumen being a cooperative scheduler, it will never preempt
-- control from a task. Thus mutexes can be needed only if the fragment of code 
-- being locked contains a call that explicitly relinquish control, such as 
-- sched.sleep(), sched.signal() or sched.wait().
-- @module mutex
-- @usage local mutex = require 'lumen.mutex'
--local mx = mutex.new()
--
--local function critical()
--  mx:acquire()
--  ...
--  mx:release()
--end
--
--local critical = mx:synchronize(function() ... end) --other method
-- @alias M

local sched=require 'lumen.sched'
local log=require 'lumen.log'

local unpack = unpack or table.unpack

table.pack = table.pack or function (...)
	return {n=select('#',...),...}
end

--get locals for some useful things
local setmetatable = setmetatable

local waitd_locks = setmetatable({}, {__mode = "kv"}) 

local n_mutex=0

local M = {}

--memoize waitds that wait for a unlock signal from a certain task
local function get_waitd_lock (taskd) 
	if waitd_locks[taskd] then return waitd_locks[taskd] 
	else
		local waitd = {{}, taskd.EVENT_DIE, taskd.EVENT_FINISH} --all the events that can release a lock
		waitd_locks[taskd] = waitd
		return waitd
	end
end

--- Create a new mutex.
-- @return a mutexd object.
M.new = function()
	n_mutex = n_mutex+1
	local mutex_name = 'mutex #'..n_mutex
	local m = setmetatable({}, {
		__tostring=function() return mutex_name end, 
		__index = M,
	})
	return m
end

--- Acquire a lock.
-- If the lock is already acquired, this call will block until the task that 
-- holds it releases the lock or finishes. Can be invoked in OO fashion 
-- as _mutexd:acquire()_.
-- @param mutexd a mutexd object.
M.acquire = function(mutexd)
	while mutexd.locker and mutexd.locker.status~='dead' do
		sched.wait(get_waitd_lock (mutexd.locker))
	end
	mutexd.locker = sched.running_task
	log('MUTEX', 'DEBUG', '%s locked %s', tostring(mutexd.locker), tostring(mutexd))
end

--- Releases a lock.
-- A task can only release a lock it acquired before, otherwise a
-- error is triggered. If a task finishes or is killed, all locks it held will be released automatically.
-- Can be invoked in OO fashion as _mutexd:release()_.
-- @param mutexd a mutexd object.
M.release = function(mutexd)
	if sched.running_task~=mutexd.locker then
		error('Attempt to release a non-acquired lock')
	end
	log('MUTEX', 'DEBUG', '%s released %s', tostring(mutexd.locker), tostring(mutexd))
	mutexd.locker = nil
	sched.signal( get_waitd_lock (sched.running_task)[1] )
end

--- Generate a synchronizzed version of a function.
-- This is a helper that takes a function, and returns a wrapper that is locked with 
-- the mutex.
-- Can be invoked in OO fashion as _mutexd:synchronize(f)_.
-- @param mutexd a mutexd object.
-- @param f function to be locked.
M.synchronize = function (mutexd, f)
	local wrapper = function(...)
		mutexd:acquire()
		local ret = table.pack(f(...))
		mutexd:release()
		return unpack(ret,1, ret.n)
	end
	log('MUTEX', 'DETAIL', '%s synchronized on mutex %s as %s'
		, tostring(f), tostring(mutexd), tostring(wrapper))
	return wrapper
end

return M

