#!/bin/bash
set -euo pipefail
FILE="$1"
LOG="${2:-dist/notary.json}"
: "${NOTARY_PROFILE:?Missing notarytool profile}"
ARGS=(--keychain-profile "$NOTARY_PROFILE" --wait --timeout 45m --output-format json)
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then ARGS+=(--keychain "$SIGNING_KEYCHAIN"); fi
xcrun notarytool submit "$FILE" "${ARGS[@]}" > "$LOG"
python3 - "$LOG" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept the notarization submission: ' + str(result.get('status')))
print('Notarization accepted:', result.get('id'))
PY
