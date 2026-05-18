#!/usr/bin/env bash
# =============================================================================
# SecureKernel — One-shot setup & launch script for Debian-based systems
# =============================================================================
#
# What this script does, in order:
#   1. Detects if running on a Debian/Ubuntu/Kali/Mint system
#   2. Installs all build and runtime dependencies
#   3. Downloads Linux 6.6.140 LTS source (if not already present)
#   4. Patches the kernel source with all four SecureKernel modules
#   5. Configures and compiles the kernel (SCPA hardened config)
#   6. Builds a minimal busybox initramfs
#   7. Boots the finished kernel in QEMU with a serial TTY
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# On subsequent runs the script skips already-completed steps automatically.
#
# Press Ctrl-A then X inside QEMU to quit.
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() {
    echo ""
    echo -e "${BOLD}${CYN}============================================================${NC}"
    echo -e "${BOLD}${CYN}  $*${NC}"
    echo -e "${BOLD}${CYN}============================================================${NC}"
    echo ""
}

step()  { echo -e "${BLU}[STEP]${NC} $*"; }
ok()    { echo -e "${GRN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YLW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERR ]${NC} $*" >&2; exit 1; }

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/linux-build"
KSRC="$BUILD_DIR/linux-6.6.140"
KTARBALL="$BUILD_DIR/linux-6.6.140.tar.xz"
KURL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.140.tar.xz"
INITRD="$BUILD_DIR/initramfs"
CPIO="$BUILD_DIR/initramfs.cpio.gz"
BZIMAGE="$KSRC/arch/x86/boot/bzImage"
JOBS=$(nproc)

# ── Banner ────────────────────────────────────────────────────────────────────
banner "SecureKernel Setup — Linux 6.6.140 LTS"
echo -e "  Script dir : ${BOLD}$SCRIPT_DIR${NC}"
echo -e "  Build dir  : ${BOLD}$BUILD_DIR${NC}"
echo -e "  CPU cores  : ${BOLD}$JOBS${NC}"
echo ""

# =============================================================================
# STEP 1 — Detect distro
# =============================================================================
banner "Step 1 — Detecting distribution"

if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS — /etc/os-release not found."
fi
source /etc/os-release

case "${ID_LIKE:-$ID}" in
    *debian*|*ubuntu*)
        ok "Detected Debian-based system: $PRETTY_NAME"
        PKG_MGR="apt-get"
        ;;
    *)
        die "This script supports Debian/Ubuntu/Kali/Mint only. Detected: ${PRETTY_NAME:-unknown}"
        ;;
esac

# =============================================================================
# STEP 2 — Install dependencies
# =============================================================================
banner "Step 2 — Installing dependencies"

DEPS=(
    # Kernel build essentials
    build-essential gcc make bc
    bison flex libssl-dev libelf-dev
    # Pahole for BTF (optional but prevents config warnings)
    dwarves
    # Compression
    cpio gzip xz-utils
    # Download
    wget curl
    # QEMU
    qemu-system-x86
    # Busybox for initramfs
    busybox
    # Misc
    python3 file
)

MISSING=()
for pkg in "${DEPS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    ok "All dependencies already installed."
else
    step "Installing: ${MISSING[*]}"
    if [[ $EUID -ne 0 ]]; then
        sudo $PKG_MGR update -qq
        sudo $PKG_MGR install -y "${MISSING[@]}"
    else
        $PKG_MGR update -qq
        $PKG_MGR install -y "${MISSING[@]}"
    fi
    ok "Dependencies installed."
fi

# Verify QEMU is usable
QEMU_BIN=$(command -v qemu-system-x86_64 2>/dev/null) || \
    die "qemu-system-x86_64 not found after installation."
ok "QEMU: $QEMU_BIN ($($QEMU_BIN --version | head -1))"

# =============================================================================
# STEP 3 — Download kernel source
# =============================================================================
banner "Step 3 — Kernel source"

mkdir -p "$BUILD_DIR"

if [[ -d "$KSRC" && -f "$KSRC/Makefile" ]]; then
    ok "Kernel source already extracted at $KSRC"
else
    if [[ ! -f "$KTARBALL" ]]; then
        step "Downloading Linux 6.6.140 (~141 MB) ..."
        wget -q --show-progress "$KURL" -O "$KTARBALL"
        ok "Downloaded: $(du -sh "$KTARBALL" | cut -f1)"
    else
        ok "Tarball already present: $(du -sh "$KTARBALL" | cut -f1)"
    fi

    step "Extracting kernel source ..."
    tar xf "$KTARBALL" -C "$BUILD_DIR"
    ok "Extracted to $KSRC"
fi

