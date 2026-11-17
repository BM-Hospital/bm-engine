---
layout: home
title: bm-render
titleTemplate: Cây node và HTML + CSS thành ảnh và PDF

hero:
  name: bm-render
  text: Cây node và HTML + CSS thành ảnh và PDF
  tagline: Một package, một engine viết bằng Zig. Tạo ảnh chia sẻ, banner, hoá đơn và báo cáo trên Node.js, trình duyệt, Bun, Deno và edge worker, không cần trình duyệt headless.
  actions:
    - theme: brand
      text: Bắt đầu
      link: /vi/getting-started
    - theme: alt
      text: Tạo ảnh
      link: /vi/image/
    - theme: alt
      text: Tạo PDF
      link: /vi/pdf/

features:
  - icon: '<svg viewBox="0 0 24 24"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>'
    title: Chạy ở mọi nơi
    details: Addon native trên Node.js, WebAssembly trên trình duyệt, Bun, Deno và edge. Cùng API, kết quả giống nhau đến từng byte.
    link: /vi/native-vs-wasm
    linkText: Native và WebAssembly
  - icon: '<svg viewBox="0 0 24 24"><path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/></svg>'
    title: Chỉ mang theo thứ cần dùng
    details: "Bốn profile: core, standard, full và pdf. Chọn theo đầu vào và đầu ra để giữ bundle nhỏ."
    link: /vi/profiles-and-size
    linkText: Profile và kích thước
  - icon: '<svg viewBox="0 0 24 24"><path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/></svg>'
    title: Đo bằng số liệu thật
    details: "So với Takumi trên cùng đầu vào: <strong>nhanh hơn ~1,9×</strong> với ảnh PNG và <strong>nhanh hơn ~3,2×</strong> với PDF (native)."
    link: /vi/benchmark
    linkText: Xem benchmark
  - icon: '<svg viewBox="0 0 24 24"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="m9 8 6 4-6 4Z"/></svg>'
    title: Thử ngay trên trình duyệt
    details: Sửa HTML, Tailwind hoặc cây node và xem kết quả tức thì. Không có gì được gửi lên máy chủ.
    link: /vi/image/playground
    linkText: Mở playground
---

## Bắt đầu trong một phút

```sh
npm install bm-render
```

Đăng ký font trước khi render chữ (đầu ra ảnh không kèm sẵn font nào). Cùng một đoạn HTML có thể ra ảnh hoặc PDF:

::: code-group

```js [Ảnh (PNG)]
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const png = renderer.renderSync(
  `<div style="display:flex; width:100%; height:100%; align-items:center; justify-content:center;
               background:linear-gradient(135deg, #0f766e, #4f46e5); color:white; font:64px Inter">
     Hello from bm-render
   </div>`,
  { width: 1200, height: 630 },
);
writeFileSync("og.png", png);
```

```js [PDF]
import { readFileSync, writeFileSync } from "node:fs";
import { PdfRenderer } from "bm-render/pdf";

const pdf = new PdfRenderer();
pdf.registerFont({ name: "Inter", data: readFileSync("Inter-Regular.ttf") });

const bytes = await pdf.render(`
  <h1 style="font-family: Inter">Invoice #42</h1>
  <p style="font-family: Inter">Selectable, searchable vector text.</p>`);
writeFileSync("invoice.pdf", bytes); // A4, lề 10 mm, tự sang trang khi dài
```

:::

Tiếp theo: [cài đặt và điểm vào](/vi/getting-started) (native hay WebAssembly, bundler, edge),
[bắt đầu nhanh với ảnh](/vi/image/) hoặc [bắt đầu nhanh với PDF](/vi/pdf/).
