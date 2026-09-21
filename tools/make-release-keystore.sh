#!/usr/bin/env bash
#
# Create the Android release signing keystore.
#
# WHY THIS IS A SCRIPT AND NOT A LINE IN THE DOCS
#
# It was a line in the docs, and it did not work: macOS ships no Java, so a bare
# `keytool` gives "Unable to locate a Java Runtime" and points at java.com —
# which is the wrong answer, because a JDK is already on the machine inside
# Android Studio. This is the same trap that makes Gradle builds fail here
# without JAVA_HOME, one tool over.
#
# This script does NOT handle passwords. keytool prompts for them directly and
# they never pass through here, through a shell argument, or through any log.
#
#   tools/make-release-keystore.sh [path]      default: ~/Documents/mozz-release.jks
#
set -euo pipefail

DEST="${1:-$HOME/Documents/mozz-release.jks}"

find_keytool() {
  if command -v keytool >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
    command -v keytool; return
  fi
  for home in \
    "${JAVA_HOME:-}" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home
  do
    [ -n "$home" ] && [ -x "$home/bin/keytool" ] && { echo "$home/bin/keytool"; return; }
  done
  return 1
}

KEYTOOL="$(find_keytool)" || {
  echo "No JDK found. Install Android Studio, or set JAVA_HOME to a JDK." >&2
  exit 1
}
echo "▸ Using ${KEYTOOL}"

if [ -e "$DEST" ]; then
  # Never silently overwrite. The existing file may be the only copy of the key
  # that every installed copy of Mozz is signed with; replacing it would end the
  # ability to update any of them, with nothing to undo.
  echo "A keystore already exists at ${DEST}." >&2
  echo "Refusing to overwrite it — if this is the real signing key, replacing it" >&2
  echo "would permanently break updates for every existing install." >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
"$KEYTOOL" -genkeypair -v \
  -keystore "$DEST" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias mozz

chmod 600 "$DEST"

cat <<NOTE

✓ ${DEST}

BACK THIS FILE UP, along with both passwords, somewhere you will still have in
five years. Android identifies an app by its signing key: if this is lost, no
existing install of Mozz can ever be updated again. Every user would have to
uninstall and lose their downloads and sign-ins. There is no recovery process.

Next, add four repository secrets (Settings > Secrets and variables > Actions):

  ANDROID_KEYSTORE_BASE64     base64 -i "${DEST}" | pbcopy
  ANDROID_KEYSTORE_PASSWORD   the keystore password you just chose
  ANDROID_KEY_ALIAS           mozz
  ANDROID_KEY_PASSWORD        the key password (same as above if you pressed
                              Return when keytool offered to reuse it)

Then tag a release — see docs/RELEASING.md.
NOTE
