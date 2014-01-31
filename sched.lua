--- Lumen cooperative scheduler.
-- Lumen (Lua Multitasking Environment) is a simple environment 
-- for coroutine based multitasking. Consists of a signal scheduler, 
-- and that's it.
-- @module sched
-- @usage local sched = require 'lumen.sched'
-- sched.sigrun({'a signal'}, print)
-- local task=sched.run(function()
--   sched.signal('a signal', 'data')
--   sched.sleep(1)
-- end)
-- @alias M
local lsleep = require'lsleep'
local ls_sleep = lsleep.sleep
local log=require 'lumen.log'
local queue3 = require 'lumen.lib.queue3'
local weak_key = {__mode='k'}
local weak_value = {__mode='v'}
local weak_keyvalue = {__mode='kv'}
local setmetatable, coroutine, type, tostring, select, pairs, unpack, assert, next =
      setmetatable, coroutine, type, tostring, select, pairs, unpack or table.unpack, assert, next
table.pack = table.pack or function (...)
	return {n=select('#',...),...}
end


local M = {}

--- Currently running task.
-- The task descriptor from current task.
M.running_task = false

--- Task died event.
-- This event will be emited when a task is either killed or finishes on error.
-- The parameter is 'killed' if the task was killed, or the error message otherwise.
-- @usage --prints each time a task dies
--sched.sigrun({sched.EVENT_DIE}, print)
M.EVENT_DIE = setmetatable({}, {__tostring=function() return "event: DIE" end})
  
--- Task finished event.
-- This event will be emited when a task finishes normally.
-- The parameters are the output of the task's function.
-- @usage --prints each time a task finishes
--sched.sigrun({sched.EVENT_FINISH}, print)
M.EVENT_FINISH = setmetatable({}, {__tostring=function() return "event: FINISH" end})

--- Event used for all events
-- When included in a @{waitd}, will match any event.
M.EVENT_ANY = {}
  
--TODO
M.STEP = {}

--- Function used by the scheduler to get current time.
-- Replace with whatever your app uses. LuaSocket's gettime works just fine.
-- Defaults to os.time.
-- @function get_time
M.get_time = os.time

--- Tasks in scheduler.
-- Table holding @{taskd} objects of the tasks in the scheduler. 
-- @usage for taskd, _ in pairs (sched.tasks) do print(taskd) end
M.tasks = {}
local new_tasks = {} --hold tasks as created until transferred to main M.tasks (ref. lua looping)

--table to keep track tasks waiting for signals
--waiting[event][waitd] = {taskd}
--waitd as per reference
local waiting = {} -- setmetatable({}, weak_key)
local signal_queue = queue3:new()
local next_waketime

local step_task
local function emit_signal ( event, packed, ... ) --FIXME
  local function walk_waitd(waitd, event, ...)
    for taskd, _ in pairs(waitd.tasks) do
      --if not taskd then print (debug.traceback()) end
      if type(taskd)~='table' then print (debug.traceback()) end
      if taskd.waitingfor == waitd and taskd.status=='ready' then
        taskd.waketime, taskd.waitingfor = nil, nil
        step_task(taskd, event, ...)
        if M.running_task and M.running_task.status == 'dead' then 
          -- the task was killed from a triggered task
          --print('the task was killed from a triggered task')
          --print (debug.traceback())
          --return --FIXME
          M.wait()
        end
      else
        --TODO buffering
        if waitd.buff_mode == 'keep_last' or
        waitd.buff_mode == 'keep_first' and not waitd.buff_event then
          waitd.buff_event = event
          --print ('buff', select('#',...), ...)
          local n = select('#',...)
          if packed then 
            waitd.signal_packed, waitd.buff_parameter = true, select(1, ...)
          elseif n == 0 then
            waitd.signal_packed, waitd.buff_parameter = nil, nil
          elseif n == 1 then
            waitd.signal_packed, waitd.buff_parameter = false, select(1, ...)
          else
            waitd.signal_packed, waitd.buff_parameter = true, {n=n,...}
          end
        end
      end
    end
  end
  if waiting[event] then 
    for waitd, _ in pairs(waiting[event]) do
      walk_waitd(waitd, event, ...)
    end
  end
  if waiting[M.EVENT_ANY] then 
    for waitd, _ in pairs(waiting[M.EVENT_ANY]) do
      walk_waitd(waitd, event, ...)
    end
  end
