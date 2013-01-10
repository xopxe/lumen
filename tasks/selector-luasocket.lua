local sched = require 'sched'
local socket = require 'socket'
--local pipes = require 'pipes'
local streams = require 'stream'

--get locals for some useful things
local setmetatable, ipairs, table, type = setmetatable, ipairs, table, type 

local CHUNK_SIZE = 1480 --65536

local recvt, sendt={}, {}

local sktds = setmetatable({}, { __mode = 'kv' })

local M = {}

-- streams for incomming data
local read_streams = setmetatable({}, { __mode = 'k' })

---------------------------------------
-- replace sched's default get_time and idle with luasocket's
sched.get_time = socket.gettime 
sched.idle = socket.sleep

-- pipe for async writing
--local write_pipes = setmetatable({}, weak_key)
--local outstanding_data = setmetatable({}, weak_key)

local module_task

local unregister = function (fd)
	local sktd = sktds[fd]
	for i=1, #recvt do
		if recvt[i] == fd then
			table.remove(recvt, i)
			break
		end
	end
	if sendt[fd] then
		for i=1, #sendt do
			if sendt[i] == fd then
				table.remove(sendt, i)
				sendt[fd] = nil
				break
			end
		end
		sktd.write_stream = nil
		sktd.outstanding_data = nil
	end
	sktd.partial = nil
	sktds[fd] = nil
end
local function send_from_pipe (fd)
	local sktd = sktds[fd]
	local out_data = sktd.outstanding_data
	--print ('outdata', skt, out_data)
	if out_data then 
		local data, next_pos = out_data.data, out_data.last+1
		local last, err, lasterr = fd:send(data, next_pos, next_pos+CHUNK_SIZE )
		if last == #data then
			-- all the oustanding data sent
			sktd.outstanding_data = nil
			return
		elseif err == 'closed' then 
			unregister(fd)
			return
		end
		sktd.outstanding_data.last = last or lasterr
	else
		local streamd = sktd.write_stream ; if not streamd then return end
		if streamd.len>0 then 
			local data, serr = streamd:read()
			local last , err, lasterr = fd:send(data, 1, CHUNK_SIZE)
			if err == 'closed' then
				unregister(fd)
				return
			end
			last = last or lasterr
			if last < #data then
				sktd.outstanding_data = {data=data,last=last}
			end
		else
			--emptied the outgoing pipe, stop selecting to write
			for i=1, #sendt do
				if sendt[i] == fd then
					table.remove(sendt, i)
					sendt[fd] = nil
					break
				end
			end
		end
	end
end
local init_sktd = function(sktdesc)
	local sktd = setmetatable(sktdesc or {},{ __index=M })
	return sktd
