local frame = require 			'lumen.tasks.http-server.websocket.frame'
local handshake = require		'lumen.tasks.http-server.websocket.handshake'
local http_util = require		'lumen.tasks.http-server.http-util'
local base64_encode = require	'lumen.tasks.http-server.base64'.encode


local tinsert = table.insert
local tconcat = table.concat
local mrandom = math.random

local generate_key = function()
	local key = string.char(
		mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff),
		mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff),
		mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff),
		mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff),mrandom(0,0xff)
	)

	assert(#key==16,#key)
	return base64_encode(key)
end

local receive = function(self)
	if self.state ~= 'OPEN' and self.state ~= 'CLOSING' then
		return nil, 'failed', 'bad state: '..tostring(self.state)
	end
	local stream = assert(self.sktd.stream)
	local first_opcode
	local frames
	local bytes = 3
	local encoded = ''
	while true do
		local chunk,err = stream:read(bytes)
		if err then
			return nil, 'failed', err
		end
		encoded = encoded..chunk
		local decoded,fin,opcode,_,masked = frame.decode(encoded)

		if not self.is_server and masked then
			return nil,'failed', 'frame was not masked'
		end
		if decoded then
			if opcode == self.CLOSE then
				if self.state ~= 'CLOSING' then
					self:send(decoded,self.CLOSE)
					self.state = 'CLOSED'
					if self.on_close then
						self:on_close()
					end
					return nil,'closed'
				else
					return decoded,opcode
				end
			end
			if not first_opcode then
				first_opcode = opcode
			end
			if not fin then
				if not frames then
					frames = {}
				elseif opcode ~= self.CONTINUATION then
					tinsert(frames,decoded)
					return nil,'protocol',tconcat(frames),first_opcode,opcode
				end
				bytes = 3
				encoded = ''
				tinsert(frames,decoded)
			elseif not frames then
				return decoded,first_opcode
			else
				tinsert(frames,decoded)
				return tconcat(frames),first_opcode
			end
		else
			assert(type(fin) == 'number' and fin > 0)
			bytes = fin
		end
	end
end

local send = function(self,data,opcode)
	if self.state ~= 'OPEN' then
		return nil,'not open'
	end
	local encoded = frame.encode(tostring(data),opcode or self.TEXT,not self.is_server)
	local ok,err = self.sktd:send_sync(encoded)
	if not ok then
		return nil, 'failed', err
	end
	return true
end

local close = function(self,code,reason)
	if self.state ~= 'OPEN' then
		return nil,'not open'
	end
	local msg = frame.encode_close(code or 1000,reason)
	self:send(msg,self.CLOSE)
	self.state = 'CLOSING'
	local rmsg,opcode = self:receive()
	self.sktd:close()
	if self.on_close then
		self:on_close()
	end
	if rmsg and rmsg:sub(1,2) == msg:sub(1,2) and opcode == self.CLOSE then
		return true
	end
	return nil,'protocol'
end

local connect = function(self,ws_url,ws_protocol)
  local stream = self.stream
  if self.state == 'OPEN' then
    return nil, 'already connected'
  end
  local protocol,host,port,uri = http_util.parse_url(ws_url)
  if protocol ~= 'ws' then
    return nil, 'bad protocol'
  end
  --XOP must be connected
  --self:sock_connect(host,port)
  local key = generate_key()
  local req = handshake.upgrade_request
  {
    key = key,
    host = host,
    port = port,
    protocols = {ws_protocol or ''},
    --FIXME origin = origin, 
    uri = uri
  }
  local ok,err = self.sktd:send_sync(req)
  if not ok then
    return nil, 'handshake failed', err
  end
  local resp = {}
  repeat
    local line,err = stream:read_line()
    if err then
      return nil, 'handshake failed', err
    end
    resp[#resp+1] = line
  until line == ''
  local response = table.concat(resp,'\r\n')
  local headers = handshake.http_headers(response)
  local expected_accept = handshake.sec_websocket_accept(key)
  if headers['sec-websocket-accept'] ~= expected_accept then
    local msg = 'Invalid Sec-Websocket-Accept (expected %s got %s)'
    return nil, 'handshake failed', msg:format(expected_accept,headers['sec-websocket-accept'] or 'nil')
  end
  self.state = 'OPEN'
  return true
end

local create_ws = function(sktd)
	assert(sktd.stream)
	assert(sktd.send_sync)
	assert(sktd.close)
	
	local ws = {
		sktd = sktd,
		receive = receive,
		send = send,
		close = close,
		connect = connect,
		
		CONTINUATION = 0,
		TEXT = 1,
		BINARY = 2,
		CLOSE = 8,
		PING = 9,
		PONG = 10,
	}
 	return ws
end

return {
	create_ws = create_ws
}
