--get locals for some useful things
local pairs, ipairs, next, coroutine, setmetatable, os
	= pairs, ipairs, next, coroutine, setmetatable, os

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

--register of names for tasks
--tasknames[co]=name
local tasknames = setmetatable({catalog = 'catalog'}, weak_key)

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
		if buff_len<0 or buff_len>buff:len() then
			buff:push({event, ...})
		end
		return true
	end
end

--iterates over a list of tasks sending them events. the iteration is split as the 
--list can change during iteration
local walktasks = function (waitingtasks, event, ...)
	local waked_up = {}
	for task, waitd in pairs(waitingtasks) do
		--print('',':',task, waitd, waiting[task])
		if wake_up( task, waitd ) then 
			waked_up[task]=true 
		else
			if not to_buffer(waitd, event, ...) then
				waiting[task]=nil --buferless, so lazy cleanup 
			end
		end
	end
	for task, _ in pairs(waked_up) do
		--waked_up[task]=nil
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

--resumes a task and handles finalization conditions
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


-----------------------------------------------------------------------------------------
--API calls

--number of new insertions in waiting[event] before triggering clean_up
M.to_clean_up = 1000

M.catalog = {}
M.catalog.register = function ( name )
	local co = coroutine.running()
	if tasknames[name] and tasknames[name] ~= co then
		return nil, 'used'
	end
	--print('catalog register', co, name)
	tasknames[name] = co
	emit_signal('catalog', name, 'registered', co)
	return true
end
M.catalog.waitfor = function ( name, timeout )
	local co = tasknames[name]
	--print('catalog query', coroutine.running(), name, timeout, co)
	if co then
		return co
	else 
		local _, action, received_co = M.wait({emitter='catalog', timeout=timeout, events={name}})
		if action == 'registered' then 
			return received_co
		else
			return nil, 'timeout'
		end
	end
end
M.catalog.tasks = function ()
	return function (_, v) return next(tasknames, v) end
end

M.run = function ( f, ... )
	local co = coroutine.create( f )
	--print('newtask', co, ...)
	tasks[co] = {status='ready'}
	step_task(co, ...)
	return co
end

M.sigrun = function ( f, waitd )
	local wrapper = function()
		while true do
			f(M.wait(waitd))
		end
	end
	return M.run( wrapper )
end

--sched.sigrunonce(f, emitter, [events...])
M.sigrunonce = function ( f, waitd )
	local wrapper = function()
		f(M.wait(waitd))
	end
	return M.run( wrapper )
end

M.kill = function ( t )
	t=t or coroutine.running()
	--print('kill',t,tasks[t])
	tasks[t].status = 'killed'
	tasks[t] = nil
	emit_signal(t, 'die', false, 'killed')
end

M.signal = function ( event, ... )
	local emitter=coroutine.running()
	emit_signal( emitter, event, ... )
end

M.waitd = function ( emitter, timeout, buff_len, ... )
	return {emitter = emitter,
		timeout = timeout,
		buff_len = buff_len,
		events = {...}
	}
end

M.wait = function ( waitd )
	local my_task = coroutine.running()
	
	--if there are buffered signals, service the first
	local buff = waitd.buff 
	if buff and buff:len()> 0 then
		local ret = buff:pop()
		return unpack(ret)
	end

	--block on signal
	register_signal( my_task, waitd )
	return coroutine.yield( my_task )
end

M.sleep = function (timeout)
--print('to sleep', timeout)
	M.wait({timeout=timeout})
end

M.yield = function ()
	local my_task = coroutine.running()
	return coroutine.yield( my_task )
end

M.idle = function (t)
	--print("Idling", t)
	if os.execute('sleep '..t) ~= 0 then os.exit() end
end

M.get_time = os.time

local cycleready, cycletimeout = {}, {}
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


M.go = function ()
	repeat
		local idle_time = M.step()
		if idle_time and idle_time>0 then
			M.idle( idle_time ) 
		end
	until not idle_time
end


return M

