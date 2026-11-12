// flexByDefault(): mimics satori / next/og, where every element is a flex container
// (migration/from-satori.md). Containers that already set `display` keep it.
export function flexByDefault(node) {
  if (!node || node.type !== "container") return node;
  return { ...node, style: { display: "flex", ...node.style }, children: node.children?.map(flexByDefault) };
}
