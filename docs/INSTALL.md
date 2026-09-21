# Installing Mozz

Every download is on the [Releases page](https://github.com/thatcube/Mozz/releases).
Pick the file for your platform, then follow the section below it.

You will need a **Plex**, **Jellyfin**, or **Subsonic / OpenSubsonic** server —
Mozz plays the music on your server and does not host anything itself.

| Platform | File |
|---|---|
| Android phone or tablet | `Mozz-android-arm64-v8a-<version>.apk` |
| Android emulator | `Mozz-android-x86_64-<version>.apk` |
| Windows 10/11 (64-bit) | `Mozz-win-x64-<version>.zip` |
| macOS (Apple silicon) | `Mozz-osx-arm64-<version>.zip` |
| Linux (x64) | `Mozz-linux-x64-<version>.tar.gz` |
| Linux (arm64) | `Mozz-linux-arm64-<version>.tar.gz` |
| iPhone / iPad | not on this page — see [iOS](#ios-and-ipados) |

Every release also has a `SHA256SUMS.txt`. To check a download:

```bash
sha256sum --check --ignore-missing SHA256SUMS.txt
```

---

## Android

Requires **Android 9 (API 28)** or later. Take the `arm64-v8a` file — that is
every phone and tablet made in roughly the last decade. The `x86_64` build is for
emulators.

1. Download the `.apk` to the device.
2. Open it. Android will say the file came from an unknown source and offer a
   settings switch; allow your browser or file manager to install apps, then come
   back and confirm.
3. Open Mozz and sign in to your server.

The APK is about 100 MB, most of which is the Swift core and its runtime — the
same code the iPhone app runs, compiled for Android.

**This is a sideload, not a Play Store install.** Android will not auto-update it;
to upgrade, download the newer APK and open it, which installs over the top and
keeps your library, downloads and sign-ins. Updates only install cleanly if they
are signed with the same key, which every official release is.

## Windows

Requires **Windows 10 or 11, 64-bit**. Nothing to install first: .NET, the Swift
runtime and FFmpeg are all inside the zip.

1. Unzip anywhere — your user folder is fine, it does not need Program Files.
2. Run `Mozz.Desktop.exe`.

**SmartScreen will warn you.** "Windows protected your PC" appears because the
build is not signed with a paid code-signing certificate, not because anything
is wrong with it. Click **More info**, then **Run anyway**. If you would rather
verify first, check the download against `SHA256SUMS.txt` above.

## macOS

Requires **macOS 12 or later on Apple silicon** (M1 and later). There is no Intel
build yet.

1. Unzip and drag **Mozz.app** to your Applications folder.
2. `brew install ffmpeg` — macOS is the one desktop platform where Mozz does not
   carry its own copy, because Homebrew is there to provide it.
3. **Right-click the app and choose Open** the first time, then confirm.

That right-click matters. The app is signed but not notarised, so a normal
double-click gives "Mozz cannot be opened because the developer cannot be
verified" with no way past it; opening from the context menu offers the button
that lets it through. You only do this once.

If macOS refuses anyway, clear the quarantine flag it attached on download:

```bash
xattr -dr com.apple.quarantine /Applications/Mozz.app
```

Run it from **Applications**, not from your Downloads folder. macOS only offers
the local-network permission prompt to an app in a normal install location, and
without that permission Mozz cannot reach a server on your LAN — it fails with
"No route to host" while everything else on the machine works.

## Linux

Requires a 64-bit desktop with **ALSA, PulseAudio or PipeWire**, which any
desktop install has. The Swift runtime and .NET are bundled; FFmpeg is not.

```bash
tar xzf Mozz-linux-x64-<version>.tar.gz
sudo apt install ffmpeg      # or dnf / pacman / zypper
./Mozz.Desktop
```

Take the `arm64` file on a Raspberry Pi, an Ampere box, or a VM on an Apple
silicon Mac.

## iOS and iPadOS

Requires **iOS / iPadOS 17 or later**.

The iPhone and iPad app is not on the Releases page, because Apple does not allow
apps to be installed from a download. It ships through TestFlight and the App
Store — see the [repository's front page](../README.md) for where that stands.

You can also build and run it yourself from source with Xcode; see
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

---

## Something went wrong

Please [open an issue](https://github.com/thatcube/Mozz/issues) with your
platform, the Mozz version, your server type (Plex / Jellyfin / Subsonic), and
what you expected. The version is in **Settings**, at the bottom.
