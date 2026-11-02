--- Minimal test harness for Lumen, with no external dependencies.
-- Every test gets freshly loaded lumen modules (so scheduler state never leaks
-- between tests) and a fake clock: idling advances the clock instead of
-- sleeping, so timeouts are instant and deterministic.

local unpack = unpack or table.unpack

local M = {}

local tests = {}

--- Register a test. The body receives a fresh lumen environment (see @{new_env}).
M.test = function(name, f)
  tests[#tests+1] = {name = name, f = f, file = M.current_file}
end

M.tests = tests

--- Pack call results, keeping trailing nils.
M.pack = function(...)
  return {n = select('#', ...), ...}
end

---------------------------------------
-- assertions

local function fmt(v)
  if type(v) == 'string' then return string.format('%q', v) end
  return tostring(v)
end

local function fail(msg, level)
  error(msg, (level or 1) + 2)
end

M.eq = function(actual, expected, msg)
  if actual ~= expected then
    fail((msg and msg..': ' or '')..'expected '..fmt(expected)..', got '..fmt(actual))
  end
end

local function deep_eq(a, b)
  if a == b then return true end
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k, _ in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function dump(v)
  if type(v) ~= 'table' then return fmt(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys+1] = k end
  table.sort(keys, function(x, y)
    if type(x) == type(y) and (type(x) == 'number' or type(x) == 'string') then
      return x < y
    end
    return type(x) < type(y)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts+1] = '['..fmt(k)..']='..dump(v[k])
  end
  return '{'..table.concat(parts, ', ')..'}'
end

M.same = function(actual, expected, msg)
  if not deep_eq(actual, expected) then
    fail((msg and msg..': ' or '')..'expected '..dump(expected)..', got '..dump(actual))
  end
end

M.ok = function(v, msg)
  if not v then fail(msg or ('expected a true value, got '..fmt(v))) end
  return v
end

--- Assert that calling f raises an error whose message matches pattern.
M.raises = function(pattern, f, ...)
  local ok, err = pcall(f, ...)
  if ok then fail('expected an error matching '..fmt(pattern)) end
  if pattern and not tostring(err):find(pattern) then
    fail('expected an error matching '..fmt(pattern)..', got '..fmt(err))
  end
  return err
end

---------------------------------------
-- environment

local function unload_lumen()
  for name in pairs(package.loaded) do
    if name == 'lumen' or name:sub(1, 6) == 'lumen.' then
      package.loaded[name] = nil
    end
  end
end

local SKIP = {}

--- Create a fresh lumen environment.
-- Fields: sched, pipe, stream, mutex, catalog, log (fresh modules), now (the
-- fake clock), errors (messages from tasks that died on error), and methods
-- loop, allow_errors and skip.
M.new_env = function()
  unload_lumen()
  local lumen = require 'lumen'
  local env = {
    sched = lumen.sched, pipe = lumen.pipe, stream = lumen.stream,
    mutex = lumen.mutex, catalog = lumen.catalog, log = lumen.log,
    now = 0, errors = {},
  }
  local sched = env.sched
  lumen.log.setlevel('NONE')
  sched.get_time = function() return env.now end
  sched.idle = function(t) env.now = env.now + t end

  -- record errors from any task, so failing asserts inside tasks fail the test
  env.die_listener = sched.sigrun({sched.EVENT_DIE}, function(_, _, err)
    if err ~= 'killed' then env.errors[#env.errors+1] = tostring(err) end
  end)

  --- Run the scheduler until there is nothing left to do (or, if given,
  -- until the clock reaches until_time). Fails if the scheduler never settles.
  env.loop = function(until_time, max_steps)
    max_steps = max_steps or 100000
    for _ = 1, max_steps do
      local idle_time = sched.step()
      if not idle_time then return end
      if until_time and env.now >= until_time then return end
      if idle_time > 0 then sched.idle(idle_time) end
    end
    error('scheduler did not settle after '..max_steps..' steps', 2)
  end

  --- Do not fail the test when tasks die on error (inspect env.errors instead).
  env.allow_errors = function() env.errors_allowed = true end

  env.skip = function(reason) error({[SKIP] = reason}, 0) end

  return env
end

---------------------------------------
-- runner

M.run = function(filter)
  local passed, failed, skipped = 0, 0, 0
  local failures = {}
  for _, t in ipairs(tests) do
    local full_name = t.file..': '..t.name
    if not filter or full_name:find(filter, 1, true) then
      local env
      local ok, err = xpcall(function()
        env = M.new_env()
        t.f(env)
        if #env.errors > 0 and not env.errors_allowed then
          error('task died on error: '..table.concat(env.errors, '\n  '), 0)
        end
      end, function(e)
        if type(e) == 'table' and e[SKIP] then return e end
        return debug.traceback(tostring(e), 2)
      end)
      if ok then
        passed = passed + 1
        io.write('  ok    ', full_name, '\n')
      elseif type(err) == 'table' and err[SKIP] then
        skipped = skipped + 1
        io.write('  skip  ', full_name, ' (', tostring(err[SKIP]), ')\n')
      else
        failed = failed + 1
        if env and #env.errors > 0 and not tostring(err):find('task died on error', 1, true) then
          -- a failed assertion is often caused by a task that died
          err = err..'\ntasks died on error:\n  '..table.concat(env.errors, '\n  ')
        end
        failures[#failures+1] = {name = full_name, err = err}
        io.write('  FAIL  ', full_name, '\n')
      end
    end
  end
  unload_lumen()

  for _, f in ipairs(failures) do
    io.write('\n', f.name, '\n', f.err, '\n')
  end
  io.write(string.format('\n%d passed, %d failed, %d skipped\n', passed, failed, skipped))
  return failed == 0
end

M.unpack = unpack

return M
