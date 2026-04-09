#!/bin/bash
# ARO Node Watchdog Script

# Environment AUTO-DETECTION
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

# Load Config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found at $CONFIG_FILE"
    exit 1
fi
source "$CONFIG_FILE"

# Config Validation
if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
    echo "FATAL: TG_BOT_TOKEN and TG_CHAT_ID must be set in $CONFIG_FILE"
    exit 1
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
last_daily_report_date=""

# ─────────────────────────────────────────────────────────────
# LOGGING (watchdog's own log)
# ─────────────────────────────────────────────────────────────
log() {
    local level="${2:-INFO}"
    local msg="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_line="[$timestamp] [$level] $msg"
    
    # Print to stdout/stderr if run in foreground
    if [ -t 1 ]; then
        if [ "$level" = "ERROR" ] || [ "$level" = "FATAL" ]; then
            echo "$log_line" >&2
        else
            echo "$log_line"
        fi
    fi
    
    # Log rotation (if > 5MB)
    if [ -f "$WATCHDOG_LOG" ]; then
        local size=$(wc -c < "$WATCHDOG_LOG" 2>/dev/null || echo 0)
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
    
    if [ -f "$STATE_FILE" ]; then
        (
            flock -x 200
            source "$STATE_FILE"
        ) 200<"$STATE_FILE" 2>/dev/null
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
EOF
    ) 200> "${STATE_FILE}.lock"
}

# ─────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────

# Format number with commas
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

# Format uptime ratio as percentage
format_uptime() {
    local ratio="$1"
    if [ -z "$ratio" ] || [ "$ratio" = "N/A" ]; then
        echo "N/A"
        return
    fi
    echo "$ratio" | awk '{printf "%.1f", $1 * 100}'
}

# Send Telegram Message
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
    
    local delta=$(echo "$REWARD_TODAY - $REWARD_YESTERDAY" | awk '{print $1}')
    local trend="➡️ No change"
    local cmp=$(echo "$delta" | awk '{if ($1 > 0) print 1; else if ($1 < 0) print -1; else print 0}')
    
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

    if [ ! -f "$LATEST_LOG_FILE" ]; then
        return
    fi

    local lines=$(tail -n 200 "$LATEST_LOG_FILE" 2>/dev/null)
    if [ -z "$lines" ]; then return; fi
    
    local val
    val=$(echo "$lines" | grep -oP '"serialNumber":"\?\K[^"]+' | tail -1)
    [ -n "$val" ] && SERIAL="$val"
    
    val=$(echo "$lines" | grep -oP '"email":"\?\K[^"]+' | tail -1)
    [ -n "$val" ] && EMAIL="$val"
    
    val=$(echo "$lines" | grep -oP '"connect":"\?\K(connected|disconnected)' | tail -1)
    [ -n "$val" ] && CONNECT_STATUS="$val"
    
    val=$(echo "$lines" | grep -oP '"today":\s*\K[0-9.]+' | tail -1)
    [ -n "$val" ] && REWARD_TODAY="$val"
    
    val=$(echo "$lines" | grep -oP '"yesterday":\s*\K[0-9.]+' | tail -1)
    [ -n "$val" ] && REWARD_YESTERDAY="$val"
    
    val=$(echo "$lines" | grep -oP '"uptime":\s*\K[0-9.]+' | tail -1)
    [ -n "$val" ] && UPTIME="$val"
    
    val=$(echo "$lines" | grep -oP '"publicIp":"\?\K[^"]+' | tail -1)
    [ -n "$val" ] && PUBLIC_IP="$val"
}

