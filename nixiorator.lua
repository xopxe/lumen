local nixio = require("nixio")
local sched = require("sched")
local nixioutil = require ("nixio.util")
local pollt={}

local MINIMAL_WAIT = 0.01 --seconds

local M = {nixio=nixio}


local function client(polle)
	local skt=polle.fd
	local data=polle.it()
	if data and data ~= '' then
		sched.signal(skt, data)
	else
		M.unregister(skt)
		sched.signal(skt, nil, 'closed')
	end
end

local function accept(polle)
	local skt, host, port = polle.fd:accept()
	skt:setblocking(true)

	M.register_client(skt, polle.block)
	sched.signal(polle.fd, 'accepted', skt)
end


M.register_server = function (skt, block)
	local polle={
		fd=skt, 
		events=nixio.poll_flags("in"), 
		block=block or 8192,
		handler=accept
	}
	skt:listen(1024)
	pollt[#pollt+1]=polle
	return polle
end

M.register_client = function (skt, block)
	local polle={
		fd=skt, 
		events=nixio.poll_flags("in"), 
		block=block or 8192,
		handler=client
	}
	if polle.block=='line' then
		polle.it=skt:linesource()
	else
		polle.it=skt:blocksource(polle.block)
	end
	pollt[#pollt+1]=polle
	return polle
end

M.unregister = function (skt)
	for k, v in ipairs(pollt) do 
		if skt==v.fd then 
			table.remove(pollt,k) 
			return
		end
	end
end

M.step = function (timeout)

	timeout=timeout or -1
	if timeout == 0 then timeout=MINIMAL_WAIT end
        local stat, code = nixio.poll(pollt, timeout*1000)
	if stat and stat > 0 then
		for _, polle in ipairs(pollt) do
			if polle.revents and polle.revents ~= 0 then 
				polle:handler()
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


