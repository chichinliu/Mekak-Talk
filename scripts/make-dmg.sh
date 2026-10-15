#!/bin/bash
# Builds the app, packs it into a signed DMG, notarizes and staples it.
# Notarization reads Apple credentials from a notarytool keychain profile:
#   xcrun notarytool store-credentials mekak-notary --key ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
NOTARY_PROFILE="${NOTARY_PROFILE:-mekak-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="$PROJECT_DIR/dist/Mekak Talk.app"
DMG="$PROJECT_DIR/dist/Mekak-Talk-$VERSION.dmg"
if [[ "${SKIP_BUILD:-0}" != 1 ]]; then bash scripts/build-app.sh; fi
source "$PROJECT_DIR/scripts/signing-identity.sh"
select_signing_identity
if ! security find-identity -v -p codesigning | grep "$SIGNING_IDENTITY" | grep -q "Developer ID Application"; then
    printf '發佈需要 Developer ID Application 憑證。\n' >&2; exit 1
fi
STAGE="$(mktemp -d "$PROJECT_DIR/.build/dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Mekak Talk" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
printf 'DMG: %s\n' "$DMG"