end


step_task = function (taskd, ...)
	if taskd.status=='ready' then
		local check = function(ok, ...)
			if coroutine.status(taskd.co)=='dead' then
				M.tasks[taskd]=nil
				if ok then 
					log('SCHED', 'DETAIL', '%s returning %d parameters', tostring(taskd), select('#',...))
					emit_signal(taskd.EVENT_FINISH, false, ...) --per task
					emit_signal(M.EVENT_FINISH, false, taskd, ...) --global
				else
					log('SCHED', 'WARNING', '%s die on error, returning %d parameters: %s'
						, tostring(taskd), select('#',...), tostring(...))
          emit_signal(taskd.EVENT_DIE, false, ...) --per task
					emit_signal(M.EVENT_DIE, false, taskd, ...) --global
				end
				for child, _ in pairs(taskd.attached) do
					M.kill(child)
				end
				taskd.status='dead'
			end
		end
		local previous_task = M.running_task
		M.running_task = taskd
		check(coroutine.resume(taskd.co, ...))
		M.running_task = previous_task
	end
end 

--- Control memory collection.
-- number of new insertions in waiting[event] before triggering clean_up.
-- Defaults to 1000
M.to_clean_up = 1000

local clean_up = function()
	--clean up waiting table
	log('SCHED', 'DEBUG', 'collecting garbage')
  for ev, waitds in pairs(waiting) do
    if next(waitds)==nil then
      waiting[ev]=nil
    end
  end
	collectgarbage ('collect')
end

local waitd_count = 0
--- Create a Wait Descriptor.
-- Creates @{waitd} object in the scheduler. Notice that buffering waitds
-- start buffering as soon they are created.
-- @param waitd_table a table to convert into a wait descriptor.
-- @return a wait descriptor object.
M.new_waitd = function(waitd_table)
  if not M.running_task then print (debug.traceback()) end
   assert(M.running_task)
  if not waitd_table.tasks then 
    -- first task to use a waitd
    setmetatable(waitd_table, { __index=M })
    waitd_table.tasks = setmetatable({[M.running_task]=true}, {__mode='k'})
    for i=1, #waitd_table do
      local ev = waitd_table[i]
      waiting[ev] = waiting[ev] or setmetatable({}, weak_key)
      waiting[ev][waitd_table] = true --setmetatable({}, weak_key)
    end
		log('SCHED', 'DETAIL', 'task %s created waitd %s', tostring(M.running_task), tostring(waitd_table))
    waitd_count = waitd_count + 1
    if waitd_count % M.to_clean_up == 0 then clean_up() end
  else
    log('SCHED', 'DETAIL', 'task %s using existing waitd %s', tostring(M.running_task), tostring(waitd_table))
		waitd_table.tasks[M.running_task] = true
  end
  
  return waitd_table
end

--- Wait for a signal.
-- Pauses the task until (one of) the specified signal(s) is available.
-- If there is a signal in the buffer, will return it immediately.
-- Otherwise will block the task until signal arrival, or a timeout.
-- If provided a table as parameter, will use @{new_waitd} to convert it
-- to a wait desciptor. If param is _nil_ will yield to other tasks (as
-- in cooperative multitasking)
-- Can be invoked as waitd:wait().
-- @return On event returns _event, parameters_. On timeout
-- returns _nil, 'timeout'_
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
M.wait = function ( waitd )
  assert(M.running_task)
  if waitd then 
    --in case passed a non created or joined waitd
    if not M.running_task.waitds[waitd] then
      waitd=M.new_waitd(waitd)
      M.running_task.waitds[waitd] = true
    end
     
    -- feed from buffer if present
    if waitd.buff_event then
      local event, parameter = waitd.buff_event, waitd.buff_parameter
      waitd.buff_event, waitd.buff_parameter = nil, nil
      if waitd.signal_packed==true then
        return event, unpack(parameter, 1, parameter.n)
      elseif waitd.signal_packed==false then
        return event, parameter
      else --nil
        return event
      end
    end
    
    local timeout = waitd.timeout
    if timeout and timeout>=0 then
      local t = timeout + M.get_time()
      M.running_task.waketime = t
      next_waketime = next_waketime or t
      if t<next_waketime then next_waketime=t end
    end

    M.running_task.waitingfor = waitd
  end
	return coroutine.yield( M.running_task.co )
