---
-- A test program for socketeer.


require "strict"

local sched = require "sched"
local socketeer = require "socketeer"
local socket = socketeer.socket

--udp
---[[
local udprecv = assert(socket.udp())
assert(udprecv:setsockname("127.0.0.1", 8888))

local udpsend = assert(socket.udp())
assert(udpsend:setsockname("127.0.0.1", 0))
assert(udpsend:setpeername("127.0.0.1", 8888))
--]]

sched.sigrun(print, {emitter="*", events={sched.EVENT_DIE}})

local s = sched.run(socketeer.task)
print('SOCKETEER',s)

--udp
--[[
socketeer.register_client(udprecv)
sched.sigrun(function(_, d) print("!U", d) end, {emitter=s, events={udprecv}})
sched.run(function()
	while true do
		sched.sleep(3)
		local m="ping! "..os.time()
		print("udp sending",m)
		--assert(udpsend:send(m))
		socketeer.async_send(udpsend, m)
	end
end)
--]]

---tcp
--[[
sched.run(function()
	sched.catalog.register('TCPLISTEN')
	local server = assert(socket.bind('127.0.0.1', 8888))
	socketeer.register_server(server, 3)--'*a')
	while true do
		local skt, msg, inskt  = sched.wait({emitter=s, events={server}})
		--print ("#", skt, msg, inskt )
		if msg=='accepted' then
			sched.sigrun(function(_, d, e)
				print("!T", d, e or '')
			end, {emitter=s, events={inskt}})
		end
	end
end)
sched.run(function()
	sched.catalog.register('TCPSEND')
	local tcpcli = socket.connect('127.0.0.1', 8888)
	sched.sleep(1)
	--local m=string.rep('x',7)
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

--async
---[[
sched.run(function()
	sched.catalog.register('TCPLISTEN')
	local server = assert(socket.bind('127.0.0.1', 8888))
	socketeer.register_server(server, 50000*100)--'*a')
	while true do 
		local skt, msg, inskt  = sched.wait({emitter=s, events={server}})
		print ("#", skt, msg, inskt )
		if msg=='accepted' then 
			--print("!T", #(d or ''), e or '')
			sched.sigrun(function(_, d, e) 
				if e == 'closed' then sched.kill()  end
				print('arrived!', #d)
			end, {emitter=s, events={inskt}})
		end
	end
end)
sched.run(function()
	local listener = sched.catalog.waitfor('TCPLISTEN')
	local tcpcli = socket.connect('127.0.0.1', 8888)
	sched.sleep(1)

	local tini, tfin
	local count = 100
	local s=string.rep("x", 50000)
	local ss=string.rep(s, count)

	print("sending sync...")
	tini = socket.gettime()
	for i=1,count do
		assert(tcpcli:send(s))
		sched.yield()
	end
	tfin = socket.gettime()
	print("sync:", tfin-tini)

	print("sending async...")
	tini = socket.gettime()
	socketeer.async_send(tcpcli, ss)
	tfin = socket.gettime()
	print("async:", tfin-tini)

	--tcpcli:close()
	--sched.kill(listener)
end)
--]]


sched.go()
