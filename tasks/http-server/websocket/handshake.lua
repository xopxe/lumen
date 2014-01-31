-- websocket support adaptded from lua-websocket (http://lipp.github.io/lua-websockets/)

local sha1 = require'lumen.tasks.http-server.sha1'.sha1_binary
local base64 = require'lumen.tasks.http-server.base64'
local tinsert = table.insert

local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

local sec_websocket_accept = function(sec_websocket_key)
	local a = sec_websocket_key..guid
	local a_sha1 = sha1(a)
	assert((#a_sha1 % 2) == 0)
	return base64.encode(a_sha1)
end

local http_headers = function(request)
	local headers = {}
	if not request:match('.*HTTP/1%.1') then
		return
	end
	request = request:match('[^\r\n]+\r\n(.*)')
	local empty_line
	for line in request:gmatch('[^\r\n]*\r\n') do
		local name,val = line:match('([^%s]+)%s*:%s*([^\r\n]+)')
		if name and val then
			name = name:lower()
			if not name:match('sec%-websocket') then
				val = val:lower()
			end
			if not headers[name] then
				headers[name] = val
			else
				headers[name] = headers[name]..','..val
			end
		elseif line == '\r\n' then
			empty_line = true
		else
			assert(false,line..'('..#line..')')
		end
	end
	return headers,request:match('\r\n\r\n(.*)')
end

local upgrade_request = function(req)
	local format = string.format
	local lines = {
		format('GET %s HTTP/1.1',req.uri or ''),
		format('host: %s',req.host),
		'upgrade: websocket',
		'connection: Upgrade',
		format('sec-websocket-key: %s',req.key),
		format('sec-websocket-protocol: %s',table.concat(req.protocols,', ')),
		'sec-websocket-version: 13',
	}
	if req.origin then
		tinsert(lines,string.format('origin: %s',req.origin))
	end
	if req.port and req.port ~= 80 then
		lines[2] = format('host: %s:%d',req.host,req.port)
	end
	tinsert(lines,'\r\n')
	return table.concat(lines,'\r\n')
end

local accept_upgrade = function(request,protocols)
	local headers = request --http_headers(request)

	if headers['upgrade'] ~= 'websocket' or
	not headers['connection'] or
	not headers['connection']:match('Upgrade') or
		headers['sec-websocket-key'] == nil or
		headers['sec-websocket-version'] ~= '13' then
		return 400, nil, nil --'HTTP/1.1 400 Bad Request\r\n\r\n'
	end
	local prot
	if headers['sec-websocket-protocol'] then
		for protocol in headers['sec-websocket-protocol']:gmatch('([^,%s]+)%s?,?') do
			if protocols[protocol] then
				prot = protocol
				break
			end
		end
	end
	local out_header = {
		['upgrade'] = 'websocket',
		['connection'] = headers['connection'],
		['sec-websocket-accept'] = sec_websocket_accept(headers['sec-websocket-key']),
	}
	if prot then 
		out_header['sec-websocket-protocol'] = prot
	end
	
	return 101, out_header, prot
end

return {
	sec_websocket_accept = sec_websocket_accept,
	http_headers = http_headers,
	accept_upgrade = accept_upgrade,
	upgrade_request = upgrade_request,
}
