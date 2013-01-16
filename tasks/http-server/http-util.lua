local M = {}

M.mime_types = {
    gif = 'image/gif',
    ico = 'image/x-icon',
    png = 'image/png',
    svg = 'image/svg+xml',
    jpg = 'image/jpeg',
    jpeg = 'image/jpeg',
    html = 'text/html',
    js = 'text/javascript',
    css = 'text/css',
    other = 'text/plain',
}

local http_error_code ={
	[200] = 'OK',
	[301] = 'Moved Permanently', 
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
	
	local header_entries = {}
	for k, v in pairs(header) do
		header_entries[#header_entries+1] = k..": "..v
	end
	
	local header_string = table.concat(header_entries, '\r\n')
	
	--print ('http_string', "HTTP/1.1 "..httpstatus.."\r\n"..header_string.."\r\n\r\n", #content)

	
	local http_string = "HTTP/1.1 "..httpstatus.."\r\n"..header_string.."\r\n\r\n" .. content
	return http_string
end

return M
