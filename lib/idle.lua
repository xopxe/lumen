--idle.lua

---[[
-- Uncomment to attempt to use lsleep
-- https://github.com/andrewstarks/lsleep
local success, lsleep = pcall(require, 'lsleep')
--]]

local function unix_idle  (t)
	local ret = os.execute('sleep '..t)
  --[[
  if _VERSION =='Lua 5.1' and type(jit) ~= 'table' and ret ~= 0
  or _VERSION =='Lua 5.1' and type(jit) == 'table' and ret ~= true 
  or _VERSION ~='Lua 5.1' and ret ~= true then
  --]]
  if ret == 0 or ret == true then
      return
  end
  os.exit()
end

local function windows_idle  (t)
	os.execute( ('ping 1.1.1.1 -n 1 -w %d > nul'):format(t * 1000) )
end

-- We have default functions for Windows and Linux
-- You can replace with your own function. If none useful is available, you can use an empty
-- function (i.e. "function() end"), which will result in busy wating.
-- Notice that the selector-* libs replace the idle function with a socket based sleep.
return os.getenv('OS') and os.getenv('OS'):match("^Windows-.") and windows_idle or unix_idle
