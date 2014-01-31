---
-- A demonstration of pipes.

--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua;"

local sched=require 'lumen.sched'
--require "log".setlevel('ALL')
local catalog=require 'lumen.catalog'
local c = catalog.get_catalog('stuff')

sched.run(function()
  for i=1, 10 do
    --collectgarbage()
    sched.sleep (.1)
    local o = 'OBJ'..i
    print('storing', o)
    c:register('object'..i, o)
  end
end)

sched.run(function()
  for i=1, 10 do
  --for i=10, 1, -1 do
    --collectgarbage()
    local o = c:waitfor('object'..i)
    print('found', o) 
  end
end)

sched.loop()
