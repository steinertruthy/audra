# Contribuindo com o Audra

Obrigado pelo interesse! Algumas orientações:

1. **Abra uma issue** antes de mudanças grandes, para alinhar a abordagem.
2. **Crie uma branch** a partir da `main` e mantenha o PR focado em um assunto.
3. **Use Conventional Commits** nos commits e no título do PR (`feat(editor): …`, `fix(summary): …`, `docs: …`).
4. **Teste:** `swift test --package-path app` e, se mexer no site, `cd website && npm run build && npm run check`.
5. **Changelog:** mudanças visíveis para quem usa entram em `CHANGELOG.md` › `[Unreleased]`.
6. **Textos da interface** usam `tr("…")` e precisam de tradução em inglês e espanhol (`app/Sources/Audra/Services/Support/Translations.swift`).
7. **Privacidade:** o Audra processa tudo localmente. Mudanças que enviem dados pela rede precisam de consentimento explícito do usuário e de atualização da Política de Privacidade.

Ao contribuir, você concorda que sua contribuição será licenciada sob a [licença MIT](LICENSE).
