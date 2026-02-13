import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/timer"
import "CoreLibs/ui"

local gfx = playdate.graphics

local a = import("async.lua")
local secrets = import("secrets.lua")
assert(secrets.user)
assert(secrets.api_key)

local URL <const> = string.format(
    "http://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user=%s&api_key=%s&format=json&limit=1",
    secrets.user, secrets.api_key)

function playdate.update()
    playdate.timer.updateTimers()
end

local function printf(fmt, ...)
    print(string.format(fmt or "", ...))
end

local function assert(condition, msg)
    if not condition then
        printf("assert error: %s", msg or "nil")
        while true do
        end
    end
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

local fetch = a.wrap(function(url, options, cb)
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
        if err then
            printf("network request error: %s", err)
        end

        local status = req:getResponseStatus()
        if status and status > 300 then
            printf("network response status: %d", status)
        end

        return cb and cb(err or req:read())
    end)

    local ok, err = req:query(options.method or "GET", path, options.headers, options.body)
    if not ok then
        printf("network query error: %s", err)
        return cb and cb()
    end
end)

--------------------------------------------------------------
-- PNG decoder (deflate + unfilter) and Floyd-Steinberg dither
--------------------------------------------------------------

local function make_bitreader(data)
    print("make bitreader start")
    local pos = 1
    local bit_pos = 0
    local byte = data:byte(1)
    local r = {}

    function r.bits(n)
        local val = 0
        for i = 0, n - 1 do
            if bit_pos >= 8 then
                pos = pos + 1
                byte = data:byte(pos)
                bit_pos = 0
            end
            if (byte >> bit_pos) & 1 == 1 then
                val = val | (1 << i)
            end
            bit_pos = bit_pos + 1
        end
        return val
    end

    function r.align()
        if bit_pos > 0 then
            bit_pos = 0
            pos = pos + 1
            if pos <= #data then byte = data:byte(pos) end
        end
    end

    print("make bitreader end")
    return r
end

local function build_hufftree(lengths)
    local max_bits = 0
    for i = 1, #lengths do
        if lengths[i] > max_bits then max_bits = lengths[i] end
    end
    if max_bits == 0 then return {}, 0 end

    local count = {}
    for b = 0, max_bits do count[b] = 0 end
    for i = 1, #lengths do
        count[lengths[i]] = count[lengths[i]] + 1
    end

    local next_code = {}
    local code = 0
    for b = 1, max_bits do
        code = (code + count[b - 1]) << 1
        next_code[b] = code
    end

    local tree = {}
    for i = 1, #lengths do
        local len = lengths[i]
        if len > 0 then
            if not tree[len] then tree[len] = {} end
            tree[len][next_code[len]] = i - 1
            next_code[len] = next_code[len] + 1
        end
    end
    return tree, max_bits
end

local function huff_decode(br, tree, max_bits)
    print("huff decode start")
    local code = 0
    for len = 1, max_bits do
        code = (code << 1) | br.bits(1)
        local t = tree[len]
        if t and t[code] ~= nil then return t[code] end
    end
    assert(false, "bad huffman code")
end

local LEN_BASE  = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
    67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
    4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DST_BASE  = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
    9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }

