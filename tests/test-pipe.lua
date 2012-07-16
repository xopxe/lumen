---
-- A demonstration of pipes.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched=require 'sched'
--require "log".setlevel('ALL')
sched.pipes=require 'pipes'

sched.sigrun( print, {emitter='*', events={sched.EVENT_DIE}})

-- sender --
sched.run(function()
	local apipe=sched.pipes.new('apipe', 3)
	for i=1, 10 do
		print('writing', i )
		apipe.write(i)
		sched.sleep (1)
	end
end)

--receiver
sched.run(function()
	local apipe=sched.pipes.waitfor('apipe')
	while true do
		sched.sleep(3)
		local n = apipe.read()
		print("received", n)
	end
end)

sched.go()
