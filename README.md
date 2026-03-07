# SpotiDate

A Spotify remote control for the [Playdate](https://play.date) handheld console. View the currently playing track, album art, and control playback — all from the crank-equipped little yellow device.

<img width="487" height="416" alt="playdate-spotify-screenshot" src="https://github.com/user-attachments/assets/0b972620-5e67-4d98-955d-a865e84e02a4" />


## Overview

SpotiDate connects to the Spotify Web API over Wi-Fi to display the currently playing song, artist, album, and a dithered 1-bit album cover image. The D-pad and face buttons provide playback controls: play, pause, skip forward, and skip back.

### Async control flow

Playdate games typically use a callback-driven `playdate.update()` loop with global state to coordinate logic across frames. SpotiDate takes a different approach by using [lua-utils/async.lua](https://github.com/mogenson/lua-utils), a coroutine-based async runtime that lets you write linear, sequential code that reads top-to-bottom:

```lua
local main = a.sync(function()
    a.wait(network_enable())
    a.wait(spotify:init(secrets))
    a.wait(a.gather({ song_poller(), button_handler() }))
end)
```

Under the hood, `a.sync` wraps a function in a coroutine, and `a.wait` yields until a future resolves — but the calling code looks like ordinary blocking code. Network requests, timers, and input all become awaitable futures via `a.wrap`, and `a.gather` / `a.select` provide concurrent task composition. The only thing `playdate.update()` does is tick the timer system; all application logic lives in async tasks.

## Setup

### 1. Create a Spotify app

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and log in.
2. Click **Create App**.
3. Give it a name and description.
4. Set the **Redirect URI** to `http://127.0.0.1:8000/callback`.
5. Under **APIs used**, select **Web API**.
6. Save and note your **Client ID** and **Client Secret** from the app settings.

### 2. Generate a refresh token

Run the included auth script to complete the OAuth flow and obtain a refresh token:

```sh
python3 spotify_auth.py --client-id YOUR_CLIENT_ID --client-secret YOUR_CLIENT_SECRET
```

This will open your browser for Spotify authorization, start a local server to capture the callback, and print your refresh token.

### 3. Create a Blitline account

Album art from Spotify is full-color and high-resolution. The Playdate has a 1-bit 400x240 display. [Blitline](https://www.blitline.com) is a web-based image processing API that handles the conversion — it resizes the image to 200x200 and applies Floyd-Steinberg dithering to produce a monochrome BMP the Playdate can render.

1. Sign up at [blitline.com](https://www.blitline.com).
2. Find your **Application ID** on the dashboard.

### 4. Create `src/secrets.lua`

Create a `src/secrets.lua` file with your credentials:

```lua
return {
    client_id = "YOUR_SPOTIFY_CLIENT_ID",
    client_secret = "YOUR_SPOTIFY_CLIENT_SECRET",
    refresh_token = "YOUR_SPOTIFY_REFRESH_TOKEN",
    app_id = "YOUR_BLITLINE_APP_ID"
}
```

## Building

The Makefile uses the Playdate SDK to compile and run the project:

```sh
make build   # compile with pdc
make run     # compile and open in Playdate Simulator
make clean   # remove build output
```

### Makefile paths

The Makefile is written for macOS and assumes:

- The Playdate SDK is installed at `~/Developer/PlaydateSDK`.
- The Playdate Simulator is launched with `open -a "Playdate Simulator"`.

On **Linux**, change the `SIM` line to the path of the simulator binary, e.g.:

```makefile
SIM = ~/Developer/PlaydateSDK/bin/PlaydateSimulator
```

On **Windows**, adjust both `SDK` and `SIM` to match your install paths and use the Windows simulator executable.

### Nix

A `shell.nix` is provided that fetches the [playdate-luacats](https://github.com/notpeter/playdate-luacats) type stubs and the [lua-utils](https://github.com/mogenson/lua-utils) async library. Run `nix-shell` to symlink these into the project for editor support and type checking via `lua-language-server`.