local function inflate(data)
    print("inflate start")
    local br = make_bitreader(data)
    local out = {}
    local n = 0

    repeat
        local bfinal = br.bits(1)
        local btype  = br.bits(2)

        if btype == 0 then
            -- uncompressed block
            br.align()
            local len = br.bits(8) | (br.bits(8) << 8)
            br.bits(16) -- skip NLEN
            for _ = 1, len do
                n = n + 1; out[n] = br.bits(8)
            end
        elseif btype == 1 or btype == 2 then
            local lt, lm, dt, dm

            if btype == 1 then
                -- fixed Huffman tables
                local ll = {}
                for i = 1, 144 do ll[i] = 8 end
                for i = 145, 256 do ll[i] = 9 end
                for i = 257, 280 do ll[i] = 7 end
                for i = 281, 288 do ll[i] = 8 end
                lt, lm = build_hufftree(ll)
                local dl = {}
                for i = 1, 32 do dl[i] = 5 end
                dt, dm = build_hufftree(dl)
            else
                -- dynamic Huffman tables
                local hlit     = br.bits(5) + 257
                local hdist    = br.bits(5) + 1
                local hclen    = br.bits(4) + 4
                local CL_ORDER = { 17, 18, 19, 1, 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16 }
                local cl       = {}
                for i = 1, 19 do cl[i] = 0 end
                for i = 1, hclen do cl[CL_ORDER[i]] = br.bits(3) end
                local ct, cm = build_hufftree(cl)

                local all = {}
                local total = hlit + hdist
                local j = 1
                while j <= total do
                    local sym = huff_decode(br, ct, cm)
                    if sym < 16 then
                        all[j] = sym; j = j + 1
                    elseif sym == 16 then
                        local rep = br.bits(2) + 3
                        local prev = all[j - 1] or 0
                        for _ = 1, rep do
                            all[j] = prev; j = j + 1
                        end
                    elseif sym == 17 then
                        local rep = br.bits(3) + 3
                        for _ = 1, rep do
                            all[j] = 0; j = j + 1
                        end
                    elseif sym == 18 then
                        local rep = br.bits(7) + 11
                        for _ = 1, rep do
                            all[j] = 0; j = j + 1
                        end
                    end
                end

                local ll = {}
                for i = 1, hlit do ll[i] = all[i] or 0 end
                lt, lm = build_hufftree(ll)
                local dl = {}
                for i = 1, hdist do dl[i] = all[hlit + i] or 0 end
                dt, dm = build_hufftree(dl)
            end

            -- decode compressed data
            while true do
                local sym = huff_decode(br, lt, lm)
                if sym < 256 then
                    n = n + 1; out[n] = sym
                elseif sym == 256 then
                    break
                else
                    local li = sym - 256
                    local length = LEN_BASE[li] + br.bits(LEN_EXTRA[li])
                    local di = huff_decode(br, dt, dm) + 1
                    local dist = DST_BASE[di] + br.bits(DST_EXTRA[di])
                    for _ = 1, length do
                        n = n + 1; out[n] = out[n - dist]
                    end
                end
            end
        else
            assert(false, "invalid deflate block type")
        end
    print("bfinal ", bfinal)
    until bfinal == 1

    print("inflate end")
    return out
end

local function read_u32be(s, p)
    local b1, b2, b3, b4 = s:byte(p, p + 3)
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
end

