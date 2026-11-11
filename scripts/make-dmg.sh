#!/bin/zsh
# Packages build/Audra.app into a compressed disk image with an Applications shortcut,
# then writes a SHA-256 checksum next to it.
#
#   scripts/make-dmg.sh
#
# Output: build/release/Audra.dmg and build/release/Audra.dmg.sha256
#
# Optional (Developer ID distribution):
#   CODESIGN_IDENTITY  signs the disk image.
#   NOTARY_PROFILE     keychain profile created with `xcrun notarytool store-credentials`;
#                      when set, the image is notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Audra.app
OUT=build/release
DMG="$OUT/Audra.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

[[ -d "$APP" ]] || { echo "✗ $APP não existe. Rode scripts/build-app.sh antes." >&2; exit 1; }

STAGE="$(mktemp -d)/Audra"
mkdir -p "$STAGE" "$OUT"
ditto "$APP" "$STAGE/Audra.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$DMG.sha256"

echo "→ Criando imagem de disco (Audra $VERSION)…"
hdiutil create -quiet -volname "Audra $VERSION" -srcfolder "$STAGE" -fs APFS -format ULFO -ov "$DMG"
rm -rf "$(dirname "$STAGE")"

if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY}" != "-" ]]; then
  echo "→ Assinando imagem de disco"
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "→ Enviando para notarização da Apple…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

hdiutil verify -quiet "$DMG"
( cd "$OUT" && shasum -a 256 Audra.dmg > Audra.dmg.sha256 )
echo "✓ $DMG ($(du -h "$DMG" | cut -f1)) · sha256 $(cut -d' ' -f1 "$DMG.sha256")"
