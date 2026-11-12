---
layout: home
title: bm-engine
titleTemplate: Render HTML + CSS thành ảnh bằng WebAssembly

hero:
  name: bm-engine
  text: Cây node, HTML và CSS thành PNG, WebP, JPEG, SVG và ảnh động
  tagline: Bản port takumi sang Zig → WebAssembly, không phụ thuộc. Cùng định dạng node, tệp nhị phân nhỏ hơn 4–9×, render nhanh hơn và kết quả tương đương điểm ảnh trên cả 250 fixture benchmark. Chạy trên Node.js, trình duyệt, Bun, Deno và edge worker.
  actions:
    - theme: brand
      text: Bắt đầu
      link: /vi/getting-started
    - theme: alt
      text: Playground
      link: /vi/playground
    - theme: alt
      text: Benchmark
      link: /vi/benchmark

features:
  - icon: 📦
    title: Nhỏ hơn takumi 4–9×
    details: "<strong>core</strong> 487.0 KiB (nhỏ hơn 8.7×), <strong>standard</strong> 933.9 KiB (4.5×), <strong>full</strong> 1 140.5 KiB (3.7×) so với 4 234.9 KiB của <code>@takumi-rs/wasm</code> 2.20. Brotli: 194.3 / 397.7 / 469.6 KiB."
    link: /vi/profiles-and-size
    linkText: Profile và kích thước
  - icon: ⚡
    title: Render nhanh hơn
    details: "Render PNG mất <strong>0.45×</strong> thời gian của takumi (geomean 1.33 so với 2.95 ms, nhanh hơn ở 248/250 ca); raw <strong>0.63×</strong> (nhanh hơn ở 229/250). Cold start 78.1 ms so với 193.8 ms (nhanh hơn 2.5×). Số liệu là của bản wasm; addon native còn nhanh hơn nữa (xem Native và WebAssembly)."
    link: /vi/benchmark
    linkText: Benchmark
  - icon: 🎯
    title: Tương đương điểm ảnh với takumi
    details: "Cả <strong>250</strong> fixture dùng chung đều identical (81) hoặc equivalent (169) với takumi 2.20: 0 close, 0 different, 0 lỗi."
    link: /vi/benchmark-report
    linkText: Báo cáo đầy đủ
  - icon: 🌐
    title: Chạy ở mọi nơi
    details: "Một tệp <code>.wasm</code> và một ES module nhỏ: Node.js, trình duyệt, bundler, Cloudflare Workers, Deno và Bun. Không addon native, không postinstall."
    link: /vi/getting-started
    linkText: Bắt đầu
  - icon: 🧩
    title: Ba profile
    details: "<code>core</code>: cây node, layout block / flex / grid, gradient, bóng đổ, filter. <code>standard</code>: + stylesheet, HTML, Tailwind, ảnh SVG, bảng, float. <code>full</code>: + emoji, chữ phức tạp, animation, <code>renderSvg</code>. Add-on WOFF 84.2 KiB tuỳ chọn cho <code>core</code>."
    link: /vi/css-support
    linkText: Hỗ trợ CSS và tính năng
  - icon: 🧪
    title: Thử ngay trên trình duyệt
    details: "Playground chạy engine thật ngay trong trình duyệt: mọi profile, đầu vào node JSON / HTML / Tailwind và mọi định dạng đầu ra."
    link: /vi/playground
    linkText: Mở playground
---
