---
-- A task that interfaces with nixio. Supports UDP, TCP and async
-- file I/O.
-- Should run as root or sudo, for reading /dev/input/mice

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

require "strict"

local sched = require "sched"
local catalog = require "catalog"

local service='socketeer' 
--local service='nixiorator'

local networker = require "tasks/networker".init({service=service})

---[[udp
-- Print out data arriving on a udp socket
local udprecv = networker.new_udp({locaddr="127.0.0.1", locport=8888})
sched.sigrun(
	{emitter=udprecv.task, events={udprecv.events.data}}, 
	function(_, _, ...) print("!U", ...) end
)

-- Send data over an udp socket
sched.run(function()
	local udpsend = networker.new_udp({address="127.0.0.1", port=8888})
	while true do
		local m="ping! "..os.time()
		print("udp sending",m)
		udpsend:send(m)
		sched.sleep(1)
	end
end)
--]]

---[[tcp
local tcp_server = networker.new_tcp_server({
	locaddr="127.0.0.1", 
	locport=8888,
	pattern='line',
	handler = function(sktd, data, err)
		print ('****', sktd, data, err or '')
	end
})

local tcp_client = networker.new_tcp_client({address="127.0.0.1", port=8888})
sched.run(function()
	--while true do
	for i=1, 15 do
		local m="ping! "..os.time()
		print("tcp sending",m)
		tcp_client:send(m.."\n")
		sched.sleep(0.1)
	end
	tcp_client:close()
end)
--]]

sched.go()
