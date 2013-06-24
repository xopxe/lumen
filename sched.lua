--- Lumen cooperative scheduler.
-- Lumen (Lua Multitasking Environment) is a simple environment 
-- for coroutine based multitasking. Consists of a signal scheduler, 
-- and that's it.
-- Functions that receive a task or wait descriptors can be invoked as methods
-- of the corresponing events. For example, sched.kill(task) can be invoked as 
-- task:kill()
-- @module sched
-- @usage local sched = require 'sched'
--sched.sigrun({emitter='*', events={'a signal'}}, print)
--local task=sched.run(function()
--   sched.signal('a signal', 'data')
--   sched.sleep(1)
--end)
-- @alias M

local log=require 'log'

--get locals for some useful things
local pairs, ipairs, next, coroutine, setmetatable, os, tostring, select, unpack
	= pairs, ipairs, next, coroutine, setmetatable, os, tostring, select, unpack

table.pack=table.pack or function (...)
	return {n=select('#',...),...}
end

local M = {}

local queue = require 'lib/queue'

local weak_key = { __mode = 'k' }

--local event_die = {} --singleton event for dying tasks
local event_die = setmetatable({}, {__tostring=function() return "event: DIE" end})


--table containing all the registered tasks.
--tasks[taskd] = true
--taskd is {waketime=[number], waitingfor=[waitd], status='ready'|'paused'|'dead', co=coroutine}

--- Tasks in scheduler.
-- Table holding @{taskd} objects of the tasks in the scheduler. 
-- @usage for taskd, _ in pairs (sched.tasks) do print(taskd) end
M.tasks = {}
local sched_tasks = M.tasks

--- Wait descriptors in scheduler.
-- Table holding @{waitd} objects used in the scheduler. Associates to each waitd
-- a table with the @{waitd}s of tasks that use it.
-- @usage for waitd, _ in pairs (sched.waitds) do print(waitd) end 
--end
M.waitds = setmetatable({}, weak_key)
local sched_waitds = M.waitds


--table to keep track tasks waiting for signals
--waiting[event][emitter][task]=waitd
--waitd as per reference
local waiting = setmetatable({}, weak_key)
local waiting_emitter_counter = 0 --for triggering cleanups

--closeset wait timeout during a scheduler step
local next_waketime

local step_task

-- debugging stuff
local track_waitd_statistics
local track_taskd_statistics 
local do_not_yield 

--changes the status of a task from waiting to active (if everything is right)
local wake_up = function (taskd, waitd)
	if not taskd or taskd.status~='ready'
	or (waitd and waitd~=taskd.waitingfor) then
		track_waitd_statistics (waitd, 'missed')
		return false
	end

	taskd.waketime = nil
	taskd.waitingfor = nil
	return true
end

local to_buffer = function (waitd, emitter, event, ...)
	local buff_len = waitd.buff_len
	--print('add to buffer',buff_len,waitd, event, ...)
	if buff_len and buff_len~=0 then
		waitd.buff = waitd.buff or queue:new()
		local buff=waitd.buff
		if buff_len<0 then
			buff:pushright(table.pack(emitter, event, ...))
		else
			local overpopulation = buff:len()-buff_len
			--print('OP', buff_len,buff:len(),overpopulation)
			if overpopulation<0 then
				buff:pushright(table.pack(emitter, event, ...))
			else
				log('SCHED', 'DEBUG', 'buffer from waitd  %s is dropping', tostring(waitd))
				waitd.dropped = true
				if waitd.buff_mode == 'drop_first' then
					for _ = 0, overpopulation do
						track_waitd_statistics (waitd, 'dropped')
						buff:popleft()
					end
					buff:pushright(table.pack(emitter, event, ...))
				else --'drop_last', default
					for _ = 1, overpopulation do
						track_waitd_statistics (waitd, 'dropped')
						buff:popright()
					end
				end
			end
		end
		return true
	end
end

