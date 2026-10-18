#!/bin/bash
# Re-signe Sparkle (le module de mise à jour) avec le certificat Developer ID de ONE COM, puis l'app.
# Apple refuse la notarisation si un seul programme de l'app n'est pas signé avec notre certificat.
# Usage : sign-sparkle.sh <Plume.app> <identité> <trousseau> <fichier d'autorisations>
set -euo pipefail

APP="$1"
IDENTITY="$2"
KEYCHAIN="$3"
ENTITLEMENTS="$4"

FW="$APP/Contents/Frameworks/Sparkle.framework"
V="$FW/Versions/Current"
SIGN=(codesign --force --sign "$IDENTITY" --options runtime --timestamp --keychain "$KEYCHAIN")

if [ ! -d "$FW" ]; then
  echo "::error::Sparkle.framework est absent de l'app."
  exit 1
fi

# De l'intérieur vers l'extérieur : services, programmes auxiliaires, module, puis l'app.
for xpc in "$V"/XPCServices/*.xpc; do
  [ -d "$xpc" ] && "${SIGN[@]}" --preserve-metadata=entitlements "$xpc"
done
[ -e "$V/Autoupdate" ] && "${SIGN[@]}" "$V/Autoupdate"
[ -d "$V/Updater.app" ] && "${SIGN[@]}" "$V/Updater.app"
"${SIGN[@]}" "$FW"
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"

echo "Sparkle et Plume signés avec : $IDENTITY"
