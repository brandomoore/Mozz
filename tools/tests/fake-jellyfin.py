#!/usr/bin/env python3
"""A Jellyfin server that is just real enough to sign in to and sync.

The sibling of `fake-subsonic.py`, and it exists for the same reason: Mozz
speaks three backends, and until these two fixtures existed only Plex had ever
been exercised against something that answers. "It reaches the connect command"
and "I watched it connect" are not the same claim, and the gap between them is
exactly where a wire-shape mistake hides.

It answers the endpoints the Jellyfin backend actually calls:

    POST Users/AuthenticateByName   the credential check — sign-in is this
    System/Info/Public              the server's name, read right after
    Users/Me                        who signed in
    Users/{id}/Views                the libraries, to find the music one
    Library/MediaFolders            the same question, asked the other way
    Items                           the catalogue, paged and filtered by type
    Artists                         the artist list
    Users/{id}/Items/Latest         recently added
    Items/{id}/Images/Primary       covers — a real PNG, so artwork paths run
    DisplayPreferences/{id}         Jellyfin stores client prefs server-side
    Sessions/Playing*               playback reporting, which must not 404

It is a TEST FIXTURE, not a server. It authenticates nobody: any username and
password are accepted, because what is under test is Mozz's side of the
conversation. Do not point anything real at it and do not expose it.

    tools/tests/fake-jellyfin.py [--port 8096] [--name "Study Jellyfin"]
"""

import argparse
import base64
import json
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

USER_ID = "aa11bb22cc33dd44ee55ff6600112233"
MUSIC_LIBRARY_ID = "lib-music"
TOKEN = "fake-jellyfin-access-token"

TICKS_PER_SECOND = 10_000_000


def ticks(seconds):
    return seconds * TICKS_PER_SECOND


ARTISTS = [
    {"Id": "ar-1", "Name": "Khruangbin", "Type": "MusicArtist"},
    {"Id": "ar-2", "Name": "Hania Rani", "Type": "MusicArtist"},
]

ALBUMS = [
    {
        "Id": "al-1", "Name": "Con Todo El Mundo", "Type": "MusicAlbum",
        "AlbumArtist": "Khruangbin", "AlbumArtists": [{"Name": "Khruangbin", "Id": "ar-1"}],
        "ArtistItems": [{"Name": "Khruangbin", "Id": "ar-1"}],
        "ProductionYear": 2018, "ChildCount": 2, "Genres": ["Psychedelic"],
        "ImageTags": {"Primary": "tag-al-1"}, "DateCreated": "2024-01-02T03:04:05.0000000Z",
    },
    {
        "Id": "al-2", "Name": "Esja", "Type": "MusicAlbum",
        "AlbumArtist": "Hania Rani", "AlbumArtists": [{"Name": "Hania Rani", "Id": "ar-2"}],
        "ArtistItems": [{"Name": "Hania Rani", "Id": "ar-2"}],
        "ProductionYear": 2019, "ChildCount": 2, "Genres": ["Modern Classical"],
        "ImageTags": {"Primary": "tag-al-2"}, "DateCreated": "2024-02-02T03:04:05.0000000Z",
    },
]

TRACKS = [
    {
        "Id": "tr-1", "Name": "Maria También", "Type": "Audio",
        "Album": "Con Todo El Mundo", "AlbumId": "al-1", "AlbumArtist": "Khruangbin",
        "Artists": ["Khruangbin"], "ArtistItems": [{"Name": "Khruangbin", "Id": "ar-1"}],
        "IndexNumber": 1, "ParentIndexNumber": 1, "ProductionYear": 2018,
        "RunTimeTicks": ticks(218), "AlbumPrimaryImageTag": "tag-al-1",
        "Genres": ["Psychedelic"], "UserData": {"IsFavorite": False},
    },
    {
        "Id": "tr-2", "Name": "August 10", "Type": "Audio",
        "Album": "Con Todo El Mundo", "AlbumId": "al-1", "AlbumArtist": "Khruangbin",
        "Artists": ["Khruangbin"], "ArtistItems": [{"Name": "Khruangbin", "Id": "ar-1"}],
        "IndexNumber": 2, "ParentIndexNumber": 1, "ProductionYear": 2018,
        "RunTimeTicks": ticks(212), "AlbumPrimaryImageTag": "tag-al-1",
        "Genres": ["Psychedelic"], "UserData": {"IsFavorite": True},
    },
    {
        "Id": "tr-3", "Name": "Glass", "Type": "Audio",
        "Album": "Esja", "AlbumId": "al-2", "AlbumArtist": "Hania Rani",
        "Artists": ["Hania Rani"], "ArtistItems": [{"Name": "Hania Rani", "Id": "ar-2"}],
        "IndexNumber": 1, "ParentIndexNumber": 1, "ProductionYear": 2019,
        "RunTimeTicks": ticks(304), "AlbumPrimaryImageTag": "tag-al-2",
        "Genres": ["Modern Classical"], "UserData": {"IsFavorite": False},
    },
    {
        "Id": "tr-4", "Name": "Sun", "Type": "Audio",
        "Album": "Esja", "AlbumId": "al-2", "AlbumArtist": "Hania Rani",
        "Artists": ["Hania Rani"], "ArtistItems": [{"Name": "Hania Rani", "Id": "ar-2"}],
        "IndexNumber": 2, "ParentIndexNumber": 1, "ProductionYear": 2019,
        "RunTimeTicks": ticks(268), "AlbumPrimaryImageTag": "tag-al-2",
        "Genres": ["Modern Classical"], "UserData": {"IsFavorite": False},
    },
]

