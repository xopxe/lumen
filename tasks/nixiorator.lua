--- Task for accessing nixio library.
-- Nixiorator is a Lumen task that allow to interface with nixio.
-- @module nixiorator
-- @usage local nixiorator = require 'nixiorator'
-- @alias M

local nixio = require("nixio")
local sched = require("sched")
require ("nixio.util")
local pollt={}

--get locals for some useful things
local math, ipairs, table = math, ipairs, table

local M = {}

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
		    M.unregister(skt)
		    sched.signal(skt, nil, 'closed')
		end
	end
end

local function accept(polle)
	local skt, host, port = polle.fd:accept()
	skt:setblocking(true)

	M.register_client(skt, polle.block)
	sched.signal(polle.fd, 'accepted', skt)
end

--- Registers a TCP server socket with nixiorator.
-- nixiorator will signal fd, 'accepted', client when establishing a connection,
-- where fd is the server socket and client is the new client socket.
-- The client socket is automatically registered into nixiorator.
-- @param skt a nixio server socket
-- @param block a nixio block mode to use with accepted client sockets
-- @param backlog The backlog to use on the connection (defaults to 32)
-- @return the polle structure from nixio
M.register_server = function (skt, block, backlog)
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

--- Registers a client socket (TCP, UDP, or filehandle) with nixiorator.
-- nixiorator will signal fd, data, error on data read.
-- @param fd A client socket or filehandle
-- @param block The read pattern to be used.
--
-- - `line` will provide data trough nixio's linesource iterator.
-- - number will provide data trough nixio's block iterator.
--
-- @return the polle structure from nixio
M.register_client = function (fd, block)
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

--- Unregisters a socket from nixiorator.
-- @param fd  the socket or filehandle to unregister.
M.unregister = function (fd)
	for k, v in ipairs(pollt) do
		if fd==v.fd then
			table.remove(pollt,k)
			return
		end
	end
end

--- Performs a single step for nixiorator.
-- Will block at the OS level for up to timeout seconds.
-- Usually this method is not used (probably what you want is to 
-- use @{task}).
-- Nixiorator will emit the signals from registered sockets
-- (see @{register_server} and @{register_client}).
-- @param timeout Max allowed blocking time.
M.step = function (timeout)
	timeout=timeout or -1
	local stat= nixio.poll(pollt, timeout*1000)
	if stat and tonumber(stat) > 0 then
		for _, polle in ipairs(pollt) do
			if polle.revents and polle.revents ~= 0 then
				polle:handler()
			end
		end
	end

end

--- The nixiorator task.
-- This task will emit the signals from registered sockets (see @{register_server} and @{register_client}). 
-- This task is registered in the catalog with the name 'nixiorator'.
-- @usage local sched = require "sched"
--local nixiorator = require "nixiorator"
--sched.sigrun({emitter=nixiorator.task, events='*'}, print)
M.task = sched.run( function ()
	require 'catalog'.get_catalog('tasks'):register('nixiorator', sched.running_task)
	while true do
		local t, _ = sched.yield()
		M.step( t )
	end
end)

--- A reference to the nixio library.
M.nixio = nixio

-- replace sched's default get_time and idle with nixio's
sched.get_time = function()
	local sec, usec = nixio.gettimeofday()
	return sec + usec/1000000
end
sched.idle = function (t)
	local sec = math.floor(t)
	local nsec = (t-sec)*1000000000
	nixio.nanosleep(sec, nsec)
end

return M


