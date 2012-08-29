--- Task for accessing nixio library.
-- Nixiorator is a Lumen task that allow to interface with nixio.
-- @module nixiorator
-- @usage local nixiorator = require 'nixiorator'
-- @alias M

local sched = require("sched")
local catalog = require "catalog"
local service --socketeer or nixiorator

local M = {}

local new_socket = function(sktdesc)
	local sktd = setmetatable(sktdesc or {},{ __index=M })
	return sktd
end

M.init = function(conf)
	M.service=conf.service or 'socketeer'
	
	if M.service == 'nixiorator' then
	elseif conf.service == 'socketeer' then
		local socket=require 'socket'
		local socketeer=require 'socketeer'
		M.socketeer=socketeer
		M.new_tcp_server = function(pattern, address, port, backlog)
			local skt=socket.bind(address, port, backlog)
			socketeer.register_server(skt, pattern)
			local sktd = new_socket({
				skt=skt,
				signals = {accept=skt}
			})
			return sktd
		end
		M.new_tcp_client = function(pattern, address, port, locaddr, locport)
			local skt=socket.bind(address, port, locaddr, locport)
			socketeer.register_client(skt, pattern)
			local sktd = new_socket({
				skt=skt,
				signals = {data=skt}
			})
			return sktd
		end
		M.new_udp = function(pattern, address, port, locaddr, locport)
			local skt=socket.udp()
			skt:setpeername(address or '*', port)
			skt:setsockname(locaddr or '*', locport or 0)
			socketeer.register_client(skt, pattern)
			local sktd = new_socket({
				skt=skt,
				signals = {data=skt}
			})
			return sktd
		end
		M.close = function(sktd)
			socketeer.unregister(sktd.skt)
			sktd.skt:close()
		end
		M.send = function(sktd, data)
			local start, err,done=0,nil
			repeat
				start, err=sktd.skt:send(data,start+1)
				done = start==#data 
			until done or err
			return done, err, start
		end
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
end

return M


