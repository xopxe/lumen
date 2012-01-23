local sched=require 'sched'

print 'testing without pipe'
---[[
sched.run(function() 
	-- sender --
	local sender = sched.run(function() 
		for i=1, 10 do 
			print("sending", i)
			sched.signal('tick', i)
			sched.sleep (1) 
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
--]]

print '\ntesting with pipe'
sched.run(function() 
	-- sender --
	local sender = sched.run(function() 
		for i=1, 10 do 
			print("sending", i)
			sched.signal('tick', i)
			sched.sleep (1) 
		end
	end)

	sched.run(function() 
		-- receiver --
		local waitd= {emitter=sender, events={'tick'}, pipe_max_len=-1}
		while true do 
		
			--consume pipe'd signals
			while waitd.pipe and waitd.pipe:len()>0 do
				local  _, n = sched.wait(waitd)
				print("from pipe", n)
			end
			local  _, n = sched.wait(waitd)
			print("received", n)
			sched.sleep(3)
		end
	end)
end)
sched.go()
