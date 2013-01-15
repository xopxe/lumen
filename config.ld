file = {"sched.lua", "mutex.lua", "catalog.lua", "pipes.lua", "stream.lua"
	--, "tasks/nixiorator.lua", "tasks/socketeer.lua", 
	, "tasks/shell.lua"
	, "tasks/selector.lua"
	, "tasks/proxy.lua"
	, "tasks/http-server.lua"
	, "docs/debug.ldoc"}
project = "Lumen"
description = "A cooperative scheduler for Lua tasks"
format = 'markdown'
examples={'tests/test.lua', 'tests/test-buff.lua', 'tests/test-selector.lua'
	--, 'tests/test-nixiorator.lua', 'tests/test-socketeer.lua'
	, 'tests/test-pipe.lua', 'tests/test-stress.lua'
	, 'tests/test-wait.lua', 'tests/test-mutex.lua', 'tests/test-http-server.lua'}
readme = "README.md"

