# Tài liệu bm-render

bm-render là thư viện viết bằng Zig, dùng để chuyển cây node hoặc HTML + CSS thành ảnh và tài liệu PDF. Thư viện chạy bằng addon native trên Node.js khi có sẵn, và bằng WebAssembly trên trình duyệt cùng các môi trường khác.

## Bắt đầu từ đâu?

1. [Cài đặt](getting-started.md) package và chọn môi trường chạy.
2. Làm theo [ví dụ tạo ảnh đầu tiên](image/index.md) hoặc [ví dụ tạo PDF đầu tiên](pdf/index.md).
3. Thử thay đổi nội dung trong [Image Playground](image/playground.md) hoặc [PDF Playground](pdf/playground.md).

## Chọn loại đầu ra

| Bạn muốn làm gì? | Đọc trang |
|:--|:--|
| Tạo ảnh chia sẻ, thumbnail, banner | [Ảnh](image/index.md) |
| Tạo hóa đơn, báo cáo, vé có nhiều trang | [PDF](pdf/index.md) |
| Chọn PNG, JPEG, WebP, SVG hay PDF | [Chọn đầu ra](outputs-compared.md) |
| Giảm dung lượng WebAssembly | [Profile và kích thước](profiles-and-size.md) |
| Hiểu backend và cách chạy song song | [Native và WebAssembly](native-vs-wasm.md) |

## Học theo nhu cầu

| Chủ đề | Hướng dẫn |
|:--|:--|
| Nội dung và bố cục ảnh | [Khái niệm](image/concepts.md), [style và layout](image/styles.md), [HTML và Tailwind](image/html-and-tailwind.md) |
| Chữ và hình ảnh | [Font](image/fonts.md), [typography](image/typography.md), [hình ảnh](image/images.md) |
| Tích hợp ứng dụng | [Framework](image/frameworks/index.md), [checklist tích hợp](image/migration/checklist.md) |
| Tài liệu nhiều trang | [Phân trang](pdf/pagination.md), [header và footer](pdf/headers-footers.md), [font trong PDF](pdf/fonts.md) |
| Tra cứu | [API ảnh](image/api.md), [CSS ảnh](image/css-support.md), [API PDF](pdf/api.md), [CSS PDF](pdf/css-support.md) |
| Khi kết quả chưa đúng | [Xử lý sự cố](troubleshooting.md), [hạn chế ảnh](image/limitations.md), [hạn chế PDF](pdf/limitations.md) |
| Đo tốc độ và so sánh | [Benchmark](benchmark.md) |
| Phát triển thư viện | [Build từ mã nguồn](building-from-source.md), [phát hành](publishing.md) |
