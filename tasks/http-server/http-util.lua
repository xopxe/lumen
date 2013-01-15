local M = {}

M.mime_types = {
    gif = 'image/gif',
    ico = 'image/x-icon',
    png = 'image/png',
    html = 'text/html',
    js = 'text/javascript',
    css = 'text/css',
    other = 'text/plain',
}

local http_error_code ={
	[200] = 'OK',
	[404] = 'Not Found',
	[500] = 'Internal Server Error',
}

M.build_http = function(status, header, content)
	local httpstatus = tostring(status).." "..http_error_code[status]
	header = header or {}

	if not content then 
		content = "<html><head><title>"..httpstatus.."</title></head><body><h3>"..httpstatus.."</h3><hr><small>Lumen http-server</small></body></html>"
		header["Content-Type"] = 'text/html'
	end
	header["Content-Length"] = #content
	
	for k, v in pairs(header) do
		header[#header+1] = k..": "..v
	end
	
	local header_string = table.concat(header, '\r\n')
	
	local http_string = "HTTP/1.1 "..httpstatus.."\r\n"..header_string.."\r\n\r\n" .. content
	return http_string
end

return M
