import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/timer"
import "CoreLibs/ui"

local a = import("async.lua")
local secrets = import("secrets.lua")
assert(secrets.user)
assert(secrets.api_key)

local URL <const> = string.format(
    "http://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user=%s&api_key=%s&format=json&limit=1",
    secrets.user, secrets.api_key)

function playdate.update()
    playdate.timer.updateTimers()
end

local function printf(fmt, ...)
    print(string.format(fmt or "", ...))
end

-- async functions
local sleep = a.wrap(playdate.timer.new)

local dispatch = a.wrap(function(fn, cb)
    playdate.timer.new(0, function()
        return cb(fn())
    end)
end)

local input = a.wrap(function(name, cb)
    playdate.inputHandlers.push({
        [name] = function(...)
            playdate.inputHandlers.pop()
            return cb and cb(...)
        end
    })
end)

local fetch = a.wrap(function(url, options, cb)
    if cb == nil and type(options) == "function" then cb, options = options, {} end
    local scheme, host, port, path = url:match("^([a-zA-Z][a-zA-Z0-9+.-]*)://([^/:]+):?(%d*)(/?.*)$")
    local ssl = scheme == "https"
    port = port and tonumber(port) or (ssl and 443 or 80)
    path = path ~= "" and path or "/"

    local req = playdate.network.http.new(host, port, ssl)
    if not req then
        print("network connect error: permission denied")
        return cb and cb()
    end

    req:setRequestCompleteCallback(function()
        local err = req:getError()
        if err then
            printf("network request error: %s", err)
        end

        local status = req:getResponseStatus()
        if status and status > 300 then
            printf("network response status: %d", status)
        end

        return cb and cb(err or req:read())
    end)

    local ok, err = req:query(options.method or "GET", path, options.headers, options.body)
    if not ok then
        printf("network query error: %s", err)
        return cb and cb()
    end
end)

-- main async function
local main = a.sync(function()
    playdate.display.setRefreshRate(10)

    print("wait for network on")
    local err = a.wait(a.wrap(playdate.network.setEnabled)(true))
    if err then
        printf("network enable error: %s", err)
        return
    end

    printf("request network access")
    a.wait(dispatch(playdate.network.http.requestAccess))

    print("press A for last.fm test")
    a.wait(input("AButtonDown"))

    local data = a.wait(fetch(URL))
    if data then
        printTable(json.decode(data))
    else
        print("no data from last.fm")
    end

    for i = 0, math.huge do
        printf("tick %d", i)
        a.wait(sleep(1000))
    end
end)

a.run(main())
