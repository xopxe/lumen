local sched=require 'sched'

print 'testing without pipe'
sched.run(function() 
	-- sender --
	local sender = sched.run(function() 
		for i=1, 10 do 
			print("sending", i)
			sched.signal('tick', i)
			sched.sleep (2) 
		end
	end)

	sched.run(function() 
		-- receiver --
		while true do 
			local  _, n = sched.wait({emitter=sender, events={'tick'}})
			print("received", n)
			sched.sleep(3)
		end
	end)
end)

sched.go()

print 'testing with pipe'
