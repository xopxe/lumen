local M = {}

function M:new ()
	local q = {first = 0, last =-1, data1={},data2={},data3={}}
	--OO boilerplate
  	setmetatable(q, self)
	self.__index = self
	return q
end

function M.pushleft (list, v1, v2, v3)
	local first = list.first - 1
	list.first = first
	list.data1[first], list.data2[first], list.data3[first] = v1, v2, v3
end

function M.pushright (list, v1, v2, v3)
	local last = list.last + 1
	list.last = last
	list.data1[last], list.data2[last], list.data3[last] = v1, v2, v3
end

function M.popleft (list)
	local first = list.first
	if first > list.last then error("list is empty") end
	local v1, v2, v3 = list.data1[first], list.data2[first], list.data3[first]
	list.data1[first], list.data2[first], list.data3[first] = nil, nil, nil -- to allow garbage collection
	list.first = first + 1
	return v1, v2, v3
end

function M.popright (list)
	local last = list.last
	if list.first > last then error("list is empty") end
	local v1, v2, v3 = list.data1[last], list.data2[last], list.data3[last]
	list.data1[last], list.data2[last], list.data3[last] = nil, nil, nil -- to allow garbage collection
	list.last = last - 1
	return v1, v2, v3
end

function M.len (list)
	return list.last - list.first + 1
end

return M
