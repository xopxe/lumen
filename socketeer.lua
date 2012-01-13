local socket = require("socket")
local sched = require("sched")

local weak_key = { __mode = 'k' }

local recvt={}

local sktmode = setmetatable({}, weak_key)
local isserver = setmetatable({}, weak_key)


local M = {socket=socket}

M.register_server = function (skt, pattern)
	isserver[skt]=true
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end

M.register_client = function (skt, pattern)
	--skt:settimeout(0)
	sktmode[skt] = pattern
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
	local recvt_ready, _, err = socket.select(recvt, nil, timeout)
	--print('-', #recvt_ready, err)
	if err~='timeout' then
		for _, skt in ipairs(recvt_ready) do
			local mode = sktmode[skt]
			if isserver[skt] then 
				local client, err=skt:accept()
				if client then
					M.register_client(client, mode)
					sched.signal(skt, 'accepted', client)
				else
					sched.signal(skt, 'fail', err)
				end
			else
				local data,err = skt:receive(mode)
				if err=='closed' then M.unregister(skt) end
				if err then 
					sched.signal(skt, data, err)
				else
					sched.signal(skt, data)
				end
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


