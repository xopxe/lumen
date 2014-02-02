--- Pipes.
-- Pipes allow can be used to communicate tasks. Unlike plain signals,
-- no message can be missed by  task doing something else when the signal occurs:
-- writers get blocked when the pipe is full
-- @module pipes
-- @usage local pipe = require 'lumen.pipe'
-- @alias M

local sched = require 'lumen.sched'
local log=require 'lumen.log'
local queue=require 'lumen.lib.queue2'

local unpack = unpack or table.unpack

table.pack = table.pack or function (...)
	return {n=select('#',...),...}
end

--get locals for some useful things
local setmetatable, tostring = setmetatable, tostring


local M = {}

--- Read from a pipe.
-- Will block on a empty pipe. Also accessible as piped:read()
-- @param piped the the pipe descriptor to read from.
-- @return  _true,..._ if data is available, _nil,'timeout'_ on timeout
M.read = function (piped)
  while piped.buff_data:len() == 0 do
    piped.rblocked = true
		local ev = sched.wait(piped.waitd_data)
    piped.rblocked = false
		if not ev then return nil, 'timeout' end
  end
  local packed, ret = piped.buff_data:popleft()
	if piped.wblocked then
		sched.signal(piped.pipe_enable_signal)
	end
  if packed then
    return true, unpack(ret, 1, ret.n)
  else
    return true, ret
  end
end

--- Write to a pipe.
-- Will block when writing to a full pipe. Also accessible as piped:write()
-- @param piped the the pipe descriptor to write to.
-- @param ... elements to write to pipe. All params are stored as a single entry.
-- @return _true_ on success, _nil,'timeout'_ on timeout
M.write = function (piped, ...)
	while piped.size and piped.buff_data:len() >= piped.size do
    piped.wblocked = true
		local ev = sched.wait(piped.waitd_enable)
    piped.wblocked = false
		if not ev then return nil, 'timeout' end
	end
  if select('#', ...) > 1 then
    piped.buff_data:pushright(true, table.pack(...))
  else
    piped.buff_data:pushright(false, select(1, ...))
  end
  if piped.rblocked then 
    sched.signal(piped.pipe_data_signal) 
  end
	return true
end

--- Number of entries in a pipe.
-- Also accessible as piped:len()
-- @param piped the the pipe descriptor.
-- @return number of entries
M.len = function (piped)
	return piped.buff_data:len()
end

local n_pipes=0
--- Create a new pipe.
-- @param size maximum number of signals in the pipe
-- @param timeout timeout for blocking on pipe operations. -1 or nil disable
-- timeout
-- @return a pipe descriptor 
M.new = function(size, timeout)
	n_pipes=n_pipes+1
	local pipename = 'pipe: #'..tostring(n_pipes)
	local piped = setmetatable({
      read = M.read,
      write = M.write,
      len = M.len,
  }, {__tostring=function() return pipename end--[[,__index=M]]})
	log('PIPE', 'DETAIL', 'pipe with name "%s" created', tostring(pipename))
	log('PIPE', 'DETAIL', 'pipe with name "%s" created', tostring(pipename))
	piped.size=size
	piped.pipe_enable_signal = {} --singleton event for pipe control
	piped.pipe_data_signal = {} --singleton event for pipe data
	piped.buff_data = queue:new()
  piped.rblocked, piped.wblocked = false, false
	piped.waitd_data = {
    piped.pipe_data_signal,
		timeout=timeout, 
		buff_mode='keep_first', 
	}
	piped.waitd_enable = {
    piped.pipe_enable_signal,
		timeout=timeout, 
		buff_mode='keep_first', 
	}
	
	return piped
end

return M

