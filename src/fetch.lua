--- Perform an async HTTP request using the Playdate network API.
--- Parses the URL, opens a connection, and invokes cb with (body, status).
---@param url string The full URL to fetch (http or https)
---@param options? {method?: string, headers?: string|string[]|table<string,string>, body?: string} Request options
---@param cb? fun(body?: string, status?: integer) Callback with response body and HTTP status
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
        local err = req:getError()
        if err then printf("network request error: %s", err) end
        return cb and cb(err or req:read(math.huge), req:getResponseStatus())
    end)

    local ok, err = req:query(options.method or "GET", path, options.headers, options.body)
    if not ok then
        printf("network query error: %s", err)
        return cb and cb()
    end
end)

return fetch
