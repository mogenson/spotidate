import("CoreLibs/graphics")
import("CoreLibs/timer")
import("CoreLibs/ui")
import("CoreLibs/string")

a = import("async")
import("printf")
import("assert")
import("fetch")

---@class Secrets
---@field client_id string Spotify app client ID
---@field client_secret string Spotify app client secret
---@field refresh_token string Spotify OAuth refresh token
---@field app_id string Blitline application ID

local secrets = import("secrets") ---@type Secrets
local spotify = import("spotify") ---@type SpotifyClient
local blitline = import("blitline") ---@type Blitline
local draw = import("draw") ---@type Draw

local TITLE = "*Now Playing* %s"
local A_BUTTON = "AButtonDown"
local B_BUTTON = "BButtonDown"
local LEFT_BUTTON = "leftButtonDown"
local RIGHT_BUTTON = "rightButtonDown"
local REFRESH = "refresh"

--- Main update callback; advances all active timers each frame.
function playdate.update()
    playdate.timer.updateTimers()
end

--- Async sleep for the given duration in milliseconds.
---@param duration integer Milliseconds to sleep
---@return fun(cb: function) future A future that resolves after the timer fires
local sleep = a.wrap(playdate.timer.new)

--- Dispatch a synchronous function to run on the next frame and return its result async.
---@param fn function The function to call
---@param cb? function Callback receiving the function's return value
local dispatch = a.wrap(function(fn, cb)
    playdate.timer.new(0, function()
        return cb(fn())
    end)
end)

--- Wait for one of the named input buttons to be pressed and return its name.
---@param names string[] List of input handler names to listen for
---@param cb? fun(name: string) Callback receiving the name of the pressed button
local input = a.wrap(function(names, cb)
    local handlers = {}
    for _, name in ipairs(names) do
        handlers[name] = function()
            playdate.inputHandlers.pop()
            return cb and cb(name)
        end
    end
    playdate.inputHandlers.push(handlers)
end)

--- Poll Spotify for the currently playing song, update the display,
--- and convert album art via Blitline. Loops with a 10-second refresh interval
--- that can be interrupted via the rx channel.
---@param client SpotifyClient The authenticated Spotify client
---@param rx Receiver Channel receiver to listen for refresh signals
local spotify_task = a.sync(function(client, rx)
    blitline:init(secrets)

    local image_url = "" -- only convert new images

    while true do
        draw:title(TITLE:format("..."))
        print("fetch currently playing track")
        local track = a.wait(client:get_currently_playing())
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
            local cmd = a.wait(a.select({ rx:recv(), sleep(1000) }))
            if cmd[1] == REFRESH then break end
        end
    end
end)

--- Handle button presses for playback controls (play, pause, next, previous).
--- Sends a refresh signal via tx after skip actions.
---@param client SpotifyClient The authenticated Spotify client
---@param tx Sender Channel sender to signal the spotify_task to refresh
local button_task = a.sync(function(client, tx)
    local y, w, h = 210, 80, 20
    local lx, rx, bx, ax = 20, 120, 220, 320
    while true do
        playdate.graphics.drawText("⬅️ prev", lx, y)
        playdate.graphics.drawText("➡️ next", rx, y)
        playdate.graphics.drawText("Ⓑ stop", bx, y)
        playdate.graphics.drawText("Ⓐ play", ax, y)

        local button = a.wait(input({
            A_BUTTON,
            B_BUTTON,
            LEFT_BUTTON,
            RIGHT_BUTTON
        }))
        printf("Button pressed: %s", button)
        if button == A_BUTTON then
            draw.clear(ax, y, w, h)
            playdate.graphics.drawText("Ⓐ *play*", ax, y)
            a.wait(client:play())
            draw.clear(ax, y, w, h)
        elseif button == B_BUTTON then
            draw.clear(bx, y, w, h)
            playdate.graphics.drawText("Ⓑ *stop*", bx, y)
            a.wait(client:pause())
            draw.clear(bx, y, w, h)
        elseif button == LEFT_BUTTON then
            draw.clear(lx, y, w, h)
            playdate.graphics.drawText("⬅️ *prev*", lx, y)
            a.wait(client:previous())
            a.wait(tx:send(REFRESH))
            draw.clear(lx, y, w, h)
        elseif button == RIGHT_BUTTON then
            draw.clear(rx, y, w, h)
            playdate.graphics.drawText("➡️ *next*", rx, y)
            a.wait(client:next())
            a.wait(tx:send(REFRESH))
            draw.clear(rx, y, w, h)
        end
    end
end)

--- App entry point. Enables networking, requests access, initializes Spotify,
--- and runs the song-polling and button-handling tasks concurrently.
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

    local tx, rx = a.channel()
    a.wait(a.gather({ spotify_task(spotify, rx), button_task(spotify, tx) }))
end)

a.run(main())
