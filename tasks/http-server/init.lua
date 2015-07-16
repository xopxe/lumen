--- Module providing a web server.
-- This is a general purpose web server. It depends on the selector module
-- being up and running.  
-- To use it, the programmer must register callbacks for method/url pattern pairs.  
-- Handlers for serving static files from disk are provided.  
-- @module http-server 
-- @alias M
local lumen = require'lumen'

local log 		=	lumen.log
local sched 	= 	lumen.sched
local stream 	= 	lumen.stream

local selector 	= require 'lumen.tasks.selector'
local http_util = require 'lumen.tasks.http-server.http-util'
local websocket -- only loaded if enabled in conf: = require 'lumen.tasks.http-server.websocket'

local function backup_response(code_out, header_out)
	local httpstatus = tostring(code_out).." "..http_util.http_error_code[code_out]
	header_out = header_out or {}
	
	local response = "<html><head><title>"..httpstatus.."</title></head><body><h3>"..httpstatus.."</h3><hr><small>Lumen http-server</small></body></html>"
	header_out["content-type"] = 'text/html'
	header_out["content-length"] = #response
	
	return header_out, response
end

local populate_cache_control =  function(http_out_header, http_req_path, conf)
	if not conf.max_age then return http_out_header end
	local extension = http_req_path:match('^%.*([^%.]+)$')
	local max_age = conf.max_age[extension] 
	if max_age then http_out_header['cache-control'] = 'max-age='..max_age end
	return http_out_header
end

local M = {}

--- How long keep a http session open.
-- Defaults to 15s.
M.HTTP_TIMEOUT = 15 --how long keep connections open

M.EVENT_DATA_TRANSFERRED = {}

-- Derived from Orbit & Orbiter
M.request_handlers = {}
local request_handlers = M.request_handlers

--- Register a new handler.
-- @param method the http method to be attendend, such as 'GET', 'POST' or '*'
-- @param pattern if a url matches this, the handler is selected. When the pattern of several
-- handler overlap, the one deeper is selected (ie if there is '/' and '/docs/', the later is selected)
-- @param callback the callback function. Must have a _method, path, http\_params, http\_header_ 
-- signature, where _http\_params, http\_header_ are tables. If callback is nil, a handler with matching
-- method and pattern will  be removed. The callback must return a number 
-- (an http error code), followed by an array with headers, and a string or stream (the content).
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
-- The whole file will be read into RAM and served from there.
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
					return 200, {['content-type']=mime, ['content-length']=#content}, content
				else
					return 500
				end
			else
				log('HTTP', 'DETAIL', 'Error opening file %s: %s', abspath, err)
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
					return 200, {['content-type']=mime, ['content-length']=fsize}, stream_file
				else
					return 500
				end
			else
				log('HTTP', 'DETAIL', 'Error opening file %s', err)
				return 404
			end
		end
	)
end