--iterates over a list of tasks sending them events. the iteration is split as the
--list can change during iteration. it also sees if a event should be buffered
local walktasks = function (waitingtasks, emitter, event, ...)
	local waked_up, bufferable = {}, {}
	--local my_task = coroutine.running()
	for taskd, waitd in pairs(waitingtasks) do
		--print('',':',task, waitd, waiting[task])
		--[[
		if task==emitter then 
			log('SCHED', 'INFO', '%s trying signal itself on waitd %s'
				, tostring(task), tostring(waitd))
		end
		--]]
		if wake_up( taskd, waitd ) then
			track_waitd_statistics (waitd, 'triggered')
			waked_up[taskd] = waitd
		else
			bufferable[waitd] = true
		end
	end
	for _, waitd in pairs(waked_up) do
		bufferable[waitd] = nil
	end
	for waitd, _ in pairs(bufferable) do
		track_waitd_statistics (waitd, 'buffered')
		to_buffer(waitd, emitter, event, ...)
	end
	for taskd, _ in pairs(waked_up) do
		step_task(taskd, emitter, event, ...)
	end
end

--will wake up and run all tasks waiting on a event
local emit_signal = function (emitter, event, ...)
	--print('emitsignal',emitter, waiting[event], event, ...)
	local on_event, on_evaster = waiting[event], waiting['*']
	if on_event then
		local waiting1, waiting2 = on_event[emitter], on_event[ '*' ]
		if waiting1 then walktasks(waiting1, emitter, event, ...) end
		if waiting2 then walktasks(waiting2, emitter, event, ...) end
	end
	if on_evaster then
		local waiting1, waiting2 = on_event[emitter], on_event[ '*' ]
		if waiting1 then walktasks(waiting1, emitter, event, ...) end
		if waiting2 then walktasks(waiting2, emitter, event, ...) end
	end
end

---
-- resumes a task and handles finalization conditions
-- @local
step_task = function(taskd, ...)
	if taskd.status=='ready' then
		local check = function(ok, ...)
			--M.running_task = nil
			if do_not_yield then 
				error("Task "..tostring(taskd).." yielded under do_not_yield: "
					..tostring(do_not_yield), 0) 
			end
		
			track_taskd_statistics(taskd, 'out')
			if coroutine.status(taskd.co)=='dead' then
				taskd.status='dead'
				sched_tasks[taskd]=nil
				if ok then 
					log('SCHED', 'DETAIL', '%s returning %d parameters', tostring(taskd), select('#',...))
					emit_signal(taskd, event_die, true, ...)
				else
					log('SCHED', 'WARNING', '%s die on error, returning %d parameters: %s'
						, tostring(taskd), select('#',...), tostring(...))
					emit_signal(taskd, event_die, nil, ...)
				end
				for child, _ in pairs(taskd.attached) do
					M.kill(child)
				end
			end
		end
		local previous_task = M.running_task
		M.running_task = taskd
		track_taskd_statistics(taskd, 'in')
		check(coroutine.resume(taskd.co, ...))
		M.running_task = previous_task
	end
end


local clean_up = function()
	--clean up waiting table
	log('SCHED', 'DEBUG', 'collecting garbage')
	for event, eventt in pairs(waiting) do
		for emitter, emittert in pairs(eventt) do
			for task, taskt in pairs(emittert) do
				if next( taskt )==nil then
					emittert[task]=nil
				end
			end
			if next( emittert )==nil then
				eventt[emitter]=nil
			end
		end
		if next( eventt )==nil then
			waiting[event]=nil
		end
	end
	collectgarbage ('collect')
end


--blocks a task waiting for a signal. registers the task in waiting table.
local register_signal = function(taskd, waitd)
	log('SCHED', 'DETAIL', '%s registers waitd %s', tostring(taskd), tostring(waitd))
  
  local function process_emev(emitter, events)
    local function register_emitter(events, etask)
      for _, event in ipairs(events) do
        --print('',':', event)
        waiting[event]=waiting[event] or setmetatable({}, weak_key)
        if not waiting[event][etask] then
          waiting[event][etask] = setmetatable({}, { __mode = 'kv' })
          waiting_emitter_counter = waiting_emitter_counter + 1
        end
        waiting[event][etask][taskd]=waitd
      end
      if waiting_emitter_counter>M.to_clean_up then
        waiting_emitter_counter = 0
        clean_up()
      end
    end
    if events then
      if events=='*' then events={'*'} end
      if emitter=='*' or emitter.co then
        --single taskd parameter
        register_emitter(events, emitter)
      else
        --is a array of taskd
        for _, e in ipairs(emitter) do 
          register_emitter(events, e)
        end
      end
    end
  end
  
  if waitd.multi then
    for _, v in ipairs(waitd.multi) do
      process_emev(v.emitter or '*', v.events)
    end
  else
    process_emev(waitd.emitter or '*', waitd.events)
  end  
  
