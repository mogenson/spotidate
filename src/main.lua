import("CoreLibs/graphics")
import("CoreLibs/timer")
import("CoreLibs/ui")
import("CoreLibs/string")

a = import("async")
import("fetch")
import("printf")
import("assert")
import("render")


local secrets = import("secrets")
local spotify = import("spotify")
local blitline = import("blitline")

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
    blitline:init(secrets)

    print("press A for Spotify test")
    a.wait(input("AButtonDown"))

    local image_url = "" -- only convert new images

    for i = 0, math.huge do
        printf("tick %d", i)
        local track = a.wait(spotify:get_currently_playing())
        if track then
            printf("currently playing song: %s", track.song)
            printf("currently playing artist: %s", track.artist)
            if image_url ~= track.image then
                image_url = track.image
                printf("converting image: %s", image_url)
                local image_data = a.wait(blitline:convert_image(image_url))
                if not image_data then
                    print("no image data")
                else
                    printf("image data size %d", #image_data)
                    render(image_data)
                end
            end
        else
            print("no currently playing track")
            -- draw a "not playing" message on screen
        end
        a.wait(sleep(10000))
    end
end)

playdate.display.setRefreshRate(10)
a.run(main())
