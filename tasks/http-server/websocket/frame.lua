-- websocket support adaptded from lua-websocket (http://lipp.github.io/lua-websockets/)
-- Following Websocket RFC: http://tools.ietf.org/html/rfc6455
--require'pack'
local bit = require'lumen.tasks.http-server.websocket.bit'

local band = bit.band
local bxor = bit.bxor
local bor = bit.bor
--local sunpack = string.unpack
--local spack = string.pack
local ssub = string.sub
local sbyte = string.byte
local schar = string.char
local tinsert = table.insert
local tconcat = table.concat
local mmin = math.min

local unpack = unpack or table.unpack

local bits = function(...)
  local n = 0
  for _,bitn in pairs{...} do
    n = n + 2^bitn
  end
  return n
end

local bit_7 = bits(7)
local bit_0_3 = bits(0,1,2,3)
local bit_0_6 = bits(0,1,2,3,4,5,6)

--from http://stackoverflow.com/questions/5241799/lua-dealing-with-non-ascii-byte-streams-byteorder-change
--adapted for fixed 4 byte bigendian unsigned ints.
function int_to_bytes(num)
    local res={}
    local n = 4 --math.ceil(select(2,math.frexp(num))/8) -- number of bytes to be used.
    for k=n,1,-1 do -- 256 = 2^8 bits per char.
        local mul=2^(8*(k-1))
        res[k]=math.floor(num/mul)
        num=num-res[k]*mul
    end
    assert(num==0)
    if endian == "big" then
        local t={}
        for k=1,n do
            t[k]=res[n-k+1]
        end
        res=t
    end
    return string.char(unpack(res))
end
function bytes_to_int(str,endian)
    local t={str:byte(1,4)}
    local n=0
    for k=1,#t do
        n=n+t[#t-k+1]*2^((k-1)*8)
    end
    return n
end

local function getunsigned_2bytes_bigendian(s)
	return 256*s:byte(1) + s:byte(2)
end

local xor_mask = function(encoded,mask,payload)
  local transformed_arr = {}
  -- xor chunk-wise to prevent stack overflow.
  -- sbyte and schar multiple in/out values
  -- which require stack
  for p=1,payload,2000 do
    local transformed = {}
    local last = mmin(p+1999,payload)
    local original = {sbyte(encoded,p,last)}
    for i=1,#original do
      local j = (i-1) % 4 + 1
      transformed[i] = bxor(original[i],mask[j])
    end
    local xored = schar(unpack(transformed))
    tinsert(transformed_arr,xored)
  end
  return tconcat(transformed_arr)
end

local encode = function(data,opcode,masked,fin)
  local encoded
  local header = opcode or 1-- TEXT is default opcode
  if fin == nil or fin == true then
    header = bor(header,bit_7)
  end
  local payload = 0
  if masked then
    payload = bor(payload,bit_7)
  end
  local len = #data
  if len < 126 then
    payload = bor(payload,len)
    --encoded = spack('bb',header,payload)
    encoded = string.char(header, payload)
  elseif len < 0xffff then
    payload = bor(payload,126)
    --encoded = spack('bb>H',header,payload,len)
    encoded = string.char(header,payload,math.floor(len/256),len%256)
  elseif len < 2^53 then
    local high = math.floor(len/2^32)
    local low = len - high*2^32
    payload = bor(payload,127)
    --encoded = spack('bb>I>I',header,payload,high,low)
    encoded = string.char(header,payload)..int_to_bytes(high)..int_to_bytes(low)
  end
  if not masked then
    encoded = encoded..data
  else
    local m1 = math.random(0,0xff)
    local m2 = math.random(0,0xff)
    local m3 = math.random(0,0xff)
    local m4 = math.random(0,0xff)
    local mask = {m1,m2,m3,m4}
    --encoded = encoded..spack('bbbb',m1,m2,m3,m4)
    encoded = encoded..string.char(m1,m2,m3,m4)
    encoded = encoded..xor_mask(data,mask,#data)
  end
  return encoded
end

local decode = function(encoded)
local high, low
  local encoded_bak = encoded
  if #encoded < 2 then
    return nil,2
  end
  --local pos,header,payload = sunpack(encoded,'bb')
  local pos,header,payload = 3,encoded:byte(1,2) 
  encoded = ssub(encoded,pos)
  local bytes = 2
  local fin = band(header,bit_7) > 0
  local opcode = band(header,bit_0_3)
  local mask = band(payload,bit_7) > 0
  payload = band(payload,bit_0_6)
  if payload > 125 then
    if payload == 126 then
      if #encoded < 2 then
        return nil,2
      end
      --pos,payload = sunpack(encoded,'>H')
      pos,payload = 3, getunsigned_2bytes_bigendian(encoded)
      
    elseif payload == 127 then
      if #encoded < 8 then
        return nil,8
      end
      --pos,high,low = sunpack(encoded,'>I>I')
      pos,high,low = 9,bytes_to_int(encoded:sub(1,4)),bytes_to_int(encoded:sub(5,8))
      payload = high*2^32 + low
      if payload < 0xffff or payload > 2^53 then
        assert(false,'INVALID PAYLOAD '..payload)
      end
    else
      assert(false,'INVALID PAYLOAD '..payload)
    end
    encoded = ssub(encoded,pos)
    bytes = bytes + pos - 1
  end
  local decoded
  if mask then
    local bytes_short = payload + 4 - #encoded
    if bytes_short > 0 then
      return nil,bytes_short
    end
    --local pos,m1,m2,m3,m4 = sunpack(encoded,'bbbb')
    local pos,m1,m2,m3,m4 = 5, encoded:byte(1,4)
    encoded = ssub(encoded,pos)
    local mask = {
      m1,m2,m3,m4
    }
    decoded = xor_mask(encoded,mask,payload)
    bytes = bytes + 4 + payload
  else
    local bytes_short = payload - #encoded
    if bytes_short > 0 then
      return nil,bytes_short
    end
    if #encoded > payload then
      decoded = ssub(encoded,1,payload)
    else
      decoded = encoded
    end
    bytes = bytes + payload
  end
  return decoded,fin,opcode,encoded_bak:sub(bytes+1),mask
end

local encode_close = function(code,reason)
  local data
  if code and type(code) == 'number' then
    --data = spack('>H',code)
    data = string.char(math.floor(code/256),code%256)
    if reason then
      data = data..tostring(reason)
    end
  end
  return data or ''
end

local decode_close = function(data)
  local _,code,reason
  if data then
    if #data > 1 then
      --_,code = sunpack(data,'>H')
      code = getunsigned_2bytes_bigendian(data)
    end
    if #data > 2 then
      reason = data:sub(3)
    end
  end
  return code,reason
end

return {
  encode = encode,
  decode = decode,
  encode_close = encode_close,
  decode_close = decode_close,
  --CONTINUATION = 0,
  --TEXT = 1,
  --BINARY = 2,
  --CLOSE = 8,
  --PING = 9,
  --PONG = 10
}
