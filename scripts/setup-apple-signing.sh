#!/bin/bash
# Called only after verifying a previously built artifact in a protected release job.
set -euo pipefail
: "${DEVELOPER_ID_P12_BASE64:?Missing certificate}"
: "${DEVELOPER_ID_P12_PASSWORD:?Missing certificate password}"
: "${DEVELOPER_ID_IDENTITY:?Missing Developer ID identity}"
: "${APP_STORE_CONNECT_KEY_P8:?Missing App Store Connect API key}"
: "${APP_STORE_CONNECT_KEY_ID:?Missing API key ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Missing issuer ID}"
[[ "$DEVELOPER_ID_IDENTITY" == 'Developer ID Application:'* ]] || exit 1
DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/macexplorer-signing.XXXXXX")"
chmod 700 "$DIR"
KEYCHAIN="$DIR/release.keychain-db"
PASSWORD="$(openssl rand -base64 32)"
printf 'SIGNING_TEMP=%s\nSIGNING_KEYCHAIN=%s\nSIGNING_IDENTITY=%s\nNOTARY_PROFILE=MacExplorerNotary\n' "$DIR" "$KEYCHAIN" "$DEVELOPER_ID_IDENTITY" >> "$GITHUB_ENV"
export SIGNING_TEMP="$DIR" SIGNING_KEYCHAIN="$KEYCHAIN"
trap 'if [[ $? != 0 ]]; then security delete-keychain "$KEYCHAIN" 2>/dev/null || true; rm -rf "$DIR"; fi' EXIT
printf '%s' "$DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 --decode > "$DIR/certificate.p12"
printf '%s' "$APP_STORE_CONNECT_KEY_P8" > "$DIR/AuthKey.p8"
chmod 600 "$DIR/certificate.p12" "$DIR/AuthKey.p8"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$DIR/certificate.p12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
xcrun notarytool store-credentials MacExplorerNotary --keychain "$KEYCHAIN" --key "$DIR/AuthKey.p8" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID"
rm -f "$DIR/certificate.p12" "$DIR/AuthKey.p8"
