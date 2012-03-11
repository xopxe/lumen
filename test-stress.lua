---
-- A test program with two tasks, one emitting signals and the other accepting them. 
--See how fast it can run.

--require "strict"
--require "profiler"

local sched = require "sched"

local i=0

--profiler.start('profiler.out')

-- task emits as fast as it can (but also yields to be realistic)
local emitter_task=sched.run(function() 
	sched.catalog.register('A')
	while true do
		sched.signal('ev', 'data!')
		sched.yield()
	end
end)

-- task receives the messages and counts them
sched.run(function() 
	local waitd=sched.create_waitd(emitter_task, nil, nil, nil, 'ev')
	while true do
		--uncomment this to create huge ammount of waitds:
		--local waitd=sched.create_waitd(t1, nil, nil, nil,  'ev', 'ev'..i)
		sched.wait(waitd)
		i=i+1
		if i==1000000 then
			--profiler.stop() 
			os.exit() 
		end
	end
end)

sched.go()
