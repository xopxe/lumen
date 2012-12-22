--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"
local tasks = require 'catalog'.get_catalog('tasks')
local selector = require "tasks/selector".init({service='nixio'})
--require "log".setlevel('NONE')

sched.debug.track_statistics = true

local A=sched.run(function()
	tasks:register('A', sched.running_task)
	for i = 1, 10 do
		if i ==5 then sched.debug.do_not_yield = true end
		sched.sleep(0.5)
		sched.debug.do_not_yield = false
		sched.signal('ev', i)
	end
end)

sched.run(function()
	local waitd_ev = sched.new_waitd({emitter=A, events={'ev'}})
	while true do
		sched.wait(waitd_ev)
		print("====T",A.debug.runtime, A.debug.cycles)
		for k, v in pairs(waitd_ev.debug or {}) do
			print("====W",k,v)
		end
		--sched.sleep(1)
	end
end)

sched.go()
