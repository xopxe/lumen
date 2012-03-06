--- Lumen cooperative scheduler.
-- Lumen (Lua Multitasking Environment) is a simple environment 
-- for coroutine based multitasking. Consists of a signal scheduler, 
-- and that's it.
-- @module sched
-- @usage local sched = require 'sched'
-- @alias M

--get locals for some useful things
local pairs, ipairs, next, coroutine, setmetatable, os
	= pairs, ipairs, next, coroutine, setmetatable, os
	
table.pack=table.pack or function (...)
	return {n=select('#',...),...}
end

local M = {}

local queue = require 'queue'

local weak_key = { __mode = 'k' }

--table containing all the registered tasks.
--tasks[task]=taskd
--taskd is {waketime=[number], waitingfor=[waitd], status='ready'|'killed'}
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
local wake_up = function (task, waitd)
	local taskd = tasks[task]
	if not taskd or taskd.status~='ready' 
	or (waitd and waitd~=taskd.waitingfor) then 
		return false 
	end

	taskd.waketime = nil
	taskd.waitingfor = nil
	return true
end

local to_buffer = function (waitd, event, ...)
	local buff_len = waitd.buff_len
	--print('add to buffer',buff_len,waitd, event, ...)
	if buff_len and buff_len~=0 then 
		waitd.buff = waitd.buff or queue:new()
		local buff=waitd.buff
		if buff_len<0 then 
			buff:pushright(table.pack(event, ...))
		else
			local overpopulation = buff:len()-buff_len
			--print('OP', buff_len,buff:len(),overpopulation)
			if overpopulation<0 then
				buff:pushright(table.pack(event, ...))
			else
				buff.dropped = true
				if waitd.buff_mode == 'drop_first' then
					for _ = 0, overpopulation do
						buff:popleft()
					end
					buff:pushright(table.pack(event, ...))
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
local walktasks = function (waitingtasks, event, ...)
	local waked_up, bufferable = {}, {}
	for task, waitd in pairs(waitingtasks) do
		--print('',':',task, waitd, waiting[task])
		if wake_up( task, waitd ) then 
			waked_up[task]=waitd
		else
			bufferable[waitd] = true
		end
	end
	for _, waitd in pairs(waked_up) do
		bufferable[waitd]=nil
	end
	for waitd, _ in pairs(bufferable) do
		to_buffer(waitd, event, ...)
	end
	for task, _ in pairs(waked_up) do
		step_task(task, event, ...)
	end
end

--will wake up and run all tasks waiting on a event
local emit_signal = function (emitter, event, ...)
	--print('emitsignal',emitter, waiting[event], event, ...)
	local onevent=waiting[event]
	if onevent then 
		local waiting1, waiting2 = onevent[emitter], onevent[ '*' ]
		if waiting1 then walktasks(waiting1, event, ...) end
		if waiting2 then walktasks(waiting2, event, ...) end
	end
end

---
-- resumes a task and handles finalization conditions
-- @local 
step_task = function(t, ...)
	local ok, ret = coroutine.resume(t, ...)
	if tasks[t] and coroutine.status(t)=='dead' then
		tasks[t]=nil
		if ok then 
			--print('task return:', t, ret)
			return emit_signal(t, 'die', true, ret) 
		else
			--print('task error:', t, ret)
			return emit_signal(t, 'die', false, ret)
		end
	end
end


