#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$PROJECT_DIR/dist/Mekak Talk.app}"
mkdir -p "$PROJECT_DIR/.build"
PROBE_DIR="$(mktemp -d "$PROJECT_DIR/.build/signing-probe.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT

# Replay an update with changed signed contents, without launching either copy.
ditto "$APP_DIR" "$PROBE_DIR/original.app"
ditto "$APP_DIR" "$PROBE_DIR/updated.app"
SIGNATURE_INFO="$(codesign --display --verbose=2 "$APP_DIR" 2>&1)"
SIGNING_IDENTITY="$(printf '%s\n' "$SIGNATURE_INFO" | awk '/^Authority=/ { sub(/^Authority=/, ""); print; exit }')"
if [[ -z "$SIGNING_IDENTITY" ]]; then SIGNING_IDENTITY="-"; fi
CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROBE_DIR/updated.app/Contents/Info.plist")"
PROBE_VERSION=999999
if [[ "$CURRENT_VERSION" == "$PROBE_VERSION" ]]; then PROBE_VERSION=999998; fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PROBE_VERSION" "$PROBE_DIR/updated.app/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --entitlements "$PROJECT_DIR/Resources/MekakTalk.entitlements" "$PROBE_DIR/updated.app"

requirement() {
    codesign --display -r- "$1" 2>&1 | awk '/designated => / { sub(/^.*designated => /, ""); print; exit }'
}
ORIGINAL_REQUIREMENT="$(requirement "$PROBE_DIR/original.app")"
UPDATED_REQUIREMENT="$(requirement "$PROBE_DIR/updated.app")"
[[ -n "$ORIGINAL_REQUIREMENT" && -n "$UPDATED_REQUIREMENT" ]] || { printf 'FAIL: Missing signing requirement.\n' >&2; exit 1; }
if ! codesign --verify --strict --verbose=1 -R "=$ORIGINAL_REQUIREMENT" "$PROBE_DIR/updated.app"; then
    printf 'FAIL: Updated app no longer matches the identity used by the original permission grant.\n' >&2
    exit 1
fi
codesign --verify --strict --verbose=1 -R "=$UPDATED_REQUIREMENT" "$PROBE_DIR/original.app"
printf 'PASS: Both versions satisfy each other\047s signing requirements.\n'
