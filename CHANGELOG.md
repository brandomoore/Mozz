# Changelog

Notable changes, newest first. Dates are the release date; versions are CalVer
(`YYYY.M.D`).

Downloads are on the [Releases page](https://github.com/thatcube/Mozz/releases);
installation is in [`docs/INSTALL.md`](docs/INSTALL.md).

## 2026.9.21

The first release with downloads for **Android, Windows, macOS and Linux**.
Previous versions were an iPhone app with work in progress beside it.

### Servers

- **Every client speaks every backend.** Plex, Jellyfin and Subsonic /
  OpenSubsonic are now offered on Android and the desktop as well as on iOS.
  Android previously had a single "Connect Plex" button.
- **Several servers at once.** Sign in to more than one and switch between them
  without signing out — your own server and a friend's, each keeping its own
  catalogue, history, likes and mixes. Previously only the desktop could do this;
  on the phones, adding a second server meant losing the first, which on Plex
  costs a link approval.
- **Find servers on the network.** Mozz looks for Plex and Jellyfin servers
  nearby and offers them instead of asking for an address.
- **Jellyfin Quick Connect** and a **Plex server picker** on every client, so an
  account with several servers connects to the one you meant.
- **Sync you can watch.** Every client shows the same checklist while your
  library arrives, rather than an indefinite spinner.
- Servers shared between your own devices now arrive without moving you to a
  different library mid-session.

### Android

- **Offline downloads** — albums, playlists and tracks kept on the device.
- **The 10-band equalizer and volume levelling**, running the same filters as the
  desktop.
- **Android Auto.**
- **Continuity** — pick up what you were playing on another device.
- **Radio and mixes**, from the shared core rather than a separate implementation.
- A rebuilt player: the iPhone's seek bar and transport, track menus on every
  list, server-backed star ratings, and a landscape layout for short windows.

### Desktop

- A redesigned library: artist and album pages led by the artwork, each page
  taking its colour from the record it is showing.
- A floating transport dock, a real Now Playing player, and keyboard control.
- The lyrics column the phones already had.
- The iPhone's rating control, writing back to whichever server you are on.
- A Downloads page, search that says who made each song, and consistent spacing
  and hover throughout.

### Music discovery

- **An on-device sonic analyzer.** Mozz listens to your library and uses what it
  hears to build better mixes and radio — roughly eight times faster than the
  first version, running in the background and only on terms you set (it waits
  for a charger unless you say otherwise).
- Devices share what they have already analysed, so a second device does not
  repeat the work.
- Mixes now belong to the server whose listening built them, instead of one
  server's mixes appearing on another's Home as blank tiles.

### Plex

- Picks the best address rather than the first that answers, moves to a nearer
  one when it appears, and stops pinning an address that has stopped responding.
- Finds a server by asking the network when the account cannot say where it is.
- Collapses duplicate entries again, taking their playlist items with them.

### Under the hood

- A release workflow: a tag now produces signed Android APKs and desktop builds
  for Windows, macOS and Linux, with checksums, on the Releases page.
- One version number across all three platforms, checked at release time.
- The macOS download is a real `Mozz.app` rather than a folder of libraries.
- `tools/check-backends.sh` fails the build when a client stops offering a
  backend, a server list, network discovery, Quick Connect or the Plex picker —
  the checks that existed before all passed while Android offered one button.

## 2026.7.8

iPhone and iPad. The first curated release; see the git history for what
preceded it.
