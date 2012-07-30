--- Lumen cooperative scheduler.
-- Lumen (Lua Multitasking Environment) is a simple environment 
-- for coroutine based multitasking. Consists of a signal scheduler, 
-- and that's it.
-- @module sched
-- @usage local sched = require 'sched'
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
local event_die = setmetatable({}, {__tostring=function() return "DIE" end})


--table containing all the registered tasks.
--tasks[taskd] = true
--taskd is {waketime=[number], waitingfor=[waitd], status='ready'|'paused'|'dead', co=coroutine}
local tasks = {}

--table to keep track tasks waiting for signals
--waiting[event][emitter][task]=waitd
--waitd as per reference
local waiting = setmetatable({}, weak_key)
local waiting_emitter_counter = 0 --for triggering cleanups

--closeset wait timeout during a scheduler step
local next_waketime

local step_task

--changes the status of a task from waiting to active (if everything is right)
local wake_up = function (taskd, waitd)
	if not taskd or taskd.status~='ready'
	or (waitd and waitd~=taskd.waitingfor) then
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
				log('SCHED', 'DETAIL', 'buffer from waitd  %s is dropping', tostring(waitd))
				waitd.dropped = true
				if waitd.buff_mode == 'drop_first' then
					for _ = 0, overpopulation do
						buff:popleft()
					end
					buff:pushright(table.pack(emitter, event, ...))
				else --'drop_last', default
					for _ = 1, overpopulation do
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
			waked_up[taskd] = waitd
		else
			bufferable[waitd] = true
		end
	end
	for _, waitd in pairs(waked_up) do
		bufferable[waitd] = nil
	end
	for waitd, _ in pairs(bufferable) do
		to_buffer(waitd, emitter, event, ...)
	end
	for taskd, _ in pairs(waked_up) do
		step_task(taskd, emitter, event, ...)
	end
end

