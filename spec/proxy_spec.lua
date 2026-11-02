-- Integration tests for the signal proxy, over loopback with real time.
-- The proxy server and its clients run in the same Lumen instance.
local T = require 'harness'
local net = require 'net'
local test, eq, same, ok, pack = T.test, T.eq, T.same, T.ok, T.pack

-- start the selector and a proxy server, then run body(proxy, port, events)
local function with_proxy(L, encoder, body)
  local selector = net.init_selector(L)
  net.run_with_selector(L, selector, function()
    local proxy = require 'lumen.tasks.proxy'
    proxy.init({ip = '127.0.0.1', port = 0, encoder = encoder})
    ok(proxy.skt_server, 'proxy server started')
    local _, port = proxy.skt_server:getsockname()
    body(proxy, port, L.catalog.get_catalog('events'))
    proxy.skt_server:close()
  end)
end

-- give the proxy server time to subscribe to the requested events
local function settle(L) L.sched.sleep(0.2) end

for _, encoder in ipairs({'json', 'bencode'}) do
  test(encoder..': a remote waitd receives the named events', function(L)
    local sched = L.sched
    local got = {}
    with_proxy(L, encoder, function(proxy, port, events)
      local ev_a, ev_b = {}, {}
      events:register('A', ev_a)
      events:register('B', ev_b)
      local waitd = ok(proxy.new_remote_waitd('127.0.0.1', port,
        {events = {'A', 'B'}, timeout = 2}))
      settle(L)
      sched.signal(ev_a, 'data', 42)
      got[1] = pack(sched.wait(waitd))
      sched.signal(ev_b)
      got[2] = pack(sched.wait(waitd))
      sched.signal({}, 'not proxied')
      got[3] = pack(sched.wait({waitd[1], timeout = 0.3}))
      got.event = waitd[1]
    end)
    same(got[1], {n = 4, got.event, 'A', 'data', 42})
    same(got[2], {n = 2, got.event, 'B'})
    same(got[3], {n = 2, nil, 'timeout'})
  end)

  test(encoder..': events registered later are found within name_timeout', function(L)
    local sched = L.sched
    local got
    with_proxy(L, encoder, function(proxy, port, events)
      local waitd = proxy.new_remote_waitd('127.0.0.1', port,
        {events = {'LATE'}, name_timeout = 2, timeout = 2})
      settle(L)
      local ev = {}
      events:register('LATE', ev)
      settle(L)
      sched.signal(ev, 1)
      got = pack(sched.wait(waitd))
      got[1] = nil
    end)
    same(got, {n = 3, nil, 'LATE', 1})
  end)

  test(encoder..': signals sent back to back are all delivered', function(L)
    local sched = L.sched
    local got = {}
    with_proxy(L, encoder, function(proxy, port, events)
      local ev = {}
      events:register('EV', ev)
      local waitd = proxy.new_remote_waitd('127.0.0.1', port, {events = {'EV'}, timeout = 1})
      settle(L)
      for i = 1, 5 do sched.signal(ev, i) end
      for i = 1, 5 do got[i] = select(3, sched.wait(waitd)) or 'timeout' end
    end)
    same(got, {1, 2, 3, 4, 5})
  end)
end

-- values each encoder can not handle: bencode fails returning nil, dkjson raises
local unencodable = {bencode = 1.5, json = print}

for encoder, bad_value in pairs(unencodable) do
  test(encoder..': an event that can not be encoded does not stop the proxy', function(L)
    local sched = L.sched
    local got
    with_proxy(L, encoder, function(proxy, port, events)
      local ev = {}
      events:register('EV', ev)
      local waitd = proxy.new_remote_waitd('127.0.0.1', port, {events = {'EV'}, timeout = 1})
      settle(L)
      sched.signal(ev, bad_value)
      sched.signal(ev, 2)
      got = pack(sched.wait(waitd))
      got[1] = nil
    end)
    same(got, {n = 3, nil, 'EV', 2})
  end)
end

test('several requests arriving together are all served', function(L)
  local sched = L.sched
  local got
  with_proxy(L, 'json', function(_, port, events)
    local selector = require 'lumen.tasks.selector'
    local ev_a, ev_b = {}, {}
    events:register('A', ev_a)
    events:register('B', ev_b)
    local client = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
    client:send_sync('{"events":["A"]}{"events":["B"]}')
    settle(L)
    sched.signal(ev_a)
    sched.signal(ev_b)
    settle(L)
    client.stream:set_timeout(1)
    got = client.stream:read() or 'nothing'
    client:close()
  end)
  ok(got:find('"A"', 1, true), 'event A forwarded, got '..got)
  ok(got:find('"B"', 1, true), 'event B forwarded, got '..got)
end)

test('forwarding stops when a client disconnects', function(L)
  local sched = L.sched
  local counts = {}
  local function count_tasks()
    local n = 0
    for _ in pairs(sched.tasks) do n = n + 1 end
    return n
  end
  with_proxy(L, 'json', function(_, port, events)
    local selector = require 'lumen.tasks.selector'
    local ev = {}
    events:register('EV', ev)
    local client = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
    settle(L)
    counts.before = count_tasks()
    client:send_sync('{"events":["EV"]}{"events":["EV"]}')
    settle(L)
    counts.connected = count_tasks()
    client:close()
    settle(L)
    counts.closed = count_tasks()
    sched.signal(ev, 'x') -- nothing left to forward it
  end)
  eq(counts.connected, counts.before + 2, 'a forwarding task per request')
  eq(counts.closed, counts.before, 'forwarding tasks left after disconnecting')
end)

test('requests split across packets from several clients do not mix', function(L)
  local sched = L.sched
  local got = {}
  local selector
  with_proxy(L, 'json', function(_, port, events)
    selector = require 'lumen.tasks.selector'
    local ev = {}
    events:register('EV', ev)
    local request = '{"events":["EV"]}'
    local a = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
    local b = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
    a:send_sync(request:sub(1, 8))
    settle(L)
    b:send_sync(request)
    settle(L)
    a:send_sync(request:sub(9))
    settle(L)
    sched.signal(ev, 'x')
    for i, client in ipairs({a, b}) do
      client.stream:set_timeout(1)
      got[i] = client.stream:read() or 'nothing'
      client:close()
    end
  end)
  ok(got[1]:find('"x"', 1, true), 'client a got '..got[1])
  ok(got[2]:find('"x"', 1, true), 'client b got '..got[2])
end)
