#!/bin/bash

CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85

LOG_FILE="$HOME/linux-server-monitor/logs/monitor.log"
ALERT_STATE_FILE="$HOME/linux-server-monitor/logs/alert_state"

SERVICES=("ssh" "nginx")

ALERT_EMAIL="your-email@gmail.com"
