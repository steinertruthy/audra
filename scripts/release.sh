#!/bin/zsh
# Builds and verifies the release artifacts for the version in VERSION.
#
#   scripts/release.sh            # test, build Audra.app, package build/release/Audra.dmg + .sha256
#   scripts/release.sh --draft    # …and create a *draft* GitHub release with the artifacts (needs `gh`)
#
# Publishing is always a manual step: review the draft on GitHub, then click “Publish release”.
# Normally the release workflow (.github/workflows/release.yml) does this when a tag is pushed;
# this script is the local equivalent.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "✗ CHANGELOG.md não tem a seção [$VERSION]" >&2; exit 1; }

echo "→ Testes"
swift test --package-path app 2>&1 | tail -1

scripts/build-app.sh
scripts/make-dmg.sh

NOTES="build/release/notes.md"
awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {f=1; next} /^## \[/{f=0} f' CHANGELOG.md | sed -e '/^\[.*\]: http/d' > "$NOTES"
cat >> "$NOTES" <<NOTES

---

**Instalação:** abra o \`Audra.dmg\` e arraste o Audra para Aplicativos. Requer macOS 26 (Tahoe) em um Mac com Apple Silicon.
Esta versão não é notarizada pela Apple: na primeira abertura, vá em Ajustes do Sistema › Privacidade e Segurança e clique em “Abrir Mesmo Assim”.

**SHA-256** (\`Audra.dmg\`): \`$(cut -d' ' -f1 build/release/Audra.dmg.sha256)\`
NOTES
echo "✓ Notas da versão em $NOTES"

if [[ "${1:-}" == "--draft" ]]; then
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "✗ O release $TAG já existe no GitHub." >&2; exit 1
  fi
  gh release create "$TAG" --draft --target "$(git rev-parse HEAD)" --title "Audra $VERSION" --notes-file "$NOTES" \
    build/release/Audra.dmg build/release/Audra.dmg.sha256
  echo "✓ Rascunho criado. Revise em: $(gh release view "$TAG" --json url -q .url)"
fi
