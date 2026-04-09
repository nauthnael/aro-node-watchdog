# 🚀 ARO Node Watchdog v1.3.5

Công cụ giám sát chuyên nghiệp và tự động khôi phục dành cho **ARO DePIN Node** trên Linux VPS.

## ⚡ Cài đặt nhanh (One-liner)

Sao chép và dán dòng lệnh bên dưới vào terminal của bạn (thay `TOKEN_CUA_BAN` và `ID_CUA_BAN` bằng thông tin của bạn). **Yêu cầu phải chạy dưới quyền Root (`sudo`)**:

```bash
curl -fsSL https://raw.githubusercontent.com/nauthnael/aro-node-watchdog/main/aro-watchdog.sh -o aro-watchdog.sh && chmod +x aro-watchdog.sh && sudo bash aro-watchdog.sh init --token "TOKEN_CUA_BAN" --chatid "ID_CUA_BAN" && sudo bash aro-watchdog.sh setup
```

> **Note:** Kể từ v1.3.5, Watchdog **bắt buộc** gọi bằng quyền Root (`sudo bash ...`) để đọc được thư mục Log của ARO, quản lý tiến trình của các user và thiết lập background service một cách hoàn hảo. Yên tâm là tool sẽ "tự hạ quyền" (drop privileges) xuống ứng với user ARO lúc khởi chạy con Node chứ không bắt Node chạy bằng Root.

## 🛠 Tính năng
- **Fix lỗi treo (Hung detection):** Tự động phát hiện khi log không cập nhật sau 10 phút.
- **Fix lỗi chết (Process crash):** Tự khởi động lại ngay khi tiến trình biến mất.
- **Systemd Linger:** Tự động thiết lập `loginctl enable-linger` đảm bảo background hoạt động vĩnh viễn cả khi tắt SSH.
- **Multi-user Support:** Hoạt động trơn tru dù bạn cài Tool ở tài khoản Root nhưng ARO chạy ở `ubuntu` hay `vpsadmin`.
- **Báo cáo Reward:** Tự động gửi lợi nhuận ngày hôm trước vào 7h sáng mỗi ngày qua Telegram.
- **Hỗ trợ Cloud VPS:** Hỗ trợ chuẩn xác các VPS có phân quyền phức tạp (AWS, Google Cloud, Oracle) qua các cơ chế non-interactive terminal (`sudo -u`).

## 💻 Các lệnh quan trọng
- `sudo bash aro-watchdog.sh setup`: Cài đặt hệ thống + Chạy + Confirm bằng Live Log.
- `sudo bash aro-watchdog.sh status`: Kiểm tra tình trạng node và xem Reward.
- `sudo bash aro-watchdog.sh report`: Test tính năng báo cáo Telegram.
- `./aro-watchdog.sh log`: Đọc log xử lý của tool (có thể chạy bình thường không cần root).

---
**GitHub:** [nauthnael/aro-node-watchdog](https://github.com/nauthnael/aro-node-watchdog)  
**Author:** [tuangg](https://x.com/tuangg)
