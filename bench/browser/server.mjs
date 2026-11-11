// Tiny static file server for the repo root (127.0.0.1, ephemeral port).
import http from "node:http";
import { createReadStream, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const MIME = {
  ".html": "text/html; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".json": "application/json", ".wasm": "application/wasm", ".css": "text/css; charset=utf-8",
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8", ".md": "text/plain; charset=utf-8",
};

export function startServer({ root = REPO_ROOT } = {}) {
  const rootN = path.resolve(root);
  const sockets = new Set();
  const server = http.createServer((req, res) => {
    try {
      const u = new URL(req.url, "http://127.0.0.1");
      let rel = decodeURIComponent(u.pathname);
      if (rel === "/favicon.ico") { res.writeHead(204).end(); return; }
      if (rel.includes("\0")) { res.writeHead(400).end("bad path"); return; }
      const file = path.resolve(rootN, "." + rel);
      if (file !== rootN && !file.startsWith(rootN + path.sep)) { res.writeHead(403).end("forbidden"); return; }
      let st;
      try { st = statSync(file); } catch { res.writeHead(404).end("not found"); return; }
      if (!st.isFile()) { res.writeHead(404).end("not a file (no directory listing)"); return; }
      const type = MIME[path.extname(file).toLowerCase()] || "application/octet-stream";
      res.writeHead(200, { "content-type": type, "content-length": st.size, "cache-control": "no-store" });
      if (req.method === "HEAD") { res.end(); return; }
      createReadStream(file).on("error", () => res.destroy()).pipe(res);
    } catch (e) { res.writeHead(500).end(String(e?.message ?? e)); }
  });
  server.on("connection", (s) => { sockets.add(s); s.on("close", () => sockets.delete(s)); });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      resolve({
        port, url: `http://127.0.0.1:${port}`,
        close: () => new Promise((r) => { for (const s of sockets) s.destroy(); server.close(() => r()); }),
      });
    });
  });
}
