// `node --import ./lib/native-hooks.mjs probe/<fuzzer>.mjs ...`: runs an existing wasm probe / fuzzer unchanged
// against the native addon. The probes import "../../js/index.mjs" and call `bm.initSync(wasmBytes)`; this
// resolve hook hands them js/node-native.mjs instead (same API, initSync is a no-op there).
import { registerHooks } from "node:module";

const native = new URL("../../js/node-native.mjs", import.meta.url).href;
registerHooks({
  resolve(specifier, context, nextResolve) {
    const r = nextResolve(specifier, context);
    if (/\/js\/index\.mjs$/.test(r.url) && context.parentURL && /\/bench\/probe\//.test(context.parentURL)) return { ...r, url: native };
    return r;
  },
});
