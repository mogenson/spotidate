import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/timer"
import "CoreLibs/ui"

local a = import("async.lua")

function playdate.update()
    playdate.timer.updateTimers()
end

local function printf(fmt, ...)
    print(string.format(fmt or "", ...))
end

-- async functions
local sleep = a.wrap(playdate.timer.new)

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
    print("wait for network")
    local err = a.wait(a.wrap(playdate.network.setEnabled)(true))
    if err then
        printf("network enable error: %s", err)
        return
    end

    print("press A for spotify test")
    a.wait(input("AButtonDown"))

    local data = a.wait(fetch("https://api.spotify.com/v1/me/top/tracks?time_range=long_term&limit=5",
        {
            headers = {
                Authorization =
                "Bearer BQCf1r2gKu5IuF3f_lj3GzxIr9A3iVi5NPbVOWWIosCEvNBCdCzMneAkDGG_nrxJVc6-ORaGaGhBJ2OtJi2bTry0kGZXuJoMCH3UIHd0tzSpQ3oSHinMMV-zs8Xg5WPkkOQm1a1T21F131V6A6hsSa7uTOmm9JtyPohMeug2_2GyGULZenDkyP3JR7SlMZAa7bi2dKroywtYZSCYmBQUGyJ1ohvIAfH3mtlxaAkaMckpsW8X6d9qhMvSkobNY2Afi8sxaUHA3Io0wUv79nGkqz56_KqRuz9dE578jU3MekqIWg",
            }
        }))
    if data then
        printTable(json.decode(data))
    else
        print("no data from spotify")
    end

    print("press A for HTTP GET test")
    a.wait(input("AButtonDown"))

    local data = a.wait(fetch("https://httpbin.org/get"))
    if data then
        printTable(json.decode(data))
    end

    print("press A for HTTP POST test")
    a.wait(input("AButtonDown"))

    local data = a.wait(fetch("https://httpbin.org/post", {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = json.encode({
            username = "admin",
            password = "admin"
        })
    }))
    if data then
        printTable(json.decode(data))
    end

    for i = 0, math.huge do
        printf("tick %d", i)
        a.wait(sleep(1000))
    end
end)

a.run(main())
