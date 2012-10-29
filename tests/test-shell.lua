---
-- A test program for socketeer.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"
--require "log".setlevel('ALL')

require "strict"

local sched = require "sched"
local selector = require "tasks/selector".init({service='luasocket'})
--local selector = require "tasks/selector".init({service='nixio'})

local shell = require "tasks/shell"


sched.run(function()
	shell.init()
end)

sched.go()
