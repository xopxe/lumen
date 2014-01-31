--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua;"

local sched = require "lumen.sched"
--require "lumen.log".setlevel('ALL')

sched.run(function()
	local A=sched.run(function()
		print("A says: going to sleep couple seconds")
		sched.sleep(2)
		print("A says: emittig 'ev, data!'")
		sched.signal('ev', 'data!')
		print("A says: going to sleep")
    sched.sleep(100)
	end)
	local B=sched.run(function()
		print ("B says: waiting for a A to die")
		sched.wait({A.EVENT_DIE})
		print ("B says: hear that A died")
		print ("B says: going to error with message 'xxx'")
		error('xxx')
	end)

	print ("0 says: waiting for a 'ev' from A")
	local _, x = sched.wait({'ev'})
	print ("0 says: received a 'ev' from A, with:", x)
	print ("0 says: going to kill A")
	sched.kill(A)

	print("0 says: finishing, returning", x)
	return x
end)

sched.loop()