verify_startup() {
    local i=0
    while [ $((i * 3)) -lt "$STARTUP_TIMEOUT" ]; do
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
    
    "$ARO_BINARY" >/dev/null 2>&1 &
    
    sleep 5
    LATEST_LOG_FILE=$(get_latest_aro_log)
    
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
        # 1. Daily Report Check
        local current_hour=$(date +%H)
        local current_date=$(date +%Y-%m-%d)
        # Parse current_hour to avoid octal issues
        current_hour=$((10#$current_hour))
        local daily_hour=$((10#$DAILY_REPORT_HOUR))
        
        if [ "$current_hour" -eq "$daily_hour" ] && [ "$current_date" != "$last_daily_report_date" ]; then
            send_daily_report
            last_daily_report_date="$current_date"
        fi

        # 2. Health Check
        local health=$(check_aro_health)
        
        if [ "$health" = "ok" ]; then
            local disc_minutes=$(get_disconnect_duration)
            if [ "$disc_minutes" -ge "$DISCONNECT_ALERT_MINUTES" ]; then
                send_notify_disconnect_alert "$disc_minutes"
            fi
            
            local now=$(date +%s)
            local stable_dur=$((now - last_stable_epoch))
            local reset_thresh=$((RESET_STABLE_HOURS * 3600))
            if [ "$stable_dur" -gt "$reset_thresh" ]; then
                retry_count=0
                save_state
            fi
            last_stable_epoch=$now
            
            sleep "$CHECK_INTERVAL"
            continue
        fi

        # 3. Handle Crash/Hung
        local reason="Process died"
        [ "$health" = "hung" ] && reason="Log silent > ${LOG_STALE_MINUTES}min"
        
        log "ARO $health detected: $reason"
        
        if [ "$retry_count" -ge "$MAX_RETRIES" ]; then
            send_notify_restart_failed
            log "Max retries reached. Watchdog sleeping 1 hour before checking again." "WARN"
            sleep 3600
            continue
        fi

        # 4. Get Backoff Delay
        local backoff_arr=($BACKOFF_TIMES)
        local backoff=${backoff_arr[$retry_count]}
        if [ -z "$backoff" ]; then
            backoff=${backoff_arr[${#backoff_arr[@]}-1]} # last element
        fi
        
        retry_count=$((retry_count + 1))
        restart_count_24h=$((restart_count_24h + 1))
        save_state

        send_notify_crash "$reason" "$retry_count" "$MAX_RETRIES"
        log "Waiting ${backoff}s before restart attempt ${retry_count}..."
        sleep "$backoff"

        # 5. Restart Action
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
        echo "Detected sysvinit init system (e.g. Devuan sysvinit)."
        echo "Run the following commands as root to install:"
        echo "  # Create /etc/init.d/aro-watchdog with LSB headers"
        echo "  # Start/stop should call: su -c \"${SCRIPT_DIR}/aro-watchdog.sh ...\" ${CURRENT_USER}"
        echo "  # Run: sudo update-rc.d aro-watchdog defaults"
        echo "Warn: Requires sudo for sysvinit install."
    fi
}

do_uninstall() {
    if systemctl --user list-unit-files | grep -q 'aro-watchdog.service'; then
        systemctl --user disable --now aro-watchdog || true
        rm -f "$HOME/.config/systemd/user/aro-watchdog.service"
        systemctl --user daemon-reload || true
        echo "systemd service uninstalled."
    else
        echo "Uninstall for runit/sysvinit must be done manually by root."
    fi
    do_stop
    echo "Done."
}

do_test_notify() {
    LATEST_LOG_FILE=$(get_latest_aro_log)
    parse_node_info
    
    local f_today=$(format_number "$REWARD_TODAY")
    local f_yest=$(format_number "$REWARD_YESTERDAY")
    local f_uptime=$(format_uptime "$UPTIME")
    
    local msg="🧪 <b>[TEST] [ARO INFO] ${HOSTNAME}</b>
──────────────────────
🖥️ VPS: ${HOSTNAME}
👤 User: ${CURRENT_USER}
🔢 Serial: ${SERIAL}
📧 Account: ${EMAIL}
🌐 IP: ${PUBLIC_IP}
💰 Reward today: ${f_today} pts
💰 Reward yesterday: ${f_yest} pts
📶 Uptime: ${f_uptime}%"

    send_telegram "$msg"
    echo "Test notification sent."
}

do_report() {
    LATEST_LOG_FILE=$(get_latest_aro_log)
    send_daily_report
    echo "Daily report sent."
}

# Core Routing
case "$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_stop
        sleep 2
        do_start
        ;;
    status)
        do_status
        ;;
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    log)
        tail -f "$WATCHDOG_LOG"
        ;;
    test-notify)
        do_test_notify
        ;;
    report)
        do_report
        ;;
    config)
        ${EDITOR:-nano} "$CONFIG_FILE"
        ;;
    start-foreground)
        watchdog_loop
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|install|uninstall|log|test-notify|report|config|start-foreground}"
        exit 1
        ;;
esac
