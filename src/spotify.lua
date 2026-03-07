local WEB_PLAYER_API = "https://api.spotify.com/v1/me/player/%s"

---@class Track
---@field song string Track name
---@field artist string Primary artist name
---@field album string Album name
---@field image string URL of the largest album cover image

---@class SpotifyClient
---@field access_token string? OAuth access token
---@field client_id string? Spotify app client ID
---@field client_secret string? Spotify app client secret
---@field refresh_token string? OAuth refresh token
---@field init fun(self: SpotifyClient, secrets: Secrets): fun(cb: function) Initialize credentials and fetch an access token
---@field refresh_access_token fun(self: SpotifyClient): fun(cb: function) Refresh the OAuth access token
---@field play fun(self: SpotifyClient): fun(cb: function) Resume playback
---@field pause fun(self: SpotifyClient): fun(cb: function) Pause playback
---@field next fun(self: SpotifyClient): fun(cb: function) Skip to next track
---@field previous fun(self: SpotifyClient): fun(cb: function) Skip to previous track
---@field get_currently_playing fun(self: SpotifyClient): fun(cb: function) Get the currently playing track

return {
    access_token = nil,
    client_id = nil,
    client_secret = nil,
    refresh_token = nil,

    --- Initialize the Spotify client with credentials and refresh the access token.
    ---@param self SpotifyClient
    ---@param secrets Secrets
    init = a.sync(function(self, secrets)
        self.client_id = assert(secrets.client_id)
        self.client_secret = assert(secrets.client_secret)
        self.refresh_token = assert(secrets.refresh_token)
        a.wait(self:refresh_access_token())
    end),

    --- Refresh the OAuth access token using the stored refresh token.
    ---@param self SpotifyClient
    refresh_access_token = a.sync(function(self)
        print("refreshing spotify token")
        local response, status = a.wait(fetch("https://accounts.spotify.com/api/token", {
            method = "POST",
            headers = "Content-Type: application/x-www-form-urlencoded",
            body = string.format("grant_type=refresh_token&refresh_token=%s&client_id=%s&client_secret=%s",
                self.refresh_token, self.client_id, self.client_secret)
        }
        ))
        if status ~= 200 then
            printf("failed to refresh token, error: %s, status: %d", response, status)
            return
        end

        self.access_token = json.decode(response).access_token
    end),

    --- Resume playback on the active Spotify device.
    ---@param self SpotifyClient
    play = a.sync(function(self)
        local response, status = a.wait(fetch(WEB_PLAYER_API:format("play"), {
            method = "PUT",
            headers = {
                string.format("Authorization: Bearer %s", self.access_token),
                "Content-Length: 0"
            }
        }))
        printf("play status: %d", status)
        if status ~= 200 then printf("play response: %s", response) end
    end),

    --- Pause playback on the active Spotify device.
    ---@param self SpotifyClient
    pause = a.sync(function(self)
        local response, status = a.wait(fetch(WEB_PLAYER_API:format("pause"), {
            method = "PUT",
            headers = {
                string.format("Authorization: Bearer %s", self.access_token),
                "Content-Length: 0"
            }
        }))
        printf("pause status: %d", status)
        if status ~= 200 then printf("pause response: %s", response) end
    end),

    --- Skip to the next track on the active Spotify device.
    ---@param self SpotifyClient
    next = a.sync(function(self)
        local response, status = a.wait(fetch(WEB_PLAYER_API:format("next"), {
            method = "POST",
            headers = {
                string.format("Authorization: Bearer %s", self.access_token),
                "Content-Length: 0"
            }
        }))
        printf("next status: %d", status)
        if status ~= 200 then printf("next response: %s", response) end
    end),

    --- Skip to the previous track on the active Spotify device.
    ---@param self SpotifyClient
    previous = a.sync(function(self)
        local response, status = a.wait(fetch(WEB_PLAYER_API:format("previous"), {
            method = "POST",
            headers = {
                string.format("Authorization: Bearer %s", self.access_token),
                "Content-Length: 0"
            }
        }))
        printf("previous status: %d", status)
        if status ~= 200 then printf("previous response: %s", response) end
    end),

    --- Fetch the currently playing track from Spotify. Automatically refreshes
    --- the access token on 401 responses.
    ---@param self SpotifyClient
    ---@return Track? track The currently playing track, or nil if nothing is playing
    get_currently_playing = a.sync(function(self)
        while true do
            local response, status = a.wait(fetch(WEB_PLAYER_API:format("currently-playing"), {
                headers = string.format("Authorization: Bearer %s", self.access_token)
            }))
            if status == 401 then
                print("access token expired, refreshing then trying agin")
                a.wait(self:refresh_access_token())
            elseif status == 204 then
                print("spotify is not currently playing any track")
                return nil
            elseif status == 200 then
                local content = json.decode(response)
                --printTable(content)
                return {
                    song = content.item.name,
                    artist = content.item.artists[1].name,    -- first artist
                    album = content.item.album.name,
                    image = content.item.album.images[1].url, -- biggest album image
                }
            else
                printf("error fetching currently playing track: %s", response)
                return nil
            end
        end
    end)
}
