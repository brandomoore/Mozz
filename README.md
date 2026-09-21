<p align="center"><img src="https://raw.githubusercontent.com/thatcube/brando/main/logos/mozz.svg" alt="Mozz logo" width="128" /></p>

<h1 align="center">Mozz</h1>

<p align="center">One app for your music, wherever it lives.<br />
A free, open-source music player for the Plex, Jellyfin, or Subsonic server you already run.</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" /></a>
  <img alt="Platforms: iOS, iPadOS, Android, Windows, macOS, Linux" src="https://img.shields.io/badge/Platforms-iOS%20%C2%B7%20Android%20%C2%B7%20Windows%20%C2%B7%20macOS%20%C2%B7%20Linux-lightgrey.svg" />
  <a href="https://github.com/sponsors/thatcube"><img alt="Sponsor" src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa.svg" /></a>
</p>

Mozz is a **self-hosted music player** for the server you already run. Point it at
**Plex**, **Jellyfin**, or a **Subsonic / OpenSubsonic** server (Navidrome is the
tested target) and your whole library shows up on your **iPhone, iPad, Android
phone, and desktop** — ready to stream over the network or download and take with
you.

Streaming and offline both matter here, equally. Some people stream everything and
never download a thing; others save their library and live underground on the
subway. Mozz is built for both, and it does not push you toward either.

**One app for your music, wherever it lives. Free forever. Open source.**

---

## Who it's for

You already self-host your music and want a fast, native client that respects it: no
second subscription, no re-uploading your library to someone else's cloud, and no
telemetry watching what you listen to.

## Platforms

Every Mozz client speaks all three backends and shares one core, so a feature is
not an iPhone feature or a desktop feature — it's a Mozz feature.

| | iOS / iPadOS | Android | Windows · macOS · Linux |
|---|---|---|---|
| Plex, Jellyfin, Subsonic | ✅ | ✅ | ✅ |
| Several servers, switch instantly | ✅ | ✅ | ✅ |
| Find servers on your network | ✅ | ✅ | ✅ |
| Offline downloads | ✅ | ✅ | ✅ |
| Equalizer, loudness, lyrics | ✅ | ✅ | ✅ |
| Mixes, radio, Mozz Weekly | ✅ | ✅ | ✅ |
| In the car | CarPlay | Android Auto | — |
| Voice assistant & widgets | Siri, HomePod, widgets | — | — |

The Android and desktop clients are younger than the iPhone one and are built from
source today — see [`clients/android/README.md`](clients/android/README.md) and
[`clients/desktop/README.md`](clients/desktop/README.md).

## Features

### Your servers

- **Bring your own.** Connect Plex, Jellyfin, or Subsonic/OpenSubsonic and sign in
  the way that server expects — a Plex login, **Jellyfin Quick Connect** or a
  password, or a Subsonic account. Choose exactly which libraries to pull in.
- **More than one at a time.** Sign in to several servers and switch between them
  without signing out of anything — your home server and a friend's, side by side,
  each keeping its own catalogue, history, and mixes.
- **Found, not typed.** Mozz looks for Plex and Jellyfin servers on your network and
  offers them, instead of asking you to copy an address out of a router admin page.
  Plex accounts with several servers get a picker rather than a guess.

### Your library

- **One tidy library.** Artists, albums, songs, playlists, and genres all live in one
  place, however your server organizes them.
- **Works when the network doesn't.** Your catalog is kept on the device, so
  browsing, searching, and opening albums stay instant even when the server is slow,
  far away, or offline.
- **Search that keeps up.** Results appear as you type, and accents and punctuation
  don't get in the way — "bjork" finds "Björk".

### Playback

- **Near-gapless.** Tracks flow into one another without a silent gap between them,
  the way an album is meant to play.
- **Smart shuffle.** Shuffle spreads your artists out instead of clumping the same one
  back to back, plus the usual repeat modes.
- **Even loudness.** Volume normalization keeps quiet and loud tracks at a comfortable
  level, so you're not reaching for the volume between songs.
