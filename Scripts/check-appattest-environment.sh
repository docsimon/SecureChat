#!/usr/bin/env bash
#
# check-appattest-environment.sh
#
# Confirms which App Attest environment (development/production) the
# AppAttestTestApp target's most recent DEVICE build was actually signed
# with — automates the manual codesign check from account-keys-reference.md.
#
# This does NOT build for you. Build AppAttestTestApp for a real device in
# Xcode first (Simulator builds strip this entitlement entirely, which this
# script will tell you if you point it at one by mistake). Run this
# afterward to confirm what actually got signed.
#
# Usage:
#   ./Scripts/check-appattest-environment.sh
#
# Run from the repository root (where SecureChat.xcodeproj lives).

set -euo pipefail

PROJECT="SecureChat.xcodeproj"
SCHEME="AppAttestTestApp"
ENTITLEMENT_KEY="com.apple.developer.devicecheck.appattest-environment"

if [[ ! -d "$PROJECT" ]]; then
    echo "error: $PROJECT not found in the current directory." >&2
    echo "Run this script from the repository root." >&2
    exit 1
fi

echo "Looking up the built app bundle path for a device build..."
APP_PATH=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -showBuildSettings -destination 'generic/platform=iOS' 2>/dev/null \
    | awk -F ' = ' '/CODESIGNING_FOLDER_PATH/ { print $2; exit }')

if [[ -z "$APP_PATH" ]]; then
    echo "error: could not determine the build path from xcodebuild." >&2
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: no build found at:" >&2
    echo "  $APP_PATH" >&2
    echo "Build $SCHEME for a real device in Xcode first, then re-run this." >&2
    exit 1
fi

echo "Inspecting: $APP_PATH"
echo

TMP_PLIST="$(mktemp -t appattest-entitlements).plist"
trap 'rm -f "$TMP_PLIST"' EXIT

if ! codesign -d --entitlements :- "$APP_PATH" > "$TMP_PLIST" 2>/dev/null; then
    echo "error: codesign failed — is the app actually signed?" >&2
    exit 1
fi

if [[ ! -s "$TMP_PLIST" ]]; then
    echo "error: codesign returned no entitlements at all." >&2
    echo "If this was a Simulator build, that's expected — capability" >&2
    echo "entitlements are stripped there. Build for a real device instead." >&2
    exit 1
fi

echo "--- Full entitlements ---"
cat "$TMP_PLIST"
echo "-------------------------"
echo

ENV_VALUE="$(/usr/libexec/PlistBuddy -c "Print :$ENTITLEMENT_KEY" "$TMP_PLIST" 2>/dev/null || true)"

case "$ENV_VALUE" in
    development)
        echo "✅ App Attest environment: development — this build won't touch your production key budget."
        ;;
    production)
        echo "⚠️  App Attest environment: production — tapping Attest on this build WILL spend real production budget."
        ;;
    *)
        echo "⚠️  '$ENTITLEMENT_KEY' not found in entitlements."
        echo "    Check Signing & Capabilities for $SCHEME in Xcode — App Attest may not be configured for this build."
        exit 1
        ;;
esac
