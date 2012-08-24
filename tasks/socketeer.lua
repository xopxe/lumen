--- Task for accessing LuaSocket library.
-- Socketeer is a Lumen task that allow to interface with LuaSocket. 
-- @module socketeer
-- @usage local socketeer = require 'socketeer'
-- @alias M

local socket = require("socket")
local sched = require("sched")
local catalog = require "catalog"

--get locals for some useful things
local setmetatable, ipairs, table, type = setmetatable, ipairs, table, type 

local weak_key = { __mode = 'k' }

local recvt={}

local sktmode = setmetatable({}, weak_key)
local isserver = setmetatable({}, weak_key)
local partial = setmetatable({}, weak_key)

local M = {socket=socket}

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
	for k, v in ipairs(recvt) do 
		if skt==v then 
			table.remove(recvt,k) 
			return
		end
	end
end

--- Performs a single step for socketeer. 
-- Will block at the OS level for up to timeout seconds. 
-- Usually this method is not used (probably what you want is to 
-- use @{task}).
-- Socketeer will emit the signals from registered sockets 
-- (see @{register_server} and @{register_client}).
-- @param timeout Max allowed blocking time.
M.step = function (timeout)
	--print('+', timeout)
	local recvt_ready, _, err = socket.select(recvt, nil, timeout)
	--print('-', #recvt_ready, err)
	if err~='timeout' then
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
					local data,err,part = skt:receive(65000)
					--print('&-',data,err,part, #part)
					if err=='closed' then
						M.unregister(skt)
						sched.signal(skt, nil, err, part) --data is nil or part?
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

--- A reference to the LuaSocket library.
M.socket = socket

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

return M


