---
-- A test program with two tasks, one emitting signals and the other accepting them.
--See how fast it can run.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"

-- task emits 5 signals and pauses itself.
local emitter_task=sched.run(function()
	while true do
		for i=1, 5 do
			sched.signal('ev', i)
			sched.sleep(1)
		end
		sched.running_task:set_pause(true)
	end
end)

-- if stop receiving signals, un-pause the emitter task.
sched.run(function()
	local waitd={emitter=emitter_task, timeout=5, events={'ev'}}
	while true do
		local _, _, s = sched.wait(waitd)
		if s then
			print(s)
		else
			print ('wakeup!')
			emitter_task:set_pause(false)
		end
	end
end)

sched.go()
