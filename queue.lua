local M = {}

function M:new ()
	local q = {first = 0, last =-1}
	--OO boilerplate
  	setmetatable(q, self)
	self.__index = self
	return q
end

function M.pushleft (list, value)
	local first = list.first - 1
	list.first = first
	list[first] = value
end

function M.pushright (list, value)
	local last = list.last + 1
	list.last = last
	list[last] = value
end

function M.popleft (list)
	local first = list.first
	if first > list.last then error("list is empty") end
	local value = list[first]
	list[first] = nil        -- to allow garbage collection
	list.first = first + 1
	return value
end

function M.popright (list)
	local last = list.last
	if list.first > last then error("list is empty") end
	local value = list[last]
	list[last] = nil         -- to allow garbage collection
	list.last = last - 1
	return value
end

function M.len(list)
	return list.last - list.first + 1
end

return M
