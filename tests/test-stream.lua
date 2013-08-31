---
-- A demonstration of pipes.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched=require 'sched'
--require "log".setlevel('ALL')
local stream=require 'stream'

local astream=stream.new()

-- sender --
sched.run(function()
	for i=1, 10 do
		local s='*'..i..'*'
		print('writing', s)
		astream:write(tostring(s))
		sched.sleep (1)
	end
end)

--receiver
sched.run(function()
	while true do
		sched.sleep(3)
		print("received", astream:read())
	end
end)

sched.go()
