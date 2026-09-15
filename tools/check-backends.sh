#!/usr/bin/env bash
#
# Which media servers each app will actually let you sign in to.
#
# `tools/check-parity.sh` asks which FFI commands a shell reaches, and that is
# a different question with a different answer. Android reached `connect` — it
# is right there in `MozzServer.connect(kind, …)`, it takes a `BackendKind`, and
# `BackendKind` has had all three values since the day it was written. Every
# check in this repo was green. And yet the Android app offered one button,
# "Connect Plex", and there was no way to sign in to Jellyfin or a Subsonic
# server at all: the capability was reachable from the code and unreachable from
# the app, which is the exact failure mode check-parity.sh exists to catch, one
# level up.
#
# So this looks at the sign-in surface itself. For each shell, which members of
# `BackendKind` does the code that DRAWS the chooser actually name?
#
#   tools/check-backends.sh            report what each app offers
#   tools/check-backends.sh --check    fail if an app offers fewer than the core
#
# There is no baseline file on purpose. The bar is not "no worse than last
# time", it is the core's own list: Mozz's rule is that a platform lacking a
# capability is behind, never exempt, and for backends that rule has a floor
# that never moves.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KINDS_FILE="$ROOT/Sources/MozzCore/BackendKind.swift"

mode="${1:-report}"

# The core's list, from the enum itself rather than a copy of it here. A fourth
# backend lands in that file first, and this starts failing for every app that
# has not caught up — which is the point.
backends() {
  grep -oE "^[[:space:]]+case [a-z]+$" "$KINDS_FILE" | awk '{print $2}' | sort
}

# The files that draw each app's chooser. Deliberately narrow: the whole point
# is that a backend named anywhere in the codebase proves nothing, so this asks
# only about the code a person picking a server is looking at.
ios_files() {
  printf '%s\n' "$ROOT/Sources/MozzApp/Onboarding"
}

android_files() {
  printf '%s\n' "$ROOT/clients/android/app/src/main/java/com/thatcube/mozz/ui/Onboarding.kt"
}

desktop_files() {
  printf '%s\n' \
    "$ROOT/clients/desktop/ViewModels/BackendOption.cs" \
    "$ROOT/clients/desktop/ViewModels/ConnectViewModel.cs"
}

# A shell "offers" a backend when its chooser names the enum case. Matched
# case-insensitively and on a word boundary: the three shells spell the same
# value `\.subsonic`, `BackendKind.SUBSONIC` and `BackendKind.Subsonic`.
offers() {
  local backend="$1"
  shift
  grep -rilE "backendkind[.:]*${backend}\b|\.${backend}\b|\"${backend}\"" "$@" >/dev/null 2>&1
}

status=0
for shell in ios android desktop; do
  case "$shell" in
    ios) files=$(ios_files) ;;
    android) files=$(android_files) ;;
    desktop) files=$(desktop_files) ;;
  esac

  missing=()
  offered=()
  while read -r backend; do
    # shellcheck disable=SC2086
    if offers "$backend" $files; then
      offered+=("$backend")
    else
      missing+=("$backend")
    fi
  done < <(backends)

  printf '%-8s offers: %s\n' "$shell" "${offered[*]:-none}"
  if [ ${#missing[@]} -gt 0 ]; then
    printf '%-8s MISSING: %s\n' "$shell" "${missing[*]}"
    status=1
  fi
done

# ---------------------------------------------------------------------------
# Holding more than one of them.
#
# Offering all three backends and holding one server at a time are different
# capabilities, and the phones had the first without the second: signing in to a
# second server meant signing out of the first, which on Plex costs a link
# approval. Android's Settings said "soon" where the desktop had a working list.
#
# Three verbs, because a list you cannot add to, switch between or leave one of
# is not the capability.
echo
server_surface() {
  case "$1" in
    ios) printf '%s\n' "$ROOT/Sources/MozzApp/Settings/ServersView.swift" ;;
    android) printf '%s\n' "$ROOT/clients/android/app/src/main/java/com/thatcube/mozz/ui/Settings.kt" ;;
    desktop) printf '%s\n' "$ROOT/clients/desktop/Views/MainWindow.axaml" ;;
  esac
}

