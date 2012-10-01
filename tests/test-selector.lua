---
-- A task that interfaces with nixio. Supports UDP, TCP and async
-- file I/O.
-- Should run as root or sudo, for reading /dev/input/mice

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

require "strict"

local sched = require "sched"

--local service='luasocket'
local service='nixio'
print ('using service:', service)

local selector = require "tasks/selector".init({service=service})

--[[ udp
-- Print out data arriving on a udp socket
local udprecv = selector.new_udp({locaddr="127.0.0.1", locport=8888})
sched.sigrun(
	{emitter=udprecv.task, events={udprecv.events.data}}, 
	function(_, _, ...) print("!U", ...) end
)

-- Send data over an udp socket
sched.run(function()
	local udpsend = selector.new_udp({address="127.0.0.1", port=8888})
	while true do
		local m="ping! "..os.time()
		print("udp sending",m)
		udpsend:send(m)
		sched.sleep(1)
	end
end)
--]]

---[[ tcp sync
local tcp_server = selector.new_tcp_server({
	locaddr="127.0.0.1", 
	locport=8888,
	--pattern='line',
	pattern=10,
	handler = function(sktd, data, err)
		print ('!T', data, err or '')
	end
})
local tcp_client = selector.new_tcp_client({address="127.0.0.1", port=8888})
sched.run(function()
	--while true do
	for i=1, 15 do
		local m="ping! "..os.time()
		print("tcp sending",m)
		tcp_client:send(m.."\n")
		sched.sleep(2.1)
	end
	tcp_client:close()
end)
local tcp_client2 = selector.new_tcp_client({address="127.0.0.1", port=8888})
sched.run(function()
	--while true do
	for i=1, 15 do
		local m="pong! "..os.time()
		print("tcp sending",m)
		tcp_client:send(m.."\n")
		sched.sleep(1.5)
	end
	tcp_client:close()
end)--]]

--[[ tcp async
local total=0
local tcp_server = selector.new_tcp_server({
	locaddr="127.0.0.1", 
	locport=8888,
	pattern=1000,
	handler = function(sktd, data, err, part)
		local data_read = #(data or '')
		total=total+ data_read 
		print ('-----', data_read, total, #(part or ''), err or '')
		--sktd:close()
	end
})
local tcp_client = selector.new_tcp_client({
	address="127.0.0.1", 
	port=8888,
	pattern=10000, 
})
sched.run(function()
	--while true do
	local s = string.rep('x', 100500)
	print("tcp sending",#s)
	tcp_client:send_async(s)
	print ('tcp sent')
	sched.sleep(10)
	--tcp_client:close()
end)
--]]


sched.go()
