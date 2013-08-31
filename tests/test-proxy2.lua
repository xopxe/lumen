--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"
local selector = require 'tasks/selector'.init({service='nixio'})
local proxy = require 'tasks/proxy'
require "log".setlevel('INFO', 'PROXY')

sched.run(function()
	--tasks:register('main', sched.running_task)
	
	---[[
	proxy.init({ip='*', port=2001, encoder='bencode'})
	local w = proxy.new_remote_waitd('127.0.0.1', 2002, {
		events={'AAA', 'BBB'},
		--timeout=5,
		name_timeout = 30,
	})
  
	sched.sigrun(w, function(_, arrived,...)
			print ('Arrived:', arrived, ...)
	end)
	--]]

	--[[
	local w = proxy.new_remote_waitd('127.0.0.1', 2002, {
		emitter={'*'},
		events={'BBB'},
		--timeout=10,
		name_timeout = 30,
	})
	sched.sigrun(w, function(_,arrived,...)
		print ('+B', arrived~=nil, ...)
	end)
	--]]
	
end)

sched.go()
