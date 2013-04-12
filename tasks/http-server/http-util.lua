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

M.http_error_code ={
	[101] = 'Switching Protocols',
	[200] = 'OK',
	[301] = 'Moved Permanently',
	[400] = 'Bad Request', 
	[404] = 'Not Found',
	[500] = 'Internal Server Error',
}

return M
