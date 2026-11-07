#!/usr/bin/env bash
# Builds the release app, notarizes it, staples the ticket and writes a ZIP to dist/.
#
# Needs SLEEPYPAWS_SIGNING_IDENTITY (a Developer ID Application identity) and notary
# credentials, either:
#   SLEEPYPAWS_NOTARY_PROFILE   a saved `xcrun notarytool store-credentials` profile, or
#   APP_STORE_KEY_ID, APP_STORE_ISSUER_ID and APP_STORE_KEY_PATH   an App Store Connect API key.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SLEEPYPAWS_SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
if [[ -n ${SLEEPYPAWS_NOTARY_PROFILE:-} ]]; then
    credentials=(--keychain-profile "$SLEEPYPAWS_NOTARY_PROFILE")
elif [[ -n ${APP_STORE_KEY_ID:-} && -n ${APP_STORE_ISSUER_ID:-} && -n ${APP_STORE_KEY_PATH:-} ]]; then
    credentials=(--key "$APP_STORE_KEY_PATH" --key-id "$APP_STORE_KEY_ID" --issuer "$APP_STORE_ISSUER_ID")
else
    echo "Set SLEEPYPAWS_NOTARY_PROFILE, or APP_STORE_KEY_ID, APP_STORE_ISSUER_ID and APP_STORE_KEY_PATH" >&2
    exit 2
fi

./script/build_and_run.sh --package
bundle="$PWD/dist/Release/Sleepy Paws.app"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$bundle/Contents/Info.plist")"
zip="$PWD/dist/Sleepy-Paws-$version-macOS-arm64.zip"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
/usr/bin/ditto -c -k --keepParent "$bundle" "$temp/submit.zip"
xcrun notarytool submit "$temp/submit.zip" "${credentials[@]}" --wait --timeout 15m --output-format json >"$temp/result.json"
status="$(/usr/bin/plutil -extract status raw "$temp/result.json")"
if [[ $status != Accepted ]]; then
    cat "$temp/result.json" >&2
    id="$(/usr/bin/plutil -extract id raw "$temp/result.json" 2>/dev/null || true)"
    [[ -n $id ]] && xcrun notarytool log "$id" "${credentials[@]}" >&2 || true
    exit 1
fi
xcrun stapler staple "$bundle"
xcrun stapler validate "$bundle"
/usr/bin/codesign --verify --strict "$bundle"
/usr/sbin/spctl --assess --type execute --verbose "$bundle"
/usr/bin/ditto -c -k --keepParent "$bundle" "$temp/final.zip"
mv "$temp/final.zip" "$zip"
echo "$zip"
