#!/bin/bash
set -euo pipefail
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then security delete-keychain "$SIGNING_KEYCHAIN" 2>/dev/null || true; fi
if [[ -n "${SIGNING_TEMP:-}" && -d "$SIGNING_TEMP" ]]; then rm -rf "$SIGNING_TEMP"; fi
