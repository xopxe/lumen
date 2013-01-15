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

local error_page = {
	[404] = "<html><head><title>404 Not Found</title></head><body><h3>404 Not Found</h3><hr><small>Lumen http_server</small></body></html>",
	[500] = "<html><head><title>500 Internal Server Error</title></head><body><h3>500 Internal Server Error</h3><hr><small>Lumen http_server</small></body></html>",
}
M.http_error = {
	[404] = "HTTP/1.1 404 Not Found\r\nContent-Type:text/html\r\nContent-Length: "..#error_page[404].."\r\n\r\n" .. error_page[404],
	[500] = "HTTP/1.1 500 Internal Server Error\r\nContent-Type:text/html\r\nContent-Length: "..#error_page[500].."\r\n\r\n" .. error_page[500],
}
error_page = nil

return M
