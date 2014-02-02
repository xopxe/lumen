-- websocket support adaptded from lua-websocket (http://lipp.github.io/lua-websockets/)
-- depends on 
-- - luabitop or nixio (if not using Lua 5.2 nor luajit)

local http_util = require		'lumen.tasks.http-server.http-util'
local handshake = require		'lumen.tasks.http-server.websocket.handshake'
local sync 		= require 		'lumen.tasks.http-server.websocket.sync'


local websocket_protocols = {} --websocket_protocols[protocol] = handler
local websocket_clients = setmetatable({}, {__mode='k'})

local set_websocket_protocol = function ( protocol, handler, keep_clients )
	if websocket_protocols[protocol] then
		if not keep_clients then
			for client in pairs(websocket_clients[protocol]) do
				client:close()
			end
			websocket_clients[protocol]={}
		end
		websocket_protocols[protocol] = handler
	else
		websocket_clients[protocol] = websocket_clients[protocol] or {}
		websocket_protocols[protocol] = handler
	end
end

local handle_websocket_request = function (sktd, req_headers)
	local http_out_code, http_out_header, prot = handshake.accept_upgrade(req_headers, websocket_protocols)
	
	local response_header = http_util.build_http_header(http_out_code, http_out_header, nil)
	sktd.stream:set_timeout(-1, -1)
	sktd:send_sync(response_header)
	local ws = sync.create_ws(sktd)
	ws.state = 'OPEN'
	ws.is_server = true
	ws.on_close = function(self)
		websocket_clients[prot][self] = nil
	end
	ws.broadcast = function(_,...)
		for client in pairs(websocket_clients[prot]) do
			client:send(...)
		end
	end
	if prot then
		websocket_clients[prot][ws] = true
		websocket_protocols[prot](ws)
	end
end


return {
	handle_websocket_request = handle_websocket_request,
	set_websocket_protocol = set_websocket_protocol,
}
