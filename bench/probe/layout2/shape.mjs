// How takumi's measure() reports text nodes, spans, inline-blocks, images, pseudo boxes.
import { both } from "./lib.mjs";
const F = { fontFamily: "Inter", fontSize: 16 };
const blk = (children, st = {}) => ({ type: "container", style: { display: "block", ...F, ...st }, children });
await both("text-only bare", blk([{ type: "text", text: "Hello " }, { type: "text", text: "world" }]));
await both("text styled", blk([{ type: "text", text: "Hello ", style: { color: "red" } }, { type: "text", text: "world" }]));
await both("span container", blk([{ type: "text", text: "A " }, { type: "container", children: [{ type: "text", text: "inner" }] }, { type: "text", text: " B" }]));
await both("inline-block", blk([{ type: "text", text: "A " }, { type: "container", style: { display: "inline-block", width: 50, height: 20, backgroundColor: "red" }, children: [{ type: "text", text: "x" }] }, { type: "text", text: " B" }]));
await both("image inline", blk([{ type: "text", text: "A " }, { type: "image", src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==", width: 10, height: 10 }, { type: "text", text: " B" }]));
await both("flex with text", { type: "container", style: { display: "flex", ...F }, children: [{ type: "text", text: "A" }, { type: "text", text: "B", style: { color: "red" } }] });
await both("block mixed block+inline", blk([{ type: "text", text: "A" }, { type: "container", style: { display: "block" }, children: [{ type: "text", text: "inner" }] }, { type: "text", text: "B" }]));
await both("root text", { type: "text", text: "Root text", style: F });