end
local register_server = function (sktd)
	sktd.isserver=true
	sktd.fd:settimeout(0)
	sktds[sktd.fd] = sktd
	--normalize_pattern(skt_table.pattern)
	--sktmode[sktd] = pattern
	recvt[#recvt+1]=sktd.fd
end
local register_client = function (sktd)
	sktd.fd:settimeout(0)
	sktds[sktd.fd] = sktd
	recvt[#recvt+1]=sktd.fd
end
local step = function (timeout)
	--print('+', #recvt, #sendt, timeout)
	local recvt_ready, sendt_ready, err_accept = socket.select(recvt, sendt, timeout)
	--print('-', #recvt_ready, #sendt_ready, err_accept or '')
	if err_accept~='timeout' then
		for _, fd in ipairs(sendt_ready) do
			send_from_pipe(fd)
		end
		for _, fd in ipairs(recvt_ready) do
			local sktd = sktds[fd]
			local pattern=sktd.pattern
			if sktd.isserver then 
				local client, err=fd:accept()
				if client then
					local skt_table_client = {
						fd=client,
						task=module_task,
						events={data=client},
						pattern=pattern,
						stream = sktd.create_stream and streams.new(), 
					}
					if sktd.handler=='stream' then
						local sktd_cli = init_sktd(skt_table_client)
						local s = streams.new()
						read_streams[sktd_cli] = s
						register_client(sktd_cli)
						sched.signal(sktd.events.accepted, sktd_cli, s)
					else
						skt_table_client.handler = sktd.handler
						local sktd_cli = init_sktd(skt_table_client)
						register_client(sktd_cli)
						sched.signal(sktd.events.accepted, sktd_cli)
					end
				else
					sched.signal(sktd.events.accepted, nil, err)
				end
			else
				--print('&+', sktd, pattern)
				if type(pattern) == "number" and pattern <= 0 then
					local data,err,part = fd:receive(CHUNK_SIZE)
					--print('&-',data,err,part, #part)
					if err=='closed' then
						unregister(fd)
						if sktd.handler then 
							sktd.handler(sktd, nil, 'closed', part) 
						elseif read_streams[sktd] then
							read_streams[sktd]:write(nil, 'fd closed')
						else
							sched.signal(sktd.events.data, nil, err, part) --data is nil or part?
						end
					elseif data then
						if sktd.handler then 
							sktd.handler(sktd, data) 
						elseif read_streams[sktd] then
							read_streams[sktd]:write(data)
						else
							sched.signal(sktd.events.data, data) 
						end
					end
				else
					local data,err,part = fd:receive(pattern,sktd.partial)
					sktd.partial=part
					--print('&-', #(data or ''), #(part or ''), data,err,part)
					if data then
						if sktd.handler then 
							sktd.handler(sktd, data) 
						elseif read_streams[sktd] then
							read_streams[sktd]:write(data)
						else
							sched.signal(sktd.events.data, data) 
						end
					elseif err=='closed' then 
						unregister(fd)
						if sktd.handler then 
							sktd.handler(sktd, nil, 'closed', part) 
						elseif read_streams[sktd] then
							read_streams[sktd]:write(nil, 'fd closed')
						else
							sched.signal(sktd.events.data, nil, err, part) --data is nil or part?
						end
					end
				end
			end
		end
	end
end
module_task = sched.new_task( function ()
	while true do
		local t, _ = sched.yield()
		step( t )
	end
end)
---------------------------------------

local normalize_pattern = function(pattern)
	if pattern=='*l' or pattern=='line' then
		return '*l'
	end
	if tonumber(pattern) and tonumber(pattern)>0 then
		return pattern
	end
	if not pattern or pattern == '*a' 
	or (tonumber(pattern) and tonumber(pattern)<=0) then
		return '*a'
	end
	print ('Could not normalize the pattern:', pattern)
end

M.init = function()
	M.new_tcp_server = function (locaddr, locport, pattern, handler)
		--address, port, backlog, pattern)
		local sktd=init_sktd()
		sktd.fd=assert(socket.bind(locaddr, locport))
		sktd.events = {accepted=sktd.fd}
		sktd.task=module_task
		sktd.pattern=normalize_pattern(pattern)
		sktd.handler = handler
		register_server(sktd)
		return sktd
	end
	M.new_tcp_client = function (address, port, locaddr, locport, pattern, handler)
		--address, port, locaddr, locport, pattern)
		local sktd=init_sktd()
		sktd.fd=assert(socket.connect(address, port, locaddr, locport))
		sktd.events = {data=sktd.fd}
		sktd.task=module_task
		sktd.pattern=normalize_pattern(pattern)
		sktd.handler = handler
		register_client(sktd)
		return sktd
	end
	M.new_udp = function ( address, port, locaddr, locport, pattern, handler)
	--address, port, locaddr, locport, count)
		local sktd=init_sktd()
		sktd.fd=socket.udp()
		sktd.events = {data=sktd.fd}
		sktd.task=module_task
		sktd.pattern=pattern 
		sktd.fd:setsockname(locaddr or '*', locport or 0)
		sktd.fd:setpeername(address or '*', port)
		sktd.handler = handler
		register_client(sktd)
		return sktd
	end
	M.close = function(sktd)
		unregister(sktd.fd)
		sktd.fd:close()
	end
	M.send_sync = function(sktd, data)
		local start, err,done=0,nil
		repeat
			start, err=sktd.fd:send(data,start+1)
			done = start==#data 
		until done or err
		return done, err, start
	end
	M.send = M.send_sync
	M.send_async = function (sktd, data)
		--make sure we're selecting to write
		local skt=sktd.fd
		if not sendt[skt] then 
			sendt[#sendt+1] = skt
			sendt[skt]=true
		end

		local streamd = sktd.write_stream
		
		-- initialize the pipe on first send
		if not streamd then
			streamd = streams.new(M.ASYNC_SEND_BUFFER)
			sktd.write_stream = streamd
		end
		streamd:write(data)

		sched.yield()
	end
	M.new_fd = function ()
		return nil, 'Not supported by luasocket'
	end
	M.getsockname = function(sktd)
		return sktd.fd:getsockname()
	end
	M.getpeername = function(sktd)
		return sktd.fd:getpeername()
	end
	
	M.task=module_task
	module_task:run()
	--[[
	M.register_server = service.register_server
	M.register_client = service.register_client
	M.unregister = service.unregister
	--]]
	return M
end

return M


