--local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]

local log = require 'log'
local http_server = require "tasks/http_server"
local http_util = require 'tasks/http_server/http_util'

local M = {}

M.serve_folder = function (webroot, fileroot)
	http_server.set_request_handler(
		'GET', 
		webroot,
		function(method, path, http_params, http_header)
			path = path:sub(#webroot)
			if path:sub(-1) == '/' then path=path..'index.html' end
			local file, err = io.open(fileroot..path, "r")
			if file then 
				local extension = path:match('%.(%a+)$') or 'other'
			        local mime = http_util.mime_types[extension] or 'text/plain'
				local content = assert(file:read('*all'))
				local response = "HTTP/1.1 200/OK\r\nContent-Type:"..mime.."\r\nContent-Length: "..#content.."\r\n\r\n"..content..'\r\n'
				return response
			else
				print ('Error opening file', err)
				return nil, 404
			end
		end
	)
end

return M
