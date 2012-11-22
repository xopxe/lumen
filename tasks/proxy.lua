--- Proxy service for signals.
-- This module allows to wait on and receive signals emitted in a remote
-- Lumen instance, trough a socket.
-- Signals are serialized using bencode, and thus bencode's restrictions 
-- on what can be passed trough apply: strings, numbers, lists (pure arrays) and
-- tables with strings as  keys.
-- This module depends on the selector task, which must be started
-- seperataly.
-- @module proxy
-- @alias M

local sched = require 'sched'
local selector = require 'tasks/selector'
local events_catalog = require 'catalog'.get_catalog('events')
local tasks_catalog = require 'catalog'.get_catalog('tasks')
local log=require 'log'


require 'lib/bencode'
local bencode = bencode

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

--- Creates a waitd object over a remote Lumen instance.
-- The remote Lumen instance must have the proxy module started,
-- and available trough a known ip address.
-- The waitd_table is as the one used in plain _sched\.wait()_ call, with
-- the difference that the objects in the _emitter_ and _events_ fields are
-- names which will be queried in the remote node's "tasks" and "events" catalogs
-- (except '*', which has the usual meaning).
-- There is an additional parameter, _name\_timeout_, which controls the querying
-- in the catalogs.
-- @param ip ip of the remote proxy module.
-- @param port port of the remote proxy module.
-- @param waitd_table a wait descriptor.
-- @return a waitd object
M.new_remote_waitd = function(ip, port, waitd_table)
	local incomming_signal = {}
	local encoded = bencode.encode(waitd_table)
	--print ('>>>', encoded)
	
	local function get_incomming_handler()
		local buff = ''
		return function(sktd, data, err) 
			if not data then sched.running_task:kill() end
			buff = buff .. data
			--print ('incomming', buff)
			local decoded, index, e = bencode.decode(buff)
			if decoded then 
				buff = buff:sub(index)
				sched.signal(incomming_signal, bencodeable_to_vararg(decoded)) 
			else
				log('PROXY', 'ERROR', 'failed to bdecode buff  with length %s with error "%s"', tostring(#buff), tostring(index).." "..tostring(e))
			end
		end
	end

	local sktd_client = selector.new_tcp_client(ip, port, nil, nil, nil, get_incomming_handler())
	sktd_client:send_sync(encoded)
	local remote_waitd = sched.new_waitd ({
		emitter = selector.task,
		events = {incomming_signal},
	})
	
	return remote_waitd
end

--- Starts the proxy.
-- This starts the task that will accept incomming wait requests.
-- @param conf the configuration table. The fields of interest are
-- _ip_  of the service (defaults to '*') and _port_ of the service (defaults to 1985)
M.init = function(conf)
	local ip = conf.ip or '*'
	local port = conf.port or 1985
	--M.task = sched.run(function()
	
	local function get_request_handler()
		local buff = ''
		return function(sktd, encoded, err)
			if encoded then 
				buff=buff .. encoded
				local rwaitd, index = bencode.decode(buff)
				
				if rwaitd then
					buff = buff:sub(index)
					
					sched.run( function()
						local name_timeout = rwaitd.name_timeout
						local remitter, emitter = rwaitd.emitter, {}
						for i=1, #remitter do
							local e = remitter[i]
							if e=='*' then
								emitter[#emitter+1] = '*'
							else
								emitter[#emitter+1] = tasks_catalog:waitfor(e, name_timeout)
							end
						end
						rwaitd.emitter = emitter
						
						local revents, events = rwaitd.events, {}
						for i=1, #revents do
							local e = revents[i]
							if e=='*' then
								events[#events+1] = '*'
							else
								events[#events+1] = events_catalog:waitfor(e, name_timeout)
							end
						end
						rwaitd.events = events
						
						sched.sigrun(rwaitd, function(_, e,...)
							--print ('caught', ...)
							local bencodeable = vararg_to_bencodeable(e, ...)
							local encoded, err = bencode.encode(bencodeable)
							if encoded then 
								sktd:send_sync(encoded) 
							else
								log('PROXY', 'ERROR', 'failed to bencode event "%s" with error "%s"', tostring(e), tostring(err))
							end
						end)
					end)
				end
			end
		end
	end
	
	log('PROXY', 'INFO', 'starting proxy on ip "%s" port "%s"', tostring(ip), tostring(port))	
	M.skt_server = selector.new_tcp_server(ip, port, nil, get_request_handler())
end


return M