#!/bin/bash
# Envoie un fichier à la notarisation Apple.
# Code de sortie : 0 = accepté, 2 = toujours en cours chez Apple (délai dépassé), 1 = refusé ou erreur.
# Variables attendues : APPLE_API_KEY_ID, APPLE_API_ISSUER, et la clé dans $RUNNER_TEMP/AuthKey.p8.
set -uo pipefail

FILE="$1"
TIMEOUT="${2:-20m}"
KEY="$RUNNER_TEMP/AuthKey.p8"
AUTH=(--key "$KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")

# 2>&1 : en cas de délai dépassé, notarytool écrit sa réponse sur la sortie d'erreur.
RESULT=$(xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait --timeout "$TIMEOUT" --output-format json 2>&1)
echo "$RESULT"

# Lecture tolérante de la réponse (notarytool peut ajouter du texte après le JSON).
field() { printf '%s' "$RESULT" | grep -oE "\"$1\" *: *\"[^\"]*\"" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'; }
ID=$(field id)
STATUS=$(field status)

[ -n "$ID" ] && echo "submission_id=$ID" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ -z "$ID" ]; then
  echo "::error::L'envoi à Apple a échoué (aucun numéro de soumission)."
  exit 1
fi

case "$STATUS" in
  Accepted)
    echo "Notarisation acceptée."
    exit 0
    ;;
  Invalid|Rejected)
    echo "::error::Notarisation refusée ($STATUS)."
    xcrun notarytool log "$ID" "${AUTH[@]}" || true
    exit 1
    ;;
  *)
    # Délai dépassé ou « In Progress » : Apple n'a pas fini, ce n'est pas un refus.
    echo "::warning::Apple n'a pas encore terminé la notarisation (soumission $ID). Le fichier deviendra valide dès qu'Apple aura fini."
    exit 2
    ;;
esac
