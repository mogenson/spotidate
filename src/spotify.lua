return {
    access_token = nil,
    client_id = nil,
    client_secret = nil,
    refresh_token = nil,

    init = a.sync(function(self, secrets)
        self.client_id = assert(secrets.client_id)
        self.client_secret = assert(secrets.client_secret)
        self.refresh_token = assert(secrets.refresh_token)
        a.wait(self:refresh_access_token())
    end),

    refresh_access_token = a.sync(function(self)
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

    get_currently_playing = a.sync(function(self)
        while true do
            local response, status = a.wait(fetch("https://api.spotify.com/v1/me/player/currently-playing", {
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
                    image = content.item.album.images[1].url, -- biggest album image
                }
            else
                printf("error fetching currently playing track: %s", response)
                return nil
            end
        end
    end)
}
