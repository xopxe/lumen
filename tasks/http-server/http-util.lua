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
	[101] = 'Switching Protocols',
	[200] = 'OK',
	[301] = 'Moved Permanently',
	[400] = 'Bad Request', 
	[404] = 'Not Found',
	[500] = 'Internal Server Error',
}
M.http_error_code = http_error_code

M.build_http_header = function(status, header, response)
	local httpstatus = tostring(status).." "..http_error_code[status]
	header = header or {}
	
	if not header["content-length"] and type (response) == "string" then 
		header["content-length"] = #response
	end
	if not header["content-type"] then
		header["content-type"] = 'text/plain'
	end

	local header_entries = {"HTTP/1.1 "..httpstatus}
	for k, v in pairs(header or {}) do
		header_entries[#header_entries+1] = k..": "..v
	end
	header_entries[#header_entries+1] = "\r\n"
	local http_string = table.concat(header_entries, '\r\n')
	return http_string
end

return M
