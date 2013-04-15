---
-- A test program for the http server.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

require "log".setlevel('ALL', 'HTTP')

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

sched.sigrun({emitter='*', events={sched.EVENT_DIE}}, print)

http_server.set_websocket_protocol('dumb-increment-protocol', function(ws,...)
	local i = 0
	
	sched.run(function()
		while true do
			local message,opcode = assert(ws:receive())
			if not message then
				ws:close()
				return
			end
			if opcode == ws.TEXT then
				if message:match('reset') then
					i = 0
				end
			end
		end
	end)
	
	sched.run(function()
		while true do
			i=i+1
			assert(ws:send(i))
			sched.sleep(1)
		end
	end)
end)

http_server.set_websocket_protocol('lws-mirror-protocol', function(ws,...)
	sched.run(function()
		while true do
			local message,opcode = assert(ws:receive())
			if not message then
				ws:close()
				return
			end
			if opcode == ws.TEXT then
				ws:broadcast(message)
			end
		end
	end)
end)


local conf = {
	ip='127.0.0.1', 
	port=12345,
	ws_enable = true,
}
http_server.init(conf)

print ('http server listening on', conf.ip, conf.port)
for _, h in pairs (http_server.request_handlers) do
	print ('url:', h.pattern)
end

sched.go()
