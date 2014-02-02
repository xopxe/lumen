---
-- A task that interfaces with nixio. Supports UDP, TCP and async
-- file I/O.
-- Should run as root or sudo, for reading /dev/input/mice

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua"

--require "strict"

local sched = require "lumen.sched"


local service=arg[1] or 'luasocket'
--local service='nixio'
print ('using service:', service)

local selector = require "lumen.tasks.selector".init({service=service})

--sched.sigrun({sched.EVENT_ANY}, function(...) print("?", ...) end)

--[[ udp
-- Print out data arriving on a udp socket
local udprecv = selector.new_udp(nil, nil, "127.0.0.1", 8888, -1)
sched.sigrun(
	{udprecv.events.data}, 
	function(_, ...) print("!U", ...) end
)

-- Send data over an udp socket
sched.run(function()
	local udpsend = selector.new_udp("127.0.0.1", 8888)
	while true do
		local m="ping! "..os.time()
		print("udp sending",m)
		udpsend:send(m)
		sched.sleep(1)
	end
end)
--]]

---[[ tcp sync
local tcp_server = selector.new_tcp_server("127.0.0.1", 8888, nil, 'stream')
--local tcp_server = selector.new_tcp_server("127.0.0.1", 8888, 'line', 'stream')

sched.sigrun({tcp_server.events.accepted}, function(_, sktd, err)
  assert(sktd, err)
  print ('client accepted', sktd.stream)
  sched.run( function()
      while true do
        --print ('?', sktd.stream, sktd.stream.len)
        --sched.sleep(1)
        local line = assert(sktd.stream:read_line())
        print ('tcp arrived on', sktd.stream, line)
      end
  end)
end)
local tcp_client1 = selector.new_tcp_client("127.0.0.1",8888)
sched.run(function()
	--while true do
	for i=1, 15 do
		local m="ping! "..os.time()
		print("tcp 1 sending",m)
		tcp_client1:send(m.."\n")
		sched.sleep(2.1)
	end
	tcp_client1:close()
end)
local tcp_client2 = selector.new_tcp_client("127.0.0.1",8888)
sched.run(function()
	--while true do
	for i=1, 15 do
		local m="pong! "..os.time()
		print("tcp 2 sending",m)
		tcp_client2:send(m.."\n")
		sched.sleep(1.5)
	end
	tcp_client2:close()
end)--]]

--[[ tcp async
local total=0
local tcp_server = selector.new_tcp_server("127.0.0.1",8888,500, function(sktd, data, err, part)
	local data_read = #(data or '')
	total=total+ data_read 
	print ('-----', data_read, total, #(part or ''), err or '', data:sub(1,3),data:sub(-3))
	assert(total <= 100500)
	--sktd:close()
	return true
end)
local tcp_client = selector.new_tcp_client("127.0.0.1", 8888, nil, nil, 10000)
sched.run(function()
	--while true do
	local s = 'ab'..string.rep('x', 100496)..'yz'
	print("tcp sending",#s)
	tcp_client:send_async(s)
	print ('tcp sent')
	sched.sleep(10)
	--tcp_client:close()
end)
--]]


sched.loop()
