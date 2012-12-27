# Lumen: Lua Multitasking Environment.

"A nice generic framework to develop complex, portable concurrent applications 
in Lua." 

## Introduction

Lumen is a very simple environment for coroutine based multitasking. Consists of a scheduler, and that's it.
The API was inspired by a brief description of [Sierra's scheduler](https://github.com/SierraWireless/luasched/).
Lumen has no external dependencies nor C code, and runs on unmodified Lua (works with Lua 5.1, 5.2 and LuaJIT).
Tasks that interface with LuaSocket and nixio for socket and async file I/O support are provided.

Lumen's [API reference](http://xopxe.github.com/Lumen/) is available online.

WARNING: Lumen is under heavy development, and API changes happen rather 
frequently, as other weird breakages.

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
    		local _, _, data = sched.wait(waitd)
    		print (data)
    	end
    end)
    
    sched.go()
```

## Tasks

Tasks can emit signals, and block waiting for them, and that's it.

- A signal can be of any type, and carry any parameters
- A task can wait on several signals, from several emitters, with a timeout.
- Signals can be buffered; this helps avoid losing signals when waiting signals in a loop.
- Tasks can register a name, and query for tasks by name.
- Tasks also can wait for a given name to get registered.

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

## How to try it out?

There several test programs in the tests/ folder. This example has a 
few tasks exchanging messages, showing off basic functionality:

    lua test.lua

You can wait on multiple events, from multiple sources. Check some
possibilities here:

    lua test-wait.lua

If you want to see LuaSocket and nixio integration working for async socket and
file I/O, try:

    lua test-selector.lua

To see how buffers, pipes and mutexes work and what they are for, try:

    lua test-buff.lua
    lua test-pipe.lua
    lua test-mutex.lua

## License

Same as Lua, see COPYRIGHT.

## Who?

Copyright (C) 2012 Jorge Visca, jvisca@fing.edu.uy

