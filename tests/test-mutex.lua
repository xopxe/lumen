---
-- A test program that uses a mutex to control concurrent access
-- to a function.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

--require "strict"

local sched = require "sched"
local mutex = require "mutex"()

local function func(n)
	print('+'..n)
	sched.sleep(1)
	print('', '-'..n)
end

local critical=mutex.synchronize(func)

---[[
print "non synchronized access"
sched.run(function()
	for i=1,5 do
		func('A')
		sched.yield()
	end
end)
sched.run(function()
	for i=1,5 do
		func('B')
		sched.yield()
	end
end)
sched.go()
--]]

---[[
print "\nsynchronized access"
sched.run(function()
	for i=1,5 do
		critical('A')
		sched.yield()
	end
end)
sched.run(function()
	for i=1,5 do
		critical('B')
		sched.yield()
	end
end)
sched.go()
--]]


