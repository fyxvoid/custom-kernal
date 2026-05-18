#!/usr/bin/env bash
# Module 2: MMOA — Runtime sysctl tuning script
# Applies memory optimisation parameters without loading a kernel module.
# Use this when the mmoa.ko module is not available (e.g. stock kernel).

set -euo pipefail

PROFILE="${1:-embedded}"  # embedded | server | desktop
LOG="$(pwd)/mmoa_tune_$(date +%Y%m%d_%H%M%S).log"

log() { echo "[MMOA] $*" | tee -a "$LOG"; }

require_root() {
    [[ $EUID -eq 0 ]] || { echo "Must be run as root."; exit 1; }
}

save_originals() {
    log "Saving original values …"
    sysctl vm.swappiness vm.min_free_kbytes vm.vfs_cache_pressure \
           vm.watermark_scale_factor vm.overcommit_memory \
           vm.overcommit_ratio 2>/dev/null | tee /tmp/mmoa_originals.txt | \
        tee -a "$LOG"
}

apply_embedded() {
    log "Applying EMBEDDED/IoT memory profile …"
    sysctl -w vm.swappiness=10
    sysctl -w vm.vfs_cache_pressure=150
    sysctl -w vm.watermark_scale_factor=200
    # Double min_free_kbytes
    ORIG=$(sysctl -n vm.min_free_kbytes)
    sysctl -w vm.min_free_kbytes=$(( ORIG * 2 ))
    # Disable overcommit — embedded must not OOM
    sysctl -w vm.overcommit_memory=2
    sysctl -w vm.overcommit_ratio=80
    # Transparent huge pages: madvise only
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
        echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
        log "THP set to madvise"
    fi
}

apply_server() {
    log "Applying SERVER memory profile …"
    sysctl -w vm.swappiness=20
    sysctl -w vm.vfs_cache_pressure=100
    sysctl -w vm.watermark_scale_factor=150
    ORIG=$(sysctl -n vm.min_free_kbytes)
    sysctl -w vm.min_free_kbytes=$(( ORIG * 2 ))
    sysctl -w vm.overcommit_memory=1  # Allow overcommit (typical server)
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
        echo always > /sys/kernel/mm/transparent_hugepage/enabled
        log "THP set to always"
    fi
}

apply_desktop() {
    log "Applying DESKTOP memory profile …"
    sysctl -w vm.swappiness=40
    sysctl -w vm.vfs_cache_pressure=75
    sysctl -w vm.watermark_scale_factor=125
    ORIG=$(sysctl -n vm.min_free_kbytes)
    sysctl -w vm.min_free_kbytes=$(( ORIG * 2 ))
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
        echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
    fi
}

check_fragmentation() {
    log "Fragmentation index (buddy allocator):"
    cat /proc/buddyinfo | tee -a "$LOG"
    log "Memory info:"
    grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree" \
        /proc/meminfo | tee -a "$LOG"
}

trigger_compaction() {
    log "Triggering memory compaction …"
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null \
        || log "Compaction not available (need kernel >= 2.6.35)"
}

require_root
save_originals

case "$PROFILE" in
    embedded|iot) apply_embedded ;;
    server)       apply_server ;;
    desktop)      apply_desktop ;;
    *)
        echo "Unknown profile: $PROFILE"
        echo "Usage: $0 [embedded|server|desktop]"
        exit 1
        ;;
esac

check_fragmentation
trigger_compaction

log "MMOA tuning applied. Restore originals with:"
log "  while IFS= read -r line; do sysctl -w \"\$line\"; done < /tmp/mmoa_originals.txt"
log "Log: $LOG"
