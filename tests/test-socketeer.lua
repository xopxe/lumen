---
-- A test program for socketeer.

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

require "strict"

local sched = require "sched"
local catalog = require "catalog"
local socketeer = require "tasks/socketeer"
local socket = socketeer.socket

--udp
---[[
local udprecv = assert(socket.udp())
assert(udprecv:setsockname("127.0.0.1", 8888))
socketeer.register_client(udprecv)
sched.sigrun(
	{emitter=socketeer.task, events={udprecv}},
	function(_, _, data) print("!U", data) end
)

sched.run(function()
	local udpsend = assert(socket.udp())
	assert(udpsend:setsockname("127.0.0.1", 0))
	assert(udpsend:setpeername("127.0.0.1", 8888))
	while true do
		local m="ping! "..os.time()
		print("udp sending",m)
		assert(udpsend:send(m))
		sched.sleep(3)
	end
end)
--]]

--tcp
---[[
sched.run(function()
	catalog.register('TCPLISTEN')
	local server = assert(socket.bind('127.0.0.1', 8888))
	socketeer.register_server(server, 3)-- -1)
	while true do
		local _, _, msg, inskt = sched.wait({emitter=socketeer.task, events={server}})
		-- a connection was accepted, create a listener task
		if msg=='accepted' then
			sched.sigrun(
				{emitter=socketeer.task, events={inskt}},
				function(_,_, data, err)
					print("!T", data, err or '')
				end
			)
		end
	end
end)

sched.run(function()
	catalog.register('TCPSEND')
	local tcpcli = socket.connect('127.0.0.1', 8888)
	sched.sleep(1)
	local m='1234567'
	print("tcp sending",m)
	assert(tcpcli:send(m))
	sched.sleep(1)
	local m='890'
	print("tcp sending",m)
	assert(tcpcli:send(m))
	tcpcli:close()
end)
--]]


sched.go()
