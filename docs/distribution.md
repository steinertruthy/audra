# Distribuição

## Artefatos

Cada release publica dois arquivos no GitHub Releases:

| Arquivo | Conteúdo |
|---|---|
| `Audra.dmg` | Imagem de disco (APFS, compactada) com `Audra.app` e um atalho para Aplicativos |
| `Audra.dmg.sha256` | Checksum SHA-256 do DMG |

O nome do DMG é fixo para que o link `https://github.com/steinertruthy/audra/releases/latest/download/Audra.dmg` sempre aponte para a versão estável mais recente. A versão aparece no nome do volume e no app.

Para conferir um download:

```bash
shasum -a 256 ~/Downloads/Audra.dmg
```

## Situação atual: assinatura ad hoc

O projeto **ainda não tem um certificado Developer ID**. Por isso:

- O app é assinado *ad hoc* (`codesign --sign -`), o que garante a integridade do bundle, mas não identifica o desenvolvedor.
- O macOS (Gatekeeper) bloqueia a primeira abertura de apps baixados que não são notarizados. No macOS 15 e posteriores, o usuário precisa ir em **Ajustes do Sistema › Privacidade e Segurança** e clicar em **Abrir Mesmo Assim**.
- O site, o README e as notas de cada release explicam esse passo.

## Como habilitar assinatura e notarização

Requisitos:

1. Conta paga no [Apple Developer Program](https://developer.apple.com/programs/).
2. Certificado **Developer ID Application**, exportado como `.p12`.
3. Para notarizar: Apple ID com **senha específica de app** e o **Team ID**.

Localmente:

```bash
xcrun notarytool store-credentials audra-notary --apple-id "voce@exemplo.com" --team-id "TEAMID" --password "senha-de-app"
CODESIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" scripts/build-app.sh
CODESIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" NOTARY_PROFILE=audra-notary scripts/make-dmg.sh
```

No GitHub Actions, cadastre estes *secrets* no repositório. O workflow de release os detecta e passa a assinar e notarizar automaticamente:

| Secret | Valor |
|---|---|
| `MACOS_CERTIFICATE_P12` | Conteúdo do `.p12` em base64 (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | Senha do `.p12` |
| `MACOS_SIGNING_IDENTITY` | `Developer ID Application: Nome (TEAMID)` |
| `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` | Credenciais de notarização |

Nunca coloque certificados, senhas ou chaves no repositório. O `.gitignore` bloqueia `*.p12`, `*.cer` e `.env`.

## Atualizações

Hoje a atualização é manual: o usuário baixa a nova versão e substitui o app em Aplicativos. Biblioteca e projetos ficam em `~/Library/Application Support/Audra` e são preservados. Uma atualização automática (por exemplo, com Sparkle) exige assinatura Developer ID e fica para quando ela estiver disponível.

## Site

O site é publicado no **GitHub Pages** pelo workflow `.github/workflows/pages.yml`. Detalhes em [website/README.md](../website/README.md).
