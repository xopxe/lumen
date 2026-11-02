-- Integration tests for the signal proxy, over loopback with real time.
-- The proxy server and its clients run in the same Lumen instance.
local T = require 'harness'
local net = require 'net'
local test, eq, same, ok, pack = T.test, T.eq, T.same, T.ok, T.pack

-- start the selector and a proxy server, then run body(proxy, port, events).
-- conf, if given, has extra configuration for the proxy
local function with_proxy(L, encoder, body, conf)
  local selector = net.init_selector(L)
  net.run_with_selector(L, selector, function()
    local proxy = require 'lumen.tasks.proxy'
    conf = conf or {}
    conf.ip, conf.port, conf.encoder = '127.0.0.1', 0, encoder
    proxy.init(conf)
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

test('each client gets events under the name it asked for', function(L)
  local sched = L.sched
  local got = {}
  with_proxy(L, 'json', function(proxy, port, events)
    local ev = {}
    events:register('OLD', ev)
    local old = proxy.new_remote_waitd('127.0.0.1', port, {events = {'OLD'}, timeout = 1})
    settle(L)
    events:register('NEW', ev, true) -- rename the event
    local new = proxy.new_remote_waitd('127.0.0.1', port, {events = {'NEW'}, timeout = 1})
    settle(L)
    for name, waitd in pairs({old = old, new = new}) do
      sched.run(function() got[name] = select(2, sched.wait(waitd)) or 'timeout' end)
    end
    sched.signal(ev)
    settle(L)
  end)
  same(got, {old = 'OLD', new = 'NEW'})
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

---------------------------------------
-- malformed and oversized messages

-- read from a stream until it closes or times out, returns all the data and why it stopped
local function read_all(s, timeout)
  s:set_timeout(timeout or 1)
  local data = {}
  while true do
    local chunk, err = s:read()
    if not chunk then return table.concat(data), err end
    data[#data+1] = chunk
  end
end

-- a request for the 'EV' event, split in three parts
local split_request = {
  json = {'{"ev', 'ents":["E', 'V"]}'},
  bencode = {'d6', ':eventsl2:E', 'Vee'},
}

for _, encoder in ipairs({'json', 'bencode'}) do
  test(encoder..': a request split anywhere is still served', function(L)
    local sched = L.sched
    local got
    with_proxy(L, encoder, function(_, port, events)
      local selector = require 'lumen.tasks.selector'
      local ev = {}
      events:register('EV', ev)
      local client = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
      for _, part in ipairs(split_request[encoder]) do
        client:send_sync(part)
        settle(L)
      end
      sched.signal(ev, 'x')
      client.stream:set_timeout(1)
      got = client.stream:read() or 'nothing'
      client:close()
    end)
    ok(got:find('EV', 1, true), 'event forwarded, got '..got)
  end)

  test(encoder..': a malformed request closes the connection', function(L)
    local got
    with_proxy(L, encoder, function(_, port)
      local selector = require 'lumen.tasks.selector'
      local client = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
      client:send_sync('GET / HTTP/1.1\r\n\r\n')
      got = {read_all(client.stream)}
      client:close()
    end)
    same(got, {'', 'closed'})
  end)
end

test('a request of the wrong shape closes the connection', function(L)
  local got = {}
  with_proxy(L, 'json', function(_, port)
    local selector = require 'lumen.tasks.selector'
    for i, request in ipairs({'"EV"', '{"events":"EV"}', '{"events":["EV"],"name_timeout":"x"}'}) do
      local client = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
      client:send_sync(request)
      got[i] = select(2, read_all(client.stream))
      client:close()
    end
  end)
  same(got, {'closed', 'closed', 'closed'})
end)

test('a request larger than max_message_size closes the connection', function(L)
  local got
  with_proxy(L, 'json', function(_, port)
    local selector = require 'lumen.tasks.selector'
    local client = selector.new_tcp_client('127.0.0.1', port, nil, nil, 0, 'stream')
    -- valid so far, but never ends
    client:send_sync('{"events":["'..string.rep('x', 100))
    got = {read_all(client.stream)}
    client:close()
  end, {max_message_size = 64})
  same(got, {'', 'closed'})
end)

test('messages larger than a network packet are fine within max_message_size', function(L)
  local sched = L.sched
  local name = string.rep('n', 5000)
  local got
  with_proxy(L, 'json', function(proxy, port, events)
    local ev = {}
    events:register(name, ev)
    local waitd = proxy.new_remote_waitd('127.0.0.1', port, {events = {name}, timeout = 1})
    settle(L)
    sched.signal(ev, string.rep('d', 5000))
    got = pack(sched.wait(waitd))
  end)
  eq(got[2], name)
  eq(got[3], string.rep('d', 5000))
end)

test('a remote waitd closes the connection on malformed signals', function(L)
  local sched = L.sched
  local got
  -- init the proxy for its configuration, but talk to a fake server
  with_proxy(L, 'json', function(proxy)
    local selector = require 'lumen.tasks.selector'
    local server = selector.new_tcp_server('127.0.0.1', 0, 0, 'stream')
    local _, port = server:getsockname()
    sched.sigrunonce({server.events.accepted}, function(_, conn)
      conn:send_sync('{"n":1,"1":"EV"}garbage')
      got = {read_all(conn.stream)}
      conn:close()
    end)
    local waitd = proxy.new_remote_waitd('127.0.0.1', port, {events = {'EV'}, timeout = 1})
    local first = pack(sched.wait(waitd))
    eq(first[2], 'EV', 'the valid signal before the garbage is delivered')
    sched.sleep(1.5)
    server:close()
  end)
  same(got, {'{"events":["EV"]}', 'closed'})
end)

test('a json signal split at any byte is not taken as malformed', function(L)
  local sched = L.sched
  -- literals and numbers cut short look like invalid values to the json decoder
  local message = '{"n":6,"1":"EV","2":true,"3":false,"4":-1.5e-3,"5":null,"6":1E+2}'
  local got
  with_proxy(L, 'json', function(proxy)
    local selector = require 'lumen.tasks.selector'
    local server = selector.new_tcp_server('127.0.0.1', 0, 0, 'stream')
    local _, port = server:getsockname()
    sched.sigrunonce({server.events.accepted}, function(_, conn)
      for i = 1, #message do
        conn:send_sync(message:sub(i, i))
        sched.sleep(0.005)
      end
    end)
    local waitd = proxy.new_remote_waitd('127.0.0.1', port, {events = {'EV'}, timeout = 3})
    got = pack(sched.wait(waitd))
    got[1] = nil
    server:close()
  end)
  same(got, {n = 7, nil, 'EV', true, false, -1.5e-3, nil, 100})
end)
