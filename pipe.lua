local M = {}

local sched = require 'sched'
local catalog =  setmetatable({}, { __mode = 'kv' })

M.new = function(name, size, timeout)
	local piped = {}
	local pipe_enable = {} 
	local waitd_read={buff_len=size, timeout=timeout, events = {piped}}
	local waitd_write={buff_len=1, buff_mode='drop_first', events = {pipe_enable}}
	piped = {
		--name=name,
		waitd_read=waitd_read, 
		waitd_write=waitd_write, 
	}
	catalog[name]=piped
	return piped
end

M.get = function(name)
	return catalog[name]
end

M.read = function (piped)
	local _, data = sched.wait(piped.waitd_read)
	if piped.buff:len() < piped.buff_len then
		sched.signal(piped.pipe_enable)
	end
	return unpack(data, 1, data.len)
end

M.write = function (piped, ...)
	sched.wait(piped.waitd_write)
	sched.signal(piped, {..., len=select('#', ...)})
end

return M