#!/usr/bin/env node
// Builds the static site into website/dist. No dependencies: Node 20+ only.
//
//   node build.mjs
//
// Environment:
//   SITE_URL      Public origin + base, e.g. https://steinertruthy.github.io/audra (default) or https://audra.app
//   GITHUB_TOKEN  Optional; raises the GitHub API rate limit when reading the latest release.
//   OFFLINE=1     Skip the GitHub API (uses VERSION/CHANGELOG only).

import { readFile, writeFile, mkdir, rm, cp, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { icons } from "./src/icons.mjs";

const root = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(root, "..");
const src = join(root, "src");
const dist = join(root, "dist");

const site = JSON.parse(await readFile(join(src, "site.json"), "utf8"));
site.url = (process.env.SITE_URL || site.url).replace(/\/$/, "");
site.base = new URL(site.url + "/").pathname; // "/audra/" or "/"
site.year = new Date().getFullYear();

// ---------------------------------------------------------------------------
// Release information
// ---------------------------------------------------------------------------

const monthsPt = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
const formatDate = (iso) => {
  if (!iso) return "";
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return `${d} de ${monthsPt[m - 1]} de ${y}`;
};
const formatSize = (bytes) => (bytes ? `${(bytes / 1024 / 1024).toFixed(1).replace(".", ",")} MB` : "—");

const changelog = await readFile(join(repoRoot, "CHANGELOG.md"), "utf8");
const versionFile = (await readFile(join(repoRoot, "VERSION"), "utf8")).trim();

function changelogDate(version) {
  const match = changelog.match(new RegExp(`^## \\[${version.replace(/\./g, "\\.")}\\] - (\\d{4}-\\d{2}-\\d{2})`, "m"));
  return match ? match[1] : null;
}

async function fetchJSON(url) {
  const headers = { Accept: "application/vnd.github+json", "User-Agent": "audra-website-build" };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`GitHub API ${response.status}`);
  return response.json();
}

async function latestRelease() {
  const fallback = {
    available: false,
    version: versionFile,
    tag: `v${versionFile}`,
    date: changelogDate(versionFile),
    downloadUrl: "",
    size: 0,
    sha256: "",
    pageUrl: `${site.repo}/releases`,
  };
  if (process.env.OFFLINE) return fallback;
  try {
    const release = await fetchJSON(`https://api.github.com/repos/${site.repoSlug}/releases/latest`);
    if (!release) return fallback;
    const dmg = release.assets.find((a) => a.name === site.assetName);
    if (!dmg) return { ...fallback, pageUrl: release.html_url };
    let sha256 = "";
    const sum = release.assets.find((a) => a.name === `${site.assetName}.sha256`);
    if (sum) {
      try {
        const text = await (await fetch(sum.browser_download_url, { signal: AbortSignal.timeout(10_000) })).text();
        sha256 = text.trim().split(/\s+/)[0];
      } catch {}
    }
    const version = release.tag_name.replace(/^v/, "");
    return {
      available: true,
      version,
      tag: release.tag_name,
      date: (release.published_at || "").slice(0, 10),
      downloadUrl: dmg.browser_download_url,
      size: dmg.size,
      sha256,
      pageUrl: release.html_url,
    };
  } catch (error) {
    console.warn(`! Não foi possível consultar o GitHub (${error.message}). Usando VERSION/CHANGELOG.`);
    return fallback;
  }
}

const release = await latestRelease();
release.dateLabel = formatDate(release.date) || "a definir";
release.sizeLabel = formatSize(release.size);
release.state = release.available ? "available" : "unavailable";
console.log(`• Release: ${release.available ? `${release.tag} publicado` : `nenhum publicado (VERSION ${release.version})`}`);

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------

const escapeHTML = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

async function partial(name) {
  return readFile(join(src, "partials", `${name}.html`), "utf8");
}

