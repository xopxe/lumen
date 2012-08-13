local sched = require 'sched'
local catalog = require 'catalog'
local nixiorator = require 'tasks/nixiorator'
local pipes = require 'pipes'
local nixio = require 'nixio'

local M = {}

local function loadbuffer (buffer, name, destroy)
	local remove = table.remove
	local function dest_reader() return remove (buffer, 1)..' ' end
	local i = 0
	local function keep_reader() i=i+1; return buffer[i]..' ' end
	return load (destroy and dest_reader or keep_reader, name)
end

local function handle_sheellbuffer ( lines )
	local ok, waitmore, out

	local code, msg = loadbuffer(lines, "@shell")
	--print('2', code, msg or '')
	if not code then 
		if msg:match "<eof>" then -- incomplete
			ok, waitmore, out = false, true, nil
		else -- compile error
			ok, waitmore, out = true, false, "Compilation error: "..msg
		end
	else
		--local task = sched.run_attached(code)
		--local _,_, okrun, ret = sched.wait({emitter=task, events={sched.EVENT_DIE}})
		setfenv(code, M.shell_env)
		local okrun, ret = pcall(code)
		if okrun then
			ok, waitmore, out = true, false, tostring(ret)
		else
			ok, waitmore, out = true, false, 'Error: '.. tostring(ret)
		end
	end
	return ok, waitmore, out
end

local function get_command_processor( pipe_in, pipe_out )
	return function()
		local lines = {}
		local prompt, banner ='> ', nil
		pipe_out.write(prompt, banner)
		while true do
			local command, data = pipe_in.read()
			if command == 'line' then
				lines[#lines+1] = data
				local compiled, waitmore, ret = handle_sheellbuffer(lines)
				if compiled then lines = {} end
				if waitmore then prompt = '+ '  else prompt = '> ' end
				pipe_out.write(prompt, ret)
			end
		end
	end
end

M.init = function(ip, port)
	M.task = sched.run( function()
		catalog.register("shell-accepter")
		local tcprecv = assert(nixio.bind(ip or "*", port or 2012, 'inet', 'stream'))
		nixiorator.register_server(tcprecv, 'line')
		local waitd={emitter=nixiorator.task, events={tcprecv}}
		while true do
			local _,_, msg, skt  = sched.wait(waitd)
			print ("#", os.time(), msg, skt )
			if msg=='accepted' then
				sched.run(function()
					local pipe_in = pipes.new('pipein:'..tostring(skt), 100)
					local pipe_out = pipes.new('pipeout:'..tostring(skt), 100)
					sched.run_attached(get_command_processor( pipe_in, pipe_out ))

					local prompt, out = pipe_out.read() -- will return first prompt
					if out then 
						skt:writeall(out..'\r\n'..out)
					else
						skt:writeall(prompt)
					end

					local waitd_skt = {emitter=nixiorator.task, events={skt}}
					while true do
						local _,  _, data, err = sched.wait(waitd_skt)
						--print('1', data, err or '')
						if not data then return nil, err end
						pipe_in.write('line', data)
						repeat
							prompt, out = pipe_out.read()
							if out then 
								skt:writeall(out..'\r\n'..prompt)
							else
								skt:writeall(prompt)
							end
						until pipe_out.len() == 0
					end
				end)
			end
		end
	
	end)
end

M.shell_env = {
	sched = sched, 
}
for k, v in pairs(_G) do M.shell_env [k] = v end

return M