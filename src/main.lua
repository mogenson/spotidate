import("CoreLibs/graphics")
import("CoreLibs/object")
import("CoreLibs/timer")
import("CoreLibs/ui")

playdate.display.setRefreshRate(10)

a = import("async")
import("fetch")
import("printf")
import("assert")

local secrets = import("secrets")
local spotify = import("spotify")

function playdate.update()
    playdate.timer.updateTimers()
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

-- main async function
local main = a.sync(function()
    print("wait for network on")
    local err = a.wait(a.wrap(playdate.network.setEnabled)(true))
    if err then
        printf("network enable error: %s", err)
        return
    end

    print("request network access")
    a.wait(dispatch(playdate.network.http.requestAccess))

    a.wait(spotify:init(secrets))

    print("press A for Spotify test")
    a.wait(input("AButtonDown"))

    for i = 0, math.huge do
        printf("tick %d", i)
        a.wait(spotify:get_currently_playing())
        a.wait(sleep(10000))
    end
end)

a.run(main())
