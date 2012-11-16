local sched = require 'sched'
local selector = require 'tasks/selector'
local signals = require 'catalog'.get_catalog('signals')
local tasks = require 'catalog'.get_catalog('tasks')


 require 'lib/bencode'

local M = {}

local function vararg_to_bencodeable(...)
	local n=select('#',...) 
	local b = {n=n}
	for i=1, n do
		b[tostring(i)] = select(i, ...)
	end
	return b
end

local function bencodeable_to_vararg(b)
	for i=1, b.n do
		b[i] = b[tostring(i)]
	end
	return unpack(b, 1, b.n)
end

M.new_remote_waitd = function(ip, port, waitd_table)
	local incomming_signal = {}
	local encoded = bencode.encode(waitd_table)
	print ('>>>', encoded)

	sktd = selector.new_tcp_client(ip, port, nil, nil, 'line', function(sktd, data, err) 
		if not data then sched.running_task:kill() end
		print ('incomming', data)
		local decoded = assert(bencode.decode(data))
		sched.signal(incomming_signal, bencodeable_to_vararg(decoded))
	end)
	sktd:send_sync(encoded.."\n")
	local remote_waitd = sched.new_waitd ({
		emitter = selector.task,
		events = {incomming_signal},
	})
	
	return remote_waitd
end

M.init = function(conf)
	local ip = assert(conf.ip)
	local port = conf.port or 1985
	--M.task = sched.run(function()
	M.skt_server = selector.new_tcp_server(ip, port, 'line', function(sktd, data, err)
		if data then 
			local rwaitd = bencode.decode(data)
			print ('<<<', rwaitd.events)
			--rwaitd.emitter =
			
			local remitter, emitter = rwaitd.emitter, {}
			for i=1, #remitter do
				local e = remitter[i]
				if e=='*' then
					emitter[#emitter+1] = '*'
				else
					emitter[#emitter+1] = tasks:waitfor(e, 0)
				end
			end
			rwaitd.emitter = emitter
			
			local revents, events = rwaitd.events, {}
			for i=1, #revents do
				local e = revents[i]
				if e=='*' then
					events[#events+1] = '*'
				else
					events[#events+1] = signals:waitfor(revents[i], 0)
				end
			end
			rwaitd.events = events
			
			sched.sigrun(rwaitd, function(_,_,...)
				print ('caught', ...)
				local encoded = assert(bencode.encode(vararg_to_bencodeable(...)))
				sktd:send_sync(encoded..'\n')
			end)
		end
	end)
	--end)
end


return M