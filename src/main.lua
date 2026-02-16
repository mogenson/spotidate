import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/timer"
import "CoreLibs/ui"

local gfx = playdate.graphics

local a = import("async.lua")
local secrets = import("secrets.lua")
assert(secrets.client_id)
assert(secrets.client_secret)
assert(secrets.refresh_token)

function playdate.update()
    playdate.timer.updateTimers()
end

local function printf(fmt, ...)
    print(string.format(fmt or "", ...))
end

local function assert(condition, msg)
    if not condition then
        printf("assert error: %s", msg or "nil")
        while true do end
    end
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
        return cb and cb(err or req:read(), req:getResponseStatus())
    end)

    local ok, err = req:query(options.method or "GET", path, options.headers, options.body)
    if not ok then
        printf("network query error: %s", err)
        return cb and cb()
    end
end)

local refresh_access_token = a.sync(function()
    local response, status = a.wait(fetch("https://accounts.spotify.com/api/token", {
        method = "POST",
        headers = "Content-Type: application/x-www-form-urlencoded",
        body = string.format("grant_type=refresh_token&refresh_token=%s&client_id=%s&client_secret=%s",
            secrets.refresh_token, secrets.client_id, secrets.client_secret)
    }
    ))
    if status ~= 200 then
        printf("failed to refresh token, error: %s, status: %d", error, status)
        return
    end

    secrets.access_token = json.decode(response).access_token
end)

local get_currently_playing = a.sync(function()
    if not secrets.access_token then
        print("no access token, requesting one")
        a.wait(refresh_access_token())
    end
    while true do
        local response, status = a.wait(fetch("https://api.spotify.com/v1/me/player/currently-playing", {
            headers = string.format("Authorization: Bearer %s", secrets.access_token)
        }))
        if status == 401 then
            print("access token expired, refreshing then trying agin")
            a.wait(refresh_access_token())
        elseif status == 204 then
            print("spotify is not currently playing any track")
            return nil
        elseif status == 200 then
            -- TODO return structured song, artist, image_url
            local content = json.decode(response)
            printTable(content)
            return content
        else
            printf("error fetching currently playing track: %s", response)
            return nil
        end
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

    print("request network access")
    a.wait(dispatch(playdate.network.http.requestAccess))

    print("press A for Spotify test")
    a.wait(input("AButtonDown"))

    for i = 0, math.huge do
        printf("tick %d", i)
        a.wait(get_currently_playing())
        a.wait(sleep(10000))
    end
end)

a.run(main())
