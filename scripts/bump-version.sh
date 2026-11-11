#!/bin/zsh
# Prepares a new version: updates VERSION and turns the "Unreleased" changelog section into a dated release.
#
#   scripts/bump-version.sh 0.2.0
#
# Does not commit or tag; review the diff, then commit with `chore(release): v0.2.0`.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
CURRENT="$(tr -d '[:space:]' < VERSION)"
TODAY="$(date +%Y-%m-%d)"

[[ "$NEW" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Uso: scripts/bump-version.sh MAJOR.MINOR.PATCH" >&2; exit 1; }

# The new version must be greater than the current one.
if [[ "$(printf '%s\n%s\n' "$CURRENT" "$NEW" | sort -V | tail -1)" != "$NEW" || "$CURRENT" == "$NEW" ]]; then
  echo "✗ $NEW não é maior que a versão atual $CURRENT" >&2; exit 1
fi
grep -q "^## \[Unreleased\]" CHANGELOG.md || { echo "✗ CHANGELOG.md não tem a seção [Unreleased]" >&2; exit 1; }

UNRELEASED="$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md | grep -v '^\s*$' || true)"
[[ -n "$UNRELEASED" ]] || { echo "✗ A seção [Unreleased] está vazia: descreva as mudanças antes de versionar." >&2; exit 1; }

echo "$NEW" > VERSION
python3 - "$NEW" "$CURRENT" "$TODAY" <<'PY'
import re, sys
new, current, today = sys.argv[1:]
path = "CHANGELOG.md"
text = open(path, encoding="utf-8").read()
text = text.replace("## [Unreleased]", f"## [Unreleased]\n\n## [{new}] - {today}", 1)
text = re.sub(r"^\[Unreleased\]: .*$", f"[Unreleased]: https://github.com/steinertruthy/audra/compare/v{new}...HEAD\n[{new}]: https://github.com/steinertruthy/audra/compare/v{current}...v{new}", text, count=1, flags=re.M)
open(path, "w", encoding="utf-8").write(text)
PY
echo "✓ Versão $CURRENT → $NEW ($TODAY). Revise CHANGELOG.md e faça o commit: chore(release): v$NEW"
