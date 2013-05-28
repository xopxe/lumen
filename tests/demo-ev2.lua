--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require 'sched'
local ev = require'ev'
local selector= require 'tasks/selector'.init()

local fake_task = sched.run(function()
	while true do 
		sched.yield()
	end
end)

-- build a timer event loop with a task defined as a callback
-- this will be the "user event" in this sample
function build_timer(loop, interval)
    local i = 0
    local function callback(loop, timer_event)
        print("EV emitting " .. tostring(i), "interval: " .. interval)
	sched.fake_signal(fake_task, 'ping!', i)
        i = i + 1
    end
    local timer = ev.Timer.new(callback, interval, interval)
    timer:start(loop)
    return timer
end

local receiver = sched.run(function()
	while true do
		local _, _, data = sched.wait({emitter=fake_task, events={'ping!'}})
		print ('EV received', data)
	end
end)

build_timer(ev.Loop.default, 2.0)
ev.Loop.default:loop()
--sched.go()
