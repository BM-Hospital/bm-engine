---
layout: home
title: bm-engine
titleTemplate: Render HTML + CSS thành ảnh bằng WebAssembly

hero:
  name: bm-engine
  text: Cây node, HTML và CSS thành PNG, WebP, JPEG, SVG, ảnh động và PDF
  tagline: Bản port takumi sang Zig → WebAssembly, không phụ thuộc. Cùng định dạng node, tệp nhị phân nhỏ hơn 4–9×, render nhanh hơn và kết quả tương đương điểm ảnh trên cả 200 fixture benchmark. Chạy trên Node.js, trình duyệt, Bun, Deno và edge worker.
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
    details: "<strong>core</strong> 454.9 KiB (nhỏ hơn 9.3×), <strong>standard</strong> 878.1 KiB (4.8×), <strong>full</strong> 1 100.9 KiB (3.8×) so với 4 234.9 KiB của <code>@takumi-rs/wasm</code> 2.20. Brotli: 180.4 / 374.6 / 453.7 KiB."
    link: /vi/profiles-and-size
    linkText: Profile và kích thước
  - icon: ⚡
    title: Render nhanh hơn
    details: "Render PNG mất <strong>0.49×</strong> thời gian của takumi (geomean 1.59 so với 3.26 ms, nhanh hơn ở 191/191 ca); raw <strong>0.68×</strong> (nhanh hơn ở 171/191). Cold start 70.8 ms so với 178.4 ms (nhanh hơn 2.5×)."
    link: /vi/benchmark
    linkText: Benchmark
  - icon: 🎯
    title: Tương đương điểm ảnh với takumi
    details: "Cả <strong>200</strong> fixture dùng chung đều identical (74) hoặc equivalent (126) với takumi 2.20: 0 close, 0 different, 0 lỗi."
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
  - icon: 📄
    title: Đầu ra PDF nhiều trang
    details: "Một profile <code>pdf</code> riêng (khoảng 1.5 MB) port <code>takumi-pdf</code>: chữ bôi chọn được với font con, phân trang, header và footer, liên kết, bookmark, tệp đính kèm, PDF có thẻ và PDF/A."
    link: /vi/pdf
    linkText: Đầu ra PDF
  - icon: 🧪
    title: Thử ngay trên trình duyệt
    details: "Playground chạy engine thật ngay trong trình duyệt: mọi profile, đầu vào node JSON / HTML / Tailwind và mọi định dạng đầu ra."
    link: /vi/playground
    linkText: Mở playground
---
