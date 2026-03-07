---@class Blitline
---@field app_id string? Blitline application ID
---@field init fun(self: Blitline, secrets: Secrets) Initialize with API credentials
---@field convert_image fun(self: Blitline, url: string): fun(cb: function) Convert a remote image to a 1-bit dithered BMP via the Blitline API

return {
    app_id = nil,

    --- Initialize the Blitline client with API credentials from secrets.
    ---@param self Blitline
    ---@param secrets Secrets
    init = function(self, secrets)
        self.app_id = assert(secrets.app_id)
    end,

    --- Submit an image conversion job to Blitline, wait for it to finish,
    --- and return the resulting 1-bit dithered BMP data.
    ---@param self Blitline
    ---@param url string URL of the source image to convert
    ---@return string? bmp Raw BMP data, or nil on failure
    convert_image = a.sync(function(self, url)
        local body = string.format(
            '{"application_id":"%s","src":"%s","functions":[{"name":"resize_to_fill","params":{"width":200,"height":200},"functions":[{"name":"convert_command","params":{"-dither":"FloydSteinberg","-monochrome":"","-colors":"2"},"save":{"image_identifier":"%s","extension":".bmp"}}]}]}',
            self.app_id, url, playdate.string.UUID(16))

        local response, status = a.wait(fetch("http://api.blitline.com/job", {
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Connection"]   = "close"
            },
            body = body,
        }))

        if status ~= 200 then
            printf("failed to submit image conversion job, error: %s, status: %d", response, status)
            return nil
        end

        local content = json.decode(response)
        local job_id = content.results.job_id

        -- this blocks until the conversion is complete
        a.wait(fetch(string.format("http://cache.blitline.com/listen/%s", job_id)))

        local result = content.results.images[1].s3_url
        printf("fetching image data from s3 url: %s", result)
        return a.wait(fetch(result))
    end)
}
