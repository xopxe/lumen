---
-- A test program for shell.

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua;"
--require "log".setlevel('ALL')

local service = 'luasocket' --arg [1] or 'luasocket'

local sched = require "lumen.sched"
--local selector = require "tasks/selector".init({service=service})
local selector = require "lumen.tasks.selector".init({service=service})

local shell = require "lumen.tasks.shell"

--sched.sigrun({sched.EVENT_ANY}, function(...) print('!', ...) end )
sched.sigrun({sched.EVENT_DIE, sched.EVENT_FINISH}, function(...) print('!', ...) end )

sched.run(function()
	local conf = {ip='127.0.0.1', port='2012'}
	shell.init(conf)
	print ('Shell started on '..tostring(conf.ip)..':'..tostring(conf.port))
end)

sched.loop()