local function decode_png(data)
    assert(data:sub(1, 8) == "\137PNG\r\n\26\n", "not a PNG")

    local pos = 9
    local w, h, bpp
    local idat = {}

    while pos <= #data do
        local len   = read_u32be(data, pos)
        local ctype = data:sub(pos + 4, pos + 7)
        local cdata = data:sub(pos + 8, pos + 7 + len)
        pos         = pos + 12 + len

        if ctype == "IHDR" then
            w = read_u32be(cdata, 1)
            h = read_u32be(cdata, 5)
            local ct = cdata:byte(10)
            if ct == 6 then
                bpp = 4 -- RGBA
            elseif ct == 2 then
                bpp = 3 -- RGB
            elseif ct == 4 then
                bpp = 2 -- Grayscale+Alpha
            elseif ct == 0 then
                bpp = 1 -- Grayscale
            else
                assert(false, "unsupported color type " .. ct)
            end
        elseif ctype == "IDAT" then
            idat[#idat + 1] = cdata
        elseif ctype == "IEND" then
            break
        end
    end
    assert(w and h, "missing IHDR")

    -- strip zlib header (2 bytes; 6 if FDICT flag set)
    local compressed = table.concat(idat)
    local flg = compressed:byte(2)
    local hdr = ((flg & 0x20) ~= 0) and 7 or 3
    local raw = inflate(compressed:sub(hdr))

    -- reconstruct filtered scanlines → grayscale float array
    local stride = w * bpp
    local prev = {}
    for i = 1, stride do prev[i] = 0 end

    local pixels = {}
    local ri = 1

    for y = 0, h - 1 do
        local filt = raw[ri]; ri = ri + 1
        local row = {}

        for x = 1, stride do
            local v          = raw[ri]; ri = ri + 1
            local left       = x > bpp and row[x - bpp] or 0
            local above      = prev[x]
            local upper_left = x > bpp and prev[x - bpp] or 0

            if filt == 0 then
                row[x] = v
            elseif filt == 1 then
                row[x] = (v + left) & 0xFF
            elseif filt == 2 then
                row[x] = (v + above) & 0xFF
            elseif filt == 3 then
                row[x] = (v + ((left + above) >> 1)) & 0xFF
            elseif filt == 4 then
                local p = left + above - upper_left
                local pa = math.abs(p - left)
                local pb = math.abs(p - above)
                local pc = math.abs(p - upper_left)
                local pr = (pa <= pb and pa <= pc) and left
                    or (pb <= pc) and above
                    or upper_left
                row[x] = (v + pr) & 0xFF
            end
        end

        -- extract RGBA → luminance, alpha-blend over white
        for x = 0, w - 1 do
            local i = x * bpp
            local r, g, b, alpha
            if bpp == 4 then
                r, g, b, alpha = row[i + 1], row[i + 2], row[i + 3], row[i + 4]
            elseif bpp == 3 then
                r, g, b, alpha = row[i + 1], row[i + 2], row[i + 3], 255
            elseif bpp == 2 then
                r, g, b, alpha = row[i + 1], row[i + 1], row[i + 1], row[i + 2]
            else
                r, g, b, alpha = row[i + 1], row[i + 1], row[i + 1], 255
            end
            local gray = 0.299 * r + 0.587 * g + 0.114 * b
            gray = gray * alpha / 255 + 255 * (1 - alpha / 255)
            pixels[y * w + x + 1] = gray
        end

        prev = row
    end

    return pixels, w, h
end

local function dither_floyd_steinberg(pixels, w, h)
    local bw = {}
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local idx = y * w + x + 1
            local old = pixels[idx]
            local new = old < 128 and 0 or 255
            bw[idx] = (new == 0)
            local err = old - new
            if x + 1 < w then
                pixels[idx + 1] = pixels[idx + 1] + err * 7 / 16
            end
            if y + 1 < h then
                if x > 0 then
                    pixels[idx + w - 1] = pixels[idx + w - 1] + err * 3 / 16
                end
                pixels[idx + w] = pixels[idx + w] + err * 5 / 16
                if x + 1 < w then
                    pixels[idx + w + 1] = pixels[idx + w + 1] + err * 1 / 16
                end
            end
        end
    end
    return bw -- true = black, false = white
end

--------------------------------------------------------------

local function show_image(img_url)
    printf("img url: %s", img_url)
    local img_data = a.wait(fetch(img_url))
    if not img_data then
        printf("failed to fetch image data")
        return
    end
    printf("img data len %d", #img_data)

    local pixels, w, h = decode_png(img_data)
    printf("decoded %dx%d image", w, h)

    local bw = dither_floyd_steinberg(pixels, w, h)

    local bitmap = gfx.image.new(w, h, gfx.kColorWhite)
    gfx.pushContext(bitmap)
    gfx.setColor(gfx.kColorBlack)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            if bw[y * w + x + 1] then
                gfx.fillRect(x, y, 1, 1)
            end
        end
    end
    gfx.popContext()

    bitmap:draw(0, 0)
end

-- main async function
local main = a.sync(function()
    playdate.display.setRefreshRate(10)

    print("wait for network on")
    local err = a.wait(a.wrap(playdate.network.setEnabled)(true))
    if err then
        printf("network enable error: %s", err)
        return
    end

    printf("request network access")
    a.wait(dispatch(playdate.network.http.requestAccess))

    print("press A for last.fm test")
    a.wait(input("AButtonDown"))

    local data = a.wait(fetch(URL))
    if data then
        data = json.decode(data)
        printTable(data)
        for _, img in ipairs(data.recenttracks.track[1].image) do
            if img.size == "small" then
                show_image(img["#text"])
                break
            end
        end
        printf("img url %s", img)
    else
        print("no data from last.fm")
    end

    for i = 0, math.huge do
        printf("tick %d", i)
        a.wait(sleep(1000))
    end
end)

a.run(main())
