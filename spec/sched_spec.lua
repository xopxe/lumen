local T = require 'harness'
local test, eq, same, ok, raises, pack = T.test, T.eq, T.same, T.ok, T.raises, T.pack

---------------------------------------
-- running tasks

test('run starts the task immediately and passes arguments', function(L)
  local got
  local task = L.sched.run(function(a, b) got = {a, b} end, 1, 2)
  same(got, {1, 2})
  eq(task.status, 'dead')
end)

test('run returns to the caller when the task blocks', function(L)
  local sched = L.sched
  local order = {}
  sched.run(function()
    order[#order+1] = 'a'
    sched.wait({'x'})
    order[#order+1] = 'c'
  end)
  order[#order+1] = 'b'
  sched.signal('x')
  order[#order+1] = 'd'
  same(order, {'a', 'b', 'c', 'd'})
end)

test('new_task creates a task that runs when passed to run', function(L)
  local sched = L.sched
  local ran = false
  local task = sched.new_task(function(v) ran = v end)
  eq(task.status, 'ready')
  eq(ran, false)
  eq(sched.run(task, 'yes'), task)
  eq(ran, 'yes')
end)

test('running_task is the current task, and false outside tasks', function(L)
  local sched = L.sched
  local inside
  local task = sched.run(function() inside = sched.running_task end)
  eq(inside, task)
  eq(sched.running_task, false)
end)

test('wait with no waitd yields to the other ready tasks', function(L)
  local sched = L.sched
  local count = {a = 0, b = 0}
  local max_lead = 0
  local function worker(me, other)
    return function()
      for _ = 1, 5 do
        count[me] = count[me] + 1
        max_lead = math.max(max_lead, count[me] - count[other])
        sched.wait()
      end
    end
  end
  sched.run(worker('a', 'b'))
  sched.run(worker('b', 'a'))
  L.loop()
  same(count, {a = 5, b = 5})
  eq(max_lead, 1, 'tasks should advance in lockstep')
end)

test('loop returns when all tasks are blocked without timeout', function(L)
  local sched = L.sched
  local task = sched.run(function() sched.wait({'never'}) end)
  L.loop()
  eq(task.status, 'ready')
  ok(task.waitingfor)
end)

test('step reports the available idle time', function(L)
  local sched = L.sched
  sched.run(function() sched.sleep(5) end)
  eq(sched.step(), 5, 'only a sleeping task')
  L.now = 5
  eq(sched.step(), 0, 'task woke up')
  eq(sched.step(), nil, 'nothing left to do')
  sched.run(function() sched.wait() end)
  eq(sched.step(), 0, 'a ready task')
end)

test('new_waitd and wait can only be called from a task', function(L)
  raises(nil, L.sched.new_waitd, {'x'})
  raises(nil, L.sched.wait, {'x'})
end)

---------------------------------------
-- signals

test('signal delivers the event and all parameters, including nils', function(L)
  local sched = L.sched
  local got
  sched.run(function() got = pack(sched.wait({'e'})) end)
  sched.signal('e', 1, nil, 3, nil)
  same(got, {n = 5, 'e', 1, nil, 3, nil})
end)

test('wait returns whichever of the events fired', function(L)
  local sched = L.sched
  local got
  sched.run(function() got = pack(sched.wait({'a', 'b', 'c'})) end)
  sched.signal('b', 'data')
  same(got, {n = 2, 'b', 'data'})
end)

test('events can be of any type', function(L)
  local sched = L.sched
  local ev_table, ev_number, got = {}, 42, {}
  sched.run(function()
    for i = 1, 3 do got[i] = sched.wait({ev_table, ev_number, true}) end
  end)
  sched.signal(ev_table)
  sched.signal(ev_number)
  sched.signal(true)
  same(got, {ev_table, ev_number, true})
end)

test('EVENT_ANY receives every signal', function(L)
  local sched = L.sched
  local got = {}
  sched.run(function()
    while true do
      local ev, v = sched.wait({sched.EVENT_ANY})
      if ev == 'x' or ev == 'y' then got[#got+1] = ev..v end
    end
  end)
  sched.signal('x', 1)
  sched.signal('y', 2)
  same(got, {'x1', 'y2'})
end)

test('all tasks waiting on a signal receive it', function(L)
  local sched = L.sched
  local got = {}
  local shared = {'e'}
  for i = 1, 3 do
    sched.run(function() got[i] = select(2, sched.wait(shared)) end)
  end
  for i = 4, 5 do
    sched.run(function() got[i] = select(2, sched.wait({'e'})) end)
  end
  sched.signal('e', 'v')
  same(got, {'v', 'v', 'v', 'v', 'v'})
end)

test('unbuffered signals are lost when the task is not waiting', function(L)
  local sched = L.sched
  local first, second
  sched.run(function()
    local waitd = {'e'}
    first = sched.wait(waitd)
    sched.sleep(1)
    waitd.timeout = 5
    second = pack(sched.wait(waitd))
  end)
  sched.signal('e')
  sched.signal('e') -- task is sleeping
  L.loop()
  eq(first, 'e')
  same(second, {n = 2, nil, 'timeout'})
end)

test('a signal emitted by a task does not reach the task itself', function(L)
  local sched = L.sched
  local got
  sched.run(function()
    sched.signal('e')
    got = pack(sched.wait({'e', timeout = 1}))
  end)
  L.loop()
  same(got, {n = 2, nil, 'timeout'})
end)

---------------------------------------
-- timeouts and sleep

test('wait times out after the given time', function(L)
  local sched = L.sched
  local got, elapsed
  sched.run(function()
    local t0 = sched.get_time()
    got = pack(sched.wait({'never', timeout = 5}))
    elapsed = sched.get_time() - t0
  end)
  L.loop()
  same(got, {n = 2, nil, 'timeout'})
  eq(elapsed, 5)
end)

test('a signal arriving before the timeout cancels it', function(L)
  local sched = L.sched
  local got, after
  sched.run(function()
    got = pack(sched.wait({'e', timeout = 5}))
    after = pack(sched.wait({'other', timeout = 10}))
  end)
  L.now = 2
  sched.signal('e', 'v')
  L.loop()
  same(got, {n = 2, 'e', 'v'})
  same(after, {n = 2, nil, 'timeout'})
  eq(L.now, 12)
end)

test('a negative timeout waits forever', function(L)
  local sched = L.sched
  local task = sched.run(function() sched.wait({'never', timeout = -1}) end)
  L.loop()
  eq(task.status, 'ready')
  eq(L.now, 0)
end)

test('waitd without events only returns on timeout', function(L)
  local sched = L.sched
  local got
  sched.run(function() got = pack(sched.wait({timeout = 3})) end)
  L.loop()
  same(got, {n = 2, nil, 'timeout'})
  eq(L.now, 3)
end)

test('sleeping tasks wake up in time order', function(L)
  local sched = L.sched
  local order = {}
  for _, t in ipairs({3, 1, 2}) do
    sched.run(function()
      sched.sleep(t)
      order[#order+1] = {t, sched.get_time()}
    end)
  end
  L.loop()
  same(order, {{1, 1}, {2, 2}, {3, 3}})
end)

---------------------------------------
-- buffering

test("keep_first buffers the first signal emitted while not waiting", function(L)
  local sched = L.sched
  local got, second
  sched.run(function()
    local waitd = sched.new_waitd({'e', buff_mode = 'keep_first'})
    sched.sleep(1)
    got = pack(sched.wait(waitd))
    waitd.timeout = 1
    second = pack(sched.wait(waitd))
  end)
  sched.signal('e', 1)
  sched.signal('e', 2)
  L.loop()
  same(got, {n = 2, 'e', 1})
  same(second, {n = 2, nil, 'timeout'}, 'buffer holds a single signal')
end)

test("keep_last buffers the last signal emitted while not waiting", function(L)
  local sched = L.sched
  local got
  sched.run(function()
    local waitd = sched.new_waitd({'e', buff_mode = 'keep_last'})
    sched.sleep(1)
    got = pack(sched.wait(waitd))
  end)
  sched.signal('e', 1)
  sched.signal('e', 2)
  L.loop()
  same(got, {n = 2, 'e', 2})
end)

test('buffered signals keep their parameter count', function(L)
  local sched = L.sched
  local got = {}
  local params = {{}, {'a'}, {'a', nil, 'c', nil, n = 4}}
  for i, p in ipairs(params) do
    sched.run(function()
      local waitd = sched.new_waitd({'e'..i, buff_mode = 'keep_last'})
      sched.sleep(1)
      got[i] = pack(sched.wait(waitd))
    end)
    sched.signal('e'..i, T.unpack(p, 1, p.n or #p))
  end
  L.loop()
  same(got[1], {n = 1, 'e1'})
  same(got[2], {n = 2, 'e2', 'a'})
  same(got[3], {n = 5, 'e3', 'a', nil, 'c', nil})
end)

test('a delivered signal is not also buffered in a shared waitd', function(L)
  local sched = L.sched
  local shared = {'e', buff_mode = 'keep_last'}
  local a_got, b_got
  sched.run(function() a_got = sched.wait(shared) end)
  sched.run(function()
    sched.new_waitd(shared) -- joins the waitd, but is not waiting on it
    sched.sleep(1)
    shared.timeout = 1
    b_got = pack(sched.wait(shared))
  end)
  sched.signal('e')
  L.loop()
  eq(a_got, 'e')
  same(b_got, {n = 2, nil, 'timeout'}, 'signal was duplicated through the buffer')
end)

test('a signal wakes only the tasks waiting when it was emitted', function(L)
  -- tasks woken by a signal start new tasks waiting on the same waitd, which
  -- adds them to the waitd while it is being traversed
  local sched = L.sched
  local shared = {'e'}
  local first_round, late = {}, 0
  for i = 1, 30 do
    sched.run(function()
      sched.wait(shared)
      first_round[i] = (first_round[i] or 0) + 1
      sched.run(function()
        sched.wait(shared)
        late = late + 1
      end)
    end)
  end
  sched.signal('e')
  for i = 1, 30 do eq(first_round[i], 1, 'waiting task '..i) end
  eq(late, 0, 'tasks that started waiting during delivery got the signal')
  sched.signal('e')
  eq(late, 30)
end)

---------------------------------------
-- scheduled signals

test('schedule_signal does not yield, and delivers in order later', function(L)
  local sched = L.sched
  local got = {}
  local delivered_before_yield
  sched.sigrun({'s'}, function(_, ...) got[#got+1] = pack(...) end)
  sched.run(function()
    sched.schedule_signal('s')
    sched.schedule_signal('s', 1)
    sched.schedule_signal('s', 'a', nil, 'c')
    sched.schedule_signal('s', 'a', nil)
    delivered_before_yield = #got
  end)
  L.loop()
  eq(delivered_before_yield, 0)
  same(got, {{n = 0}, {n = 1, 1}, {n = 3, 'a', nil, 'c'}, {n = 2, 'a', nil}})
end)

test('loop does not finish with scheduled signals pending', function(L)
  local sched = L.sched
  local received
  sched.run(function() received = sched.wait({'x'}) end)
  -- a task woken from a buffered waitd, with no timers around, schedules a
  -- signal: the step that runs it must not report the scheduler as idle
  local waitd = {'b', buff_mode = 'keep_last'}
  local task = sched.run(function()
    sched.wait(waitd)
    sched.schedule_signal('x')
  end)
  sched.set_pause(task, true)
  sched.signal('b')
  sched.set_pause(task, false)
  L.loop()
  eq(task.status, 'dead')
  eq(received, 'x')
end)

---------------------------------------
-- task termination

test('a finished task emits its EVENT_FINISH and the global one', function(L)
  local sched = L.sched
  local per_task, global, status_at_finish
  local task = sched.new_task(function()
    sched.sleep(1)
    return 'r1', nil, 'r3'
  end)
  sched.run(function()
    per_task = pack(sched.wait({task.EVENT_FINISH}))
    status_at_finish = task.status
  end)
  sched.sigrun({sched.EVENT_FINISH}, function(_, taskd, ...)
    if taskd == task then global = pack(...) end
  end)
  sched.run(task)
  L.loop()
  same(per_task, {n = 4, task.EVENT_FINISH, 'r1', nil, 'r3'})
  same(global, {n = 3, 'r1', nil, 'r3'})
  eq(status_at_finish, 'dead')
  eq(sched.tasks[task], nil)
end)

test('every task waiting for EVENT_FINISH receives it', function(L)
  local sched = L.sched
  local task = sched.new_task(function() sched.sleep(1) end)
  local count = 0
  for _ = 1, 3 do
    sched.run(function()
      sched.wait({task.EVENT_FINISH})
      count = count + 1
    end)
  end
  sched.run(task)
  L.loop()
  eq(count, 3)
end)

test('a task failing with an error emits EVENT_DIE with the message', function(L)
  L.allow_errors()
  local sched = L.sched
  local died, finished
  local task = sched.new_task(function() sched.sleep(1); error('boom', 0) end)
  sched.run(function() died = pack(sched.wait({task.EVENT_DIE})) end)
  sched.run(function() finished = sched.wait({task.EVENT_FINISH}) end)
  sched.run(task)
  L.loop()
  same(died, {n = 2, task.EVENT_DIE, 'boom'})
  eq(finished, nil)
  eq(task.status, 'dead')
  same(L.errors, {'boom'})
end)

test('kill stops a task and emits EVENT_DIE with "killed"', function(L)
  local sched = L.sched
  local resumed = false
  local died = {}
  local task = sched.run(function()
    sched.sleep(5)
    resumed = true
  end)
  sched.sigrun({sched.EVENT_DIE}, function(_, taskd, why)
    if taskd == task then died[#died+1] = why end
  end)
  sched.kill(task)
  eq(task.status, 'dead')
  sched.kill(task) -- killing a dead task does nothing
  L.loop()
  eq(resumed, false)
  same(died, {'killed'})
  eq(sched.tasks[task], nil)
end)

test('a task that kills itself does not continue', function(L)
  local sched = L.sched
  local after = false
  local task = sched.run(function()
    sched.kill(sched.running_task)
    after = true
  end)
  L.loop()
  eq(after, false)
  eq(task.status, 'dead')
end)

test('a task killed by the task it signals does not continue', function(L)
  local sched = L.sched
  local after = false
  local emitter = sched.new_task(function()
    sched.signal('e')
    after = true
  end)
  sched.run(function()
    sched.wait({'e'})
    sched.kill(emitter)
  end)
  sched.run(emitter)
  L.loop()
  eq(after, false)
  eq(emitter.status, 'dead')
end)

test('a task killed by a task it runs does not continue', function(L)
  local sched = L.sched
  local after = false
  local parent = sched.run(function()
    local me = sched.running_task
    sched.run(function() sched.kill(me) end)
    after = true
  end)
  eq(after, false)
  eq(parent.status, 'dead')
end)

test('a killed task never runs again, even with pending wakeups', function(L)
  local sched = L.sched
  local runs = 0
  local task = sched.run(function()
    while true do
      sched.wait({'e', timeout = 1})
      runs = runs + 1
    end
  end)
  sched.kill(task)
  sched.signal('e')
  L.loop()
  eq(runs, 0)
end)

---------------------------------------
-- attached tasks

test('attached tasks are killed when the parent finishes', function(L)
  local sched = L.sched
  local child, other
  sched.run(function()
    child = sched.run(function() sched.wait({'never'}) end):set_as_attached()
    other = sched.run(function() sched.wait({'never'}) end)
    sched.sleep(1)
  end)
  L.loop()
  eq(child.status, 'dead')
  eq(other.status, 'ready', 'non attached task survives')
end)

test('attached tasks are killed when the parent dies', function(L)
  L.allow_errors()
  local sched = L.sched
  local killed_child, failing_child
  local killed = sched.run(function()
    killed_child = sched.run(function() sched.wait({'never'}) end):set_as_attached()
    sched.wait({'never'})
  end)
  sched.run(function()
    failing_child = sched.run(function() sched.wait({'never'}) end):set_as_attached()
    sched.sleep(1)
    error('boom')
  end)
  sched.kill(killed)
  eq(killed_child.status, 'dead')
  L.loop()
  eq(failing_child.status, 'dead')
end)

test('attach links any two tasks, recursively', function(L)
  local sched = L.sched
  local a = sched.run(function() sched.wait({'never'}) end)
  local b = sched.run(function() sched.wait({'never'}) end)
  local c = sched.run(function() sched.wait({'never'}) end)
  eq(a:attach(b), a)
  b:attach(c)
  sched.kill(a)
  eq(b.status, 'dead')
  eq(c.status, 'dead')
end)

test('an attached task that kills its parent dies with it', function(L)
  local sched = L.sched
  local parent_died, after_kill = false, false
  local parent, child
  parent = sched.run(function()
    child = sched.run(function()
      sched.wait({'go'})
      sched.kill(parent)
      after_kill = true
    end):set_as_attached()
    sched.wait({'never'})
  end)
  sched.run(function()
    sched.wait({parent.EVENT_DIE})
    parent_died = true
  end)
  sched.signal('go')
  L.loop()
  eq(parent.status, 'dead')
  eq(child.status, 'dead')
  ok(parent_died, 'parent EVENT_DIE was emitted')
  eq(after_kill, false)
end)

---------------------------------------
-- sigrun

test('sigrun calls the function for every signal', function(L)
  local sched = L.sched
  local got = {}
  local task = sched.sigrun({'e'}, function(ev, v) got[#got+1] = ev..v end)
  for i = 1, 3 do sched.signal('e', i) end
  same(got, {'e1', 'e2', 'e3'})
  eq(task.status, 'ready')
end)

test('sigrunonce calls the function for one signal and finishes', function(L)
  local sched = L.sched
  local got = {}
  local task = sched.sigrunonce({'e'}, function(_, v) got[#got+1] = v end)
  sched.signal('e', 1)
  sched.signal('e', 2)
  same(got, {1})
  eq(task.status, 'dead')
end)

test('sigrun receives timeouts', function(L)
  local sched = L.sched
  local got = {}
  local task = sched.sigrun({'e', timeout = 1}, function(ev, err)
    got[#got+1] = tostring(ev)..' '..tostring(err)
  end)
  L.loop(3)
  sched.kill(task)
  same(got, {'nil timeout', 'nil timeout', 'nil timeout'})
end)

test('sigrun can attach the task to the caller', function(L)
  local sched = L.sched
  local listener
  sched.run(function()
    listener = sched.sigrun({'e'}, function() end, true)
    sched.sleep(1)
  end)
  L.loop()
  eq(listener.status, 'dead')
end)

---------------------------------------
-- pause

test('a paused task does not receive unbuffered signals', function(L)
  local sched = L.sched
  local got = {}
  local task = sched.sigrun({'e'}, function(_, v) got[#got+1] = v end)
  eq(sched.set_pause(task, true), task)
  eq(task.status, 'paused')
  sched.signal('e', 1)
  sched.set_pause(task, false)
  sched.signal('e', 2)
  same(got, {2})
end)

test('a paused task does not run until unpaused', function(L)
  local sched = L.sched
  local steps = 0
  local task = sched.run(function()
    while true do steps = steps + 1; sched.wait() end
  end)
  sched.set_pause(task, true)
  for _ = 1, 3 do sched.step() end
  eq(steps, 1)
  sched.set_pause(task, false)
  sched.step()
  eq(steps, 2)
  sched.kill(task)
end)

test('a task can pause itself', function(L)
  local sched = L.sched
  local resumed = false
  local task = sched.run(function()
    sched.set_pause(sched.running_task, true)
    resumed = true
  end)
  eq(task.status, 'paused')
  sched.step()
  eq(resumed, false)
  sched.set_pause(task, false)
  L.loop()
  eq(resumed, true)
end)

test('a buffered signal is delivered when the task is unpaused', function(L)
  local sched = L.sched
  local got
  local task = sched.run(function()
    got = pack(sched.wait({'e', buff_mode = 'keep_last'}))
  end)
  sched.set_pause(task, true)
  sched.signal('e', 7)
  eq(got, nil)
  sched.set_pause(task, false)
  L.loop()
  same(got, {n = 2, 'e', 7})
end)

test('pausing a dead task fails', function(L)
  local task = L.sched.run(function() end)
  same(pack(L.sched.set_pause(task, true)), {n = 2, nil, 'task is dead'})
end)
