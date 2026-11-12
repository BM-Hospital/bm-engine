// Examples for docs/{en,vi}/pdf/frameworks.md. Run: node docs/examples/run-all.mjs pdf-frameworks
// (and with BM_ENGINE_BACKEND=wasm). Calls the Request -> Response handler in-process and through node:http.
import "./_lib.mjs";
import assert from "node:assert/strict";
import { once } from "node:events";
process.env.PORT = "0"; // the example server below listens on PORT; here on an ephemeral port

// #region renderer
// pdf.js — create the renderer once per process (or per isolate), not per request
import { readFileSync } from "node:fs";
import { PdfRenderer } from "bm-engine/pdf";

let renderer;
export function getPdfRenderer() {
  if (!renderer) {
    renderer = new PdfRenderer();
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Regular.ttf") });
    renderer.registerFont({ name: "Inter", data: readFileSync("assets/fonts/Inter-Bold.ttf") });
  }
  return renderer;
}
// #endregion

// #region helper
/** PDF bytes -> a web-standard Response. `download: true` makes browsers save the file instead of showing it. */
export function pdfResponse(bytes, { filename = "document.pdf", download = false, headers = {} } = {}) {
  return new Response(bytes, {
    headers: {
      "content-type": "application/pdf",
      "content-length": String(bytes.byteLength),
      "content-disposition": `${download ? "attachment" : "inline"}; filename="${filename}"`,
      ...headers,
    },
  });
}
// #endregion

// #region handler
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** GET /report.pdf?name=Ada[&download=1] — works wherever a framework hands you a Request. */
export async function handleReport(request) {
  const url = new URL(request.url);
  const name = escapeHtml((url.searchParams.get("name") ?? "World").slice(0, 100));
  const bytes = await getPdfRenderer().render(
    `<div style="font-family: Inter; font-size: 14px">
       <h1>Report for ${name}</h1>
       <p>Generated on ${new Date().toISOString().slice(0, 10)}.</p>
     </div>`,
    {
      size: "a4",
      footer: `<div style="font: 10px Inter; text-align: center">Page <span class="pageNumber"></span></div>`,
      signal: request.signal, // a request the client abandoned is not rendered
    },
  );
  return pdfResponse(bytes, {
    filename: "report.pdf",
    download: url.searchParams.has("download"),
    headers: { "cache-control": "private, no-store" },
  });
}
// #endregion

// in-process: the handler as a framework would call it
const r1 = await handleReport(new Request("http://localhost/report.pdf?name=Ada%20%3CLovelace%3E"));
assert.equal(r1.status, 200);
assert.equal(r1.headers.get("content-type"), "application/pdf");
assert.equal(r1.headers.get("content-disposition"), 'inline; filename="report.pdf"');
const b1 = new Uint8Array(await r1.arrayBuffer());
assert.equal(new TextDecoder().decode(b1.subarray(0, 5)), "%PDF-");
assert.equal(Number(r1.headers.get("content-length")), b1.byteLength);
const r2 = await handleReport(new Request("http://localhost/report.pdf?download=1"));
assert.equal(r2.headers.get("content-disposition"), 'attachment; filename="report.pdf"');

// an aborted request: the render is not started
const ac = new AbortController();
ac.abort();
let abortError;
try { await handleReport(new Request("http://localhost/report.pdf", { signal: ac.signal })); } catch (e) { abortError = e; }
assert.ok(abortError, "aborted request should reject");

// #region node-http
import { createServer } from "node:http";
import { Readable } from "node:stream";

// node:http has no Request / Response: convert at the edge (Hono, Nitro, SvelteKit, ... do this for you)
const server = createServer(async (req, res) => {
  const controller = new AbortController();
  res.on("close", () => { if (!res.writableFinished) controller.abort(); });
  try {
    const request = new Request(new URL(req.url, `http://${req.headers.host}`), { signal: controller.signal });
    const response = await handleReport(request);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    Readable.fromWeb(response.body).pipe(res);
  } catch (error) {
    if (!controller.signal.aborted) console.error(error);
    if (!res.headersSent) res.writeHead(500, { "content-type": "text/plain" }).end("Failed to render the PDF");
  }
});
server.listen(Number(process.env.PORT ?? 3000));
// #endregion
server.close();
await once(server, "close");

// the same server on an ephemeral port, fetched for real
server.listen(0, "127.0.0.1");
await once(server, "listening");
const { port } = server.address();
const res = await fetch(`http://127.0.0.1:${port}/report.pdf?name=Grace`);
assert.equal(res.status, 200);
assert.equal(res.headers.get("content-type"), "application/pdf");
const b3 = new Uint8Array(await res.arrayBuffer());
assert.equal(new TextDecoder().decode(b3.subarray(0, 5)), "%PDF-");
assert.equal(Number(res.headers.get("content-length")), b3.byteLength);
server.close();

const { backend } = await import("bm-engine/pdf");
console.log("pdf-frameworks: ok", { backend, inProcessBytes: b1.byteLength, httpBytes: b3.byteLength, abort: abortError.name + ": " + abortError.message });