end

--- Sleeps the task for t time units.
-- Time computed according to @\{get_time}.
-- @param timeout time to sleep
M.sleep = function (timeout)
	local sleep_waitd = M.running_task.sleep_waitd
	sleep_waitd.timeout=timeout
	M.wait(sleep_waitd)
end

--M.new_task = function ( f )
local function new_task ( f )
	local co = coroutine.create( f )
	local taskd = setmetatable({
		status='ready', --'paused',
		created_by=M.running_task,
		co=co,
		attached=setmetatable({}, weak_key),
    waitds=setmetatable({}, weak_key),
		sleep_waitd={}, --see M.sleep()
    EVENT_DIE = setmetatable({}, {__tostring=function() return "event: DIE"..tostring(f) end}),
    EVENT_FINISH = setmetatable({}, {__tostring=function() return "event: FINISH"..tostring(f) end}),
	}, {
		__index=M, --OO-styled access
	})
	--M.tasks[taskd] = true
  new_tasks[taskd] = true
	return taskd
end
--- Create a task.
-- The task is created in paused mode. To run the created task,
-- use @{run} or @{set_pause}.
-- The task will emit a _sched.EVENT\_FINISH, true, params..._
-- signal upon normal finalization, were params are the returns of f.
-- If there is a error, the task will emit a _sched.EVENT\_DIE, false, err_ were
-- err is the error message.
-- @function new_task
-- @param f function for the task
-- @return task in the scheduler (see @{taskd}).
M.new_task = new_task

--- Attach a task to another.
-- An attached task will be killed by the scheduler whenever
-- the parent task is finished (returns, errors or is killed). Can be 
-- invoked as taskd:attach(taskd\_child).
-- @param taskd The parent task
-- @param taskd_child The child (attached) task.
-- @return the modified taskd.
M.attach = function (taskd, taskd_child)
	taskd.attached[taskd_child] = true
	log('SCHED', 'DETAIL', '%s is attached to %s', tostring(taskd_child), tostring(taskd))
	return taskd
end

--- Set a task as attached to the creator task.
-- An attached task will be killed by the scheduler whenever
-- the parent task (the task that created it) is finished (returns, errors or is killed). 
-- Can be invoked as taskd:set\_as\_attached().
-- @param taskd The child (attached) task.
-- @return the modified taskd.
M.set_as_attached = function(taskd)
	if taskd.created_by then M.attach(taskd.created_by, taskd) end
	return taskd
end

--- Run a task.
-- Can be provided either a @{taskd} or a function, with optional parameters.
-- If provided a taskd, will run it. If provided a function, will use @{new_task}
-- to create a task first. This call yields control to the new task immediatelly.
-- @param task wither a @{taskd} or function for the task.
-- @param ... parameters passed to the task upon first run.
-- @return a task in the scheduler (see @{taskd}).
M.run = function ( task, ... )
	local taskd
	if type(task)=='function' then
		taskd = new_task( task )
	else
		taskd = task
	end
	--M.set_pause(taskd, false)
	step_task(taskd, ...)  --FIXME can get the task killed: still in new_tasks
	return taskd
end

--- Create and run a task that listens for a signal.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter.The signal will be provided as 
-- _event, parameters_, just as the result of a @{wait}
-- @param attached if true, the new task will run in attached mode
-- @return task in the scheduler (see @{taskd}).
M.sigrun = function( waitd, f, attached)
	--local taskd = M.new_sigrun_task( waitd, f )
 	local taskd = new_task( function()
		while true do
			f(M.wait(waitd))
		end
	end)
	if attached then taskd:set_as_attached() end
	return M.run(taskd)
end

