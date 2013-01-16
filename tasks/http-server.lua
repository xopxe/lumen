--- Module providing a web server.
-- This is a general purpose web server. It depends on the selector module
-- being up and running.  
-- To use it, the programmer must register callbacks for method/url pattern pairs.
-- @module http-server 
-- @alias M

local log=require 'log'

local sched = require 'sched'
local selector = require 'tasks/selector'
local http_util = require 'tasks/http-server/http-util'
--local stream = require 'stream'


local M = {}

--- How long keep a session open.
M.HTTP_TIMEOUT = 15 --how long keep connections open

-- Derived from Orbit & Orbiter
M.request_handlers = {}
local request_handlers = M.request_handlers

--- Register a new handler.
-- @param method the http method to be attendend, such as 'GET', 'POST' or '*'
-- @param pattern if a url matches this, the handler is selected. When the pattern of several
-- handler overlap, the one deeper is selected (ie if there is '/' and '/docs/', the later is selected)
-- @param callback the callback function. Must have a _method, path, http\_params, http\_header_ 
-- signature, where _http\_params, http\_header_ are tables. If callback is nil, a handler with matching
-- method and pattern will  be removed. The callback must reurn a number 
-- (an http error code), followed by an array with headers, and a string (the content).
M.set_request_handler = function ( method, pattern, callback )
	for i = 1,  #request_handlers do
		local handler = request_handlers[i]
		if method == handler.method and pattern == handler.pattern then
			if callback then 
				handler.callback = callback
			else
				table.remove(request_handlers, i)
			end
			return
		end
	end
	local _, depth = pattern:gsub('/','')
	request_handlers[#request_handlers+1] = {
		method=method, 
		pattern=pattern, 
		callback=callback,
		depth=depth,
	}
end

--- Serve static files from a folder.
-- This helper function calls @{set_request_handler} with a handler for providing static content.
-- @param webroot the root of the url where the content will be served. 
-- @param fileroot the path to the root folder where the content to be served is found.
M.serve_static_content = function (webroot, fileroot)
	M.set_request_handler(
		'GET', 
		webroot,
		function(method, path, http_params, http_header)
			path = path:sub(#webroot)
			if path:sub(-1) == '/' then path=path..'index.html' end
			local file, err = io.open(fileroot..path, "r")
			if file then 
				local extension = path:match('%.(%a+)$') or 'other'
			        local mime = http_util.mime_types[extension] or 'text/plain'
				local content = file:read('*all')
				if content then 
					return 200, {['Content-Type']=mime}, content
				else
					return 500
				end
			else
				print ('Error opening file', err)
				return 404
			end
		end
	)
end

--- Start the http server.
-- @param conf a configuration table. Attributes of interest are _ip_ (defaults to '*')
-- and _port_ (defaults to 8080).
M.init = function(conf)
	conf = conf or  {}
	local ip = conf.ip or '*'
	local port = conf.port or 8080
		
	local tcp_server = selector.new_tcp_server(ip, port, 0, 'stream')
	
	local servertask = sched.new_task( function()
		local waitd_accept={emitter=selector.task, events={tcp_server.events.accepted}}
		print('webserver accepting connections on', tcp_server:getsockname())
		M.task = sched.sigrun(waitd_accept, function (_,_, sktd_cli, instream)
			local function find_matching_handler(method, url)
				local max_depth, best_handler = 0
				for i = 1,  #request_handlers do
					local handler = request_handlers[i]
					if handler.method == '*' or handler.method == method then
						if url:match(handler.pattern) and handler.depth>max_depth then
							max_depth=handler.depth
							best_handler=handler
						end
					end
				end
				if best_handler then return best_handler.callback end
			end
			local function parse_params(s)
				local params={}
				for k,v in string.gmatch(s, '([%w%%%_%-]+)=?([%w%%%_%-]*)') do
					--print('PARAM', k, v)
					params[k]=v
				end
				return params
			end
			
			instream:set_timeout(M.HTTP_TIMEOUT, -1)
			print ("#", os.time(), sktd_cli )
			while true do
				--read first line
				local request = instream:read_line()
				if not request then sktd_cli:close(); return end
				local method,path, params, version = 
					string.match(request, '^([A-Z]+) ([%/%.%d%w%-_]+)[%?]?(%S*) HTTP/(.+)$')
				
				print ('HTTP', method, path, params, version)
				
				local http_header  = {}
				--read header
				while true do
					local line = instream:read_line()
					if not line then sktd_cli:close(); return end
					if line=='' then break end
					local key, value=string.match(line, '^([^:]+):%s*(.*)$')
					--print ('HEADER', line, key, value)
					http_header[key] = value
				end
				local content_length = http_header['Content-Length'] or 0
				
				local data = instream:read(content_length)
				if not data then sktd_cli:close(); return end
				--print ('DATA', #data,  data)
				
				local http_params
				if method=='POST' then 
					http_params=parse_params(data)
				else
					http_params=parse_params(params)
				end
				
				local code_out, header_out, response
				--print ('matching', path, path:match('/[^/%.]+$'))
				if path:match('/[^/%.]+$') then 
					--redirect to path..'/'
					code_out, header_out = 301, {['Location']='http://'..http_header['Host']..path..'/'}
				else
					local callback = find_matching_handler(method, path)
					if callback then 
						code_out, header_out, response = callback(method, path, http_params, http_header)
					else
						code_out = 404
					end
				end
				
				local out = http_util.build_http(code_out, header_out, response)
				sktd_cli:send_sync(out)
				
				--sktd_cli:close()
				
				if version == '1.0' then 
					sktd_cli:close()
					return
				end
			end
		end)
	end)
	M.task = servertask
	servertask:run()
end

return M