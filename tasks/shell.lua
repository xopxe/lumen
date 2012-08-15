local sched = require 'sched'
local catalog = require 'catalog'
local nixiorator = require 'tasks/nixiorator'
local pipes = require 'pipes'
local nixio = require 'nixio'

local M = {}

local function loadbuffer (buffer, name, destroy)
	local remove = table.remove
	local function dest_reader() 
		local ret = remove (buffer, 1)
		if ret then return ret..' ' end
	end
	local i = 0
	local function keep_reader() 
		i=i+1; 
		if buffer[i] then return buffer[i]..' '  end
	end
	return load (destroy and dest_reader or keep_reader, name)
end

local function handle_sheellbuffer ( shell )
	local background, pretty

	-- Parse first special character --
	local special_char, special_line = shell.lines[1] :match "^%s*([&=:])(.*)"
	local original1st = shell.lines[1]
	if special_char == '=' then -- print expression value
		shell.lines[1] = "return " .. special_line
	elseif special_char == '&' then -- Execute in //
		background = true
		shell.lines[1] = special_line
	elseif special_char == ':' then -- Use pretty printer to output the results
		pretty = true
		shell.lines[1] = "return " .. special_line
	end

	local code, msg = loadbuffer(shell.lines, "@shell")
	if not code then
		if msg:match "<eof>" then -- incomplete
			shell.lines[1] = original1st
			shell.pipe_out:write(shell.prompt_more, nil)
		else -- compile error
			shell.lines = {} 
			shell.pipe_out:write(shell.prompt_ready, "Compilation error: "..msg)
		end
	else -- compiled succesfully
		shell.lines = {}

		local prettifier
		if pretty then  prettifier = function(v)
				if type(v) ~='table' then 
					return tostring(v)
				else
					local s= 'table: {\r\n'
					for k, v in pairs(v) do
						s=s..'\t'..tostring(k)..' = '..tostring(v)..'\r\n'
					end
					return s..'}'
				end
			end
		else prettifier = tostring
		end
		
		local function printer(...)
			if select('#', ...) == 0 then 
				return nil
			else
				local r = '= '..prettifier(select(1, ...))
				for i=2, select('#', ...) do
					local s=prettifier(select(i, ...))
					r=r..'\t'..s
				end
				return r
			end
		end
		
		setfenv(code, shell.env)
		local task_command = sched.new_task(code)
		task_command:set_as_attached()
		local waitd_command = sched.new_waitd({emitter=task_command, buff_len=1, events={sched.EVENT_DIE}})
		task_command:run()
		if background then -- create task that will push into out pipe
			shell.pipe_out:write(shell.prompt_ready, 'In background: '..tostring(task_command))
			sched.sigrun(waitd_command, function(_,_,okrun, ...) 
				sched.running_task:set_as_attached()
				if okrun then
					shell.pipe_out:write(nil, 'Background finished: '..tostring(task_command))
					shell.pipe_out:write(nil, printer(...))
				else
					shell.pipe_out:write(nil, 'Background killed: '..tostring(task_command))
					shell.pipe_out:write(nil, 'Error: '.. tostring(...))
				end
			end)
		else -- wait until command finishes
			local function read_signal(_,_,okrun, ...)
				if okrun then
					shell.pipe_out:write(shell.prompt_ready, printer(...))
				else
					shell.pipe_out:write(shell.prompt_ready, 'Error: '.. tostring(...))
				end
			end
			read_signal(sched.wait(waitd_command))
		end
	end
end

local function new_shell()
	-- prepare environment
	local shell = {
		prompt_ready = '> ',
		prompt_more = '+ ',
		banner = 'Welcome to Toribio Shell',
		env={},
		lines = {},
		pipe_in = pipes.new({}, 100),
		pipe_out = pipes.new({}, 100),
		handle_sheellbuffer = handle_sheellbuffer
	}
	for k, v in pairs (M.shell_env) do shell.env[k] = v end
	shell.env.print = function(...)
		local args = table.pack(...)
		local t= {}
		for k = 1, args.n do table.insert(t, tostring(args[k])) end
		shell.pipe_out:write(nil, table.concat(t, '\t')..'\r\n')
	end
	shell.task=sched.new_task(function()
		shell.pipe_out:write(shell.prompt_ready, shell.banner)
		while true do
			local command, data = shell.pipe_in:read()
			if command == 'line' then
				shell.lines[#shell.lines+1] = data
				shell:handle_sheellbuffer()
			end
		end
	end):set_as_attached():run()
	return shell
end

M.init = function(ip, port)
	M.task = sched.run( function()
		catalog.register("shell-accepter")
		local tcprecv = assert(nixio.bind(ip or "*", port or 2012, 'inet', 'stream'))
		nixiorator.register_server(tcprecv, 'line')
		local waitd_accept={emitter=nixiorator.task, events={tcprecv}}
		
		sched.sigrun(waitd_accept, function (_,_, msg, skt)
			print ("#", os.time(), msg, skt )
			if msg=='accepted' then
				local shell = new_shell() 

				local function print_pipe_out()
					repeat
						local prompt, out = shell.pipe_out:read()
						if out then 
							skt:writeall(tostring(out)..'\r\n')
						end
						if prompt then
							skt:writeall(prompt)
						end
					until shell.pipe_out:len() == 0
				end
				
				print_pipe_out()

				local waitd_skt = {emitter=nixiorator.task, events={skt}}
				sched.sigrun(waitd_skt, function(_,  _, data, err )
					if not data then 
						return nil, err 
					end
					shell.pipe_in:write('line', data)
					print_pipe_out()
				end)
			end
		end)
	end)
end

M.shell_env = {
	sched = sched, 
}
for k, v in pairs(_G) do M.shell_env [k] = v end

return M