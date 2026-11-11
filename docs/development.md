# Desenvolvimento

## Requisitos

- macOS 26 (Tahoe) em um Mac com Apple Silicon.
- Xcode 26 (Swift 6.2). O app é um Swift Package em `app/`; também pode ser aberto no Xcode pelo `app/Package.swift`.
- Node 20 ou mais recente, apenas para o site (sem dependências npm).

## App

```bash
swift build --package-path app            # build de depuração
swift test --package-path app             # testes (Swift Testing)
scripts/build-app.sh [--open]             # build release → build/Audra.app (assinado ad hoc)
scripts/make-dmg.sh                       # build/release/Audra.dmg + Audra.dmg.sha256
```

`scripts/build-app.sh` lê a versão de `VERSION`, usa o número de commits como número de build e grava ambos no `Info.plist` do bundle. Variáveis opcionais: `CODESIGN_IDENTITY`, `BUILD_NUMBER`, `VERSION_OVERRIDE`.

### Biblioteca isolada para testes manuais

Builds de depuração aceitam `AUDRA_DATA_DIR` para não tocar na biblioteca real:

```bash
AUDRA_DATA_DIR=/tmp/audra-dev app/.build/debug/Audra
```

### Capturas de tela do site

As imagens do site são capturas reais do app, geradas de forma reproduzível:

```bash
swift scripts/screenshots/make-demo-video.swift /tmp/audra/demo.mp4     # vídeo de demonstração (slides + narração)
swift build --package-path app
AUDRA_DATA_DIR=/tmp/audra/data AUDRA_MARKETING=/tmp/audra/shots \
  AUDRA_DEBUG_IMPORT=/tmp/audra/demo.mp4 app/.build/debug/Audra       # importa, transcreve, edita e captura
swift scripts/screenshots/optimize.swift /tmp/audra/shots website/src/assets/img/screens
swift scripts/screenshots/make-og.swift /tmp/audra/shots/editor.png build/AppIcon.iconset/icon_256x256.png website/src/assets/img/og.jpg
```

O modo `AUDRA_MARKETING` só existe em builds de depuração (`DebugHarness.swift`) e precisa de Apple Intelligence ativado para o resumo aparecer nas capturas.

## Site

```bash
cd website
npm run dev        # build + servidor local em http://localhost:4321/audra/
npm run build      # gera website/dist
npm run check      # valida links, âncoras, imagens, metadados e ids
```

Veja [website/README.md](../website/README.md).

## Convenções

- Commits no padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/): `feat(editor): …`, `fix(transcription): …`, `docs: …`, `chore(release): v0.2.0`.
- Mudanças visíveis para quem usa entram em `CHANGELOG.md` › `[Unreleased]` no mesmo PR.
- Textos novos da interface usam `tr("…")` e precisam de tradução em `Translations.swift`.
