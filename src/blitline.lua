import("CoreLibs/string")

return {
    app_id = nil,

    init = function(self, secrets)
        self.app_id = assert(secrets.app_id)
    end,

    convert_image = a.sync(function(self, url)
        local body = string.format(
            '{"application_id":"%s","src":"%s","functions":[{"name":"resize_to_fill","params":{"width":200,"height":200},"functions":[{"name":"convert_command","params":{"-dither":"FloydSteinberg","-monochrome":"","-colors":"2"},"save":{"image_identifier":"%s","extension":".bmp"}}]}]}',
            self.app_id, url, playdate.string.UUID(16))

        local response, status = a.wait(fetch("http://api.blitline.com/job", {
            method = "POST",
            headers = "Content-Type: application/json",
            body = body,
        }))

        if status ~= 200 then
            printf("failed to submit image conversion job, error: %s, status: %d", response, status)
            return nil
        end

        local content = json.decode(response)

        local result = content.results.images[1].s3_url
        printf("fetching image data from s3 url: %s", result)
        return a.wait(fetch(result))
    end)
}
