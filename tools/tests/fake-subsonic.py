#!/usr/bin/env python3
"""A Subsonic server that is just real enough to sign in to and sync.

Mozz speaks Plex, Jellyfin and Subsonic, and only Plex was ever exercised
against a live server here — the other two were compile-verified and reasoned
about. "It reaches the connect command" and "I watched it connect" are not the
same claim, and the gap is exactly where a wire-shape mistake hides.

So this answers the handful of endpoints the Subsonic backend actually calls,
out of a catalogue defined at the top of the file:

    ping            the authoritative credential check (sign-in is this alone)
    getArtists      the whole indexed artist list, in one call
    getAlbumList2   albums, paged by size/offset
    getAlbum        one album with its songs — the album-walk's second half
    search3         the quick-start flat track path
    getPlaylists    (empty, but it must answer)
    getLicense      some clients ask; harmless to answer

It is a TEST FIXTURE, not a server. It authenticates nobody: any `u`/`t`/`s` is
accepted, because what is under test is Mozz's side of the conversation, not
this side's security. Do not point anything real at it and do not expose it.

    tools/tests/fake-subsonic.py [--port 4533] [--name Navidrome]
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

API_VERSION = "1.16.1"

ARTISTS = [
    {"id": "ar-1", "name": "Jaubi", "albumCount": 1},
    {"id": "ar-2", "name": "Khruangbin", "albumCount": 1},
]

ALBUMS = [
    {
        "id": "al-1", "name": "Nafs at Peace", "artist": "Jaubi", "artistId": "ar-1",
        "songCount": 2, "duration": 495, "year": 2021, "genre": "Jazz",
    },
    {
        "id": "al-2", "name": "Con Todo El Mundo", "artist": "Khruangbin", "artistId": "ar-2",
        "songCount": 2, "duration": 430, "year": 2018, "genre": "Psychedelic",
    },
]

SONGS = {
    "al-1": [
        {"id": "so-1", "parent": "al-1", "title": "Insia", "album": "Nafs at Peace",
         "artist": "Jaubi", "track": 1, "year": 2021, "duration": 260,
         "suffix": "mp3", "contentType": "audio/mpeg"},
        {"id": "so-2", "parent": "al-1", "title": "Raga Gujri Todi", "album": "Nafs at Peace",
         "artist": "Jaubi", "track": 2, "year": 2021, "duration": 235,
         "suffix": "mp3", "contentType": "audio/mpeg"},
    ],
    "al-2": [
        {"id": "so-3", "parent": "al-2", "title": "Maria También", "album": "Con Todo El Mundo",
         "artist": "Khruangbin", "track": 1, "year": 2018, "duration": 218,
         "suffix": "mp3", "contentType": "audio/mpeg"},
        {"id": "so-4", "parent": "al-2", "title": "August 10", "album": "Con Todo El Mundo",
         "artist": "Khruangbin", "track": 2, "year": 2018, "duration": 212,
         "suffix": "mp3", "contentType": "audio/mpeg"},
    ],
}


def index_artists():
    """Artists grouped under their initial, which is the shape `getArtists` has."""
    buckets: dict[str, list] = {}
    for artist in ARTISTS:
        buckets.setdefault(artist["name"][0].upper(), []).append(artist)
    return [{"name": letter, "artist": found} for letter, found in sorted(buckets.items())]


class Handler(BaseHTTPRequestHandler):
    server_name_label = "Navidrome"

    def do_GET(self):  # noqa: N802 — BaseHTTPRequestHandler's spelling
        parsed = urlparse(self.path)
        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}

        if not parsed.path.startswith("/rest/"):
            self.send_error(404)
            return

        endpoint = parsed.path[len("/rest/"):].removesuffix(".view")
        body = self.answer(endpoint, query)
        if body is None:
            # An endpoint Mozz asks for that this does not model. Reported as
            # Subsonic's own "not supported" rather than a 404, so the client
            # takes the documented path instead of a transport error.
            body = {"status": "failed", "error": {"code": 30, "message": f"{endpoint} not implemented"}}

        payload = json.dumps({"subsonic-response": {
            "status": "ok",
            "version": API_VERSION,
            "type": self.server_name_label.lower(),
            "serverVersion": "0.0.0-fake",
            "openSubsonic": True,
            **body,
        }}).encode()

        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def answer(self, endpoint, query):
        if endpoint == "ping":
            return {}
        if endpoint == "getLicense":
            return {"license": {"valid": True}}
        if endpoint == "getMusicFolders":
            return {"musicFolders": {"musicFolder": [{"id": 1, "name": "Music"}]}}
        if endpoint == "getArtists":
            return {"artists": {"index": index_artists()}}
        if endpoint == "getAlbumList2":
            offset = int(query.get("offset", 0))
            size = int(query.get("size", 500))
            return {"albumList2": {"album": ALBUMS[offset:offset + size]}}
        if endpoint == "getAlbum":
            album = next((a for a in ALBUMS if a["id"] == query.get("id")), None)
            if album is None:
                return {"album": None}
            return {"album": {**album, "song": SONGS.get(album["id"], [])}}
        if endpoint == "getArtist":
            artist = next((a for a in ARTISTS if a["id"] == query.get("id")), None)
            if artist is None:
                return {"artist": None}
            return {"artist": {**artist,
                               "album": [a for a in ALBUMS if a["artistId"] == artist["id"]]}}
        if endpoint == "search3":
            offset = int(query.get("songOffset", query.get("offset", 0)))
            count = int(query.get("songCount", 500))
            songs = [s for album in SONGS.values() for s in album]
            return {"searchResult3": {
                "artist": ARTISTS,
                "album": ALBUMS,
                "song": songs[offset:offset + count],
            }}
        if endpoint == "getPlaylists":
            return {"playlists": {"playlist": []}}
        if endpoint in ("scrobble", "setRating", "star", "unstar", "savePlayQueue"):
            return {}
        if endpoint == "getPlayQueue":
            return {}
        return None

    def log_message(self, fmt, *args):
        # One line per request, which is the point: it is how you see what the
        # client actually asked for.
        print(f"  {self.address_string()} {fmt % args}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=4533)
    parser.add_argument("--name", default="Navidrome",
                        help="What `ping` reports as the server product.")
    args = parser.parse_args()

    Handler.server_name_label = args.name
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"fake {args.name} on http://127.0.0.1:{args.port} — "
          f"{len(ARTISTS)} artists, {len(ALBUMS)} albums, "
          f"{sum(len(s) for s in SONGS.values())} songs", flush=True)
    print("any username and password are accepted; this authenticates nobody", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
