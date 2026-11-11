# bm-engine playground

## English

A static, framework-free playground (plain HTML + ES modules + CSS, no build step, no external requests) for
the bm-engine WebAssembly renderer. Features: profile selector (core / standard / full), node JSON / HTML /
Tailwind inputs, `css` option, font and image upload, PNG / JPEG / WebP / raw / SVG / animated WebP-APNG-GIF
output, render timing, download / copy data URL, `measure()` overlay, templates, EN / VI UI, state kept in
localStorage and in a shareable URL hash.

### Run locally

```
node playground/serve.mjs                # serves the repo root: http://127.0.0.1:8080/playground/
node playground/serve.mjs --port 3000
node playground/build.mjs && node playground/serve.mjs --dist     # the self-contained build
```

The dev page loads the engine from `../js/` and fonts from `../assets/fonts/`; the dist build uses `./vendor/`.
Both layouts are described by a single file, `config.js` (`build.mjs` writes a different `dist/config.js`).

Profiles: `js/index.mjs` keeps one wasm instance per module instance, so the selector reloads the page with
`?profile=core|standard|full`. Your source, options and images are restored from localStorage. The **Share
link** button puts the (deflate-compressed) state in the URL hash.

Test: `node bench/browser/playground-test.mjs` (headless Edge via puppeteer-core; writes
`playground/screenshots/*.png` and `bench/out/PLAYGROUND.md`).

### Deploy to GitHub Pages

1. `node playground/build.mjs` creates `playground/dist/` (HTML/JS/CSS, `vendor/` with `js/*.mjs`, `*.wasm` and
   the default fonts, plus `.nojekyll`). The `js/*.wasm` files must exist (build the engine first).
2. Copy `playground/pages.yml.example` to `.github/workflows/pages.yml`, set Settings > Pages > Source to
   "GitHub Actions", and push. The workflow is:

```yaml
name: playground-pages
on:
  push:
    branches: [main]
    paths: ["playground/**", "js/**", "assets/fonts/**"]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: true
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: node playground/build.mjs
      - uses: actions/upload-pages-artifact@v3
        with: { path: playground/dist }
      - id: deployment
        uses: actions/deploy-pages@v4
```

Alternatively publish the contents of `playground/dist/` to a `gh-pages` branch by hand.

## Tiếng Việt

Playground tĩnh, không framework (HTML + ES module + CSS thuần, không bước build, không gọi mạng ngoài) cho bộ
render WebAssembly bm-engine: chọn profile (core / standard / full), nhập node JSON / HTML / Tailwind, tuỳ chọn
`css`, tải font và ảnh lên, xuất PNG / JPEG / WebP / raw / SVG / WebP-APNG-GIF động, đo thời gian render, tải
xuống / sao chép data URL, lớp `measure()`, các mẫu có sẵn, giao diện EN / VI, trạng thái lưu trong localStorage
và trong hash URL để chia sẻ.

### Chạy cục bộ

```
node playground/serve.mjs                # phục vụ thư mục gốc repo: http://127.0.0.1:8080/playground/
node playground/serve.mjs --port 3000
node playground/build.mjs && node playground/serve.mjs --dist     # bản build độc lập
```

Bản dev nạp engine từ `../js/` và font từ `../assets/fonts/`; bản dist dùng `./vendor/`. Hai cách bố trí này chỉ
được khai báo trong `config.js`. Vì `js/index.mjs` chỉ giữ một wasm instance, đổi profile sẽ tải lại trang với
`?profile=...`; nội dung đang soạn được khôi phục từ localStorage. Nút **Share link** đặt trạng thái (đã nén) vào hash URL.

Kiểm thử: `node bench/browser/playground-test.mjs` (Edge headless qua puppeteer-core).

### Triển khai lên GitHub Pages

1. Chạy `node playground/build.mjs` để tạo `playground/dist/` (cần có sẵn các tệp `js/*.wasm`).
2. Sao chép `playground/pages.yml.example` thành `.github/workflows/pages.yml` (nội dung ở phần English phía trên),
   vào Settings > Pages > Source chọn "GitHub Actions", rồi push lên nhánh `main`.
3. Hoặc đẩy thủ công nội dung `playground/dist/` lên nhánh `gh-pages`.