--- Serve static files from a table.
-- This helper function calls @{set_request_handler} with a handler for providing content from a table.  
-- @param webroot the root of the url where the content will be served. 
-- @param content File contents to serve will be looked-up in this table.
M.serve_static_content_from_table = function (webroot, content)
	M.set_request_handler(
		'GET', 
		webroot,
		function(method, path, http_params, http_header)
			path = path:sub(#webroot)
			--if path:sub(-1) == '/' then path=path..'index.html' end
      local extension = path:match('%.(%a+)$') or 'other'
      local mime = http_util.mime_types[extension] or 'text/plain'      
      local content = content[path]
      if content then 
        local start=tonumber(http_params['s'])
        if start and start>1 then
          content = content:sub(start)
        end
        return 200, {['content-type']=mime, ['content-length']=#content}, content
      else
        log('HTTP', 'DETAIL', 'Error opening file %s: Not in content', path)
        return 404
      end
		end
	)
end


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

--- Start the http server.
-- @param conf the configuration table (see @{conf}).
M.init = function(conf)
	conf = conf or  {}

	if conf.ws_enable then
		websocket = require 'lumen.tasks.http-server.websocket'
		--- Register a websocket protocol.
		-- The configuration flag _ws_enable_ must be set (see @{conf})
		-- @function set_websocket_protocol
		-- @param protocol the protocol name
		-- @param handler a handler function. This function will be called when a new connection requesting
		-- the protocol arrives. It will be pased a websocket object. If the handler parameter is nil, the protocol will be 
		-- removed.
		-- @param keep_clients when handler is nil, or changing an already present protocol, wether to kill the 
		-- already running connections or leave them.
		M.set_websocket_protocol = websocket.set_websocket_protocol
	end

	local ip = conf.ip or '*'
	local port = conf.port or 8080
	local attached = conf.kill_on_close
	
	local tcp_server = selector.new_tcp_server(ip, port, 0, 'stream')

	local waitd_accept={tcp_server.events.accepted}
	log('HTTP', 'INFO', 'http-server accepting connections on %s:%s', tcp_server:getsockname())
	M.task = sched.sigrun(waitd_accept, function (_, sktd_cli)
		-- run the connection in a separated task
		sched.run(function()
			local instream = sktd_cli.stream
			log('HTTP', 'DETAIL', 'http-server accepted connection from %s:%s', sktd_cli:getpeername())
      
			local read_incomming_header = function()
        --FIXME According to RFC-2616, section 4.2:	Header fields can be extended over multiple 
        --lines by preceding each	extra line with at least one SP or HT. 
				local http_req_header  = {}
				while true do
					local line = instream:read_line()
					if not line then sktd_cli:close(); return end
					if line=='' then break end
					local key, value=string.match(line, '^(.-):%s*(.-)$')
					--print ('HEADER', key, value)
					if key and value then http_req_header[key:lower()] = value end
				end
				return http_req_header
			end
		
			instream:set_timeout(M.HTTP_TIMEOUT, -1)
			while true do
				-- read first line ------------------------------------------------------
				local request = instream:read_line()
				if not request then sktd_cli:close(); return end
				local http_req_method,http_req_path, http_req_params, http_req_version = 
					string.match(request, '^([A-Z]+) ([%/%.%d%w%-_]+)[%?]?(%S*) HTTP/(.+)$')
				
				log('HTTP', 'DETAIL', 'incommig request %s %s %s %s', 
					http_req_method, http_req_path, http_req_params, http_req_version)
				
				-- read header ---------------------------------------------------------
				local http_req_header  = read_incomming_header()
				
				-- handle websockets ----------------------------------------------
				if conf.ws_enable and http_req_header['connection'] and http_req_header['upgrade']
				and http_req_header['connection']:lower():find('upgrade', 1, true) 
				and http_req_header['upgrade']:lower()=='websocket' then
					log('HTTP', 'DETAIL', 'incoming websocket request')
					websocket.handle_websocket_request(sktd_cli,http_req_header) 
					-- this should return only when finished
					return
				end
				
				-- read body ------------------------------------------------------------
				local http_params
				if http_req_method=='POST' then 
					local data = instream:read( tonumber(http_req_header['content-length']) or 0 )
					if not data then sktd_cli:close(); return end
					http_params=parse_params(data)
				else
					http_params=parse_params(http_req_params)
				end
				
				-- prepare response ------------------------------------------------------------
				local http_out_code, http_out_header, response
				--print ('matching', path, path:match('/[^/%.]+$'))
				if http_req_path:match('/[^/%.]+$') then 
					--redirect to path..'/'
					http_out_code, http_out_header = 301, {['location']='http://'..http_req_header['host']..http_req_path..'/'}
				else
					local callback = find_matching_handler(http_req_method, http_req_path)
					if callback then 
						http_out_code, http_out_header, response
              = callback(http_req_method, http_req_path, http_params, http_req_header)
					else
						http_out_code = 404
					end
				end
				populate_cache_control(http_out_header, http_req_path, conf)
				
				
				-- we got no content to return, probably code_out<>200
				if not response then 
					http_out_header, response = backup_response(http_out_code, http_out_header)
				end
				
				-- write response ------------------------------------------------------------
				log('HTTP', 'DETAIL', 'sending response %s', tostring(http_out_code))
				local need_flush
				local done, err, bytes
        
				local response_header = http_util.build_http_header(http_out_code, http_out_header, response, conf)
				done, err, bytes = sktd_cli:send_sync(response_header)
        if done then 
          if type(response) == 'string' then
            --sktd_cli:send_async(response)
            sched.run(function()
              done, err, bytes = sktd_cli:send_sync(response)
              sched.signal(M.EVENT_DATA_TRANSFERRED, http_req_path, http_out_code, done, err, bytes)
            end)
          else --stream
            if not http_out_header["content-length"] then
              need_flush = true
            end
            while true do
              --TODO share streams?
              local s, _ = response:read()
              if not s then break end
              done, err, bytes = sktd_cli:send_sync(s)
              if not done then break end
            end
            sched.signal(M.EVENT_DATA_TRANSFERRED, http_req_path, http_out_code, done, err, bytes)
          end
        else
          sched.signal(M.EVENT_DATA_TRANSFERRED, http_req_path, http_out_code, done, err, bytes)
        end
				
        --handle socket closing when appropiate
				if (http_req_version== '1.0' and http_req_header['connection']~='Keep-Alive')
				or need_flush then 
					sktd_cli:close()
					return
				end
			end
		end, attached)
	end)
end

--- Configuration Table.
-- This table is populated by toribio from the configuration file.
-- @table conf
-- @field ip the ip where the server listens (defaults to '*')
-- @field port the port where the server listens (defaults to 8080)
-- @field max_age allows to set the cache-control header, selectable by file extension.  
-- An example value could be {ico=99999, css=600, html=60}
-- @field ws_enable enable the websocket server component. 

return M