# =============================================================================
# STEP 4 — Patch kernel source with SecureKernel modules
# =============================================================================
banner "Step 4 — Patching kernel with SecureKernel modules"

patch_acm() {
    local target="$KSRC/security/acm"
    [[ -f "$target/acm_lsm.c" ]] && { ok "ACM LSM already patched."; return; }

    step "Patching Module 4 — ACM LSM into security/acm/"
    mkdir -p "$target"
    cp "$SCRIPT_DIR/module4_security/acm_lsm.c" "$target/"

    cat > "$target/Kconfig" << 'EOF'
config SECURITY_ACM
	bool "Access Control Mechanism (ACM) LSM"
	depends on SECURITY
	default y
	help
	  SecureKernel mandatory access control LSM. Enforces MAC
	  policy via security labels, managed at /proc/acm_policy.
EOF

    echo 'obj-$(CONFIG_SECURITY_ACM) += acm_lsm.o' > "$target/Makefile"

    # Patch security/Kconfig
    if ! grep -q "security/acm/Kconfig" "$KSRC/security/Kconfig"; then
        sed -i 's|source "security/Kconfig.hardening"|source "security/acm/Kconfig"\nsource "security/Kconfig.hardening"|' \
            "$KSRC/security/Kconfig"
    fi

    # Patch security/Makefile
    if ! grep -q "CONFIG_SECURITY_ACM" "$KSRC/security/Makefile"; then
        sed -i 's|obj-$(CONFIG_SECURITY_LANDLOCK).*+= landlock/|&\nobj-$(CONFIG_SECURITY_ACM)\t\t+= acm/|' \
            "$KSRC/security/Makefile"
    fi

    ok "ACM LSM patched."
}

patch_rbpf() {
    [[ -f "$KSRC/net/netfilter/rbpf.c" ]] && { ok "RBPF already patched."; return; }

    step "Patching Module 3 — RBPF into net/netfilter/"
    cp "$SCRIPT_DIR/module3_network/rbpf.c" "$KSRC/net/netfilter/"

    if ! grep -q "NETFILTER_RBPF" "$KSRC/net/netfilter/Kconfig"; then
        python3 - "$KSRC/net/netfilter/Kconfig" << 'EOF'
import sys
path = sys.argv[1]
entry = """
config NETFILTER_RBPF
\tbool "Rule-Based Packet Filter (RBPF)"
\tdepends on NETFILTER
\tdefault y
\thelp
\t  SecureKernel kernel-level packet filter.
\t  Rules managed at runtime via /proc/rbpf_rules.
"""
content = open(path).read()
content = content.replace('endmenu', entry + 'endmenu', 1)
open(path, 'w').write(content)
EOF
    fi

    if ! grep -q "rbpf" "$KSRC/net/netfilter/Makefile"; then
        echo 'obj-$(CONFIG_NETFILTER_RBPF) += rbpf.o' >> "$KSRC/net/netfilter/Makefile"
    fi

    ok "RBPF patched."
}

patch_mmoa() {
    [[ -f "$KSRC/drivers/misc/mmoa.c" ]] && { ok "MMOA already patched."; return; }

    step "Patching Module 2 — MMOA into drivers/misc/"
    cp "$SCRIPT_DIR/module2_memory/mmoa.c" "$KSRC/drivers/misc/"

    if ! grep -q "MISC_MMOA" "$KSRC/drivers/misc/Kconfig"; then
        python3 - "$KSRC/drivers/misc/Kconfig" << 'EOF'
import sys
path = sys.argv[1]
entry = """
config MISC_MMOA
\tbool "Memory Management Optimization Algorithm (MMOA)"
\tdefault y
\thelp
\t  SecureKernel memory allocator tuning and fragmentation
\t  monitor, managed via /proc/mmoa_stats and /proc/mmoa_control.
"""
content = open(path).read()
content = content.replace('endmenu', entry + 'endmenu', 1)
open(path, 'w').write(content)
EOF
    fi

    if ! grep -q "mmoa" "$KSRC/drivers/misc/Makefile"; then
        echo 'obj-$(CONFIG_MISC_MMOA) += mmoa.o' >> "$KSRC/drivers/misc/Makefile"
    fi

    ok "MMOA patched."
}

patch_acm
patch_rbpf
patch_mmoa

# =============================================================================
# STEP 5 — Configure kernel (SCPA)
# =============================================================================
banner "Step 5 — Kernel configuration (SCPA)"

if [[ -f "$KSRC/.config" ]] && grep -q "CONFIG_SECURITY_ACM=y" "$KSRC/.config"; then
    ok "Kernel already configured — skipping."
