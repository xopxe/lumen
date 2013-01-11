---
-- A test program for shell.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"
--require "log".setlevel('INFO')

require "strict"

local service = _G.arg [1] or 'luasocket'

local sched = require "sched"
--local selector = require "tasks/selector".init({service=service})
require "tasks/selector".init({service=service})

local shell = require "tasks/httpserver"


sched.run(function()
	local conf = {ip='127.0.0.1', port='8080'}
	shell.init(conf)
end)

sched.go()
