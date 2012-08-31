--- Task for accessing LuaSocket library.
-- Socketeer is a Lumen task that allow to interface with LuaSocket. 
-- @module socketeer
-- @usage local socketeer = require 'socketeer'
-- @alias M

local socket = require 'socket'
local sched = require 'sched'
local catalog = require 'catalog'
local pipes = require 'pipes'

--get locals for some useful things
local setmetatable, ipairs, table, type = setmetatable, ipairs, table, type 

local weak_key = { __mode = 'k' }

local CHUNK_SIZE = 65536

--size paramter for pipe for asynchrous sending
local ASYNC_SEND_BUFFER=10

local recvt, sendt={}, {}

local sktmode = setmetatable({}, weak_key)
local isserver = setmetatable({}, weak_key)
local partial = setmetatable({}, weak_key)

local M = {socket=socket}


-- pipe for async writing
local write_pipes = setmetatable({}, weak_key)
local outstanding_data = setmetatable({}, weak_key)

local function send_from_pipe (skt)
	local out_data = outstanding_data[skt]
	--print ('outdata', skt, out_data)
	if out_data then 
		local data, next = out_data.data, out_data.last+1
		local last, err, lasterr = skt:send(data, next, next+CHUNK_SIZE )
		if last == #data then
			-- all the oustanding data sent
			outstanding_data[skt] = nil
			return
		elseif err == 'closed' then 
			M.unregister(skt)
			return
		end
		outstanding_data[skt].last = last or lasterr
	else
		--local piped = assert(write_pipes[skt] , "socket not registered?")
		local piped = write_pipes[skt] ; if not piped then return end
		--print ('piped', piped)
		local _, data, err = piped:read()
		if data then 
			--print ('data', #data)
			local last , err, lasterr = skt:send(data, 1, CHUNK_SIZE)
			if err == 'closed' then
				M.unregister(skt)
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

--- Registers a TCP server socket with socketeer.
-- socketeer will signal _skt, 'accepted'_, client when establishing a connection, 
-- where skt is the server socket and client is the new client socket, or _skt, 'fail', error_ 
-- on error conditions. 
-- The client socket is automatically registered into socketeer.
-- @param skt a LuaSocket server socket
-- @param pattern The read pattern to be used for established connections (see @{register_client})
M.register_server = function (skt, pattern)
	isserver[skt]=true
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end

--- Registers a client socket (TCP or UDP) with socketeer.
-- socketeer will signal _skt, data, error_ on data read. data is the string read. 
-- Data can be nil if error is 'closed'. A 'closed' error also means the skt got unregistered. 
-- When reading from TCP with pattern>0, the last signal can provide a partial read after 
-- the err return.
-- @param skt a LuaSocket client socket
-- @param pattern The read pattern to be used.
--
-- - '*a' (TCP only) will read all the data from the socket until it is closed, and provide it all in one signal.
-- - '*l' (TCP only) will read line by line, as specified in LuaSocket.
-- - number>0 If TCP will read in chunks of number bytes. If UDP, means the first number bytes from each UDP packet.
-- - number<=0 Will provide chunks as they arrive, with no further processing.
M.register_client = function (skt, pattern)
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end

--- Unregisters a socket from socketeer
-- @param skt the socket to unregister.
M.unregister = function (skt)
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

--- Performs a single step for socketeer. 
-- Will block at the OS level for up to timeout seconds. 
-- Usually this method is not used (probably what you want is to 
-- use @{task}).
-- Socketeer will emit the signals from registered sockets 
-- (see @{register_server} and @{register_client}).
-- @param timeout Max allowed blocking time.
M.step = function (timeout)
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
					M.register_client(client, mode)
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
						M.unregister(skt)
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
							M.unregister(skt)
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

--- A synchronous send for TCP sockets.
-- This method will block until all data is sent. 
-- @param skt the socket to send on.
-- @param data data to send.
-- @return _true_ on success, or _false_ followed by an error message
-- and the count of the last succesfully sent byte.
M.send_sync = function(skt, data)
	local start, err,done=0,nil
	repeat
		start, err=skt:send(data,start+1)
		done = start==#data 
	until done or err
	return done, err, start
end

--- An asynchronous send for TCP sockets.
-- When using this method, the control is returned 
-- immediatelly, while the sending continues in the background.
-- This is useful when sending big chunks of data (say, hundreds 
-- of kb or megabytes). 
-- @param skt the socket to send on.
-- @param data data to send.
M.send_async = function (skt, data)
	--make sure were selecting to write
	if not sendt[skt] then 
		sendt[#sendt+1] = skt
		sendt[skt]=true
	end

	local piped = write_pipes[skt] 
	
	-- initialize the pipe on first send
	if not piped then
		piped = pipes.new(skt, ASYNC_SEND_BUFFER, 0)
		write_pipes[skt] = piped
	end

	--print ('writepipe', piped, #data)
	piped:write(data)

	sched.yield()
end

--- Send data on a TCP socket.
-- This is an alias for @{send_sync}
-- @function send
-- @param skt the socket to send on.
-- @param data data to send.
-- @return _true_ on success, or _false_ followed by an error message
-- and the count of the last succesfully sent byte.
M.send = M.send_sync

--- The socketeer task.
-- This task will emit the signals from registered sockets (see @{register_server} and @{register_client}). 
-- This task  is registered in the catalog with the name 'socketeer'.
-- @usage local sched = require "sched"
--local socketeer = require 'socketeer'
--sched.sigrun({emitter=socketeer.task, events='*'}, print)
M.task = sched.run( function ()
	catalog.register('socketeer')
	while true do
		local t, _ = sched.yield()
		M.step( t )
	end
end)

--- A reference to the LuaSocket library.
M.socket = socket

-- replace sched's default get_time and idle with luasocket's
sched.get_time = socket.gettime 
sched.idle = socket.sleep

return M


