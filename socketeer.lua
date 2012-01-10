local socket = require("socket")
local sched = require("sched")

local MINIMAL_WAIT = 0.01 --seconds

local recvt={}

local M = {socket=socket}

M.register = function (skt)
	recvt[#recvt+1]=skt
end

M.unregister = function (skt)
	for k, v in ipairs(recvt) do 
		if skt==v then 
			table.remove(recvt,k) 
			return
		end
	end
end

M.step = function (timeout)
	--print('socket +', timeout)
	if timeout == 0 then timeout=MINIMAL_WAIT end
	local recvt_ready, _, err = socket.select(recvt, nil, timeout)
	--print('socket -', err)
	if err~='timeout' then
		for _, skt in ipairs(recvt_ready) do
			local data,err = skt:receive()
			if err then 
				sched.signal(skt, data, err)
			else
				sched.signal(skt, data)
			end
		end
	end
end

M.run = function ()
	while true do
		local t, _ = sched.yield()
		M.step( t )
	end
end

return M


