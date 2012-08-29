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

local normalize_pattern = function(service, pattern)
	if pattern=='*l' or pattern=='line' then
		if service=='socketeer' then return '*l' end
		if service=='nixiorator' then return 'line' end
	end
	if tonumber(pattern) and tonumber(pattern)>0 then
		return pattern
	end
	if not pattern or pattern == '*a' 
	or (tonumber(pattern) and tonumber(pattern)<=0) then
		if service=='socketeer' then return '*a' end
		if service=='nixiorator' then return nil end
	end
	print ('Could not normalize for', service, 'the pattern:', pattern)
end

M.init = function(conf)
	M.service=conf.service or 'socketeer'
	
	if M.service == 'nixiorator' then
		local nixio = require 'nixio'
		local nixiorator = require 'tasks/nixiorator'
		require 'nixio.util'
		M.nixiorator=nixiorator
		M.new_tcp_server = function(address, port, pattern, backlog)
			local skt = assert(nixio.bind(address, port, 'inet', 'stream'))
			nixiorator.register_server(skt, normalize_pattern('nixiorator', pattern), backlog)
			local sktd = new_socket({
				skt=skt,
				events = {accept=skt},
				task=nixiorator.task,
			})
			return sktd
		end
		M.new_tcp_client = function(address, port, locaddr, locport, pattern)
			--local skt=socket.bind(address, port, locaddr, locport)
			local skt = assert(nixio.bind(locaddr, locport or 0, 'inet', 'stream'))
			skt:connect(address,port)
			nixiorator.register_client(skt, normalize_pattern('nixiorator', pattern))
			local sktd = new_socket({
				skt=skt,
				events = {data=skt},
				task=nixiorator.task,
			})
			return sktd
		end
		M.new_udp = function(address, port, locaddr, locport, count)
			local skt = assert(nixio.bind(locaddr, locport or 0, 'inet', 'dgram'))
			skt:connect(address,port or 0)
			nixiorator.register_client(skt, count)
			local sktd = new_socket({
				skt=skt,
				events = {data=skt},
				task=nixiorator.task,
			})
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
		M.new_tcp_server = function(address, port, backlog, pattern)
			local skt=socket.bind(address, port, backlog)
			socketeer.register_server(skt, normalize_pattern('socketeer', pattern))
			local sktd = new_socket({
				skt=skt,
				events = {accept=skt},
				task=socketeer.task,
			})
			return sktd
		end
		M.new_tcp_client = function(address, port, locaddr, locport, pattern)
			local skt=socket.bind(address, port, locaddr, locport)
			socketeer.register_client(skt, normalize_pattern('socketeer', pattern))
			local sktd = new_socket({
				skt=skt,
				events = {data=skt},
				task=socketeer.task,
			})
			return sktd
		end
		M.new_udp = function(address, port, locaddr, locport, count)
			local skt=socket.udp()
			skt:setsockname(locaddr or '*', locport or 0)
			skt:setpeername(address or '*', port)
			socketeer.register_client(skt, count)
			local sktd = new_socket({
				skt=skt,
				events = {data=skt},
				task=socketeer.task,
			})
			return sktd
		end
		M.close = function(sktd)
			socketeer.unregister(sktd.skt)
			sktd.skt:close()
		end
		M.send_sync = function(sktd, data)
			local start, err,done=0,nil
			repeat
				start, err=sktd.skt:send(data,start+1)
				done = start==#data 
			until done or err
			return done, err, start
		end
		M.send = M.send_sync
		M.send_async = function(sktd, data)
			--TODO
			sktd.skt:send(data)
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


