# Lumen: Lua Multitasking Environment.

"A nice generic framework to develop complex, portable concurrent applications 
in Lua." 

## Introduction

Lumen is a very simple environment for coroutine based multitasking. Consists of a scheduler, and that's it.
The API was inspired by a brief description of [Sierra's scheduler](https://github.com/SierraWireless/luasched/).
Lumen has no external dependencies nor C code, and runs on unmodified Lua (works with Lua 5.1, 5.2 and LuaJIT).
Tasks that interface with LuaSocket and nixio for socket and async file I/O support are provided.

WARNING: Lumen is under heavy development, and API changes happen rather 
frequently, as other weird breakages.

## Tasks

Tasks can emit signals, and block waiting for them, and that's it.

- A signal can be of any type, and carry any parameters
- A task can wait on several signals, with a timeout.
- Signals can be buffered; this helps avoid losing signals when waiting signals in a loop.
- Tasks can register a name, and query for tasks by name.
- Tasks also can wait for a given name to get registered.

## Pipes

There are also named pipes, for intertask communications. 

- Similar to signals, but writers can get blocked too (when pipe gets full).
- Synchronous and asynchronous (with a timeout) modes supported.
- Multiple readers and writers per pipe supported. 
- For when no signal can get lost!

## How does it look?

Here is a small program, with two tasks: one emits ten numbered signals, 
one second apart. Another tasks receives those signals and prints them.

```lua
local sched=require 'sched'

-- task emits signals
local emitter_task = sched.run(function()
	for i = 1, 10 do
		sched.signal('an_event', i)
		sched.sleep(1)
	end
end)

-- task receives signals
sched.run(function()
	local waitd = {emitter=emitter_task, events={'an_event'}}
	while true do
		local ev, data = sched.wait(waitd)
		print (ev, data)
	end
end)

sched.go()
```

## How to try it out?

This example has a few tasks exchanging messages, showing off basic 
functionality:

    lua test.lua

If you want to see LuaSocket integration working, try:

    lua test-socketeer.lua

If you want to see TCP, UDP and async file I/O running, and have nixio 
installed, and in Linux, you can try (root needed as it reads from 
/dev/input/mice):

    sudo lua test-nixiorator.lua

To see how buffers and pipes work and what they are for, try:

    lua test-buff.lua
    lua test-pipe.lua

## License

Same as Lua, see COPYRIGHT.

## Who?

Copyright (C) 2012 Jorge Visca, jvisca@fing.edu.uy

