require "strict"

local sched = require "sched"
local socketeer = require "socketeer"
local socket = socketeer.socket

--udp
--[[
local udprecv = assert(socket.udp())
assert(udprecv:setsockname("127.0.0.1", 8888))

local udpsend = assert(socket.udp())
assert(udpsend:setsockname("127.0.0.1", 0))
assert(udpsend:setpeername("127.0.0.1", 8888))
--]]

sched.get_time = socket.gettime
sched.idle = socket.sleep

---[[
sched.run(function() 
	sched.catalog.register('MAIN')
	local s = sched.run(socketeer.run)
	print('SOCKETEER',s)

	--udp
	--[[
	socketeer.register(udprecv)
	sched.sigrun(function(...) print("!U", ...) end, {emitter=s, events={udprecv}})
	sched.run(function()
		while true do
			local m="ping! "..os.time()
			print("udp sending",m)
			assert(udpsend:send(m))
			sched.sleep(3)
		end
	end)
	--]]

	--tcp
	sched.run(function()
		sched.catalog.register('TCPLISTEN')
		local server = assert(socket.bind('127.0.0.1', 8888))
		socketeer.register_server(server)
		while true do 
			local skt, msg, inskt  = sched.wait({emitter=s, events={server}})
			print ("#", os.time(), skt, msg, inskt )
			if msg=='accepted' then 
				sched.sigrun(function(...) print("!T", ...) end, {emitter=s, events={inskt}})
			end
		end
	end)
	sched.run(function()
		sched.catalog.register('TCPSEND')
		local tcpcli = socket.connect('127.0.0.1', 8888)
		while true do
			sched.sleep(1)
			local m="ping! "..os.time()
			print("tcp sending",m)
			assert(tcpcli:send(m.."\n"))
		end
	end)
end)
--]]

sched.go()
