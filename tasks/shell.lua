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

local function handle_sheellbuffer ( self )
	local background, pretty

	-- Parse first special character --
	local special_char, special_line = self.lines[1] :match "^%s*([&=:])(.*)"
	local original1st = self.lines[1]
	if special_char == '=' then -- print expression value
		self.lines[1] = "return " .. special_line
	elseif special_char == '&' then -- Execute in //
		background = true
		self.lines[1] = special_line
	elseif special_char == ':' then -- Use pretty printer to output the results
		pretty = true
		self.lines[1] = "return " .. special_line
	end

	local code, msg = loadbuffer(self.lines, "@shell")
print('2', code, msg or '')
	if not code then
		if msg:match "<eof>" then -- incomplete
			self.lines[1] = original1st
			self.pipe_out:write(self.prompt_more, nil)
		else -- compile error
			self.lines = {} 
			self.pipe_out:write(self.prompt_ready, "Compilation error: "..msg)
		end
	else
		self.lines = {}

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
		
		setfenv(code, self.env)
		local task_command = sched.new_task(code)
		task_command:set_as_attached()
		local waitd_command = sched.new_waitd({emitter=task_command, buff_len=1, events={sched.EVENT_DIE}})
		task_command:run()
		if background then
			sched.sigrun(waitd_command, function(_,_,okrun, ...) 
				sched.running_task:set_as_attached()
				if okrun then
					self.pipe_out:write(nil, 'Background finished: '..tostring(task_command))
					self.pipe_out:write(nil, printer(...))
				else
					self.pipe_out:write(nil, 'Background killed: '..tostring(task_command))
					self.pipe_out:write(nil, 'Error: '.. tostring(...))
				end
			end)
			self.pipe_out:write(self.prompt_ready, 'In background: '..tostring(task_command))
		else
			local function read_signal(_,_,okrun, ...)
	print('3', okrun, ...)
				if okrun then
					self.pipe_out:write(self.prompt_ready, printer(...))
				else
					self.pipe_out:write(self.prompt_ready, 'Error: '.. tostring(...))
				end
			end
			read_signal(sched.wait(waitd_command))
		end
	end
end

local function get_command_processor( pipe_in, pipe_out )
	return function()
		-- prepare environment
		local shell = {
			prompt_ready = '> ',
			prompt_more = '+ ',
			banner = 'Welcome to Toribio Shell',
			env={},
			lines = {},
			pipe_out = pipe_out,
			handle_sheellbuffer = handle_sheellbuffer
		}
		for k, v in pairs (M.shell_env) do shell.env[k] = v end
		shell.env.print = function(...)
			local args = table.pack(...)
			local t= {}
			for k = 1, args.n do table.insert(t, tostring(args[k])) end
			pipe_out:write(nil, table.concat(t, '\t')..'\r\n')
		end
		
print('generating banner')
		pipe_out:write(shell.prompt_ready, shell.banner)
		while true do
			local command, data = pipe_in:read()
			if command == 'line' then
				shell.lines[#shell.lines+1] = data
				shell:handle_sheellbuffer()
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
					local task_command_processor = sched.new_task(get_command_processor( pipe_in, pipe_out ))
					task_command_processor:set_as_attached():run()

					local prompt, out = pipe_out:read() -- will return first prompt
					if out then 
						skt:writeall(out..'\r\n'..prompt)
					else
						skt:writeall(prompt)
					end

					local waitd_skt = {emitter=nixiorator.task, events={skt}}
					while true do
						local _,  _, data, err = sched.wait(waitd_skt)
print('1', data, err or '')
						if not data then return nil, err end
						pipe_in:write('line', data)
						repeat
							prompt, out = pipe_out:read()
							if out then 
								skt:writeall(tostring(out)..'\r\n')
							end
							if prompt then
								skt:writeall(prompt)
							end
						until pipe_out:len() == 0
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