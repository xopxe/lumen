---
-- A test program with two tasks, one emitting signals and the other accepting them.
--See how fast it can run.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

--require "strict"
--require "profiler"

local sched = require "sched"

local i=0

--profiler.start('profiler.out')

-- task emits as fast as it can (but also yields to be realistic)
local emitter_task=sched.run(function()
	local i=0
	while true do
		i=i+1
		sched.signal('ev', i)
		sched.sleep(1)
	end
end)

-- task receives the messages and counts them
sched.run(function()
	local waitd={emitter=emitter_task, timeout=5, events={'ev'}}
	while true do
		for i=1, 5 do
			local _, _, s = sched.wait(waitd)
			print(s)
			if not s then emitter_task:set_pause(false) end
		end
		emitter_task:set_pause(true)
	end
end)

sched.go()
