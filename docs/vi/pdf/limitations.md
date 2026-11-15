# Hạn chế PDF

Chỉ dùng `bm-engine/pdf` để tạo PDF. Trên Node.js, entry này dùng native khi có sẵn và tự chuyển sang WebAssembly khi cần.

## Hạn chế đã biết

- **Font:** không có font dự phòng đi kèm. Đăng ký font trước khi render; `uncoveredText` quyết định cách xử lý ký tự không có glyph. Chữ có thể gây lỗi khi không đăng ký font nào.
- **JSX:** document và header/footer có thể nhận React element, nhưng component chạy không có React dispatcher; không dùng hook phụ thuộc dispatcher.
- **SVG font:** glyph dùng bảng SVG-in-OpenType dựa vào outline dự phòng. COLR và font màu bitmap có hỗ trợ.
- **Nội dung sinh:** ảnh URL trong pseudo content và bộ đếm CSS có hỗ trợ. Ảnh gradient trong generated content, gradient list marker và rule `::marker` tự viết chưa được xác minh đầy đủ.
- **Motion path:** các trường hợp thiếu viewport xác định hoặc có liên kết qua ranh giới trang cần kiểm tra riêng.
- **Lề trang:** `@page` hỗ trợ khổ giấy, lề, trang đầu/chẵn/lẻ và named page. Hộp lề như `@top-center` bị bỏ qua; dùng tùy chọn header/footer.
- **Ngắt trang:** `left`, `right`, `recto`, `verso` tạo ngắt nhưng không tự chèn trang trắng để đúng mặt giấy. `column` không phải ngắt trang.
- **Đổi bề rộng trang:** hàng bảng hoặc dòng flex tiếp diễn qua chỗ đổi khổ vẫn giữ bề rộng trước đó cho phần tiếp diễn.
- **Bảng:** header/footer lặp, tách hàng và `rowspan` có hỗ trợ. Kiểm tra viền gộp dày và header lặp bằng tài liệu thật.
- **Grid:** chưa có fragment riêng cho hàng grid; kiểm tra item `align-items: end` khi bị ngắt trước hàng.
- **Float, transform và clip:** các tổ hợp lồng nhau, nhất là kèm liên kết qua trang, cần được kiểm tra riêng.
- **Danh sách:** marker của mục bị chia qua trang nằm ở dòng đầu tiên của mục.
- **Tài liệu dài:** toàn bộ layout cuối được giữ tới khi ghi xong PDF. Chưa có cơ chế xuất từng trang với giới hạn bộ nhớ layout đang giữ.
- **Đầu vào lỗi:** kích thước quá lớn, font bị cắt cụt hoặc font thiếu `cmap` có thể bị từ chối. `margin: NaN` trở thành `null` khi mã hóa JSON và dùng lề mặc định.

## Tài nguyên và kiểm tra file

`prepare()` phân tích tài nguyên cần dùng, nạp font subset và `@font-face`, rồi tải ảnh thiếu. Hành vi này khác renderer ảnh; xem [API PDF](api.md). Đăng ký font rõ ràng và kiểm soát nguồn tài nguyên trong ứng dụng.

Các phép kiểm tra PDF/A và PDF/UA không phải chứng nhận. Luôn kiểm tra file thực tế của ứng dụng bằng công cụ phù hợp. Xem [khả năng truy cập và lưu trữ](accessibility.md), [CSS trong PDF](css-support.md) và [phân trang](pagination.md).
