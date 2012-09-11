--- Library suporting sockets and files.
-- Selector integrates Lumen with a select/poll-like mechanism. 
-- Backends luasocket and nixio are supported.
-- @module selector
-- @usage local selector = require 'selector'
-- @alias M

local M = {}

M.init = function(conf)
	conf=conf or {}
	M.service=conf.service or 'luasocket'
	
	local native = require ('tasks/selector-'..M.service)
	native.init()
	
	M.new_tcp_server = native.new_tcp_server
	M.new_tcp_client = native.new_tcp_client
	M.new_udp = native.new_udp
	M.close = native.close
	M.send_sync = native.send_sync
	M.send = native.send
	M.send_async = native.send_async
	M.new_fd = native.new_fd
	M.task = native.task

	require 'catalog'.get_catalog('tasks'):register('selector', M.task)

	--[[
	M.register_server = service.register_server
	M.register_client = service.register_client
	M.unregister = service.unregister
	--]]
	return M
end

return M


