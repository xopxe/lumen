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

local http_server = require "tasks/http_server"
local static_files = require 'tasks/http_server/static_files'

static_files.serve_folder('/', '../tasks/http_server/www')
static_files.serve_folder('/docs/', '../docs')

local conf = {ip='127.0.0.1', port='8080'}
http_server.init(conf)

sched.go()
