--- Proxy service for signals.
-- This module allows to wait on and receive signals emitted in a remote
-- Lumen instance, trough a socket.
-- Signals are serialized using bencode, and thus bencode's restrictions 
-- on what can be passed trough apply: strings, numbers, lists (pure arrays) and
-- tables with strings as  keys.
-- This module depends on the selector task, which must be started
-- seperataly.
-- @usage  local proxy = require 'proxy'
--
-- --for accepting connections
-- proxy.init({ip='*', port=1985}) 
-- 
-- --connect to a remote node
-- local waitd = proxy.new_remote_waitd('192.1681.1', 1985, {
-- 	emitter = {'*'},
-- 	events = {'a_event_name', 'other_event_name'},
-- })
-- sched.wait(waitd, function(_, _, taskname, eventname, ...)
-- 	print ('received signal', taskname, eventname, ...)
-- end)
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
-- The waitd_table is as the one used in plain _sched.new\_waitd()_ call, with
-- the difference that the objects in the _emitter_ and _events_ fields are
-- names which will be queried in the remote node's "tasks" and "events" catalogs
-- (except '*', which has the usual meaning).
-- There is an additional parameter, _name\_timeout_, which controls the querying
-- in the catalogs.
-- The obtained waitd will react with a non null event, followed by the remote emitter and
-- event names (as put in the waitd_table), followed by the parameters of the original event.
-- On timeout, returns _nil, 'timeout'_.
-- @param ip ip of the remote proxy module.
-- @param port port of the remote proxy module.
-- @param waitd_table a wait descriptor.
-- @return a waitd object
M.new_remote_waitd = function(ip, port, waitd_table)
	-- the timeout will be applied on the proxy's side
	local timeout = waitd_table.timeout
	waitd_table.timeout = nil
	
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
		timeout = timeout,
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

	local meta_name_default = {__index=function() return '*' end}
	local task_to_name = setmetatable({}, meta_name_default)
	local event_to_name = setmetatable({}, meta_name_default)
	
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
							local emname = remitter[i]
							if emname=='*' then
								emitter[#emitter+1] = '*'
							else
								local task = tasks_catalog:waitfor(emname, name_timeout)
								if task then
									emitter[#emitter+1] =task
									task_to_name[task] = emname
								end
							end
						end
						rwaitd.emitter = emitter
						
						local revents, events = rwaitd.events, {}
						for i=1, #revents do
							local evname = revents[i]
							if evname=='*' then
								events[#events+1] = '*'
							else
								local event = events_catalog:waitfor(evname, name_timeout)
								if event then 
									events[#events+1] = event
									event_to_name[event] = evname
								end
							end
						end
						rwaitd.events = events
						
						sched.sigrun(rwaitd, function(em, ev,...)
							--print ('caught', ...)
							local emname = event_to_name[em] 
							local evname = event_to_name[ev] 
							local bencodeable = vararg_to_bencodeable(emname, evname, ...)
							local encodedout, encodeerr = bencode.encode(bencodeable)
							if encoded then 
								sktd:send_sync(encodedout) 
							else
								log('PROXY', 'ERROR', 'failed to bencode event "%s" with error "%s"', 
									tostring(evname), tostring(encodeerr))
							end
						end)
					end)
				end
			else
				log('PROXY', 'ERROR', 'socket handler called with error "%s"', tostring(err))
			end
		end
	end
	
	log('PROXY', 'INFO', 'starting proxy on ip "%s" port "%s"', tostring(ip), tostring(port))
	M.skt_server = selector.new_tcp_server(ip, port, nil, get_request_handler())
end


return M