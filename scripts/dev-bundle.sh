#!/bin/zsh
# Debug build of LabelBridge.app for local testing (current arch only).
#   SIGN_ID: signing identity (default "-" ad-hoc; use a stable identity so Bluetooth permission survives rebuilds)
set -e
cd "$(dirname "$0")/.."
swift build
APP=build/dev/LabelBridge.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp .build/debug/LabelBridgeApp "$APP/Contents/MacOS/LabelBridge"
# The CLI lives in Helpers: "labelbridge" and "LabelBridge" are the same name on case-insensitive volumes.
cp .build/debug/labelbridge "$APP/Contents/Helpers/labelbridge"
[[ -d Resources/Bundle ]] && cp -R Resources/Bundle/ "$APP/Contents/Resources/"
codesign --force -s "${SIGN_ID:--}" "$APP/Contents/Helpers/labelbridge"
codesign --force -s "${SIGN_ID:--}" "$APP"
echo "$APP"
