# Chọn đầu ra

Chọn theo cách người dùng sẽ xem kết quả. Ảnh phù hợp để hiển thị hoặc chia sẻ; PDF phù hợp để đọc, tìm kiếm và in tài liệu.

| Nhu cầu | API | Profile |
|:--|:--|:--|
| Ảnh PNG, JPEG hoặc WebP | `Renderer.render()` | `core`, `standard`, `full` |
| Điểm ảnh RGBA để xử lý tiếp | `Renderer.render()` với `format: "raw"` | `core`, `standard`, `full` |
| Đồ họa vector SVG | `Renderer.renderSvg()` | `full` |
| Ảnh động WebP, APNG hoặc GIF | `Renderer.renderAnimation()` | `full` |
| PDF nhiều trang, chữ tìm kiếm và bôi chọn được | `PdfRenderer.render()` từ `bm-render/pdf` | `pdf` |
| Đo vị trí và kích thước trước khi vẽ | `Renderer.measure()` | `core`, `standard`, `full` |

## Ảnh và SVG

Mỗi lần render ảnh dùng một canvas với `width` và `height` bạn chọn. Nội dung không tự chia trang. PNG giữ vùng trong suốt; JPEG bỏ alpha nên cần nền đặc; WebP đầu ra luôn lossless. SVG giữ hình dạng vector, nhưng chữ được chuyển thành đường nét và không còn là văn bản bôi chọn được.

Xem [bắt đầu với ảnh](image/index.md) và [định dạng đầu ra](image/formats.md).

## PDF

Dùng `bm-render/pdf` cho tài liệu có khổ giấy, lề, phân trang, header và footer. PDF có thể chứa chữ, liên kết, bookmark, metadata và tệp đính kèm. Các yêu cầu PDF/A hoặc PDF/UA cần cấu hình và kiểm tra riêng cho tài liệu của bạn.

Xem [bắt đầu với PDF](pdf/index.md), [phân trang](pdf/pagination.md) và [hạn chế đã biết](pdf/limitations.md).

## Đo layout

`measure()` trả về cây hộp và vị trí các dòng chữ. Kết quả không chứa đầy đủ lệnh vẽ, màu đã tính hay vị trí từng glyph; bm-render chưa cung cấp API xuất cây lệnh vẽ hoặc slide có thể chỉnh sửa.

Xem [measure()](image/measure.md).
