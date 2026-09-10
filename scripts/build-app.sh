#!/usr/bin/env bash
set -euo pipefail

# Builds the SwiftPM executable and wraps it in a .app bundle. The bundle is what
# matters: macOS only shows the Bluetooth permission prompt to a signed app whose
# Info.plist carries NSBluetoothAlwaysUsageDescription.

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="Nommo Control"
BUNDLE=".build/${APP_NAME}.app"

swift build -c "$CONFIG"

BINARY=".build/${CONFIG}/RazerNommoControl"
if [[ ! -f "$BINARY" ]]; then
    echo "Binaire introuvable : $BINARY" >&2
    exit 1
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/RazerNommoControl"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc signature: enough for local use, and gives TCC a stable identity so the
# Bluetooth permission is remembered between launches.
codesign --force --sign - "$BUNDLE"

echo "Construit : $BUNDLE"
echo "Lancer avec : open \"$BUNDLE\""
