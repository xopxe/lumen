--- Module suporting asynchronous access to sockets and files.
-- Selector integrates Lumen with a select/poll-like mechanism. 
-- Backends luasocket and nixio are supported.
-- Module's task will generate signals on data arrival on opened 
-- sockets/files. Also a @{stream} can be used to pipe data from 
-- sockets/files.
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
	-- @param locaddr Local IP address or '*' (defaults to '*')
	-- @param locport Local port (defaults to 0)
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler optional handler function for new clients, 
	-- must have a (sktd, data, err, part) signature
	-- @param create_stream create a new stream object for new clients.
	-- @return a @{sktd} object
	M.new_tcp_server = native.new_tcp_server

	--- Creates a TCP client socket.
	-- Emits a _sktd.events.data, data_ signal on incommig data, 
	-- and _sktd.events.data, nil, err_ on errors.
	-- @function new_tcp_client
	-- @param address Remote IP address. 
	-- @param port Remote port ()
	-- @param locaddr Local IP address or '*' (defaults to '*')
	-- @param locport Local port (defaults to 0)
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler optional handler function, must have a (sktd, data, err, part) signature
	-- @param stream an optional @{stream} object to pipe data into.
	-- @return a @{sktd} object
	M.new_tcp_client = native.new_tcp_client
	
	--- Creates a UDP socket.
	-- Emits a _sktd.events.data, data_ signal on incommig data, 
	-- and _sktd.events.data, nil, err_ on errors.
	-- @function new_udp
	-- @param address Remote IP address. 
	-- @param port Remote port ()
	-- @param locaddr Local IP address or '*' (defaults to '*')
	-- @param locport Local port (defaults to 0)
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler optional handler function, must have a (sktd, data, err, part) signature
	-- @return a @{sktd} object
	M.new_udp = native.new_udp
	
	--- Opens a file.
	-- Emits a _sktd.events.data, data_ signal on incommig data, 
	-- and _sktd.events.data, nil, err_ on errors.
	-- @function new_fd
	-- @param filename 
	-- @param flags ATM as specified for nixio.open()
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler optional handler function, must have a (sktd, data, err, part) signature
	-- @return a @{sktd} object
	M.new_fd = native.new_fd
	
	--- Grab the output of a command.
	-- Usefull for capturing the output of long running programs.
	-- Emits a _sktd.events.data, data_ signal on incommig data, 
	-- and _sktd.events.data, nil, err_ on errors.
	-- @function grab_stdout
	-- @param command command whose ouput capture
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler optional handler function, must have a (sktd, data, err, part) signature
	-- @return a @{sktd} object
	M.grab_stdout = native.grab_stdout 
	
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
	
	--- Get the local address of a socket.
	-- @function getsockname
	-- @param sktd a @{sktd} object
	-- @return  _ip, port_
	M.getsockname = native.getsockname

	--- Get the remote address of a socket.
	-- @function getpeername
	-- @param sktd a @{sktd} object
	-- @return  _ip, port_
	M.getpeername = native.getpeername

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
-- @field stream If asigned a @{stream} object, will write data into it (in addittion to signals)
-- @table sktd


return M


