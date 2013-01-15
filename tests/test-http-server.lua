---
-- A test program for the http server.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

--require "log".setlevel('INFO')

require "strict"

local service = _G.arg [1] or 'luasocket'

local sched = require "sched"
require "tasks/selector".init({service=service})

local http_server = require "tasks/http-server"

http_server.serve_static_content('/', '../tasks/http-server/www')
http_server.serve_static_content('/docs/', '../docs')

local conf = {ip='127.0.0.1', port='8080'}
http_server.init(conf)

sched.go()
