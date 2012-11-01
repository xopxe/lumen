--- Library suporting asynchronous access to sockets and files.
-- Selector integrates Lumen with a select/poll-like mechanism. 
-- Backends luasocket and nixio are supported.
-- @module selector
-- @usage local selector = require 'selector'
--selector.init({service='luasocket'})
-- @alias M

local M = {}

--- Start the task.
-- @param conf the configuration table. The fields of interest is
-- _service_ , the backend to use (defaults to 'luasocket')
M.init = function(conf)
	conf=conf or {}
	M.service=conf.service or 'luasocket'
	
	local native = require ('tasks/selector-'..M.service)
	native.init()
	
	--- Creates a TCP server socket.
	-- Emits a _sktd.events.accepted, client\_sktd_ signal on new connections.
	-- @function new_tcp_server
	-- @param locaddr
	-- @param locport
	-- @param pattern
	-- @param handler optional handler function for new clients, 
	-- must have a (sktd, data, err, part) signature
	-- @return a @{sktd} object
	M.new_tcp_server = native.new_tcp_server

	--- Creates a TCP client socket.
	-- Emits a _sktd.events.data, data_ signal on incommig data, 
	-- and _sktd.events.data, nil, err_ on errors.
	-- @function new_tcp_client
	-- @param address
	-- @param port
	-- @param locaddr
	-- @param locport
	-- @param pattern
	-- @param handler optional handler function, must have a (sktd, data, err, part) signature
	-- @return a @{sktd} object
	M.new_tcp_client = native.new_tcp_client
	
	--- Creates a UDP socket.
	-- Emits a _sktd.events.data, data_ signal on incommig data, 
	-- and _sktd.events.data, nil, err_ on errors.
	-- @function new_udp
	-- @param address
	-- @param port
	-- @param locaddr
	-- @param locport
	-- @param pattern
	-- @param handler optional handler function, must have a (sktd, data, err, part) signature
	-- @return a @{sktd} object
	M.new_udp = native.new_udp
	
	--- Closes a socket/file.
	-- @function close
	-- @param sktd a @{sktd} object
	M.close = native.close
	
	--- Synchronous data send.
	-- @function send_sync
	-- @param sktd a @{sktd} object
	-- @param data data to send
	-- @return _true_ on success. _nil, err, partial_ on failure
	M.send_sync = native.send_sync
	
	--- Alias for send\_sync.
	-- can be reasigned to to send\_async, if so preferred
	-- @function send
	M.send = native.send
	
	--- Asynchronous data send.
	-- @function send_async
	-- @param sktd a @{sktd} object
	-- @param data data to send
	M.send_async = native.send_async
	
	--- Opens a file.
	-- Emits a _sktd.events.data, data_ signal on incommig data, 
	-- and _sktd.events.data, nil, err_ on errors.
	-- @function new_fd
	-- @param filename
	-- @param flags
	-- @param pattern
	-- @param handler optional handler function, must have a (sktd, data, err, part) signature
	-- @return a @{sktd} object
	M.new_fd = native.new_fd
	
	--- Task that emits signals.
	M.task = native.task

	require 'catalog'.get_catalog('tasks'):register('selector', M.task)

	--[[
	M.register_server = service.register_server
	M.register_client = service.register_client
	M.unregister = service.unregister
	--]]
	return M
end

------
-- Socket/File descriptor.
-- Provides OO-styled access to methods, such as sktd:send(data) and sktd:close()
-- @field task task that will emit signal related to this object
-- @table sktd


return M


