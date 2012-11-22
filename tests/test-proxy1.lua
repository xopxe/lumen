--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"
local selector = require 'tasks/selector'.init({service='nixio'})
local proxy = require 'tasks/proxy'
local catalog_events = require 'catalog'.get_catalog('events')
require "log".setlevel('INFO')


sched.run(function()
	proxy.init({ip='*', port=2002})
	sched.run(function()
		local e = {aaa=1}
		--catalog_events:register('AAA',e)
		local i=0
		while true do
			i=i+1
			print ('a', i)
			if i==5 then catalog_events:register('AAA',e) end
			sched.signal(e, i)
			sched.sleep(1)
		end
	end)
	sched.run(function()
		local e = {bbb=1}
		catalog_events:register('BBB',e)
		local i=0
		while true do
			i=i+1
			print ('b', i)
			sched.signal(e, nil, i)
			sched.sleep(0.3)
		end
	end)

end)

sched.go()
