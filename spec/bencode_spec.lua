local T = require 'harness'
local test, eq, same, pack = T.test, T.eq, T.same, T.pack

local function bencode() return require 'lumen.lib.bencode' end

local function roundtrip(b, v)
  local encoded = assert(b.encode(v))
  local decoded, index = b.decode(encoded)
  eq(index, #encoded + 1, 'decode consumes the whole encoding of '..encoded)
  return decoded, encoded
end

test('encodes the basic types as specified', function()
  local b = bencode()
  eq(b.encode('spam'), '4:spam')
  eq(b.encode(''), '0:')
  eq(b.encode(42), 'i42e')
  eq(b.encode(-3), 'i-3e')
  eq(b.encode(0), 'i0e')
  eq(b.encode({'spam', 42}), 'l4:spami42ee')
  eq(b.encode({}), 'le')
  eq(b.encode({cow = 'moo', spam = 'eggs'}), 'd3:cow3:moo4:spam4:eggse')
end)

test('dictionary keys are encoded sorted', function()
  eq(bencode().encode({b = 1, a = 2, c = 3}), 'd1:ai2e1:bi1e1:ci3ee')
end)

test('values survive a roundtrip', function()
  local b = bencode()
  local values = {
    'plain', '', 'with:colon and \0 nul and \n newline', string.rep('x', 1000),
    0, 7, -7, 123456789,
    {}, {1, 2, 3}, {'a', {'nested', {'deep'}}},
    {key = 'value', list = {1, 'two'}, dict = {inner = -1}},
  }
  for _, v in ipairs(values) do
    same(roundtrip(b, v), v)
  end
end)

test('integers stored as floats are encoded as integers', function()
  local b = bencode()
  eq(b.encode(6 / 2), 'i3e')
  eq(b.encode(2^40), 'i1099511627776e')
  eq(b.encode(1e15), 'i1000000000000000e')
  eq(b.encode(2^53), 'i9007199254740992e')
  eq(b.encode(-2^53), 'i-9007199254740992e')
  eq(b.encode(-0.0), 'i0e')
  eq(roundtrip(b, 2^53), 2^53)
end)

test('non integer numbers can not be encoded', function()
  same(pack(bencode().encode(1.5)), {n = 3, nil, 'number is not an integer', 1.5})
end)

test('tables with non string keys that are not lists are rejected', function()
  local b = bencode()
  local err = 'bencoding requires dictionary keys to be strings'
  -- which offending key gets reported depends on the traversal order
  local sparse = pack(b.encode({[1] = 'a', [3] = 'c'}))
  eq(sparse[1], nil); eq(sparse[2], err)
  T.ok(sparse[3] == 1 or sparse[3] == 3, 'reports a non string key')
  local mixed = pack(b.encode({1, 2, x = 3}))
  eq(mixed[1], nil); eq(mixed[2], err)
  T.ok(mixed[3] == 1 or mixed[3] == 2, 'reports a non string key')
  same(pack(b.encode({nested = {[true] = 'v'}})), {n = 3, nil, err, true})
end)

test('other types are encoded as strings, as a best effort', function()
  local b = bencode()
  eq(b.encode(true), '4:true')
  same(roundtrip(b, {flag = false}), {flag = 'false'})
end)

test('decode returns the position after the value', function()
  local b = bencode()
  local s = 'i1e4:spamli2ee'
  local v1, i = b.decode(s)
  local v2, j = b.decode(s, i)
  local v3, k = b.decode(s, j)
  eq(v1, 1); eq(v2, 'spam'); same(v3, {2})
  eq(k, #s + 1)
end)

test('decode tells truncated input from malformed input', function()
  local b = bencode()
  local full = b.encode({events = {'EV', 12}, n = -3})
  for i = 1, #full - 1 do
    local v, err = b.decode(full:sub(1, i))
    eq(v, nil)
    T.ok(err:find('^truncat'), 'prefix '..full:sub(1, i)..' reported as '..err)
  end
  for _, bad in ipairs({'x', 'd1:ai1x', 'd1:a1x', 'GET / HTTP', 'l-e'}) do
    local v, err = b.decode(bad)
    eq(v, nil)
    T.ok(not err:find('^truncat'), bad..' reported as truncated')
  end
end)

test('decode reports malformed and truncated input', function()
  local b = bencode()
  for _, bad in ipairs({'x', 'i12', 'ie', '5:ab', 'l1:a', 'd1:a', '', nil}) do
    eq(b.decode(bad), nil, 'decoding '..tostring(bad))
  end
end)
