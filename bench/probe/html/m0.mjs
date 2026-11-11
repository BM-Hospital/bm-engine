import { Renderer } from "@takumi-rs/wasm/node";
const r = new Renderer();
const src = process.argv[2];
const m = await r.measure(src, { width: 400, height: 200 });
console.log(JSON.stringify(m, (k, v) => (k === "transform" ? undefined : v), 1).slice(0, 3000));
