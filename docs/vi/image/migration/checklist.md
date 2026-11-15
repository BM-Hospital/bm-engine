# Checklist tích hợp

Làm theo thứ tự này khi đưa bm-engine vào một ứng dụng hoặc chuyển mẫu ảnh có sẵn sang thư viện.

1. **Chọn đầu vào.** Dùng cây node thuần hoặc HTML với `standard` / `full`. Với JSX, xem [hàm dựng node](../frameworks/index.md#node-tree-không-cần-jsx).
2. **Đăng ký font.** Nạp dữ liệu font một lần cho mỗi renderer. Chữ không hiện nếu chưa có font.
3. **Khai báo layout.** Đặt `display: "flex"`, `"grid"` hoặc `"block"` cho các container cần bố cục. Mặc định là `inline`.
4. **Nạp ảnh.** Tự tải ảnh rồi truyền byte qua `images`; renderer ảnh không tải URL giúp bạn.
5. **Chọn kích thước và định dạng.** Bắt đầu với PNG; đặt nền đặc khi dùng JPEG.
6. **Trả HTTP response.** Đặt `Content-Type` theo định dạng và cache kết quả khi nội dung ít thay đổi.
7. **Tái sử dụng renderer.** Đăng ký font một lần; trên native dùng API async cho server, trên WebAssembly dùng worker nếu cần tránh chặn luồng chính.
8. **Kiểm tra mẫu thật.** Thử chữ dài, tiếng Việt, emoji, ảnh lỗi và nội dung vượt kích thước. Sau đó chọn profile nhỏ hơn nếu đủ tính năng.

Xem [framework](../frameworks/index.md), [xử lý sự cố](../../troubleshooting.md) và [hạn chế đã biết](../limitations.md).
