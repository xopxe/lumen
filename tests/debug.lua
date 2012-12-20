--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"
local tasks = require 'catalog'.get_catalog('tasks')
local selector = require "tasks/selector".init({service='nixio'})
--require "log".setlevel('NONE')

sched.debug.track_statistics = true

sched.run(function()
	tasks:register('main', sched.running_task)
	local A=sched.run(function()
		tasks:register('A', sched.running_task)
		print("A says: going to sleep couple seconds")
		sched.sleep(2)
		print("A says: emittig 'ev, data!'")
		sched.signal('ev', 'data!')
		print("A says: finishing")
	end)

	local waitd_ev = sched.new_waitd({emitter=A, events={'ev'}})
	
	sched.run(function()
		while true do
			print("====T",A.debug.runtime, A.debug.cycles)
			print("====W",waitd_ev.debug and waitd_ev.debug.triggered, 
				waitd_ev.debug and waitd_ev.debug.buffered, 
				waitd_ev.debug and waitd_ev.debug.missed, 
				waitd_ev.debug and waitd_ev.debug.dropped)
			sched.sleep(0.5)
		end
	end)

	local B=sched.run(function()
		tasks:register('B', sched.running_task)
		local A = tasks:waitfor('A')
		print ("B says: A found at", A)
		print ("B says: waiting for a 'die' from A")
		local _, _, status = sched.wait({emitter=A, events={sched.EVENT_DIE}})
		print ("B says: received a 'die' from A")
		print ("B says: going to error with message 'xxx'")
		error('xxx')
	end)

	print ("0 says: waiting for a 'ev' from A")
	local _, _, x = sched.wait(waitd_ev)
	print ("0 says: received a 'ev' from A, with a", x)
	print ("0 says: going to kill A")
	sched.kill(A)

	print("0 says: finishing, returning", x)
	return x
end)

sched.go()
