---
-- A demonstration of pipes.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched=require 'sched'
--require "log".setlevel('ALL')
local pipes=require 'pipes'
local catalog_pipes = require 'catalog'.get_catalog('pipes')

-- sender --
sched.run(function()
	local apipe=pipes.new(3)
	catalog_pipes:register('apipe', apipe)
	for i=1, 10 do
		print('writing', i )
		apipe:write(i)
		sched.sleep (1)
	end
end)

--receiver
sched.run(function()
	local apipe=catalog_pipes:waitfor('apipe')
	while true do
		sched.sleep(3)
		local _, n = apipe:read()
		print("received", n)
	end
end)

sched.go()
