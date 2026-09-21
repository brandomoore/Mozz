# Releasing Mozz

One tag produces one release: Android APKs, Windows, macOS and Linux desktop
builds, checksums and notes, all attached to a GitHub Release. iOS is a separate,
manual path because Apple requires it to be.

## The short version

```bash
# 1. Bump the version. This file is the single source for every platform.
$EDITOR project.yml          # MARKETING_VERSION: "2026.9.21"

# 2. Write what changed.
$EDITOR CHANGELOG.md         # add a "## 2026.9.21" section at the top

# 3. Land both on main, then tag it.
git commit -am "Mozz 2026.9.21"
git push origin main
git tag -a v2026.9.21 -m "Mozz 2026.9.21 — <highlights>"
git push origin v2026.9.21
```

Pushing the tag starts `.github/workflows/release.yml`. It takes roughly an hour,
most of it cross-compiling Swift four ways.

To rehearse without publishing, run the workflow manually from the Actions tab
with **draft** left on — it builds everything and leaves the release unpublished
for you to look at.

## Where the version comes from

`MARKETING_VERSION` in `project.yml` is the only place a human edits it.

- **iOS** reads it directly, through XcodeGen.
- **Desktop** reads it via `tools/version-info.py`, which the `.csproj` calls
  during the build.
- **Android** reads the same script from `app/build.gradle.kts`.

`versionCode` (Android) and the build number everywhere else are
`git rev-list --count HEAD` — monotonic by construction, which is what Android
requires and what lets a build number name an exact commit.

The release workflow **refuses to run if the tag and `project.yml` disagree**.
That check exists because the three clients once shipped three different version
numbers for the same commit, which makes a bug report impossible to place.

CalVer, `YYYY.M.D`. A second release the same day is `2026.9.21.1`.

## Secrets the workflow needs

Set these under **Settings → Secrets and variables → Actions**.

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The release keystore, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Its store password |
| `ANDROID_KEY_ALIAS` | The key alias inside it |
| `ANDROID_KEY_PASSWORD` | That key's password |

### Creating the Android keystore (once, ever)

```bash
keytool -genkeypair -v -keystore mozz-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias mozz
```

Then, to get it into the secret:

```bash
base64 -i mozz-release.jks | pbcopy
```

**Back this file up somewhere you will still have in five years, along with both
passwords.** Android identifies an app by its signing key. Lose the keystore and
no existing install can ever be updated again — every user would have to
uninstall and lose their downloads and sign-ins. There is no recovery and no
appeal; this is the single most important file in the project.

Keep it out of the repository. `.gitignore` covers `*.jks`.

The release job fails loudly if the keystore secret is missing, rather than
publishing an unsigned APK — an unsigned APK builds perfectly and installs
nowhere, and the installer's refusal says nothing a user could act on.

## iOS

Not part of the tag workflow. Apple requires submission through App Store Connect
with credentials that are not in this repository.

```bash
fastlane beta --env fastlane      # TestFlight
```

The build number fastlane stamps should match the tag's, so a TestFlight build
maps back to an exact commit. See `fastlane/README.md`.

## What is still manual, and what it would take

- **macOS notarisation.** Releases are ad-hoc signed, so first launch needs a
  right-click → Open (documented in [INSTALL.md](INSTALL.md)). Removing that step
  needs an Apple Developer ID certificate and a notarisation run in CI.
- **Windows code signing.** SmartScreen warns on first run. Removing that needs a
  paid code-signing certificate.
- **macOS on Intel.** Only `osx-arm64` is built. `osx-x64` is a matrix entry away
  if anyone asks for it.
- **Google Play.** The release APK is around 100 MB, over Play's 100 MB APK
  limit, so a Play listing would need an Android App Bundle (`bundleRelease`)
  rather than the APK. Sideloading from the Releases page has no such limit.

## After the release

Check that the assets are all there and that one of them actually runs. The
workflow verifies a great deal — that the APK is signed, that the macOS bundle's
signature validates, that every expected FFI symbol is exported — but nothing
substitutes for opening the app once.
