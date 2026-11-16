// Static dev server for the playground.  node docs/playground-app/serve.mjs [--port 8080] [--dist] [--host 127.0.0.1]
//   default : serves the REPO ROOT so /docs/playground-app/ and /js/ both resolve (npm run playground)
//   --dist  : serves docs/playground-app/dist (build it first with `node docs/playground-app/build.mjs`) at /
import http from "node:http";
import { createReadStream, statSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(HERE, "..", "..");
const MIME = {
  ".html": "text/html; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".wasm": "application/wasm", ".css": "text/css; charset=utf-8",
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif", ".svg": "image/svg+xml",
  ".ttf": "font/ttf", ".otf": "font/otf", ".woff": "font/woff", ".woff2": "font/woff2",
  ".txt": "text/plain; charset=utf-8", ".md": "text/plain; charset=utf-8",
};

/** Starts the server; resolves { port, url, root, close() }. `port: 0` = ephemeral.
 *  cleanUrls: serve /x from x.html and unknown paths with 404.html (used to test the built docs site). */
export function startServer({ root = REPO_ROOT, port = 0, host = "127.0.0.1", cleanUrls = false } = {}) {
  const rootN = path.resolve(root);
  const sockets = new Set();
  const server = http.createServer((req, res) => {
    try {
      const u = new URL(req.url, "http://127.0.0.1");
      const rel = decodeURIComponent(u.pathname);
      if (rel.includes("\0")) { res.writeHead(400).end("bad path"); return; }
      let file = path.resolve(rootN, "." + rel);
      if (file !== rootN && !file.startsWith(rootN + path.sep)) { res.writeHead(403).end("forbidden"); return; }
      let st;
      let status = 200;
      try { st = statSync(file); } catch {
        const alt = cleanUrls && !path.extname(file) ? [file + ".html"] : [];
        if (cleanUrls) alt.push(path.join(rootN, "404.html"));
        for (const a of alt) { try { st = statSync(a); file = a; status = a.endsWith(path.sep + "404.html") ? 404 : 200; break; } catch { /* next */ } }
        if (!st) { res.writeHead(rel === "/favicon.ico" ? 204 : 404).end(rel === "/favicon.ico" ? "" : "not found"); return; }
      }
      if (st.isDirectory()) {
        if (!rel.endsWith("/")) { res.writeHead(301, { location: rel + "/" + u.search }).end(); return; }
        file = path.join(file, "index.html");
        try { st = statSync(file); } catch { res.writeHead(404).end("no directory listing"); return; }
      }
      const type = MIME[path.extname(file).toLowerCase()] || "application/octet-stream";
      res.writeHead(status, { "content-type": type, "content-length": st.size, "cache-control": "no-store" });
      if (req.method === "HEAD") { res.end(); return; }
      createReadStream(file).on("error", () => res.destroy()).pipe(res);
    } catch (e) { res.writeHead(500).end(String(e?.message ?? e)); }
  });
  server.on("connection", (s) => { sockets.add(s); s.on("close", () => sockets.delete(s)); });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      const p = server.address().port;
      resolve({ port: p, url: `http://${host}:${p}`, root: rootN, close: () => new Promise((r) => { for (const s of sockets) s.destroy(); server.close(() => r()); }) });
    });
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const argv = process.argv.slice(2);
  const opt = (n, d) => { const i = argv.findIndex((a) => a === `--${n}` || a.startsWith(`--${n}=`)); if (i < 0) return d; return argv[i].includes("=") ? argv[i].split("=")[1] : (argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : true); };
  const dist = opt("dist", false);
  const root = dist ? path.join(HERE, "dist") : REPO_ROOT;
  if (dist && !existsSync(root)) { console.error("docs/playground-app/dist not found: run `node docs/playground-app/build.mjs` first"); process.exit(1); }
  const port = Number(opt("port", process.env.PORT || 8080));
  const host = opt("host", "127.0.0.1");
  const s = await startServer({ root, port, host });
  console.log(`bm-render playground (${dist ? "dist" : "dev"}): ${s.url}${dist ? "/" : "/docs/playground-app/"}`);
}