local clean_up = function()
	--clean up waiting table
	--print("cleanup!")
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
local register_signal = function(task, waitd)
	local emitter, timeout, events = waitd.emitter, waitd.timeout, waitd.events
	local taskd = tasks[task]
	taskd.waitingfor = waitd

	if timeout and timeout>=0 then 
		local t = timeout + M.get_time() 
		taskd.waketime = t
		next_waketime = next_waketime or t
		if t<next_waketime then next_waketime=t end
	end
	--print('registersignal', task, emitter, timeout, #events)

	if events and emitter then 
		for _, event in ipairs(events) do
			--print('',':', event)
			waiting[event]=waiting[event] or setmetatable({}, weak_key)
			if not waiting[event][emitter] then
				waiting[event][emitter] = setmetatable({}, { __mode = 'kv' })
				waiting_emitter_counter = waiting_emitter_counter +1
			end
			waiting[event][emitter][task]=waitd
		end
		if waiting_emitter_counter>M.to_clean_up then
			waiting_emitter_counter = 0
			clean_up()
		end
	end
end

local emit_timeout = function (task)
	--print('emittimeout',task)
	if wake_up( task ) then 
		step_task(task, nil, 'timeout')
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


--- Catalog operations.
-- The catalog is used to give tasks names, and then query them
-- @section catalog

M.catalog = {}

local CATALOG_EV = {} --singleton origin for catalog events
--register of names for tasks
--tasknames[co]=name
local tasknames = setmetatable({CATALOG_EV = CATALOG_EV}, weak_key)

--- Register a name for the current task
-- @param name a name for the task
-- @return true is successful; nil, 'used' if the name is already used by another task.
M.catalog.register = function ( name )
	local co = coroutine.running()
	if tasknames[name] and tasknames[name] ~= co then
		return nil, 'used'
	end
	--print('catalog register', co, name)
	tasknames[name] = co
	emit_signal(CATALOG_EV, name, 'registered', co)
	return true
end

--- Find task with a given name.
-- Can wait up to timeout until it appears.
-- @param name name of the task
-- @param timeout time to wait. nil or negative waits for ever.
-- @return the task if successful; on timeout expiration returns nil, 'timeout'.
M.catalog.waitfor = function ( name, timeout )
	local co = tasknames[name]
	--print('catalog query', coroutine.running(), name, timeout, co)
	if co then
		return co
	else 
		local _, action, received_co = M.wait({emitter=CATALOG_EV, timeout=timeout, events={name}})
		if action == 'registered' then 
			return received_co
		else
			return nil, 'timeout'
		end
	end
end

--- Iterator for registered tasks.
-- @return iterator
-- @usage for name, task in sched.catalog.tasks() do 
--	print(name, task) 
--end
M.catalog.iterator = function ()
	return function (_, v) return next(tasknames, v) end
end


--- Named pipes.
-- Pipes allow can be used to communicate tasks. Unlike plain signals,
-- no message can get lost: writers get blocked when the pipe is full
-- @section pipes

M.pipes={}

------
-- Pipe descriptor.
-- A named pipe.
-- @field write writes to the pipe. Will block when writing to a full pipe. 
-- Return true on success, nil, 'timeout' on timeout
-- @field read reads from the pipe. Will block on a empty pipe. 
-- Return data if available, nil, 'timeout' on timeout
-- @table piped

local PIPES_EV={} --singleton origin for pipes events
tasknames[PIPES_EV]=PIPES_EV
--register of pipes
local pipes =  setmetatable({}, { __mode = 'kv' })

--- Create a new pipe.
-- @param name a name for the pipe
-- @param size maximum number of signals in the pipe
-- @param timeout timeout for blocking on pipe operations. -1 or nil disable 
-- timeout
-- @return the pipe descriptor (see @{piped}) on success, or nil,'exists' if a pipe
-- with the given name already exists

M.pipes.new = function(name, size, timeout)
	if pipes[name] then
		return nil, 'exists'
	end
	local piped = {}
	local pipe_enable = {} --singleton event for pipe control
	local pipe_data = {} --singleton event for pipe data
	local buff_data = queue:new()
	local waitd_data={emitter='*', buff_len=size+1, timeout=timeout, events = {pipe_data}, buff = buff_data}
	M.wait_feed(waitd_data)
	local waitd_enable={emitter='*', buff_len=1, timeout=timeout, buff_mode='drop_last', events = {pipe_enable}, buff = queue:new()}
	local piped_read = function ()
		local function format_signal(ev, ...)
			if not ev then return nil, 'timeout' end
			return ...
		end
		if buff_data:len() == size-1 then
			M.signal(pipe_enable)
		end
		return format_signal(M.wait(waitd_data))
	end
	local piped_write = function (...)
		if buff_data:len() >= size then
			local ret, _ = M.wait(waitd_enable)
			if not ret then return nil, 'timeout' end
		end
		M.signal(pipe_data, ...) --table.pack(...))
		return true
	end
	--first run is a initialization, replaces functions with proper code
	piped.read = function ()
		piped.read = piped_read
		piped.write = piped_write
		M.signal(pipe_enable)
		return piped_read()
	end
	--blocks on no-readers, replaced in piped.read
	piped.write = function (...)
		local ret, _ = M.wait(waitd_enable)
		if not ret then return nil, 'timeout' end
		M.signal(pipe_data, ...)
		return true
	end
	
	pipes[name]=piped
	emit_signal(PIPES_EV, name, 'created', piped)
	return piped
end

--- Look for a pipe with the given name.
-- Can wait up to timeout until it appears.
-- @param name of the pipe to get
-- @param timeout max. time time to wait. -1 or nil disables timeout.
M.pipes.waitfor = function(name, timeout)
	local piped = pipes[name]
	if piped then 
		return piped
	else
		local _, action, received_piped= M.wait({emitter=PIPES_EV, timeout=timeout, events={name}})
		if action == 'created' then 
			return received_piped
		else
			return nil, 'timeout'
		end
	end
end

--- Iterator for all pipes
-- @return iterator
-- @usage for name, pipe in sched.pipes.tasks() do 
--	print(name, pipe) 
--end
M.pipes.iterator = function ()
	return function (_, v) return next(pipes, v) end
end


