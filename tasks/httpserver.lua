local log=require 'log'

local sched = require 'sched'
local selector = require "tasks/selector"
--local stream = require 'stream'

local HTTP_TIMEOUT = 5

local M = {}

local function parse_params(s)
	local params={}
	for k,v in string.gmatch(s, '([%w%%%_%-]+)=?([%w%%%_%-]*)') do
		print('PARAM', k, v)
		params[k]=v
	end
	return params
end


M.init = function(conf)
	conf = conf or  {}
	local ip = conf.ip or '*'
	local port = conf.port or 8080
		
	local tcp_server = selector.new_tcp_server(ip, port, 0, 'stream')
	
	local servertask = sched.new_task( function()
		local waitd_accept={emitter=selector.task, events={tcp_server.events.accepted}}
		print('webserver accepting connections on', tcp_server:getsockname())
		M.task = sched.sigrun(waitd_accept, function (_,_, sktd_cli, instream)
			instream:set_timeout(HTTP_TIMEOUT, -1)
			print ("#", os.time(), sktd_cli )
			while true do
				--read first line
				local request = instream:read_line()
				if not request then sktd_cli:close(); return end
				local method,path, params, version = 
					string.match(request, '^([A-Z]+) ([%/%.%d%w%-_]+)[%?]?(%S*) HTTP/(.+)$')
				print ('HTTP', method,path, params, version)
				local http_header  = {}
				--read header
				while true do
					local line = instream:read_line()
					if not line then sktd_cli:close(); return end
					if line=='' then break end
					local key, value=string.match(line, '^([^:]+): (.*)$')
					print ('HEADER', line, key, value)
					http_header[key] = value
				end
				local content_length = http_header['Content%-Length'] or 0
				
				local data = instream:read(content_length)
				if not data then sktd_cli:close(); return end
				print ('DATA', #data,  data)
				
				local http_params
				if method=='POST' then 
					http_params=parse_params(data)
				else
					http_params=parse_params(params)
				end
				
				local page = '<http><head><title>Toribio</title></head><body><h1>Works!</h1></body></http>'
				local answ = "HTTP/1.1 200/OK\r\nContent-Type:text/html\r\nContent-Length: "..#page.."\r\n\r\n"..page..'\r\n'
				
				print ('ANSW', sktd_cli:send_sync(answ))

				sktd_cli:close()
				
				if version == '1.0' then 
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