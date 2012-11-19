--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"
local selector = require 'tasks/selector'.init({service='nixio'})
local proxy = require 'tasks/proxy'
local signals = require 'catalog'.get_catalog('signals')
require "log".setlevel('INFO')


sched.run(function()
	proxy.init({ip='*', port=2002})
	sched.run(function()
		local e = {aaa=true}
		signals:register('AAA',e)
		local i=0
		while true do
			i=i+1
			print (i)
			sched.signal(e, i)
			sched.sleep(1)
		end
		--tasks:register('main', sched.running_task)
	end)
	sched.run(function()
		local e = {bbb=true}
		signals:register('BBB',e)
		local i=0
		while true do
			i=i+1
			print (i)
			sched.signal(e, nil, i)
			sched.sleep(0.3)
		end
		--tasks:register('main', sched.running_task)
	end)

end)

sched.go()
