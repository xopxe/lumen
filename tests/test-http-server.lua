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

http_server.serve_static_content_from_ram('/', '../tasks/http-server/www')
if service=='nixio' then
	http_server.serve_static_content_from_stream('/docs/', '../docs')
else
	http_server.serve_static_content_from_ram('/docs/', '../docs')
end

local conf = {ip='127.0.0.1', port='8080'}
http_server.init(conf)

print ('http server listening on', conf.ip, conf.port)
for _, h in pairs (http_server.request_handlers) do
	print ('url:', h.pattern)
end

sched.go()
