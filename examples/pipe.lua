---
-- A demonstration of pipes.

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua"

local sched=require 'lumen.sched'
--require "log".setlevel('ALL')
local pipe=require 'lumen.pipe'


local p=pipe.new(2)

--sched.sigrun({sched.EVENT_DIE}, function() print (debug.traceback()) end)

-- sender --
sched.run(function()
  --p=pipe.new(2)
	for i=1, 10 do
		print('W', assert(p:write(i)), i )
		--assert(p:write(i))
		sched.sleep(1)
	end
end)

--receiver
sched.run(function()
  --sched.sleep(1)
	while true do
		--sched.sleep(5)
		print("R1", assert(p:read()))
    sched.sleep(5)
	end
end)

sched.run(function()
  sched.sleep(1)
	while true do
		--sched.sleep(5)
		print("R2", assert(p:read()))
    --sched.sleep(5)
	end
end)

sched.loop()
