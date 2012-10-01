--- Task for accessing nixio library.
-- Nixiorator is a Lumen task that allow to interface with nixio.
-- @module nixiorator
-- @usage local nixiorator = require 'nixiorator'
-- @alias M

local sched = require 'sched'
local socket = require 'socket'
local pipes = require 'pipes'

--get locals for some useful things
local setmetatable, ipairs, table, type = setmetatable, ipairs, table, type 

local weak_key = { __mode = 'k' }

local CHUNK_SIZE = 65536

--size parameter for pipe for asynchrous sending
local ASYNC_SEND_BUFFER=10

local recvt, sendt={}, {}

local sktmode = setmetatable({}, weak_key)
local isserver = setmetatable({}, weak_key)
local partial = setmetatable({}, weak_key)

local M = {}

---------------------------------------
-- replace sched's default get_time and idle with luasocket's
sched.get_time = socket.gettime 
sched.idle = socket.sleep

-- pipe for async writing
local write_pipes = setmetatable({}, weak_key)
local outstanding_data = setmetatable({}, weak_key)

local unregister = function (skt)
	for i=1, #recvt do
		if recvt[i] == skt then
			table.remove(recvt, i)
			break
		end
	end
	if sendt[skt] then
		for i=1, #sendt do
			if sendt[i] == skt then
				table.remove(sendt, i)
				sendt[skt] = nil
				break
			end
		end
		write_pipes[skt] = nil
		outstanding_data[skt] = nil
	end
	partial[skt] = nil
end
local function send_from_pipe (skt)
	local out_data = outstanding_data[skt]
	--print ('outdata', skt, out_data)
	if out_data then 
		local data, next_pos = out_data.data, out_data.last+1
		local last, err, lasterr = skt:send(data, next_pos, next_pos+CHUNK_SIZE )
		if last == #data then
			-- all the oustanding data sent
			outstanding_data[skt] = nil
			return
		elseif err == 'closed' then 
			unregister(skt)
			return
		end
		outstanding_data[skt].last = last or lasterr
	else
		--local piped = assert(write_pipes[skt] , "socket not registered?")
		local piped = write_pipes[skt] ; if not piped then return end
		--print ('piped', piped)
		--local _, data, err = piped:read()
		if piped:len()>0 then 
			local _, data, err = piped:read()
			local last , err, lasterr = skt:send(data, 1, CHUNK_SIZE)
			if err == 'closed' then
				unregister(skt)
				return
			end
			last = last or lasterr
			if last < #data then
				outstanding_data[skt] = {data=data,last=last}
			end
		else
			--print ('pipeempty!', err)
			--emptied the outgoing pipe, stop selecting to write
			for i=1, #sendt do
				if sendt[i] == skt then
					table.remove(sendt, i)
					sendt[skt] = nil
					break
				end
			end
		end
	end
end
local register_server = function (skt, pattern)
	isserver[skt]=true
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end
local register_client = function (skt, pattern)
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end
local step = function (timeout)
	--print('+', #recvt, #sendt, timeout)
	local recvt_ready, sendt_ready, err_accept = socket.select(recvt, sendt, timeout)
	--print('-', #recvt_ready, #sendt_ready, err_accept or '')
	if err_accept~='timeout' then
		for _, skt in ipairs(sendt_ready) do
			send_from_pipe(skt)
		end
		for _, skt in ipairs(recvt_ready) do
			local mode = sktmode[skt]
			if isserver[skt] then 
				local client, err=skt:accept()
				if client then
					register_client(client, mode)
					sched.signal(skt, 'accepted', client)
				else
					sched.signal(skt, 'fail', err)
				end
			else
				--print('&+', skt, mode, partial[skt])
				if type(mode) == "number" and mode <= 0 then
					local data,err,part = skt:receive(CHUNK_SIZE)
					--print('&-',data,err,part, #part)
					if err=='closed' then
						unregister(skt)
						sched.signal(skt, nil, err, part) --data is nil or part?
					elseif data then
						sched.signal(skt, data)
					end
				else
					local data,err,part = skt:receive(mode,partial[skt])
					partial[skt]=part
					--print('&-',data,err,part)
					if not data then
						if err=='closed' then 
							unregister(skt)
							sched.signal(skt, nil, err, part) --data is nil or part?
						elseif not part or part=='' then
							sched.signal(skt, nil, err)
						end
					else
						sched.signal(skt, data)
					end
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
---------------------------------------

local new_socket = function(sktdesc)
	local sktd = setmetatable(sktdesc or {},{ __index=M })
	return sktd
end

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

M.init = function()
	M.new_tcp_server = function( skt_table )
		--address, port, backlog, pattern)
		skt_table.skt=assert(socket.bind(skt_table.locaddr, skt_table.locport, skt_table.backlog))
		skt_table.events = {accepted='accepted'}
		skt_table.task = build_tcp_accept_task(skt_table)
		local sktd = new_socket(skt_table)
		register_server(skt_table.skt, normalize_pattern(skt_table.pattern))
		return sktd
	end
	M.new_tcp_client = function( skt_table )
		--address, port, locaddr, locport, pattern)
		skt_table.skt=assert(socket.connect(skt_table.address, skt_table.port, skt_table.locaddr, skt_table.locport))
		skt_table.events = {data=skt_table.skt}
		skt_table.task=task
		local sktd = new_socket(skt_table)
		register_client(skt_table.skt, normalize_pattern(skt_table.pattern))
		return sktd
	end
	M.new_udp = function( skt_table )
	--address, port, locaddr, locport, count)
		skt_table.skt=socket.udp()
		skt_table.events = {data=skt_table.skt}
		skt_table.task=task
		local sktd = new_socket(skt_table)
		skt_table.skt:setsockname(skt_table.locaddr or '*', skt_table.locport or 0)
		skt_table.skt:setpeername(skt_table.address or '*', skt_table.port)
		register_client(skt_table.skt, skt_table.count)
		return sktd
	end
	M.close = function(sktd)
		unregister(sktd.skt)
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
	M.send_async = function (sktd, data)
		--make sure we're selecting to write
		local skt=sktd.skt
		if not sendt[skt] then 
			sendt[#sendt+1] = skt
			sendt[skt]=true
		end

		local piped = write_pipes[skt] 
		
		-- initialize the pipe on first send
		if not piped then
			piped = pipes.new(ASYNC_SEND_BUFFER)
			write_pipes[skt] = piped
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