--- Create and run a task that listens for a signal, once.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- _event, parameters_, just as the result of a @{wait}
-- @param attached if true, the new task will run in attached more
-- @return task in the scheduler (see @{taskd}).
M.sigrunonce = function( waitd, f, attached)
	local taskd = new_task( function()
		f(M.wait(waitd))
	end )
	if attached then taskd:set_as_attached() end
	return M.run(taskd)
end

--- Pause a task.
-- A paused task won't be scheduled for execution. If paused while waiting for a signal, 
-- won't respond to signals. Signals on unbuffered waitds will get lost. Task's buffered 
-- waitds will still buffer events. Can be invoked as taskd:set_pause(pause)
-- @param taskd Task to pause (see @{taskd}). 
-- @param pause mode, true to pause, false to unpause
-- @return the modified taskd on success or _nil, errormessage_ on failure.
M.set_pause = function(taskd, pause)
	log('SCHED', 'DEBUG', '%s setting pause on %s to %s', tostring(M.running_task), tostring(taskd), tostring(pause))
	if taskd.status=='dead' then
		log('SCHED', 'WARNING', '%s toggling pause on dead %s', tostring(M.running_task), tostring(taskd))
		return nil, 'task is dead'
	end
	if pause then
		taskd.status='paused'
		if M.running_task==taskd then
			M.wait()
		end
	else
		taskd.status='ready'
	end
	return taskd
end

--- Idle function.
-- Function called by the scheduler when there is
-- nothing else to do (e.g., all tasks are waiting for a signal).
-- This function should idle up to t time units. Replace with
-- whatever your app uses. LuaSocket's sleep works just fine.
-- It is allowed to idle for less than t; the empty function will
-- result in a busy wait. Defaults to execution of Linux's "sleep" command.
-- @param t time to idle
M.idle = require'lumen.lib.idle'

local cycleready = {}

--[[
local wake_up = function (taskd, waitd)
	if not taskd or taskd.status~='ready'
	or (waitd and waitd~=taskd.waitingfor) then
		return false
	end

	taskd.waketime = nil
	taskd.waitingfor = nil
	return true
end
--]]

--- Finishes a task.
-- The killed task will emit a signal _sched.EVENT\_DIE, 'killed'_. Can be 
-- invoked as taskd:kill().
-- @param taskd task to terminate (see @{taskd}).
M.kill = function ( taskd )
	log('SCHED', 'DETAIL', 'killing %s from %s', tostring(taskd), tostring(M.running_task))
	M.tasks[taskd] = nil
	
	for child, _ in pairs(taskd.attached) do
		M.kill(child)
	end
  emit_signal(taskd.EVENT_DIE, false, 'killed') --per task
  emit_signal(M.EVENT_DIE, false, taskd, 'killed') --global
	taskd.status = 'dead'
end

--- Emit a signal.
-- Will give control immediatelly to tasks that are waiting on
-- event, to regain it when they finish/block.
-- @param event event of the signal. Can be of any type.
-- @param ... further parameters to be sent with the signal.
M.signal = function ( event, ... )
	log('SCHED', 'DEBUG', 'task %s emitting event %s with %d parameters', 
		tostring(M.running_task), tostring(event), select('#', ...))
  emit_signal(event, false, ...)  
end

--- Emit a signal lazily.
-- Like @{signal}, except it does not yield control.
-- Will schedule the event to be emitted after task yields by 
-- other means (it even can be delayed beyond that by the scheduler). 
-- Scheduled signals from multiple tasks will be 
-- emitted in order.
-- @param event event of the signal. Can be of any type.
-- @param ... further parameters to be sent with the signal.
M.schedule_signal = function ( event, ... )
  local n = select('#', ...)
	log('SCHED', 'DEBUG', '%s echeduling event %s with %d parameters', 
		tostring(M.running_task), tostring(event), n)
  if n == 0 then
    signal_queue:pushright(event, nil, nil)  
  elseif n==1 then 
    signal_queue:pushright(event, false, select(1, ...))  
  else
    signal_queue:pushright(event, true, {n=n,...})  
  end
end

