local mime_types = {
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

local build_http_header = function(status, header, response)
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

local parse_url = function(url)
  local protocol,host = url:match('^(%w+)://([^:/]+)')
  local port,uri = url:match('.+//[^:/]+:?(%d*)(.*)')
  if port and port ~= '' then
    port = tonumber(port)
  elseif protocol == 'ws' then
    port = 80
  end
  if not uri or uri == '' then
    uri = '/'
  end
  if not protocol or not host or not port or not uri then
    error('Invalid URL:'..url)
  end
  return protocol,host,port,uri
end

return {
	parse_url=parse_url,
	build_http_header=build_http_header,
	http_error_code=http_error_code,
	mime_types=mime_types
}