/** {{> partial}}, {{icon:name}}, {{{raw.path}}}, {{escaped.path}}, {{#if path}}…{{/if}}, {{#unless path}}…{{/unless}} */
async function render(template, data, depth = 0) {
  if (depth > 6) throw new Error("Partials aninhados demais");
  let out = template;
  const partials = [...out.matchAll(/\{\{>\s*([\w-]+)\s*\}\}/g)];
  for (const [token, name] of partials) out = out.replace(token, await render(await partial(name), data, depth + 1));
  const lookup = (path) => path.split(".").reduce((o, k) => (o == null ? undefined : o[k]), data);
  out = out.replace(/\{\{#(if|unless)\s+([\w.]+)\s*\}\}([\s\S]*?)\{\{\/\1\}\}/g, (_, kind, path, body) =>
    Boolean(lookup(path)) === (kind === "if") ? body : "");
  out = out.replace(/\{\{icon:([\w-]+)\}\}/g, (_, name) => {
    if (!icons[name]) throw new Error(`Ícone desconhecido: ${name}`);
    return icons[name];
  });
  out = out.replace(/\{\{\{\s*([\w.]+)\s*\}\}\}/g, (_, path) => lookup(path) ?? "");
  out = out.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, path) => {
    const value = lookup(path);
    if (value === undefined) throw new Error(`Variável indefinida: ${path}`);
    return escapeHTML(value);
  });
  return out;
}

// ---------------------------------------------------------------------------
// Markdown (subset used by the legal pages and the changelog)
// ---------------------------------------------------------------------------

function inline(text) {
  return escapeHTML(text)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, href) => {
      const url = href.startsWith("/") ? site.base + href.slice(1) : href;
      const external = /^https?:/.test(url) && !url.startsWith(site.url);
      return `<a href="${url}"${external ? ' rel="noopener"' : ""}>${label}</a>`;
    });
}

