--- A sample program that uses the scheduler to do stuff.

--require "strict"

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

local sched = require "sched"
local selector = require 'tasks/selector'.init({service='nixio'})
local proxy = require 'tasks/proxy'
local tasks = require 'catalog'.get_catalog('tasks')
require "log".setlevel('INFO')

sched.run(function()
	--tasks:register('main', sched.running_task)
	
	proxy.init({ip='*', port=2001})
	local remote_event = 'AAA'
	local remote_emitter= '*'
	local w = proxy.new_remote_waitd('127.0.0.1', 2002, {
		emitter={remote_emitter},
		events={remote_event},
		timeout=10,
	})
	sched.sigrun(w, function(...)
		print ('+', ...)
	end)
	
	
end)

sched.go()