--will wake up and run all tasks waiting on a event
local emit_signal = function (emitter, event, ...)
	--print('emitsignal',emitter, waiting[event], event, ...)
	local onevent=waiting[event]
	if onevent then
		local waiting1, waiting2 = onevent[emitter], onevent[ '*' ]
		if waiting1 then walktasks(waiting1, emitter, event, ...) end
		if waiting2 then walktasks(waiting2, emitter, event, ...) end
	end
	onevent=waiting['*']
	if onevent then
		local waiting1, waiting2 = onevent[emitter], onevent[ '*' ]
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
			if coroutine.status(taskd.co)=='dead' then
				taskd.status='dead'
				tasks[taskd]=nil
				if ok then 
					log('SCHED', 'INFO', '%s returning %d parameters', tostring(taskd), select('#',...))
					return emit_signal(taskd, event_die, true, ...)
				else
					log('SCHED', 'WARNING', '%s die on error, returning %d parameters: %s'
						, tostring(taskd), select('#',...), (...))
					return emit_signal(taskd, event_die, nil, ...)
				end
			end
		end
		local previous_task = M.running_task
		M.running_task = taskd
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
	local emitter, timeout, events = waitd.emitter, waitd.timeout, waitd.events
	if events=='*' then events={'*'} end
	taskd.waitingfor = waitd

	if timeout and timeout>=0 then
		local t = timeout + M.get_time()
		taskd.waketime = t
		next_waketime = next_waketime or t
		if t<next_waketime then next_waketime=t end
	end
	--print('registersignal', task, emitter, timeout, #events)
	log('SCHED', 'DETAIL', '%s registers waitd %s', tostring(taskd), tostring(waitd))

	local function register_emitter(etask)
		for _, event in ipairs(events) do
			--print('',':', event)
			waiting[event]=waiting[event] or setmetatable({}, weak_key)
			if not waiting[event][etask] then
				waiting[event][etask] = setmetatable({}, { __mode = 'kv' })
				waiting_emitter_counter = waiting_emitter_counter +1
			end
			waiting[event][etask][taskd]=waitd
		end
		if waiting_emitter_counter>M.to_clean_up then
			waiting_emitter_counter = 0
			clean_up()
		end
	end

	if events and emitter then
		if emitter=='*' or emitter.co then
			--single taskd parameter
			register_emitter(emitter)
		else
			--is a array of taskd
			for _, e in ipairs(emitter) do 
				register_emitter(e)
			end
		end
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
--- Create and run a task.
-- The task will emit a sched.EVENT\_DIE, true, params...
-- signal upon normal finalization, were params are the returns of f.
-- If there is a error, the task will emit a sched.EVENT\_DIE, false, err were
-- err is the error message.
-- @param f function for the task
-- @param ... parameters passed to f upon first run
-- @return task in the scheduler (see @{taskd}).
M.run = function ( f, ... )
	local co = coroutine.create( f )
	n_task = n_task + 1
	local taskd = setmetatable({
		status='ready',
		created_by=M.running_task,
		co=co,
		--for : calls
		kill=M.kill,
		set_pause=M.set_pause
	}, {
		__tostring=function() return 'TASK#'..n_task end,
	})
	tasks[taskd] = true
	log('SCHED', 'INFO', 'created %s from %s, with %d parameters', tostring(taskd), tostring(f), select('#', ...))
	step_task(taskd, ...)
	return taskd
end

--- Run a task that listens for a signal.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter.The signal will be provided as 
-- emitter, event, event_parameters, just as the result of a @{wait}
-- @return task in the scheduler (see @{taskd}).
-- @see wait
-- @see run
M.sigrun = function ( waitd, f )
	local wrapper = function()
		while true do
			f(M.wait(waitd))
		end
	end
	log('SCHED', 'INFO', 'sigrun wrapper %s created from %s and waitd %s', 
		tostring(wrapper), tostring(f), tostring(waitd))
	return M.run( wrapper )
end

--- Run a task that listens for a signal, once.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- emitter, event, event_parameters, just as the result of a @{wait}
-- @return task in the scheduler (see @{taskd}).
-- @see wait
-- @see run
M.sigrunonce = function ( waitd, f )
	local wrapper = function()
		f(M.wait(waitd))
	end
	log('SCHED', 'INFO', 'sigrunonce wrapper %s created from %s and waitd %s', 
		tostring(wrapper), tostring(f), tostring(waitd))
	return M.run( wrapper )
end

--- Finishes a task.
-- The killed task will emit a signal sched.EVENT\_DIE, false, 'killed'. Can be 
-- invoked as taskd:kill().
-- @param taskd task to terminate (see @{taskd}).
M.kill = function ( taskd )
	log('SCHED', 'INFO', 'killing %s from %s', tostring(taskd), tostring(M.running_task))
	taskd.status = 'dead'
	tasks[taskd] = nil
	emit_signal(taskd, event_die, false, 'killed')
end

--- Emit a signal.
-- @param event event of the signal. Can be of any type.
-- @param ... further parameters to be sent with the signal.
M.signal = function ( event, ... )
	log('SCHED', 'DETAIL', '%s emitting event %s with %d parameters', 
		tostring(M.running_task), tostring(event), select('#', ...))
	emit_signal( M.running_task, event, ... )
end

--- Wait for a signal.
-- Pauses the task until (one of) the specified signal(s) is available.
-- If there are signals in the buffer, will return the first immediately.
-- Otherwise will block the task until signal arrival, or a timeout.
-- @return On event returns emitter, event, event_parameters. On timeout
-- returns nil, 'timeout'
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
M.wait = function ( waitd )
	log('SCHED', 'DETAIL', '%s is waiting on waitd %s', tostring(M.running_task), tostring(waitd))
	
	--if there are buffered signals, service the first
	local buff = waitd.buff
	if buff and buff:len()> 0 then
		local ret = buff:popleft()
		--print('W from buff')
		return unpack(ret, 1, ret.n)
	end

	--block on signal
	--print('W+')
	register_signal( M.running_task, waitd )
	--print('W-')
	return coroutine.yield( M.running_task.co )
end

--- Feeds a wait descriptor to the scheduler.
-- Allows a buffering Wait Descriptor to start buffering before the task is ready
-- to wait().
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
M.wait_feed = function(waitd)
	local timeout=waitd.timeout
	waitd.timeout=0
	M.wait(waitd)
	waitd.timeout=timeout
end

--- Sleeps the task for t time units.
-- Time computed according to @\{get_time}.
-- @param timeout time to sleep
M.sleep = function (timeout)
--print('to sleep', timeout)
	M.wait({timeout=timeout})
end

--- Yields the execution of a task, as in cooperative multitasking.
M.yield = function ()
	return coroutine.yield( M.running_task.co )
end

--- Pause a task.
-- A paused task won't be scheduled for execution. If paused while waiting for a signal, 
-- won't respond to signals. Signals on unbuffered waitds will get lost. Task's buffered 
-- waitds will still buffer events. Can be invoked as taskd:set_pause(pause)
-- @param taskd Task to pause (see @{taskd}). 
-- @param pause mode, true to pause, false to unpause
-- @return true on success or nil, errormessage on failure
M.set_pause = function(taskd, pause)
	log('SCHED', 'INFO', '%s setting pause on %s to %s', tostring(M.running_task), tostring(taskd), tostring(pause))
	if taskd.status=='dead' then
		log('SCHED', 'ERROR', '%s toggling pause on dead %s', tostring(M.running_task), tostring(taskd))
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
	return true
end

--- Idle function.
-- Function called by the scheduler when there is
-- nothing else to do (e.g., all tasks are waiting for a signal).
-- This function should idle up to t time units. Replace with
-- whatever your app uses. LuaSocket's sleep works just fine.
-- It is allowed to idle for less than t; the empty function will
-- result in a busy wait. Defaults to execution of Linux's "sleep" command.
-- @param t time to idle
M.idle = function (t)
	--print("Idling", t)
	if os.execute('sleep '..t) ~= 0 then os.exit() end
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
	for taskd, _ in pairs (tasks) do
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
	repeat
		local idle_time = M.step()
		if idle_time and idle_time>0 then
			M.idle( idle_time )
		end
	until not idle_time
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
-- @field emitter optional, task originating the signal we wait for. If nil, will
-- only return on timeout. If '*', means anyone. I also can be an array of 
-- tasks, in which case any of them is accepted as a source (see @{taskd}).
-- @field timeout optional, time to wait. nil or negative waits for ever.
-- @field buff_len Maximum length of the buffer. A buffer allows for storing
-- signals that arrived while the task is not blocked on the wait descriptor.
-- Whenever there is an attempt to insert in a full buffer, the buffer.dropped
-- flag is set. nil o 0 disables, negative means no length limit.
-- @field buff_mode Specifies how to behave when inserting in a full buffer.
-- 'drop first' means drop the oldest signals to make space. 'drop last'
-- or nil will skip the insertion in a full buffer.
-- @field dropped the scheduler will set this to true when dropping events
-- from the buffer. Can be reset by the user.
-- @field events optional, array with the events to wait. Can contain a '\*', 
-- or be '\*' instead of a table, to mark interest in any event
-- @table waitd

------
-- Task descriptor.
-- Handler of a task.
-- @field status Status of the task, can be 'ready', 'paused' or 'dead'
-- @field waitingfor If the the task is waiting for a signal, this is the 
-- Wait Descriptor (see @{waitd})
-- @field waketime The time at which to task will be forced to wake-up (due
-- to a timeout on a wait)
-- @field co The coroutine of the task
-- @field kill Object oriented synonimous of sched.kill(taskd) (see @{kill})
-- @field set_pause Object oriented synonimous of sched.set_pause(taskd, pause)
-- (see @{set_pause})
-- @table taskd

return M

