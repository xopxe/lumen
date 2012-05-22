---
-- A demonstration of pipes.

local sched=require 'sched'

sched.run(function()
	-- sender --
	sched.run(function()
		local apipe=sched.pipes.new('apipe', 3)
		for i=1, 10 do
			print('writing', i )
			apipe.write(i)
			sched.sleep (1)
		end
	end)

	sched.run(function()
		local apipe=sched.pipes.waitfor('apipe')
		while true do
			sched.sleep(3)
			local n = apipe.read()
			print("received", n)
		end
	end)
end)
sched.go()