end

local emit_timeout = function (taskd)
	--print('emittimeout',task)
	if wake_up( taskd ) then
		step_task(taskd, nil, 'timeout')
	end
end

--aux. function, computes time>=0 until next_waketime, nil if no next_waketime
local compute_available_time = function()
	local available_time
	if next_waketime then
		available_time=next_waketime-M.get_time()
		if available_time<0 then available_time=0 end
	end
	return available_time
end

local n_task = 0

--- Create a task.
-- The task is created in paused mode. To run the created task,
-- use @{run} or @{set_pause}.
-- The task will emit a _sched.EVENT\_DIE, true, params..._
-- signal upon normal finalization, were params are the returns of f.
-- If there is a error, the task will emit a _sched.EVENT\_DIE, false, err_ were
-- err is the error message.
-- @param f function for the task
-- @return task in the scheduler (see @{taskd}).
M.new_task = function ( f )
	local co = coroutine.create( f )
	n_task = n_task + 1
	local task_name = 'task: #'..n_task
	local taskd = setmetatable({
		status='paused',
		created_by=M.running_task,
		co=co,
		attached=setmetatable({}, weak_key),
		sleep_waitd={}, --see M.sleep()
		
		--OO-styled access
		run = M.run,
		attach = M.attach,
		set_as_attached = M.set_as_attached,
		kill = M.kill,
		set_pause = M.set_pause,
	}, {
		--__index=M, --OO-styled access
		__tostring=function() return task_name end,
	})
	sched_tasks[taskd] = true
	log('SCHED', 'DETAIL', 'created %s from %s', tostring(taskd), tostring(f))
	--step_task(taskd, ...)
	return taskd
end

local function get_sigrun_wrapper(waitd, f)
	local wrapper = function()
		while true do
			f(M.wait(waitd))
		end
	end
	log('SCHED', 'DETAIL', 'sigrun wrapper %s created from %s and waitd %s', 
		tostring(wrapper), tostring(f), tostring(waitd))
	return wrapper
end

--- Create a task that listens for a signal.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter.The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @return task in the scheduler (see @{taskd}).
M.new_sigrun_task = function ( waitd, f )
	local taskd=M.new_task( get_sigrun_wrapper(waitd, f) )
	return taskd
end

local function get_sigrunonce_wrapper(waitd, f)
	local wrapper = function()
		f(M.wait(waitd))
	end
	log('SCHED', 'DETAIL', 'sigrun wrapper %s created from %s and waitd %s', 
		tostring(wrapper), tostring(f), tostring(waitd))
	return wrapper
end

--- Create a task that listens for a signal, once.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @return task in the scheduler (see @{taskd}).
M.new_sigrunonce_task = function ( waitd, f )
	local taskd=M.new_task( get_sigrunonce_wrapper(waitd, f) )
	return taskd
end

--- Run a task.
-- Can be provided either a @{taskd} or a function with optional parameters.
-- If provided a taskd, will run it. If provided a function, will use @{new_task}
-- to create a task first.
-- @param task wither a @{taskd} or function for the task.
-- @param ... parameters passed to the task upon first run.
-- @return a task in the scheduler (see @{taskd}).
M.run = function ( task, ... )
	local taskd
	if type(task)=='function' then
		taskd = M.new_task( task, ...)
	else
		taskd = task
	end
	M.set_pause(taskd, false)
	step_task(taskd, ...)
	return taskd
end

--- Create and run a task that listens for a signal.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter.The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @param attached if true, the new task will run in attached more
-- @return task in the scheduler (see @{taskd}).
M.sigrun = function( waitd, f, attached)
	local taskd = M.new_sigrun_task( waitd, f )
	if attached then taskd:set_as_attached() end
	return M.run(taskd)
