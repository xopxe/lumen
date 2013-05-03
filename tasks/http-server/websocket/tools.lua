local base64_encode = require 'tasks/http-server/websocket/base64'.encode
local mrandom = math.random

-- used for generate key random ops
math.randomseed(os.time())

local parse_url = function(url)
  local protocol,host = url:match('^(%w+)://([^:/]+)')
  local port,uri = url:match('.+//[^:/]+:?(%d*)(.*)')
  if port and port ~= '' then
    port = tonumber(port)
  elseif protocol == 'ws' then
    port = 80
  end
  if not uri or uri == '' then
    uri = '/'
  end
  if not protocol or not host or not port or not uri then
    error('Invalid URL:'..url)
  end
  return protocol,host,port,uri
end

local generate_key = function()
  local key = string.char(
	mrandom(0,0xff),
	mrandom(0,0xff),
 	mrandom(0,0xff),
	mrandom(0,0xff),
 	mrandom(0,0xff),
	mrandom(0,0xff),
 	mrandom(0,0xff),
	mrandom(0,0xff),
	mrandom(0,0xff),
	mrandom(0,0xff),
 	mrandom(0,0xff),
	mrandom(0,0xff),
 	mrandom(0,0xff),
	mrandom(0,0xff),
 	mrandom(0,0xff),
	mrandom(0,0xff)
   )
  
  assert(#key==16,#key)
  return base64_encode(key)
end

return {
  parse_url = parse_url,
  generate_key = generate_key,
}