- **A real equalizer.** A 10-band graphic EQ (31 Hz–16 kHz) with presets.
- **Lyrics.** Time-synced lyrics that highlight and scroll the current line, with a
  full-screen mode for just the words. Mozz uses your server's lyrics first and falls
  back to [LRCLIB](https://lrclib.net) when there are none.

### Take it offline

- **Download for the road.** Save albums, playlists, or tracks to the device and play
  them straight from storage — no network needed, no quality loss.
- **Downloads that stick around.** Transfers keep going in the background, re-syncing
  never loses what you've saved, and your lyrics come with them.

### Discovery & ratings

- **Mozz Weekly.** A weekly mix that rediscovers music already in your library, built
  right on the device.
- **Radio and mixes** seeded from what you're listening to.
- **Likes and stars, unified.** Jellyfin and Subsonic favourites and Plex's star
  ratings show up together, and Mozz writes them back to your server where it's
  supported.
- **Optional enrichment.** Sharpen radio and mixes with open music databases (only song
  and artist names are sent) — or leave it off and keep recommendations on-device.

### Across your devices

- **Continue here.** Leave off on one device and Mozz can offer to pick playback up
  where you left it on another — resumed only when you choose, never yanked away.
- **Deep links.** `mozz://` links open straight to an album, artist, playlist, genre,
  or tab, and Apple devices can hand a screen off between themselves.
- **Sign in once.** On Apple devices your server credentials travel through the iCloud
  Keychain, so you don't retype them.

### In the car

**CarPlay** and **Android Auto** both get your Home and Library on the car screen, with
artwork, a shuffle shortcut, and an Up Next list. They read the on-device library, so
they stay quick where signal is poor and downloaded tracks keep playing when the server
can't be reached.

### Siri, HomePod & widgets (Apple devices)

- **Ask for anything.** "Play …" a song, album, artist, playlist, genre, your liked
  songs, or a mix — from the Siri button, Shortcuts, or a **HomePod**, which hands the
  request to your iPhone.
- **Widgets.** Now Playing and Recently Played for your Home Screen.

### Make it yours

Light, dark, or follow the system, with a choice of dark looks and an optional Liquid
Glass player finish on newer iOS.

---

## Requirements

- **A device**: iPhone or iPad on iOS / iPadOS 17+, an Android phone or tablet, or a
  Windows, macOS, or Linux desktop.
- **A media server** you can reach: Plex, Jellyfin, or Subsonic / OpenSubsonic.
  Navidrome is the tested Subsonic target; other OpenSubsonic servers are best-effort.

## Getting started

1. Install Mozz — see [building it yourself](#contributing--development) while a public
   release is in progress.
2. Choose your server type: Plex, Jellyfin, or Subsonic. Mozz offers any it finds on
   your network.
3. Sign in the way that server expects and pick the libraries you want.
4. Wait for your library to appear, then start streaming — or download some albums for
   offline.

## Privacy

Mozz has no backend of its own and collects nothing about you — no account, no
analytics, no tracking. It talks to **your** media server, to Plex's sign-in and
discovery service when you use Plex, and — only when you turn those features on — to
LRCLIB for lyrics and open music databases for recommendations, sending only the
minimum needed (song and artist names). Full details are in
[`docs/PRIVACY.md`](docs/PRIVACY.md).

## Reporting bugs & requesting features

Please open an issue on [GitHub Issues](https://github.com/thatcube/Mozz/issues).
Clear steps to reproduce, your server type, your platform, and what you expected all
help.

## Contributing & development

Mozz is open source and contributions are welcome. Build instructions, the code
layout, testing, and how releases work live in
[`CONTRIBUTING.md`](CONTRIBUTING.md); the deeper design rationale is in
[`ARCHITECTURE.md`](ARCHITECTURE.md) and the notes and decision records under
[`docs/`](docs).

## Donate

Mozz is **free forever**. If it's earned a place on your Home Screen and you'd like to
chip in, you can sponsor development through
[GitHub Sponsors](https://github.com/sponsors/thatcube). It genuinely helps — but not
donating is completely fine, and you get every feature either way.

## License

Mozz is free software licensed under the **GNU General Public License v3.0**, with an
additional permission under section 7 allowing distribution through Apple's App Store
despite its DRM and code-signing requirements. See [`LICENSE`](LICENSE) for the full
terms.

Mozz is not affiliated with or endorsed by Plex, Jellyfin, Navidrome,
Subsonic/OpenSubsonic, MusicBrainz, ListenBrainz, or LRCLIB. All trademarks belong to
their respective owners.

<!-- app-family:start -->
<!-- Generated by https://github.com/thatcube/brando — edit apps.json there, not this block. -->

---

<p align="center"><b>More open source</b></p>

<p align="center">
  <a href="https://github.com/thatcube/hozz" title="Hozz — Apple Health, exported to storage you own"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/hozz-dark.svg" /><img src="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/hozz-light.svg" height="40" alt="Hozz" /></picture></a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/thatcube/Mozz" title="Mozz — Your music, wherever it lives"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/mozz-dark.svg" /><img src="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/mozz-light.svg" height="40" alt="Mozz" /></picture></a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/thatcube/Plozz" title="Plozz — Movies &amp; TV on Apple TV, iPhone &amp; iPad"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/plozz-dark.svg" /><img src="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/plozz-light.svg" height="40" alt="Plozz" /></picture></a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/thatcube/Twozz" title="Twozz — Twitch on Apple TV, with real emotes"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/twozz-dark.svg" /><img src="https://raw.githubusercontent.com/thatcube/brando/main/logos/lockups/twozz-light.svg" height="40" alt="Twozz" /></picture></a>
</p>

<p align="center">
  <a href="https://brando.page">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/thatcube/brando/main/logos/brando-white.svg" />
      <img src="https://raw.githubusercontent.com/thatcube/brando/main/logos/brando-black.svg" height="22" alt="Brandon Moore" />
    </picture>
  </a>
</p>
<!-- app-family:end -->
