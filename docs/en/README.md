# bm-engine documentation

[English](README.md) · [Tiếng Việt](../vi/README.md)

User documentation for bm-engine 0.1.0, a Zig → WebAssembly port of the takumi image renderer. Start
with Getting started; the API reference and the CSS support matrix are the pages you will come back to.

| Page | What it covers |
|:--|:--|
| [Getting started](getting-started.md) | Install, Node.js, browsers, bundlers, Workers / Deno / Bun, choosing a profile, fonts, images, output formats |
| [API reference](api.md) | `init`, `features`, `Renderer` and every method, node format, render options, errors, limits, memory model, WOFF add-on |
| [CSS and feature support](css-support.md) | Feature matrix with minimum profile and equivalence status, Tailwind, HTML, SVG, animations, known gaps, every supported property |
| [Profiles and size](profiles-and-size.md) | What `core` / `standard` / `full` contain, sizes, per-feature cost, custom builds, the WOFF add-on |
| [Differences from takumi](differences-from-takumi.md) | Migration guide, API and rendering differences, takumi behaviours reproduced on purpose |
| [Benchmark](benchmark.md) | Speed, size, memory and pixel equivalence against takumi 2.20, and how to reproduce |
| [Building from source](building-from-source.md) | Zig toolchain, build / test / fuzz commands, repository layout, contributing |
| [Playground](playground.md) | The in-browser playground (embedded in the documentation site), running it locally |
| [Troubleshooting](troubleshooting.md) | Missing text, collapsed containers, profile errors, images, wasm loading, memory, DPR, Vietnamese, emoji |

Developer documents (in the parent folder): [ARCHITECTURE.md](../ARCHITECTURE.md),
[TAKUMI_NOTES.md](../TAKUMI_NOTES.md), [CONVENTIONS.md](../CONVENTIONS.md),
[BENCHMARK.md](../BENCHMARK.md) (full benchmark report, Vietnamese), [RESULTS_FULL.md](../RESULTS_FULL.md).