else
    step "Generating x86_64 defconfig ..."
    make -C "$KSRC" ARCH=x86_64 x86_64_defconfig 2>&1 | tail -2

    step "Applying SCPA pruning and SecureKernel settings ..."
    python3 - "$KSRC/.config" << 'EOF'
import sys, re

path = sys.argv[1]
cfg  = open(path).read()

def set_opt(cfg, opt, val):
    p1 = rf'^{re.escape(opt)}=.*$'
    p2 = rf'^# {re.escape(opt)} is not set$'
    line = f'{opt}={val}'
    if re.search(p1, cfg, re.MULTILINE):
        return re.sub(p1, line, cfg, flags=re.MULTILINE)
    if re.search(p2, cfg, re.MULTILINE):
        return re.sub(p2, line, cfg, flags=re.MULTILINE)
    return cfg + f'\n{line}\n'

# SCPA: disable debug/trace/unused
for opt in [
    'CONFIG_DEBUG_INFO_BTF', 'CONFIG_DEBUG_INFO_BTF_MODULES',
    'CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT',
    'CONFIG_KASAN', 'CONFIG_UBSAN', 'CONFIG_KCSAN',
    'CONFIG_LOCKDEP', 'CONFIG_PROVE_LOCKING',
    'CONFIG_SLUB_DEBUG', 'CONFIG_PAGE_POISONING', 'CONFIG_KMEMLEAK',
    'CONFIG_FTRACE', 'CONFIG_FUNCTION_TRACER', 'CONFIG_KPROBES',
    'CONFIG_BT', 'CONFIG_SOUND', 'CONFIG_HAMRADIO',
    'CONFIG_ATM', 'CONFIG_IPX', 'CONFIG_APPLETALK',
    'CONFIG_PCMCIA', 'CONFIG_FIREWIRE', 'CONFIG_INFINIBAND',
]:
    cfg = set_opt(cfg, opt, 'n')

# SCPA: HZ=250 (embedded — fewer timer interrupts)
cfg = set_opt(cfg, 'CONFIG_HZ_1000', 'n')
cfg = set_opt(cfg, 'CONFIG_HZ_250',  'y')
cfg = set_opt(cfg, 'CONFIG_HZ',      '250')

# Our three built-in modules
cfg = set_opt(cfg, 'CONFIG_SECURITY_ACM',   'y')
cfg = set_opt(cfg, 'CONFIG_NETFILTER_RBPF', 'y')
cfg = set_opt(cfg, 'CONFIG_MISC_MMOA',      'y')

# Security hardening
for opt in [
    'CONFIG_HARDENED_USERCOPY', 'CONFIG_FORTIFY_SOURCE',
    'CONFIG_STACKPROTECTOR_STRONG', 'CONFIG_RANDOMIZE_BASE',
    'CONFIG_RANDOMIZE_MEMORY', 'CONFIG_STRICT_KERNEL_RWX',
    'CONFIG_STRICT_MODULE_RWX', 'CONFIG_PAGE_TABLE_ISOLATION',
    'CONFIG_RETPOLINE', 'CONFIG_VMAP_STACK', 'CONFIG_STRICT_DEVMEM',
    'CONFIG_SLAB_FREELIST_RANDOM', 'CONFIG_SLAB_FREELIST_HARDENED',
    'CONFIG_SHUFFLE_PAGE_ALLOCATOR', 'CONFIG_INIT_ON_ALLOC_DEFAULT_ON',
    'CONFIG_SECURITY_YAMA', 'CONFIG_VIRTIO_CONSOLE',
]:
    cfg = set_opt(cfg, opt, 'y')

# Transparent huge pages: madvise only (embedded)
cfg = set_opt(cfg, 'CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS', 'n')
cfg = set_opt(cfg, 'CONFIG_TRANSPARENT_HUGEPAGE_MADVISE', 'y')

# Append ACM to LSM list
m = re.search(r'(CONFIG_LSM=")([^"]*?)(")', cfg)
if m and 'acm' not in m.group(2):
    cfg = re.sub(r'(CONFIG_LSM=")([^"]*?)(")', r'\1\2,acm\3', cfg)

open(path, 'w').write(cfg)
print('SCPA configuration applied.')
EOF

    step "Resolving configuration dependencies ..."
    make -C "$KSRC" ARCH=x86_64 olddefconfig 2>&1 | tail -2

    # Confirm all three modules are set
    for sym in CONFIG_SECURITY_ACM CONFIG_NETFILTER_RBPF CONFIG_MISC_MMOA; do
        grep -q "^${sym}=y" "$KSRC/.config" || warn "$sym not set — check config"
    done

    ok "Kernel configured."
fi

