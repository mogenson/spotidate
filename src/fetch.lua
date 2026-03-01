fetch = a.wrap(function(url, options, cb)
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
        printf("request complete for %s", path)
        local status = req:getResponseStatus()
        local err = req:getError()
        local response = nil
        if err then
            printf("network request error: %s", err)
        else
            response = req:read()
        end
        req:close()
        req = nil
        return cb and cb(err or response, status)
    end)

    local ok, err = req:query(options.method or "GET", path, options.headers, options.body)
    printf("request made to %s", path)
    if not ok then
        printf("network query error: %s", err)
        return cb and cb()
    end
end)

return fetch
