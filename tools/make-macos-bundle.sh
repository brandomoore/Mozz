#!/usr/bin/env bash
#
# Assemble a published .NET folder into a real macOS .app bundle.
#
# WHY THIS IS ITS OWN SCRIPT
#
# `dotnet publish` produces a folder with a bare executable in it. On Windows and
# Linux that is genuinely what you ship; on macOS it is not an app. Double-clicking
# it opens a Terminal window, it has no Dock icon, it cannot be dragged to
# Applications, and Gatekeeper treats it as an unidentified binary rather than
# something with a bundle identifier.
#
# Two callers need that bundle and they are not the same build:
#
#   tools/build-macos-app.sh   the maintainer's local loop — publishes, then
#                              calls this with --local-dev
#   .github/workflows/         the release — publishes with its own careful
#     desktop-app.yml          Swift-runtime steps, then calls this
#
# The release used to ship the bare publish folder zipped, which is why "the
# macOS download" was a directory of DLLs. Copying the plist into the workflow
# would have fixed that and created a second copy of it, and the two would have
# drifted on the key that matters most — see NSLocalNetworkUsageDescription
# below, whose absence breaks every LAN connection with a message that points
# nowhere near the cause.
#
#   tools/make-macos-bundle.sh --stage build/publish-osx-arm64 --out build/Mozz.app
#   tools/make-macos-bundle.sh --stage … --out … --local-dev
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

STAGE=""
APP=""
LOCAL_DEV=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stage)     STAGE="$2"; shift 2 ;;
    --out)       APP="$2"; shift 2 ;;
    --local-dev) LOCAL_DEV=1; shift ;;
    -h|--help)   sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$STAGE" ] && [ -n "$APP" ] || { echo "need --stage and --out" >&2; exit 2; }
[ -d "$STAGE" ] || { echo "no such publish directory: $STAGE" >&2; exit 2; }

cd "$REPO"
eval "$("$REPO/tools/version-info.py" --format shell)"

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Everything published goes in MacOS/ so the executable finds its runtime and
# libMozzFFI.dylib beside it, which is where dlopen looks first.
cp -R "$STAGE/." "$APP/Contents/MacOS/"

# The icon. iconutil wants a specific set of sizes and @2x names; anything
# missing shows as a generic document in some contexts and not others.
ICONSET="$(dirname "$APP")/Mozz.iconset"
SOURCE_ICON="App/Mozz/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
if [ -f "$SOURCE_ICON" ]; then
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$SOURCE_ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$SOURCE_ICON" \
      --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Mozz.icns"
  rm -rf "$ICONSET"
else
  echo "  (no source icon at $SOURCE_ICON — bundle will use the generic one)"
fi

# Only the local loop marks itself. The flag lets the credential store skip
# legacy Keychain ACL prompts that happen only because that binary is rebuilt
# constantly; a release is not rebuilt constantly and should use the Keychain
# normally, so a released bundle carrying this key would be a bug.
DEV_KEY=""
if [ "$LOCAL_DEV" = "1" ]; then
  DEV_KEY="  <key>MozzLocalDevelopmentBuild</key><true/>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mozz</string>
  <key>CFBundleDisplayName</key><string>Mozz</string>
  <key>CFBundleIdentifier</key><string>com.thatcube.Mozz.desktop</string>
  <key>CFBundleExecutable</key><string>Mozz.Desktop</string>
  <key>CFBundleIconFile</key><string>Mozz</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$MOZZ_RESOLVED_MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$MOZZ_RESOLVED_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Mozz plays from a server the user runs, which is almost always on the
       local network. Since macOS 15 an app must declare why it needs local
       network access before the system will even offer the permission prompt;
       without this key the request is refused silently and every LAN
       connection fails as EHOSTUNREACH, which surfaces as "No route to host"
       from .NET while curl on the same machine succeeds. -->
  <key>NSLocalNetworkUsageDescription</key><string>Mozz connects to your media server to stream music and download album art. Your server is usually on your local network.</string>
$DEV_KEY
  <!-- Without this the process is a background agent: no Dock icon, no menu
       bar, and the window cannot be brought to the front. -->
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHumanReadableCopyright</key><string>GPL-3.0. Free forever, open source.</string>
</dict>
</plist>
PLIST

# Signing.
#
# A bundle containing a self-contained .NET runtime is refused outright on Apple
# silicon unless every Mach-O carries at least an ad-hoc signature — which is
# why the nested binaries are signed before the bundle around them.
#
# Ad-hoc is the fallback, not the goal. A real Developer ID plus notarisation is
# what stops Gatekeeper warning the user, and needs credentials that are not in
# this repository; MOZZ_CODESIGN_IDENTITY selects one when it is available.
IDENTITY="${MOZZ_CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) [0-9A-F]* "\(.*\)"$/\1/p' | head -1)"
fi

if [ -n "$IDENTITY" ]; then
  echo "▸ Signing as ${IDENTITY}…"
  SIGN=(--force --sign "$IDENTITY" --timestamp=none)
else
  echo "▸ Signing ad-hoc (no certificate found)…"
  SIGN=(--force --sign - --timestamp=none)
fi

find "$APP/Contents/MacOS" -type f \( -name "*.dylib" -o -name "*.so" \) \
  -exec codesign "${SIGN[@]}" {} \; 2>/dev/null || true
codesign "${SIGN[@]}" --deep "$APP" 2>/dev/null \
  || echo "  (codesign reported an issue; the app may still run)"

SIZE="$(du -sh "$APP" | cut -f1)"
echo "✓ $APP ($SIZE) — version $MOZZ_RESOLVED_DISPLAY_VERSION"
