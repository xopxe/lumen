local T = require 'harness'
local test, eq, raises = T.test, T.eq, T.raises

test('queue works as a deque', function()
  local queue = require 'lumen.lib.queue'
  local q = queue:new()
  q:pushright(1)
  q:pushright(2)
  q:pushleft(0)
  eq(q:len(), 3)
  eq(q:popleft(), 0)
  eq(q:popright(), 2)
  eq(q:popleft(), 1)
  eq(q:len(), 0)
  raises('empty', q.popleft, q)
  raises('empty', q.popright, q)
end)

test('queue2 and queue3 hold several values per entry', function()
  for n, name in ipairs({'lumen.lib.queue2', 'lumen.lib.queue3'}) do
    local q = require(name):new()
    q:pushright('b', nil, n)
    q:pushleft('a', false, n)
    eq(q:len(), 2)
    local v1, v2, v3 = q:popleft()
    eq(v1, 'a'); eq(v2, false)
    if n == 2 then eq(v3, 2) end
    v1, v2, v3 = q:popright()
    eq(v1, 'b'); eq(v2, nil)
    if n == 2 then eq(v3, 2) end
    raises('empty', q.popleft, q)
  end
end)

test('queues are independent', function()
  local queue = require 'lumen.lib.queue2'
  local a, b = queue:new(), queue:new()
  a:pushright(1)
  eq(b:len(), 0)
end)
