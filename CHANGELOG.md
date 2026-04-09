# Changelog

## [1.2.1] - 2026-04-09
### Fixed
- parse_node_info(): syntax error "f" instead of "fi" caused crash
  when called without a log file present (affects status, test-notify,
  report, and every restart success notification)
- Removed dead "init)" block from CLI case statement — init is fully
  handled before case and never reaches it
- do_setup() fallback: kill existing watchdog before starting new
  background instance to prevent duplicate watchdog processes

## [1.2.0] - 2026-04-09
### Fixed
- verify_startup() now re-detects the newest ARO log file on every poll iteration, fixing false "restart failed" when ARO creates a new timestamped log file after relaunch
- restart_aro() no longer does a fixed sleep before verify; detection is now dynamic and starts immediately
- LIBGL_ALWAYS_SOFTWARE and XAUTHORITY env vars restored in restart_aro() launch command

### Changed
- Default BACKOFF_TIMES changed from "30 60 120 300 600" to "0 0 30 60 120" — first two restart attempts are now immediate
- Backoff sleep is skipped entirely when value is 0 (no log noise)

### Added
- New command "setup": installs service + starts it + shows live log confirmation in one step
- setup command falls back to background mode with linger hint if systemd user service fails to start
- README one-liner updated to use "setup" instead of "install && start"
- loginctl enable-linger note added to README

## [1.1.2] - 2026-04-09
### Fixed
- Banner now shown only once at script start; footer only on clean exit via trap, never on error paths
- Added validate_telegram_credentials() to detect placeholder and malformed --token / --chatid values before saving to config
- Interactive prompt allows user to skip invalid credentials and configure later; auto-skips in non-interactive mode
- Invalid credentials are never written to config file

## [1.1.1] - 2026-04-09
### Fixed
- Boot-order bug: config validation ran before init command handler, causing "Configuration file not found" error on first run
- create_default_config() now creates SCRIPT_DIR if missing
- CLI flags --token/--chatid now applied during init even if config file already exists
- Telegram validation skipped for commands that do not need it

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
