--- Proxy service for signals.
-- This module allows to wait on and receive signals emitted in a remote
-- Lumen instance, trough a socket.  
-- Signals are serialized using bencode or json, and restrictions apply
-- on what can be passed trough depending on the encoder selected. For
-- example, under bencode strings, numbers, lists (pure arrays) and tables 
-- with strings as keys are supported.
-- This module depends on the selector task, which must be started
-- separataly.
-- @usage local proxy = require 'lumen.proxy'
--
-- --for accepting connections
-- proxy.init({ip='*', port=1985}) 
--
-- --connect to a remote node
-- local waitd = proxy.new_remote_waitd('192.168.1.1', 1985, 
--   {'a_event_name', 'other_event_name'})
--   sched.wait(waitd, function(_, eventname, ...)
--   print ('received signal', eventname, ...)
-- end)
-- @module proxy
-- @alias M
local lumen = require'lumen'

local log 				= lumen.log
local sched 			= lumen.sched
local stream 			= lumen.stream
local events_catalog 	= lumen.catalog.get_catalog('events')

local selector 	= require 'lumen.tasks.selector'

local unpack = unpack or table.unpack

local encode_f
local decode_f

local M = {}

local function vararg_to_encodeable(...)
	local n=select('#',...) 
	local b = {n=n}
	for i=1, n do
		b[tostring(i)] = select(i, ...)
	end
	return b
end

local function encodeable_to_vararg(b)
	for i=1, b.n do
		b[i] = b[tostring(i)]
	end
	return unpack(b, 1, b.n)
end

--- Creates a waitd object over a remote Lumen instance.
-- The remote Lumen instance must have the proxy module started,
-- and available trough a known ip address.
-- The waitd_table is as the one used in plain _sched.new\___waitd()_ call, with
-- the difference that the array part does not contain the events but the 
-- names which will be queried in the remote node's "events" catalog.
-- There is an additional parameter, _name\___timeout_, which controls the querying
-- in the catalogs.
-- The obtained waitd will react with a non null event, followed by the event name 
-- (as put in the waitd_table), followed by the parameters of the original event.
-- @param ip ip of the remote proxy module.
-- @param port port of the remote proxy module.
-- @param waitd_table a wait descriptor.
-- @return waitd object on success. _nil, err_ on failure
M.new_remote_waitd = function(ip, port, waitd_table)
	-- the timeout will be applied on the proxy's side
	local timeout = waitd_table.timeout
	waitd_table.timeout = nil
	
	local incomming_signal = {}
	local encoded = encode_f(waitd_table)
	
	local function get_incomming_handler()
		local buff = ''
		return function(sktd, data, err) 
			--print ('incomming', data, buff)
			if not data then return false end
			buff = buff .. data
			-- a chunk can hold several signals, or only part of one
			while buff ~= '' do
				local decoded, index, e = decode_f(buff)
				if not decoded then
					log('PROXY', 'DEBUG', 'waiting for more data, buff with length %s does not decode: "%s"',
						tostring(#buff), tostring(index).." "..tostring(e))
					break
				end
				buff = buff:sub(index)
				sched.signal(incomming_signal, encodeable_to_vararg(decoded))
			end
			return true
		end
	end

	local sktd_client, err = selector.new_tcp_client(ip, port, nil, nil, nil, get_incomming_handler())
	if err then
		return nil, 'could not create remote waitd:'..err
	end
	sktd_client:send_sync(encoded)
	local remote_waitd = {
		incomming_signal,
		timeout = timeout,
	}
	return remote_waitd
end

--- Starts the proxy.
-- This starts the task that will accept incomming wait requests.
-- @param conf the configuration table (see @{conf})
M.init = function(conf)
	local ip = conf.ip or '*'
	local port = conf.port or 1985
	local encoder = conf.encoder or 'json'

	if encoder =='json' then encoder = 'dkjson' end
	local encoder_lib = require ('lumen.lib.'..encoder)
	encode_f = encoder_lib.encode
	decode_f = encoder_lib.decode

	local meta_name_default = {__index=function() return '*' end}
	local task_to_name = setmetatable({}, meta_name_default)
	
	-- per connection state: the receive buffer, and the tasks forwarding events
	-- (the request handler is shared by all the connections)
	local buffs = setmetatable({}, {__mode = 'k'})
	local forwarders = setmetatable({}, {__mode = 'k'})

	-- stop serving a connection, killing its forwarding tasks
	local function drop_connection(sktd)
		buffs[sktd] = nil
		local tasks = forwarders[sktd]
		forwarders[sktd] = nil
		if not tasks then return end
		-- the running task may be one of them: kill it last, as it does not return
		for task in pairs(tasks) do
			if task ~= sched.running_task then sched.kill(task) end
		end
		if tasks[sched.running_task] then sched.kill(sched.running_task) end
	end

	local function forward(sktd, evname, ...)
		local encodeable = vararg_to_encodeable(evname, ...)
		-- bencode returns nil on failure, dkjson raises an error
		local ok, encodedout, encodeerr = pcall(encode_f, encodeable)
		if not ok then encodedout, encodeerr = nil, encodedout end
		if not encodedout then
			log('PROXY', 'ERROR', 'failed to encode event "%s" with error "%s"',
				tostring(evname), tostring(encodeerr))
			return
		end
		local sent, senderr = sktd:send_sync(encodedout)
		if not sent then
			log('PROXY', 'DETAIL', 'dropping connection, sending failed with error "%s"',
				tostring(senderr))
			sktd:close()
			drop_connection(sktd)
		end
	end

	-- start forwarding the events requested in rwaitd through sktd
	local function serve_request(sktd, rwaitd)
		local task = sched.new_task( function()
			local name_timeout = rwaitd.name_timeout

			-- recover all request all events
			-- names are kept per request: an event renamed in the catalog is still
			-- reported with the name this client asked for
			local nwaitd, event_to_name, rnames = {}, {}, rwaitd.events
			for i=1, #rnames do
				local evname = rnames[i]
				local event = events_catalog:waitfor(evname, name_timeout)
				log('PROXY', 'DETAIL', 'event "%s" recovered from catalog:  "%s"',
					tostring(evname), tostring(event))
				if event then
					nwaitd[#nwaitd+1] = event
					event_to_name[event] = evname
				end
			end

			local function forward_event(ev, ...)
				forward(sktd, event_to_name[ev], ...)
			end
			while true do
				forward_event(sched.wait(nwaitd))
			end
		end)
		forwarders[sktd] = forwarders[sktd] or {}
		forwarders[sktd][task] = true
		sched.run(task)
	end

	local function request_handler(sktd, encoded, err)
		if encoded then
			local buff = (buffs[sktd] or '') .. encoded
			-- a chunk can hold several requests, or only part of one
			while buff ~= '' do
				local rwaitd, index = decode_f(buff)
				if not rwaitd then break end
				buff = buff:sub(index)
				serve_request(sktd, rwaitd)
			end
			buffs[sktd] = buff
		else
			log('PROXY', 'DEBUG', 'socket handler called with error "%s"', tostring(err))
			drop_connection(sktd)
			return
		end
		return true
	end
	
	log('PROXY', 'INFO', 'starting proxy on %s:%s, using %s', tostring(ip), tostring(port), tostring(encoder))
	M.skt_server = selector.new_tcp_server(ip, port, nil, request_handler)
end

--- Configuration Table.
-- @table conf
-- @field ip the ip where the server listens (defaults to '*')
-- @field port the port where the server listens (defaults to 1985)
-- @field encoder the encoding method to use: 'bencode' or 'json' (default).

return M