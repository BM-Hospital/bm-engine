// Local documentation site: renders the repository's Markdown docs as HTML.
//   node scripts/docs-serve.mjs [--port 4173]      (npm run docs)
// Needs `marked` (installed in bench/node_modules by `npm i --ignore-scripts` inside bench/).
import http from "node:http";
import { readFileSync, existsSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const markedPath = [path.join(root, "node_modules/marked/lib/marked.esm.js"), path.join(root, "bench/node_modules/marked/lib/marked.esm.js")].find(existsSync);
if (!markedPath) {
  console.error("marked not found: run `npm i --ignore-scripts` inside bench/ first");
  process.exit(1);
}
const { marked } = await import(pathToFileURL(markedPath).href);

const portArg = process.argv.indexOf("--port");
const port = portArg > 0 ? Number(process.argv[portArg + 1]) : 4173;

const NAV = {
  en: [
    ["README.md", "Overview"], ["docs/en/getting-started.md", "Getting started"], ["docs/en/api.md", "API reference"],
    ["docs/en/css-support.md", "CSS & feature support"], ["docs/en/profiles-and-size.md", "Profiles & size"],
    ["docs/en/differences-from-takumi.md", "Differences from takumi"], ["docs/en/benchmark.md", "Benchmark"],
    ["docs/en/playground.md", "Playground"], ["docs/en/building-from-source.md", "Building from source"],
    ["docs/en/troubleshooting.md", "Troubleshooting"],
  ],
  vi: [
    ["README.vi.md", "Tổng quan"], ["docs/vi/getting-started.md", "Bắt đầu"], ["docs/vi/api.md", "Tham chiếu API"],
    ["docs/vi/css-support.md", "CSS & tính năng"], ["docs/vi/profiles-and-size.md", "Cấu hình & kích thước"],
    ["docs/vi/differences-from-takumi.md", "Khác biệt với takumi"], ["docs/vi/benchmark.md", "Benchmark (tóm tắt)"],
    ["docs/BENCHMARK.md", "Benchmark (báo cáo đầy đủ)"], ["docs/RESULTS_FULL.md", "Kết quả từng fixture"],
    ["docs/vi/playground.md", "Playground"], ["docs/vi/building-from-source.md", "Build từ mã nguồn"],
    ["docs/vi/troubleshooting.md", "Xử lý sự cố"],
  ],
  dev: [["docs/ARCHITECTURE.md", "Architecture"], ["docs/TAKUMI_NOTES.md", "takumi semantics notes"], ["docs/CONVENTIONS.md", "Conventions"], ["THIRD-PARTY-NOTICES.md", "Third-party notices"]],
};

const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const slug = (s) => s.toLowerCase().replace(/<[^>]+>/g, "").replace(/[^\p{L}\p{N}\s-]/gu, "").trim().replace(/\s+/g, "-");

function page(rel) {
  const md = readFileSync(path.join(root, rel), "utf8");
  let html = marked.parse(md, { gfm: true });
  // GitHub-style heading ids so in-page anchors work
  html = html.replace(/<h([1-6])>([\s\S]*?)<\/h\1>/g, (_, n, inner) => `<h${n} id="${slug(inner)}">${inner}</h${n}>`);
  const lang = rel.includes("/vi/") || rel.endsWith(".vi.md") || rel === "docs/BENCHMARK.md" || rel === "docs/RESULTS_FULL.md" ? "vi" : "en";
  const nav = (items) => items.map(([p, t]) => `<a href="/${p}"${p === rel ? ' class="on"' : ""}>${esc(t)}</a>`).join("");
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(rel)} — bm-engine docs</title><style>
:root{--bg:#fff;--fg:#1f2328;--mut:#59636e;--line:#d1d9e0;--side:#f6f8fa;--acc:#4f46e5;--code:#f6f8fa}
@media(prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--mut:#9198a1;--line:#30363d;--side:#151b23;--acc:#a5b4fc;--code:#151b23}}
*{box-sizing:border-box}body{margin:0;font:16px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif;background:var(--bg);color:var(--fg);display:flex;min-height:100vh}
nav{width:270px;flex:none;background:var(--side);border-right:1px solid var(--line);padding:20px 14px;position:sticky;top:0;height:100vh;overflow:auto}
nav h2{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:18px 8px 6px}nav h1{font-size:18px;margin:0 8px 4px}
nav a{display:block;padding:5px 8px;border-radius:6px;color:var(--fg);text-decoration:none;font-size:14px}nav a:hover{background:var(--line)}nav a.on{background:var(--acc);color:#fff}
main{flex:1;min-width:0;padding:28px 44px 80px;max-width:1080px}a{color:var(--acc)}
h1,h2{border-bottom:1px solid var(--line);padding-bottom:.3em}h1{font-size:30px}h2{margin-top:1.8em}
table{border-collapse:collapse;display:block;overflow:auto;max-width:100%;font-size:14px;margin:14px 0}th,td{border:1px solid var(--line);padding:6px 11px;white-space:nowrap}
td:last-child,th:last-child{white-space:normal;min-width:180px}th{background:var(--side)}tr:nth-child(even) td{background:color-mix(in srgb,var(--side) 55%,transparent)}
code{background:var(--code);padding:.15em .35em;border-radius:5px;font:13px/1.5 ui-monospace,Consolas,monospace}pre{background:var(--code);border:1px solid var(--line);border-radius:8px;padding:14px;overflow:auto}pre code{background:none;padding:0}
blockquote{margin:0;padding:2px 16px;border-left:4px solid var(--line);color:var(--mut)}img{max-width:100%}
@media(max-width:820px){body{display:block}nav{position:static;width:auto;height:auto}main{padding:18px}}
</style></head><body><nav><h1>bm-engine docs</h1><a href="/playground/">▶ Playground</a>
<h2>Tiếng Việt</h2>${nav(NAV.vi)}<h2>English</h2>${nav(NAV.en)}<h2>Developer</h2>${nav(NAV.dev)}</nav><main>${html}</main></body></html>`;
}

const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json", ".wasm": "application/wasm", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".ttf": "font/ttf", ".woff2": "font/woff2" };

http.createServer((req, res) => {
  try {
    let rel = decodeURIComponent(new URL(req.url, "http://x").pathname).replace(/^\/+/, "");
    if (rel === "") rel = "README.vi.md";
    let file = path.resolve(root, rel);
    if (file !== root && !file.startsWith(root + path.sep)) { res.writeHead(403).end("forbidden"); return; }
    if (existsSync(file) && statSync(file).isDirectory()) {
      if (existsSync(path.join(file, "README.md"))) { rel = path.posix.join(rel, "README.md"); file = path.join(file, "README.md"); }
      else if (existsSync(path.join(file, "index.html"))) {
        if (!req.url.split("?")[0].endsWith("/")) { res.writeHead(302, { location: "/" + rel + "/" }).end(); return; }
        file = path.join(file, "index.html");
      }
    }
    if (!existsSync(file) || statSync(file).isDirectory()) { res.writeHead(404, { "content-type": "text/plain" }).end("not found: " + rel); return; }
    if (file.endsWith(".md")) { res.writeHead(200, { "content-type": MIME[".html"] }).end(page(path.relative(root, file).replace(/\\/g, "/"))); return; }
    res.writeHead(200, { "content-type": MIME[path.extname(file).toLowerCase()] || "application/octet-stream" }).end(readFileSync(file));
  } catch (e) {
    res.writeHead(500, { "content-type": "text/plain" }).end(String(e && e.message));
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`bm-engine docs: http://127.0.0.1:${port}/   (Tiếng Việt: /README.vi.md · English: /README.md · Benchmark: /docs/BENCHMARK.md · Playground: /playground/)`);
});
