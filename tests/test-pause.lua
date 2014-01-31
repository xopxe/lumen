---
-- A test program for pausing and resuming tasks

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua;"

local sched = require "lumen.sched"

-- task emits 5 signals and pauses itself.
local emitter_task=sched.new_task(function()
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
	local waitd={timeout=5, 'ev'}
	while true do
		local ev, s = sched.wait(waitd)
		if ev then
			print(s)
		else
			print ('wakeup!')
			emitter_task:set_pause(false)
		end
	end
end)

emitter_task:run()
sched.loop()