end

--- Create and run a task that listens for a signal, once.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @param attached if true, the new task will run in attached more
-- @return task in the scheduler (see @{taskd}).
M.sigrunonce = function( waitd, f, attached)
	local taskd = M.new_sigrunonce_task( waitd, f )
	if attached then taskd:set_as_attached() end
	return M.run(taskd)
end


--- Attach a task to another.
-- An attached task will be killed by the scheduler whenever
-- the parent task is finished (returns, errors or is killed). Can be 
-- invoked as taskd:attach(taskd_child).
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
-- Can be invoked as taskd:set_as_attached().
-- @param taskd The child (attached) task.
-- @return the modified taskd.
M.set_as_attached = function(taskd)
	if taskd.created_by then M.attach(taskd.created_by, taskd) end
	return taskd
end

--- Finishes a task.
-- The killed task will emit a signal _sched.EVENT\_DIE, false, 'killed'_. Can be 
-- invoked as taskd:kill().
-- @param taskd task to terminate (see @{taskd}).
M.kill = function ( taskd )
	log('SCHED', 'DETAIL', 'killing %s from %s', tostring(taskd), tostring(M.running_task))
	taskd.status = 'dead'
	sched_tasks[taskd] = nil
	
	for child, _ in pairs(taskd.attached) do
		M.kill(child)
	end
	
	emit_signal(taskd, event_die, false, 'killed')
end

--- Emit a signal.
-- @param event event of the signal. Can be of any type.
-- @param ... further parameters to be sent with the signal.
M.signal = function ( event, ... )
	log('SCHED', 'DEBUG', '%s emitting event %s with %d parameters', 
		tostring(M.running_task), tostring(event), select('#', ...))
	emit_signal( M.running_task, event, ... )
end


local n_waitd=0
--- Create a Wait Descriptor.
-- Creates @{waitd} object in the scheduler. Notice that buffering waitds
-- start buffering as soon they are created.
-- @param waitd_table a table to convert into a wait descriptor.
-- @return a wait descriptor object.
M.new_waitd = function(waitd_table)
	if not sched_waitds[waitd_table] then 
		-- first task to use a waitd
		n_waitd = n_waitd + 1
		local waitd_name = 'waitd: #'..n_waitd
		setmetatable(waitd_table, {
			__tostring=function() return waitd_name end,
		})
		--OO
		waitd_table.new_sigrun_task = M.new_sigrun_task
		waitd_table.new_sigrunonce_task = M.new_sigrunonce_task
		waitd_table.sigrun = M.sigrun
		waitd_table.sigrunonce = M.sigrunonce
		waitd_table.wait = M.wait
		
		log('SCHED', 'DETAIL', '%s created %s', tostring(M.running_task), tostring(waitd_table))
		
		register_signal( M.running_task, waitd_table )
		sched_waitds[waitd_table] = setmetatable({[M.running_task]=true}, weak_key)
		track_waitd_statistics (waitd_table, 'registered')
	elseif not sched_waitds[waitd_table][M.running_task] then
		-- additional task using a waitd
		log('SCHED', 'DETAIL', '%s using existing %s', tostring(M.running_task), tostring(waitd_table))
		register_signal( M.running_task, waitd_table )
		sched_waitds[waitd_table][M.running_task] = true
		track_waitd_statistics (waitd_table, 'registered')
	end
	
	return waitd_table
end

