# Changelog

## [1.3.2] - 2026-04-09
### Changed
- do_setup(): loginctl enable-linger now runs automatically
  before service install instead of showing a manual hint
- enable_linger() added: checks if linger already active,
  tries direct then sudo, falls back to hint if both fail
- Linger step shown as [0/3] before service installation
  so it takes effect before systemd service starts
- Removed redundant linger hint from systemd fallback block

## [1.3.1] - 2026-04-09
### Fixed
- detect_aro_user(): root (uid=0) excluded from scan — prevents
  confusing "ARO should not run as root" error when only /root
  home directory has ARO data folder
- detect_aro_user() and resolve_effective_user() moved to after
  log() definition to ensure log() is always available when called
- resolve_effective_user(): added idempotency guard
  (EFFECTIVE_USER_RESOLVED flag) — prevents duplicate log entries
  when called from multiple CLI commands
- do_setup(): now clears STATE_FILE and stale PID_FILE at start,
  ensuring watchdog always begins with a clean slate after reinstall
- Telegram notifications now show EFFECTIVE_USER (actual ARO user)
  instead of CURRENT_USER (script runner) in all message templates
- do_setup(): added 4-second delay before tailing watchdog log so
  new log entries are visible instead of stale history

## [1.3.0] - 2026-04-09
### Fixed
- All ARO process operations (pgrep, pkill, launch) now use
  EFFECTIVE_USER instead of CURRENT_USER — fixes false crash
  detection when watchdog runs as root but ARO runs as another user
- ARO launch in restart_aro() uses correct user via "su" when
  EFFECTIVE_USER differs from CURRENT_USER
- EFFECTIVE_HOME used for ARO log dir and Xauthority paths
- Max retry sleep reduced from 1 hour to 12 minutes; retry
  counter resets after sleep so watchdog resumes automatically

### Added
- detect_aro_user(): auto-detects ARO user by scanning all home
  directories for ARO log folder; falls back to CRD process detection
- resolve_effective_user(): validates ARO_RUN_USER (blocks root,
  checks user exists), resolves EFFECTIVE_USER and EFFECTIVE_HOME,
  updates ARO_LOG_DIR and ARO_DATA_DIR to correct paths
- ARO_RUN_USER config key: leave empty for auto-detect, or set
  manually if auto-detection finds multiple users
- Auto-persists detected user into config file on first run
- Clear error messages when user is root, missing, or ambiguous

## [1.2.2] - 2026-04-09
### Fixed
- do_stop(): now waits up to 10s for graceful SIGTERM shutdown,
  then sends SIGKILL if process is still alive — prevents terminal
  from freezing when watchdog is mid-restart
- do_status(): now detects watchdog running as systemd user service
  even when no PID_FILE exists; shows "Running (systemd)" with PID
- Default STARTUP_TIMEOUT increased from 90s to 120s to allow ARO
  more time to reach connected state on slow networks

### Added
- get_aro_log_snippet(): extracts last N lines from ARO log with
  HTML entity escaping for safe Telegram delivery
- send_notify_crash(): now includes last 5 ARO log lines in
  Telegram message for immediate crash debugging without SSH
- send_notify_restart_failed(): same ARO log snippet added

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
- Chống thông báo lỗi mất kết nối (giới hạn 1 thông báo/giờ).

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
