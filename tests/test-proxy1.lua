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
	local e = {aaa=true}
	signals:register('AAA',e)
	proxy.init({ip='*', port=2002})
	local i=0
	while true do
		i=i+1
		print (i)
		sched.signal(e, nil, i)
		sched.sleep(1)
	end
	--tasks:register('main', sched.running_task)
	
end)

sched.go()
