local T = require 'harness'
local test, eq, same, ok = T.test, T.eq, T.same, T.ok

local function capture(log)
  local lines = {}
  log.displaylogger = function(module, severity, msg)
    lines[#lines+1] = {module, severity, msg}
  end
  log.format = '%m|%s|%l'
  return lines
end

test('messages are filtered by severity, per module', function(L)
  local log = L.log
  log.setlevel('WARNING')
  local lines = capture(log)
  ok(log.musttrace('ANY', 'ERROR'))
  ok(not log.musttrace('ANY', 'INFO'))
  log.setlevel('DEBUG', 'CHATTY')
  ok(log.musttrace('CHATTY', 'DEBUG'))
  ok(not log.musttrace('CHATTY', 'ALL'))
  log('ANY', 'INFO', 'hidden')
  log('ANY', 'WARNING', 'shown')
  log('CHATTY', 'DEBUG', 'also shown')
  same(lines, {
    {'ANY', 'WARNING', 'ANY|WARNING|shown'},
    {'CHATTY', 'DEBUG', 'CHATTY|DEBUG|also shown'},
  })
end)

test('messages are formatted, and sent to the store logger too', function(L)
  local log = L.log
  log.setlevel('ALL')
  local lines = capture(log)
  local stored = {}
  log.storelogger = function(_, _, msg) stored[#stored+1] = msg end
  log.trace('MOD', 'INFO', 'n=%d s=%s', 5, 'x')
  same(lines, {{'MOD', 'INFO', 'MOD|INFO|n=5 s=x'}})
  same(stored, {'MOD|INFO|n=5 s=x'})
end)

test('a bad format string does not raise', function(L)
  local log = L.log
  log.setlevel('ALL')
  local lines = capture(log)
  log('MOD', 'ERROR', 'n=%d', 'not a number')
  ok(#lines > 0)
  ok(lines[1][3]:find('Error in the log formating', 1, true))
end)

test('an unknown level reverts to ALL', function(L)
  local log = L.log
  capture(log)
  log.setlevel('BOGUS')
  eq(log.defaultlevel, log.levels.ALL)
end)
