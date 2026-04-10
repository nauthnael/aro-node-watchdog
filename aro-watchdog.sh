#!/bin/bash
# ─────────────────────────────────────────────────────────────
# ARO Node Watchdog Script v1.4.3
# ─────────────────────────────────────────────────────────────

# STEP 1: Define Constants
SCRIPT_VERSION="1.4.3"
SHOW_FOOTER_ON_EXIT=0

CURRENT_USER=$(whoami)
HOME_DIR="$HOME"
export DISPLAY=":20"
export XAUTHORITY="$HOME/.Xauthority"
export LIBGL_ALWAYS_SOFTWARE="1"
ARO_LOG_DIR="$HOME/.local/share/com.aro.ARONetwork/logs"
ARO_DATA_DIR="$HOME/.local/share/com.aro.ARONetwork"
HOSTNAME=$(hostname)
SCRIPT_DIR=$(dirname "$(realpath "$0")")
WATCHDOG_LOG="$SCRIPT_DIR/aro-watchdog.log"
CONFIG_FILE="$SCRIPT_DIR/aro-watchdog.conf"
PID_FILE="/tmp/aro_watchdog_${CURRENT_USER}.pid"
STATE_FILE="/tmp/aro_watchdog_state_${CURRENT_USER}"

# ─────────────────────────────────────────────────────────────
# ROOT CHECK
# ─────────────────────────────────────────────────────────────
_require_root() {
    [ "$CURRENT_USER" = "root" ] && return 0

    # Parse command — some commands are exempt from root requirement
    local _cmd=""
    for _arg in "$@"; do
        case "$_arg" in
            --token|--chatid) continue ;;
            -*) continue ;;
            *)
                [ -z "$_cmd" ] && _cmd="$_arg"
                ;;
        esac
    done

    # Commands that do not need root
    case "$_cmd" in
        log|version|readme|"")
            return 0
            ;;
    esac

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║              ⚠  ROOT REQUIRED  ⚠                ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  This script must run as root to:               ║"
    echo "║  • Read ARO log files owned by other users      ║"
    echo "║  • Launch ARO as the correct user               ║"
    echo "║  • Manage systemd services                      ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  Please re-run as root:                         ║"
    echo "║                                                 ║"
    echo "║    sudo -i                                      ║"
    echo "║    bash aro-watchdog.sh $*        ║"
    echo "║                                                 ║"
    echo "║  Or prefix with sudo:                           ║"
    echo "║    sudo bash aro-watchdog.sh $*   ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    exit 1
}

_require_root "$@"

show_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║           ARO Node Watchdog v1.4.3                    ║
║       Automated crash recovery for ARO DePIN nodes    ║
╠═══════════════════════════════════════════════════════╣
║  Bird Connect: https://x.com/tuangg                   ║
╚═══════════════════════════════════════════════════════╝
EOF
}

show_footer() {
    cat << "EOF"
─────────────────────────────────────────────────────────
 Thanks for using ARO Watchdog! Follow @tuangg on X/Twitter
 for updates, tips and new scripts: https://x.com/tuangg
─────────────────────────────────────────────────────────
EOF
}

# Trap for footer
trap '[ "$SHOW_FOOTER_ON_EXIT" = "1" ] && show_footer' EXIT

