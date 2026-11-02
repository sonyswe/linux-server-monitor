#!/bin/bash

set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="$SCRIPT_DIR/data"
CSV_FILE="$DATA_DIR/metrics.csv"

mkdir -p "$DATA_DIR"

# Create CSV header if needed
if [[ ! -s "$CSV_FILE" ]]; then
    echo "timestamp,cpu,memory,root_disk,mnt_c_disk,mnt_d_disk,ssh_status,nginx_status" > "$CSV_FILE"
fi

# CPU usage
read -r total1 idle1 < <(
    awk '/^cpu / {
        total=0
        for (i=2; i<=NF; i++) total += $i
        print total, $5+$6
        exit
    }' /proc/stat
)

sleep 1

read -r total2 idle2 < <(
    awk '/^cpu / {
        total=0
        for (i=2; i<=NF; i++) total += $i
        print total, $5+$6
        exit
    }' /proc/stat
)

total_diff=$((total2-total1))
idle_diff=$((idle2-idle1))

CPU=0
if (( total_diff > 0 )); then
    CPU=$((100 * (total_diff-idle_diff) / total_diff))
fi

# Memory usage
MEMORY=$(free -m | awk '/^Mem:/ {
    if ($2 > 0) printf "%.0f", (($2-$7)/$2)*100
}')

MEMORY=${MEMORY:-0}

# Disk usage
ROOT_DISK=0
C_DISK=0
D_DISK=0

while read -r usage mountpoint; do
    case "$mountpoint" in
        "/") ROOT_DISK="$usage" ;;
        "/mnt/c") C_DISK="$usage" ;;
        "/mnt/d") D_DISK="$usage" ;;
    esac
done < <(
    df -P -x tmpfs -x devtmpfs -x squashfs |
    awk 'NR>1 && ($6=="/" || $6 ~ "^/mnt/[a-z]$") {
        gsub("%","",$5)
        print $5,$6
    }'
)

# Service status
SSH_STATUS="STOPPED"
NGINX_STATUS="STOPPED"

systemctl is-active --quiet ssh && SSH_STATUS="RUNNING"
systemctl is-active --quiet nginx && NGINX_STATUS="RUNNING"

# Save metrics
printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$CPU" "$MEMORY" "$ROOT_DISK" "$C_DISK" "$D_DISK" \
    "$SSH_STATUS" "$NGINX_STATUS" >> "$CSV_FILE"

echo "Metrics successfully saved to $CSV_FILE"
