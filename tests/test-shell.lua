---
-- A test program for shell.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"
--require "log".setlevel('INFO')

require "strict"

local service = arg [1] or 'luasocket'

local sched = require "sched"
--local selector = require "tasks/selector".init({service=service})
local selector = require "tasks/selector".init({service=service})

local shell = require "tasks/shell"


sched.run(function()
	local conf = {ip='127.0.0.1', port='2012'}
	shell.init(conf)
	print ('Shell started on '..tostring(conf.ip)..':'..tostring(conf.port))
end)

sched.go()
