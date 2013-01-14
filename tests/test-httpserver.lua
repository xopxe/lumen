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

local httpserver = require "tasks/httpserver"
local static_files = require 'tasks/httpserver/static_files'

static_files.serve_folder('/', '../tasks/httpserver/www')
static_files.serve_folder('/docs/', '../docs')

sched.run(function()
	local conf = {ip='127.0.0.1', port='8080'}
	httpserver.init(conf)
end)

sched.go()
