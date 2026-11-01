local T = require 'harness'
local test, eq, same, ok, raises = T.test, T.eq, T.same, T.ok, T.raises

test('synchronize lets one task at a time in the critical section', function(L)
  local sched, mx = L.sched, L.mutex.new()
  local inside, max_inside = 0, 0
  local critical = mx:synchronize(function(name)
    inside = inside + 1
    max_inside = math.max(max_inside, inside)
    sched.sleep(1)
    inside = inside - 1
    return name..'!', 'second'
  end)
  local results = {}
  for i = 1, 3 do
    sched.run(function() results[i] = {critical('t'..i)} end)
  end
  L.loop()
  eq(max_inside, 1)
  same(results, {{'t1!', 'second'}, {'t2!', 'second'}, {'t3!', 'second'}})
  eq(L.now, 3)
  eq(mx.locker, nil)
end)

test('acquire blocks until the holder releases', function(L)
  local sched, mx = L.sched, L.mutex.new()
  local order = {}
  sched.run(function()
    mx:acquire()
    order[#order+1] = 'A in'
    sched.sleep(2)
    order[#order+1] = 'A out'
    mx:release()
  end)
  local b = sched.run(function()
    mx:acquire()
    order[#order+1] = 'B in'
    mx:release()
  end)
  eq(b.status, 'ready')
  L.loop()
  same(order, {'A in', 'A out', 'B in'})
end)

test('acquiring a lock twice is an error', function(L)
  local mx = L.mutex.new()
  local err
  L.sched.run(function()
    mx:acquire()
    err = raises('already acquired', mx.acquire, mx)
  end)
  ok(err)
end)

test('releasing a lock not held is an error', function(L)
  local sched, mx = L.sched, L.mutex.new()
  local errs = {}
  sched.run(function() errs[1] = raises('non%-acquired', mx.release, mx) end)
  sched.run(function()
    mx:acquire()
    sched.wait({'never'})
  end)
  sched.run(function() errs[2] = raises('non%-acquired', mx.release, mx) end)
  eq(#errs, 2)
end)

test('a lock is released when the holder finishes or is killed', function(L)
  local sched = L.sched
  local finished_mx, killed_mx = L.mutex.new(), L.mutex.new()
  local got = {}
  sched.run(function() finished_mx:acquire(); sched.sleep(1) end)
  local holder = sched.run(function() killed_mx:acquire(); sched.wait({'never'}) end)
  local waiter_f = sched.run(function() finished_mx:acquire(); got.finished = true end)
  local waiter_k = sched.run(function()
    killed_mx:acquire()
    got.killed = true
    sched.wait({'never'})
  end)
  sched.kill(holder)
  eq(got.killed, true)
  eq(killed_mx.locker, waiter_k)
  L.loop()
  eq(got.finished, true)
  eq(finished_mx.locker, waiter_f)
end)

test('synchronize releases the lock and re-raises on error', function(L)
  L.allow_errors()
  local sched, mx = L.sched, L.mutex.new()
  local critical = mx:synchronize(function()
    sched.sleep(1)
    error('boom', 0)
  end)
  -- the task must die from the error, not just release the lock: Lua 5.1
  -- can't yield across a pcall here, so check the error through EVENT_DIE
  local failing = sched.run(critical)
  local reacquired
  sched.run(function()
    sched.sleep(2)
    mx:acquire()
    reacquired = true
    mx:release()
  end)
  L.loop()
  eq(failing.status, 'dead')
  same(L.errors, {'boom'})
  eq(reacquired, true)
  eq(mx.locker, nil)
end)

test('mutexes are independent', function(L)
  local sched = L.sched
  local a, b = L.mutex.new(), L.mutex.new()
  ok(tostring(a) ~= tostring(b))
  local got
  sched.run(function() a:acquire(); sched.wait({'never'}) end)
  sched.run(function() b:acquire(); got = true end)
  eq(got, true)
end)
