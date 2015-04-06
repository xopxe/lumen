local lumen = require'lumen'

local log 				= lumen.log
local sched 			= lumen.sched
local streams			= lumen.stream

local nixio = require 'nixio'


--local nixiorator = require 'lumen.tasks/nixiorator'
require 'nixio.util'

local floor = math.floor
local weak_key = { __mode = 'k' }

local CHUNK_SIZE = 1480 -- 65536 --8192

-- pipe for async writing
local write_streams = setmetatable({}, weak_key)
local outstanding_data = setmetatable({}, weak_key)

-- streams for incomming data
local read_streams = setmetatable({}, weak_key)

local unpack = unpack or table.unpack

local M = {}

-------------------
-- replace sched's default get_time and idle with nixio's
sched.get_time = function()
  local sec, usec = nixio.gettimeofday()
  return sec + usec/1000000
end
sched.idle = function (t)
  local sec = floor(t)
  local nsec = (t-sec)*1000000000
  nixio.nanosleep(sec, nsec)
end

local normalize_pattern = function( pattern)
  if pattern=='*l' or pattern=='line' then
    return 'line'
  end
  if tonumber(pattern) and tonumber(pattern)>0 then
    return pattern
  end
  if not pattern or pattern == '*a' 
  or (tonumber(pattern) and tonumber(pattern)<=0) then
    return nil
  end
  log('SELECTOR', 'WARN', 'Could not normalize pattern "%s"', tostring(pattern))
end

local init_sktd = function(sktdesc)
  sktdesc.send_sync = M.send_sync
  sktdesc.send = M.send
  sktdesc.send_async = M.send_async
  sktdesc.getsockname = M.getsockname
  sktdesc.getpeername = M.getpeername
  sktdesc.close = M.close
  return sktdesc
end

local pollt={}
local unregister = function (fd)
  for k, v in ipairs(pollt) do
    if fd==v.fd then
      table.remove(pollt,k)
      return
    end
  end
end
local function handle_incomming(sktd, data)
  if sktd.handler then 
    local ok, errcall = pcall(sktd.handler, sktd, data) 
    if not ok then
      log('SELECTOR', 'ERROR', 'Handler died with "%s"', tostring(errcall))
      sktd:close()
    elseif errcall==false then 
      log('SELECTOR', 'DETAIL', 'Handler finished connection')
      sktd:close()
    end
  elseif read_streams[sktd] then
    read_streams[sktd]:write(data)
  else
    sched.signal(sktd.events.data, data)
  end
end
local function handle_incomming_error(sktd, err)
  err = err or 'fd closed'
  if sktd.handler then 
    local ok, errcall = pcall(sktd.handler,sktd, nil, err) 
    if not ok then
      log('SELECTOR', 'ERROR', 'Handler died with "%s"', tostring(errcall))
    end
  elseif read_streams[sktd] then
    read_streams[sktd]:write(nil, err)
  else
    sched.signal(sktd.events.data, nil, err)
  end
end

