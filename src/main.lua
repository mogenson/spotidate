import("CoreLibs/graphics")
import("CoreLibs/timer")
import("CoreLibs/ui")
import("CoreLibs/string")

a = import("async")
import("printf")
import("assert")
import("fetch")

local secrets = import("secrets")
local spotify = import("spotify")
local blitline = import("blitline")
local draw = import("draw")

local TITLE = "*Now Playing* %s"

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
    playdate.display.setRefreshRate(10)
    playdate.setAutoLockDisabled(true)

    print("wait for network on")
    local err = a.wait(a.wrap(playdate.network.setEnabled)(true))
    if err then
        printf("network enable error: %s", err)
        return
    end

    draw:splash()
    draw:title(TITLE:format(""))

    print("request network access")
    a.wait(dispatch(playdate.network.http.requestAccess))

    a.wait(spotify:init(secrets))
    blitline:init(secrets)

    -- print("press A for Spotify test")
    -- a.wait(input("AButtonDown"))

    local image_url = "" -- only convert new images

    while true do
        draw:title(TITLE:format("..."))
        print("fetch currently playing track")
        local track = a.wait(spotify:get_currently_playing())
        if track then
            printf("currently playing song: %s", track.song)
            printf("currently playing artist: %s", track.artist)
            draw:song(track.song)
            draw:artist(track.artist)
            draw:album(track.album)
            if image_url ~= track.image then
                image_url = track.image
                printf("converting image: %s", image_url)
                local image_data = a.wait(blitline:convert_image(image_url))
                if not image_data then
                    print("no image data")
                else
                    printf("image data size %d", #image_data)
                    draw:image(image_data)
                end
            end
        else
            print("no currently playing track")
            draw:splash()
        end
        for i = 10, 1, -1 do
            draw:title(TITLE:format(i % 2 == 0 and "." or ""))
            a.wait(sleep(1000)) -- sleep 1 second
        end
    end
end)

a.run(main())
