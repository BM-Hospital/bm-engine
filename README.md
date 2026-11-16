# bm-render

[English](README.md) · [Tiếng Việt](README.vi.md)

A Zig library that turns node trees or HTML + CSS into PNG, JPEG, WebP, SVG, animations and PDF. Runs as a native addon on Node.js when available, with WebAssembly fallback and support for browsers and edge runtimes.

## Install

```sh
npm install bm-render
```

## Create an image

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont(readFileSync("./fonts/Inter-Regular.ttf"));

const png = await renderer.render({
  type: "container",
  style: {
    display: "flex", width: "100%", height: "100%",
    alignItems: "center", justifyContent: "center",
    backgroundColor: "#18181b", color: "white", fontSize: 64,
  },
  children: [{ type: "text", text: "Hello from bm-render" }],
}, { width: 1200, height: 630 });

writeFileSync("card.png", png);
```

Provide the font file at the example path before running it. Reuse the renderer so each image does not reload fonts.

## Documentation

- [Getting started](docs/en/getting-started.md)
- [Images](docs/en/image/index.md)
- [PDF](docs/en/pdf/index.md)
- [Choose an output](docs/en/outputs-compared.md)
- [Profiles and size](docs/en/profiles-and-size.md)
- [Benchmark](docs/en/benchmark.md)
- [Troubleshooting](docs/en/troubleshooting.md)

## License and attribution

bm-render is licensed under the [MIT License](LICENSE). Copyright (c) 2026 hunghg255.
Third-party code and data it builds on are credited in [NOTICE](NOTICE) and
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
