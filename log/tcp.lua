-------------------------------------------------------------------------------
-- Allow to redirect Lua logs to TCP sockets, by adding a function
-- log.settarget() to the log module.
-- See function comment below for details.
-------------------------------------------------------------------------------

require 'log'

-------------------------------------------------------------------------------
-- original_displayloger: allow to revert to default behavior
-- clients: list of all currently connected TCP clients
-- server: currently running TCP server, can be nil.
-------------------------------------------------------------------------------
local original_displaylogger = log.displaylogger
local clients = { }
local server  = nil

-------------------------------------------------------------------------------
-- Close all TCP sockets, clients and server.
-------------------------------------------------------------------------------
local function kill_sockets()
    for s, _ in pairs (clients) do s :close(); clients[s] = nil end
    if server then server :close(); server = nil end
end

-------------------------------------------------------------------------------
-- Dispatch log messages to all TCP client sockets.
-------------------------------------------------------------------------------
local function tcplogger(_, _, msg)
    for c, _ in pairs(clients) do
        local status = c :send(msg.."\r\n")
        if not c then c :close(); clients[c]=nil end
    end
end

-------------------------------------------------------------------------------
-- redirect all messages on the Telnet shell.
-------------------------------------------------------------------------------
local function shelllogger(_, _, msg)
    print (msg.."\r\n$ ")
end

-------------------------------------------------------------------------------
-- Allow to redirect display logs.
--  * log.tcp "shell" will send logs to the telnet shell;
--  * log.tcp(n), with n a port number, will start a TCP server
--    socket on that port. Every client connecting to this port will
--    receive the logs; there can be several clients simultaneously.
--  * log.tcp "<host>:<port>" will connect to the given IP, on the
--    given TCP port, and send logs to the established connection.
--  * log.tcp() will revert to the default behavior (logs on UART).
-------------------------------------------------------------------------------
function log.tcp(x, port)
    if type(x)=='string' and x :match "^([^:]+):(%d+)$" then
        x, port = x :match "^([^:]+):(%d+)$"; port = tonumber(port)
    end

    if x=='shell' then
        -- print on shell --
        kill_sockets()
        log.displaylogger = shelllogger

    elseif tonumber(x) then
        -- start log server socket --
        if server then server :close() end
        local function srv_hook (client) clients[client] = true end
        server = socket.bind('*', tonumber(x), srv_hook)
        log.displaylogger = tcplogger

    elseif type(x)=='string' and port then
        -- start log client socket --
        log.displaylogger = tcplogger
        local client, msg = socket.connect (x, port)
        if client then clients[client] = true else error (msg) end

    elseif not x then
        -- back to default --
        kill_sockets()
        log.displaylogger = original_displayloger

    else error "Invalid log.settarget parameter" end
end

return log.tcp
