--require "strict"

--require "profiler"

local sched = require "sched"


local i=0

--profiler.start('profiler.out')

sched.run(function() 
	local t2=sched.run(function() 
		local t1 = sched.catalog.waitfor('A')
		local waitd=sched.waitd(t1, nil, 'ev')
		while true do
			--local waitd=sched.waitd(t1, nil, 'ev', 'ev'..i)
			--print(i)
			sched.wait(waitd)
			i=i+1
			if i==1000000 then
				--profiler.stop() 
				os.exit() 
			end
		end
	end)
	local t1=sched.run(function() 
		sched.catalog.register('A')
		while true do
			sched.signal('ev', 'data!')
			sched.yield()
		end
	end)
	--[[
	local t3=sched.run(function() 
		while true do
			sched.sleep(1)
			print('cleanup!')
			sched.clean_up()
		end
	end)
	--]]

end)

sched.go()
