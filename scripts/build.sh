#!/bin/zsh
# Release build of LabelBridge.app (universal arm64 + x86_64) into ./build.
#   SIGN_ID  code-signing identity, e.g. "Developer ID Application: Your Name (TEAMID)"
#            (default "-" = ad-hoc, for local use only)
set -e
cd "$(dirname "$0")/.."
SIGN_ID=${SIGN_ID:--}
APP=build/LabelBridge.app

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf build/LabelBridge.app && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp "$BIN/LabelBridgeApp" "$APP/Contents/MacOS/LabelBridge"
# The CLI lives in Helpers: "labelbridge" and "LabelBridge" collide on case-insensitive volumes.
cp "$BIN/labelbridge" "$APP/Contents/Helpers/labelbridge"
cp -R Resources/Bundle/ "$APP/Contents/Resources/"

if [[ "$SIGN_ID" == "-" ]]; then
  codesign --force -s - "$APP/Contents/Helpers/labelbridge"
  codesign --force -s - "$APP"
else
  codesign --force --options runtime --timestamp -s "$SIGN_ID" "$APP/Contents/Helpers/labelbridge"
  codesign --force --options runtime --timestamp --entitlements Resources/LabelBridge.entitlements -s "$SIGN_ID" "$APP"
fi
codesign --verify --strict --deep "$APP"
lipo -archs "$APP/Contents/MacOS/LabelBridge"
echo "built $APP"
