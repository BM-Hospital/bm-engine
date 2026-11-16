// Module Web Worker (recipes.md / vite-browser.md): owns the wasm instance and the fonts, renders off the main thread.
import { init, Renderer } from "/node_modules/bm-render/js/standard.mjs"; // with a bundler: "bm-render/standard"

const ready = (async () => {
  await init(); // fetches bm_render.standard.wasm next to standard.mjs
  const renderer = new Renderer();
  const font = await (await fetch("/fonts/Inter-Regular.ttf")).arrayBuffer();
  renderer.registerFont({ name: "Inter", data: font });
  return renderer;
})();

self.onmessage = async ({ data: { id, node, options } }) => {
  try {
    const renderer = await ready;
    const png = renderer.renderSync(node, options);
    self.postMessage({ id, png }, [png.buffer]); // transfer, no copy
  } catch (error) {
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};
