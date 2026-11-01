local T = require 'harness'
local test, eq, same, pack = T.test, T.eq, T.same, T.pack

test('reads return written entries in order', function(L)
  local p = L.pipe.new()
  local got = {}
  L.sched.run(function()
    p:write('a')
    p:write('b')
    eq(p:len(), 2)
    got[1] = pack(p:read())
    got[2] = pack(p:read())
    eq(p:len(), 0)
  end)
  same(got, {{n = 2, true, 'a'}, {n = 2, true, 'b'}})
end)

test('an entry keeps all its values, including nils', function(L)
  local p = L.pipe.new()
  local got = {}
  L.sched.run(function()
    p:write('a', nil, 'c', nil)
    p:write(nil)
    got[1] = pack(p:read())
    got[2] = pack(p:read())
  end)
  same(got[1], {n = 5, true, 'a', nil, 'c', nil})
  same(got[2], {n = 2, true, nil})
end)

test('a reader blocks on an empty pipe until data arrives', function(L)
  local sched, p = L.sched, L.pipe.new()
  local got
  sched.run(function() got = pack(p:read()) end)
  eq(got, nil)
  sched.run(function() sched.sleep(3); p:write('x') end)
  L.loop()
  same(got, {n = 2, true, 'x'})
  eq(L.now, 3)
end)

test('a writer blocks on a full pipe until there is room', function(L)
  local sched, p = L.sched, L.pipe.new(2)
  local written = 0
  sched.run(function()
    for i = 1, 5 do p:write(i); written = i end
  end)
  eq(written, 2)
  local got = {}
  sched.run(function()
    for i = 1, 5 do
      sched.sleep(1)
      got[i] = select(2, p:read())
    end
  end)
  L.loop()
  eq(written, 5)
  same(got, {1, 2, 3, 4, 5})
end)

test('reads and writes time out', function(L)
  local sched, p = L.sched, L.pipe.new(1, 3)
  local read_result, write_result
  sched.run(function()
    read_result = pack(p:read())
    p:write('fill')
    write_result = pack(p:write('overflow'))
  end)
  L.loop()
  same(read_result, {n = 2, nil, 'timeout'})
  same(write_result, {n = 2, nil, 'timeout'})
  eq(L.now, 6)
  eq(p:len(), 1)
end)

test('several readers and writers share a pipe', function(L)
  local sched, p = L.sched, L.pipe.new(2)
  local got, done = {}, 0
  for _ = 1, 3 do
    sched.run(function()
      while true do
        local _, v = p:read()
        if v == 'stop' then break end
        got[#got+1] = v
        if v % 2 == 0 then sched.sleep(1) end
      end
      done = done + 1
    end)
  end
  for w = 0, 1 do
    sched.run(function()
      for i = 1, 20 do
        p:write(w * 20 + i)
        if i % 3 == 0 then sched.sleep(1) end
      end
    end)
  end
  sched.run(function()
    sched.sleep(100)
    for _ = 1, 3 do p:write('stop') end
  end)
  L.loop()
  table.sort(got)
  local expected = {}
  for i = 1, 40 do expected[i] = i end
  same(got, expected)
  eq(done, 3)
end)
