#!/usr/bin/env python3
"""
Spotify OAuth Authorization Script
Handles the authorization flow to obtain a refresh token for the Spotify Web API.
"""

import argparse
import sys
import threading
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer


class CallbackHandler(BaseHTTPRequestHandler):
    """HTTP request handler to capture the authorization code from Spotify's redirect."""

    authorization_code = None

    def do_GET(self):
        """Handle GET request from Spotify redirect."""
        # Parse the query parameters
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)

        if "code" in params:
            # Store the authorization code
            CallbackHandler.authorization_code = params["code"][0]

            # Send success response to browser
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(b"""
                <html>
                <body>
                    <h1>Authorization Successful!</h1>
                    <p>You can close this window and return to the terminal.</p>
                </body>
                </html>
            """)
        elif "error" in params:
            # Handle authorization error
            error = params["error"][0]
            self.send_response(400)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(
                f"""
                <html>
                <body>
                    <h1>Authorization Failed</h1>
                    <p>Error: {error}</p>
                </body>
                </html>
            """.encode()
            )
        else:
            # Unknown request
            self.send_response(400)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body><h1>Invalid Request</h1></body></html>")

    def log_message(self, format, *args):
        """Suppress default logging."""
        pass


def start_local_server(port=8000):
    """Start a local HTTP server to receive the callback."""
    server = HTTPServer(("localhost", port), CallbackHandler)

    # Run server in a separate thread
    server_thread = threading.Thread(target=server.handle_request)
    server_thread.daemon = True
    server_thread.start()

    return server


def get_authorization_code(client_id, redirect_uri, scopes):
    """
    Open browser for user authorization and capture the authorization code.

    Args:
        client_id: Spotify application client ID
        redirect_uri: Redirect URI configured in Spotify app
        scopes: List of permission scopes to request

    Returns:
        Authorization code string
    """
    # Build authorization URL
    scope_string = " ".join(scopes)
    auth_params = {
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "scope": scope_string,
    }

    auth_url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode(
        auth_params
    )

    print("\n🎵 Opening browser for Spotify authorization...")
    print("If the browser doesn't open automatically, visit this URL:")
    print(f"{auth_url}\n")

    # Open browser
    webbrowser.open(auth_url)

    # Start local server to capture callback
    port = int(urllib.parse.urlparse(redirect_uri).port or 8000)
    server = start_local_server(port)

    print(f"Waiting for authorization... (listening on port {port})")

    # Wait for the authorization code
    while CallbackHandler.authorization_code is None:
        import time

        time.sleep(0.1)

    return CallbackHandler.authorization_code


def exchange_code_for_token(client_id, client_secret, authorization_code, redirect_uri):
    """
    Exchange authorization code for access and refresh tokens.

    Args:
        client_id: Spotify application client ID
        client_secret: Spotify application client secret
        authorization_code: Authorization code from user approval
        redirect_uri: Redirect URI used in authorization

    Returns:
        Dictionary containing access_token, refresh_token, and other token data
    """
    import json
    import urllib.request

    token_url = "https://accounts.spotify.com/api/token"

    data = {
        "grant_type": "authorization_code",
        "code": authorization_code,
        "redirect_uri": redirect_uri,
        "client_id": client_id,
        "client_secret": client_secret,
    }

    # Encode data
    data_encoded = urllib.parse.urlencode(data).encode("utf-8")

    # Make request
    req = urllib.request.Request(token_url, data=data_encoded, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")

    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        print(f"❌ Error exchanging code for token: {e.code} {e.reason}")
        print(f"Response: {error_body}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Obtain Spotify refresh token for API access",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example usage:
  python spotify_auth.py --client-id YOUR_CLIENT_ID --client-secret YOUR_CLIENT_SECRET

The script will:
1. Open your browser for Spotify authorization
2. Start a local server to receive the callback
3. Exchange the code for tokens
4. Display your refresh token

Make sure your Spotify app has 'http://127.0.0.1:8000/callback' as a redirect URI.
        """,
    )

    parser.add_argument(
        "--client-id", required=True, help="Spotify application Client ID"
    )

    parser.add_argument(
        "--client-secret", required=True, help="Spotify application Client Secret"
    )

    parser.add_argument(
        "--port", type=int, default=8000, help="Local server port (default: 8000)"
    )

    parser.add_argument(
        "--scopes",
        nargs="+",
        default=[
            "user-read-playback-state",
            "user-modify-playback-state",
            "user-read-currently-playing",
        ],
        help="Space-separated list of scopes to request (default: user-read-playback-state user-modify-playback-state user-read-currently-playing)",
    )

    args = parser.parse_args()

    # Set redirect URI
    redirect_uri = f"http://127.0.0.1:{args.port}/callback"

    print("=" * 80)
    print("Spotify OAuth Authorization Flow")
    print("=" * 80)
    print(f"Client ID: {args.client_id}")
    print(f"Redirect URI: {redirect_uri}")
    print(f"Scopes: {', '.join(args.scopes)}")
    print("=" * 80)

    # Step 1: Get authorization code
    auth_code = get_authorization_code(args.client_id, redirect_uri, args.scopes)
    print("✅ Authorization code received!\n")

    # Step 2: Exchange for tokens
    print("🔄 Exchanging authorization code for tokens...")
    tokens = exchange_code_for_token(
        args.client_id, args.client_secret, auth_code, redirect_uri
    )

    print("\n" + "=" * 80)
    print("✅ SUCCESS! Tokens obtained")
    print("=" * 80)
    print(f"\n🔑 Access Token (expires in {tokens['expires_in']} seconds):")
    print(tokens["access_token"])
    print("\n♻️  Refresh Token (save this - it doesn't expire):")
    print(tokens["refresh_token"])
    print("\n📋 Scopes granted:")
    print(tokens.get("scope", "N/A"))
    print("\n" + "=" * 80)
    print("\n💡 Tip: Save your refresh token securely. You can use it to get new")
    print("   access tokens without going through this flow again.")
    print("\n   Example curl command to refresh:")
    print(f"""
   curl -X POST "https://accounts.spotify.com/api/token" \\
        -H "Content-Type: application/x-www-form-urlencoded" \\
        -d "grant_type=refresh_token" \\
        -d "refresh_token={tokens["refresh_token"]}" \\
        -d "client_id={args.client_id}" \\
        -d "client_secret={args.client_secret}"
    """)


if __name__ == "__main__":
    main()
