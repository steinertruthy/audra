## O que muda

<!-- Descreva a mudança e o motivo. Use um título no padrão Conventional Commits, ex.: feat(editor): … -->

## Como foi verificado

- [ ] `swift test --package-path app`
- [ ] `scripts/build-app.sh` (quando altera o app)
- [ ] `node website/build.mjs && node website/check.mjs` (quando altera o site)
- [ ] Entrada adicionada em `CHANGELOG.md` › `[Unreleased]` (quando a mudança é visível para quem usa)