--- Scheduler operations.
-- Main API of the scheduler.
-- @section scheduler

--- control memory collection.
-- number of new insertions in waiting[event] before triggering clean_up.
-- Defaults to 1000
M.to_clean_up = 1000

--- Create and run a task.
-- The task will emit a 'die', true, params... 
-- signal upon normal finalization, were params are the returns of f. 
-- If there is a error, the task will emit a 'die', false, err were 
-- err is the error message.
-- @param f function for the task
-- @param ... parameters passed to f upon first run
-- @return task in the scheduler.
M.run = function ( f, ... )
	local co = coroutine.create( f )
	--print('newtask', co, ...)
	tasks[co] = {status='ready'}
	step_task(co, ...)
	return co
end

--- Run a task on a signal.
-- @param f function for the task
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @return task in the scheduler.
-- @see wait
-- @see run
M.sigrun = function ( f, waitd )
	local wrapper = function()
		while true do
			f(M.wait(waitd))
		end
	end
	return M.run( wrapper )
end

--- Run a task on a signal, once.
-- @param f function for the task
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
-- @return task in the scheduler.
-- @see wait
-- @see run
M.sigrunonce = function ( f, waitd )
	local wrapper = function()
		f(M.wait(waitd))
	end
	return M.run( wrapper )
end

--- Finishes a task.
-- The killed task will emit a signal 'die', false, 'killed'
-- @param t task to terminate. If nil, terminates the current task.
M.kill = function ( t )
	t=t or coroutine.running()
	--print('kill',t,tasks[t])
	tasks[t].status = 'killed'
	tasks[t] = nil
	emit_signal(t, 'die', false, 'killed')
end

--- Emit a signal.
-- @param event event of the signal. Can be of any type.
-- @param ... further parameters to be sent with the signal.
M.signal = function ( event, ... )
	local emitter=coroutine.running()
	emit_signal( emitter, event, ... )
end

M.create_waitd = function ( emitter, timeout, buff_len, buff_mode, ... )
	return {emitter = emitter,
		timeout = timeout,
		buff_len = buff_len,
		buff_mode = buff_mode,
		events = {...}
	}
end

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
-- Can use @\{create_waitd} to create this table.
-- @field emitter optional, task originating the signal we wait for. If nil, will
-- only return on timeout. If '*', means anyone.
-- @field timeout optional, time to wait. nil or negative waits for ever.
-- @field buff_len Maximum length of the buffer. A buffer allows for storing 
-- signals that arrived while the task is not blocked on the wait descriptor. 
-- Whenever there is an attempt to insert in a full buffer, the buffer.dropped 
-- flag is set. nil o 0 disables, negative means no length limit.
-- @field buff_mode: Specifies how to behave when inserting in a full buffer. 
-- 'drop first' means drop the oldest signals to make space. 'drop last' 
-- or nil will skip the insertion in a full buffer. 
-- @field events optional, array with the events to wait.
-- @table waitd

--- Wait for a signal.
-- Pauses the task until (one of) the specified signal(s) is available. 
-- If there are signals in the buffer, will return the first immediately. 
-- Otherwise will block the task until signal arrival, or a timeout.
-- @param waitd a Wait Descriptor for the signal (see @{waitd})
M.wait = function ( waitd )
	local my_task = coroutine.running()
	
	--if there are buffered signals, service the first
	local buff = waitd.buff 
	if buff and buff:len()> 0 then
		local ret = buff:popleft()
		--print('W from buff')
		return unpack(ret, 1, ret.n)
	end

	--block on signal
	--print('W+')
	register_signal( my_task, waitd )
	--print('W-')
	return coroutine.yield( my_task )
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
	local my_task = coroutine.running()
	return coroutine.yield( my_task )
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
	for task, taskd in pairs (tasks) do
		if taskd.waitingfor then 
			local waketime = taskd.waketime
			if waketime then 
				next_waketime = next_waketime or waketime
				if waketime <= M.get_time() then
					cycletimeout[#cycletimeout+1]=task
				end
				if waketime < next_waketime then
					next_waketime = waketime
				end
			end
		elseif taskd.status=='ready' then
			cycleready[#cycleready+1]=task
		end
	end
	local ncycleready,ncycletimeout = #cycleready, #cycletimeout

	--wake timeouted tasks
	for i, task in ipairs(cycletimeout) do
		cycletimeout[i]=nil
		emit_timeout( task )
	end

	--step active tasks (keeping track of impending timeouts)
	--active means they yielded, so they receive as parameters timing data 
	--see sched.yield()
	if ncycleready==1 then
		local available_time = compute_available_time()
		step_task( cycleready[1], available_time, available_time )
		cycleready[1]=nil
	else
		for i, task in ipairs(cycleready) do
			local available_time = compute_available_time()
			step_task( task, 0, available_time )
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


return M

