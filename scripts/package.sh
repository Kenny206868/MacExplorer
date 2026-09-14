#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be MAJOR.MINOR.PATCH' >&2; exit 1; }
export VERSION SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
APP=dist/MacExplorer.app
if [[ -n "${NOTARY_PROFILE:-}" && "${SIGNING_IDENTITY:-}" != 'Developer ID Application:'* ]]; then echo 'Notarization requires Developer ID Application signing.' >&2; exit 1; fi
if [[ "${USE_PREBUILT_APP:-0}" != 1 ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/"{MacOS,Resources,Frameworks}
  cp "$BIN/MacExplorer" "$APP/Contents/MacOS/MacExplorer"
  ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
  cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
  cp LICENSE "$APP/Contents/Resources/MacExplorer-LICENSE.txt"
  python3 scripts/make-info.py "$APP/Contents/Info.plist"
  swift scripts/icon.swift "$APP/Contents/Resources"
else
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
  lipo "$APP/Contents/MacOS/MacExplorer" -verify_arch arm64 x86_64
  codesign --verify --deep --strict "$APP"
fi
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  SIGN=(--force --timestamp --options runtime --sign "$SIGNING_IDENTITY")
  if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then SIGN+=(--keychain "$SIGNING_KEYCHAIN"); fi
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for COMPONENT in "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$SPARKLE"/XPCServices/*.xpc "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign "${SIGN[@]}" --preserve-metadata=entitlements "$COMPONENT"
  done
  codesign "${SIGN[@]}" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/notary-app.zip"
  bash scripts/notarize.sh "$STAGE/notary-app.zip" dist/notary-app.json
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  STATUS='Developer ID-signed and Apple notarized'
elif [[ -n "${SIGNING_IDENTITY:-}" ]]; then STATUS='Developer ID-signed; not Apple notarized'
else STATUS='Ad-hoc signed development build; not Apple notarized'; fi
printf 'MacExplorer %s\nSigning: %s\n\n' "$VERSION" "$STATUS" > dist/INSTALL.md
cat INSTALL.md >> dist/INSTALL.md
rm -f "$STAGE/notary-app.zip"
ditto "$APP" "$STAGE/MacExplorer.app"
ln -s /Applications "$STAGE/Applications"
cp dist/INSTALL.md "$STAGE/Read Me.txt"
hdiutil create -volname MacExplorer -srcfolder "$STAGE" -ov -format UDZO "dist/MacExplorer-$VERSION-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/MacExplorer-$VERSION-universal.zip"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  codesign "${SIGN[@]}" "dist/MacExplorer-$VERSION-universal.dmg"
  bash scripts/notarize.sh "dist/MacExplorer-$VERSION-universal.dmg" dist/notary-dmg.json
  xcrun stapler staple "dist/MacExplorer-$VERSION-universal.dmg"
  xcrun stapler validate "dist/MacExplorer-$VERSION-universal.dmg"
fi
(cd dist && shasum -a 256 "MacExplorer-$VERSION-universal.zip" "MacExplorer-$VERSION-universal.dmg" > SHA256SUMS)
