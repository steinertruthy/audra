#!/usr/bin/env node
// Local preview of website/dist, served under the same base path as production.
//
//   node serve.mjs            → http://localhost:4321/audra/
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const dist = join(root, "dist");
const site = JSON.parse(await readFile(join(root, "src", "site.json"), "utf8"));
const base = new URL((process.env.SITE_URL || site.url).replace(/\/$/, "") + "/").pathname;
const port = Number(process.env.PORT || 4321);
const types = {
  ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".json": "application/json",
  ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".avif": "image/avif", ".xml": "application/xml", ".txt": "text/plain",
};

createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (!url.pathname.startsWith(base)) { res.writeHead(302, { Location: base }); return res.end(); }
  let path = normalize(decodeURIComponent(url.pathname.slice(base.length))).replace(/^(\.\.[/\\])+/, "");
  let file = join(dist, path);
  try {
    if ((await stat(file)).isDirectory()) file = join(file, "index.html");
    const body = await readFile(file);
    res.writeHead(200, { "Content-Type": types[extname(file)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404, { "Content-Type": types[".html"] });
    res.end(await readFile(join(dist, "404.html")));
  }
}).listen(port, () => console.log(`→ http://localhost:${port}${base}`));
