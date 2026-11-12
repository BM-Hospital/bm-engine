# Tài liệu bm-engine

[English](../en/README.md) · [Tiếng Việt](README.md)

Tài liệu người dùng cho bm-engine 0.1.0, bản port bộ render takumi sang Zig. Một package gồm hai sản phẩm:
**Ảnh** (PNG, JPEG, WebP, SVG và ảnh động; `bm-engine`) và **PDF** (tài liệu phân trang; `bm-engine/pdf`). Mỗi
sản phẩm có thư mục riêng ([image/](image/index.md), [pdf/](pdf/index.md)); các trang dùng chung cho cả hai nằm ngay trong thư
mục này. Hãy bắt đầu từ [Bắt đầu](getting-started.md), rồi tới phần bắt đầu nhanh của sản phẩm bạn dùng.

## Gói (dùng chung)

| Trang | Nội dung |
|:--|:--|
| [Bắt đầu](getting-started.md) | Cài đặt, addon native và WebAssembly, các điểm vào của package, CommonJS, bundler, Workers / Deno / Bun, chọn profile |
| [Native và WebAssembly](native-vs-wasm.md) | Backend Node.js nào được dùng, mô hình thread, đầu ra trùng từng byte, nền tảng hỗ trợ, tốc độ / bộ nhớ / cold start so với wasm và takumi |
| [Profile và kích thước](profiles-and-size.md) | `core` / `standard` / `full` / `pdf` gồm những gì, kích thước, chi phí từng tính năng, build tùy biến, add-on WOFF |
| [So sánh Image, PDF và Paint](outputs-compared.md) | Ba loại đầu ra của takumi và phần bm-engine hỗ trợ |
| [Benchmark](benchmark.md) | Tốc độ, kích thước, bộ nhớ và mức tương đương điểm ảnh so với takumi 2.20, cách chạy lại |
| [Xử lý sự cố](troubleshooting.md) | Mất chữ, khối chứa bị co, lỗi do profile, ảnh, nạp wasm, bộ nhớ, DPR, tiếng Việt, emoji |
| [Build từ mã nguồn](building-from-source.md) | Bộ công cụ Zig, lệnh build / test / fuzz, cấu trúc repository, đóng góp |
| [Phát hành (maintainer)](publishing.md) | Phát hành chín package npm: thiết lập một lần, quy trình phát hành, xử lý khi lỗi, bản prerelease và dist-tag, CI |

## Ảnh

| Trang | Nội dung |
|:--|:--|
| [Bắt đầu nhanh với ảnh](image/index.md) | Render lần đầu trên Node.js và trong trình duyệt, font, ảnh, định dạng đầu ra |
| [Khái niệm](image/concepts.md) · [Playground](image/playground.md) | Mô hình node, kích thước và đơn vị; playground chạy trên trình duyệt |
| [Style](image/styles.md) · [HTML và Tailwind](image/html-and-tailwind.md) · [Font](image/fonts.md) · [Typography](image/typography.md) · [Hình ảnh](image/images.md) · [Bảng](image/tables.md) · [Biểu đồ](image/charts.md) · [Hiệu ứng](image/effects.md) | Nội dung, kèm ví dụ chạy được và kết quả |
| [Định dạng đầu ra](image/formats.md) · [Hoạt ảnh](image/animation.md) · [Hiệu năng](image/performance.md) | Render |
| [Framework](image/frameworks/index.md) | Next.js, Nuxt / Nitro, SvelteKit, Astro, TanStack Start, Hono / Express, Cloudflare Workers, Deno / Bun, Vite |
| [Tham chiếu API](image/api.md) | `init`, `features`, `Renderer` và mọi method, định dạng node, tùy chọn render, lỗi, giới hạn, mô hình bộ nhớ, add-on WOFF |
| [measure()](image/measure.md) · [Hỗ trợ CSS và tính năng](image/css-support.md) · [Công thức](image/recipes.md) · [Mẫu dựng sẵn](image/templates.md) | Tham chiếu |
| [Từ takumi](image/migration/from-takumi.md) · [Từ Satori](image/migration/from-satori.md) · [Khác biệt với takumi](image/differences-from-takumi.md) | Chuyển đổi |

## PDF

| Trang | Nội dung |
|:--|:--|
| [Bắt đầu nhanh với PDF](pdf/index.md) | `bm-engine/pdf`, tài liệu đầu tiên trên Node.js và trong trình duyệt, `measure`, các tùy chọn |
| [Khổ giấy, lề và viewport](pdf/page-size-and-viewport.md) · [Native và WebAssembly](pdf/native-and-wasm.md) | Hình dạng trang và tài liệu một trang; backend và kích thước profile `pdf` |
| [Phân trang](pdf/pagination.md) · [Header, footer và bộ đếm trang](pdf/headers-footers.md) · [Liên kết, bookmark, metadata, tệp đính kèm](pdf/links-metadata.md) · [Font trong PDF](pdf/fonts.md) · [Khả năng truy cập và lưu trữ](pdf/accessibility.md) | Hướng dẫn |
| [Công thức](pdf/recipes.md) · [Trả PDF từ framework](pdf/frameworks.md) | Hoá đơn, báo cáo, vé; HTTP handler |
| [Tham chiếu API PDF](pdf/api.md) · [CSS trong PDF](pdf/css-support.md) · [Khác biệt với takumi-pdf](pdf/differences-from-takumi.md) | Tham chiếu |

Tài liệu cho nhà phát triển (ở thư mục cha): [ARCHITECTURE.md](../ARCHITECTURE.md),
[TAKUMI_NOTES.md](../TAKUMI_NOTES.md), [CONVENTIONS.md](../CONVENTIONS.md),
[BENCHMARK.md](../BENCHMARK.md) (báo cáo benchmark đầy đủ), [RESULTS_FULL.md](../RESULTS_FULL.md).
