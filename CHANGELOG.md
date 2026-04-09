# Changelog

## [1.1.0] - 2026-04-09
### Fixed
- Sửa lỗi Regex parsing dữ liệu từ tệp log của ARO.
- Khắc phục lỗi phạm vi biến (scope) khi sử dụng `flock`.
- Sửa công thức tính Delta Reward (hỗ trợ số thực).
- Chống spam thông báo mất kết nối (giới hạn 1 thông báo/giờ).

### Updated
- Tối ưu lệnh chạy ARO: `DISPLAY=:20 /usr/bin/ARO`.
- Thêm cờ lệnh `--token` và `--chatid` hỗ trợ cài đặt nhanh qua Curl.
- Tự động tạo file `README.md` và `CHANGELOG.md` khi chạy lệnh `init`.
- Giao diện CLI mới với Banner ASCII chuyên nghiệp.

## [1.0.0] - 2026-04-09
### Added
- Bản phát hành đầu tiên theo yêu cầu của @tuangg.
- Tính năng giám sát chết/treo cơ bản.
- Hỗ trợ Systemd service, Runit và SysVinit.
