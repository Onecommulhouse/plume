#!/bin/bash
# Envoie un fichier à la notarisation Apple et affiche le rapport en cas de refus.
# Variables attendues : APPLE_API_KEY_ID, APPLE_API_ISSUER, et la clé dans $RUNNER_TEMP/AuthKey.p8.
set -euo pipefail

FILE="$1"
KEY="$RUNNER_TEMP/AuthKey.p8"

RESULT=$(xcrun notarytool submit "$FILE" \
  --key "$KEY" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER" \
  --wait --timeout 30m \
  --output-format json)
echo "$RESULT"

ID=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')
STATUS=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')

if [ "$STATUS" != "Accepted" ]; then
  echo "::error::Notarisation refusée ($STATUS)."
  if [ -n "$ID" ]; then
    xcrun notarytool log "$ID" --key "$KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" || true
  fi
  exit 1
fi
echo "Notarisation acceptée."
