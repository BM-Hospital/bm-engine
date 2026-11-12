---
title: Playground
sidebar: false
aside: false
pageClass: playground-page
---

# Playground

[English](../../en/image/playground.md) · [Tiếng Việt](playground.md)

Playground chạy bản build WebAssembly thật của bm-engine ngay trong trình duyệt: thử đầu vào node JSON,
HTML và Tailwind, so sánh ba profile, xem layout bằng `measure()` và xuất mọi định dạng đầu ra. Không có
gì được tải lên máy chủ; font và ảnh bạn thêm vào chỉ nằm trong trang.

<ClientOnly>
  <PlaygroundFrame lang="vi" mode="image" />
</ClientOnly>

## Tính năng

- Chọn profile (`core` / `standard` / `full`); khi đổi, trang được tải lại với
  `?profile=core|standard|full` vì mỗi trang chỉ giữ một instance wasm. Mã nguồn, tùy chọn và ảnh đang
  soạn được khôi phục từ `localStorage`.
- Đầu vào: node JSON, HTML, Tailwind; tùy chọn `css`; tải font và ảnh lên.
- Đầu ra: PNG, JPEG, WebP, raw, SVG (`renderSvg`) và WebP / APNG / GIF động, kèm thời gian render, tải
  xuống và "sao chép data URL".
- Lớp phủ `measure()`, các mẫu có sẵn (thẻ OG, thẻ blog, chữ tiếng Việt, emoji, ảnh SVG, bài viết HTML,
  thẻ Tailwind, demo CSS, animation, gradient, bảng + float), giao diện tiếng Anh / tiếng Việt.
- **Share link** đặt trạng thái (đã nén deflate) vào hash của URL.
- **Đầu ra PDF**: nút chuyển phía trên ứng dụng mở [playground PDF](../pdf/playground.md), cùng ứng dụng
  ở chế độ PDF (`?mode=pdf`); nội dung đang soạn được giữ nguyên.

Những mẫu cần tính năng mà profile đang chọn không có sẽ hiện thông báo rõ ràng hoặc render ở dạng giản
lược (ví dụ thẻ Tailwind trên `core`), nên playground là cách nhanh để thấy mỗi profile bỏ đi những gì.

## Chạy cục bộ

Mã nguồn playground nằm ở [docs/playground-app/](../../playground-app/README.md) (HTML, ES module và CSS
thuần, không framework, không gọi mạng ngoài). Từ một bản checkout có sẵn các binary `js/*.wasm` (đã build
sẵn trong repository, hoặc chạy `node scripts/build.mjs`):

```sh
npm run playground          # = node docs/playground-app/serve.mjs -> http://127.0.0.1:8080/docs/playground-app/
npm run docs:dev            # toàn bộ trang tài liệu, có playground -> http://localhost:5173/vi/playground
```

Trang phát triển nạp engine từ `../../js/` và font từ `../../assets/fonts/`; bản build tài liệu
(`npm run docs:build`) chạy `docs/playground-app/build.mjs` để chép ứng dụng, `js/*.mjs`, các tệp `.wasm`
và font mặc định vào `docs/public/playground-app/` (`vendor/`), và trang tài liệu nhúng bản đó. Cả hai cách bố
trí được mô tả trong `config.js`. Ứng dụng nhận `?lang=en|vi` và `?theme=light|dark`.

Kiểm thử tự động: `node bench/browser/playground-test.mjs` (Edge / Chrome headless qua puppeteer-core;
kiểm tra server phát triển trên cả ba profile, bản build độc lập và trang playground của trang tài liệu đã
build; ghi `bench/out/PLAYGROUND.md`).
