-- Integration tests for the luasocket selector, over loopback with real time.
local T = require 'harness'
local test, eq, same, ok = T.test, T.eq, T.same, T.ok

local function init_selector(L)
  if not pcall(require, 'socket') then L.skip('luasocket not available') end
  local selector = require 'lumen.tasks.selector'
  selector.init({service = 'luasocket'})
  return selector
end

-- run body in a task, stopping the (endless) selector task when it finishes
-- or after a deadline
local function run_with_selector(L, selector, body)
  local sched = L.sched
  local timed_out = false
  local main
  local watchdog = sched.run(function()
    sched.sleep(5)
    timed_out = true
    sched.kill(main)
    sched.kill(selector.task)
  end)
  main = sched.run(function()
    body()
    sched.kill(watchdog)
    sched.kill(selector.task)
  end)
  L.loop()
  eq(timed_out, false, 'timed out')
end

test('tcp server and client exchange lines through streams', function(L)
  local sched = L.sched
  local selector = init_selector(L)
  local server_got, client_got = {}, {}
  run_with_selector(L, selector, function()
    local server = ok(selector.new_tcp_server('127.0.0.1', 0, 0, 'stream'))
    local _, port = server:getsockname()
    local accepted = {server.events.accepted, timeout = 3}

    sched.run(function()
      local _, conn = sched.wait(accepted)
      ok(conn, 'connection accepted')
      while true do
        local line = conn.stream:read_line()
        if not line then break end
        server_got[#server_got+1] = line
        conn:send_sync(line:upper()..'\n')
      end
      conn:close()
    end)

    local client = ok(selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream'))
    ok(client:send_sync('hello\nwor'))
    sched.sleep(0.05)
    ok(client:send_sync('ld\n'))
    for i = 1, 2 do client_got[i] = client.stream:read_line() end
    client:close()
    server:close()
  end)
  same(server_got, {'hello', 'world'})
  same(client_got, {'HELLO', 'WORLD'})
end)

test('closing the remote end closes the stream', function(L)
  local sched = L.sched
  local selector = init_selector(L)
  local got
  run_with_selector(L, selector, function()
    local server = ok(selector.new_tcp_server('127.0.0.1', 0, 0, 'stream'))
    local _, port = server:getsockname()
    sched.sigrunonce({server.events.accepted}, function(_, conn)
      conn:send_sync('bye')
      conn:close()
    end)
    local client = ok(selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream'))
    local s = client.stream
    s:set_timeout(3)
    local data = {}
    while true do
      local chunk, err = s:read()
      if not chunk then got = {table.concat(data), err}; break end
      data[#data+1] = chunk
    end
    server:close()
  end)
  same(got, {'bye', 'closed'})
end)

test('tcp client with a handler function receives the data', function(L)
  local sched = L.sched
  local selector = init_selector(L)
  local received = {}
  run_with_selector(L, selector, function()
    local server = ok(selector.new_tcp_server('127.0.0.1', 0, 0, 'stream'))
    local _, port = server:getsockname()
    sched.sigrunonce({server.events.accepted}, function(_, conn)
      conn:send_sync('payload')
      sched.sleep(0.1)
      conn:close()
    end)
    local done = {}
    selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, function(_, data, err)
      if data then received[#received+1] = data
      else received.err = err; sched.signal(done) end
      return true
    end)
    eq(sched.wait({done, timeout = 3}), done)
    server:close()
  end)
  eq(table.concat(received), 'payload')
  eq(received.err, 'closed')
end)
