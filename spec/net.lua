--- Helpers for tests that use real sockets (over loopback, with real time).
local T = require 'harness'

local M = {}

--- Start the luasocket selector, or skip the test if luasocket is missing.
M.init_selector = function(L)
  if not pcall(require, 'socket') then L.skip('luasocket not available') end
  local selector = require 'lumen.tasks.selector'
  selector.init({service = 'luasocket'})
  return selector
end

--- Run body in a task, stopping the (endless) selector task when it
-- finishes, dies on error, or after a deadline.
M.run_with_selector = function(L, selector, body, deadline)
  local sched = L.sched
  local timed_out = false
  local main = sched.new_task(body)
  local watchdog = sched.run(function()
    sched.sleep(deadline or 5)
    timed_out = true
    sched.kill(main)
  end)
  sched.run(function()
    sched.wait({main.EVENT_FINISH, main.EVENT_DIE})
    sched.kill(watchdog)
    sched.kill(selector.task)
  end)
  sched.run(main)
  L.loop()
  T.eq(timed_out, false, 'timed out')
end

return M
