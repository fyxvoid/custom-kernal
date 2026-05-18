#!/usr/bin/env bash
# Module 1: Kernel Lightening — Static Configuration Pruning Algorithm (SCPA)
#
# Usage:
#   ./scpa.sh [--kernel-src <path>] [--arch <arch>] [--profile <profile>]
#             [--output <config_file>] [--dry-run]
#
# Profiles: embedded | server | desktop | iot
# Default:  embedded (most aggressive pruning)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
KERNEL_SRC="${KERNEL_SRC:-/usr/src/linux}"
ARCH="${ARCH:-x86_64}"
PROFILE="${PROFILE:-embedded}"
OUTPUT_CONFIG="${OUTPUT_CONFIG:-$(pwd)/hardened.config}"
DRY_RUN=0
JOBS=$(nproc)
LOG_FILE="$(pwd)/scpa_$(date +%Y%m%d_%H%M%S).log"

# Colours
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLU}[SCPA]${NC} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GRN}[OK]${NC}   $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YLW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERR]${NC}  $*" | tee -a "$LOG_FILE"; }

usage() {
    cat <<EOF
SCPA — Static Configuration Pruning Algorithm

Usage: $0 [OPTIONS]

Options:
  --kernel-src <path>   Path to kernel source tree  (default: /usr/src/linux)
  --arch <arch>         Target architecture          (default: x86_64)
  --profile <profile>   Pruning profile: embedded | server | desktop | iot
  --output <file>       Output .config file path
  --dry-run             Print changes without writing
  -h, --help            Show this help

Environment variables override corresponding defaults:
  KERNEL_SRC, ARCH, PROFILE, OUTPUT_CONFIG
EOF
}

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --kernel-src) KERNEL_SRC="$2"; shift 2 ;;
        --arch)       ARCH="$2";       shift 2 ;;
        --profile)    PROFILE="$2";    shift 2 ;;
        --output)     OUTPUT_CONFIG="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=1;       shift ;;
        -h|--help)    usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ── Validate environment ───────────────────────────────────────────────────────
[[ -d "$KERNEL_SRC" ]] || { err "Kernel source not found: $KERNEL_SRC"; exit 1; }
[[ -f "$KERNEL_SRC/Makefile" ]] || { err "Not a kernel source tree: $KERNEL_SRC"; exit 1; }

log "SCPA starting"
log "  Kernel source : $KERNEL_SRC"
log "  Architecture  : $ARCH"
log "  Profile       : $PROFILE"
log "  Output config : $OUTPUT_CONFIG"
log "  Dry run       : $DRY_RUN"

# ── Step 1: Generate a baseline defconfig ─────────────────────────────────────
WORK_CONFIG="$(mktemp /tmp/scpa_config.XXXXXX)"
trap 'rm -f "$WORK_CONFIG"' EXIT

log "Step 1: Generating defconfig baseline …"
if [[ $DRY_RUN -eq 0 ]]; then
    make -C "$KERNEL_SRC" ARCH="$ARCH" defconfig O="$(dirname "$WORK_CONFIG")" \
        2>>"$LOG_FILE"
    cp "$KERNEL_SRC/.config" "$WORK_CONFIG" 2>/dev/null \
        || { warn "Using default config from make output"; }
else
    log "  [dry-run] would run: make -C $KERNEL_SRC ARCH=$ARCH defconfig"
fi

# ── Helper: set/unset a config option ─────────────────────────────────────────
set_option() {
    local opt="$1" val="$2" cfg="$3"
    if [[ $DRY_RUN -eq 1 ]]; then
        log "  [dry-run] $opt=$val"
        return
    fi
    if grep -q "^${opt}=" "$cfg" 2>/dev/null; then
        sed -i "s|^${opt}=.*|${opt}=${val}|" "$cfg"
    elif grep -q "^# ${opt} is not set" "$cfg" 2>/dev/null; then
        if [[ "$val" != "n" ]]; then
            sed -i "s|^# ${opt} is not set|${opt}=${val}|" "$cfg"
        fi
    else
        echo "${opt}=${val}" >> "$cfg"
    fi
}

disable() { set_option "$1" "n" "$WORK_CONFIG"; }
enable()  { set_option "$1" "y" "$WORK_CONFIG"; }
set_val() { set_option "$1" "$2" "$WORK_CONFIG"; }

# ── Step 2: Profile-specific pruning ──────────────────────────────────────────
log "Step 2: Applying SCPA pruning rules for profile '$PROFILE' …"

