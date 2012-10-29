--- Task for accessing nixio library.
-- Selector-nixio is a Lumen task that allow to interface with nixio.
-- @module selector-nixio
-- @alias M

local sched = require 'sched'
local nixio = require 'nixio'
local pipes = require 'pipes'
--local nixiorator = require 'tasks/nixiorator'
require 'nixio.util'

local floor = math.floor
local weak_key = { __mode = 'k' }

local CHUNK_SIZE = 1500 -- 65536 --8192

--size parameter for pipe for asynchrous sending
local ASYNC_SEND_BUFFER=10

-- pipe for async writing
local write_pipes = setmetatable({}, weak_key)
local outstanding_data = setmetatable({}, weak_key)


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
local init_sktd = function(sktdesc)
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
			local block = polle.block
			if not block or block=='line'  or block == #data then
				if sktd.handler then sktd.handler(sktd, data) end
				sched.signal(sktd.events.data, data)
				return
			end
			if type(block) == 'number' and block > #data then
				polle.readbuff = (polle.readbuff or '') .. data
				data = polle.readbuff
				if block==#data then
					polle.readbuff = nil
					if sktd.handler then sktd.handler(sktd, data) end
					sched.signal(sktd.events.data, data)
				end
			end
		else
			--11: 'Resource temporarily unavailable'
			--print('!!!!!',data,code,msg)
			if (code==nil)
			or (code and code~=11) then
			    unregister(sktd)
			    sched.signal(sktd.events.data, nil, 'closed')
			end
		end
	end
	local polle={
		fd=sktd.skt,
		events=nixio.poll_flags("in", "pri"), --, "out"),
		block=normalize_pattern(sktd.pattern) or 8192,
		handler=client_handler,
		sktd=sktd,
	}
	if polle.block=='line' then
		polle.it=polle.fd:linesource()
	else
		polle.it=polle.fd:blocksource(polle.block)
	end
	polle.fd:setblocking(false)
	sktd.polle=polle
	pollt[#pollt+1]=polle
end
local register_server = function (sktd ) --, block, backlog)
	local function accept_handler(polle)
		local skt, host, port = polle.fd:accept()
		local skt_table_client = {
			skt=skt,
			handler= sktd.handler,
			task=sktd.task,
			events={data=skt},
			pattern=sktd.pattern,
		}
		register_client(skt_table_client)
		local insktd = init_sktd(skt_table_client)
		sched.signal(sktd.events.accepted, insktd)
	end
	local polle={
		fd=sktd.skt,
		sktd=sktd,
		events=nixio.poll_flags("in"),
		--block=normalize_pattern(sktd.pattern) or 8192,
		handler=accept_handler
	}
	polle.fd:listen(sktd.backlog or 32)
	pollt[#pollt+1]=polle
	sktd.polle=polle
end
local function send_from_pipe (sktd)
	local out_data = outstanding_data[sktd]
	local skt=sktd.skt
	if out_data then 
		local data, next_pos = out_data.data, out_data.last
		
		local blocksize = CHUNK_SIZE
		if blocksize>#data-next_pos then blocksize=#data-blocksize end
		local written, errwrite =skt:write(data, next_pos, blocksize )
		if not written and errwrite~=11 then --error, is not EAGAIN
			unregister(sktd.polle)
			return
		end
		
		local last = next_pos + (written or 0)
		if last == #data then
			-- all the oustanding data sent
			outstanding_data[sktd] = nil
		else
			outstanding_data[sktd].last = last
		end
	else
		--local piped = assert(write_pipes[skt] , "socket not registered?")
		local piped = write_pipes[sktd] ; if not piped then return end
		if piped:len()>0 then 
			--print ('data', #data)
			local _, data, err = piped:read()
			
			local blocksize = CHUNK_SIZE
			if blocksize>#data then blocksize=#data-blocksize end
			local written, errwrite =skt:write(data, 0, blocksize )
			if not written and errwrite~=11 then --not EAGAIN
				unregister(sktd.polle)
				return
			end
			
			written=written or 0
			if written < #data then
				outstanding_data[sktd] = {data=data,last=written}
			end
		else
			--emptied the outgoing pipe, stop selecting to write
			sktd.polle.events=nixio.poll_flags("in", "pri")
		end
	end
end
local step = function (timeout)
	timeout=timeout or -1
	local stat= nixio.poll(pollt, floor(timeout*1000))
	if stat and tonumber(stat) > 0 then
		for _, polle in ipairs(pollt) do
			local revents = polle.revents 
			if revents and revents ~= 0 then
				local mode = nixio.poll_flags(revents)
				if mode['out'] then 
					send_from_pipe(polle.sktd)
				end
				if mode['in'] then 
					polle:handler() 
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
		local sktd = init_sktd(skt_table)
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
		local sktd = init_sktd(skt_table)
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
		local sktd = init_sktd(skt_table)
		return sktd
	end
	M.new_fd = function ( skt_table )
		skt_table.flags = skt_table.flags  or {}
		skt_table.skt = assert(nixio.open(skt_table.filename, nixio.open_flags(unpack(skt_table.flags))))
		skt_table.events = {data=skt_table.skt}
		skt_table.task = task
		register_client(skt_table)
		local sktd = init_sktd(skt_table)
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
		--make sure we're selecting to write
		sktd.polle.events=nixio.poll_flags("in", "pri", "out")
		
		local piped = write_pipes[sktd] 
		
		-- initialize the pipe on first send
		if not piped then
			piped = pipes.new(ASYNC_SEND_BUFFER)
			write_pipes[sktd] = piped
		end

		piped:write(data)

		sched.yield()
	end

	M.task=task
	
	return M
end

return M


