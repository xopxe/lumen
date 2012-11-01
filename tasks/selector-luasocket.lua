local sched = require 'sched'
local socket = require 'socket'
local pipes = require 'pipes'

--get locals for some useful things
local setmetatable, ipairs, table, type = setmetatable, ipairs, table, type 

local weak_key = { __mode = 'k' }

local CHUNK_SIZE = 1500 --65536

--size parameter for pipe for asynchrous sending
local ASYNC_SEND_BUFFER=10

local recvt, sendt={}, {}

local sktds = setmetatable({}, { __mode = 'kv' })

local M = {}

---------------------------------------
-- replace sched's default get_time and idle with luasocket's
sched.get_time = socket.gettime 
sched.idle = socket.sleep

-- pipe for async writing
--local write_pipes = setmetatable({}, weak_key)
--local outstanding_data = setmetatable({}, weak_key)

local task

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
		sktd.write_pipes = nil
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
		--local piped = assert(write_pipes[skt] , "socket not registered?")
		local piped = sktd.write_pipes ; if not piped then return end
		--print ('piped', piped)
		--local _, data, err = piped:read()
		if piped:len()>0 then 
			local _, data, err = piped:read()
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
			--print ('pipeempty!', err)
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
						task=task,
						events={data=client},
						pattern=pattern,
						handler = sktd.handler,
					}
					local sktd_cli = init_sktd(skt_table_client)
					--[[
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
					--]]
					
					register_client(sktd_cli)
					sched.signal(sktd.events.accepted, sktd_cli)
				else
					sched.signal(sktd.events.accepted, nil, err)
				end
			else
				--print('&+', skt, mode, partial[skt])
				if type(pattern) == "number" and pattern <= 0 then
					local data,err,part = fd:receive(CHUNK_SIZE)
					--print('&-',data,err,part, #part)
					if err=='closed' then
						unregister(fd)
						sched.signal(fd, nil, err, part) --data is nil or part?
					elseif data then
						sched.signal(fd, data)
					end
				else
					local data,err,part = fd:receive(pattern,sktd.partial)
					sktd.partial=part
					--print('&-',sktd.handler, data,err,part)
					if sktd.handler then sktd.handler(sktd, data, err, part) end
					if not data then
						if err=='closed' then 
							unregister(fd)
							sched.signal(sktd.events.data, nil, err, part) --data is nil or part?
						elseif not part or part=='' then
							sched.signal(sktd.events.data, nil, err)
						end
					else
						sched.signal(sktd.events.data, data)
					end
				end
			end
		end
	end
end
task = sched.run( function ()
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
	M.new_tcp_server = function(locaddr, locport, pattern, handler)
		--address, port, backlog, pattern)
		local sktd=init_sktd()
		sktd.fd=assert(socket.bind(locaddr, locport))
		sktd.events = {accepted=sktd.fd}
		sktd.task=task
		sktd.pattern=normalize_pattern(pattern)
		sktd.handler = handler
		register_server(sktd)
		return sktd
	end
	M.new_tcp_client = function(address, port, locaddr, locport, pattern, handler)
		--address, port, locaddr, locport, pattern)
		local sktd=init_sktd()
		sktd.fd=assert(socket.connect(address, port, locaddr, locport))
		sktd.events = {data=sktd.fd}
		sktd.task=task
		sktd.pattern=normalize_pattern(pattern)
		sktd.handler = handler
		register_client(sktd)
		return sktd
	end
	M.new_udp = function( address, port, locaddr, locport, pattern, handler)
	--address, port, locaddr, locport, count)
		local sktd=init_sktd()
		sktd.fd=socket.udp()
		sktd.events = {data=sktd.fd}
		sktd.task=task
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

		local piped = sktd.write_pipes
		
		-- initialize the pipe on first send
		if not piped then
			piped = pipes.new(ASYNC_SEND_BUFFER)
			sktd.write_pipes = piped
		end
		piped:write(data)

		sched.yield()
	end
	
	M.new_fd = function ()
		return nil, 'Not supported by luasocket'
	end

	--[[
	M.register_server = service.register_server
	M.register_client = service.register_client
	M.unregister = service.unregister
	--]]
	return M
end

return M


