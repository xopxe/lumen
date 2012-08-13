--- A sample program that shows waiting on 
-- multiple emitters and events

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"

-- Watch for some task dying.
sched.new_sigrun_task({emitter='*', events={sched.EVENT_DIE}}, print):run()

-- 3 tasks, each emitting a combination of 2 events out of 3 possible,
-- and sending it's own number as data
local emitter1=sched.run(function()
	while true do
		sched.signal('evA', 1)
		sched.sleep(1)
		sched.signal('evB', 1)
		sched.sleep(1)
	end
end)
local emitter2=sched.run(function()
	while true do
		sched.signal('evA', 2)
		sched.sleep(1)
		sched.signal('evC', 2)
		sched.sleep(1)
	end
end)
local emitter3=sched.run(function()
	while true do
		sched.signal('evB', 3)
		sched.sleep(1)
		sched.signal('evC', 3)
		sched.sleep(1)
	end
end)

---[[
-- we are only interested in events B and C, emitted by tasks 2 and 3
sched.new_sigrun_task({emitter={emitter2, emitter3}, events={'evB', 'evC'}}, print):run()
--]]

--[[
-- we are interested in all events
sched.new_sigrun_task({emitter='*', events='*'}, print):run()
--]]

sched.go()
