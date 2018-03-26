package = "lumen"
version = "2.0-0"
source = {
    url = "git+https://github.com/xopxe/lumen"
}
description = {
    homepage = "https://github.com/xopxe/lumen",
    license = "MIT"
}
dependencies = {
    "lua >= 5.1, <= 5.3",
    "nixio 0.3-1",
    "luasocket 3.0rc1-2"
}
build = {
    type = "builtin",
    modules = {
        lumen = "init.lua",
        [ "lumen.sched" ] = "sched.lua",
        [ "lumen.catalog" ] = "catalog.lua",
        [ "lumen.pipe" ] = "pipe.lua",
        [ "lumen.stream" ] = "stream.lua",
        [ "lumen.mutex" ] = "mutex.lua",
        [ "lumen.log" ] = "log.lua",
        [ "lumen.lib.queue" ] = "lib/queue.lua",
        [ "lumen.lib.queue2" ] = "lib/queue2.lua",
        [ "lumen.lib.queue3" ] = "lib/queue3.lua",
        [ "lumen.lib.idle" ] = "lib/idle.lua",
        [ "lumen.lib.dkjson" ] = "lib/dkjson.lua",
        [ "lumen.lib.bencode" ] = "lib/bencode.lua",
        [ "lumen.lib.compat_env" ] = "lib/compat_env.lua",
        [ "lumen.tasks.proxy" ] = "tasks/proxy.lua",
        [ "lumen.tasks.selector-luasocket" ] = "tasks/selector-luasocket.lua",
        [ "lumen.tasks.selector-nixio" ] = "tasks/selector-nixio.lua",
        [ "lumen.tasks.selector" ] = "tasks/selector.lua",
        [ "lumen.tasks.shell" ] = "tasks/shell.lua",
        [ "lumen.tasks.http-server" ] = "tasks/http-server/init.lua",
        [ "lumen.tasks.http-server.base64" ] = "tasks/http-server/base64.lua",
        [ "lumen.tasks.http-server.http-util" ] = "tasks/http-server/http-util.lua",
        [ "lumen.tasks.http-server.sha1" ] = "tasks/http-server/sha1.lua",
        [ "lumen.tasks.http-server.websocket" ] = "tasks/http-server/websocket.lua",
        [ "lumen.tasks.http-server.websocket.bit" ] = "tasks/http-server/websocket/bit.lua",
        [ "lumen.tasks.http-server.websocket.frame" ] = "tasks/http-server/websocket/frame.lua",
        [ "lumen.tasks.http-server.websocket.handshake" ] = "tasks/http-server/websocket/handshake.lua",
        [ "lumen.tasks.http-server.websocket.sync" ] = "tasks/http-server/websocket/sync.lua"
    },
    copy_directories = {
        "docs",
        "tests",
        "tasks/http-server/www"
    }
}
