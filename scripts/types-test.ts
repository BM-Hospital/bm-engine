// Type-level smoke test of the published typings. Not executed: `tsc --noEmit` only. scripts/pack-test.mjs
// copies it into a project that installed the packed tarball and checks it with moduleResolution
// "bundler" and "node16".
import init, {
  initSync,
  Renderer,
  features,
  setGlyphCacheMaxBytes,
  backend,
  type Node,
  type ContainerNode,
  type TextNode,
  type ImageNode,
  type Style,
  type RenderOptions,
  type RenderAnimationOptions,
  type MeasuredNode,
  type RegisteredFamily,
  type FontDetails,
  type OutputFormat,
  type CssInput,
  type ImageSource,
  type Features,
  type Prepared,
  type WasmExports,
} from "bm-engine";
import * as core from "bm-engine/core";
import { init as initStandard, profile as standardProfile } from "bm-engine/standard";
import fullInit, { Renderer as FullRenderer, wasmUrl } from "bm-engine/full";
import { loadWoff, decodeWoff } from "bm-engine/woff";
import coreWasm from "bm-engine/core.wasm";
import woffWasm from "bm-engine/woff.wasm";
import coreWasmModule from "bm-engine/core.wasm?module"; // Next.js Edge / webpack `?module` form
import * as native from "bm-engine/native";
import nativeInit, { Renderer as NativeRenderer, backend as nativeBackend } from "bm-engine/native";

declare const bytes: Uint8Array;

const style: Style = { display: "flex", width: "100%", height: 630, backgroundColor: "#fff", fontSize: 32, "--brand": "#f00" };
const text: TextNode = { type: "text", text: "Hello", style: { fontFamily: "Inter", color: "black" } };
const img: ImageNode = { type: "image", src: bytes, width: 64, height: 64 };
const tree: ContainerNode = { type: "container", style, children: [text, img, null] };
const node: Node = tree;

async function main(): Promise<void> {
  const ex: WasmExports = await init(bytes);
  void ex;
  initSync(bytes);
  await init(fetch("/bm_engine.wasm"));
  await init({ module_or_path: new URL("https://example.com/x.wasm") });
  await init(coreWasm);
  // @ts-expect-error the neutral entry needs the wasm argument
  await init();

  await core.init(); // profile entries default to their own wasm file
  await core.init(coreWasm); // Cloudflare Workers form
  await initStandard();
  await fullInit();
  const p: "core" = core.profile;
  const s: "standard" = standardProfile;
  const u: URL = wasmUrl();
  void p; void s; void u;

  const r = new Renderer({ cacheMaxBytes: 1 << 20 });
  const fams: RegisteredFamily[] = r.registerFont(bytes);
  const fams2: RegisteredFamily[] = r.registerFont({ name: "Inter", data: bytes, weight: 400, style: "normal" });
  const lazy: FontDetails = { name: "Lazy", data: () => Promise.resolve(bytes) };
  const fams3 = await r.registerFont(lazy);
  const fams4 = await r.registerFont("https://example.com/font.ttf");
  void fams; void fams2; void fams3; void fams4;
  const removed: boolean = r.unregisterFont("Inter") || r.unregisterFont({ name: "Inter" });
  void removed;

  const fmt: OutputFormat = "webp";
  const css: CssInput[] = [".a { color: red }", { selector: ".b", style: { color: "blue" } }];
  const images: ImageSource[] = [{ src: "logo", data: bytes }, { src: "lazy", data: async () => bytes }];
  const opts: RenderOptions = { width: 1200, height: 630, format: fmt, quality: 80, devicePixelRatio: 2, css, images, timeMs: 0, fontFamilies: ["Inter"] };
  const png: Uint8Array = r.renderSync(node, opts);
  const png2: Uint8Array = await r.render("<div>html</div>", { format: "png" });
  const png3: Uint8Array = await r.render({ json: JSON.stringify(node) });
  const url: string = r.renderAsDataUrlSync(node, { format: "jpeg" });
  const url2: string = await r.renderAsDataUrl(node);
  const svg: string = r.renderSvgSync(node);
  const svg2: string = await r.renderSvg(node, { width: 10, height: 10 });
  const m: MeasuredNode = r.measureSync(node, { width: 100 });
  const m2: MeasuredNode = await r.measure(node);
  const t: [number, number, number, number, number, number] = m.transform;
  void png; void png2; void png3; void url; void url2; void svg; void svg2; void m2; void t;
  m.children[0]?.runs[0]?.x.toFixed();

  const prepared: Prepared = await r.prepare(node, { fonts: [bytes] });
  r.renderSync(prepared);
  const anim: RenderAnimationOptions = { scenes: [{ node, durationMs: 500 }], width: 100, height: 100, fps: 30, format: "gif" };
  const a1: Uint8Array = r.renderAnimationSync(anim);
  const a2: Uint8Array = await r.renderAnimation(anim);
  const a3: Uint8Array = await r.renderAnimation(await r.prepareAnimation(anim), { signal: new AbortController().signal });
  void a1; void a2; void a3;

  const mem: number = r.memoryBytes() + Renderer.memoryBytes();
  void mem;
  r.clearFonts();
  r.free();
  r[Symbol.dispose]();

  const f: Readonly<Features> = features;
  const hasSvg: boolean = f.renderSvg && core.features.woff;
  void hasSvg;
  setGlyphCacheMaxBytes(1024);

  const fr = new FullRenderer();
  fr.renderSync(node);

  const w: { builtIn: boolean } = await loadWoff();
  await loadWoff(woffWasm);
  const sfnt: Uint8Array = decodeWoff(bytes);
  void w; void sfnt;

  // @ts-expect-error unknown output format
  r.renderSync(node, { format: "bmp" });
  // @ts-expect-error a node needs a type
  r.renderSync({ style: {} });
  // @ts-expect-error renderAnimation needs fps
  r.renderAnimationSync({ scenes: [], width: 1, height: 1 });
  // @ts-expect-error features are read-only
  features.css = true;
}
function backends(): void {
  const b: "wasm" | "native" = backend;
  const nb: "wasm" | "native" = nativeBackend;
  const cb: "wasm" | "native" = core.backend;
  // @ts-expect-error backend is a closed union
  const bad: "gpu" = backend;
  const m: WebAssembly.Module = coreWasmModule;
  core.initSync(coreWasmModule);
  const nr = new NativeRenderer();
  const png: Uint8Array = nr.renderSync({ type: "text", text: "native" });
  void b; void nb; void cb; void bad; void m; void png; void nativeInit; void native.features.css;
}
void backends;
void main;
