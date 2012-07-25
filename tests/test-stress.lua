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
	while true do
		sched.signal('ev', 'data!')
		sched.yield()
	end
end)

-- task receives the messages and counts them
sched.run(function()
	local waitd={emitter=emitter_task, events={'ev'}}
	while true do
		--uncomment this to create huge ammount of waitds:
		--local waitd={emitter=emitter_task, events={'ev','ev'..i}
		sched.wait(waitd)
		i=i+1
		if i==1000000 then
			--profiler.stop()
			os.exit()
		end
	end
end)

sched.go()
