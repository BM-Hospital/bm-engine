# Hạn chế đã biết

## Những điều cần biết trước khi dùng

- **Font:** không có font đi kèm. Chữ không hiện khi chưa đăng ký font.
- **Tài nguyên:** renderer ảnh không tải ảnh hoặc `@font-face` từ URL. Hãy nạp byte và truyền vào API.
- **Đầu vào:** cây node thuần, `{ json }` hoặc HTML; React element cần chuyển đổi trước.
- **Layout:** `display` mặc định là `inline`, `box-sizing` mặc định là `border-box`. Đặt layout rõ ràng cho container.
- **Định dạng:** JPEG bỏ alpha; WebP đầu ra luôn lossless; SVG chuyển chữ thành đường nét.
- **Đo layout:** `measure()` trả vị trí hộp và dòng, không có nội dung chữ hoặc vị trí từng glyph.
- **Profile:** HTML, Tailwind, bảng và float cần `standard`; SVG đầu ra và animation cần `full`.
- **Bộ nhớ:** WebAssembly có thể tăng bộ nhớ nhưng không thu nhỏ lại sau mỗi lần render. Tái sử dụng renderer và giới hạn kích thước đầu vào.

## Những trường hợp cần kiểm tra riêng

Inline phức tạp, RTL kết hợp `pre-wrap`, line-clamp quanh float và thứ tự vẽ SVG có các giới hạn được ghi tại [CSS hỗ trợ](css-support.md#các-hạn-chế-đã-biết). SVG nhúng dùng mô hình chữ đơn giản; xem [biểu đồ](charts.md). Utility Tailwind tương tác không hoạt động vì không có trạng thái hover, focus hay trình duyệt tương tác.

## Tìm hướng dẫn phù hợp

[Xử lý sự cố](../troubleshooting.md) giúp tìm nguyên nhân khi kết quả sai. [API ảnh](api.md) mô tả tùy chọn và lỗi. Dùng [PDF](../pdf/index.md) khi cần tài liệu nhiều trang; xem [hạn chế PDF](../pdf/limitations.md).
