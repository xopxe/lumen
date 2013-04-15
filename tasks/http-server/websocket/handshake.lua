
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
      for _,supported in ipairs(protocols) do
        if supported.protocol == protocol then
          prot = supported
          break
        end
      end
      if prot then
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
		out_header['Sec-WebSocket-Protocol'] = prot.protocol
	end

  return 101, out_header, prot
end

return {
  sec_websocket_accept = sec_websocket_accept,
  accept_upgrade = accept_upgrade,
}
