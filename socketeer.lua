local socket = require("socket")
local sched = require("sched")

--get locals for some useful things
local setmetatable, ipairs, table, type = setmetatable, ipairs, table, type 

local weak_key = { __mode = 'k' }

local recvt={}

local sktmode = setmetatable({}, weak_key)
local isserver = setmetatable({}, weak_key)
local partial = setmetatable({}, weak_key)

local M = {socket=socket}

M.register_server = function (skt, pattern)
	isserver[skt]=true
	skt:settimeout(0)
	sktmode[skt] = pattern
	recvt[#recvt+1]=skt
end

M.register_client = function (skt, pattern)
	skt:settimeout(0)
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
	--print('+', timeout)
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
				--print('&+', skt, mode, partial[skt])
				if type(mode) == "number" and mode <= 0 then
					local data,err,part = skt:receive(65000)
					--print('&-',data,err,part, #part)
					if err=='closed' then
						M.unregister(skt)
						sched.signal(skt, nil, err, part) --data is nil or part?
					else
						sched.signal(skt, data)
					end
				else
					local data,err,part = skt:receive(mode,partial[skt])
					partial[skt]=part
					--print('&-',data,err,part)
					if not data then
						if err=='closed' then 
							M.unregister(skt)
							sched.signal(skt, nil, err, part) --data is nil or part?
						elseif not part or part=='' then
							sched.signal(skt, nil, err)
						end
					else
						sched.signal(skt, data)
					end
				end
			end
		end
	end
end

M.task = function ()
	sched.catalog.register('socketeer')
	while true do
		local t, _ = sched.yield()
		M.step( t )
	end
end

return M


