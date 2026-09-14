#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VERSION:?Missing version}"
: "${SPARKLE_PRIVATE_KEY:?Missing MacExplorer-specific Sparkle private key}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
ARTIFACTS="${1:-dist}"
TOOLS=.build/artifacts/sparkle/Sparkle/bin
VERIFIER=.build/release-tools/verify-signature
[[ -x "$TOOLS/generate_appcast" && -x "$VERIFIER" ]] || { echo 'Resolve Sparkle and compile verify-signature before loading credentials.' >&2; exit 1; }
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ARTIFACTS/MacExplorer-$VERSION-universal.zip" "$STAGE/"
cp .github/RELEASE_NOTES.md "$STAGE/MacExplorer-$VERSION-universal.md"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/generate_appcast" --ed-key-file - --maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/wieslawsoltes/MacExplorer/releases/download/v$VERSION/" --link https://github.com/wieslawsoltes/MacExplorer "$STAGE"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/sign_update" --ed-key-file - --verify "$STAGE/appcast.xml"
python3 scripts/verify-appcast.py "$STAGE/appcast.xml" "$ARTIFACTS/MacExplorer-$VERSION-universal.zip" "$VERSION" "$VERIFIER"
cp "$STAGE/appcast.xml" "$ARTIFACTS/appcast.xml"
