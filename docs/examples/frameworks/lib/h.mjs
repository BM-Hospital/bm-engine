// h(): a tiny hyperscript / JSX factory that builds bm-render node trees (docs/{en,vi}/frameworks/index.md;
// keep the two in sync). Usable as a JSX factory: esbuild --jsx-factory=h --jsx-fragment=Fragment.

/** h("div", { style }, ...children) -> container; h("img", { src, width, height }) -> image; strings -> text. */
export function h(tag, props, ...children) {
  const kids = children.flat(Infinity).filter((c) => c != null && typeof c !== "boolean")
    .map((c) => (typeof c === "object" ? c : { type: "text", text: String(c) }));
  if (typeof tag === "function") return tag({ ...props, children: kids }); // components
  const { children: _, ...meta } = props ?? {};
  if (tag === "img") return { type: "image", tagName: "img", ...meta }; // src, width, height, style
  return { type: "container", tagName: tag, ...meta, children: kids };  // style, tw, className, id, ...
}

/** <>...</> : returns the children array, which the parent h() flattens. */
export const Fragment = ({ children }) => children;
