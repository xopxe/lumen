---
-- A test program for the http server.

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua;"

require "lumen.log".setlevel('ALL', 'HTTP')
require "lumen.log".setlevel('ALL')

--require "strict"

local service = _G.arg [1] or 'luasocket'

local sched = require "lumen.sched"
require "lumen.tasks.selector".init({service=service})

local http_server = require "lumen.tasks.http-server"

http_server.serve_static_content_from_ram('/', '../tasks/http-server/www')
--http_server.serve_static_content_from_stream('/', '/home/xopxe')

if service=='nixio' then
	http_server.serve_static_content_from_stream('/docs/', '../docs')
else
	http_server.serve_static_content_from_ram('/docs/', '../docs')
end

http_server.set_websocket_protocol('lumen-shell-protocol', function(ws)
	local shell = require 'lumen.tasks.shell' 
	local sh = shell.new_shell()
	
	sched.run(function()
		while true do
			local message,opcode = ws:receive()
			if not message then
				ws:close()
				return
			end
			if opcode == ws.TEXT then
				sh.pipe_in:write('line', message)
			end
		end
	end):attach(sh.task)
	
	sched.run(function()
		while true do
			local _, prompt, out = sh.pipe_out:read()
			if out then 
				assert(ws:send(tostring(out)..'\r\n'))
			end
			if prompt then
				assert(ws:send(prompt))
			end
		end
	end)
end)

local conf = {
	ip='127.0.0.1', 
	port=8080,
	ws_enable = true,
	max_age = {ico=5, css=60},
}
http_server.init(conf)

print ('http server listening on', conf.ip, conf.port)
for _, h in pairs (http_server.request_handlers) do
	print ('url:', h.pattern)
end

sched.loop()
