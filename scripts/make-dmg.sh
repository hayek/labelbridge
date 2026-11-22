#!/bin/zsh
# Packages build/LabelBridge.app into build/LabelBridge.dmg (app + Applications shortcut).
#   SIGN_ID  optional; signs the .dmg too
set -e
cd "$(dirname "$0")/.."
STAGE=build/dmg-stage
rm -rf "$STAGE" build/LabelBridge.dmg && mkdir -p "$STAGE"
ditto build/LabelBridge.app "$STAGE/LabelBridge.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "LabelBridge" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/LabelBridge.dmg >/dev/null
rm -rf "$STAGE"
if [[ -n "$SIGN_ID" && "$SIGN_ID" != "-" ]]; then codesign --force --timestamp -s "$SIGN_ID" build/LabelBridge.dmg; fi
echo "built build/LabelBridge.dmg"
