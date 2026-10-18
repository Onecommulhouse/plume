#!/bin/bash
# Publie une nouvelle version de Plume dans une Release GitHub :
#   - Plume-<build>.zip : la mise à jour téléchargée par Sparkle, signée avec la clé SPARKLE_PRIVATE_KEY ;
#   - appcast.xml       : la fiche que Plume consulte toutes les heures pour savoir s'il y a du nouveau ;
#   - Plume.dmg         : l'installeur pour une première installation.
# Usage : publish-update.sh <Plume.app> <Plume.dmg>
# Variables : SPARKLE_PRIVATE_KEY, GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, RUNNER_TEMP.
set -euo pipefail

APP="$1"
DMG="$2"
PLIST="$APP/Contents/Info.plist"

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "::warning::Secret SPARKLE_PRIVATE_KEY absent : version compilée mais pas publiée en mise à jour."
  exit 0
fi

SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
PUBKEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST")
TAG="v$SHORT-$BUILD"
ZIP="Plume-$BUILD.zip"
OUT="$RUNNER_TEMP/release"
rm -rf "$OUT" && mkdir -p "$OUT"

# 1. Archive de mise à jour (ditto garde les liens et les signatures intacts).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP"
LENGTH=$(stat -f %z "$OUT/$ZIP")

# 2. Signature EdDSA avec l'outil officiel de Sparkle (fourni avec le paquet Swift).
SIGN_UPDATE=$(find build/SourcePackages/artifacts -type f -name sign_update -path '*/bin/*' | head -1)
if [ -z "$SIGN_UPDATE" ]; then
  echo "::error::Outil sign_update de Sparkle introuvable."
  exit 1
fi
SIG=$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" -p --ed-key-file - "$OUT/$ZIP" | tail -1 | tr -d '[:space:]')

# 3. Contrôle : la signature doit correspondre à la clé publique inscrite dans l'app.
xcrun swift scripts/verify-ed-signature.swift "$PUBKEY" "$SIG" "$OUT/$ZIP"

# 4 et 5. Notes de version (le message du commit) et fiche des versions (appcast) lue par Sparkle.
git log -1 --format=%B "$GITHUB_SHA" > "$OUT/commit.txt"
python3 scripts/make-appcast.py \
  --commit "$OUT/commit.txt" --notes-out "$OUT/notes.md" --out "$OUT/appcast.xml" \
  --version "$SHORT" --build "$BUILD" --length "$LENGTH" --signature "$SIG" \
  --url "https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$ZIP"

# 6. Publication (marquée « dernière version » : c'est elle que Plume trouvera).
cp "$DMG" "$OUT/Plume.dmg"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$OUT/Plume.dmg" "$OUT/$ZIP" "$OUT/appcast.xml" --clobber
else
  gh release create "$TAG" "$OUT/Plume.dmg" "$OUT/$ZIP" "$OUT/appcast.xml" \
    --title "Plume $SHORT ($BUILD)" --notes-file "$OUT/notes.md" --target "$GITHUB_SHA" --latest
fi

{
  echo "## Mise à jour publiée : Plume $SHORT ($BUILD)"
  echo
  echo "Les Plume installées la récupéreront d'elles-mêmes dans l'heure."
  echo
  echo "Installeur pour une première installation : https://github.com/$GITHUB_REPOSITORY/releases/latest/download/Plume.dmg"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "Publié : $TAG"
