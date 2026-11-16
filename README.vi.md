# bm-render

[English](README.md) · [Tiếng Việt](README.vi.md)

Thư viện viết bằng Zig để chuyển cây node hoặc HTML + CSS thành PNG, JPEG, WebP, SVG, ảnh động và PDF. Chạy bằng addon native trên Node.js khi có sẵn, với WebAssembly dự phòng và hỗ trợ trình duyệt cùng môi trường edge.

## Cài đặt

```sh
npm install bm-render
```

## Ví dụ tạo ảnh

```js
import { readFileSync, writeFileSync } from "node:fs";
import { Renderer } from "bm-render";

const renderer = new Renderer();
renderer.registerFont(readFileSync("./fonts/Inter-Regular.ttf"));

const png = await renderer.render({
  type: "container",
  style: {
    display: "flex", width: "100%", height: "100%",
    alignItems: "center", justifyContent: "center",
    backgroundColor: "#18181b", color: "white", fontSize: 64,
  },
  children: [{ type: "text", text: "Hello from bm-render" }],
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
- [Benchmark](docs/vi/benchmark.md)
- [Xử lý sự cố](docs/vi/troubleshooting.md)

## Giấy phép và ghi công

bm-render được cấp phép theo [MIT License](LICENSE). Copyright (c) 2026 hunghg255.
Mã và dữ liệu bên thứ ba mà bm-render dựa vào được ghi công trong [NOTICE](NOTICE) và
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
