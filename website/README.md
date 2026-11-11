# Site oficial do Audra

Site estático em português, publicado no GitHub Pages. Não usa frameworks nem dependências npm: um script em Node gera o HTML final a partir de templates, Markdown e dos dados de versão.

## Comandos

```bash
npm run dev      # build + servidor local em http://localhost:4321/audra/
npm run build    # gera dist/
npm run check    # valida links, âncoras, imagens, ids, metadados e arquivos obrigatórios
```

Variáveis de ambiente do build:

| Variável | Uso |
|---|---|
| `SITE_URL` | URL pública com o caminho base. Padrão: `https://steinertruthy.github.io/audra`. No CI, vem das configurações do Pages. |
| `GITHUB_TOKEN` | Opcional; aumenta o limite da API do GitHub ao ler o último release. |
| `OFFLINE=1` | Não consulta o GitHub; usa só `VERSION` e `CHANGELOG.md`. |

## Estrutura

```text
website/
├── build.mjs              Gerador: templates, Markdown, dados do release, sitemap, robots
├── check.mjs              Verificação de qualidade do dist/
├── serve.mjs              Servidor local com o mesmo caminho base da produção
└── src/
    ├── site.json          Nome, URLs, repositório e requisitos
    ├── icons.mjs          Ícones SVG inline
    ├── layouts/base.html  <head> com SEO, Open Graph, JSON-LD
    ├── partials/          Cabeçalho, rodapé e página de documento
    ├── pages/             Página inicial e 404
    ├── content/           Termos, privacidade e licença (Markdown)
    ├── static/            Arquivos copiados para a raiz (favicons)
    └── assets/            CSS, JS e imagens otimizadas
```

O histórico de versões é gerado a partir do `CHANGELOG.md` da raiz, e a licença a partir do `LICENSE`.

## Templates

| Sintaxe | Efeito |
|---|---|
| `{{> header}}` | Inclui `partials/header.html` |
| `{{site.repo}}`, `{{release.version}}` | Valor com escape de HTML (falha o build se não existir) |
| `{{{page.content}}}` | Valor sem escape |
| `{{icon:download}}` | Ícone SVG de `icons.mjs` |
| `{{#if release.available}} … {{/if}}`, `{{#unless …}}` | Blocos condicionais |

Todos os links internos usam `{{site.base}}`, para o site funcionar tanto em `/audra/` quanto em um domínio próprio.

## Download e versões

- Durante o build, `build.mjs` consulta `GET /repos/steinertruthy/audra/releases/latest`. Se existir um release com o arquivo `Audra.dmg`, a área de download mostra a versão, a data, o tamanho e o checksum (lido de `Audra.dmg.sha256`).
- Se ainda não houver release, a página mostra **"Download em breve"** e a versão de `VERSION`, sem nenhum link falso.
- No navegador, `site.js` consulta a mesma API (com cache de 10 minutos na sessão) e atualiza a página se houver uma versão mais nova que a do build.
- O workflow do site roda novamente sempre que um release é publicado.

## Imagens

As capturas em `assets/img/screens/` são do app real, geradas pelos scripts em `scripts/screenshots/` (veja [docs/development.md](../docs/development.md)). Cada uma tem versões AVIF em 1440 e 2880 px e um JPEG de fallback.

## Domínio próprio

1. Configure o domínio em **Settings › Pages** do repositório.
2. Crie `src/static/CNAME` com o domínio.
3. O workflow passa o novo `SITE_URL` automaticamente (via `actions/configure-pages`), e os links passam a usar `/` como base.

## Por que GitHub Pages

O site é estático e gerado no CI, então o Pages atende a todos os requisitos: HTTPS, domínio próprio, publicação automática por Actions, página 404 personalizada e nenhum custo. Não há rotas dinâmicas nem renderização no servidor que justifiquem Vercel ou Cloudflare Pages.
