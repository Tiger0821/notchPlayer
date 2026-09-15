#!/bin/bash
# Builds build/NotchLyrics.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/NotchLyrics.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchLyrics" "$APP/Contents/MacOS/NotchLyrics"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: fine for personal use. macOS may ask for Music automation permission again after a rebuild.
codesign --force --sign - "$APP"

echo "Built $APP"
