---
title: Playground PDF
sidebar: false
aside: false
pageClass: playground-page
---

# Playground PDF

[English](../../en/pdf/playground.md) · [Tiếng Việt](playground.md)

Playground PDF chạy bản build WebAssembly thật của `bm-render/pdf` (`bm_render.pdf.wasm`) ngay trong trình
duyệt: viết node JSON, HTML hoặc Tailwind, đặt khổ trang, header, footer, metadata và các tiêu chuẩn, rồi xem
file PDF mà engine ghi ra. Không có gì được tải lên máy chủ; font và ảnh bạn thêm vào chỉ nằm trong trang.

<ClientOnly>
  <PlaygroundFrame lang="vi" mode="pdf" />
</ClientOnly>

## Tính năng

- Cùng trình soạn thảo với [playground ảnh](../image/playground.md): đầu vào node JSON, HTML và Tailwind,
  tuỳ chọn `css`, tải font và ảnh lên. Chuyển giữa Ảnh và PDF vẫn giữ nguyên nội dung đang soạn.
- Mọi tuỳ chọn lấy từ [`PdfRenderOptions`](api.md#render-options): khổ giấy (các khổ có sẵn hoặc tuỳ
  chỉnh) và `landscape`, lề (để trống = `auto`), phân trang hoặc một trang (`viewport`), band `header` và
  `footer` với bộ đếm `pageNumber` / `totalPages`, `pages.first`, `pageRanges`, `backgroundColor`,
  `metadata` (tiêu đề, tác giả, chủ đề, từ khoá, ngày tạo), `lang`, `outline`, `tagged` (kể cả PDF/UA
  `ua1` / `ua2`), `pdfa` (chỉ chọn được các tổ hợp mà typings cho phép) và `uncoveredText`. Lỗi của engine,
  ví dụ lỗi kiểm tra PDF/UA, được hiển thị nguyên văn.
- Mẫu có sẵn: hoá đơn có footer số trang, bài viết A5 nhiều trang có bookmark và orphans / widows, báo
  cáo có header bảng lặp lại ở mỗi trang, vé sự kiện trên một trang khổ tuỳ chỉnh, tài liệu PDF/UA-1 có
  alt text, tiếng Việt và các hệ chữ khác, liên kết với mục lục dựng từ `targetPageNumber`.
- Phần xem trước dùng trình xem PDF có sẵn của trình duyệt. Khi không có (điện thoại, hoặc khi chọn
  **Xem trước: Trang vẽ bằng pdf.js**) các trang được vẽ bằng [pdf.js](https://mozilla.github.io/pdf.js/),
  do chính trang tài liệu phục vụ và chỉ tải cho phần xem trước đó.
- Số trang, dung lượng file, thời gian render (trung vị của các lần render gần nhất), bộ nhớ wasm và, với
  `measure()`, kích thước tài liệu sau khi layout.
- **Tải .pdf**, **Mở trong tab mới**, **Liên kết chia sẻ** (mã nguồn và mọi tuỳ chọn nằm trong hash của
  URL) và **Sao chép mã**: chép một module Node.js tạo lại đúng bản render đó bằng `PdfRenderer`.

Engine không kèm font nào: playground đăng ký Inter và Noto Sans, giống playground ảnh. Chữ thuộc hệ chữ mà
các font này không có cần tải font lên (hoặc dùng `uncoveredText`).

## Chạy cục bộ

```sh
npm run playground          # http://127.0.0.1:8080/docs/playground-app/?mode=pdf
```

Engine PDF (`js/pdf.mjs` và `bm_render.pdf.wasm`, khoảng 1,5 MiB) chỉ được tải khi dùng chế độ PDF, nên
playground ảnh không phải tải nó. Ứng dụng cũng nhận `?mode=image|pdf`, `?lang=en|vi` và
`?theme=light|dark`; mã nguồn nằm ở [docs/playground-app/](../../playground-app/README.md).
