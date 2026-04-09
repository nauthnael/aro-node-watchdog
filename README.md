# 🚀 ARO Node Watchdog v1.1.0

Công cụ giám sát chuyên nghiệp và tự động khôi phục dành cho **ARO DePIN Node** trên Linux VPS.

## ⚡ Cài đặt nhanh (One-liner)

Sao chép và dán dòng lệnh bên dưới vào terminal của bạn (thay `TOKEN` và `ID` bằng thông tin của bạn):

```bash
curl -fsSL https://raw.githubusercontent.com/nauthnael/aro-node-watchdog/main/aro-watchdog.sh -o aro-watchdog.sh && chmod +x aro-watchdog.sh && ./aro-watchdog.sh init --token "TOKEN_CUA_BAN" --chatid "ID_CUA_BAN" && ./aro-watchdog.sh install && ./aro-watchdog.sh start
```

## 🛠 Tính năng
- **Fix lỗi treo (Hung detection):** Tự động phát hiện khi log không cập nhật sau 10 phút.
- **Fix lỗi chết (Process crash):** Tự khởi động lại ngay khi tiến trình biến mất.
- **Báo cáo Reward:** Tự động gửi lợi nhuận ngày hôm trước vào 7h sáng mỗi ngày.
- **Quản lý Service:** Hỗ trợ cài đặt như một service hệ thống (Systemd/SysVinit).

## 💻 Các lệnh quan trọng
- `./aro-watchdog.sh status`: Kiểm tra tình trạng node.
- `./aro-watchdog.sh report`: Gửi báo cáo Reward ngay lập tức qua Telegram.
- `./aro-watchdog.sh log`: Theo dõi hoạt động của watchdog.

---
**GitHub:** [nauthnael/aro-node-watchdog](https://github.com/nauthnael/aro-node-watchdog)  
**Author:** [tuangg](https://x.com/tuangg)
**Connect:** [X.com/tuangg](https://x.com/tuangg)