local register_client = function (sktd)
  local function client_handler(polle)
    local ok, data, code, msg
    repeat
      --if polle.do_not_read then code=999; break end
      ok,data,code,msg=pcall(polle.it)
      if ok and data then
        local block = polle.block
        if not block or block=='line' or block == #data then
          handle_incomming(sktd, data)
        elseif type(block) == 'number' and block > #data then
          polle.readbuff = (polle.readbuff or '') .. data
          data = polle.readbuff
          if block==#data then
            polle.readbuff = nil
            handle_incomming(sktd, data)
          end
        end
      end
    until not ok or not data
    if code~=11 then
      sktd:close()
      handle_incomming_error(sktd, code)
      return
    end
  end
  local polle={
    fd=sktd.fd,
    events=nixio.poll_flags("in", "pri"), --, "out"),
    block=sktd.pattern,
    handler=client_handler,
    sktd=sktd,
  }
  if polle.block=='line' then
    polle.it=polle.fd:linesource()
  else
    polle.it=polle.fd:blocksource(polle.block)
  end
  polle.fd:setblocking(false)
  sktd.polle=polle
  if type (sktd.handler) == 'table' then --is a stream
    read_streams[sktd] = sktd.handler
    sktd.handler = nil
  end
  pollt[#pollt+1]=polle
end
local register_server = function (sktd) --, block, backlog)
  local function accept_handler(polle)
    local skt, host, port = polle.fd:accept()
    local skt_table_client = {
      fd=skt,
      task=sktd.task,
      events={data=skt},
      pattern=sktd.pattern,
    }
    local insktd = init_sktd(skt_table_client)
    if sktd.handler=='stream' then
      local s = streams.new()
      insktd.handler = s
      insktd.stream = s
    else
      insktd.handler = sktd.handler
    end
    sched.signal(sktd.events.accepted, insktd)
    register_client(insktd)
  end
  local polle={
    fd=sktd.fd,
    sktd=sktd,
    events=nixio.poll_flags("in"),
    --block=normalize_pattern(sktd.pattern) or 8192,
    handler=accept_handler
  }
  polle.fd:listen(sktd.backlog or 32)
  pollt[#pollt+1]=polle
  sktd.polle=polle
end
local function send_from_pipe (sktd)
  local out_data = outstanding_data[sktd]
  local skt=sktd.fd
  if out_data then 
    local data, next_pos = out_data.data, out_data.last
    
    local blocksize = CHUNK_SIZE
    if blocksize>#data-next_pos then blocksize=#data-blocksize end
    local written, errwrite =skt:write(data, next_pos, blocksize )
    if not written and errwrite~=11 then --error, is not EAGAIN
      handle_incomming_error(sktd, 'error writing:'..tostring(errwrite))
      sktd:close()
      return
    end
    
    local last = next_pos + (written or 0)
    if last == #data then
      -- all the oustanding data sent
      outstanding_data[sktd] = nil
    else
      outstanding_data[sktd].last = last
    end
  else
    --local piped = assert(write_pipes[skt] , "socket not registered?")
    local streamd = write_streams[sktd] ; if not streamd then return end
    if streamd.len>0 then 
      local data, err = streamd:read()
      
      local blocksize = CHUNK_SIZE
      if blocksize>#data then blocksize=#data-blocksize end
      local written, errwrite =skt:write(data, 0, blocksize )
      if not written and errwrite~=11 then --not EAGAIN
        handle_incomming_error(sktd, 'error writing:'..tostring(errwrite))
        sktd:close()
        sched.signal(sktd.events.async_finished, false)
        return
      end
      
      written=written or 0
      if written < #data then
        outstanding_data[sktd] = {data=data,last=written}
      end
    else
      --emptied the outgoing pipe, stop selecting to write
      sktd.polle.events=nixio.poll_flags("in", "pri")
      sched.signal(sktd.events.async_finished, true)
    end
  end
end
local step = function (timeout)
  timeout=timeout or -1
  local stat= nixio.poll(pollt, floor(timeout*1000))
  if stat and tonumber(stat) > 0 then
    for _, polle in ipairs(pollt) do
      local revents = polle.revents 
      if revents and revents ~= 0 then
        local mode = nixio.poll_flags(revents)
        if mode['out'] then 
          send_from_pipe(polle.sktd)
        end
        if mode['in'] or mode ['hup'] or mode['pri'] then
          polle:handler() 
        end
      end
    end
  end

end
-------------------

M.init = function(conf)
  conf=conf or {}

  --M.nixiorator=nixiorator
  M.new_tcp_server = function(locaddr, locport, pattern, handler)
    --address, port, pattern, backlog)
    if locaddr=='*' then locaddr = nil end
    local sktd=init_sktd({
      fd = nixio.bind(locaddr, locport, 'inet', 'stream'),
      handler = handler,
      pattern = normalize_pattern(pattern),
    })
    sktd.events = {accepted=sktd.fd }
    if sktd.pattern=='*l' and handler == 'stream' then sktd.pattern=nil end
    register_server(sktd)
    return sktd
  end
  M.new_tcp_client = function(address, port, locaddr, locport, pattern, handler)
    if locaddr=='*' then locaddr = nil end
    local sktd=init_sktd({
      fd = nixio.bind(locaddr, locport or 0, 'inet', 'stream'),
      pattern=normalize_pattern(pattern),
      handler = handler,
    })
    local ok, _, errmsg = sktd.fd:connect(address, port)
    if not ok then return nil, errmsg end
    sktd.events = {data=sktd.fd, async_finished={}}
    if sktd.pattern=='*l' and handler == 'stream' then sktd.pattern=nil end
    register_client(sktd)
    return sktd
  end
  M.new_udp = function( address, port, locaddr, locport, pattern, handler)
    if locaddr=='*' then locaddr = nil end
    local sktd=init_sktd({
      fd = nixio.bind(locaddr, locport or 0, 'inet', 'dgram'),
      pattern =  normalize_pattern(pattern),
      handler = handler,
    })
    sktd.events = {data=sktd.fd, async_finished={}}
    if address and port then 
      local ok, _, errmsg = sktd.fd:connect(address, port)
      if not ok then return nil, errmsg end
    end
    register_client(sktd)
    return sktd
  end
  M.new_fd = function ( filename, flags, pattern, handler, stream )
    local sktd=init_sktd({
      flags = flags  or {},
      pattern =  normalize_pattern(pattern),
      handler = handler,
      stream = stream,
    })
    local err, errmsg
    sktd.fd, err, errmsg = nixio.open(filename, nixio.open_flags(unpack(flags)))
    if not sktd.fd then return nil, errmsg end
    sktd.events = {data=sktd.fd, async_finished={}}
    register_client(sktd)
    return sktd
  end
  M.grab_stdout = function ( command, pattern, handler )
    local function run_shell_nixio(command)
      local fdi, fdo = nixio.pipe()
      local pid = nixio.fork()
      if pid > 0 then 
        --parent
        fdo:close()
        return fdi
      else
        --child
        nixio.dup(fdo, nixio.stdout)
        fdi:close()
        fdo:close()
        nixio.exec("/bin/sh", "-c", command) --should not return
      end
    end
    local sktd=init_sktd({
      pattern =  normalize_pattern(pattern),
      handler = handler,
      fd = run_shell_nixio(command),
    })
    if not sktd.fd then return end
    sktd.events = {data=sktd.fd}
    if sktd.pattern=='*l' and handler == 'stream' then sktd.pattern=nil end
    register_client(sktd)
    return sktd
  end
  M.close = function(sktd)
    --sktd.polle.do_not_read = true
    local fd = sktd.fd
    unregister(fd)
    pcall(fd.close, fd)
  end
  M.send_sync = function(sktd, data)
    local start, len, err,done, errmsg=0,0,nil, nil, nil
    local ok
    while true do
      --len, err, errmsg=sktd.fd:write(data,start)
      ok, len, err, errmsg=pcall(sktd.fd.write, sktd.fd, data, start)
      if not ok then 
        sktd:close()
        done, errmsg = nil, 'invalid fd object'
        break
      end
      start=start+(len or 0)
      done = start==#data
      if done or err then
        break
      else
        sched.wait()
      end
    end
    return done, errmsg, start
  end
  M.send = M.send_sync
  M.send_async = function(sktd, data)
    --make sure we're selecting to write
    sktd.polle.events=nixio.poll_flags("in", "pri", "out")
    
    local streamd = write_streams[sktd] 
    
    -- initialize the stream on first send
    if not streamd then
      streamd = streams.new(M.ASYNC_SEND_BUFFER)
      write_streams[sktd] = streamd
    end
    streamd:write(data)
    
    sched.wait()
  end
  M.getsockname = function(sktd)
    return sktd.fd:getsockname()
  end
  M.getpeername = function(sktd)
    return sktd.fd:getpeername()
  end
  
  M.task = sched.run(function ()
    while true do
      local _, t, _ = sched.wait()
      step( t )
    end
  end)
  
  return M
end

return M


