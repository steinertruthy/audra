# Versionamento e publicação

## Versionamento semântico

O Audra segue o [SemVer](https://semver.org/lang/pt-BR/) no formato `MAJOR.MINOR.PATCH`:

| Mudança | Exemplo |
|---|---|
| Correções sem mudar o comportamento esperado | `0.1.0 → 0.1.1` |
| Novas funcionalidades compatíveis | `0.1.1 → 0.2.0` |
| Mudanças incompatíveis (formato de projeto, requisitos mínimos) | `0.9.0 → 1.0.0` |

Enquanto a versão for `0.x`, o projeto está em desenvolvimento inicial. A `1.0.0` deve sair quando o app for assinado e notarizado e o formato de projeto for considerado estável.

**Fonte única da versão:** o arquivo `VERSION`. Ele alimenta o `Info.plist` do app (`CFBundleShortVersionString`), a tela Ajustes › Sobre, o site e a validação das tags.

## Commits e changelog

- Commits seguem o [Conventional Commits](https://www.conventionalcommits.org/pt-br/). O CI valida o título dos pull requests.
- O `CHANGELOG.md` segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Cada mudança relevante entra em `[Unreleased]`, nas seções *Adicionado*, *Alterado*, *Corrigido* ou *Removido*.

## Publicar uma versão

1. **Preparar** (em uma branch):

   ```bash
   scripts/bump-version.sh 0.2.0
   git commit -am "chore(release): v0.2.0"
   ```

   O script atualiza `VERSION`, transforma `[Unreleased]` em `[0.2.0] - AAAA-MM-DD` e corrige os links de comparação.

2. **Revisar e integrar** o PR na `main` (o CI compila, testa e gera um DMG de teste).

3. **Criar a tag** no commit da `main`:

   ```bash
   git tag -a v0.2.0 -m "Audra 0.2.0"
   git push origin v0.2.0
   ```

4. **Workflow de release** (`.github/workflows/release.yml`): valida a tag contra `VERSION` e `CHANGELOG.md`, roda os testes, compila, gera `Audra.dmg` e `Audra.dmg.sha256` e cria um **release em rascunho** com as notas extraídas do changelog.

5. **Validar e publicar:** baixe o DMG do rascunho, instale em um Mac limpo, confira o checksum e clique em **Publish release**.

6. **Site:** a publicação dispara o workflow do site, que passa a mostrar a nova versão, o tamanho, a data e o checksum. O site também consulta a API do GitHub no navegador, então a nova versão aparece mesmo antes do rebuild.

### Alternativa local

Sem runner macOS disponível, o mesmo processo pode ser feito localmente:

```bash
scripts/release.sh          # testa, compila, gera DMG, checksum e notas
scripts/release.sh --draft  # …e cria o release em rascunho no GitHub (requer gh e o commit na main)
```

## Corrigir uma versão publicada

Não reescreva tags publicadas. Corrija na `main` e publique uma versão de patch (`0.2.1`).
