local M = {}

local weak_key = { __mode = 'k' }

--table containing all the registered tasks.
--tasks[task]=taskd
local tasks = {}

--table to keep track tasks waiting for signals
--waiting[event][emitter][task]=waitd
local waiting = setmetatable({}, weak_key)

--register of names for tasks
local tasknames = setmetatable({catalog = 'catalog'}, weak_key)

--closeset wait timeout during a scheduler step
local next_waketime


local step_task

--changes the status of a task from wainting to active (if everything is right)
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

local waked_up = {}
--will wake up and run all tasks waiting on a event
local emit_signal = function (emitter, event, ...)
	--print('emitsignal',emitter, waiting[event], event, ...)
	local walktasks = function (waiting, ...)
		for task, waitd in pairs(waiting) do
			--print('',':',task, waiting[task])
			if wake_up( task, waitd ) then 
				waked_up[task]=true 
			else
				waiting[task]=nil --lazy cleanup
			end
		end
		for task, _ in pairs(waked_up) do
			waked_up[task]=nil
			step_task(task, event, ...)
		end
	end
	local onevent=waiting[event]
	if onevent then 
		local waiting1, waiting2 = onevent[emitter], onevent['*']
		if waiting1 then walktasks(waiting1,...) end
		if waiting2 then walktasks(waiting2,...) end
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
			waiting[event][emitter] = waiting[event][emitter] 
						or setmetatable({}, { __mode = 'kv' })
			waiting[event][emitter][task]=waitd
		end
	end
end

local emit_timeout = function (task)
	--print('emittimeout',task)
	if wake_up( task ) then 
		step_task(task, nil, 'timeout')
	end
end

-----------------------------------------------------------------------------------------
--API calls

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
		local name, action, co = M.wait({emitter='catalog', timeout=timeout, events={name}})
		if name and action == 'registered' then 
			return co
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

M.waitd = function ( emitter, timeout, ... )
	return {emitter = emitter, timeout = timeout, events = {...}}
end

M.wait = function ( waitd )
	local my_task = coroutine.running()
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

M.clean_up = function()
	--clean up waiting table
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
	--active means they yielded, so they receive as parametets timing data 
	--see sched.yield()
	if ncycleready==1 then
		local available_time
		if next_waketime then 
			available_time=next_waketime-M.get_time() 
			if available_time<0 then available_time=0 end
		end
		step_task( cycleready[1], available_time, available_time )
		cycleready[1]=nil
	else
		for i, task in ipairs(cycleready) do
			cycleready[i]=nil
			local available_time
			if next_waketime then available_time=next_waketime-M.get_time() end
			step_task( task, 0, available_time )
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

