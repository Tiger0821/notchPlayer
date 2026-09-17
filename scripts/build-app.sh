#!/bin/bash
# Builds build/NotchLyrics.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/NotchLyrics.app"

# Replacing the bundle under a running copy invalidates that process's code signature, and macOS then asks
# again for permissions it has already been granted. Quit it first, and put it back afterwards.
RELAUNCH=false
if pgrep -x NotchLyrics >/dev/null; then
  RELAUNCH=true
  osascript -e 'quit app "NotchLyrics"' 2>/dev/null || pkill -x NotchLyrics || true
  for _ in $(seq 1 20); do pgrep -x NotchLyrics >/dev/null || break; sleep 0.1; done
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchLyrics" "$APP/Contents/MacOS/NotchLyrics"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sign with a real identity when there is one: an ad-hoc signature changes with every build, so macOS treats
# each build as a new app and drops the Automation and Accessibility permissions it was granted.
# Extended attributes (Finder info, quarantine) make codesign refuse the bundle, and a synced folder such as
# iCloud Drive keeps adding them back, so clear and sign together and try again if it loses the race. An
# unsigned build is worth failing over: macOS treats it as a different app and drops granted permissions.
# The identity list is read in full before searching it: awk stopping at the first match can kill `security`
# with SIGPIPE, and under pipefail that would end the whole script here without a word.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
IDENTITY="${CODESIGN_IDENTITY:-$(awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}' <<< "$IDENTITIES")}"

sign() {
  xattr -c "$APP" 2>/dev/null || true
  xattr -cr "$APP" 2>/dev/null || true
  if [ -n "$IDENTITY" ]; then
    # A real identity turns on the hardened runtime, which needs the entitlements to reach Music and its audio.
    codesign --force --options runtime --entitlements Resources/NotchLyrics.entitlements --sign "$IDENTITY" "$APP" 2>&1
  else
    codesign --force --sign - "$APP" 2>&1
  fi
}

for attempt in 1 2 3; do
  OUTPUT="$(sign)" && break
  echo "Signing attempt $attempt failed: $OUTPUT"
  sleep 1
done

# Read the signature first: piped straight into `grep -q`, codesign can die of SIGPIPE when grep stops reading,
# and under pipefail that failure makes an ad-hoc signature look like a real one.
SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1)"
if grep -q "Signature=adhoc" <<< "$SIGNATURE"; then
  if [ -n "$IDENTITY" ]; then
    echo "Failed to sign with $IDENTITY; macOS will ask for permissions again." >&2
    exit 1
  fi
  echo "Ad-hoc signed: permissions reset on each rebuild. Set CODESIGN_IDENTITY to keep them."
else
  echo "Signed as: ${IDENTITY:-unknown}"
fi

echo "Built $APP"

if [ "$RELAUNCH" = true ]; then
  open "$APP"
  echo "Relaunched"
fi