# ── 2a: Always disabled (all profiles) ────────────────────────────────────────
log "  Disabling debug / tracing facilities …"
ALWAYS_DISABLE=(
    # Debugging & tracing
    CONFIG_DEBUG_KERNEL
    CONFIG_DEBUG_INFO
    CONFIG_DEBUG_FS
    CONFIG_KPROBES
    CONFIG_FTRACE
    CONFIG_FUNCTION_TRACER
    CONFIG_FUNCTION_GRAPH_TRACER
    CONFIG_DYNAMIC_FTRACE
    CONFIG_KASAN
    CONFIG_UBSAN
    CONFIG_KCSAN
    CONFIG_LOCKDEP
    CONFIG_PROVE_LOCKING
    CONFIG_LOCK_STAT
    CONFIG_DEBUG_SPINLOCK
    CONFIG_DEBUG_MUTEXES
    CONFIG_DEBUG_ATOMIC_SLEEP
    CONFIG_SLUB_DEBUG
    CONFIG_PAGE_POISONING
    CONFIG_DEBUG_PAGEALLOC
    CONFIG_KMEMLEAK
    CONFIG_KMSAN
    CONFIG_KCOV
    # Unused filesystems (conservative — re-enable as needed)
    CONFIG_NTFS_FS
    CONFIG_HFSPLUS_FS
    CONFIG_AFFS_FS
    CONFIG_BEFS_FS
    CONFIG_ROMFS_FS
    CONFIG_CRAMFS
    CONFIG_MINIX_FS
    CONFIG_OMFS_FS
    CONFIG_SUN_OPENPROMFS
    # Legacy network protocols
    CONFIG_IPX
    CONFIG_APPLETALK
    CONFIG_X25
    CONFIG_LAPB
    CONFIG_WAN_ROUTER
    CONFIG_NET_VENDOR_3COM
    CONFIG_NET_VENDOR_ADAPTEC
    CONFIG_NET_VENDOR_ALTEON
    # Bluetooth (disable if not needed)
    CONFIG_BT
    CONFIG_BT_HCIBTUSB
    CONFIG_BT_HCIBTSDIO
    # Sound (typically unused on servers/embedded)
    CONFIG_SOUND
    CONFIG_SND
    # Amateur radio
    CONFIG_HAMRADIO
    # InfiniBand (unless HPC target)
    CONFIG_INFINIBAND
    # Exotic bus interfaces
    CONFIG_PCMCIA
    CONFIG_CARDBUS
    CONFIG_FIREWIRE
    CONFIG_IEEE1394
    CONFIG_MCA
    # Virtualization guest support (unless VM target)
    CONFIG_XEN_GUEST
)

for opt in "${ALWAYS_DISABLE[@]}"; do
    disable "$opt"
done

# ── 2b: Profile-specific pruning ──────────────────────────────────────────────
case "$PROFILE" in

    embedded|iot)
        log "  Profile: $PROFILE — aggressive pruning …"

        # Timer frequency → 250 Hz (reduces CPU wakeups)
        disable CONFIG_HZ_1000
        disable CONFIG_HZ_300
        enable  CONFIG_HZ_250
        set_val CONFIG_HZ 250

        # Disable module loading (monolithic build)
        disable CONFIG_MODULES

        # Disable swap (not present on many embedded devices)
        disable CONFIG_SWAP

        # Disable SMP for single-core targets (adjust if multi-core)
        # disable CONFIG_SMP

        # NFS client/server
        disable CONFIG_NFS_FS
        disable CONFIG_NFSD
        disable CONFIG_CIFS

        # Disable USB host (adjust if USB needed)
        # disable CONFIG_USB

        # Disable power management features not needed on embedded
        disable CONFIG_CPU_FREQ
        disable CONFIG_ACPI_DOCK

        # Strip out optional crypto not used
        disable CONFIG_CRYPTO_TEST
        disable CONFIG_CRYPTO_SIMD
        disable CONFIG_CRYPTO_GHASH_CLMUL_NI_INTEL

        ok "Embedded/IoT profile applied"
        ;;

    server)
        log "  Profile: server — moderate pruning …"

        # Keep modules, SMP, NFS, etc. — servers need flexibility
        # but still strip GUI, USB HID, Bluetooth, Sound, video
        disable CONFIG_DRM
        disable CONFIG_FB
        disable CONFIG_VGA_CONSOLE
        disable CONFIG_USB_HID
        disable CONFIG_INPUT_JOYSTICK
        disable CONFIG_INPUT_TABLET
        disable CONFIG_INPUT_TOUCHSCREEN
        disable CONFIG_INPUT_MISC

        # HZ 1000 is typical for servers (low latency syscalls)
        enable  CONFIG_HZ_1000
        set_val CONFIG_HZ 1000

        ok "Server profile applied"
        ;;

    desktop)
        log "  Profile: desktop — light pruning …"
        # Keep DRM, sound, USB — only strip exotic/legacy items
        disable CONFIG_FDDI
        disable CONFIG_HIPPI
        disable CONFIG_NET_SB1000

        enable  CONFIG_HZ_1000
        set_val CONFIG_HZ 1000

        ok "Desktop profile applied"
        ;;

    *)
        warn "Unknown profile '$PROFILE' — only common pruning applied"
        ;;
