# Lumen: Lua Multitasking Environment.

"A nice generic framework to develop complex, portable concurrent applications 
in Lua." 

## Introduction

Lumen is a very simple environment for coroutine based multitasking. Consists of a scheduler, and that's it.
The API was inspired by a brief description of [Sierra's scheduler](https://github.com/SierraWireless/luasched/).
Lumen has no external dependencies nor C code, and runs on unmodified Lua (works with Lua 5.1, 5.2 and LuaJIT).
Tasks that interface with LuaSocket and nixio for socket and async file I/O support are provided.

Lumen's API reference is available in the `docs/` directory, or [online](https://www.fing.edu.uy/~jvisca/lumen_api/).


## How does it look?

Here is a small program, with two tasks: one emits ten numbered signals, 
one second apart. Another tasks receives those signals and prints them.

```lua
    local sched=require 'lumen.sched'

    -- task receives signals
    sched.run(function()
    	local waitd = {'an_event'}
    	while true do
    		local _, data = sched.wait(waitd)
    		print(data)
    	end
    end)
    
    -- task emits signals
    sched.run(function()
    	for i = 1, 10 do
    		sched.signal('an_event', i)
    		sched.sleep(1)
    	end
    end)
        
    sched.loop()
```

## Tasks

Tasks can emit signals, and block waiting for them, and that's it.

- A signal can be of any type, and carry any parameters
- A task can wait on several signals, with an optional timeout.
- Signals can be buffered; this helps avoid losing signals when waiting signals in a loop.
- There is an catalog that can be used to simplify sharing data between tasks.


## Pipes & Streams

There are also pipes and streams, for intertask communications. 

- Unlike with plain signals, writers can get blocked too (when pipe or stream gets full).
- Synchronous and asynchronous (with a timeout) modes supported.
- Multiple readers and writers supported. 
- For when no signal can get lost!


## Mutexes

There are cases when you must guarantee that only one task is accessing a piece 
of code at a time. Mutexes provide a mechanism for that. Notice that Lumen, being a 
cooperative scheduler, will never preempt control from a task. That means you only 
may have to resort to mutexes when your critical piece of code relinquish 
control explicitly, for example with a call to sleep, emitting a signal or blocking 
waiting for a signal.


## Goodies

There are a few other useful modules, like an integrated remote Lua shell and a lightweigth 
HTTP server. 


## How to try it out?

There several test programs in the tests/ folder. This example has a 
few tasks exchanging messages, showing off basic functionality:

    lua test.lua


## License

Same as Lua, see COPYRIGHT.


## Who?

Copyright (C) 2012 Jorge Visca, jvisca@fing.edu.uy


## Contributors

Andrew Starks (@andrewstarks)

