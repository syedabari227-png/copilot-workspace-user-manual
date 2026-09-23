#!/usr/bin/env bash

set -euo pipefail

threshold=60
explain=false

if [[ $# -gt 1 || ( $# -eq 1 && $1 != "explain" ) ]]; then
    printf 'Usage: %s [explain]\n' "${0##*/}" >&2
    exit 2
fi

if [[ $# -eq 1 ]]; then
    explain=true
fi

read_cpu_times() {
    awk '/^cpu / {
        idle = $5 + $6
        total = $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9 + $10 + $11
        print idle, total
        exit
    }' /proc/stat
}

read -r idle_before total_before < <(read_cpu_times)
sleep 1
read -r idle_after total_after < <(read_cpu_times)

cpu_delta=$((total_after - total_before))
idle_delta=$((idle_after - idle_before))
if (( cpu_delta > 0 )); then
    cpu_usage=$(( (100 * (cpu_delta - idle_delta)) / cpu_delta ))
else
    cpu_usage=0
fi

read -r memory_total memory_available < <(
    awk '
        /^MemTotal:/ { total = $2 }
        /^MemAvailable:/ { available = $2 }
        END { print total, available }
    ' /proc/meminfo
)

if (( memory_total > 0 )); then
    memory_usage=$((100 * (memory_total - memory_available) / memory_total))
else
    printf 'Unable to determine memory utilization.\n' >&2
    exit 1
fi

disk_usage=$(df -P / | awk 'END { gsub(/%/, "", $5); print $5 }')

unhealthy_resources=()
if (( cpu_usage > threshold )); then
    unhealthy_resources+=("CPU")
fi
if (( memory_usage > threshold )); then
    unhealthy_resources+=("memory")
fi
if (( disk_usage > threshold )); then
    unhealthy_resources+=("disk")
fi

if (( ${#unhealthy_resources[@]} > 0 )); then
    health_status="Not healthy"
else
    health_status="Healthy"
fi

printf 'VM health: %s\n' "$health_status"

if [[ "$explain" == true ]]; then
    printf 'CPU utilization: %d%%\n' "$cpu_usage"
    printf 'Memory utilization: %d%%\n' "$memory_usage"
    printf 'Disk utilization (/): %d%%\n' "$disk_usage"
    printf 'Threshold: %d%% (values above the threshold make the VM Not healthy)\n' "$threshold"

    if [[ "$health_status" == "Healthy" ]]; then
        printf 'Reason: CPU, memory, and disk utilization are at or below the threshold.\n'
    else
        unhealthy_reason=$(printf '%s, ' "${unhealthy_resources[@]}")
        unhealthy_reason=${unhealthy_reason%, }
        printf 'Reason: %s utilization is above the threshold.\n' \
            "$unhealthy_reason"
    fi
fi
