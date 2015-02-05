--- Module suporting asynchronous access to sockets and files.
-- Selector integrates Lumen with a select/poll-like mechanism.   
-- Backends luasocket and nixio are supported.  
-- The socket can be setup to react to data arrival by either calling a handler function,
-- writing to a @{stream}, or emiting signals.
-- @module selector
-- @usage local selector = require 'lumen.selector'
--selector.init({service='luasocket'})
-- @alias M

local M = {}

--- Start the service.
-- @param conf the configuration table (see @{conf}).
M.init = function(conf)
	conf=conf or {}
	M.service=conf.service or 'luasocket'
	
	local native = require ('lumen.tasks.selector-'..M.service)
	native.init()
	
	--- Creates a TCP server socket.
	-- Emits a _sktd.events.accepted, client\_sktd_ signal on new connections.
	-- @function new_tcp_server
	-- @param locaddr Local IP address or '*' (defaults to '*')
	-- @param locport Local port (defaults to 0)
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler Optional,  a handler function or 'stream'. Will be used 
	-- when creating new client sockets.  See @{new_tcp_client}. 
	-- 'stream' mean a new stream will be created, and provided in 
	-- the @{sktd} object.
	-- @return a @{sktd} object
	M.new_tcp_server = native.new_tcp_server

	--- Creates a TCP client socket.
	-- Can be set up to use a handler function, write to a stream, or emit signals
	-- (_sktd.events.data, data_ signal on incommig data, and _sktd.events.data, nil, err_ on errors).
	-- @function new_tcp_client
	-- @param address Remote IP address. 
	-- @param port Remote port ()
	-- @param locaddr Local IP address or '*' (defaults to '*')
	-- @param locport Local port (defaults to 0)
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler Optional, either a handler function or a stream.  
	-- The handler function must have a (sktd, data, err, part) signature.
	-- The handler must return true to keep the socket open, otherwised the socket will b e closed
	-- as soon as it returns (or errors).  
	-- When a stream it will be used to push data as it arrives. On socket closing, the stream 
	-- will be closed with the error message as provided by the socket.  
	-- If the handler parameter is nil, the socket object will emit signals. 
	-- @return a @{sktd} object on success, _nil, err_ on fauilure
	M.new_tcp_client = native.new_tcp_client
	
	--- Creates a UDP socket.
	-- Can be set up to use a handler function, write to a stream, or emit signals
	-- (_sktd.events.data, data_ signal on incommig data, and _sktd.events.data, nil, err_ on errors).
	-- @function new_udp
	-- @param address Remote IP address. 
	-- @param port Remote port ()
	-- @param locaddr Local IP address or '*' (defaults to '*')
	-- @param locport Local port (defaults to 0)
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler Optional, either a handler function or a stream. 
	-- The handler function must have a (sktd, data, err, part) signature.
	-- The handler must return true to keep the socket open, otherwised the socket will be closed
	-- as soon as it returns (or errors).  
	-- When a stream it will be used to push data as it arrives. On socket closing, the stream 
	-- will be closed with the error message as provided by the socket.  
	-- If the handler parameter is nil, the socket object will emit signals.  
	-- @return a @{sktd} object
	M.new_udp = native.new_udp
	
	--- Opens a file.
	-- Can be set up to use a handler function, write to a stream, or emit signals
	-- (_sktd.events.data, data_ signal on incommig data, and _sktd.events.data, nil, err_ on errors).
	-- @function new_fd
	-- @param filename 
	-- @param flags ATM as specified for nixio.open()
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler Optional, either a handler function or a stream. 
	-- The handler function must have a (sktd, data, err, part) signature.
	-- The handler must return true to keep the socket open, otherwised the socket will b e closed
	-- as soon as it returns (or errors).  
	-- When a stream it will be used to push data as it arrives. On socket closing, the stream 
	-- will be closed with the error message as provided by the socket.  
	-- If the handler parameter is nil, the socket object will emit signals. 
	-- @return a @{sktd} object
	M.new_fd = native.new_fd
	
	--- Grab the output of a command.
	-- Usefull for capturing the output of long running programs.  
	-- Can be set up to use a handler function, write to a stream, or emit signals
	-- (_sktd.events.data, data_ signal on incommig data, and _sktd.events.data, nil, err_ on errors).
	-- @function grab_stdout
	-- @param command command whose ouput capture
	-- @param pattern Any of nixio or luasocket patterns.
	-- @param handler Optional, either a handler function or a stream. 
	-- The handler function must have a (sktd, data, err, part) signature.
	-- The handler must return true to keep the socket open, otherwised the socket will b e closed
	-- as soon as it returns (or errors).  
	-- When a stream it will be used to push data as it arrives. On socket closing, the stream 
	-- will be closed with the error message as provided by the socket.  
	-- If the handler parameter is nil, the socket object will emit signals. 
	-- @return a @{sktd} object
	M.grab_stdout = native.grab_stdout 
	
	--- Closes a socket/file.
	-- @function close
	-- @param sktd a @{sktd} object
	M.close = native.close
	
	--- Synchronous data send.
	-- The task calling this function will block until all data is sent.
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
	-- This call return immediatelly. The data transmission will continue in background. Aditional calls
	-- will queue data. When all data queued for asynchronous transmission is sent, 
	-- a `sktd.events.async_finished, success` signal is emitted.
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

	--- Suggested max buffer size for asynchronous sending.
	-- Must be set before first call to async send. Defaults to 1mb.
	M.ASYNC_SEND_BUFFER=1024^2 --1mb

	require 'lumen.catalog'.get_catalog('tasks'):register('selector', M.task)

	return M
end

--- Socket/File descriptor.
-- Provides OO-styled access to methods, such as sktd:send(data) and sktd:close()
-- @field task task that will emit signal related to this object
-- @field stream If asigned a @{stream} object, will write data into it (in addittion to signals)
-- @table sktd

--- Configuration Table.
-- @table conf
-- @field service backend to use: 'nixio' or 'luasocket' (default)


return M


