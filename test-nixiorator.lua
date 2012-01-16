--should run as root or sudo, for reading /dev/input/mice

require "strict"

local sched = require "sched"
local nixiorator = require "nixiorator"
local nixio = nixiorator.nixio

local udprecv = assert(nixio.bind("127.0.0.1", 8888, 'inet', 'dgram'))
local fdrecv = nixio.open('/dev/input/mice', nixio.open_flags('rdonly', 'sync'))

sched.idle = nixio.idle or sched.idle
if nixio.gettime then
	sched.get_time = nixio.gettime
end

sched.run(function() 
	nixiorator.register_client(udprecv, 1500)
	nixiorator.register_client(fdrecv, 10)
	local nxtask = sched.run(nixiorator.task)
	print('NIXIORATOR',nxtask)
	sched.sigrun(function(file, data) print("!F", file, string.byte(data)) end, {emitter=nxtask, events={fdrecv}})
	sched.sigrun(function(...) print("!U", ...) end, {emitter=nxtask, events={udprecv}})
	sched.run(function()
		local tcprecv = assert(nixio.bind("127.0.0.1", 8888, 'inet', 'stream'))
		nixiorator.register_server(tcprecv, 'line')
		sched.catalog.register("accepter")
		local waitd={emitter=nxtask, events={tcprecv}}
		while true do
			local skt, msg, inskt  = sched.wait(waitd)
			print ("#", os.time(), skt, msg, inskt )
			if msg=='accepted' then 
				sched.sigrun(function(skt, data, err) 
					print("!T", skt, data, err) 
					if not data then sched.kill() end
				end, {emitter=nxtask, events={inskt}})
			end
		end
	end)
	sched.run(function()
		sched.catalog.waitfor('accepter')
		local tcpsend = assert(nixio.bind("127.0.0.1", 0, 'inet', 'stream'))
		tcpsend:connect("127.0.0.1",8888)
		while true do
			local m="ping! "..os.time()
			print("tcp sending",m)
			tcpsend:writeall(m.."\n")
			sched.sleep(3)
		end
	end)
	sched.run(function()
		local udpsend = assert(nixio.bind("127.0.0.1", 0, 'inet', 'dgram'))
		udpsend:connect("127.0.0.1",8888)
		while true do
			local m="ping! "..os.time()
			print("udp sending",m)
			udpsend:send(m)
			sched.sleep(2)
		end
	end)


end)


sched.go()
