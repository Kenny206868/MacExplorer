#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${APP_PATH:-dist/MacExplorer.app}"
[[ -d "$APP" && -x "$APP/Contents/MacOS/MacExplorer" ]]
plutil -lint "$APP/Contents/Info.plist"
lipo "$APP/Contents/MacOS/MacExplorer" -verify_arch arm64 x86_64
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" == com.wieslawsoltes.MacExplorer ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == 14.0 ]]
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]]
[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]
codesign --verify --deep --strict "$APP"
otool -L "$APP/Contents/MacOS/MacExplorer" | grep -q '@rpath/Sparkle.framework'
if [[ "${EXPECT_NOTARIZED:-0}" == 1 ]]; then
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi
