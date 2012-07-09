---
-- A demonstration of buffers.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched=require 'sched'

---[[
----------------------------------------------------------
print 'testing without buffer'
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
	local waitd = {emitter=sender, events={'tick'}}
	while true do
		local  _, _, n = sched.wait(waitd)
		print("received", n)
		sched.sleep(3)
	end
end)
sched.go()
----------------------------------------------------------
--]]

----------------------------------------------------------
print '\ntesting with buffer'
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
	local waitd = {emitter=sender, events={'tick'}, buff_len=-1}
	while true do
		--consume buffered signals
		while waitd.buff and waitd.buff:len()>0 do
			local  _, _, n = sched.wait(waitd)
			print("received (buff)", n)
		end
		print("waiting")
		local  _, _, n = sched.wait(waitd)
		print("received", n)
		sched.sleep(3)
	end
end)
sched.go()
----------------------------------------------------------

