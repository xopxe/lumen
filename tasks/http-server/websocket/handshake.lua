require'pack'

local sha1 = require'tasks/http-server/websocket/tools'.sha1
local base64 = require'tasks/http-server/websocket/tools'.base64
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
		format('Host: %s',req.host),
		'Upgrade: websocket',
		'Connection: Upgrade',
		format('Sec-WebSocket-Key: %s',req.key),
		format('Sec-WebSocket-Protocol: %s',table.concat(req.protocols,', ')),
		'Sec-WebSocket-Version: 13',
	}
	if req.origin then
		tinsert(lines,string.format('Origin: %s',req.origin))
	end
	if req.port and req.port ~= 80 then
		lines[2] = format('Host: %s:%d',req.host,req.port)
	end
	tinsert(lines,'\r\n')
	return table.concat(lines,'\r\n')
end

local accept_upgrade = function(request,protocols)
	local headers = request --http_headers(request)

	if headers['Upgrade'] ~= 'websocket' or
	not headers['Connection'] or
	not headers['Connection']:match('Upgrade') or
		headers['Sec-WebSocket-Key'] == nil or
		headers['Sec-WebSocket-Version'] ~= '13' then
		return 400, nil, nil --'HTTP/1.1 400 Bad Request\r\n\r\n'
	end
	local prot
	if headers['Sec-WebSocket-Protocol'] then
		for protocol in headers['Sec-WebSocket-Protocol']:gmatch('([^,%s]+)%s?,?') do
			if protocols[protocol] then
				prot = protocol
				break
			end
		end
	end
	local out_header = {
		['Upgrade'] = 'websocket',
		['Connection'] = headers['Connection'],
		['Sec-WebSocket-Accept'] = sec_websocket_accept(headers['Sec-WebSocket-Key']),
	}
	if prot then 
		out_header['Sec-WebSocket-Protocol'] = prot
	end
	
	return 101, out_header, prot
end

return {
	sec_websocket_accept = sec_websocket_accept,
	http_headers = http_headers,
	accept_upgrade = accept_upgrade,
	upgrade_request = upgrade_request,
}
