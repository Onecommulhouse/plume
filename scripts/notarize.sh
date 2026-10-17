#!/bin/bash
# Envoie un fichier à la notarisation Apple.
# Code de sortie : 0 = accepté, 2 = toujours en cours chez Apple (délai dépassé), 1 = refusé ou erreur.
# Variables attendues : APPLE_API_KEY_ID, APPLE_API_ISSUER, et la clé dans $RUNNER_TEMP/AuthKey.p8.
set -uo pipefail

FILE="$1"
TIMEOUT="${2:-20m}"
KEY="$RUNNER_TEMP/AuthKey.p8"
AUTH=(--key "$KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")

RESULT=$(xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait --timeout "$TIMEOUT" --output-format json)
echo "$RESULT"

field() { printf '%s' "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1', ''))" 2>/dev/null; }
ID=$(field id)
STATUS=$(field status)
MESSAGE=$(field message)

[ -n "$ID" ] && echo "submission_id=$ID" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ "$STATUS" = "Accepted" ]; then
  echo "Notarisation acceptée."
  exit 0
fi

if [ -z "$STATUS" ] && printf '%s' "$MESSAGE" | grep -qi "timeout"; then
  echo "::warning::Apple n'a pas encore terminé la notarisation (soumission $ID). Le fichier deviendra valide dès qu'Apple aura fini."
  exit 2
fi

echo "::error::Notarisation refusée (${STATUS:-erreur})."
if [ -n "$ID" ]; then
  xcrun notarytool log "$ID" "${AUTH[@]}" || true
fi
exit 1
