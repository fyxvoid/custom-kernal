#!/usr/bin/env bash
# Benchmark runner — compares stock vs. customised kernel metrics.
# Reproduces the experimental results from Chapter 7 of the project report.
#
# Run on both stock and custom kernel builds; compare the output CSVs.
#
# Dependencies: sysbench, stress-ng, iperf3, lmbench (lat_syscall), bc

set -euo pipefail

RESULTS_DIR="$(pwd)/results"
RUN_ID="${1:-$(date +%Y%m%d_%H%M%S)}"
KERNEL_VER=$(uname -r)
CSV="$RESULTS_DIR/${RUN_ID}_${KERNEL_VER}.csv"

mkdir -p "$RESULTS_DIR"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLU}[BENCH]${NC} $*"; }
ok()   { echo -e "${GRN}[OK]${NC}   $*"; }
warn() { echo -e "${YLW}[WARN]${NC} $*"; }
check_cmd() { command -v "$1" &>/dev/null; }

echo "metric,value,unit" > "$CSV"

record() {
    local metric="$1" value="$2" unit="$3"
    echo "${metric},${value},${unit}" >> "$CSV"
    printf "  %-45s %s %s\n" "$metric" "$value" "$unit"
}

# ── Module 1: Kernel image size ────────────────────────────────────────────────
log "Module 1: Kernel image size"
KIMG=""
for p in /boot/vmlinuz-"$KERNEL_VER" /boot/vmlinuz /boot/kernel; do
    [[ -f "$p" ]] && { KIMG="$p"; break; }
done
if [[ -n "$KIMG" ]]; then
    SIZE_KB=$(du -k "$KIMG" | cut -f1)
    record "kernel_image_size_kb" "$SIZE_KB" "KB"
else
    warn "Kernel image not found in /boot"
fi

MOD_COUNT=$(find /lib/modules/"$KERNEL_VER" -name "*.ko" 2>/dev/null | wc -l)
record "loaded_module_count" "$MOD_COUNT" "modules"

# Boot time (requires systemd-analyze or dmesg timestamps)
if command -v systemd-analyze &>/dev/null; then
    BOOT_TIME=$(systemd-analyze 2>/dev/null | grep "Startup finished" | \
        grep -oP '\d+\.\d+(?=s \(kernel\))' | head -1 || echo "N/A")
    record "boot_time_kernel_s" "$BOOT_TIME" "s"
fi

# ── Module 2: Memory management ────────────────────────────────────────────────
log "Module 2: Memory management"

IDLE_MEM=$(free -m | awk '/^Mem:/ {print $3}')
record "memory_used_idle_mb" "$IDLE_MEM" "MB"

if check_cmd sysbench; then
    MEM_LATENCY=$(sysbench memory --memory-block-size=1K --memory-total-size=1G \
        run 2>/dev/null | grep "Average" | grep -oP '[\d.]+' | head -1 || echo "N/A")
    record "memory_alloc_latency_us" "$MEM_LATENCY" "us"
else
    warn "sysbench not found — skipping memory latency"
fi

# Fragmentation index: % of high-order free pages
log "  Measuring buddy allocator fragmentation …"
TOTAL_FREE=0; HIGH_FREE=0
while IFS= read -r line; do
    order=0
    for count in $line; do
        [[ "$count" =~ ^[0-9]+$ ]] || { (( order++ )) || true; continue; }
        pages=$(( count << order ))
        TOTAL_FREE=$(( TOTAL_FREE + pages ))
        (( order >= 4 )) && HIGH_FREE=$(( HIGH_FREE + pages ))
        (( order++ )) || true
    done
done < <(grep Normal /proc/buddyinfo 2>/dev/null | awk '{for(i=5;i<=NF;i++) print $i}' | \
         paste -s -d' ' | awk '{print}')

if (( TOTAL_FREE > 0 )); then
    FRAG=$(echo "scale=2; 100 - ($HIGH_FREE * 100 / $TOTAL_FREE)" | bc)
    record "memory_fragmentation_pct" "$FRAG" "%"
fi

# ── Module 3: Network security ─────────────────────────────────────────────────
log "Module 3: Network security"

if check_cmd iperf3; then
    # Run iperf3 server in background for 10s, measure throughput
    iperf3 -s -D -I /tmp/iperf3.pid 2>/dev/null || true
    sleep 1
    THROUGHPUT=$(iperf3 -c 127.0.0.1 -t 5 -J 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); \
        print(round(d['end']['sum_received']['bits_per_second']/1e6,1))" 2>/dev/null \
        || echo "N/A")
    record "iperf3_loopback_mbps" "$THROUGHPUT" "Mbps"
    kill "$(cat /tmp/iperf3.pid 2>/dev/null)" 2>/dev/null || true
else
    warn "iperf3 not found — skipping network throughput"
fi

# Port scan detection via rbpf module
if [[ -f /proc/rbpf_rules ]]; then
    DROPPED=$(awk '/stat_dropped/ {print $2}' /proc/rbpf_rules 2>/dev/null || \
        grep -oP 'dropped=\K\d+' /proc/rbpf_rules 2>/dev/null || echo "0")
    record "rbpf_packets_dropped" "$DROPPED" "packets"
    record "rbpf_module_active" "1" "bool"
else
    record "rbpf_module_active" "0" "bool"
fi

# ── Module 4: Security module ──────────────────────────────────────────────────
log "Module 4: Security module"

if [[ -f /proc/acm_policy ]]; then
    DENY_COUNT=$(grep "denied=" /proc/acm_policy 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
    record "acm_denied_operations" "$DENY_COUNT" "count"
    record "acm_lsm_active" "1" "bool"
else
    record "acm_lsm_active" "0" "bool"
fi

# System call overhead via lmbench lat_syscall
if check_cmd lat_syscall; then
    SYSCALL_LAT=$(lat_syscall -N 1000 null 2>/dev/null | \
        grep -oP '[\d.]+(?= microseconds)' | head -1 || echo "N/A")
    record "syscall_latency_us" "$SYSCALL_LAT" "us"
else
    warn "lmbench lat_syscall not found — skipping syscall latency"
fi

# ── Sysctl snapshot ───────────────────────────────────────────────────────────
log "Kernel parameters snapshot"
record "vm_swappiness"           "$(sysctl -n vm.swappiness 2>/dev/null)"          ""
record "vm_min_free_kbytes"      "$(sysctl -n vm.min_free_kbytes 2>/dev/null)"     "KB"
record "vm_vfs_cache_pressure"   "$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)"  ""

ok "Results written to $CSV"
log "Compare two runs with: diff <stock.csv> <custom.csv>"