# =============================================================================
# STEP 6 — Compile kernel
# =============================================================================
banner "Step 6 — Compiling kernel (make -j$JOBS)"

if [[ -f "$BZIMAGE" ]]; then
    ok "bzImage already built: $(du -sh "$BZIMAGE" | cut -f1)"
else
    step "Compiling — this takes 15–40 minutes depending on hardware ..."
    make -C "$KSRC" ARCH=x86_64 -j"$JOBS" 2>&1 | \
        grep --line-buffered -E \
            "^  (CC|LD|AR|AS|LINK|BUILD|Kernel)|error:|warning:.*error" || true

    [[ -f "$BZIMAGE" ]] || die "Compilation failed — bzImage not produced. Check build output."

    # Confirm all three modules compiled
    for mod in "security/acm/acm_lsm.o" "net/netfilter/rbpf.o" "drivers/misc/mmoa.o"; do
        [[ -f "$KSRC/$mod" ]] && ok "Compiled: $mod" || warn "Missing: $mod"
    done

    ok "Kernel built: $(du -sh "$BZIMAGE" | cut -f1)"
fi

# =============================================================================
# STEP 7 — Build initramfs
# =============================================================================
banner "Step 7 — Building initramfs"

build_initramfs() {
    step "Setting up BusyBox root filesystem ..."
    mkdir -p "$INITRD"/{bin,sbin,etc,proc,sys,dev,tmp,root,lib,lib64}
    mkdir -p "$INITRD/lib/x86_64-linux-gnu"

    # Copy busybox
    local BB
    BB=$(command -v busybox) || die "busybox not found"
    cp "$BB" "$INITRD/bin/busybox"

    # Copy shared libraries needed by busybox
    local INTERP
    INTERP=$(ldd "$BB" 2>/dev/null | grep "ld-linux" | awk '{print $1}' | head -1)
    [[ -f "$INTERP" ]] && cp "$INTERP" "$INITRD/lib64/"

    for lib in $(ldd "$BB" 2>/dev/null | grep "=> /" | awk '{print $3}'); do
        [[ -f "$lib" ]] && cp "$lib" "$INITRD/lib/x86_64-linux-gnu/" 2>/dev/null || true
    done

    # Busybox applet symlinks
    for cmd in sh ash ls cat echo ps mount umount dmesg insmod rmmod lsmod \
               grep awk sed find mkdir rm cp mv ifconfig ip ping free df \
               uname sysctl mdev head tail wc tee tr cut sort uniq date \
               hostname vi more sleep chmod chown; do
        ln -sf /bin/busybox "$INITRD/bin/$cmd" 2>/dev/null || true
    done

    # Copy init script
    cp "$SCRIPT_DIR/linux-build/initramfs/init" "$INITRD/init"
    chmod +x "$INITRD/init"

    ok "Initramfs root filesystem ready."
}

pack_initramfs() {
    step "Packing initramfs.cpio.gz ..."
    (cd "$INITRD" && find . -print0 | cpio --null -ov --format=newc 2>/dev/null \
        | gzip -9 > "$CPIO")
    ok "Initramfs packed: $(du -sh "$CPIO" | cut -f1)"
}

if [[ -f "$CPIO" && "$CPIO" -nt "$INITRD/init" ]]; then
    ok "Initramfs already packed: $(du -sh "$CPIO" | cut -f1)"
else
    build_initramfs
    pack_initramfs
fi

# =============================================================================
# STEP 8 — Launch QEMU
# =============================================================================
banner "Step 8 — Launching SecureKernel in QEMU"

echo -e "  Kernel    : ${BOLD}$BZIMAGE${NC} ($(du -sh "$BZIMAGE" | cut -f1))"
echo -e "  Initramfs : ${BOLD}$CPIO${NC} ($(du -sh "$CPIO" | cut -f1))"
echo ""
echo -e "${YLW}  Press Ctrl-A then X to quit QEMU${NC}"
echo -e "${YLW}  At the shell, try:${NC}"
echo -e "    ${CYN}cat /proc/mmoa_stats${NC}"
echo -e "    ${CYN}cat /proc/rbpf_rules${NC}"
echo -e "    ${CYN}cat /proc/acm_policy${NC}"
echo -e "    ${CYN}dmesg | grep -E 'ACM|MMOA|RBPF'${NC}"
echo ""

exec "$QEMU_BIN" \
    -kernel "$BZIMAGE" \
    -initrd "$CPIO" \
    -append "console=ttyS0 loglevel=4 lsm=capability,yama,acm nokaslr" \
    -m 512M \
    -smp 2 \
    -nographic \
    -no-reboot \
    -device virtio-rng-pci \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0
