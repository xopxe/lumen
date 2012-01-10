require "strict"

local sched = require "sched"
local socketeer = require "socketeer"
local socket = socketeer.socket

local udprecv = assert(socket.udp())
assert(udprecv:setsockname("127.0.0.1", 8888))

local udpsend = assert(socket.udp())
assert(udpsend:setsockname("127.0.0.1", 0))
assert(udpsend:setpeername("127.0.0.1", 8888))


sched.get_time = socket.gettime
sched.idle = socket.sleep

---[[
sched.run(function() 
	socketeer.register(udprecv)
	local s = sched.run(socketeer.run)
	print('SOCKETEER',s)
	sched.sigrun(function(...) print("!U", ...) end, {emitter=s, events={udprecv}})
	sched.run(function()
		while true do
			local m="ping! "..os.time()
			print("sending",m)
			assert(udpsend:send(m))
			sched.sleep(3)
		end
	end)
end)
--]]

sched.go()
