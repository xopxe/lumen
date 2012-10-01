--- Task for accessing nixio library.
-- Nixiorator is a Lumen task that allow to interface with nixio.
-- @module nixiorator
-- @usage local nixiorator = require 'nixiorator'
-- @alias M

local sched = require("sched")
local nixio = require 'nixio'
--local nixiorator = require 'tasks/nixiorator'
require 'nixio.util'

local floor = math.floor

local CHUNK_SIZE = 65536 --8192
local EAGAIN_WAIT = 0.001

local M = {}

-------------------
-- replace sched's default get_time and idle with nixio's
sched.get_time = function()
	local sec, usec = nixio.gettimeofday()
	return sec + usec/1000000
end
sched.idle = function (t)
	local sec = floor(t)
	local nsec = (t-sec)*1000000000
	nixio.nanosleep(sec, nsec)
end


local normalize_pattern = function( pattern)
	if pattern=='*l' or pattern=='line' then
		return 'line'
	end
	if tonumber(pattern) and tonumber(pattern)>0 then
		return pattern
	end
	if not pattern or pattern == '*a' 
	or (tonumber(pattern) and tonumber(pattern)<=0) then
		return nil
	end
	print ('Could not normalize the pattern:', pattern)
end
local new_socket = function(sktdesc)
	local sktd = setmetatable(sktdesc or {},{ __index=M })
	return sktd
end

local pollt={}
local unregister = function (fd)
	for k, v in ipairs(pollt) do
		if fd==v.fd then
			table.remove(pollt,k)
			return
		end
	end
end
local register_client = function (sktd)
	local function client_handler(polle)
		local skt=polle.fd
		local data,code,msg=polle.it()
		if data then
			if sktd.handler then sktd.handler(sktd, data) end
			sched.signal(skt, data)
		else
			--11: 'Resource temporarily unavailable'
			--print('!!!!!',data,code,msg)
			if (code==nil)
			or (code and code~=11) then
			    unregister(skt)
			    sched.signal(skt, nil, 'closed')
			end
		end
	end
	print ('BLOCKc', sktd.pattern)
	local polle={
		fd=sktd.skt,
		events=nixio.poll_flags("in", "pri"), --, "out"),
		block=normalize_pattern(sktd.pattern) or 8192,
		handler=client_handler
	}
	if polle.block=='line' then
		print ('PATTERN LINE')
		polle.it=polle.fd:linesource()
	else
		print ('PATTERN BLOCK', polle.block)
		polle.it=polle.fd:blocksource(polle.block)
	end
	polle.fd:setblocking(false)
	sktd.polle=polle
	pollt[#pollt+1]=polle
end
local register_server = function (sktd ) --, block, backlog)
	local function accept_handler(polle)
		print ('ACCEPTING')
		local skt, host, port = polle.fd:accept()
		local skt_table_client = {
			skt=skt,
			handler= sktd.handler,
			task=sktd.task,
			events={data=skt},
			pattern=sktd.pattern,
		}
		register_client(skt_table_client)
		local insktd = new_socket(skt_table_client)
		sched.signal(sktd.events.accepted, insktd)
	end
	print ('BLOCKs', sktd.pattern)
	local polle={
		fd=sktd.skt,
		events=nixio.poll_flags("in"),
		--block=normalize_pattern(sktd.pattern) or 8192,
		handler=accept_handler
	}
	polle.fd:listen(sktd.backlog or 32)
	pollt[#pollt+1]=polle
	sktd.polle=polle
end

local step = function (timeout)
	timeout=timeout or -1
	local stat= nixio.poll(pollt, floor(timeout*1000))
	if stat and tonumber(stat) > 0 then
		for _, polle in ipairs(pollt) do
			local revents = polle.revents 
			if revents and revents ~= 0 then
				local mode = nixio.poll_flags(revents)
				if mode['in'] then 
					polle:handler() 
				else
					--print ('?',polle.revents )
				end
			end
		end
	end

end
local task = sched.run( function ()
	while true do
		local t, _ = sched.yield()
		step( t )
	end
end)

-------------------


M.init = function(conf)
	conf=conf or {}
	M.service=conf.service or 'socketeer'
	
	--M.nixiorator=nixiorator
	M.new_tcp_server = function( skt_table )
		--address, port, pattern, backlog)
		skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport, 'inet', 'stream'))
		skt_table.events = {accepted=skt_table.skt }
		skt_table.task = task
		local sktd = new_socket(skt_table)
		register_server(sktd)
		return sktd
	end
	M.new_tcp_client = function(skt_table)
		--address, port, locaddr, locport, pattern)
		skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport or 0, 'inet', 'stream'))
		skt_table.events = {data=skt_table.skt}
		skt_table.task=task
		skt_table.skt:connect(skt_table.address,skt_table.port)
		register_client(skt_table)
		local sktd = new_socket(skt_table)
		return sktd
	end
	M.new_udp = function( skt_table )
		--address, port, locaddr, locport, count)
		skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport or 0, 'inet', 'dgram'))
		skt_table.events = {data=skt_table.skt}
		skt_table.task = task
		skt_table.skt:connect(skt_table.address,skt_table.port or 0)
		skt_table.block =  normalize_pattern(skt_table.pattern)
		register_client(skt_table)
		local sktd = new_socket(skt_table)
		return sktd
	end
	M.new_fd = function ( skt_table )
		skt_table.flags = skt_table.flags  or {}
		skt_table.skt = assert(nixio.open(skt_table.filename, nixio.open_flags(unpack(skt_table.flags))))
		skt_table.events = {data=skt_table.skt}
		skt_table.task = task
		register_client(skt_table)
		local sktd = new_socket(skt_table)
		return sktd
	end
	M.close = function(sktd)
		unregister(sktd.skt)
		sktd.skt:close()
	end
	M.send_sync = function(sktd, data)
		local written,_,_,writtenerr = sktd.skt:writeall(data)
		return written==#data, 'unknown error', writtenerr
	end
	M.send = M.send_sync
	M.send_async = function(sktd, data)
	
	--[[
		--TODO
		--sktd.skt:writeall(data)
		sched.run(function()
			local skt, block=sktd.skt, tonumber(sktd.pattern) or CHUNK_SIZE
			local total, start=0, 0
			repeat
				if block>#data-total then block=#data-total end
				local written, err =skt:write(data, start, block)
				if not written then 
					print ('!!!!', err)
					if err~=11 then return end
					sched.sleep(EAGAIN_WAIT)
				else
					total=total + written
					print ('+++++', block, written, total, #data)
					sched.yield()
				end
			until total >= #data 
		end)
	--]]
	end

	
	M.task=task
	
	--[[
	M.register_server = service.register_server
	M.register_client = service.register_client
	M.unregister = service.unregister
	--]]
	return M
end

return M


