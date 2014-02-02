---
-- A test program that uses a mutex to control concurrent access
-- to a function.

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua"

--require "strict"
local lumen = require 'lumen'
local sched = lumen.sched
local mutex = lumen.mutex

local mx = mutex.new()

local function func(n)
	print('+'..n)
	sched.sleep(1)
	print('', '-'..n)
end

local critical=mx:synchronize(func)

---[[
print "non synchronized access"
sched.run(function()
	for i=1,5 do
		func('A')
		sched.wait()
	end
end)
sched.run(function()
	for i=1,5 do
		func('B')
		sched.wait()
	end
end)
sched.loop()
--]]

---[[
print "\nsynchronized access"
sched.run(function()
	for i=1,5 do
		critical('A')
		sched.wait()
	end
end)
sched.run(function()
	for i=1,5 do
		critical('B')
		sched.wait()
	end
end)
sched.loop()
--]]


