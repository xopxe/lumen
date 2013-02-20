--- Module providing a web server.
-- This is a general purpose web server. It depends on the selector module
-- being up and running.  
-- To use it, the programmer must register callbacks for method/url pattern pairs.  
-- Handlers for serving static files from disk is provided.
-- @module http-server 
-- @alias M

local log=require 'log'

local sched = require 'sched'
local selector = require 'tasks/selector'
local http_util = require 'tasks/http-server/http-util'
local stream = require 'stream'


local M = {}

local build_http_header = function(status, header, response)
	local httpstatus = tostring(status).." "..http_util.http_error_code[status]
	header = header or {}
	
	if not header["Content-Length"] and type (response) == "string" then 
		header["Content-Length"] = #response
	end
	if not header["Content-Type"] then
		header["Content-Type"] = 'text/plain'
	end

	local header_entries = {}
	for k, v in pairs(header or {}) do
		header_entries[#header_entries+1] = k..": "..v
	end
	
	local header_string = table.concat(header_entries, '\r\n')
	
	local http_string = "HTTP/1.1 "..httpstatus.."\r\n"..header_string.."\r\n\r\n"
	return http_string
end

local function backup_response(code_out, header_out)
	local httpstatus = tostring(code_out).." "..http_util.http_error_code[code_out]
	header_out = header_out or {}
	
	local response = "<html><head><title>"..httpstatus.."</title></head><body><h3>"..httpstatus.."</h3><hr><small>Lumen http-server</small></body></html>"
	header_out["Content-Type"] = 'text/html'
	header_out["Content-Length"] = #response
	
	return header_out, response
end

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

--- Serve static files from a folder (using ram).
-- This helper function calls @{set_request_handler} with a handler for providing static content.  
-- The whole file will be read into RAM and server from there.
-- @param webroot the root of the url where the content will be served. 
-- @param fileroot the path to the root folder where the content to be served is found.
M.serve_static_content_from_ram = function (webroot, fileroot)
	M.set_request_handler(
		'GET', 
		webroot,
		function(method, path, http_params, http_header)
			path = path:sub(#webroot)
			if path:sub(-1) == '/' then path=path..'index.html' end
			local abspath=fileroot..path
						
			local file, err = io.open(abspath, "r")
			if file then 
				local extension = path:match('%.(%a+)$') or 'other'
			        local mime = http_util.mime_types[extension] or 'text/plain'
				local content = file:read('*all')
				file:close()
				if content then 
					return 200, {['Content-Type']=mime, ['Content-Length']=#content}, content
				else
					return 500
				end
			else
				log('HTTP', 'WARN', 'Error opening file %s', err)
				return 404
			end
		end
	)
end

--- Serve static files from a folder (using streams).
-- This helper function calls @{set_request_handler} with a handler for providing static content.  
-- The file will be served as it is read from disk, so there is no file size limitation.  
-- Depends on nixio library.
-- @param webroot the root of the url where the content will be served. 
-- @param fileroot the path to the root folder where the content to be served is found.
-- @param buffer_size the reccmended ammount of RAM to use as buffer (defauls to 100kb)
M.serve_static_content_from_stream = function (webroot, fileroot, buffer_size)
	buffer_size = buffer_size or 100*1024
	local nixio = require 'nixio'
	M.set_request_handler(
		'GET', 
		webroot,
		function(method, path, http_params, http_header)
			path = path:sub(#webroot)
			if path:sub(-1) == '/' then path=path..'index.html' end
			local abspath=fileroot..path
			
			local stream_file = stream.new(buffer_size)
			local sktd, err = selector.new_fd (abspath, {"rdonly"}, nil, stream_file)
			if sktd then 
				local extension = path:match('%.(%a+)$') or 'other'
			        local mime = http_util.mime_types[extension] or 'text/plain'
				local fsize  = nixio.fs.stat(abspath, 'size')
				if fsize then 
					return 200, {['Content-Type']=mime, ['Content-Length']=fsize}, stream_file
				else
					return 500
				end
			else
				log('HTTP', 'WARN', 'Error opening file %s', err)
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
		log('HTTP', 'INFO', 'http-server accepting connections on %s:%s', tcp_server:getsockname())
		M.task = sched.sigrun(waitd_accept, function (_,_, sktd_cli, instream)
			log('HTTP', 'DETAIL', 'http-server accepted connection from %s:%s', sktd_cli:getpeername())
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
			while true do
				--read first line
				local request = instream:read_line()
				if not request then sktd_cli:close(); return end
				local http_req_method,http_req_path, http_req_params, http_req_version = 
					string.match(request, '^([A-Z]+) ([%/%.%d%w%-_]+)[%?]?(%S*) HTTP/(.+)$')
				
				log('HTTP', 'DEBUG', 'incommig request %s %s %s %s', 
					http_req_method, http_req_path, http_req_params, http_req_version)
				
				local http_req_header  = {}
				--read header
				while true do
					local line = instream:read_line()
					if not line then sktd_cli:close(); return end
					if line=='' then break end
					local key, value=string.match(line, '^([^:]+):%s*(.*)$')
					--print ('HEADER', line, key, value)
					http_req_header[key] = value
				end

				--print ('DATA', #data,  data)
				
				local http_params
				if http_req_method=='POST' then 
					local req_content_length = http_req_header['Content-Length'] or 0
					local data = instream:read(req_content_length)
					if not data then sktd_cli:close(); return end
					http_params=parse_params(data)
				else
					http_params=parse_params(http_req_params)
				end
				
				local http_out_code, http_out_header, response
				--print ('matching', path, path:match('/[^/%.]+$'))
				if http_req_path:match('/[^/%.]+$') then 
					--redirect to path..'/'
					http_out_code, http_out_header = 301, {['Location']='http://'..http_req_header['Host']..http_req_path..'/'}
				else
					local callback = find_matching_handler(http_req_method, http_req_path)
					if callback then 
						http_out_code, http_out_header, response = callback(http_req_method, http_req_path, http_params, http_req_header)
					else
						http_out_code = 404
					end
				end
				
				-- we got no content to return, probably code_out<>200
				if not response then 
					http_out_header, response = backup_response(http_out_code, http_out_header)
				end
				
				local need_flush
				
				local response_header = build_http_header(http_out_code, http_out_header, response)
				sktd_cli:send_sync(response_header)
				if type(response) == 'string' then
					sktd_cli:send_sync(response)
				else --stream
					if not http_out_header["Content-Length"] then
						need_flush = true
					end
					while true do
						--TODO share streams?
						local s, err = response:read()
						if not s then break end
						sktd_cli:send_sync(s)
					end
				end
				
				if http_req_version == '1.0' or need_flush then 
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