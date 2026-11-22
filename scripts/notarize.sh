#!/bin/zsh
# Notarizes and staples build/LabelBridge.dmg.
# Credentials (either):
#   NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`>
# or an App Store Connect API key:
#   ASC_KEY_PATH=/path/AuthKey_XXXX.p8  ASC_KEY_ID=XXXX  ASC_ISSUER_ID=xxxxxxxx-...
set -e
cd "$(dirname "$0")/../build"
if [[ -n "$NOTARY_PROFILE" ]]; then
  auth=(--keychain-profile "$NOTARY_PROFILE")
else
  : ${ASC_KEY_PATH:?set NOTARY_PROFILE or ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID}
  auth=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
fi
xcrun notarytool submit LabelBridge.dmg "${auth[@]}" --wait
xcrun stapler staple LabelBridge.dmg
spctl -a -vv -t open --context context:primary-signature LabelBridge.dmg
echo "ready: build/LabelBridge.dmg"
