package.path = package.path .. ";;;../../?.lua;../../?/init.lua;"

local sched = require "lumen.sched"


sched.run(function()
  local waitdb = sched.new_waitd({timeout=1})
  while true do
    print ('a', sched.wait(waitdb))
  end
end)

sched.run(function()
  local waitda = sched.new_waitd({timeout=3})
  while true do
    print ('b', sched.wait(waitda))
  end
end)

sched.loop()