function markdown(source) {
  const lines = source.replace(/<!--[\s\S]*?-->/g, "").split("\n");
  const html = [];
  let list = null;
  let paragraph = [];
  let quote = [];
  const flushParagraph = () => { if (paragraph.length) { html.push(`<p>${inline(paragraph.join(" "))}</p>`); paragraph = []; } };
  const flushList = () => { if (list) { html.push(`<${list.type}>${list.items.map((i) => `<li>${inline(i)}</li>`).join("")}</${list.type}>`); list = null; } };
  const flushQuote = () => { if (quote.length) { html.push(`<blockquote><p>${inline(quote.join(" "))}</p></blockquote>`); quote = []; } };
  const flushAll = () => { flushParagraph(); flushList(); flushQuote(); };

  for (const raw of lines) {
    const line = raw.trimEnd();
    let m;
    if (!line.trim()) { flushAll(); continue; }
    if ((m = line.match(/^(#{1,4})\s+(.*)$/))) {
      flushAll();
      const level = Math.min(4, m[1].length + 1); // "#" in documents becomes <h2>; the page owns <h1>
      const id = m[2].toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
      html.push(`<h${level} id="${id}">${inline(m[2])}</h${level}>`);
      continue;
    }
    if (/^---+$/.test(line)) { flushAll(); html.push("<hr>"); continue; }
    if ((m = line.match(/^>\s?(.*)$/))) { flushParagraph(); flushList(); quote.push(m[1]); continue; }
    if ((m = line.match(/^\s*[-*]\s+(.*)$/))) {
      flushParagraph(); flushQuote();
      if (!list || list.type !== "ul") { flushList(); list = { type: "ul", items: [] }; }
      list.items.push(m[1]);
      continue;
    }
    if ((m = line.match(/^\s*\d+\.\s+(.*)$/))) {
      flushParagraph(); flushQuote();
      if (!list || list.type !== "ol") { flushList(); list = { type: "ol", items: [] }; }
      list.items.push(m[1]);
      continue;
    }
    if (list && /^\s{2,}\S/.test(raw)) { list.items[list.items.length - 1] += " " + line.trim(); continue; }
    flushList(); flushQuote();
    paragraph.push(line.trim());
  }
  flushAll();
  return html.join("\n");
}

/** Changelog → one block per release, newest first. */
function changelogHTML() {
  const sections = changelog
    .replace(/^\[[^\]]+\]:\s.*$/gm, "") // link reference definitions
    .split(/^## /m)
    .slice(1);
  return sections
    .map((section) => {
      const [heading, ...rest] = section.split("\n");
      const m = heading.match(/^\[([^\]]+)\](?:\s*-\s*(\d{4}-\d{2}-\d{2}))?/);
      if (!m) return "";
      const [, version, date] = m;
      if (!rest.join("").trim()) return ""; // nothing unreleased yet
      const label = version === "Unreleased" ? "Em desenvolvimento" : `Versão ${version}`;
      const id = version === "Unreleased" ? "em-desenvolvimento" : `v${version.replace(/\./g, "-")}`;
      const body = markdown(rest.join("\n"));
      return `<section class="release" id="${id}"><h2>${label}${date ? ` <small>${formatDate(date)}</small>` : ""}</h2>${body}</section>`;
    })
    .join("\n");
}

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

const pages = [
  { out: "index.html", template: "pages/index.html", title: site.title, description: site.description, path: "", nav: "home" },
  {
    out: "termos/index.html", doc: "content/termos.md", path: "termos/",
    title: "Termos de Uso — Audra", heading: "Termos de Uso",
    intro: "Condições para usar o Audra e este site.", description: "Termos de Uso do Audra, aplicativo gratuito para macOS.",
  },
  {
    out: "privacidade/index.html", doc: "content/privacidade.md", path: "privacidade/",
    title: "Política de Privacidade — Audra", heading: "Política de Privacidade",
    intro: "Como o Audra trata seus vídeos, áudios, transcrições e dados.", description: "Como o Audra processa arquivos localmente e quando algum dado sai do seu Mac.",
  },
  {
    out: "licenca/index.html", doc: "content/licenca.md", path: "licenca/",
    title: "Licença — Audra", heading: "Licença",
    intro: "O Audra é software livre, distribuído sob a licença MIT.", description: "Licença MIT do Audra e avisos de terceiros.",
  },
  {
    out: "versoes/index.html", changelog: true, path: "versoes/",
    title: "Histórico de versões — Audra", heading: "Histórico de versões",
    intro: "Novidades, melhorias e correções de cada versão do Audra.", description: "Changelog do Audra: novidades e correções de cada versão.",
  },
  { out: "404.html", template: "pages/404.html", path: "404.html", title: "Página não encontrada — Audra", description: site.description, noindex: true },
];

await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
const layout = await readFile(join(src, "layouts", "base.html"), "utf8");

for (const page of pages) {
  let body;
  if (page.template) {
    body = await readFile(join(src, page.template), "utf8");
  } else {
    let content = page.changelog ? changelogHTML() : markdown(await readFile(join(src, page.doc), "utf8"));
    if (content.includes("{{LICENSE}}")) {
      const license = await readFile(join(repoRoot, "LICENSE"), "utf8");
      content = content.replace(/<p>\{\{LICENSE\}\}<\/p>/, `<pre>${escapeHTML(license.trim())}</pre>`);
    }
    body = `{{> doc}}`;
    page.content = content;
  }
  const data = {
    site,
    release,
    page: {
      ...page,
      url: `${site.url}/${page.path}`,
      ogImage: `${site.url}/assets/img/og.jpg`,
      robots: page.noindex ? "noindex" : "index, follow",
    },
    jsonld: JSON.stringify({
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: "Audra",
      operatingSystem: "macOS 26",
      applicationCategory: "MultimediaApplication",
      description: site.description,
      softwareVersion: release.version,
      license: "https://opensource.org/licenses/MIT",
      offers: { "@type": "Offer", price: "0", priceCurrency: "BRL" },
      url: `${site.url}/`,
      ...(release.available ? { downloadUrl: release.downloadUrl } : {}),
    }),
    releaseJSON: JSON.stringify(release),
  };
  const html = await render(layout.replace("{{{body}}}", body), data);
  const file = join(dist, page.out);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, html.replace(/\n\s*\n\s*\n/g, "\n\n"));
  console.log(`✓ ${page.out}`);
}

// Static assets
await cp(join(src, "assets"), join(dist, "assets"), { recursive: true });
await cp(join(src, "static"), dist, { recursive: true });

// Release data consumed by the page script (and by anyone automating checks).
await writeFile(join(dist, "release.json"), JSON.stringify(release, null, 2));

// SEO files
const today = new Date().toISOString().slice(0, 10);
const indexable = pages.filter((p) => !p.noindex);
await writeFile(
  join(dist, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${indexable
    .map((p) => `  <url><loc>${site.url}/${p.path}</loc><lastmod>${today}</lastmod></url>`)
    .join("\n")}\n</urlset>\n`,
);
await writeFile(join(dist, "robots.txt"), `User-agent: *\nAllow: /\n\nSitemap: ${site.url}/sitemap.xml\n`);
await writeFile(join(dist, ".nojekyll"), "");

// Size report
async function folderSize(dir) {
  let total = 0;
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    total += entry.isDirectory() ? await folderSize(path) : (await stat(path)).size;
  }
  return total;
}
console.log(`✓ dist/ pronto (${(await folderSize(dist) / 1024 / 1024).toFixed(1)} MB) · base ${site.base}`);
if (!existsSync(join(dist, "index.html"))) process.exit(1);
