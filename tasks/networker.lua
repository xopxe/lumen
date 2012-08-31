--- Task for accessing nixio library.
-- Nixiorator is a Lumen task that allow to interface with nixio.
-- @module nixiorator
-- @usage local nixiorator = require 'nixiorator'
-- @alias M

local sched = require("sched")

local M = {}

local new_socket = function(sktdesc)
	local sktd = setmetatable(sktdesc or {},{ __index=M })
	return sktd
end

local normalize_pattern = function(servicename, pattern)
	if pattern=='*l' or pattern=='line' then
		if servicename=='socketeer' then return '*l' end
		if servicename=='nixiorator' then return 'line' end
	end
	if tonumber(pattern) and tonumber(pattern)>0 then
		return pattern
	end
	if not pattern or pattern == '*a' 
	or (tonumber(pattern) and tonumber(pattern)<=0) then
		if servicename=='socketeer' then return '*a' end
		if servicename=='nixiorator' then return nil end
	end
	print ('Could not normalize for', servicename, 'the pattern:', pattern)
end

local build_tcp_accept_task = function (service, skt_table)
	return sched.run(function ()
		local waitd_accept = {emitter=service.task, events={skt_table.skt}}
		while true do
			local _, _, msg, inskt = sched.wait(waitd_accept)
			if msg=='accepted' then
				local skt_table_client = {
					skt=inskt,
					task=service.task,
					events={data=inskt}
				}
				local sktd = new_socket(skt_table_client)
				sched.signal(skt_table.events.accepted, sktd)
				if skt_table.handler then 
					sched.sigrun(
						{emitter=service.task, events={inskt}},
						function(_,_, data, err, part)
							skt_table.handler(sktd, data, err, part)
							if not data then sched.running_task:kill() end
						end
					)
				end
			end
		end
	end)
end

M.init = function(conf)
	conf=conf or {}
	M.service=conf.service or 'socketeer'
	
	if M.service == 'nixiorator' then
		local nixio = require 'nixio'
		local nixiorator = require 'tasks/nixiorator'
		require 'nixio.util'
		M.nixiorator=nixiorator
		M.new_tcp_server = function( skt_table )
			--address, port, pattern, backlog)
			skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport, 'inet', 'stream'))
			skt_table.events = {accepted='accepted'}
			skt_table.task = build_tcp_accept_task(nixiorator, skt_table)
			local sktd = new_socket(skt_table)
			nixiorator.register_server(skt_table.skt, normalize_pattern('nixiorator', skt_table.pattern), skt_table.backlog)
			return sktd
		end
		M.new_tcp_client = function(skt_table)
			--address, port, locaddr, locport, pattern)
			skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport or 0, 'inet', 'stream'))
			skt_table.events = {data=skt_table.skt}
			skt_table.task=nixiorator.task
			skt_table.skt:connect(skt_table.address,skt_table.port)
			local sktd = new_socket(skt_table)
			nixiorator.register_client(skt_table.skt, normalize_pattern('nixiorator', skt_table.pattern))
			return sktd
		end
		M.new_udp = function( skt_table )
		--address, port, locaddr, locport, count)
			skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport or 0, 'inet', 'dgram'))
			skt_table.events = {data=skt_table.skt}
			skt_table.task = nixiorator.task
			skt_table.skt:connect(skt_table.address,skt_table.port or 0)
			nixiorator.register_client(skt_table.skt, skt_table.count)
			local sktd = new_socket(skt_table)
			return sktd
		end
		M.close = function(sktd)
			nixiorator.unregister(sktd.skt)
			sktd.skt:close()
		end
		M.send_sync = function(sktd, data)
			local written,_,_,writtenerr = sktd.skt:writeall(data)
			return written==#data, 'unknown error', writtenerr
		end
		M.send = M.send_sync
		M.send_async = function(sktd, data)
			--TODO
			sktd.skt:writeall(data)
		end
	elseif conf.service == 'socketeer' then
		local socket = require 'socket'
		local socketeer = require 'tasks/socketeer'
		M.socketeer=socketeer
		M.new_tcp_server = function( skt_table )
			--address, port, backlog, pattern)
			skt_table.skt=assert(socket.bind(skt_table.locaddr, skt_table.locport, skt_table.backlog))
			skt_table.events = {accepted='accepted'}
			skt_table.task = build_tcp_accept_task(socketeer, skt_table)
			local sktd = new_socket(skt_table)
			socketeer.register_server(skt_table.skt, normalize_pattern('socketeer', skt_table.pattern))
			return sktd
		end
		M.new_tcp_client = function( skt_table )
			--address, port, locaddr, locport, pattern)
			skt_table.skt=assert(socket.connect(skt_table.address, skt_table.port, skt_table.locaddr, skt_table.locport))
			skt_table.events = {data=skt_table.skt}
			skt_table.task=socketeer.task
			local sktd = new_socket(skt_table)
			socketeer.register_client(skt_table.skt, normalize_pattern('socketeer', skt_table.pattern))
			return sktd
		end
		M.new_udp = function( skt_table )
		--address, port, locaddr, locport, count)
			skt_table.skt=socket.udp()
			skt_table.events = {data=skt_table.skt}
			skt_table.task=socketeer.task
			local sktd = new_socket(skt_table)
			skt_table.skt:setsockname(skt_table.locaddr or '*', skt_table.locport or 0)
			skt_table.skt:setpeername(skt_table.address or '*', skt_table.port)
			socketeer.register_client(skt_table.skt, skt_table.count)
			return sktd
		end
		M.close = function(sktd)
			socketeer.unregister(sktd.skt)
			sktd.skt:close()
		end
		M.send_sync = function(sktd, data)
			socketeer.send_sync(sktd.skt, data)
		end
		M.send = M.send_sync
		M.send_async = function(sktd, data)
			socketeer.send_async(sktd.skt, data)
		end
	else
		print('networker: unsuported service',conf.service)
		return
	end


	--[[
	M.register_server = service.register_server
	M.register_client = service.register_client
	M.unregister = service.unregister
	--]]
	return M
end

return M


