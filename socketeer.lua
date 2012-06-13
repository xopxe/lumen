--- Task for accessing LuaSocket library.
-- Socketeer is a Lumen task that allow to interface with LuaSocket. 
-- @module socketeer
-- @usage local socketeer = require 'socketeer'
-- @alias M

local socket = require("socket")
local sched = require("sched")

--get locals for some useful things
local setmetatable, ipairs, table, type = setmetatable, ipairs, table, type 

local weak_key = { __mode = 'k' }

local CHUNK_SIZE = 65536

local recvt, sendt={}, {}

local sktmode = setmetatable({}, weak_key)
local isserver = setmetatable({}, weak_key)
local partial = setmetatable({}, weak_key)

-- replace sched's default get_time with luasocket's
if sched.get_time == os.time then
	sched.get_time = socket.gettime 
end
sched.idle = socket.sleep

local M = {socket=socket}

-- pipe for async writing
local write_pipes = {}
local outstanding_data = {}

local function send_from_pipe (skt)
--print('a')
	local out_data = outstanding_data[skt]
	if out_data then 
--print('aA')
		local data, next = out_data.data, out_data.last+1
--print("S o+" , #data, next)
		local last, err, lasterr = skt:send(data, next, next+CHUNK_SIZE )
--print("S o-" , last,err,lasterr)
		if last == #data then
			-- all the oustanding data sent
			outstanding_data[skt] = nil
			return
		end
		outstanding_data[skt].last = last or lasterr
	else
--print('aB')
		--local pipe = assert(write_pipes[skt] , "socket not registered?")
		local pipe = write_pipes[skt] ; if not pipe then return end
--print('aB:',pipe.len())
		local data = pipe.read()
		if  data then 
--print("S p+" , pipe.len(), #data)
			local last , err, lasterr = skt:send(data, 1, CHUNK_SIZE)
--print("S p-" , last,err, lasterr)
			last = last or lasterr
			if last < #data then
				outstanding_data[skt] = {data=data,last=last}
			end
		else	
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

M.async_send = function (skt, s)
	--make sure were selecting to write
	if not sendt[skt] then 
		sendt[#sendt+1] = skt
		sendt[skt]=true
	end

	local pipe = write_pipes[skt] 
	
	-- initialize the pipe on first send
	if not pipe then
--print('0')
		pipe = sched.pipes.new(skt, 30, 0) --FIXME 30?
--print('0.1')
		write_pipes[skt]  = pipe
--print('0.2')
	end

--print('1')
	pipe.write(s)
--print('2')	

	sched.yield()
end

--- Registers a TCP server socket with socketeer.
-- socketeer will signal fd, 'accepted', client when establishing a connection, 
-- where skt is the server socket and client is the new client socket, or skt, 'fail', error 
-- on error conditions. 
-- The client socket is automatically registered into nixiorator.
-- @param skt a LuaSocket server socket
-- @param pattern The read pattern to be used for established connections (see @{register_client})
M.register_server = function (skt, pattern)
	isserver[skt]=true
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end

--- Registers a client socket (TCP or UDP) with socketeer.
-- socketeer will signal skt, data, error On data read. data is the string read. 
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
--
M.register_client = function (skt, pattern)
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end

--- Unregisters a socket from socketeer
-- @param skt the socket to unregister.
M.unregister = function (skt)
	for k, v in ipairs(recvt) do 
		if skt==v then 
			table.remove(recvt,k) 
			break
		end
	end
	local i=sendt[skt]
	if i then sendt[i]=nil end
end

--- Performs a single step for socketeer. 
-- Will block at the OS level for up to timeout seconds. 
-- Usually this method is not used (probably what you want is to 
-- register @{task} with the Lumen scheduler).
-- Socketeer will emit the signals from registered sockets 
-- (see @{register_server} and @{register_client}).
-- @param timeout Max allowed blocking time.
M.step = function (timeout)
	--print('+', #recvt, #sendt,timeout)
	local recvt_ready, send_ready, err = socket.select(recvt, sendt, timeout)
	--print('-', #recvt, #sendt,#recvt_ready, #send_ready, err)
	if err~='timeout' then
		for _, skt in ipairs(send_ready) do
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
					local data,err,part = skt:receive(65536)
					--print('&-',data,err,part, #part)
					if err=='closed' then
						M.unregister(skt)
						sched.signal(skt, nil, err, part)
					else
						sched.signal(skt, data)
					end
				else
					local data,err,part = skt:receive(mode,partial[skt])
					partial[skt]=part
					--print('&-',data,err,part)
					if not data then
						if err=='closed' then 
							M.unregister(skt)
							sched.signal(skt, nil, err, part)
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

--- The function to be registered with the Lumen scheduler to receive the nixiorator signals.
-- Whe running, socketeer will emit the signals from registered sockets 
-- (see @{register_server} and @{register_client}).
-- @usage local sched = require 'sched'
--local socketter = require 'socketeer'
--local n = sched.run(socketeer.task)
M.task = function ()
	sched.catalog.register('socketeer')
	while true do
		local t, _ = sched.yield()
		M.step( t )
	end
end

return M


