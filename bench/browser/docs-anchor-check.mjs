// Link and anchor check of the built docs site (docs/.vitepress/dist, `npm run docs:build` first).
//   node bench/browser/docs-anchor-check.mjs
// For every <a href> in every page that points into the site: the target exists (clean URLs: /x -> x.html,
// /x/ -> x/index.html, or a static file), and when it has a #fragment, the target page has an element with that id.
// VitePress's own dead-link check covers pages, not fragments; this covers both. Exit code 1 on any problem.
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { CROSS_LOCALE } from "../../docs/.vitepress/redirects.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SITE = path.join(ROOT, "docs", ".vitepress", "dist");
if (!existsSync(path.join(SITE, "index.html"))) { console.error("docs/.vitepress/dist missing: run `npm run docs:build` first"); process.exit(2); }

const pages = [];
const walk = (rel) => {
  for (const f of readdirSync(path.join(SITE, rel))) {
    const r = rel ? rel + "/" + f : f;
    if (r === "assets" || r === "playground-app") continue;
    if (statSync(path.join(SITE, r)).isDirectory()) walk(r);
    else if (f.endsWith(".html") && f !== "404.html") pages.push(r);
  }
};
walk("");

const idCache = new Map();
function ids(file) {
  if (!idCache.has(file)) {
    const html = readFileSync(path.join(SITE, file), "utf8");
    idCache.set(file, new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1].replace(/&amp;/g, "&"))));
  }
  return idCache.get(file);
}
/** Site path ("/pdf/fonts", "/pdf/") -> file in dist, or null. */
function fileOf(p) {
  const clean = decodeURIComponent(p).replace(/^\//, "");
  for (const c of clean === "" || clean.endsWith("/") ? [clean + "index.html"] : [clean + ".html", clean, clean + "/index.html"]) {
    const abs = path.join(SITE, c);
    if (existsSync(abs) && statSync(abs).isFile()) return c;
  }
  return null;
}

let links = 0, withAnchor = 0, problems = 0;
const seen = new Set();
for (const page of pages) {
  const html = readFileSync(path.join(SITE, page), "utf8");
  // only the page content and navigation, not the inlined scripts
  for (const m of html.matchAll(/<a\s[^>]*href="([^"]*)"/g)) {
    let href = m[1].replace(/&amp;/g, "&");
    if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(href)) continue; // external
    links++;
    const base = "/" + page.replace(/index\.html$/, "").replace(/\.html$/, "");
    const u = new URL(href, "http://site" + base);
    const target = u.pathname === base && href.startsWith("#") ? page : fileOf(u.pathname);
    const key = page + " " + href;
    if (seen.has(key)) continue;
    seen.add(key);
    if (!target && CROSS_LOCALE[u.pathname]) continue; // language menu link to a single-language page (redirected)
    if (!target) { problems++; console.log(`${page}: no page for ${href}`); continue; }
    if (u.hash && u.hash.length > 1) {
      withAnchor++;
      if (!target.endsWith(".html")) continue;
      const id = decodeURIComponent(u.hash.slice(1));
      if (!ids(target).has(id)) { problems++; console.log(`${page}: missing #${id} in ${target} (href ${href})`); }
    }
  }
}
console.log(`${pages.length} pages, ${links} in-site links (${seen.size} distinct per page), ${withAnchor} with #anchor, ${problems} problem(s)`);
process.exit(problems ? 1 : 0);
