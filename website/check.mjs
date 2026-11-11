#!/usr/bin/env node
// Quality gate for website/dist: internal links, anchors, assets, alt text, ids, metadata and size budget.
//
//   node check.mjs
import { readFile, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const dist = join(root, "dist");
const site = JSON.parse(await readFile(join(root, "src", "site.json"), "utf8"));
const base = new URL((process.env.SITE_URL || site.url).replace(/\/$/, "") + "/").pathname;
const errors = [];
const warnings = [];

async function walk(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await walk(path)));
    else out.push(path);
  }
  return out;
}

const files = await walk(dist);
const pages = files.filter((f) => f.endsWith(".html"));
const ids = new Map();

for (const file of pages) {
  const html = await readFile(file, "utf8");
  const rel = file.slice(dist.length + 1);
  const pageIds = [...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]);
  const duplicates = pageIds.filter((id, i) => pageIds.indexOf(id) !== i);
  if (duplicates.length) errors.push(`${rel}: ids duplicados: ${[...new Set(duplicates)].join(", ")}`);
  ids.set(rel, new Set(pageIds));

  if (!/<html lang="/.test(html)) errors.push(`${rel}: falta lang no <html>`);
  if (!/<title>[^<]{10,}<\/title>/.test(html)) errors.push(`${rel}: título ausente ou curto`);
  if (!/<meta name="description" content="[^"]{40,}"/.test(html)) errors.push(`${rel}: meta description ausente ou curta`);
  if (!/<meta property="og:image"/.test(html)) errors.push(`${rel}: falta og:image`);
  if ((html.match(/<h1[\s>]/g) || []).length !== 1) errors.push(`${rel}: deve ter exatamente um <h1>`);
  for (const img of html.matchAll(/<img\b[^>]*>/g)) {
    if (!/\salt="/.test(img[0])) errors.push(`${rel}: <img> sem alt: ${img[0].slice(0, 80)}`);
    if (!/\swidth="\d+"/.test(img[0]) || !/\sheight="\d+"/.test(img[0])) warnings.push(`${rel}: <img> sem width/height: ${img[0].slice(0, 80)}`);
  }
  if (/\{\{|\}\}/.test(html)) errors.push(`${rel}: marcação de template não processada`);
  for (const a of html.matchAll(/<a\b[^>]*target="_blank"[^>]*>/g)) {
    if (!/rel="[^"]*noopener/.test(a[0])) errors.push(`${rel}: target=_blank sem rel=noopener`);
  }
}

// Resolve every internal href/src against dist.
for (const file of pages) {
  const html = await readFile(file, "utf8");
  const rel = file.slice(dist.length + 1);
  const refs = [...html.matchAll(/\s(?:href|src)="([^"]+)"/g), ...html.matchAll(/\ssrcset="([^"]+)"/g)]
    .flatMap((m) => (m[0].includes("srcset") ? m[1].split(",").map((s) => s.trim().split(/\s+/)[0]) : [m[1]]));
  for (const ref of refs) {
    if (/^(https?:|mailto:|data:)/.test(ref)) continue;
    const [pathPart, hash] = ref.split("#");
    let target;
    if (!pathPart) target = rel;
    else if (pathPart.startsWith(base)) target = pathPart.slice(base.length);
    else if (pathPart.startsWith("/")) { errors.push(`${rel}: link absoluto fora da base ${base}: ${ref}`); continue; }
    else target = normalize(join(dirname(rel), pathPart));
    if (target === "" || target.endsWith("/")) target += "index.html";
    if (!existsSync(join(dist, target))) { errors.push(`${rel}: destino inexistente: ${ref}`); continue; }
    if (hash && target.endsWith(".html") && !ids.get(target)?.has(hash)) errors.push(`${rel}: âncora inexistente: ${ref}`);
  }
}

// Weight budget.
const index = (await stat(join(dist, "index.html"))).size;
const css = (await stat(join(dist, "assets/css/site.css"))).size;
const js = (await stat(join(dist, "assets/js/site.js"))).size;
if (index > 120_000) warnings.push(`index.html tem ${(index / 1024).toFixed(0)} KB`);
console.log(`• HTML ${(index / 1024).toFixed(1)} KB · CSS ${(css / 1024).toFixed(1)} KB · JS ${(js / 1024).toFixed(1)} KB · ${pages.length} páginas`);

for (const required of ["sitemap.xml", "robots.txt", "release.json", "404.html", "favicon.svg", "assets/img/og.jpg"]) {
  if (!existsSync(join(dist, required))) errors.push(`arquivo obrigatório ausente: ${required}`);
}

warnings.forEach((w) => console.warn(`! ${w}`));
if (errors.length) {
  errors.forEach((e) => console.error(`✗ ${e}`));
  console.error(`\n${errors.length} problema(s) encontrado(s).`);
  process.exit(1);
}
console.log("✓ Verificação concluída sem erros");
