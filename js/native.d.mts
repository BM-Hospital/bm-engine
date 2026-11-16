// bm-render/native: the native Node-API addon (Node.js, Bun, Deno). Same API as bm-render (./index.d.mts); the
// import throws when no addon is installed for the platform. init() / initSync() are accepted and do nothing.
export * from "./index.mjs";
export { default } from "./index.mjs";
