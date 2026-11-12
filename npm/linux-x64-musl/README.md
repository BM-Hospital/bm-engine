# bm-engine-linux-x64-musl

The native Node-API addon of [bm-engine](https://www.npmjs.com/package/bm-engine) for **Linux x64, musl (Alpine)**
(`os: linux`, `cpu: x64`, `libc: musl`).

Do not install this package yourself. `npm install bm-engine` lists every platform package as an optional
dependency and your package manager installs only the one that matches the machine. `bm-engine` loads it
when present and otherwise uses its WebAssembly build, with the same API and the same output bytes:

```js
import { backend } from "bm-engine";
console.log(backend); // "native" when this package is installed and loads, else "wasm"
```

It is released together with `bm-engine` at the same version (0.1.0), which pins it exactly; an
addon whose internal interface version does not match the installed `bm-engine` is ignored (wasm is used).
Requires Node-API 6 (`engines.node`: `>=10.20.0 <11 || >=12.17.0 <13 || >=14.0.0`); `bm-engine` itself requires Node.js 18+.

The x64 binary needs an x86-64-v2 CPU (SSE4.2, 2009+); on older CPUs it refuses to load and `bm-engine` uses wasm.

Status: cross-compiled and structurally verified (exports, imported symbols, CPU level), but **not yet executed on this platform** by the project; `bm-engine` falls back to WebAssembly if it does not load.

License: (MIT OR Apache-2.0). See LICENSE-MIT, LICENSE-APACHE, NOTICE and THIRD-PARTY-NOTICES.md.
