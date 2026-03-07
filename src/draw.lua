local X = 210
local Y = 10

return {
    clear = function(x, y, w, h)
        playdate.graphics.setColor(playdate.graphics.kColorWhite)
        playdate.graphics.fillRect(x, y, w, h)
        playdate.graphics.setColor(playdate.graphics.kColorBlack)
    end,

    title = function(self, title)
        self.clear(X + 40, Y, 400 - X + 40, 20)
        playdate.graphics.drawText(title, X + 40, Y)
    end,

    song = function(self, song)
        self.clear(X, Y + 50, 400 - X, 20)
        playdate.graphics.drawText(song, X, Y + 50)
    end,

    artist = function(self, artist)
        self.clear(X, Y + 100, 400 - X, 20)
        playdate.graphics.drawText(artist, X, Y + 100)
    end,

    album = function(self, album)
        self.clear(X, Y + 150, 400 - X, 20)
        playdate.graphics.drawText(album, X, Y + 150)
    end,

    splash = function(self)
        local img = playdate.graphics.image.new("assets/splash")
        self.clear(0, 0, 200, 200)
        assert(img):draw(0, 0)

        playdate.graphics.drawText("*Song:*", X, Y + 30)
        self:song("Unknown Song")

        playdate.graphics.drawText("*Artist:*", X, Y + 80)
        self:artist("Unknown Artist")

        playdate.graphics.drawText("*Album:*", X, Y + 130)
        self:album("Unknown Album")
    end,

    image = function(_, bmp)
        -- read a little-endian u32 at 1-indexed position
        local function u32(pos)
            local b1, b2, b3, b4 = string.byte(bmp, pos, pos + 3)
            return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        end

        -- read a signed little-endian i32 (BMP height can be negative)
        local function s32(pos)
            local v = u32(pos)
            return v >= 0x80000000 and v - 0x100000000 or v
        end

        -- BMP header fields (1-indexed: file offset + 1)
        local data_offset = u32(11) -- pixel data start
        local dib_size = u32(15)    -- DIB header size
        local width = u32(19)       -- image width
        local raw_height = s32(23)  -- image height (negative = top-down)
        local top_down = raw_height < 0
        local height = math.abs(raw_height)
        local row_bytes = math.floor((width + 31) / 32) * 4 -- row stride padded to 4 bytes

        -- color table starts after DIB header (1-indexed: 14 + dib_size + 1)
        local ct = 15 + dib_size
        local c0 = string.byte(bmp, ct) + string.byte(bmp, ct + 1) + string.byte(bmp, ct + 2)
        -- if color 0 is dark, bit=0 means black; otherwise bit=1 means black
        local black_bit = c0 < 384 and 0 or 1

        -- create the playdate bitmap image
        local bitmap = playdate.graphics.image.new(width, height, playdate.graphics.kColorWhite)
        playdate.graphics.pushContext(bitmap)
        playdate.graphics.setColor(playdate.graphics.kColorBlack)

        -- bit masks for extracting each bit from a byte (MSB first)
        local masks = { 128, 64, 32, 16, 8, 4, 2, 1 }

        for row = 0, height - 1 do
            local y = top_down and row or (height - 1 - row)
            local base = data_offset + row * row_bytes + 1 -- 1-indexed row start
            local run_start = nil

            for col = 0, width - 1 do
                local mask = masks[col % 8 + 1]
                local byte_val = string.byte(bmp, base + math.floor(col / 8))
                local bit = (byte_val % (mask * 2) >= mask) and 1 or 0

                if bit == black_bit then
                    if not run_start then run_start = col end
                elseif run_start then
                    -- draw the accumulated horizontal run of black pixels
                    playdate.graphics.fillRect(run_start, y, col - run_start, 1)
                    run_start = nil
                end
            end

            if run_start then
                playdate.graphics.fillRect(run_start, y, width - run_start, 1)
            end
        end

        -- end drawing and show the bitmap image on the screen
        playdate.graphics.popContext()
        bitmap:draw(0, 0)
    end
}
