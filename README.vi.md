# bm-engine

[English](README.md) · [Tiếng Việt](README.vi.md)

Thư viện viết bằng Zig để chuyển cây node hoặc HTML + CSS thành PNG, JPEG, WebP, SVG, ảnh động và PDF. Chạy bằng addon native trên Node.js khi có sẵn, với WebAssembly dự phòng và hỗ trợ trình duyệt cùng môi trường edge.

## Cài đặt

```sh
npm install bm-engine
```

## Ví dụ tạo ảnh

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-engine";

const renderer = new Renderer();
renderer.registerFont(readFileSync("./fonts/Inter-Regular.ttf"));

const png = await renderer.render({
  type: "container",
  style: {
    display: "flex", width: "100%", height: "100%",
    alignItems: "center", justifyContent: "center",
    backgroundColor: "#18181b", color: "white", fontSize: 64,
  },
  children: [{ type: "text", text: "Hello from bm-engine" }],
}, { width: 1200, height: 630 });

writeFileSync("card.png", png);
```

Chuẩn bị file font ở đường dẫn trong ví dụ trước khi chạy. Tái sử dụng renderer để không phải nạp font lại cho từng ảnh.

## Tài liệu

- [Bắt đầu](docs/vi/getting-started.md)
- [Tạo ảnh](docs/vi/image/index.md)
- [Tạo PDF](docs/vi/pdf/index.md)
- [Chọn đầu ra](docs/vi/outputs-compared.md)
- [Profile và kích thước](docs/vi/profiles-and-size.md)
- [Benchmark so sánh với Takumi](docs/vi/benchmark.md)
- [Xử lý sự cố](docs/vi/troubleshooting.md)

## Giấy phép và ghi công

bm-engine được cấp phép theo [MIT License](LICENSE). Copyright (c) 2026 hunghg255.

bm-engine là sản phẩm phái sinh của **takumi** do Kane Wang phát triển (MIT OR Apache-2.0): phần lớn mã
được chuyển ngữ từ mã Rust của takumi (layout, vẽ, chữ, CSS, Tailwind, HTML, SVG, animation, codec), và
hành vi của nó được kiểm chứng bằng chính đầu ra của takumi. Mọi công lao thiết kế bộ render thuộc về dự
án takumi. Bản thân takumi đi theo Blink của Chromium và Skia; bm-engine còn port thuật toán và dữ liệu
từ tiny-skia, HarfBuzz, libwebp, libjpeg, Unicode / ICU, Brotli và các dự án khác. Xem [NOTICE](NOTICE)
và [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) để biết phần ghi công.
