#!/usr/bin/env bash
#
# Build Mozz Desktop as a real macOS .app bundle.
#
# WHY THIS EXISTS
#
# `dotnet publish` produces a folder with a bare executable in it. On Windows and
# Linux that is genuinely what you ship. On macOS it is not an app: double-clicking
# it opens a Terminal window, it has no icon in the Dock, it cannot be dragged to
# Applications, and Gatekeeper treats it as an unidentified binary rather than
# something with a bundle identifier.
#
# So this assembles the bundle macOS expects, gives it the app icon as an .icns,
# and signs it with whatever codesigning certificate is on the machine, falling
# back to ad-hoc when there is none. A real certificate matters for more than
# tidiness: the Keychain identifies an app by its designated requirement, and an
# ad-hoc one is a hash of the binary, so every rebuild looked like a brand new
# program and re-prompted for the Keychain password. Distributing to other
# people additionally needs notarisation, which is a separate job with its own
# credentials — see fastlane for how the iOS side does it.
#
#   tools/build-macos-app.sh              → build/Mozz.app
#   tools/build-macos-app.sh --run        → build it and launch it
#   tools/build-macos-app.sh --library X  → launch against a specific library file
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/tools/lib/apple-build-entrypoint.sh"
enter_mozz_apple_build_entrypoint "mozz/build-macos-app" "${BASH_SOURCE[0]}" "$@"

cd "$REPO"

RUN=0
LIBRARY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN=1; shift ;;
    --library) LIBRARY="$2"; RUN=1; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# SwiftPM refuses to resolve in this worktree without it; see AGENTS.local.md.
export GIT_CONFIG_PARAMETERS="'safe.bareRepository=all'"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
# ~/.nuget is root-owned on this machine.
export NUGET_PACKAGES="${NUGET_PACKAGES:-$HOME/Development/.nuget-packages}"
eval "$(tools/version-info.py --format shell)"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) RID="osx-arm64" ;;
  x86_64) RID="osx-x64" ;;
  *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

APP="build/Mozz.app"
STAGE="build/publish-$RID"

echo "▸ Building the Swift core…"
swift build -c release --product MozzFFI
# Ask SwiftPM where it actually put the binaries rather than reading
# `.build/release`. That name is a SYMLINK, and it is shared: the Android
# client's Gradle build cross-compiles the same package for
# aarch64-unknown-linux-android28 and repoints it on the way past. A macOS
# build running alongside one then copied from an Android directory and failed
# on a missing dylib, with nothing in the output to say why.
SWIFT_BIN="$(swift build -c release --product MozzFFI --show-bin-path)"

echo "▸ Publishing the app ($RID, self-contained)…"
rm -rf "$STAGE"
dotnet publish clients/desktop/Mozz.Desktop.csproj \
  -c Release -r "$RID" --self-contained true \
  -p:UseAppHost=true \
  -p:MozzMarketingVersion="$MOZZ_RESOLVED_MARKETING_VERSION" \
  -p:MozzBuildNumber="$MOZZ_RESOLVED_BUILD_NUMBER" \
  -p:MozzDisplayVersion="$MOZZ_RESOLVED_DISPLAY_VERSION" \
  -p:MozzAssemblyVersion="$MOZZ_RESOLVED_ASSEMBLY_VERSION" \
  -p:MozzFileVersion="$MOZZ_RESOLVED_FILE_VERSION" \
  -o "$STAGE" \
  --nologo -v quiet
cp "$SWIFT_BIN/libMozzFFI.dylib" "$STAGE/"

# The bundle layout, the Info.plist and the signing live in one place, shared
# with the release workflow — which used to ship the bare publish folder because
# this logic was only ever reachable from here. `--local-dev` is the one
# difference between the two: see the note on the flag in that script.
tools/make-macos-bundle.sh --stage "$STAGE" --out "$APP" --local-dev

if [ "$RUN" = "1" ]; then
  # Launch from /Applications, never from the build directory.
  #
  # macOS shows the local network permission prompt for an app in a normal
  # install location. Run the same signed bundle out of a worktree's build/
  # folder and no prompt ever appears: connections to a LAN server just fail
  # with EHOSTUNREACH, the app never appears in the Local Network settings list,
  # and there is nothing to switch on. Meanwhile curl, nc and the child ffmpeg
  # process all reach the server fine - so music plays and album art silently
  # does not, which is a hard thing to read as a permissions problem.
  #
  # Once the prompt is answered the grant follows the signing identity rather
  # than the path, so build/ works afterwards too. This copy exists to get the
  # prompt asked in the first place, which is the part that only happens once
  # and only from here.
  INSTALLED="/Applications/$(basename "$APP")"
  # Braced deliberately: bash 3.2 under some locales swallows the following
  # multibyte character into the variable name, so `$INSTALLED…` looks up a
  # variable that does not exist and `set -u` aborts the install.
  echo "▸ Installing to ${INSTALLED}…"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"

  echo "▸ Launching…"
  if [ -n "$LIBRARY" ]; then
    MOZZ_LIBRARY="$LIBRARY" open -n "$INSTALLED"
  else
    open -n "$INSTALLED"
  fi
fi
