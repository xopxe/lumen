--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require 'sched'
local ev = require'ev'

local function unloop_default_loop(_, _)
	ev.Loop.default:unloop()
end

---------------------------------------
-- replace sched's default get_time and idle with ev based timers
sched.get_time = function()
	return ev.Loop.default:update_now()
end 
sched.idle = function( t )
	local timer = ev.Timer.new(unloop_default_loop, t)
	timer:start(ev.Loop.default)
	ev.Loop.default:loop()
end

-- build a timer event loop with a task defined as a callback
-- this will be the "user event" in this sample
function build_timer(loop, interval)
    local i = 0
    local function callback(loop, timer_event)
        print("EV emitting " .. tostring(i), "interval: " .. interval)
	sched.signal('ping!', i)
        i = i + 1
    end
    local timer = ev.Timer.new(callback, interval, interval)
    timer:start(loop)
    return timer
end

---------------------------------------
-- a task for ev callbacks
local step = function ( t )
	if t==nil then --run to completion
		ev.Loop.default:loop()
	elseif t==0 then --return as soon as possible
		ev.Loop.default:unloop()
	else --run for t seconds
		local step_timer = ev.Timer.new(unloop_default_loop, t)
		step_timer:start(ev.Loop.default)
		ev.Loop.default:loop()
	end
end
local ev_task=sched.new_task( function ()
	--register ev events here
	build_timer(ev.Loop.default, 2.0)

	--main loop of the ev task
	while true do
		local t, _ = sched.yield()
		step( t )
	end
end)

sched.run(function()
	while true do 
		local _, _, data = sched.wait({emitter=ev_task, events={'ping!'}})
		print ('EV received', data)
	end
end)

ev_task:run()
sched.go()
