--local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]

local log = require 'log'
local httpserver = require "tasks/httpserver"

local M = {}

local mime_types = {
    gif = 'image/gif',
    ico = 'image/x-icon',
    png = 'image/png',
    html = 'text/html',
    js = 'text/javascript',
    css = 'text/css',
    other = 'text/plain',
}


M.serve_folder = function (webroot, fileroot)
	httpserver.set_request_handler(
		'GET', 
		webroot,
		function(method, path, http_params, http_header)
			path = path:sub(#webroot)
			if path:sub(-1) == '/' then path=path..'index.html' end
			print ('','',fileroot..path)
			local file, err = io.open(fileroot..path, "r")
			if file then 
				local extension = path:match('%.(%a+)$') or 'other'
			        local mime = mime_types[extension] or 'text/plain'
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
