--look for packages one folder up.
package.path = package.path .. ";;;../../?.lua;../../?/init.lua"

local sched = require 'lumen.sched'
local stream = require 'lumen.stream'
local selector = require 'lumen.tasks.selector'

selector.init({service='nixio'})

local astream=stream.new()

-- task that issues command
sched.run(function()
    local sktd = selector.grab_stdout('ping -c 5 8.8.8.8', '*a', astream)
end)

-- task receives ping output
sched.run(function()
	while true do
        local a, b, c = astream:read()
        if a ~= nil then
            print (a)
        else
            return
        end
    end
end)

sched.loop()
