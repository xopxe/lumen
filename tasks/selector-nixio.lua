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

local pollt={}
local unregister = function (fd)
	for k, v in ipairs(pollt) do
		if fd==v.fd then
			table.remove(pollt,k)
			return
		end
	end
end
local function client(polle)
	local skt=polle.fd
	local data,code,msg=polle.it()
	if data then
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
local register_client = function (fd, block)
	local polle={
		fd=fd,
		events=nixio.poll_flags("in", "pri"),
		block=block or 8192,
		handler=client
	}
	if polle.block=='line' then
		polle.it=fd:linesource()
	else
		polle.it=fd:blocksource(polle.block)
	end
	pollt[#pollt+1]=polle
	return polle
end
local function accept(polle)
	local skt, host, port = polle.fd:accept()
	skt:setblocking(true)

	register_client(skt, polle.block)
	sched.signal(polle.fd, 'accepted', skt)
end
local register_server = function (skt, block, backlog)
	local polle={
		fd=skt,
		events=nixio.poll_flags("in"),
		block=block or 8192,
		handler=accept
	}
	skt:listen(backlog or 32)
	pollt[#pollt+1]=polle
	return polle
end
local step = function (timeout)
	timeout=timeout or -1
	local stat= nixio.poll(pollt, floor(timeout*1000))
	if stat and tonumber(stat) > 0 then
		for _, polle in ipairs(pollt) do
			if polle.revents and polle.revents ~= 0 then
				polle:handler()
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


local new_socket = function(sktdesc)
	local sktd = setmetatable(sktdesc or {},{ __index=M })
	return sktd
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

local build_tcp_accept_task = function (skt_table)
	return sched.run(function ()
		local waitd_accept = {emitter=task, events={skt_table.skt}}
		while true do
			local _, _, msg, inskt = sched.wait(waitd_accept)
			if msg=='accepted' then
				local skt_table_client = {
					skt=inskt,
					task=task,
					events={data=inskt}
				}
				local sktd = new_socket(skt_table_client)
				sched.signal(skt_table.events.accepted, sktd)
				if skt_table.handler then 
					sched.sigrun(
						{emitter=task, events={inskt}},
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
	
	--M.nixiorator=nixiorator
	M.new_tcp_server = function( skt_table )
		--address, port, pattern, backlog)
		skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport, 'inet', 'stream'))
		skt_table.events = {accepted='accepted'}
		skt_table.task = build_tcp_accept_task(skt_table)
		local sktd = new_socket(skt_table)
		register_server(skt_table.skt, normalize_pattern(skt_table.pattern), skt_table.backlog)
		return sktd
	end
	M.new_tcp_client = function(skt_table)
		--address, port, locaddr, locport, pattern)
		skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport or 0, 'inet', 'stream'))
		skt_table.events = {data=skt_table.skt}
		skt_table.task=task
		skt_table.skt:connect(skt_table.address,skt_table.port)
		local sktd = new_socket(skt_table)
		register_client(skt_table.skt, normalize_pattern(skt_table.pattern))
		return sktd
	end
	M.new_udp = function( skt_table )
	--address, port, locaddr, locport, count)
		skt_table.skt = assert(nixio.bind(skt_table.locaddr, skt_table.locport or 0, 'inet', 'dgram'))
		skt_table.events = {data=skt_table.skt}
		skt_table.task = task
		skt_table.skt:connect(skt_table.address,skt_table.port or 0)
		register_client(skt_table.skt, skt_table.count)
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
		--TODO
		sktd.skt:writeall(data)
	end
	M.new_fd = function ( skt_table )
		skt_table.flags = skt_table.flags  or {}
		skt_table.skt = assert(nixio.open(skt_table.filename, nixio.open_flags(unpack(skt_table.flags))))
		skt_table.events = {data=skt_table.skt}
		skt_table.task = task
		register_client(skt_table.skt, normalize_pattern(skt_table.pattern))
		local sktd = new_socket(skt_table)
		return sktd
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