# What each shell calls the verb. Matched against its own screen rather than
# anywhere in the tree: a view model that can switch servers proves nothing if
# no screen offers it, which is exactly the state Android was in.
verbs_for() {
  case "$1" in
    ios) printf '%s\n' 'switchTo' 'Add a Server' 'signOut(' ;;
    android) printf '%s\n' 'onSwitch' 'Add a server' 'onSignOutOf' ;;
    desktop) printf '%s\n' 'UseServerCommand' 'Add a server' 'ForgetAccountCommand' ;;
  esac
}

for shell in ios android desktop; do
  file=$(server_surface "$shell")
  missing=()
  while read -r verb; do
    grep -qF "$verb" "$file" 2>/dev/null || missing+=("$verb")
  done < <(verbs_for "$shell")

  if [ ${#missing[@]} -eq 0 ]; then
    printf '%-8s can add, switch and leave servers\n' "$shell"
  else
    printf '%-8s CANNOT: %s\n' "$shell" "${missing[*]}"
    status=1
  fi
done

# ---------------------------------------------------------------------------
# Finding a server without being told where it is.
#
# Both local discoveries have lived in the shared core for as long as the
# backends have — Plex's GDM sweep and Jellyfin's UDP probe — and for most of
# that time neither had an FFI command, so only the Apple app, which reaches
# into the modules directly, could offer them. Everywhere else you typed an
# address copied out of a router's admin page. That is the shape
# ARCHITECTURE.md calls a half-built feature, and it is invisible from every
# other check here because the capability exists and compiles.
echo
discovery_surface() {
  case "$1" in
    ios) printf '%s\n' "$ROOT/Sources/MozzApp/Onboarding" ;;
    android) printf '%s\n' "$ROOT/clients/android/app/src/main/java/com/thatcube/mozz/ui/Onboarding.kt" ;;
    desktop) printf '%s\n' "$ROOT/clients/desktop/Views/MainWindow.axaml" ;;
  esac
}

for shell in ios android desktop; do
  file=$(discovery_surface "$shell")
  if grep -qiE "discover" "$file"/* 2>/dev/null || grep -qiE "discover" "$file" 2>/dev/null; then
    printf '%-8s offers servers found on the network\n' "$shell"
  else
    printf '%-8s CANNOT find servers on the network\n' "$shell"
    status=1
  fi
done

# ---------------------------------------------------------------------------
# Signing in without typing a password, and picking which server.
#
# Both live in the core and both were Apple-only for the same reason as
# discovery: no FFI command, so no other client could reach them. Quick Connect
# is Jellyfin's answer to the same problem Plex's link flow solves — a password
# typed into a third-party app is a password that app could have kept — and the
# Plex picker is the difference between signing in to the server you meant and
# whichever plex.tv happened to list first.
echo
for shell in ios android desktop; do
  file=$(discovery_surface "$shell")
  missing=()
  grep -qi "quick.\?connect" "$file"/* 2>/dev/null || grep -qi "quick.\?connect" "$file" 2>/dev/null \
    || missing+=("Quick Connect")
  case "$shell" in
    ios) picker="$ROOT/Sources/MozzApp/Settings/PlexLibraryPickerView.swift" ;;
    android) picker="$file" ;;
    desktop) picker="$file" ;;
  esac
  grep -qiE "plexserver" "$picker" 2>/dev/null || missing+=("Plex server picker")

  if [ ${#missing[@]} -eq 0 ]; then
    printf '%-8s offers Quick Connect and a Plex server picker\n' "$shell"
  else
    printf '%-8s CANNOT: %s\n' "$shell" "${missing[*]}"
    status=1
  fi
done

if [ "$mode" = "--check" ] && [ "$status" -ne 0 ]; then
  echo
  echo "An app is behind on servers."
  echo "The core's list is Sources/MozzCore/BackendKind.swift; the choosers are"
  echo "listed at the top of this script. Add the missing row rather than"
  echo "recording a new baseline — there is no baseline for this one."
  exit 1
fi

exit 0
