#!/bin/zsh
# Builds Audra.app (release, Apple Silicon) into ./build.
#
#   scripts/build-app.sh [--open]
#
# Environment (all optional):
#   VERSION_OVERRIDE   Marketing version; defaults to the VERSION file.
#   BUILD_NUMBER       CFBundleVersion; defaults to the git commit count.
#   CODESIGN_IDENTITY  e.g. "Developer ID Application: Name (TEAMID)". Defaults to ad-hoc ("-").
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION_OVERRIDE:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP=build/Audra.app

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "✗ Versão inválida em VERSION: '$VERSION' (use MAJOR.MINOR.PATCH)" >&2
  exit 1
fi

echo "→ Compilando Audra $VERSION ($BUILD_NUMBER), release, arm64…"
swift build --package-path app -c release --arch arm64
BIN="$(swift build --package-path app -c release --arch arm64 --show-bin-path)/Audra"

echo "→ Montando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Audra"
cp app/Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
  echo "→ Gerando ícone"
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "→ Copiando localizações"
cp -R app/Resources/Localization/*.lproj "$APP/Contents/Resources/"

echo "→ Compilando cores (AccentColor)"
xcrun actool app/Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --accent-color AccentColor --output-partial-info-plist build/assets-info.plist >/dev/null
/usr/libexec/PlistBuddy -c "Add :NSAccentColorName string AccentColor" "$APP/Contents/Info.plist" 2>/dev/null || true

if [[ "$IDENTITY" == "-" ]]; then
  echo "→ Assinando (ad hoc — sem certificado de desenvolvedor)"
  codesign --force --deep --options runtime --sign - "$APP"
else
  echo "→ Assinando com “$IDENTITY”"
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ Pronto: $APP (v$VERSION, build $BUILD_NUMBER)"
[[ "${1:-}" == "--open" ]] && open "$APP"
exit 0
