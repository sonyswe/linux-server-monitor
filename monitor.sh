i
#!/bin/bash

set -o pipefail

# ==========================================
# LINUX SERVER MONITORING SCRIPT
# ==========================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/config.sh"

# Store alert details
ALERT_KEYS=()
ALERT_MESSAGES=()

# ==========================================
# 1. LOGGING FUNCTION
# ==========================================

log_message() {
    local message="$1"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | $message" |
        tee -a "$LOG_FILE"
}

# ==========================================
# 2. ALERT COLLECTION
# ==========================================

add_alert() {
    local key="$1"
    local message="$2"

    ALERT_KEYS+=("$key")
    ALERT_MESSAGES+=("$message")

    log_message "ALERT: $message"
}

# ==========================================
# 3. CPU MONITORING
# ==========================================

check_cpu() {

    local total1 idle1 total2 idle2
    local total_diff idle_diff cpu_usage

    read -r total1 idle1 < <(
        awk '/^cpu / {
            total = 0
            for (i = 2; i <= 9 && i <= NF; i++)
                total += $i

            idle = $5 + $6
            print total, idle
            exit
        }' /proc/stat
    )

    sleep 1

    read -r total2 idle2 < <(
        awk '/^cpu / {
            total = 0
            for (i = 2; i <= 9 && i <= NF; i++)
                total += $i

            idle = $5 + $6
            print total, idle
            exit
        }' /proc/stat
    )

    total_diff=$((total2 - total1))
    idle_diff=$((idle2 - idle1))

    if (( total_diff > 0 )); then
        cpu_usage=$(( (100 * (total_diff - idle_diff)) / total_diff ))
    else
        cpu_usage=0
    fi

    log_message "CPU Usage: ${cpu_usage}%"

    if (( cpu_usage >= CPU_THRESHOLD )); then
        add_alert "CPU" \
            "High CPU usage: ${cpu_usage}% (Threshold: ${CPU_THRESHOLD}%)"
    fi
}

# ==========================================
# 4. MEMORY MONITORING
# ==========================================

check_memory() {

    local memory_usage

    memory_usage=$(free -m | awk '/^Mem:/ {
        if ($2 > 0)
            printf "%.0f", (($2 - $7) / $2) * 100
        else
            print 0
    }')

    memory_usage=${memory_usage:-0}

    log_message "Memory Usage: ${memory_usage}%"

    if (( memory_usage >= MEMORY_THRESHOLD )); then
        add_alert "MEMORY" \
            "High memory usage: ${memory_usage}% (Threshold: ${MEMORY_THRESHOLD}%)"
    fi
}

# ==========================================
# 5. DISK MONITORING
# ==========================================

check_disk() {

    while read -r filesystem usage mountpoint; do

        log_message "Disk Usage: $mountpoint = ${usage}%"

        if (( usage >= DISK_THRESHOLD )); then
            add_alert "DISK_${mountpoint}" \
                "High disk usage on $mountpoint: ${usage}% (Threshold: ${DISK_THRESHOLD}%)"
        fi

    done < <(
        df -P -x tmpfs -x devtmpfs -x squashfs |
        awk 'NR > 1 {
            gsub("%", "", $5)

            if ($6 == "/" || $6 ~ "^/mnt/[a-z]$") {
                print $1, $5, $6
            }
        }'
    )
}

# ==========================================
# 6. PROCESS MONITORING
# ==========================================

check_processes() {

    log_message "Top 5 CPU-consuming processes:"

    ps -eo pid,comm,%cpu,%mem --sort=-%cpu |
        head -n 6 |
        while IFS= read -r process; do
            log_message "$process"
        done
}

# ==========================================
# 7. UPTIME MONITORING
# ==========================================

check_uptime() {

    local uptime_info

    uptime_info=$(uptime -p)

    log_message "Server Uptime: $uptime_info"
}

# ==========================================
# 8. SERVICE MONITORING
# ==========================================

check_services() {

    for service in "${SERVICES[@]}"; do

        if systemctl is-active --quiet "$service"; then
            log_message "Service $service: RUNNING"
        else
            add_alert "SERVICE_${service}" \
                "Service $service is NOT RUNNING!"
        fi

    done
}

# ==========================================
# 9. EMAIL ALERT FUNCTION
# ==========================================

send_alerts() {

    # No alerts: clear previous alert state
    if (( ${#ALERT_KEYS[@]} == 0 )); then

        if [[ -s "$ALERT_STATE_FILE" ]]; then
            : > "$ALERT_STATE_FILE"
            log_message "All previous alerts have recovered."
        fi

        return
    fi

    # Create stable alert identifiers
    local current_state

    current_state=$(
        printf '%s\n' "${ALERT_KEYS[@]}" | sort -u
    )

    local previous_state=""

    if [[ -f "$ALERT_STATE_FILE" ]]; then
        previous_state=$(cat "$ALERT_STATE_FILE")
    fi

    # Avoid sending duplicate emails
    if [[ "$current_state" == "$previous_state" ]]; then
        log_message "Existing alerts unchanged. Email suppressed."
        return
    fi

    # Check msmtp availability
    if ! command -v msmtp >/dev/null 2>&1; then
        log_message "ERROR: msmtp is not installed."
        return
    fi

    # Construct and send email
    if {
        printf 'From: %s\n' "$ALERT_EMAIL"
        printf 'To: %s\n' "$ALERT_EMAIL"
        printf 'Subject: [ALERT] Linux Server Monitoring\n'
        printf 'MIME-Version: 1.0\n'
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf '\n'
        printf 'Linux Server Health Alert\n\n'
        printf 'Detected issues:\n\n'

        printf '%s\n' "${ALERT_MESSAGES[@]}"

        printf '\nPlease investigate the server immediately.\n'

    } | msmtp -a gmail -t; then

        printf '%s\n' "$current_state" > "$ALERT_STATE_FILE"

        log_message "Email alert sent successfully to $ALERT_EMAIL"

    else
        log_message "ERROR: Failed to send email alert."
    fi
}

# ==========================================
# 10. MAIN EXECUTION
# ==========================================

log_message "========== SERVER HEALTH CHECK STARTED =========="

check_cpu
check_memory
check_disk
check_processes
check_uptime
check_services

send_alerts

log_message "========== SERVER HEALTH CHECK COMPLETED =========="