--- Wait for a signal.
-- Pauses the task until (one of) the specified signal(s) is available.
-- If there are signals in the buffer, will return the first immediately.
-- Otherwise will block the task until signal arrival, or a timeout.
-- If provided a table as parameter, will use @{new_waitd} to convert it
-- to a wait desciptor.
-- Can be invoked as waitd:wait().
-- @return On event returns _emitter, event, parameters_. On timeout
-- returns _nil, 'timeout'_
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
M.wait = function ( waitd )
	assert(M.running_task, 'attempt to wait outside a task')

	--in case passed a non created waitd
	waitd=M.new_waitd(waitd)
	
	log('SCHED', 'DEBUG', '%s is waiting on waitd %s', tostring(M.running_task), tostring(waitd))
	
	--if there are buffered signals, service the first
	local buff = waitd.buff
	if buff and buff:len()> 0 then
		local ret = buff:popleft()
		--print('W from buff')
		return unpack(ret, 1, ret.n)
	end

	local timeout = waitd.timeout
	if timeout and timeout>=0 then
		local t = timeout + M.get_time()
		M.running_task.waketime = t
		next_waketime = next_waketime or t
		if t<next_waketime then next_waketime=t end
	end

	M.running_task.waitingfor = waitd
	return coroutine.yield( M.running_task.co )
end

--- Sleeps the task for t time units.
-- Time computed according to @\{get_time}.
-- @param timeout time to sleep
M.sleep = function (timeout)
--print('to sleep', timeout)
	assert(M.running_task, 'attempt to sleep outside a task')
	local sleep_waitd = M.running_task.sleep_waitd
	sleep_waitd.timeout=timeout
	M.wait(sleep_waitd)
	--M.wait({timeout=timeout})
end

--- Yields the execution of a task, as in cooperative multitasking.
M.yield = function ()
	assert(M.running_task, 'attempt to yield outside a task')
	return coroutine.yield( M.running_task.co )
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
			M.yield()
		end
	else
		taskd.status='ready'
	end
	return taskd
end

--- Idle function.
-- Function called by the scheduler when there is
-- nothing else to do (e.g., all tasks are waiting for a signal).
-- This function should idle up to t time units (notice that an empty
-- function satisifies this, tough results in busy waits). Replace with
-- whatever your app uses. LuaSocket's sleep works just fine.
-- It is allowed to idle for less than t; the empty function will
-- result in a busy wait. Defaults to execution of Linux's "sleep" command.
-- @param t time to idle
M.idle = function (t)
	--print("Idling", t)
	local ret = os.execute('sleep '..t) 
	if _VERSION =='Lua 5.1' and ret ~= 0 
	or _VERSION =='Lua 5.2' and ret ~= true then 
		log('SCHED', 'INFO', 'Idle sleeping cancelled, will exit.')
		os.exit() 
	end
end

--- Function used by the scheduler to get current time.
-- Replace with whatever your app uses. LuaSocket's gettime works just fine.
-- Defaults to os.time.
-- @function get_time
M.get_time = os.time

