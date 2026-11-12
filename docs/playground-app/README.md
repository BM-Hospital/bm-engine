# bm-engine playground (source)

A static, framework-free playground (plain HTML + ES modules + CSS, no build step, no external requests) for
the bm-engine WebAssembly renderer. It is published as part of the documentation site: the **Playground**
page ([docs/en/playground.md](../en/playground.md), [docs/vi/playground.md](../vi/playground.md); `/playground`
and `/vi/playground` on the site) embeds a self-contained build of this folder.

```
npm run playground                                   # dev server, repo root: http://127.0.0.1:8080/docs/playground-app/
node docs/playground-app/build.mjs                   # self-contained build -> docs/playground-app/dist/
node docs/playground-app/serve.mjs --dist            # serve that build at /
npm run docs:build                                   # builds into docs/public/playground-app/ and then the whole site
```

- `config.js` is the only place that knows where the engine lives: dev = `../../js/` and `../../assets/fonts/`;
  `build.mjs` writes a `config.js` pointing at `./vendor/` into its output folder (`--out <dir>`, relative to
  this folder). It needs the prebuilt `js/*.wasm` (tracked in git), not Zig.
- `?profile=core|standard|full` picks the binary (one wasm instance per page, so switching reloads);
  `?lang=en|vi` and `?theme=light|dark` override the language and colour scheme (the docs site sets both and
  posts `{ type: "bm-playground:theme" }` messages when the site theme changes). State is kept in localStorage
  and, with **Share link**, in the URL hash.
- Test: `node bench/browser/playground-test.mjs` (headless Edge via puppeteer-core; screenshots in
  `docs/playground-app/screenshots/`, report in `bench/out/PLAYGROUND.md`).
- Deployment: the build output is plain static files, so it is deployed with the docs site (Vercel, see
  `vercel.json` at the repository root). Any static host works if it serves `.wasm` as `application/wasm`.

Tiếng Việt: mã nguồn playground của bm-engine. Trang **Playground** của trang tài liệu (`/vi/playground`) nhúng bản
build độc lập của thư mục này; `npm run playground` chạy bản phát triển tại `http://127.0.0.1:8080/docs/playground-app/`.
