--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua;"

local sched = require "lumen.sched"
local selector = require 'lumen.tasks.selector'.init({service='nixio'})
local proxy = require 'lumen.tasks.proxy'
require "lumen.log".setlevel('INFO', 'PROXY')

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

sched.loop()