local cycleready, cycletimeout = {}, {}
--- Runs a single step of the scheduler.
-- @return the idle time available until more activity is expected; this
-- means it will be 0 if there are active tasks.
M.step = function ()
	next_waketime = nil

	--find tasks ready to run (active) and ready to wakeup by timeout
	for taskd, _ in pairs (sched_tasks) do
		if  taskd.status=='ready' then
			if taskd.waitingfor then
				local waketime = taskd.waketime
				if waketime then
					next_waketime = next_waketime or waketime
					if waketime <= M.get_time() then
						cycletimeout[#cycletimeout+1]=taskd
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
	local ncycleready,ncycletimeout = #cycleready, #cycletimeout

	--wake timeouted tasks
	for i, taskd in ipairs(cycletimeout) do
		cycletimeout[i]=nil
		emit_timeout( taskd )
	end

	--step active tasks (keeping track of impending timeouts)
	--active means they yielded, so they receive as parameters timing data
	--see sched.yield()
	if ncycleready==1 then
		local available_time = compute_available_time()
		step_task( cycleready[1], available_time, available_time )
		cycleready[1]=nil
	else
		for i, taskd in ipairs(cycleready) do
			local available_time = compute_available_time()
			step_task( taskd, 0, available_time )
			cycleready[i]=nil
		end
	end

	--calculate available idle time to be returned
	if ncycletimeout==0 and ncycleready==0 then
		if not next_waketime then
			return nil
		else
			local remaining = next_waketime-M.get_time()
			if remaining > 0 then
				return remaining
			end
		end
	end
	return 0
end

--- Starts the scheduler.
-- Will run until there is no more activity, i.e. there's no active task,
-- and none of the waiting tasks has a timeout set.
M.go = function ()
	log('SCHED', 'INFO', 'Started.')
	repeat
		local idle_time = M.step()
		if idle_time and idle_time>0 then
			M.idle( idle_time )
		end
	until not idle_time
	log('SCHED', 'INFO', 'Finished.')
end

--- Task dying event.
-- This event will be emitted when a task dies. When the task dies a natural 
-- death (finishes), the first parameter is true, followed by 
-- the task returns. Otherwise, the first parameter is nil and the second 
-- is 'killed' if the task was killed, or the error message if the task errore'd.
-- @usage --prints each time a task dies
--sched.sigrun({emitter='*', events={sched.EVENT_DIE}}, print)
M.EVENT_DIE = event_die

--- Control memory collection.
-- number of new insertions in waiting[event] before triggering clean_up.
-- Defaults to 1000
M.to_clean_up = 1000

--- Currently running task.
-- the task descriptor from current task.
M.running_task = false

local track_statistics_enabled

--- Debugging module.
-- The debug module allows to have a better look at the workings of a Lumen
-- application (see @{debug}).
M.debug = setmetatable({},
	{__index = function(t, k)
		if k=='track_statistics' then
			return track_statistics_enabled
		elseif k=='do_not_yield' then
			return do_not_yield 
		else
			return rawget(t, k)
		end
	end,
	
	__newindex = function(t,k,v)
		if k == 'track_statistics' then
			if v then --enable
				log('SCHED', 'INFO', 'Statistics tracking enabled')
				track_taskd_statistics = function (taskd, op)
					taskd.debug = taskd.debug or {
						runtime = 0,
						cycles = 0,
					}
					local wdebug = taskd.debug
					if op == 'in' then
						wdebug.last_start = M.get_time()
					elseif op == 'out' then
						wdebug.last_start = wdebug.last_start or M.get_time() --debugging itself, can lack last_start call
						wdebug.last_stop = M.get_time()
						wdebug.runtime = wdebug.runtime + wdebug.last_stop - wdebug.last_start
						wdebug.cycles = wdebug.cycles+1
					else
						error('Not supported action', 2)
					end
				end
				track_waitd_statistics = function(waitd, op)
					waitd.debug = waitd.debug or {
						triggered = 0,
						buffered = 0,
						missed = 0,
						dropped = 0,
						registered = 0,
					}
					local wdebug = waitd.debug
					assert(wdebug[op], 'Not supported action')
					wdebug[op] = wdebug[op] +1
				end
			else --disable
				log('SCHED', 'INFO', 'Statistics tracking disabled')
				track_taskd_statistics = function () end
				track_waitd_statistics = function () end
			end
			track_statistics_enabled = v
		elseif k=='do_not_yield' then
			do_not_yield = v
		else
			rawset(t, k, v)
		end
	end
})

M.debug.track_statistics = false

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
-- @field emitter optional, task originating the signal we wait for. If '*' or nil,
-- means anyone. It also can be an array of  tasks, in which case any of 
-- them is accepted as a source (see @{taskd}). To use separated emitter-events 
-- pairs, see the _multi_ attribute.
-- @field events optional, array with the events to wait. Can contain a '\*', 
-- or be '\*' instead of a table, to mark interest in any event. If nil, will
-- only return on timeout. To use separated emitter-events 
-- pairs, see the _multi_ attribute.
-- @field multi if more than a single emitter-events pair is needed, these can be 
-- placed in this array. Example:  
-- _multi={{events={'evA'}, emitter=emA}, {events={'evB'}, emitter=emB}}_
-- @field timeout optional, time to wait. nil or negative waits for ever.
-- @field buff_len Maximum length of the buffer. A buffer allows for storing
-- signals that arrived while the task is not blocked on the wait descriptor.
-- Whenever there is an attempt to insert in a full buffer, the dropped
-- flag is set. nil o 0 disables, negative means no length limit.
-- @field buff_mode Specifies how to behave when inserting in a full buffer.
-- 'drop first' means drop the oldest signals to make space. 'drop last'
-- or nil will skip the insertion in a full buffer.
-- @field dropped the scheduler will set this to true when dropping events
-- from the buffer. Can be reset by the user.
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

