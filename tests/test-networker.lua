---
-- A task that interfaces with nixio. Supports UDP, TCP and async
-- file I/O.
-- Should run as root or sudo, for reading /dev/input/mice

--look for packages one folder up.
package.path = package.path .. ";;;../?.lua"

require "strict"

local sched = require "sched"
local catalog = require "catalog"

--local service='socketeer' 
local service='nixiorator'


local networker = require "tasks/networker".init({service=service})

-- Print out data arriving on a udp socket
print ('1+')
local udprecv = networker.new_udp(nil, nil, "127.0.0.1", 8888)
print ('1-')
sched.sigrun(
	{emitter=udprecv.task, events={udprecv.events.data}}, 
	function(_, _, ...) print("!U", ...) end
)

-- Send data over an udp socket
sched.run(function()
	print ('2+')
	local udpsend = networker.new_udp("127.0.0.1", 8888)
	print ('2-')
	while true do
		local m="ping! "..os.time()
		print("udp sending",m)
		udpsend:send(m)
		sched.sleep(2)
	end
end)


sched.go()
