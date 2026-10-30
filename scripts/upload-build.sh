#!/usr/bin/env bash
#
# Export a Release archive and upload it to App Store Connect (TestFlight).
# Same mechanism as Aangan's scripts/upload-build.sh: an App Store Connect API
# key that the owner installed once, read only by Apple's tooling.
#
#   ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
#
# This script never receives, prints or logs the key. Only the key ID and the
# issuer ID are passed in, and neither is a secret on its own.
#
# Setup (once): App Store Connect -> Users and Access -> Integrations ->
# App Store Connect API -> generate a key (App Manager role). Apple lets you
# download the .p8 once; move it to the path above and chmod 600 it.
#
# Usage:
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<uuid> \
#     scripts/upload-build.sh "~/Library/Developer/Xcode/Archives/<date>/Sangrah 1.0 (2).xcarchive"
#
#   Add --validate-only to check the binary without uploading.
#
# Every upload consumes a build number for good (App Store Connect rejects a
# reused one, ITMS-90062), so bump CURRENT_PROJECT_VERSION in project.pbxproj
# and CFBundleVersion in iOS/Commonplace/Info.plist before archiving.
set -euo pipefail

ARCHIVE="${1:?usage: upload-build.sh <path-to.xcarchive> [--validate-only]}"
MODE="${2:-}"
: "${ASC_KEY_ID:?set ASC_KEY_ID (the key ID, not the key)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (from App Store Connect -> Integrations)}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$ARCHIVE" ] || { echo "error: no archive at $ARCHIVE" >&2; exit 1; }

KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$KEY_PATH" ] || { echo "error: no API key at $KEY_PATH (see setup notes above)" >&2; exit 1; }

# plutil -p only; `plutil -extract ... <file>` without `-o -` rewrites the file.
APP_PLIST="$ARCHIVE/Products/Applications/Commonplace.app/Info.plist"
VERSION=$(plutil -p "$APP_PLIST" | awk -F'"' '/CFBundleShortVersionString/ {print $4}')
BUILD=$(plutil -p "$APP_PLIST" | awk -F'"' '/"CFBundleVersion"/ {print $4}')
echo "Shipping Sangrah $VERSION (build $BUILD) from $ARCHIVE"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

echo "-> exporting (signs with the App Store profile; creates it if needed)"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$REPO/iOS/ExportOptions.plist" \
    -exportPath "$OUT" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA=$(find "$OUT" -maxdepth 2 -name '*.ipa' | head -1)
[ -n "$IPA" ] || { echo "error: export produced no .ipa" >&2; exit 1; }
echo "-> exported $(basename "$IPA") ($(du -h "$IPA" | cut -f1))"

echo "-> validating"
xcrun altool --validate-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [ "$MODE" = "--validate-only" ]; then
    echo "Validated. Nothing uploaded (--validate-only)."
    exit 0
fi

echo "-> uploading"
xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo "Uploaded Sangrah $VERSION ($BUILD). It appears in TestFlight after processing."
