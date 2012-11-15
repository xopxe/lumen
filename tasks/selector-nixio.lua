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

local CHUNK_SIZE = 1480 -- 65536 --8192

--size parameter for pipe for asynchrous sending
local ASYNC_SEND_BUFFER=10

-- pipe for async writing
local write_pipes = setmetatable({}, weak_key)
local outstanding_data = setmetatable({}, weak_key)


local M = {}

local module_task

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
	sktd.task = module_task
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
	local data_event = sktd.events.data
	local function client_handler(polle)
		local data,code,msg=polle.it()
		if data then
			local block = polle.block
			if not block or block=='line'  or block == #data then
				if sktd.handler then sktd.handler(sktd, data) end
				sched.signal(data_event, data)
				return
			end
			if type(block) == 'number' and block > #data then
				polle.readbuff = (polle.readbuff or '') .. data
				data = polle.readbuff
				if block==#data then
					polle.readbuff = nil
					if sktd.handler then sktd.handler(sktd, data) end
					sched.signal(data_event, data)
				end
			end
		else
			--11: 'Resource temporarily unavailable'
			--print('!!!!!',data,code,msg)
			if (code==nil)
			or (code and code~=11) then
				--sktd:close()
				unregister(sktd)
				sched.signal(data_event, nil, 'closed')
				sktd:close()
			end
		end
	end
	local polle={
		fd=sktd.fd,
		events=nixio.poll_flags("in", "pri"), --, "out"),
		block=sktd.pattern,
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
	local accepted_event = sktd.events.accepted
	local function accept_handler(polle)
		local skt, host, port = polle.fd:accept()
		local skt_table_client = {
			fd=skt,
			handler= sktd.handler,
			task=sktd.task,
			events={data=skt},
			pattern=sktd.pattern,
		}
		register_client(skt_table_client)
		local insktd = init_sktd(skt_table_client)
		sched.signal(accepted_event, insktd)
	end
	local polle={
		fd=sktd.fd,
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
	local skt=sktd.fd
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
module_task = sched.new_task( function ()
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
	M.new_tcp_server = function(locaddr, locport, pattern, handler)
		--address, port, pattern, backlog)
		local sktd=init_sktd()
		if locaddr=='*' then locaddr = nil end
		sktd.fd = assert(nixio.bind(locaddr, locport, 'inet', 'stream'))
		sktd.events = {accepted=sktd.fd }
		sktd.handler = handler
		sktd.pattern = normalize_pattern(pattern)
		register_server(sktd)
		return sktd
	end
	M.new_tcp_client = function(address, port, locaddr, locport, pattern, handler)
		local sktd=init_sktd()
		if locaddr=='*' then locaddr = nil end
		sktd.fd = assert(nixio.bind(locaddr, locport or 0, 'inet', 'stream'))
		sktd.events = {data=sktd.fd}
		sktd.fd:connect(address, port)
		sktd.pattern=normalize_pattern(pattern)
		sktd.handler = handler
		register_client(sktd)
		return sktd
	end
	M.new_udp = function( address, port, locaddr, locport, pattern, handler)
		local sktd=init_sktd()
		if locaddr=='*' then locaddr = nil end
		sktd.fd = assert(nixio.bind(locaddr, locport or 0, 'inet', 'dgram'))
		sktd.events = {data=sktd.fd}
		if address and port then sktd.fd:connect(address, port) end
		sktd.pattern =  normalize_pattern(pattern)
		sktd.handler = handler
		register_client(sktd)
		return sktd
	end
	M.new_fd = function ( filename, flags, pattern, handler )
		local sktd=init_sktd()
		local err
		sktd.flags = flags  or {}
		sktd.fd, err = nixio.open(filename, nixio.open_flags(unpack(flags)))
		if not sktd.fd then return nil, err end
		sktd.events = {data=sktd.fd}
		sktd.pattern =  normalize_pattern(pattern)
		sktd.handler = handler
		register_client(sktd)
		return sktd
	end
	M.grab_stdout = function ( command, pattern, handler )
		local function run_shell_nixio(command)
		    local fdi, fdo = nixio.pipe()
		    local pid = nixio.fork()
			if pid > 0 then 
				--parent
				fdo:close()
				return fdi
			else
				--child
				nixio.dup(fdo, nixio.stdout)
				fdi:close()
				fdo:close()
				nixio.exec("/bin/sh", "-c", command) --should not return
			end
		end
		local sktd=init_sktd()
		sktd.fd =  run_shell_nixio(command)
		if not sktd.fd then return end
		sktd.events = {data=sktd.fd}
		sktd.pattern =  normalize_pattern(pattern)
		sktd.handler = handler
		register_client(sktd)
		return sktd
	end
	M.close = function(sktd)
		unregister(sktd.fd)
		sktd.fd:close()
	end
	M.send_sync = function(sktd, data)
		local written,_,_,writtenerr = sktd.fd:writeall(data)
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
	M.getsockname = function(sktd)
		return sktd.fd:getsockname()
	end
	M.getpeername = function(sktd)
		return sktd.fd:getpeername()
	end

	
	M.task=module_task
	module_task:run()
	
	return M
end

return M