--- Runs a single step of the scheduler.
-- @return the idle time available until more activity is expected; this
-- means it will be 0 if there are active tasks.
M.step = function ()
  next_waketime = nil
    
  -- emit scheduled signals
  while signal_queue:len()>0 do
    local event, packed, parameter = signal_queue:popleft() 
    emit_signal(event, packed, parameter) --FIXME avoid repacking when buffering
  end
  
  -- transfer recently created tasks to main table
  for k, _ in pairs(new_tasks) do
    new_tasks[k]=nil
    M.tasks[k]=true
  end
  
  --register all ready&not waiting to run
  --if find one waiting&timeouting, wake it --and finish
	for taskd, _ in pairs (M.tasks) do
		if taskd.status=='ready' then
			if taskd.waitingfor then
				local waketime = taskd.waketime
				if waketime then
					next_waketime = next_waketime or waketime
					if waketime <= M.get_time() then
            --emit_timeout
            taskd.waketime, taskd.waitingfor = nil, nil
            step_task(taskd, nil, 'timeout')
            --return 0
					end
					if waketime < next_waketime then
						next_waketime = waketime
					end
				end
			else
				cycleready[#cycleready+1]=taskd
			end
		end
	end

  
  --wake all ready tasks
  local function compute_available_time()
    local available_time
    if next_waketime then
      available_time=next_waketime-M.get_time()
      if available_time<0 then available_time=0 end
    end
    return available_time
  end
  local remaining -- available idle time to be returned

	if #cycleready==0 then
		if next_waketime then
			remaining = next_waketime-M.get_time()
			if remaining < 0 then remaining = 0 end
		end
  elseif #cycleready==1 then
    local available_time = compute_available_time()
    step_task( cycleready[1], M.STEP, available_time, available_time )
    cycleready[1]=nil
    remaining = 0
  else
    for i=1, #cycleready do
      step_task( cycleready[i], M.STEP, 0, compute_available_time() )
      cycleready[i]=nil
    end
    remaining = 0
	end
  
	return remaining
end

--- Wait for the scheduler to finish.
-- This call will block until there is no more task activity, i.e. there's no active task,
-- and none of the waiting tasks has a timeout set. 
-- @usage local sched = require 'lumen.sched'
-- sched.run(function()
--    --start at least one task
-- end)
-- sched.loop()
-- --potentially free any resources before finishing here  
--
M.loop = function ()
	log('SCHED', 'INFO', 'Started.')
	repeat
		local idle_time = M.step()
		if idle_time and idle_time>0 then
			M.idle( idle_time )
		end
	until not idle_time
	log('SCHED', 'INFO', 'Finished.')
end

--- Data structures.
-- Main structures used.
-- @section structures

------
-- Wait descriptor.
-- Specifies a condition on which wait. Includes a signal description,
-- a optional timeout specification and buffer configuration.
-- A wait descriptor can be reused (for example, when waiting inside a
-- loop) and shared amongst different tasks. If a wait descriptor changes
-- while there is a task waiting, the behavior is unspecified. Notice that
-- when sharing a wait descriptor between several tasks, the buffer is
-- associated to the wait descriptor, and tasks will service buffered signals
-- on first request basis.  
-- Besides the following fields, provides methods for
-- the sched functions that have a waitd as first parameter.
-- @field array The array part contains the events to wait. Can contain `sched.EVENT_ANY` 
-- to mark interest in any event. If nil, will only return on timeout. 
-- @field timeout optional, time to wait. nil or negative waits for ever.
-- @field buff_mode Specifies how to behave when inserting in a full buffer.
-- 'keep last' means replace with the new arrived signal. 'keep first'
-- will skip the insertion in a full buffer. nil disables buffering
-- @table waitd

------
-- Task descriptor.
-- Handler of a task. Besides the following fields, provides methods for
-- the sched functions that have a taskd as first parameter.
-- @field status Status of the task, can be 'ready', 'paused' or 'dead'
-- @field waitingfor If the the task is waiting for a signal, this is the 
-- Wait Descriptor (see @{waitd})
-- @field waketime The time at which to task will be forced to wake-up (due
-- to a timeout on a wait)
-- @field created_by The task that started this one.
-- @field attached Table containing attached tasks.
-- @field co The coroutine of the task
-- @table taskd


return M