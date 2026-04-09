#!/bin/bash
# ─────────────────────────────────────────────────────────────
# ARO Node Watchdog Script v1.2.1
# ─────────────────────────────────────────────────────────────

# STEP 1: Define Constants
SCRIPT_VERSION="1.2.1"
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

show_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║           ARO Node Watchdog v1.2.1                    ║
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
# Version: 1.2.1
# Edit this file then run: ./aro-watchdog.sh start

# === Telegram ===
TG_BOT_TOKEN=""
TG_CHAT_ID=""

# === Timing ===
CHECK_INTERVAL=30
LOG_STALE_MINUTES=10
DISCONNECT_ALERT_MINUTES=15
STARTUP_TIMEOUT=90
RESET_STABLE_HOURS=2

# === Restart Policy ===
MAX_RETRIES=5
# Backoff delay in seconds per retry (space-separated, one per retry slot)
BACKOFF_TIMES="0 0 30 60 120"

# === Daily Report ===
DAILY_REPORT_HOUR=7

# === ARO Binary ===
ARO_BINARY="/usr/bin/ARO"
EOF

    if [ -n "$CLI_TOKEN" ]; then
        sed -i "s|^TG_BOT_TOKEN=\"\"|TG_BOT_TOKEN=\"${CLI_TOKEN}\"|" "$CONFIG_FILE" 2>/dev/null
    fi
    if [ -n "$CLI_CHATID" ]; then
        sed -i "s|^TG_CHAT_ID=\"\"|TG_CHAT_ID=\"${CLI_CHATID}\"|" "$CONFIG_FILE" 2>/dev/null
    fi

    cat > "$SCRIPT_DIR/README.md" << 'EOF'
# 🚀 ARO Node Watchdog v1.2.1

Công cụ giám sát chuyên nghiệp và tự động khôi phục dành cho **ARO DePIN Node** trên Linux VPS.

## ⚡ Cài đặt nhanh (One-liner)

Sao chép và dán dòng lệnh bên dưới vào terminal của bạn (thay `TOKEN` và `ID` bằng thông tin của bạn):

```bash
curl -fsSL https://raw.githubusercontent.com/nauthnael/aro-node-watchdog/main/aro-watchdog.sh -o aro-watchdog.sh && chmod +x aro-watchdog.sh && ./aro-watchdog.sh init --token "TOKEN_CUA_BAN" --chatid "ID_CUA_BAN" && ./aro-watchdog.sh setup
```

> **Note:** Nếu bạn dùng Ubuntu/Debian có systemd, hãy chạy lệnh này một lần để service watchdog tiếp tục chạy sau khi thoát SSH:
> `loginctl enable-linger $(whoami)`

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

send_telegram() {
    local msg="$1"
    curl -s -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d parse_mode="HTML" \
        -d text="$msg" >/dev/null 2>&1 || log "Telegram notification failed." "WARN"
}

# ─────────────────────────────────────────────────────────────
# NOTIFICATION TEMPLATES
# ─────────────────────────────────────────────────────────────
send_notify_crash() {
    local reason="$1"
    local retry_num="$2"
    local max_retries="$3"
    local datetime=$(date "+%Y-%m-%d %H:%M:%S")
    
    local msg="🔴 <b>[ARO CRASH] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 User: ${CURRENT_USER}
⏰ Time: ${datetime}
📋 Reason: ${reason}
🔄 Retry: ${retry_num}/${max_retries}"
    
    send_telegram "$msg"
}

send_notify_restart_success() {
    local startup_seconds="$1"
    parse_node_info
    
    local f_today=$(format_number "$REWARD_TODAY")
    local f_yest=$(format_number "$REWARD_YESTERDAY")
    local f_uptime=$(format_uptime "$UPTIME")
    
    local msg="✅ <b>[ARO RESTARTED] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 User: ${CURRENT_USER}
🔢 Serial: ${SERIAL}
📧 Account: ${EMAIL}
🌐 IP: ${PUBLIC_IP}
⏱️ Startup time: ${startup_seconds}s
💰 Reward today: ${f_today} pts
💰 Reward yesterday: ${f_yest} pts
📶 Uptime: ${f_uptime}%"

    send_telegram "$msg"
}

send_notify_restart_failed() {
    local msg="❌ <b>[ARO FAILED] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 User: ${CURRENT_USER}
⚠️ Failed after ${MAX_RETRIES} attempts
🛑 Watchdog stopped retrying
👉 Manual intervention required!"

    send_telegram "$msg"
}

send_notify_disconnect_alert() {
    local minutes="$1"
    local msg="⚠️ <b>[ARO DISCONNECTED] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
🔌 Node disconnected for ${minutes} min
🔢 Serial: ${SERIAL}
💡 Process still running — may be network issue
👉 No restart triggered"

    send_telegram "$msg"
}

send_daily_report() {
    parse_node_info
    
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
🟢 Status: ${CONNECT_STATUS}"

    send_telegram "$msg"
}