BY_TYPE = {
    "MusicArtist": ARTISTS,
    "MusicAlbum": ALBUMS,
    "Audio": TRACKS,
    "Playlist": [],
}


def png(rgb):
    """A 1x1 PNG of one colour, so the artwork path runs end to end."""
    def chunk(kind, payload):
        body = kind + payload
        return (len(payload).to_bytes(4, "big") + body
                + (zlib.crc32(body) & 0xFFFFFFFF).to_bytes(4, "big"))

    header = (1).to_bytes(4, "big") + (1).to_bytes(4, "big") + bytes([8, 2, 0, 0, 0])
    raw = bytes([0]) + bytes(rgb)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


COVERS = {"tag-al-1": png((0x2E, 0x86, 0xD6)), "tag-al-2": png((0xE5, 0xA0, 0x0D))}


class Handler(BaseHTTPRequestHandler):
    server_name_label = "Study Jellyfin"

    # MARK: plumbing

    def do_GET(self):  # noqa: N802 — BaseHTTPRequestHandler's spelling
        self.respond(*self.answer_get(urlparse(self.path)))

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        self.respond(*self.answer_post(urlparse(self.path), raw))

    def respond(self, body, content_type="application/json; charset=utf-8", status=200):
        if body is None:
            self.send_error(404)
            return
        payload = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    # MARK: the API

    def answer_post(self, parsed, raw):
        path = parsed.path.strip("/")
        if path == "Users/AuthenticateByName":
            # Any credential. What is under test is the exchange, not the check.
            body = json.loads(raw or b"{}")
            return ({
                "AccessToken": TOKEN,
                "ServerId": "fake-jellyfin",
                "User": {"Id": USER_ID, "Name": body.get("Username") or "listener"},
            },)
        if path.startswith("Sessions/Playing") or path.startswith("Users/"):
            return ({},)
        if path.startswith("DisplayPreferences/"):
            return ({},)
        return (None,)

    def answer_get(self, parsed):
        path = parsed.path.strip("/")
        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}

        if path == "System/Info/Public":
            return ({"ServerName": self.server_name_label,
                     "Version": "10.9.0",
                     "Id": "fake-jellyfin"},)

        if path == "Users/Me":
            return ({"Id": USER_ID, "Name": "listener"},)

        if path.endswith("/Views") or path == "Library/MediaFolders":
            return ({"Items": [{
                "Id": MUSIC_LIBRARY_ID,
                "Name": "Music",
                "Type": "CollectionFolder",
                "CollectionType": "music",
            }], "TotalRecordCount": 1},)

        if path == "Artists":
            return self.page(ARTISTS, query)

        if path == "Items":
            kinds = [k for k in (query.get("IncludeItemTypes") or "").split(",") if k]
            rows = []
            for kind in kinds or ["Audio"]:
                rows += BY_TYPE.get(kind, [])
            # `ParentId` scopes to an album when the backend walks one.
            parent = query.get("ParentId")
            if parent and parent != MUSIC_LIBRARY_ID:
                rows = [r for r in rows if r.get("AlbumId") == parent]
            return self.page(rows, query)

        if path.endswith("/Items/Latest"):
            return (ALBUMS,)

        if "/Images/Primary" in path:
            tag = query.get("tag") or query.get("Tag")
            cover = COVERS.get(tag) or next(iter(COVERS.values()))
            return (cover, "image/png")

        if path.startswith("DisplayPreferences/"):
            return ({"Id": path.split("/")[-1], "CustomPrefs": {}},)

        if "/universal" in path or path.endswith("/Download"):
            # Not real audio. Enough that resolving a stream URL succeeds.
            return (b"", "audio/mpeg")

        if path.startswith("Audio/") and path.endswith("/Lyrics"):
            return (None,)

        return (None,)

    def page(self, rows, query):
        start = int(query.get("StartIndex", 0))
        limit = int(query.get("Limit", len(rows)))
        return ({"Items": rows[start:start + limit], "TotalRecordCount": len(rows)},)

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} {fmt % args}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8096)
    parser.add_argument("--name", default="Study Jellyfin")
    args = parser.parse_args()

    Handler.server_name_label = args.name
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"fake Jellyfin '{args.name}' on http://0.0.0.0:{args.port} — "
          f"{len(ARTISTS)} artists, {len(ALBUMS)} albums, {len(TRACKS)} tracks", flush=True)
    print("any username and password are accepted; this authenticates nobody", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
