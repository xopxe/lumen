--- A sample program that uses the scheduler to do stuff.

require "strict"

local log = require "log/init"
log.setlevel('ALL')

local sched = require "sched"

--sched.sigrun( print, {emitter='*', events={sched.EVENT_DIE}})
--print("---------------",sched.run(function() return "AAAAAA", "BBBBBB" end))
--os.exit()

sched.run(function() 
	sched.catalog.register('main')
	local A=sched.run(function() 
		sched.catalog.register('A')
		sched.sleep(2)
		print("A says: emittig 'ev, data!'")
		sched.signal('ev', 'data!', 'moredata!')
		print("A says: finishing")
	end)
	local B=sched.run(function() 
		sched.catalog.register('B')
		local A = sched.catalog.waitfor('A')
		print ("B says: A found at", A)
		print ("B says: waiting for a 'die' from A")
		local _, status = sched.wait({emitter=A, events={sched.EVENT_DIE}})
		print ("B says: received a 'die' from A")
		print ("B says: going to error with message 'xxx'")
		error('xxx')
	end)

	print ("0 says: waiting for a 'ev' from A")
	local _, x, y = sched.wait({emitter=A, events={'ev'}})
	print ("0 says: received a 'ev' from A, with a", x, y)
	print ("0 says: going to kill A")
	sched.kill(A)

	print("0 says: finishing, returning", x)
	return x
end)


sched.go()