esac

# ── Step 3: Security hardening options ────────────────────────────────────────
log "Step 3: Enabling security hardening options …"

SECURITY_ENABLE=(
    CONFIG_SECURITY
    CONFIG_SECURITYFS
    CONFIG_SECURITY_NETWORK
    CONFIG_LSM_MMAP_MIN_ADDR
    CONFIG_SECURITY_YAMA
    CONFIG_HARDENED_USERCOPY
    CONFIG_FORTIFY_SOURCE
    CONFIG_STACKPROTECTOR
    CONFIG_STACKPROTECTOR_STRONG
    CONFIG_RANDOMIZE_BASE
    CONFIG_RANDOMIZE_MEMORY
    CONFIG_CC_STACKPROTECTOR_STRONG
    CONFIG_STRICT_KERNEL_RWX
    CONFIG_STRICT_MODULE_RWX
    CONFIG_REFCOUNT_FULL
    CONFIG_INIT_ON_ALLOC_DEFAULT_ON
    CONFIG_INIT_ON_FREE_DEFAULT_ON
    CONFIG_PAGE_TABLE_ISOLATION
    CONFIG_RETPOLINE
    CONFIG_GCC_PLUGIN_LATENT_ENTROPY
    CONFIG_GCC_PLUGIN_RANDSTRUCT
    CONFIG_SLAB_FREELIST_RANDOM
    CONFIG_SLAB_FREELIST_HARDENED
    CONFIG_SHUFFLE_PAGE_ALLOCATOR
    CONFIG_VMAP_STACK
    CONFIG_STRICT_DEVMEM
    CONFIG_IO_STRICT_DEVMEM
    CONFIG_SECURITY_DMESG_RESTRICT
)

for opt in "${SECURITY_ENABLE[@]}"; do
    enable "$opt"
done

# Disable kernel.dmesg_restrict override
set_val CONFIG_SECURITY_DMESG_RESTRICT y

# ── Step 4: Resolve dependencies ──────────────────────────────────────────────
log "Step 4: Resolving configuration dependencies …"
if [[ $DRY_RUN -eq 0 ]]; then
    cp "$WORK_CONFIG" "$KERNEL_SRC/.config"
    make -C "$KERNEL_SRC" ARCH="$ARCH" olddefconfig 2>>"$LOG_FILE"
    cp "$KERNEL_SRC/.config" "$OUTPUT_CONFIG"
    ok "Resolved config written to $OUTPUT_CONFIG"
else
    log "  [dry-run] would run: make olddefconfig"
fi

# ── Step 5: Report statistics ──────────────────────────────────────────────────
if [[ $DRY_RUN -eq 0 ]] && [[ -f "$OUTPUT_CONFIG" ]]; then
    ENABLED=$(grep -c "^CONFIG_.*=y$" "$OUTPUT_CONFIG" 2>/dev/null || true)
    MODULES=$(grep -c "^CONFIG_.*=m$" "$OUTPUT_CONFIG" 2>/dev/null || true)
    DISABLED=$(grep -c "^# CONFIG_.* is not set$" "$OUTPUT_CONFIG" 2>/dev/null || true)

    log "Step 5: Configuration summary"
    log "  Built-in options (=y) : $ENABLED"
    log "  Module options  (=m)  : $MODULES"
    log "  Disabled options      : $DISABLED"
fi

# ── Step 6: (Optional) Compile ────────────────────────────────────────────────
if [[ $DRY_RUN -eq 0 ]]; then
    read -rp "Compile the kernel now? [y/N] " COMPILE
    if [[ "${COMPILE,,}" == "y" ]]; then
        log "Step 6: Compiling kernel (make -j$JOBS) …"
        cp "$OUTPUT_CONFIG" "$KERNEL_SRC/.config"
        time make -C "$KERNEL_SRC" ARCH="$ARCH" -j"$JOBS" 2>&1 | tee -a "$LOG_FILE"
        KIMG=$(find "$KERNEL_SRC/arch/$ARCH/boot" -name "bzImage" 2>/dev/null | head -1)
        if [[ -n "$KIMG" ]]; then
            SIZE=$(du -sh "$KIMG" | cut -f1)
            ok "Kernel image: $KIMG ($SIZE)"
        fi
    else
        log "Skipping compilation. Run:"
        log "  cp $OUTPUT_CONFIG <kernel_src>/.config"
        log "  make -C <kernel_src> ARCH=$ARCH -j\$(nproc)"
    fi
fi

ok "SCPA complete. Log: $LOG_FILE"