# ─────────────────────────────────────────────────────────────
# CORE ARO LOGIC
# ─────────────────────────────────────────────────────────────
get_latest_aro_log() {
    if [ -d "$ARO_LOG_DIR" ]; then
        local latest=$(ls -t "$ARO_LOG_DIR"/*.log 2>/dev/null | head -1)
        echo "$latest"
    fi
}

check_aro_health() {
    local pid=$(pgrep -u "$CURRENT_USER" -x ARO | head -1)
    if [ -z "$pid" ]; then
        echo "dead"
        return
    fi
    
    if [ -f "$LATEST_LOG_FILE" ]; then
        local mtime=$(stat -c %Y "$LATEST_LOG_FILE" 2>/dev/null)
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
    
    local last_status_line=$(tail -n 100 "$LATEST_LOG_FILE" | grep -E '"connect":"(connected|disconnected)"' | tail -1)
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
    local lines=$(tail -n 200 "$LATEST_LOG_FILE" 2>/dev/null)
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
            local lines=$(tail -n 50 "$LATEST_LOG_FILE" 2>/dev/null)
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
    pkill -u "$CURRENT_USER" -x ARO 2>/dev/null
    sleep 3
    pkill -9 -u "$CURRENT_USER" -x ARO 2>/dev/null
    sleep 2
    
    if [ ! -f "$ARO_BINARY" ]; then
        log "ARO binary not found at $ARO_BINARY. Cannot restart." "FATAL"
        echo "failed"
        return
    fi
    
    DISPLAY=":20" XAUTHORITY="$HOME/.Xauthority" \
    LIBGL_ALWAYS_SOFTWARE="1" "$ARO_BINARY" >/dev/null 2>&1 &
    
    # Do NOT sleep here — verify_startup() will poll and detect new log
    verify_startup
}

# ─────────────────────────────────────────────────────────────
# MAIN WATCHDOG LOOP
# ─────────────────────────────────────────────────────────────
watchdog_loop() {
    load_state
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
            log "Max retries reached. Watchdog sleeping 1 hour before checking again." "WARN"
            sleep 3600
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
            send_notify_restart_success "$elapsed"
            last_stable_epoch=$(date +%s)
            LATEST_LOG_FILE=$(get_latest_aro_log)
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
        local pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
        echo "Watchdog stopped (PID: $pid)."
    else
        echo "Watchdog is not running."
    fi
}

do_status() {
    local w_status="Stopped"
    local w_pid="N/A"
    if [ -f "$PID_FILE" ]; then
        w_pid=$(cat "$PID_FILE")
        if kill -0 "$w_pid" 2>/dev/null; then
            w_status="Running"
        else
            w_status="Stale PID"
        fi
    fi
    
    local a_pid=$(pgrep -u "$CURRENT_USER" -x ARO | head -1)
    local a_status="Stopped"
    [ -n "$a_pid" ] && a_status="Running" || a_pid="N/A"
    
    LATEST_LOG_FILE=$(get_latest_aro_log)
    local log_path=${LATEST_LOG_FILE:-"None"}
    
    echo "=== Watchdog Status ==="
    echo "Watchdog: $w_status (PID: $w_pid)"
    echo "ARO Node: $a_status (PID: $a_pid)"
    echo "Latest Log: $log_path"
    echo ""
    echo "=== ARO Node Info ==="
    parse_node_info
    echo "Serial Number   : $SERIAL"
    echo "Email Acc      : $EMAIL"
    echo "Connect Status : $CONNECT_STATUS"
    echo "Public IP      : $PUBLIC_IP"
    echo "Uptime Ratio   : $(format_uptime "$UPTIME")%"
    echo "Reward Today   : $(format_number "$REWARD_TODAY")"
    echo "Reward Yest.   : $(format_number "$REWARD_YESTERDAY")"
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
        local unit_dir="$HOME/.config/systemd/user"
        mkdir -p "$unit_dir"
        local svc_file="$unit_dir/aro-watchdog.service"
        cat > "$svc_file" <<EOF
[Unit]
Description=ARO Node Watchdog
After=network.target graphical.target

[Service]
Type=simple
ExecStart=${SCRIPT_DIR}/aro-watchdog.sh start-foreground
Restart=always
RestartSec=10
Environment="DISPLAY=:20"

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload || true
        systemctl --user enable --now aro-watchdog || true
        echo "Installed as systemd user service."
    
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
    if systemctl --user list-unit-files | grep -q 'aro-watchdog.service'; then
        systemctl --user disable --now aro-watchdog || true
        rm -f "$HOME/.config/systemd/user/aro-watchdog.service"
        systemctl --user daemon-reload || true
        echo "systemd service uninstalled."
    else
        echo "Uninstall for runit/sysvinit must be done manually."
    fi
    do_stop
    echo "Done."
}

do_setup() {
    echo "=== ARO Watchdog Setup ==="
    echo ""

    # Step 1: Install as service
    echo "[1/3] Installing watchdog as system service..."
    do_install
    echo ""

    # Step 2: Ensure service is actually running
    echo "[2/3] Starting watchdog service..."

    # For systemd: use systemctl --user
    if [ -d /run/systemd/system ]; then
        systemctl --user start aro-watchdog 2>/dev/null || true
        sleep 2
        if systemctl --user is-active --quiet aro-watchdog 2>/dev/null; then
            echo "✔ Watchdog service is running (systemd)."
        else
            # Fallback: start as background process if service failed
            echo "⚠ systemd service did not start. Falling back to background mode."
            echo "  Hint: Run 'loginctl enable-linger $CURRENT_USER' to allow user services."
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
            echo "  Note: Will stop if SSH session ends. Run the hint above to fix."
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
    fi
    echo ""

    # Step 3: Show last 15 lines of watchdog log to confirm activity
    echo "[3/3] Recent watchdog activity:"
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
        LATEST_LOG_FILE=$(get_latest_aro_log)
        parse_node_info
        send_notify_restart_success 0
        echo "Sent."
        SHOW_FOOTER_ON_EXIT=1
        ;;
    report)
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