validate_telegram_credentials() {
    local token_invalid=0
    local chatid_invalid=0
    local token_reason=""
    local chatid_reason=""
    
    local placeholders=("TOKEN_CUA_BAN" "YOUR_TOKEN" "BOT_TOKEN" "YOUR_BOT_TOKEN" "ID_CUA_BAN" "YOUR_CHAT_ID" "CHATID" "YOUR_ID" "TOKEN" "CHAT_ID")
    
    if [ -n "$CLI_TOKEN" ]; then
        local t_upper=$(echo "$CLI_TOKEN" | tr '[:lower:]' '[:upper:]')
        for p in "${placeholders[@]}"; do
            if [ "$t_upper" = "$p" ]; then
                token_invalid=1
                token_reason="looks like a placeholder"
                break
            fi
        done
        if [ "$token_invalid" -eq 0 ] && [[ ! "$CLI_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            token_invalid=1
            token_reason="invalid format (expected format: 123456789:ABCdef...)"
        fi
    fi
    
    if [ -n "$CLI_CHATID" ]; then
        local c_upper=$(echo "$CLI_CHATID" | tr '[:lower:]' '[:upper:]')
        for p in "${placeholders[@]}"; do
            if [ "$c_upper" = "$p" ]; then
                chatid_invalid=1
                chatid_reason="looks like a placeholder"
                break
            fi
        done
        if [ "$chatid_invalid" -eq 0 ] && [[ ! "$CLI_CHATID" =~ ^-?[0-9]+$ ]]; then
            chatid_invalid=1
            chatid_reason="invalid format (expected: numeric ID like 123456789 or -100123456789)"
        fi
    fi
    
    if [ "$token_invalid" -eq 1 ] || [ "$chatid_invalid" -eq 1 ]; then
        if [ "$token_invalid" -eq 1 ]; then
            echo ""
            echo "  ⚠️  WARNING: Telegram Bot Token appears invalid"
            echo "      Value:  \"$CLI_TOKEN\""
            echo "      Reason: $token_reason"
        fi
        if [ "$chatid_invalid" -eq 1 ]; then
            echo ""
            echo "  ⚠️  WARNING: Telegram Chat ID appears invalid"
            echo "      Value:  \"$CLI_CHATID\""
            echo "      Reason: $chatid_reason"
        fi
        
        local choice="Y"
        if [ -t 0 ]; then
            echo ""
            echo "  ┌─────────────────────────────────────────────────┐"
            echo "  │  Do you want to skip Telegram setup for now?    │"
            echo "  │  You can configure it later by editing:         │"
            echo "  │  $CONFIG_FILE                                   │"
            echo "  │                                                 │"
            echo "  │  [Y] Skip — continue without valid credentials  │"
            echo "  │  [N] Exit — let me fix the token/chatid first   │"
            echo "  └─────────────────────────────────────────────────┘"
            printf "  Your choice [Y/n]: "
            read choice
            choice=${choice:-Y}
        else
            echo ""
            echo "  → Non-interactive mode detected. Automatically skipping invalid credentials."
        fi
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo "  → Skipped. Edit config later: nano $CONFIG_FILE"
            echo "  → Then run: ./aro-watchdog.sh test-notify  to verify"
            CLI_TOKEN=""
            CLI_CHATID=""
        else
            echo "  → Exiting. Get your token from @BotFather on Telegram."
            echo "  → Re-run: ./aro-watchdog.sh init --token YOUR_TOKEN --chatid YOUR_CHAT_ID"
            SHOW_FOOTER_ON_EXIT=0
            exit 1
        fi
    fi
}

create_default_config() {
    mkdir -p "$SCRIPT_DIR"

    if [ -f "$CONFIG_FILE" ]; then
        echo "Config already exists at $CONFIG_FILE"
        if [ -n "$CLI_TOKEN" ]; then
            sed -i "s|^TG_BOT_TOKEN=.*|TG_BOT_TOKEN=\"${CLI_TOKEN}\"|" "$CONFIG_FILE" 2>/dev/null
        fi
        if [ -n "$CLI_CHATID" ]; then
            sed -i "s|^TG_CHAT_ID=.*|TG_CHAT_ID=\"${CLI_CHATID}\"|" "$CONFIG_FILE" 2>/dev/null
        fi
        return 0
    fi

    cat > "$CONFIG_FILE" << 'EOF'
# ARO Node Watchdog — Configuration File
# Version: 1.4.3
# Edit this file then run: ./aro-watchdog.sh start

# === Telegram ===
TG_BOT_TOKEN=""
TG_CHAT_ID=""

# === Timing ===
CHECK_INTERVAL=30
LOG_STALE_MINUTES=10
DISCONNECT_ALERT_MINUTES=15
STARTUP_TIMEOUT=120
RESET_STABLE_HOURS=2

# === Restart Policy ===
MAX_RETRIES=5
# Backoff delay in seconds per retry (space-separated, one per retry slot)
BACKOFF_TIMES="0 0 30 60 120"

# === Daily Report ===
DAILY_REPORT_HOUR=7

# === ARO Binary ===
ARO_BINARY="/usr/bin/ARO"

# === ARO Run User ===
# The Linux user account that runs the ARO node.
# Leave empty to auto-detect (recommended).
# Do NOT set this to root — ARO must run as a normal user.
ARO_RUN_USER=""
EOF

    if [ -n "$CLI_TOKEN" ]; then
        sed -i "s|^TG_BOT_TOKEN=\"\"|TG_BOT_TOKEN=\"${CLI_TOKEN}\"|" "$CONFIG_FILE" 2>/dev/null
    fi
    if [ -n "$CLI_CHATID" ]; then
        sed -i "s|^TG_CHAT_ID=\"\"|TG_CHAT_ID=\"${CLI_CHATID}\"|" "$CONFIG_FILE" 2>/dev/null
    fi

    cat > "$SCRIPT_DIR/README.md" << 'EOF'
# 🚀 ARO Node Watchdog v1.4.3

Công cụ giám sát chuyên nghiệp và tự động khôi phục dành cho **ARO DePIN Node** trên Linux VPS.

## ⚡ Cài đặt nhanh (One-liner)

Sao chép và dán dòng lệnh bên dưới vào terminal của bạn (thay `TOKEN` và `ID` bằng thông tin của bạn):

```bash
curl -fsSL https://raw.githubusercontent.com/nauthnael/aro-node-watchdog/main/aro-watchdog.sh -o aro-watchdog.sh && chmod +x aro-watchdog.sh && sudo bash aro-watchdog.sh init --token "TOKEN_CUA_BAN" --chatid "ID_CUA_BAN" && sudo bash aro-watchdog.sh setup
```

> **Note:** Lệnh `setup` giờ đây tự động cấu hình tính năng auto-start luôn, nên Watchdog vẫn tự chạy sau khi khởi động khởi động lại VPS của bạn.

## 🛠 Tính năng
- **Fix lỗi treo (Hung detection):** Tự động phát hiện khi log không cập nhật sau 10 phút.
- **Fix lỗi chết (Process crash):** Tự khởi động lại ngay khi tiến trình biến mất.
- **Báo cáo Reward:** Tự động gửi lợi nhuận ngày hôm trước vào 7h sáng mỗi ngày.
- **Quản lý Service:** Hỗ trợ cài đặt như một service hệ thống (Systemd/SysVinit).

## 💻 Các lệnh quan trọng
- `./aro-watchdog.sh setup`: Cài đặt service + Chạy + Kiểm tra log (Nên dùng).
- `./aro-watchdog.sh status`: Kiểm tra tình trạng node.
- `./aro-watchdog.sh report`: Gửi báo cáo Reward ngay lập tức qua Telegram.
- `./aro-watchdog.sh log`: Theo dõi hoạt động của watchdog.

---
**GitHub:** [nauthnael/aro-node-watchdog](https://github.com/nauthnael/aro-node-watchdog)  
**Author:** [tuangg](https://x.com/tuangg)
EOF

    cat > "$SCRIPT_DIR/CHANGELOG.md" << 'EOF'
# Changelog

## [1.4.3] - 2026-04-10
### Fixed
- Duplicate watchdog instances: do_install() now only enables
  the service (not starts it); do_setup() explicitly stops
  any existing instance before starting fresh — eliminates
  2-3 concurrent watchdog processes that caused duplicate
  crash notifications and log spam
- Increased service start wait from 2s to 3s for reliability

### Added
- wait_then_notify_restart(): runs in background after ARO
  restart, polls log every 5s up to 120s waiting for
  "connect":"connected" status before sending Telegram
  notification — ensures reward/uptime data in notification
  reflects actual connected state rather than stale values

## [1.4.2] - 2026-04-10
### Added
- format_time_ago(): converts elapsed seconds to human-readable
  string (e.g. "1d 2h 30m ago", "45m 12s ago")
- get_last_online_info(): scans last 500 lines of ARO log to
  find the most recent "connect":"connected" timestamp and
  sets LAST_ONLINE_LABEL + LAST_ONLINE_AGO variables:
  • If currently connected: shows "🟢 Online since: Xh Ym ago"
    (from first connected line in recent log)
  • If disconnected: shows "🔴 Last online: Xd Yh ago"
    (from last connected line found)
  • If no history: shows "❓ No connection history"
- Last online info added to: send_daily_report(),
  send_notify_setup_success(), send_notify_restart_success()

## [1.4.1] - 2026-04-10
### Added
- send_notify_setup_success(): sends a Telegram notification
  at the end of do_setup() confirming watchdog is installed,
  including: VPS hostname, ARO user, watchdog mode (systemd
  or background), serial number, email, public IP, connection
  status, today/yesterday rewards, and uptime ratio
- Watchdog mode label distinguishes between "systemd system
  service (auto-start on reboot)" and "background process"
  so user knows immediately whether the service survives reboot

## [1.4.0] - 2026-04-10
### Changed
- Switched from systemd USER service to SYSTEM service
  (/etc/systemd/system/aro-watchdog.service) — fixes service
  immediately exiting when ExecStart path is not readable by
  EFFECTIVE_USER (e.g. script lives in /root/ but service ran
  as ubuntu)
- systemctl_user() now wraps plain "systemctl" (no --user)
  since the watchdog runs as root via system service
- Service unit now uses User=root with WantedBy=multi-user.target
  — ARO itself still launches as EFFECTIVE_USER via sudo -u,
  so ARO runs as the correct unprivileged user (safe)
- System services survive reboot without loginctl linger
- do_setup(): removed [0/3] linger step (not needed for
  system services)
- do_uninstall(): updated to remove system service file;
  also cleans up legacy user service files if present
- do_setup() already_installed check updated to use system
  service detection

## [1.3.6] - 2026-04-10
### Fixed
- All systemctl --user calls now run via systemctl_user()
  helper which executes as EFFECTIVE_USER with correct
  XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS — fixes
  "Failed to connect to bus: No medium found" when script
  runs as root managing another user's systemd service
- do_install(): service unit file now written to
  EFFECTIVE_HOME instead of HOME — fixes service being
  installed in /root/.config instead of the ARO user's
  home directory when running as root
- do_uninstall(): service file removal now uses
  EFFECTIVE_HOME for the same reason

### Added
- systemctl_user(): helper function that transparently
  wraps systemctl --user with correct user context and
  D-Bus environment variables

## [1.3.5] - 2026-04-09
### Added
- Hard root requirement: script now exits immediately with
  a clear error message if not run as root, listing exactly
  why root is needed and how to fix it
- Exempt commands (log, version, readme) still work without root
- README one-liner updated to use "sudo bash" explicitly

## [1.3.4] - 2026-04-09
### Fixed
- All ARO log file operations (ls, tail, stat) now use
  run_as_aro_user() helper — fixes verify_startup() always
  timing out when watchdog runs as a different user than the
  ARO node owner (e.g. root watching adam's ARO process),
  causing false "restart failed" even when ARO started OK
- Affected functions fixed: get_latest_aro_log(),
  check_aro_health(), verify_startup(), parse_node_info(),
  get_aro_log_snippet(), get_disconnect_duration()

### Added
- run_as_aro_user(): helper that transparently runs commands
  as EFFECTIVE_USER via sudo -n when direct file access is
  denied; falls back to direct execution if sudo unavailable
- do_setup(): now detects and uninstalls any existing watchdog
  installation before proceeding, preventing duplicate
  processes and stale service files on reinstall

## [1.3.3] - 2026-04-09
### Fixed
- restart_aro(): replaced "su" with "sudo -u" to launch ARO
  as EFFECTIVE_USER without requiring a TTY — fixes ARO never
  starting when watchdog runs as a different user (e.g. root)
  because "su" is immediately suspended (state T) in
  non-interactive/no-TTY contexts such as systemd services
- sudo -n used for non-interactive check before attempting
  launch; falls back to su if sudo is unavailable or requires
  a password (non-cloud environments)
- Confirmed working on Google Cloud

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
EOF

    echo "✔ Config created: $CONFIG_FILE"
    echo "✔ README.md created: $SCRIPT_DIR/README.md"
    echo "✔ CHANGELOG.md created: $SCRIPT_DIR/CHANGELOG.md"
    echo "→ Next steps:"
    echo "  1. Edit config if needed: nano $CONFIG_FILE"
    echo "  2. Run setup: ./aro-watchdog.sh setup"
}

# STEP 2: Parse CLI flags
CMD=""
CLI_TOKEN=""
CLI_CHATID=""

# Create a local copy of arguments to parse
args=("$@")
while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)
            CLI_TOKEN="$2"
            shift 2
            ;;
        --chatid)
            CLI_CHATID="$2"
            shift 2
            ;;
        -*)
            shift
            ;;
        *)
            if [ -z "$CMD" ]; then
                CMD="$1"
            fi
            shift
            ;;
    esac
done

# Show Banner once at start
if [[ -n "$CMD" && ! "$CMD" =~ ^(log|start-foreground)$ ]]; then
    show_banner
fi

# Validation for init
if [[ "$CMD" = "init" && ( -n "$CLI_TOKEN" || -n "$CLI_CHATID" ) ]]; then
    validate_telegram_credentials
fi

# STEP 3: Handle commands without config
if [[ "$CMD" =~ ^(init|version|readme)$ ]]; then
    if [ "$CMD" = "init" ]; then
        create_default_config
    elif [ "$CMD" = "version" ]; then
        echo "ARO Watchdog v${SCRIPT_VERSION}"
    elif [ "$CMD" = "readme" ]; then
        [ -f "$SCRIPT_DIR/README.md" ] && cat "$SCRIPT_DIR/README.md"
    fi
    SHOW_FOOTER_ON_EXIT=1
    exit 0
fi

# STEP 4: Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config not found. Run first: $0 init"
    exit 1
fi

# STEP 5: Source config
source "$CONFIG_FILE" 2>/dev/null

# STEP 6 & 7: Override with CLI flags & Auto-persist
if [ -n "$CLI_TOKEN" ]; then
    if [ -z "$TG_BOT_TOKEN" ]; then
        sed -i "s|^TG_BOT_TOKEN=\"\"|TG_BOT_TOKEN=\"$CLI_TOKEN\"|" "$CONFIG_FILE" 2>/dev/null
    fi
    TG_BOT_TOKEN="$CLI_TOKEN"
fi

if [ -n "$CLI_CHATID" ]; then
    if [ -z "$TG_CHAT_ID" ]; then
        sed -i "s|^TG_CHAT_ID=\"\"|TG_CHAT_ID=\"$CLI_CHATID\"|" "$CONFIG_FILE" 2>/dev/null
    fi
    TG_CHAT_ID="$CLI_CHATID"
fi

# STEP 8: Validate TG_BOT_TOKEN and TG_CHAT_ID (skipped for some commands)
if [[ ! "$CMD" =~ ^(stop|status|log|config|uninstall)$ ]]; then
    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        echo "FATAL: TG_BOT_TOKEN and TG_CHAT_ID must be set in $CONFIG_FILE"
        exit 1
    fi
fi

# Global Stats Variables
SERIAL="N/A"
EMAIL="N/A"
CONNECT_STATUS="N/A"
REWARD_TODAY="0"
REWARD_YESTERDAY="0"
UPTIME="0"
PUBLIC_IP="N/A"
LATEST_LOG_FILE=""

EFFECTIVE_USER="$CURRENT_USER"
EFFECTIVE_HOME="$HOME"
EFFECTIVE_USER_RESOLVED=0

# State Variables
retry_count=0
last_crash_epoch=0
last_restart_epoch=0
restart_count_24h=0
last_stable_epoch=$(date +%s)
last_disconnect_alert_epoch=0
last_daily_report_date=""

# ─────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────
log() {
    local level="${2:-INFO}"
    local msg="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_line="[$timestamp] [$level] $msg"
    
    if [ -t 1 ]; then
        if [ "$level" = "ERROR" ] || [ "$level" = "FATAL" ]; then
            echo "$log_line" >&2
        else
            echo "$log_line"
        fi
    fi
    
    if [ -f "$WATCHDOG_LOG" ]; then
        local size=$(wc -c < "$WATCHDOG_LOG" 2>/dev/null || stat -c%s "$WATCHDOG_LOG" 2>/dev/null || echo 0)
        if [ "$size" -gt 5242880 ]; then
            mv -f "${WATCHDOG_LOG}.2" "${WATCHDOG_LOG}.3" 2>/dev/null
            mv -f "${WATCHDOG_LOG}.1" "${WATCHDOG_LOG}.2" 2>/dev/null
            mv -f "${WATCHDOG_LOG}" "${WATCHDOG_LOG}.1" 2>/dev/null
        fi
    fi
    
    echo "$log_line" >> "$WATCHDOG_LOG"
}

# Detect which Linux user is running ARO node
detect_aro_user() {
    local found_users=()
    local aro_log_subpath=".local/share/com.aro.ARONetwork/logs"

    # Scan all users: check /home/* and /root
    local all_homes=()
    while IFS=: read -r uname _ uid _ _ uhome _; do
        # Only consider users with uid >= 1000 (normal users)
        if [ "$uid" -ge 1000 ] 2>/dev/null; then
            all_homes+=("$uname:$uhome")
        fi
    done < /etc/passwd

    for entry in "${all_homes[@]}"; do
        local uname="${entry%%:*}"
        local uhome="${entry#*:}"
        if [ -d "$uhome/$aro_log_subpath" ]; then
            found_users+=("$uname")
        fi
    done

    local count=${#found_users[@]}

    if [ "$count" -eq 1 ]; then
        # Exactly one user found — use it
        local detected="${found_users[0]}"
        log "Auto-detected ARO user: $detected (found ARO log directory)" "INFO"
        # Persist to config so future runs skip detection
        if [ -f "$CONFIG_FILE" ]; then
            sed -i "s|^ARO_RUN_USER=\"\"|ARO_RUN_USER=\"${detected}\"|" \
                "$CONFIG_FILE" 2>/dev/null
        fi
        echo "$detected"
        return 0

    elif [ "$count" -eq 0 ]; then
        # Fallback: try detecting via Chrome Remote Desktop process
        local crd_user
        crd_user=$(ps aux 2>/dev/null \
            | grep -i "chrome-remote-desktop\|Xvfb\|Xtightvnc" \
            | grep -v grep \
            | grep -v root \
            | awk '{print $1}' \
            | sort -u \
            | head -1)

        if [ -n "$crd_user" ] && [ "$crd_user" != "root" ]; then
            log "Detected ARO user via CRD process: $crd_user" "INFO"
            if [ -f "$CONFIG_FILE" ]; then
                sed -i "s|^ARO_RUN_USER=\"\"|ARO_RUN_USER=\"${crd_user}\"|" \
                    "$CONFIG_FILE" 2>/dev/null
            fi
            echo "$crd_user"
            return 0
        fi

        # Cannot detect
        echo ""
        return 1

    else
        # Multiple users found — cannot auto-select
        echo ""
        return 2
    fi
}

# Resolve EFFECTIVE_USER and EFFECTIVE_HOME, update ARO path variables
resolve_effective_user() {
    # Idempotency guard — only resolve once per process
    if [ "$EFFECTIVE_USER_RESOLVED" = "1" ]; then
        return 0
    fi

    # If ARO_RUN_USER not set in config, auto-detect
    if [ -z "$ARO_RUN_USER" ]; then
        local detected
        local detect_rc
        detected=$(detect_aro_user)
        detect_rc=$?

        if [ "$detect_rc" -eq 0 ] && [ -n "$detected" ]; then
            ARO_RUN_USER="$detected"
        elif [ "$detect_rc" -eq 2 ]; then
            echo "ERROR: Multiple users have ARO installed."
            echo "  Please set ARO_RUN_USER manually in: $CONFIG_FILE"
            echo "  Example: ARO_RUN_USER=\"adam\""
            exit 1
        else
            echo "ERROR: Cannot detect which user runs ARO."
            echo "  Please set ARO_RUN_USER manually in: $CONFIG_FILE"
            echo "  Example: ARO_RUN_USER=\"adam\""
            exit 1
        fi
    fi

    # Validate: must not be root
    if [ "$ARO_RUN_USER" = "root" ]; then
        echo "ERROR: ARO_RUN_USER is set to 'root'."
        echo "  ARO node should not run as root."
        echo "  Set the correct username in: $CONFIG_FILE"
        echo "  Example: ARO_RUN_USER=\"adam\""
        exit 1
    fi

    # Validate: user must exist
    if ! id "$ARO_RUN_USER" >/dev/null 2>&1; then
        echo "ERROR: ARO_RUN_USER=\"$ARO_RUN_USER\" does not exist on this system."
        echo "  Check the username in: $CONFIG_FILE"
        exit 1
    fi

    # Resolve home directory
    EFFECTIVE_USER="$ARO_RUN_USER"
    EFFECTIVE_HOME=$(eval echo "~$EFFECTIVE_USER")

    # Update path variables to use effective user's home
    ARO_LOG_DIR="$EFFECTIVE_HOME/.local/share/com.aro.ARONetwork/logs"
    ARO_DATA_DIR="$EFFECTIVE_HOME/.local/share/com.aro.ARONetwork"

    log "Running watchdog for user: $EFFECTIVE_USER (home: $EFFECTIVE_HOME)" "INFO"
    EFFECTIVE_USER_RESOLVED=1
}

# ─────────────────────────────────────────────────────────────
# STATE MANAGEMENT
# ─────────────────────────────────────────────────────────────
load_state() {
    retry_count=0
    last_crash_epoch=0
    last_restart_epoch=0
    restart_count_24h=0
    last_stable_epoch=$(date +%s)
    last_disconnect_alert_epoch=0
    
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE" 2>/dev/null
    fi
}

save_state() {
    (
        flock -x 200
        cat > "$STATE_FILE" <<EOF
retry_count=$retry_count
last_crash_epoch=$last_crash_epoch
last_restart_epoch=$last_restart_epoch
restart_count_24h=$restart_count_24h
last_stable_epoch=$last_stable_epoch
last_disconnect_alert_epoch=$last_disconnect_alert_epoch
EOF
    ) 200> "${STATE_FILE}.lock"
}

# ─────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────
format_number() {
    local raw="$1"
    if [ -z "$raw" ] || [ "$raw" = "N/A" ]; then
        echo "0"
        return
    fi
    echo "$raw" | awk '{
        split($1, a, ".")
        int_part = a[1]
        frac_part = (length(a)>1) ? "." a[2] : ""
        res = ""
        len = length(int_part)
        for (i = 1; i <= len; i++) {
            res = res substr(int_part, i, 1)
            if ((len - i) % 3 == 0 && i != len) res = res ","
        }
        print res frac_part
    }'
}

format_uptime() {
    local ratio="$1"
    if [ -z "$ratio" ] || [ "$ratio" = "N/A" ]; then
        echo "N/A"
        return
    fi
    echo "$ratio" | awk '{printf "%.1f", $1 * 100}'
}

# Format seconds elapsed into human-readable "X ago" string
format_time_ago() {
    local seconds="$1"
    if [ -z "$seconds" ] || [ "$seconds" -lt 0 ] 2>/dev/null; then
        echo "unknown"
        return
    fi

    local days=$(( seconds / 86400 ))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$(( seconds % 60 ))

    if [ "$days" -gt 0 ]; then
        if [ "$hours" -gt 0 ] && [ "$minutes" -gt 0 ]; then
            echo "${days}d ${hours}h ${minutes}m ago"
        elif [ "$hours" -gt 0 ]; then
            echo "${days}d ${hours}h ago"
        else
            echo "${days}d ago"
        fi
    elif [ "$hours" -gt 0 ]; then
        if [ "$minutes" -gt 0 ]; then
            echo "${hours}h ${minutes}m ago"
        else
            echo "${hours}h ago"
        fi
    elif [ "$minutes" -gt 0 ]; then
        echo "${minutes}m ${secs}s ago"
    else
        echo "${secs}s ago"
    fi
}

# Get last online timestamp info from ARO log.
# Sets two variables in caller scope:
#   LAST_ONLINE_LABEL  — emoji + label string
#   LAST_ONLINE_AGO    — human readable time string
get_last_online_info() {
    LAST_ONLINE_LABEL="❓ No connection history"
    LAST_ONLINE_AGO=""

    if ! run_as_aro_user test -f "$LATEST_LOG_FILE" \
            2>/dev/null; then
        return
    fi

    local now
    now=$(date +%s)

    # Get all lines containing connect status from log
    local log_content
    log_content=$(run_as_aro_user tail -n 500 \
                  "$LATEST_LOG_FILE" 2>/dev/null)

    # Find timestamp of last "connected" line
    local last_connected_line
    last_connected_line=$(echo "$log_content" \
        | grep '"connect":"connected"' \
        | tail -1)

    if [ -z "$last_connected_line" ]; then
        LAST_ONLINE_LABEL="❓ Never connected in recent log"
        LAST_ONLINE_AGO=""
        return
    fi

    # Extract timestamp: format [2026-04-09 16:45:17.186]
    local last_ts_str
    last_ts_str=$(echo "$last_connected_line" \
        | grep -oP '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' \
        | tr -d '[')

    local last_epoch=0
    if [ -n "$last_ts_str" ]; then
        last_epoch=$(date -d "$last_ts_str" +%s 2>/dev/null || echo 0)
    fi

    if [ "$last_epoch" -eq 0 ]; then
        LAST_ONLINE_LABEL="❓ Could not parse timestamp"
        LAST_ONLINE_AGO=""
        return
    fi

    local elapsed=$(( now - last_epoch ))
    local ago_str
    ago_str=$(format_time_ago "$elapsed")

    # Determine if currently connected or last seen
    if [ "$CONNECT_STATUS" = "connected" ]; then
        # Find FIRST connected line in the current continuous
        # connected session (scan backwards from end)
        local first_connected_line
        first_connected_line=$(echo "$log_content" \
            | grep '"connect":"connected"' \
            | head -1)

        local session_ts_str
        session_ts_str=$(echo "$first_connected_line" \
            | grep -oP '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' \
            | tr -d '[')

        local session_epoch=0
        if [ -n "$session_ts_str" ]; then
            session_epoch=$(date -d "$session_ts_str" \
                            +%s 2>/dev/null || echo 0)
        fi

        if [ "$session_epoch" -gt 0 ]; then
            local session_elapsed=$(( now - session_epoch ))
            local session_ago
            session_ago=$(format_time_ago "$session_elapsed")
            LAST_ONLINE_LABEL="🟢 Online since"
            LAST_ONLINE_AGO="$session_ago"
        else
            LAST_ONLINE_LABEL="🟢 Currently online"
            LAST_ONLINE_AGO="$ago_str"
        fi
    else
        LAST_ONLINE_LABEL="🔴 Last online"
        LAST_ONLINE_AGO="$ago_str"
    fi
}

send_telegram() {
    local msg="$1"
    curl -s -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d parse_mode="HTML" \
        -d text="$msg" >/dev/null 2>&1 || log "Telegram notification failed." "WARN"
}

# Get last N lines of ARO log as a plain string for notifications
get_aro_log_snippet() {
    local lines="${1:-5}"
    if [ -f "$LATEST_LOG_FILE" ]; then
        local snippet
        snippet=$(run_as_aro_user tail -n "$lines" \
                  "$LATEST_LOG_FILE" 2>/dev/null \
                  | grep -oP '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+\] \[(?:INFO|WARN|ERROR)\] .*' \
                  | sed 's/\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] \([0-9:]*\)\.[0-9]*\]/[\1]/g' \
                  | tail -n "$lines")
        if [ -z "$snippet" ]; then
            # Fallback: just return raw last lines if grep finds nothing
            snippet=$(run_as_aro_user tail -n "$lines" \
                      "$LATEST_LOG_FILE" 2>/dev/null)
        fi
        snippet=$(echo "$snippet" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        echo "$snippet"
    else
        echo "(ARO log not available)"
    fi
}

# ─────────────────────────────────────────────────────────────
# NOTIFICATION TEMPLATES
# ─────────────────────────────────────────────────────────────
send_notify_setup_success() {
    local watchdog_mode="$1"   # "systemd" or "background"

    # Resolve latest log and parse node info
    LATEST_LOG_FILE=$(get_latest_aro_log)
    parse_node_info
    get_last_online_info

    local f_today
    f_today=$(format_number "$REWARD_TODAY")
    local f_yest
    f_yest=$(format_number "$REWARD_YESTERDAY")
    local f_uptime
    f_uptime=$(format_uptime "$UPTIME")
    local datetime
    datetime=$(date "+%Y-%m-%d %H:%M:%S")

    # Determine watchdog status label
    local mode_label="background process"
    [ "$watchdog_mode" = "systemd" ] && \
        mode_label="systemd system service (auto-start on reboot)"

    local msg="🚀 <b>[ARO WATCHDOG INSTALLED] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 ARO User: ${EFFECTIVE_USER}
⏰ Time: ${datetime}
⚙️ Mode: ${mode_label}
──────────────────────
🔢 Serial: ${SERIAL}
📧 Account: ${EMAIL}
🌐 IP: ${PUBLIC_IP}
🔗 Status: ${CONNECT_STATUS}
${LAST_ONLINE_LABEL}: ${LAST_ONLINE_AGO}
──────────────────────
💰 Reward today:     ${f_today} pts
💰 Reward yesterday: ${f_yest} pts
📶 Uptime: ${f_uptime}%
──────────────────────
✅ Watchdog is active and monitoring your node."

    send_telegram "$msg"
}

send_notify_crash() {
    local reason="$1"
    local retry_num="$2"
    local max_retries="$3"
    local datetime
    datetime=$(date "+%Y-%m-%d %H:%M:%S")
    local snippet
    snippet=$(get_aro_log_snippet 5)

    local msg="🔴 <b>[ARO CRASH] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 ARO User: ${EFFECTIVE_USER}
⏰ Time: ${datetime}
📋 Reason: ${reason}
🔄 Retry: ${retry_num}/${max_retries}
──────────────────────
📄 Last ARO log:
<code>${snippet}</code>"
    
    send_telegram "$msg"
}

send_notify_restart_success() {
    local startup_seconds="$1"
    parse_node_info
    get_last_online_info
    
    local f_today=$(format_number "$REWARD_TODAY")
    local f_yest=$(format_number "$REWARD_YESTERDAY")
    local f_uptime=$(format_uptime "$UPTIME")
    
    local msg="✅ <b>[ARO RESTARTED] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 ARO User: ${EFFECTIVE_USER}
🔢 Serial: ${SERIAL}
📧 Account: ${EMAIL}
🌐 IP: ${PUBLIC_IP}
⏱️ Startup time: ${startup_seconds}s
💰 Reward today: ${f_today} pts
💰 Reward yesterday: ${f_yest} pts
📶 Uptime: ${f_uptime}%
${LAST_ONLINE_LABEL}: ${LAST_ONLINE_AGO}"

    send_telegram "$msg"
}

send_notify_restart_failed() {
    local snippet
    snippet=$(get_aro_log_snippet 5)

    local msg="❌ <b>[ARO FAILED] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 ARO User: ${EFFECTIVE_USER}
⚠️ Failed after ${MAX_RETRIES} attempts
🛑 Watchdog stopped retrying
👉 Manual intervention required!
──────────────────────
📄 Last ARO log:
<code>${snippet}</code>"

    send_telegram "$msg"
}

send_notify_disconnect_alert() {
    local minutes="$1"
    local msg="⚠️ <b>[ARO DISCONNECTED] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 ARO User: ${EFFECTIVE_USER}
🔌 Node disconnected for ${minutes} min
🔢 Serial: ${SERIAL}
💡 Process still running — may be network issue
👉 No restart triggered"

    send_telegram "$msg"
}

send_daily_report() {
    parse_node_info
    get_last_online_info
    
    local delta=$(awk "BEGIN {print $REWARD_TODAY - $REWARD_YESTERDAY}")
    local cmp=$(awk "BEGIN {if ($delta > 0) print 1; else if ($delta < 0) print -1; else print 0}")
    local trend="➡️ No change"
    
    if [ "$cmp" -eq 1 ]; then
        trend="📈 +$(format_number "$delta")"
    elif [ "$cmp" -eq -1 ]; then
        trend="📉 $(format_number "$delta")"
    fi
    
    local f_today=$(format_number "$REWARD_TODAY")
    local f_yest=$(format_number "$REWARD_YESTERDAY")
    local f_uptime=$(format_uptime "$UPTIME")
    
    local msg="📊 <b>[ARO DAILY REPORT] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
🔢 Serial: ${SERIAL}
📧 Account: ${EMAIL}
─────── Reward ───────
💰 Today:     ${f_today} pts
💰 Yesterday: ${f_yest} pts
${trend}
📶 Uptime: ${f_uptime}%
🔄 Restarts (24h): ${restart_count_24h}
🟢 Status: ${CONNECT_STATUS}
${LAST_ONLINE_LABEL}: ${LAST_ONLINE_AGO}"

    send_telegram "$msg"
}

# ─────────────────────────────────────────────────────────────
# CORE ARO LOGIC
# ─────────────────────────────────────────────────────────────

# Run a command as EFFECTIVE_USER if we lack direct permission
run_as_aro_user() {
    # $@ = command to run
    if [ "$EFFECTIVE_USER" = "$CURRENT_USER" ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1 && \
         sudo -n -u "$EFFECTIVE_USER" true 2>/dev/null; then
        sudo -u "$EFFECTIVE_USER" "$@"
    else
        # Last resort: try directly (may fail with permission error)
        "$@"
    fi
}

get_latest_aro_log() {
    if [ -d "$ARO_LOG_DIR" ] || \
       run_as_aro_user test -d "$ARO_LOG_DIR" 2>/dev/null; then
        run_as_aro_user ls -t "$ARO_LOG_DIR"/*.log 2>/dev/null \
            | head -1
    fi
}

check_aro_health() {
    local pid=$(pgrep -u "$EFFECTIVE_USER" -x ARO | head -1)
    if [ -z "$pid" ]; then
        echo "dead"
        return
    fi
    
    if [ -f "$LATEST_LOG_FILE" ]; then
        local mtime
        mtime=$(run_as_aro_user stat -c %Y "$LATEST_LOG_FILE" \
                2>/dev/null)
        if [ -n "$mtime" ]; then
            local now=$(date +%s)
            local staleness=$((now - mtime))
            local max_stale=$((LOG_STALE_MINUTES * 60))
            if [ "$staleness" -gt "$max_stale" ]; then
                echo "hung"
                return
            fi
        fi
    fi
    echo "ok"
}

get_disconnect_duration() {
    if [ ! -f "$LATEST_LOG_FILE" ]; then
        echo "0"
        return
    fi
    
    local last_status_line
    last_status_line=$(run_as_aro_user tail -n 100 "$LATEST_LOG_FILE" \
                       | grep -E '"connect":"(connected|disconnected)"' | tail -1)
    if echo "$last_status_line" | grep -q '"connect":"disconnected"'; then
        local timestamp_str=$(echo "$last_status_line" | awk -F'[][]' '{print $2}' | cut -d'.' -f1)
        if [ -n "$timestamp_str" ]; then
            local log_epoch=$(date -d "$timestamp_str" +%s 2>/dev/null)
            if [ -n "$log_epoch" ]; then
                local now=$(date +%s)
                local diff=$((now - log_epoch))
                echo $((diff / 60))
                return
            fi
        fi
    fi
    echo "0"
}

parse_node_info() {
    SERIAL="N/A"
    EMAIL="N/A"
    CONNECT_STATUS="N/A"
    REWARD_TODAY="0"
    REWARD_YESTERDAY="0"
    UPTIME="0"
    PUBLIC_IP="N/A"

    if [ ! -f "$LATEST_LOG_FILE" ]; then return; fi
    local lines
    lines=$(run_as_aro_user tail -n 200 "$LATEST_LOG_FILE" \
            2>/dev/null)
    if [ -z "$lines" ]; then return; fi
    
    local val
    val=$(echo "$lines" | grep -oP '(?<="serialNumber":")[^"]+' | tail -1)
    [ -n "$val" ] && SERIAL="$val"
    
    val=$(echo "$lines" | grep -oP '(?<="email":")[^"]+' | tail -1)
    [ -n "$val" ] && EMAIL="$val"
    
    val=$(echo "$lines" | grep -oP '(?<="connect":")(connected|disconnected)' | tail -1)
    [ -n "$val" ] && CONNECT_STATUS="$val"
    
    val=$(echo "$lines" | grep -oP '(?<="today":)[0-9.]+' | tail -1)
    [ -n "$val" ] && REWARD_TODAY="$val"
    
    val=$(echo "$lines" | grep -oP '(?<="yesterday":)[0-9.]+' | tail -1)
    [ -n "$val" ] && REWARD_YESTERDAY="$val"
    
    val=$(echo "$lines" | grep -oP '(?<="uptime":)[0-9.]+' | tail -1)
    [ -n "$val" ] && UPTIME="$val"
    
    val=$(echo "$lines" | grep -oP '(?<="publicIp":")[^"]+' | tail -1)
    [ -n "$val" ] && PUBLIC_IP="$val"
}

verify_startup() {
    local i=0
    while [ $((i * 3)) -lt "$STARTUP_TIMEOUT" ]; do
        # Re-detect newest log file on every iteration
        local candidate=$(get_latest_aro_log)
        [ -n "$candidate" ] && LATEST_LOG_FILE="$candidate"

        if [ -f "$LATEST_LOG_FILE" ]; then
            local lines
            lines=$(run_as_aro_user tail -n 50 "$LATEST_LOG_FILE" \
                    2>/dev/null)
            local has_info=$(echo "$lines" | grep -c "initial node info resolved")
            local has_conn=$(echo "$lines" | grep -c '"connect":"connected"')
            if [ "$has_info" -gt 0 ] && [ "$has_conn" -gt 0 ]; then
                echo "success"
                return
            fi
        fi
        sleep 3
        i=$((i + 1))
    done
    echo "failed"
}

restart_aro() {
    pkill -u "$EFFECTIVE_USER" -x ARO 2>/dev/null
    sleep 3
    pkill -9 -u "$EFFECTIVE_USER" -x ARO 2>/dev/null
    sleep 2
    
    if [ ! -f "$ARO_BINARY" ]; then
        log "ARO binary not found at $ARO_BINARY. Cannot restart." "FATAL"
        echo "failed"
        return
    fi
    
    if [ "$EFFECTIVE_USER" != "$CURRENT_USER" ]; then
        # Prefer sudo -u (no TTY required, works on cloud VPS
        # with NOPASSWD sudo: GCloud, AWS, Oracle, etc.)
        if command -v sudo >/dev/null 2>&1 && \
           sudo -n -u "$EFFECTIVE_USER" true 2>/dev/null; then
            sudo -u "$EFFECTIVE_USER" \
                DISPLAY=":20" \
                XAUTHORITY="$EFFECTIVE_HOME/.Xauthority" \
                LIBGL_ALWAYS_SOFTWARE="1" \
                "$ARO_BINARY" >/dev/null 2>&1 &
            log "ARO launched via sudo -u $EFFECTIVE_USER" "INFO"
        else
            # Fallback: su (requires TTY/password — may fail
            # in non-interactive mode)
            log "sudo not available or requires password, trying su..." "WARN"
            su -s /bin/bash "$EFFECTIVE_USER" -c \
                "DISPLAY=:20 XAUTHORITY=\"$EFFECTIVE_HOME/.Xauthority\" \
                 LIBGL_ALWAYS_SOFTWARE=1 \"$ARO_BINARY\"" \
                >/dev/null 2>&1 &
        fi
    else
        DISPLAY=":20" XAUTHORITY="$EFFECTIVE_HOME/.Xauthority" \
        LIBGL_ALWAYS_SOFTWARE="1" "$ARO_BINARY" >/dev/null 2>&1 &
    fi
    
    # Do NOT sleep here — verify_startup() will poll and detect new log
    verify_startup
}

# Wait for ARO to reach "connected" state then send notification.
# Runs in background so watchdog loop is not blocked.
wait_then_notify_restart() {
    local startup_seconds="$1"
    local wait_max=120    # max seconds to wait for connected
    local interval=5
    local waited=0

    # Poll until connected or timeout
    while [ "$waited" -lt "$wait_max" ]; do
        sleep "$interval"
        waited=$((waited + interval))

        # Re-read latest log
        local candidate
        candidate=$(get_latest_aro_log)
        [ -n "$candidate" ] && LATEST_LOG_FILE="$candidate"

        # Check connect status from log
        local current_status=""
        if run_as_aro_user test -f "$LATEST_LOG_FILE" \
                2>/dev/null; then
            current_status=$(run_as_aro_user tail -n 100 \
                "$LATEST_LOG_FILE" 2>/dev/null \
                | grep -oP '(?<="connect":")(connected|disconnected)' \
                | tail -1)
        fi

        if [ "$current_status" = "connected" ]; then
            log "Node connected after $((startup_seconds + waited))s total. Sending notification." "INFO"
            send_notify_restart_success "$((startup_seconds + waited))"
            return
        fi
    done

    # Timeout — send notification with whatever data is available
    log "Timed out waiting for connected status. Sending notification anyway." "WARN"
    send_notify_restart_success "$((startup_seconds + waited))"
}

# ─────────────────────────────────────────────────────────────
# MAIN WATCHDOG LOOP
# ─────────────────────────────────────────────────────────────
watchdog_loop() {
    load_state
    resolve_effective_user
    LATEST_LOG_FILE=$(get_latest_aro_log)
    last_daily_report_date=""

    trap 'log "Watchdog stopping..."; rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT

    while true; do
        local current_hour=$(date +%H)
        local current_date=$(date +%Y-%m-%d)
        current_hour=$((10#$current_hour))
        local daily_hour=$((10#$DAILY_REPORT_HOUR))
        
        if [ "$current_hour" -eq "$daily_hour" ] && [ "$current_date" != "$last_daily_report_date" ]; then
            send_daily_report
            last_daily_report_date="$current_date"
        fi

        local health=$(check_aro_health)
        
        if [ "$health" = "ok" ]; then
            local disc_minutes=$(get_disconnect_duration)
            if [ "$disc_minutes" -ge "$DISCONNECT_ALERT_MINUTES" ]; then
                local now=$(date +%s)
                if [ $((now - last_disconnect_alert_epoch)) -gt 3600 ]; then
                    send_notify_disconnect_alert "$disc_minutes"
                    last_disconnect_alert_epoch=$now
                    save_state
                fi
            fi
            
            local now=$(date +%s)
            local stable_dur=$((now - last_stable_epoch))
            local reset_thresh=$((RESET_STABLE_HOURS * 3600))
            if [ "$stable_dur" -gt "$reset_thresh" ]; then
                retry_count=0
                save_state
            fi
            if [ $((now - last_restart_epoch)) -gt 86400 ]; then
                restart_count_24h=0
                save_state
            fi
            last_stable_epoch=$now
            
            sleep "$CHECK_INTERVAL"
            continue
        fi

        local reason="Process died"
        [ "$health" = "hung" ] && reason="Log silent > ${LOG_STALE_MINUTES}min"
        
        log "ARO $health detected: $reason"
        
        if [ "$retry_count" -ge "$MAX_RETRIES" ]; then
            send_notify_restart_failed
            log "Max retries reached. Sleeping 12 minutes before resuming..." "WARN"
            sleep 720
            retry_count=0
            save_state
            log "Retry counter reset. Resuming health checks." "INFO"
            continue
        fi

        local backoff_arr=($BACKOFF_TIMES)
        local backoff=${backoff_arr[$retry_count]}
        if [ -z "$backoff" ]; then
            backoff=${backoff_arr[${#backoff_arr[@]}-1]}
        fi
        
        retry_count=$((retry_count + 1))
        restart_count_24h=$((restart_count_24h + 1))
        last_restart_epoch=$(date +%s)
        save_state

        send_notify_crash "$reason" "$retry_count" "$MAX_RETRIES"
        if [ "$backoff" -gt 0 ]; then
            log "Waiting ${backoff}s before restart attempt ${retry_count}..."
            sleep "$backoff"
        else
            log "Restarting immediately (attempt ${retry_count})..."
        fi

        local start_epoch=$(date +%s)
        local result=$(restart_aro)
        local elapsed=$(($(date +%s) - start_epoch))

        if [ "$result" = "success" ]; then
            log "ARO restarted successfully in ${elapsed}s"
            last_stable_epoch=$(date +%s)
            LATEST_LOG_FILE=$(get_latest_aro_log)
            # Send notification after node reaches connected state
            wait_then_notify_restart "$elapsed" &
        else
            log "ARO restart failed (attempt ${retry_count})" "WARN"
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# ─────────────────────────────────────────────────────────────
# CLI INTERFACE
# ─────────────────────────────────────────────────────────────
do_start() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Watchdog already running (PID: $pid)"
            SHOW_FOOTER_ON_EXIT=1
            exit 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    echo "Starting background watchdog..."
    watchdog_loop &
    local new_pid=$!
    echo $new_pid > "$PID_FILE"
    echo "Watchdog started (PID: $new_pid)"
}

do_stop() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping watchdog (PID: $pid)..."
            kill "$pid" 2>/dev/null
            # Wait up to 10 seconds for graceful shutdown
            local waited=0
            while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
                sleep 1
                waited=$((waited + 1))
            done
            # Force kill if still alive
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force killing watchdog (PID: $pid)..."
                kill -9 "$pid" 2>/dev/null
                sleep 1
            fi
            echo "Watchdog stopped (PID: $pid)."
        else
            echo "Watchdog process not found (stale PID: $pid)."
        fi
        rm -f "$PID_FILE"
    else
        echo "Watchdog is not running."
    fi
}

do_status() {
    resolve_effective_user
    
    local w_status="Stopped"
    local w_pid="N/A"

    # Check PID file first
    if [ -f "$PID_FILE" ]; then
        w_pid=$(cat "$PID_FILE")
        if kill -0 "$w_pid" 2>/dev/null; then
            w_status="Running (background)"
        else
            w_status="Stale PID"
            w_pid="N/A"
        fi
    fi

    # Also check systemd user service (may override above)
    if [ -d /run/systemd/system ]; then
        if systemctl_user is-active --quiet aro-watchdog 2>/dev/null; then
            local svc_pid
            svc_pid=$(systemctl_user show aro-watchdog \
                      --property=MainPID --value 2>/dev/null)
            if [ -n "$svc_pid" ] && [ "$svc_pid" != "0" ]; then
                w_status="Running (systemd system service)"
                w_pid="$svc_pid"
            else
                w_status="Running (systemd system service)"
            fi
        fi
    fi

    local a_pid
    a_pid=$(pgrep -u "$EFFECTIVE_USER" -x ARO | head -1)
    local a_status="Stopped"
    [ -n "$a_pid" ] && a_status="Running" || a_pid="N/A"

    LATEST_LOG_FILE=$(get_latest_aro_log)
    local log_path=${LATEST_LOG_FILE:-"None"}

    echo "=== Watchdog Status ==="
    echo "Watchdog : $w_status (PID: $w_pid)"
    echo "ARO Node : $a_status (PID: $a_pid)"
    echo "Latest Log: $log_path"
    echo ""
    echo "=== ARO Node Info ==="
    parse_node_info
    echo "Serial Number   : $SERIAL"
    echo "Email Acc       : $EMAIL"
    echo "Connect Status  : $CONNECT_STATUS"
    echo "Public IP       : $PUBLIC_IP"
    echo "Uptime Ratio    : $(format_uptime "$UPTIME")%"
    echo "Reward Today    : $(format_number "$REWARD_TODAY")"
    echo "Reward Yest.    : $(format_number "$REWARD_YESTERDAY")"
}

# Wrapper for systemctl (system-level, no --user needed)
# When running as root we use system services, not user services
systemctl_user() {
    systemctl "$@"
}

do_install() {
    local is_systemd=0
    local is_runit=0
    
    if [ -d /run/systemd/system ]; then
        is_systemd=1
    elif [ -x /sbin/runit ]; then
        is_runit=1
    fi
    
    if [ "$is_systemd" -eq 1 ]; then
        local svc_file="/etc/systemd/system/aro-watchdog.service"
        cat > "$svc_file" <<EOF
[Unit]
Description=ARO Node Watchdog
After=network.target

[Service]
Type=simple
User=root
ExecStart=${SCRIPT_DIR}/aro-watchdog.sh start-foreground
Restart=always
RestartSec=10
Environment="DISPLAY=:20"

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload || true
        systemctl enable aro-watchdog || true
        echo "Installed as systemd system service (not started yet)."
    
    elif [ "$is_runit" -eq 1 ]; then
        echo "Detected runit init system."
        echo "Run the following commands as root to install:"
        echo "  sudo mkdir -p /etc/sv/aro-watchdog"
        echo "  echo -e '#!/bin/sh\nexec su -c \"${SCRIPT_DIR}/aro-watchdog.sh start-foreground\" ${CURRENT_USER}' | sudo tee /etc/sv/aro-watchdog/run"
        echo "  sudo chmod +x /etc/sv/aro-watchdog/run"
        echo "  sudo ln -s /etc/sv/aro-watchdog /var/service/"
        echo "Warn: Requires sudo for runit install."
        
    else
        echo "Detected sysvinit init system."
        local init_file="/etc/init.d/aro-watchdog"
        
        local SCMD=""
        if command -v sudo >/dev/null 2>&1; then
            SCMD="sudo "
        elif [ "$CURRENT_USER" = "root" ]; then
            SCMD=""
        fi
        
        if [[ -n "$SCMD" || "$CURRENT_USER" == "root" ]]; then
            cat <<EOF | $SCMD tee "$init_file" >/dev/null
#!/bin/bash
### BEGIN INIT INFO
# Provides:          aro-watchdog
# Required-Start:    \$network \$local_fs \$remote_fs
# Required-Stop:     \$network \$local_fs \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ARO Node Watchdog
# Description:       Automated crash recovery for ARO DePIN nodes
### END INIT INFO

DAEMON="${SCRIPT_DIR}/aro-watchdog.sh"
DAEMON_ARGS="start-foreground"
USER="${CURRENT_USER}"
PIDFILE="/tmp/aro_watchdog_\${USER}.pid"

case "\$1" in
  start)
    echo "Starting ARO Watchdog..."
    start-stop-daemon --start --background --make-pidfile --pidfile "\$PIDFILE" \\
                      --chuid "\$USER" --exec /bin/bash -- -c "\$DAEMON \$DAEMON_ARGS"
    ;;
  stop)
    echo "Stopping ARO Watchdog..."
    start-stop-daemon --stop --pidfile "\$PIDFILE" --retry 10
    rm -f "\$PIDFILE"
    ;;
  restart)
    \$0 stop
    sleep 2
    \$0 start
    ;;
  status)
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        echo "ARO Watchdog is running."
        exit 0
    else
        echo "ARO Watchdog is stopped."
        exit 1
    fi
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
EOF
            $SCMD chmod +x "$init_file"
            $SCMD update-rc.d aro-watchdog defaults
            echo "sysvinit service installed successfully (used sudo)."
        else
            echo "Failed: sysvinit install requires sudo or root privileges."
            echo "To install manually, create $init_file with LSB headers and start-stop-daemon, then run: update-rc.d aro-watchdog defaults."
        fi
    fi
}

do_uninstall() {
    # System service uninstall
    if systemctl list-unit-files 2>/dev/null \
            | grep -q 'aro-watchdog.service'; then
        systemctl disable --now aro-watchdog 2>/dev/null || true
        rm -f "/etc/systemd/system/aro-watchdog.service"
        systemctl daemon-reload || true
        echo "systemd system service uninstalled."
    fi

    # Legacy: also clean up old user service files if present
    if [ -f "$EFFECTIVE_HOME/.config/systemd/user/aro-watchdog.service" ]; then
        rm -f "$EFFECTIVE_HOME/.config/systemd/user/aro-watchdog.service"
        sudo -u "$EFFECTIVE_USER" \
            XDG_RUNTIME_DIR="/run/user/$(id -u "$EFFECTIVE_USER")" \
            systemctl --user daemon-reload 2>/dev/null || true
        echo "Legacy user service files cleaned up."
    fi

    do_stop
    echo "Done."
}

enable_linger() {
    # Skip if not a systemd system
    if [ ! -d /run/systemd/system ]; then
        return 0
    fi

    local target_user="$EFFECTIVE_USER"

    # Check if linger is already enabled
    if loginctl show-user "$target_user" 2>/dev/null \
            | grep -q "Linger=yes"; then
        echo "✔ Linger already enabled for user: $target_user"
        return 0
    fi

    echo "  Enabling systemd linger for user: $target_user..."

    # Try to enable linger directly (works if current user is
    # root OR if target_user == current user)
    if loginctl enable-linger "$target_user" 2>/dev/null; then
        echo "✔ Linger enabled — watchdog service will survive SSH disconnect."
        return 0
    fi

    # Try with sudo if available
    if command -v sudo >/dev/null 2>&1; then
        if sudo loginctl enable-linger "$target_user" 2>/dev/null; then
            echo "✔ Linger enabled (via sudo)."
            return 0
        fi
    fi

    # Could not enable — print manual hint
    echo "⚠ Could not enable linger automatically."
    echo "  Run this manually to keep watchdog alive after SSH disconnect:"
    echo "    loginctl enable-linger $target_user"
}

do_setup() {
    resolve_effective_user
    local _setup_watchdog_mode="background"

    # Uninstall any existing watchdog installation first
    local already_installed=0
    if [ -d /run/systemd/system ]; then
        if systemctl list-unit-files 2>/dev/null \
                | grep -q 'aro-watchdog.service'; then
            already_installed=1
        fi
    fi
    if [ -f "$PID_FILE" ]; then
        local existing_pid
        existing_pid=$(cat "$PID_FILE")
        if kill -0 "$existing_pid" 2>/dev/null; then
            already_installed=1
        fi
    fi

    if [ "$already_installed" -eq 1 ]; then
        echo "⚠ Existing watchdog installation detected."
        echo "  Uninstalling previous version first..."
        do_uninstall >/dev/null 2>&1 || true
        do_stop >/dev/null 2>&1 || true
        sleep 2
        echo "✔ Previous installation removed."
        echo ""
    fi

    # Reset stale watchdog state from any previous run
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE" "${STATE_FILE}.lock"
        echo "✔ Previous watchdog state cleared."
    fi

    if [ -f "$PID_FILE" ]; then
        local stale_pid
        stale_pid=$(cat "$PID_FILE")
        if ! kill -0 "$stale_pid" 2>/dev/null; then
            rm -f "$PID_FILE"
        fi
    fi

    echo "=== ARO Watchdog Setup ==="
    echo ""

    # Step 1: Install as service
    echo "[1/3] Installing watchdog as system service..."
    do_install
    echo ""

    # Step 2: Ensure service is actually running
    echo "[2/3] Starting watchdog service..."

    # For systemd: use systemctl_user
    if [ -d /run/systemd/system ]; then
        # Stop first to ensure no existing instance is running
        systemctl_user stop aro-watchdog 2>/dev/null || true
        sleep 1
        systemctl_user start aro-watchdog 2>/dev/null || true
        sleep 3
        if systemctl_user is-active --quiet aro-watchdog 2>/dev/null; then
            echo "✔ Watchdog service is running (systemd)."
            _setup_watchdog_mode="systemd"
        else
            # Fallback: start as background process if service failed
            echo "⚠ systemd service did not start. Falling back to background mode."
            if [ -f "$PID_FILE" ]; then
                local old_pid
                old_pid=$(cat "$PID_FILE")
                kill -0 "$old_pid" 2>/dev/null && kill "$old_pid" 2>/dev/null
                rm -f "$PID_FILE"
            fi
            watchdog_loop &
            local new_pid=$!
            echo "$new_pid" > "$PID_FILE"
            echo "✔ Watchdog started in background (PID: $new_pid)."
            _setup_watchdog_mode="background"
        fi
    else
        # sysvinit / runit: fallback to background
        if [ -f "$PID_FILE" ]; then
            local old_pid
            old_pid=$(cat "$PID_FILE")
            kill -0 "$old_pid" 2>/dev/null && kill "$old_pid" 2>/dev/null
            rm -f "$PID_FILE"
        fi
        watchdog_loop &
        local new_pid=$!
        echo "$new_pid" > "$PID_FILE"
        echo "✔ Watchdog started in background (PID: $new_pid)."
        _setup_watchdog_mode="background"
    fi
    echo ""

    # Step 3: Show last 15 lines of watchdog log to confirm activity
    echo "[3/3] Recent watchdog activity:"
    echo "  (waiting 4s for watchdog to initialize...)"
    sleep 4
    echo "──────────────────────────────────────────────"
    if [ -f "$WATCHDOG_LOG" ]; then
        tail -n 15 "$WATCHDOG_LOG"
    else
        echo "(No log yet — watchdog just started)"
    fi
    echo "──────────────────────────────────────────────"
    echo ""
    echo "✔ Setup complete! Use './aro-watchdog.sh status' to check node info."
    echo "  Live log: ./aro-watchdog.sh log"

    # Send Telegram notification with setup result and node info
    echo "  Sending setup notification to Telegram..."
    send_notify_setup_success "$_setup_watchdog_mode"
    echo "✔ Telegram notification sent."
}

# Main routing logic
case "$CMD" in
    setup)
        do_setup
        SHOW_FOOTER_ON_EXIT=1
        ;;
    start)
        do_start
        SHOW_FOOTER_ON_EXIT=1
        ;;
    stop)
        do_stop
        SHOW_FOOTER_ON_EXIT=1
        ;;
    restart)
        do_stop
        sleep 2
        do_start
        SHOW_FOOTER_ON_EXIT=1
        ;;
    status)
        do_status
        SHOW_FOOTER_ON_EXIT=1
        ;;
    install)
        do_install
        SHOW_FOOTER_ON_EXIT=1
        ;;
    uninstall)
        do_uninstall
        SHOW_FOOTER_ON_EXIT=1
        ;;
    log)
        tail -f "$WATCHDOG_LOG"
        ;;
    test-notify)
        resolve_effective_user
        LATEST_LOG_FILE=$(get_latest_aro_log)
        parse_node_info
        send_notify_restart_success 0
        echo "Sent."
        SHOW_FOOTER_ON_EXIT=1
        ;;
    report)
        resolve_effective_user
        LATEST_LOG_FILE=$(get_latest_aro_log)
        send_daily_report
        echo "Sent."
        SHOW_FOOTER_ON_EXIT=1
        ;;
    config)
        ${EDITOR:-nano} "$CONFIG_FILE"
        SHOW_FOOTER_ON_EXIT=1
        ;;
    start-foreground)
        watchdog_loop
        ;;
    *)
        echo "Usage: $0 {init|setup|start|stop|restart|status|install|uninstall|log|test-notify|report|config|start-foreground|readme|version} [--token TOKEN] [--chatid ID]"
        exit 1
        ;;
esac
