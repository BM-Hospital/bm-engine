---
layout: home
title: bm-engine
titleTemplate: Render HTML + CSS to images with WebAssembly

hero:
  name: bm-engine
  text: Node trees, HTML and CSS to PNG, WebP, JPEG, SVG, animations and PDF
  tagline: A dependency-free Zig → WebAssembly port of takumi. Same node format, 4–9× smaller binaries, faster rendering, and pixel-equivalent output on all 200 benchmark fixtures. Runs in Node.js, browsers, Bun, Deno and edge workers.
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
    details: "<strong>core</strong> 454.9 KiB (9.3× smaller), <strong>standard</strong> 878.1 KiB (4.8×), <strong>full</strong> 1 100.9 KiB (3.8×) vs. 4 234.9 KiB for <code>@takumi-rs/wasm</code> 2.20. Brotli: 180.4 / 374.6 / 453.7 KiB."
    link: /profiles-and-size
    linkText: Profiles and size
  - icon: ⚡
    title: Faster rendering
    details: "PNG render at <strong>0.49×</strong> takumi's time (1.59 vs 3.26 ms geomean, faster in 191/191 cases); raw at <strong>0.68×</strong> (faster in 171/191). Cold start 70.8 ms vs 178.4 ms (2.5× faster)."
    link: /benchmark
    linkText: Benchmark summary
  - icon: 🎯
    title: Pixel-equivalent to takumi
    details: "All <strong>200</strong> shared fixtures are identical (74) or equivalent (126) to takumi 2.20: 0 close, 0 different, 0 errors."
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
  - icon: 📄
    title: Paged PDF output
    details: "A separate <code>pdf</code> profile (about 1.5 MB) ports <code>takumi-pdf</code>: selectable text with subset fonts, pagination, headers and footers, links, bookmarks, attachments, tagged PDF and PDF/A."
    link: /pdf
    linkText: PDF output
  - icon: 🧪
    title: Try it in the browser
    details: "The playground runs the real engine in your browser: every profile, node JSON / HTML / Tailwind input and every output format."
    link: /playground
    linkText: Open the playground
---
