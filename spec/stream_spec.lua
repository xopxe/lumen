local T = require 'harness'
local test, eq, same, pack = T.test, T.eq, T.same, T.pack

test('read returns all the buffered data', function(L)
  local s = L.stream.new()
  local got
  L.sched.run(function()
    s:write('ab')
    s:write('cd')
    got = s:read()
  end)
  eq(got, 'abcd')
  eq(s.len, 0)
end)

test('read with a length returns exactly that many bytes', function(L)
  local s = L.stream.new()
  local got = {}
  L.sched.run(function()
    s:write('abcdef')
    got[1] = s:read(2)
    got[2] = s:read(0)
    got[3] = s:read(4)
  end)
  same(got, {'ab', '', 'cdef'})
end)

test('read with a length blocks until enough data arrives', function(L)
  local sched, s = L.sched, L.stream.new()
  local got
  sched.run(function() got = s:read(5) end)
  sched.run(function()
    for _, chunk in ipairs({'ab', 'c', 'defg'}) do
      sched.sleep(1)
      s:write(chunk)
    end
  end)
  L.loop()
  eq(got, 'abcde')
  eq(L.now, 3)
  eq(s:read(), 'fg')
end)

test('read_line splits lines, with or without carriage return', function(L)
  local sched, s = L.sched, L.stream.new()
  local got = {}
  sched.run(function()
    for i = 1, 4 do got[i] = s:read_line() end
  end)
  s:write('one\ntw')
  s:write('o\r\n\nfo')
  s:write('ur\nrest')
  same(got, {'one', 'two', '', 'four'})
  eq(s:read(), 'rest')
end)

test('read_line blocks until a whole line is available', function(L)
  local sched, s = L.sched, L.stream.new()
  local got
  sched.run(function() got = s:read_line() end)
  sched.run(function()
    for _, chunk in ipairs({'a', 'b', 'c\nd'}) do
      sched.sleep(1)
      s:write(chunk)
    end
  end)
  L.loop()
  eq(got, 'abc')
  eq(L.now, 3)
end)

test('a closed stream returns its data, then the closing error', function(L)
  local sched, s = L.sched, L.stream.new()
  local got = {}
  sched.run(function()
    s:write('line\nlast')
    s:write(nil, 'eof')
    got[1] = pack(s:read())
    got[2] = pack(s:read())
    got[3] = pack(s:write('more'))
  end)
  same(got[1], {n = 1, 'line\nlast'})
  same(got[2], {n = 3, nil, 'closed', 'eof'})
  same(got[3], {n = 3, nil, 'closed', 'eof'})
end)

test('read_line on a closed stream hands out the unterminated line', function(L)
  local sched, s = L.sched, L.stream.new()
  local got = {}
  sched.run(function()
    s:write('line\nla')
    s:write('st')
    s:write(nil, 'eof')
    got[1] = pack(s:read_line())
    got[2] = pack(s:read_line())
    got[3] = pack(s:read_line())
    got[4] = pack(s:read())
  end)
  same(got[1], {n = 1, 'line'})
  same(got[2], {n = 4, nil, 'closed', 'eof', 'last'}, 'the unterminated line')
  same(got[3], {n = 4, nil, 'closed', 'eof', nil}, 'it was removed')
  same(got[4], {n = 3, nil, 'closed', 'eof'})
end)

test('closing without an error message reports true', function(L)
  local s = L.stream.new()
  local got
  L.sched.run(function()
    s:write(false)
    got = pack(s:read())
  end)
  same(got, {n = 3, nil, 'closed', true})
end)

test('close without an error message reports true', function(L)
  local s = L.stream.new()
  same(pack(s:close()), {n = 1, true})
  same(pack(s:write('x')), {n = 3, nil, 'closed', true})
end)

test('closing an already closed stream keeps the first error', function(L)
  local s = L.stream.new()
  s:close('first')
  same(pack(s:close('second')), {n = 1, true})
  s:write(nil, 'third')
  same(pack(s:write('x')), {n = 3, nil, 'closed', 'first'})
end)

test('closing wakes blocked readers', function(L)
  local sched, s = L.sched, L.stream.new()
  local got = {}
  sched.run(function() got[1] = pack(s:read()) end)
  sched.run(function() got[2] = pack(s:read_line()) end)
  s:close('bye')
  same(got, {{n = 3, nil, 'closed', 'bye'}, {n = 4, nil, 'closed', 'bye', nil}})
end)

test('a writer blocks while the stream holds more than its size', function(L)
  local sched, s = L.sched, L.stream.new(4)
  local written = {}
  sched.run(function()
    for _, chunk in ipairs({'abcde', 'f', 'g'}) do
      s:write(chunk)
      written[#written+1] = chunk
    end
  end)
  same(written, {'abcde'}, 'a write is accepted while not over the size')
  local got
  sched.run(function()
    sched.sleep(1)
    got = s:read(2)
  end)
  L.loop()
  eq(got, 'ab')
  same(written, {'abcde', 'f', 'g'})
  eq(s:read(), 'cdefg')
end)

test('closing wakes blocked writers, which fail', function(L)
  local sched, s = L.sched, L.stream.new(1)
  local got
  sched.run(function()
    s:write('xx')
    got = pack(s:write('y'))
  end)
  s:close('gone')
  same(got, {n = 3, nil, 'closed', 'gone'})
end)

test('reads and writes time out', function(L)
  local sched, s = L.sched, L.stream.new(1, 2, 3)
  local got = {}
  sched.run(function()
    got.read = pack(s:read())
    got.line = pack(s:read_line())
    s:write('xx')
    got.write = pack(s:write('y'))
  end)
  L.loop()
  same(got.read, {n = 2, nil, 'timeout'})
  same(got.line, {n = 2, nil, 'timeout'})
  same(got.write, {n = 2, nil, 'timeout'})
  eq(L.now, 7)
end)

test('set_timeout applies to readers already blocked', function(L)
  local sched, s = L.sched, L.stream.new()
  local got
  sched.run(function() got = pack(s:read()) end)
  sched.run(function()
    sched.sleep(10)
    s:set_timeout(1, 1)
  end)
  L.loop()
  -- the blocked reader is woken, finds no data and waits again with the new timeout
  same(got, {n = 2, nil, 'timeout'})
  eq(L.now, 11)
end)

test('several readers share the lines of a stream', function(L)
  local sched, s = L.sched, L.stream.new(8)
  local got, done = {}, 0
  for r = 1, 3 do
    sched.run(function()
      while true do
        local line = s:read_line()
        if not line then break end
        got[#got+1] = line
        if r == 1 then sched.sleep(1) end
      end
      done = done + 1
    end)
  end
  sched.run(function()
    for i = 1, 30 do
      -- lines split across writes, and several lines per write
      s:write(i % 2 == 0 and ('line'..i..'\n') or ('li'))
      if i % 2 == 1 then s:write('ne'..i..'\n') end
      if i % 5 == 0 then sched.sleep(1) end
    end
    s:write(nil)
  end)
  L.loop()
  table.sort(got)
  local expected = {}
  for i = 1, 30 do expected[i] = 'line'..i end
  table.sort(expected)
  same(got, expected)
  eq(done, 3)
end)
