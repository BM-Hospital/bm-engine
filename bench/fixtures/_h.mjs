// Tiny node-tree builders. Containers are ALWAYS display:flex with explicit flexDirection;
// text ALWAYS carries an explicit fontFamily (default Inter).
export { asset } from "../lib/assets.mjs";
export const c = (style, children = []) => ({ type: "container", style: { display: "flex", flexDirection: "row", ...style }, children });
export const col = (style, children = []) => c({ flexDirection: "column", ...style }, children);
export const t = (text, style = {}) => ({ type: "text", text, style: { fontFamily: "Inter", ...style } });
export const img = (src, style = {}, width, height) => ({ type: "image", src, ...(width != null ? { width } : {}), ...(height != null ? { height } : {}), style });
/** Root filling the canvas. */
export const root = (style, children) => c({ width: "100%", height: "100%", ...style }, children);
export const rootCol = (style, children) => col({ width: "100%", height: "100%", ...style }, children);
export const box = (backgroundColor, w, h, extra = {}) => c({ width: w, height: h, backgroundColor, flexShrink: 0, ...extra });
export const pal = ["#ef4444", "#f97316", "#eab308", "#22c55e", "#06b6d4", "#3b82f6", "#8b5cf6", "#ec4899"];
export const lorem = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump! Sphinx of black quartz, judge my vow.";
