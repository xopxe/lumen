---
-- A demonstration of buffers.

local sched=require 'sched'

---[[
print 'testing without buffer'
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

print '\ntesting with buffer'
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
		local waitd= {emitter=sender, events={'tick'}, buff_len=-1}
		while true do 
		
			--consume buffered signals
			while waitd.buff and waitd.buff:len()>0 do
				local  _, n = sched.wait(waitd)
				print("received (buff)", n)
			end
			print("waiting")
			local  _, n = sched.wait(waitd)
			print("received", n)
			sched.sleep(3)
		end
	end)
end)
sched.go()
