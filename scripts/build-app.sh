#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
# VARIANT=dev builds "Mekak Talk Dev": a debug build with its own bundle identifier and settings.
VARIANT="${VARIANT:-release}"
APP_NAME="Mekak Talk"; CONFIGURATION=release
if [[ "$VARIANT" == dev ]]; then APP_NAME="Mekak Talk Dev"; CONFIGURATION=debug; fi
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
ensure_app_stopped() {
    local app_pid command_path
    while read -r app_pid; do
        command_path="$(ps -p "$app_pid" -o comm= 2>/dev/null || true)"
        if [[ "$command_path" == "$APP_DIR/Contents/MacOS/MekakTalk" ]]; then
            printf '請先關閉權限指引並完全結束 %s，再執行建置。\n' "$APP_NAME" >&2
            return 1
        fi
    done < <(pgrep -x MekakTalk || true)
}
ensure_app_stopped
source "$PROJECT_DIR/scripts/signing-identity.sh"
select_signing_identity
bash scripts/build-whisper-runtime.sh
bash scripts/build-transcribe-runtime.sh
swift build -c "$CONFIGURATION"
BINARY_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
PACKAGE_STAGE="$(mktemp -d "$PROJECT_DIR/.build/app-package.XXXXXX")"
STAGED_APP="$PACKAGE_STAGE/$APP_NAME.app"
cleanup_package() {
    if [[ -d "$PACKAGE_STAGE/previous.app" && ! -e "$APP_DIR" ]]; then
        mv "$PACKAGE_STAGE/previous.app" "$APP_DIR"
    fi
    rm -rf "$PACKAGE_STAGE"
}
trap cleanup_package EXIT
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$STAGED_APP/Contents/Helpers" "$PROJECT_DIR/dist"
cp "$BINARY_DIR/MekakTalk" "$STAGED_APP/Contents/MacOS/MekakTalk"
cp .build/whisper-runtime/build/bin/whisper-cli "$STAGED_APP/Contents/Helpers/whisper-cli"
cp .build/whisper-runtime/source/LICENSE "$STAGED_APP/Contents/Resources/Whisper-LICENSE.txt"
cp .build/transcribe-runtime/transcribe-cli "$STAGED_APP/Contents/Helpers/transcribe-cli"
cp .build/transcribe-runtime/source/LICENSE "$STAGED_APP/Contents/Resources/Transcribe-LICENSE.txt"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
if [[ "$VARIANT" == dev ]]; then
    plist="$STAGED_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist").dev" \
        -c "Set :CFBundleName $APP_NAME" -c "Set :CFBundleDisplayName $APP_NAME" "$plist"
fi
cat Sources/MekakTalk/DesignTokens.swift scripts/make-icon.swift > "$PACKAGE_STAGE/make-icon.swift"
swift "$PACKAGE_STAGE/make-icon.swift" "$STAGED_APP/Contents/Resources/AppIcon.icns"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" --options runtime "$STAGED_APP/Contents/Helpers/whisper-cli"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" --options runtime "$STAGED_APP/Contents/Helpers/transcribe-cli"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" --options runtime --entitlements Resources/MekakTalk.entitlements "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
ensure_app_stopped
if [[ -e "$APP_DIR" ]]; then mv "$APP_DIR" "$PACKAGE_STAGE/previous.app"; fi
mv "$STAGED_APP" "$APP_DIR"
save_signing_identity
printf 'Built: %s\n' "$APP_DIR"
