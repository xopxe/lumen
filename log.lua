------------------------------------------------------------------------------
--- Log library provides logging facilities.
-- The module exposes extension points. It is possible to provide both the custom printing function and the custom log saving function. <br />
-- The module is callable. Thus:
--    local log = require"log"
--    log("MODULE", "INFO", "message")
-- calls the @{trace} function.
-- @module log
------------------------------------------------------------------------------

local pcall = pcall
local string = string
local table = table
local tostring = tostring
local setmetatable = setmetatable
local os = os
local base = _G
local pairs = pairs
local select = select
local next = next

table.pack=table.pack or function (...)
	return {n=select('#',...),...}
end

local M = {}

-------------------------------------------------------------------------------
-- Severity name <-> Severity numeric value translation table. <br />
-- Built-in values (in order from the least verbose to the most):
--
-- - 'NONE'
-- - 'ERROR'
-- - 'WARNING'
-- - 'INFO'
-- - 'DETAIL'
-- - 'DEBUG'
-- - 'ALL'
--
-------------------------------------------------------------------------------
local levels = {}
for k,v in pairs{ 'NONE', 'ERROR', 'WARNING', 'INFO', 'DETAIL', 'DEBUG', 'ALL' } do
    levels[k], levels[v] = v, k
end
M.levels=levels

-------------------------------------------------------------------------------
-- Default verbosity level. <br />
-- Default value is 'WARNING'.
-- See @{levels} to see existing levels.
-------------------------------------------------------------------------------
M.defaultlevel = levels.WARNING
--- Per module verbosity levels.
-- See @{levels} to see existing levels.
-- @table modules
M.modules = {}

-------------------------------------------------------------------------------
-- The string format of the timestamp is the same as what os.date takes.
-- Example: "%F %T"
-------------------------------------------------------------------------------
M.timestampformat = nil

-------------------------------------------------------------------------------
-- logger functions, will be called if non nil
-- the loggers are called with following params (module, severity, logvalue)
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Default logger for instant display.
-- This logger can be replaced by a custom function. <br />
-- It is called only if the log needs to be traced.
-- @param module string identifying the module that issues the log
-- @param severity string representing the log level.
-- @param msg string containing the message to log.
-- @function displaylogger
-------------------------------------------------------------------------------
M.displaylogger = function(_, _, ...)
    if base.print then base.print(...) end
end

-------------------------------------------------------------------------------
-- Logger function for log storage. <br />
-- This logger can be replaced by a custom function. <br />
-- There is no default logger. <br />
-- It is called only if the log needs to be traced (see @{musttrace}) and after the log has been displayed using {displaylogger}.
-- @param module string identifying the module thats issues the log
-- @param severity string representing the log level.
-- @param msg string containing the message to log.
-- @function storelogger
-------------------------------------------------------------------------------
M.storelogger = nil

-------------------------------------------------------------------------------
-- Format is a string used to apply specific formating before the log is outputted. <br />
-- Within a format, the following tokens are available (in addition to standard text)
--
-- - %l => the actual log (given in 3rd argument when calling log() function)
-- - %t => the current date
-- - %m => module name
-- - %s => log level (severity)
--
-------------------------------------------------------------------------------
M.format = nil

local function loggers(...)
    if M.displaylogger then M.displaylogger(...) end
    if M.storelogger then M.storelogger(...) end
end

-------------------------------------------------------------------------------
-- Determines whether a log must be traced depending on its severity and the module.
-- issuing the log.
-- @param module string identifying the module that issues the log.
-- @param severity string representing the log level.
-- @return `nil' if the message of the given severity by the given module should
-- not be printed.
-- @return true if the message should be printed.
-------------------------------------------------------------------------------
function M.musttrace(module, severity)
    -- get the log level for this module, or default log level
    local lev, sev = M.modules[module] or M.defaultlevel, levels[severity]
    return not sev or lev >= sev
end


-------------------------------------------------------------------------------
-- Prints out a log entry according to the module and the severity of the log entry. <br />
-- This function uses @{format} and @{timestampformat} to create the final message string. <br />
-- It calls @{displaylogger} and @{storelogger}.
-- @param module string identifying the module that issues the log.
-- @param severity string representing the log level.
-- @param fmt string format that holds the log text the same way as string.format does.
-- @param ... additional arguments can be provided (as with string.format).
-- @usage trace("MODULE", "INFO", "message=%s", "sometext").
-------------------------------------------------------------------------------
function M.trace(module, severity, fmt, ...)
    module = tostring (module)
    severity = tostring (severity)
    if not M.musttrace(module, severity) then return end
    fmt = tostring (fmt)

    local c, s = pcall(string.format, fmt, ...)
    if c then
        local t
        local function sub(p)
            if     p=="l" then return s
            elseif p=="t" then t = t or tostring(os.date(M.timestampformat)) return t
            elseif p=="m" then return module
            elseif p=="s" then return severity
            else return p end
        end
        local out = (M.format or "%t %m-%s: %l"):gsub("%%(%a)", sub)
        loggers(module, severity, out)
    else -- fallback printing when the formating failed. The fallback printing allow to safely print what was given to the log function, without crashing the thread !
        local args = {}
        local t = table.pack(...)
        for k = 1, t.n do table.insert(args, tostring(k)..":["..tostring(t[k]).."]") end
        --trace(module, severity, "\targs=("..table.concat(args, " ")..")" )
        loggers(module, severity, "Error in the log formating! ("..tostring(s)..") - Fallback to raw printing:" )
        loggers(module, severity, string.format("\tmodule=(%s), severity=(%s), format=(%q), args=(%s)", module, severity, fmt, table.concat(args, " ") ) )
    end
end


-------------------------------------------------------------------------------
-- Sets the log level for a list of module names.
-- If no module name is given, the default log level is affected
-- @param slevel level as in @{levels}
-- @param ... Optional list of modules names (string) to apply the level to.
-- @return nothing.
-------------------------------------------------------------------------------
function M.setlevel(slevel, ...)
    local mods = {...}
    local nlevel = levels[slevel] or levels['ALL']
    if not levels[slevel] then
        trace("LOG", "ERROR", "Unknown severity %q, reverting to 'ALL'", tostring(slevel))
    end
    if next(mods) then for _, m in pairs(mods) do M.modules[m] = nlevel end
    else M.defaultlevel = nlevel end
end

-------------------------------------------------------------------------------
-- Make the module callable, so the user can call log(x) instead of log.trace(x)
-------------------------------------------------------------------------------
setmetatable(M, {__call = function(_, ...) return M.trace(...) end })

return M
