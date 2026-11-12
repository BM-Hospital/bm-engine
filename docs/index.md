---
layout: home
title: bm-engine
titleTemplate: Render HTML + CSS to images with WebAssembly

hero:
  name: bm-engine
  text: Node trees, HTML and CSS to PNG, WebP, JPEG, SVG and animations
  tagline: A dependency-free Zig → WebAssembly port of takumi. Same node format, 4–9× smaller binaries, faster rendering, and pixel-equivalent output on all 250 benchmark fixtures. Runs in Node.js, browsers, Bun, Deno and edge workers.
  actions:
    - theme: brand
      text: Get started
      link: /getting-started
    - theme: alt
      text: Playground
      link: /playground
    - theme: alt
      text: Benchmark
      link: /benchmark

features:
  - icon: 📦
    title: 4–9× smaller than takumi
    details: "<strong>core</strong> 454.5 KiB (9.3× smaller), <strong>standard</strong> 877.5 KiB (4.8×), <strong>full</strong> 1 099.8 KiB (3.9×) vs. 4 234.9 KiB for <code>@takumi-rs/wasm</code> 2.20. Brotli: 180.3 / 374.5 / 453.4 KiB."
    link: /profiles-and-size
    linkText: Profiles and size
  - icon: ⚡
    title: Faster rendering
    details: "PNG render at <strong>0.49×</strong> takumi's time (1.59 vs 3.26 ms geomean, faster in 191/191 cases); raw at <strong>0.68×</strong> (faster in 171/191). Cold start 70.8 ms vs 178.4 ms (2.5× faster)."
    link: /benchmark
    linkText: Benchmark summary
  - icon: 🎯
    title: Pixel-equivalent to takumi
    details: "All <strong>250</strong> shared fixtures are identical (81) or equivalent (169) to takumi 2.20: 0 close, 0 different, 0 errors."
    link: /results-full
    linkText: Per-fixture results
  - icon: 🌐
    title: Runs everywhere
    details: "One <code>.wasm</code> plus a small ES module: Node.js, browsers, bundlers, Cloudflare Workers, Deno and Bun. No native addons, no postinstall."
    link: /getting-started
    linkText: Getting started
  - icon: 🧩
    title: Three profiles
    details: "<code>core</code>: node trees, block / flex / grid layout, gradients, shadows, filters. <code>standard</code>: + stylesheets, HTML, Tailwind, SVG images, tables, floats. <code>full</code>: + emoji, complex scripts, animations, <code>renderSvg</code>. Optional 84.2 KiB WOFF add-on for <code>core</code>."
    link: /css-support
    linkText: CSS and feature support
  - icon: 🧪
    title: Try it in the browser
    details: "The playground runs the real engine in your browser: every profile, node JSON / HTML / Tailwind input and every output format."
    link: /playground
    linkText: Open the playground
---
