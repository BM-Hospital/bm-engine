# Tài liệu bm-engine

[English](../en/README.md) · [Tiếng Việt](README.md)

Tài liệu người dùng cho bm-engine 0.1.0, bản port bộ render ảnh takumi sang Zig → WebAssembly. Hãy bắt
đầu từ trang Bắt đầu; tham chiếu API và ma trận hỗ trợ CSS là hai trang bạn sẽ quay lại nhiều nhất.

| Trang | Nội dung |
|:--|:--|
| [Bắt đầu](getting-started.md) | Cài đặt, Node.js, trình duyệt, bundler, Workers / Deno / Bun, chọn profile, font, ảnh, định dạng đầu ra |
| [Tham chiếu API](api.md) | `init`, `features`, `Renderer` và mọi method, định dạng node, tùy chọn render, lỗi, giới hạn, mô hình bộ nhớ, add-on WOFF |
| [Hỗ trợ CSS và tính năng](css-support.md) | Ma trận tính năng kèm profile tối thiểu và mức tương đương, Tailwind, HTML, SVG, animation, hạn chế đã biết, mọi thuộc tính được hỗ trợ |
| [Profile và kích thước](profiles-and-size.md) | `core` / `standard` / `full` gồm những gì, kích thước, chi phí từng tính năng, build tùy biến, add-on WOFF |
| [Khác biệt với takumi](differences-from-takumi.md) | Hướng dẫn chuyển đổi, khác biệt API và kết quả render, các hành vi của takumi được giữ nguyên có chủ đích |
| [Benchmark](benchmark.md) | Tốc độ, kích thước, bộ nhớ và mức tương đương điểm ảnh so với takumi 2.20, cách chạy lại |
| [Build từ mã nguồn](building-from-source.md) | Bộ công cụ Zig, lệnh build / test / fuzz, cấu trúc repository, đóng góp |
| [Playground](playground.md) | Playground chạy trên trình duyệt (nhúng trong trang tài liệu), chạy cục bộ |
| [Xử lý sự cố](troubleshooting.md) | Mất chữ, khối chứa bị co, lỗi do profile, ảnh, nạp wasm, bộ nhớ, DPR, tiếng Việt, emoji |

Tài liệu cho nhà phát triển (ở thư mục cha): [ARCHITECTURE.md](../ARCHITECTURE.md),
[TAKUMI_NOTES.md](../TAKUMI_NOTES.md), [CONVENTIONS.md](../CONVENTIONS.md),
[BENCHMARK.md](../BENCHMARK.md) (báo cáo benchmark đầy đủ), [RESULTS_FULL.md](../RESULTS_FULL.md).
