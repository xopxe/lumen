--idle.lua

--replace with your own funciton


--[[
--https://github.com/andrewstarks/lsleep
local success, lsleep= pcall(require, 'lsleep')
--]]
local success, lsleep= pcall(require, 'lsleep')


function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end





local function unix_idle  (t)

	local ret = os.execute('sleep '..t) 
	if _VERSION =='Lua 5.1' and ret ~= 0 
	or _VERSION =='Lua 5.2' or _VERSION == "Lua 5.3" and ret ~= true then 
		os.exit() 
	end
end

local function windows_idle  (t)
	os.execute( ('ping 1.1.1.1 -n 1 -w %d > nul'):format(t * 1000) )
end

-- return success and lsleep.sleep or 
-- 	os.getenv('OS'):match("^Windows-.") and windows_idle or unix_idle
return os.getenv('OS') and os.getenv('OS'):match("^Windows-.") and windows_idle or unix_idle