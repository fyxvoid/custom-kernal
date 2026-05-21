#!/usr/bin/env bash
# =============================================================================
# SecureKernel — Linux Mint (and Ubuntu-based) Installer
# =============================================================================
#
# One-shot script that installs ALL build dependencies, compiles the
# Linux 6.6.140 LTS kernel with SecureKernel modules, builds a minimal
# initramfs, and boots the result inside QEMU.
#
# Tested on:
#   Linux Mint 21.x / 22.x (Ubuntu 22.04 / 24.04 base)
#   Ubuntu 22.04 LTS, 24.04 LTS
#   Pop!_OS 22.04
#
# Usage:
#   chmod +x install_mint.sh
#   ./install_mint.sh
#
# To skip the QEMU boot and just build:
#   NO_QEMU=1 ./install_mint.sh
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

banner "SecureKernel — Linux Mint Installer (Linux 6.6.140 LTS)"
echo -e "  Script dir : ${BOLD}$SCRIPT_DIR${NC}"
echo -e "  Build dir  : ${BOLD}$BUILD_DIR${NC}"
echo -e "  CPU cores  : ${BOLD}$JOBS${NC}"
echo ""

# =============================================================================
# STEP 1 — Detect distro (Linux Mint compatible)
# =============================================================================
banner "Step 1 — Detecting distribution"

[[ -f /etc/os-release ]] || die "Cannot detect OS — /etc/os-release not found."
source /etc/os-release

# Linux Mint sets ID=linuxmint and ID_LIKE=ubuntu — handle both
DISTRO_OK=0
[[ "${ID:-}"      =~ ^(debian|ubuntu|linuxmint|pop|elementary|zorin|kali)$ ]] && DISTRO_OK=1
[[ "${ID_LIKE:-}" =~ (debian|ubuntu) ]]                                        && DISTRO_OK=1

[[ $DISTRO_OK -eq 1 ]] || \
    die "Unsupported OS: ${PRETTY_NAME:-unknown}. This script targets Debian/Ubuntu/Mint."

ok "Detected: ${PRETTY_NAME:-$ID}"

# Ubuntu/Mint version for package name differences
UBUNTU_VER="0"
if [[ -n "${UBUNTU_CODENAME:-}" ]]; then
    UBUNTU_VER="${UBUNTU_CODENAME}"
fi

# =============================================================================
# STEP 2 — Install ALL build dependencies
# =============================================================================
banner "Step 2 — Installing build dependencies"

# Comprehensive list — covers Mint 21/22 (Ubuntu 22.04/24.04 base)
DEPS=(
    # Core toolchain
    build-essential gcc g++ make binutils
    # Kernel build requirements
    bc bison flex
    libssl-dev libelf-dev
    libncurses-dev libncurses5-dev
    # GCC plugins (required by newer kernels)
    libgmp-dev libmpc-dev libmpfr-dev
    # Compression libraries
    zlib1g-dev libzstd-dev
    liblz4-tool lz4
    # Pahole / BTF (dwarves provides pahole)
    dwarves
    # Archive & download tools
    cpio gzip xz-utils tar wget curl
    # Kernel signing / certs (needed even when disabled, for headers)
    openssl
    # Build system helpers
    pkg-config rsync
    # Python (used by kernel scripts)
    python3
    # File utilities
    file kmod
    # QEMU
    qemu-system-x86
    # BusyBox for initramfs
    busybox-static
)

# apt-get may not know busybox-static on some versions; fallback to busybox
MISSING=()
for pkg in "${DEPS[@]}"; do
    dpkg -s "$pkg" &>/dev/null 2>&1 || MISSING+=("$pkg")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    ok "All dependencies already installed."
else
    step "Updating package lists ..."
    if [[ $EUID -ne 0 ]]; then
        sudo apt-get update -qq
    else
        apt-get update -qq
    fi

    step "Installing ${#MISSING[@]} package(s): ${MISSING[*]}"
    FAILED_PKGS=()
    for pkg in "${MISSING[@]}"; do
        if [[ $EUID -ne 0 ]]; then
            sudo apt-get install -y "$pkg" 2>/dev/null || FAILED_PKGS+=("$pkg")
        else
            apt-get install -y "$pkg" 2>/dev/null || FAILED_PKGS+=("$pkg")
        fi
    done

    if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
        warn "Could not install (may not exist on this release): ${FAILED_PKGS[*]}"
        # Try alternatives
        for pkg in "${FAILED_PKGS[@]}"; do
            case "$pkg" in
                busybox-static)
                    step "Trying 'busybox' as fallback ..."
                    if [[ $EUID -ne 0 ]]; then sudo apt-get install -y busybox 2>/dev/null || true
                    else apt-get install -y busybox 2>/dev/null || true; fi
                    ;;
                libncurses-dev)
                    step "Trying 'libncurses5-dev' ..."
                    if [[ $EUID -ne 0 ]]; then sudo apt-get install -y libncurses5-dev 2>/dev/null || true
                    else apt-get install -y libncurses5-dev 2>/dev/null || true; fi
                    ;;
                liblz4-tool)
                    step "Trying 'lz4' ..."
                    if [[ $EUID -ne 0 ]]; then sudo apt-get install -y lz4 2>/dev/null || true
                    else apt-get install -y lz4 2>/dev/null || true; fi
                    ;;
            esac
        done
    fi
    ok "Dependencies installed."
fi

# Locate busybox (static preferred)
BUSYBOX_BIN=""
for b in /usr/bin/busybox /bin/busybox /usr/lib/busybox/busybox-x86_64; do
    [[ -x "$b" ]] && { BUSYBOX_BIN="$b"; break; }
done
[[ -n "$BUSYBOX_BIN" ]] || die "busybox not found after installation. Try: sudo apt-get install busybox-static"
ok "BusyBox: $BUSYBOX_BIN"

# Verify QEMU
QEMU_BIN=$(command -v qemu-system-x86_64 2>/dev/null) || \
    die "qemu-system-x86_64 not found. Try: sudo apt-get install qemu-system-x86"
ok "QEMU: $QEMU_BIN ($($QEMU_BIN --version | head -1))"

# Verify pahole (needed for CONFIG_DEBUG_INFO_BTF even when disabled)
PAHOLE_BIN=$(command -v pahole 2>/dev/null || true)
if [[ -z "$PAHOLE_BIN" ]]; then
    warn "pahole not found — CONFIG_DEBUG_INFO_BTF will be forcibly disabled."
else
    ok "pahole: $PAHOLE_BIN ($(pahole --version 2>&1 | head -1))"
fi

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
        wget -q --show-progress "$KURL" -O "$KTARBALL" || \
            curl -L --progress-bar "$KURL" -o "$KTARBALL"
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

    if ! grep -q "security/acm/Kconfig" "$KSRC/security/Kconfig"; then
        sed -i 's|source "security/Kconfig.hardening"|source "security/acm/Kconfig"\nsource "security/Kconfig.hardening"|' \
            "$KSRC/security/Kconfig"
    fi

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
# STEP 5 — Configure kernel (SCPA + Mint-safe settings)
# =============================================================================
banner "Step 5 — Kernel configuration (SCPA)"

if [[ -f "$KSRC/.config" ]] && grep -q "CONFIG_SECURITY_ACM=y" "$KSRC/.config"; then
    ok "Kernel already configured — skipping."
else
    step "Generating x86_64 defconfig ..."
    make -C "$KSRC" ARCH=x86_64 x86_64_defconfig 2>&1 | tail -3

    step "Applying SCPA pruning, SecureKernel settings, and Mint-safe fixes ..."
    python3 - "$KSRC/.config" << 'PYEOF'
import sys, re

path = sys.argv[1]
cfg  = open(path).read()

def set_opt(cfg, opt, val):
    """Set a kernel config option, handling all three states."""
    p_set     = rf'^{re.escape(opt)}=.*$'
    p_not_set = rf'^# {re.escape(opt)} is not set$'
    p_tristate_not = rf'^# {re.escape(opt)} is not set'
    line = f'{opt}={val}'
    if re.search(p_set, cfg, re.MULTILINE):
        return re.sub(p_set, line, cfg, flags=re.MULTILINE)
    if re.search(p_not_set, cfg, re.MULTILINE):
        return re.sub(p_not_set, line, cfg, flags=re.MULTILINE)
    # Not present at all — append
    return cfg + f'\n{line}\n'

# ── MINT/UBUNTU FIX: clear trusted key paths ────────────────────────────────
# Ubuntu/Mint defconfig sets these to system cert files which break the build
# when building outside the distro's own build environment.
cfg = set_opt(cfg, 'CONFIG_SYSTEM_TRUSTED_KEYS',      '""')
cfg = set_opt(cfg, 'CONFIG_SYSTEM_REVOCATION_KEYS',   '""')
cfg = set_opt(cfg, 'CONFIG_MODULE_SIG_KEY',           '"certs/signing_key.pem"')

# ── SCPA: disable debug/trace/unused ────────────────────────────────────────
for opt in [
    'CONFIG_DEBUG_INFO_BTF', 'CONFIG_DEBUG_INFO_BTF_MODULES',
    'CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT',
    'CONFIG_DEBUG_INFO_DWARF4', 'CONFIG_DEBUG_INFO_DWARF5',
    'CONFIG_DEBUG_INFO', 'CONFIG_DEBUG_INFO_REDUCED',
    'CONFIG_KASAN', 'CONFIG_UBSAN', 'CONFIG_KCSAN',
    'CONFIG_LOCKDEP', 'CONFIG_PROVE_LOCKING',
    'CONFIG_SLUB_DEBUG', 'CONFIG_PAGE_POISONING', 'CONFIG_KMEMLEAK',
    'CONFIG_FTRACE', 'CONFIG_FUNCTION_TRACER', 'CONFIG_KPROBES',
    'CONFIG_BT', 'CONFIG_SOUND', 'CONFIG_HAMRADIO',
    'CONFIG_ATM', 'CONFIG_IPX', 'CONFIG_APPLETALK',
    'CONFIG_PCMCIA', 'CONFIG_FIREWIRE', 'CONFIG_INFINIBAND',
    # Disable module signing (avoids cert dependency issues)
    'CONFIG_MODULE_SIG', 'CONFIG_MODULE_SIG_FORCE',
    'CONFIG_MODULE_SIG_ALL',
    # Disable IMA/EVM (cert-dependent)
    'CONFIG_IMA', 'CONFIG_EVM',
]:
    cfg = set_opt(cfg, opt, 'n')

# ── SCPA: HZ=250 (fewer timer interrupts — embedded profile) ────────────────
cfg = set_opt(cfg, 'CONFIG_HZ_1000', 'n')
cfg = set_opt(cfg, 'CONFIG_HZ_250',  'y')
cfg = set_opt(cfg, 'CONFIG_HZ',      '250')

# ── SecureKernel modules ────────────────────────────────────────────────────
cfg = set_opt(cfg, 'CONFIG_SECURITY_ACM',   'y')
cfg = set_opt(cfg, 'CONFIG_NETFILTER_RBPF', 'y')
cfg = set_opt(cfg, 'CONFIG_MISC_MMOA',      'y')

# ── Security hardening + network built-in ───────────────────────────────────
for opt in [
    'CONFIG_HARDENED_USERCOPY', 'CONFIG_FORTIFY_SOURCE',
    'CONFIG_STACKPROTECTOR_STRONG', 'CONFIG_RANDOMIZE_BASE',
    'CONFIG_RANDOMIZE_MEMORY', 'CONFIG_STRICT_KERNEL_RWX',
    'CONFIG_STRICT_MODULE_RWX', 'CONFIG_PAGE_TABLE_ISOLATION',
    'CONFIG_RETPOLINE', 'CONFIG_VMAP_STACK', 'CONFIG_STRICT_DEVMEM',
    'CONFIG_SLAB_FREELIST_RANDOM', 'CONFIG_SLAB_FREELIST_HARDENED',
    'CONFIG_SHUFFLE_PAGE_ALLOCATOR', 'CONFIG_INIT_ON_ALLOC_DEFAULT_ON',
    'CONFIG_SECURITY_YAMA', 'CONFIG_VIRTIO_CONSOLE',
    # Network: built-in so initramfs can use without modprobe
    'CONFIG_VIRTIO_NET', 'CONFIG_NET', 'CONFIG_INET',
    'CONFIG_IP_PNP', 'CONFIG_PACKET', 'CONFIG_UNIX',
    'CONFIG_NETFILTER', 'CONFIG_NF_CONNTRACK',
]:
    cfg = set_opt(cfg, opt, 'y')

# ── THP: madvise only (embedded profile) ────────────────────────────────────
cfg = set_opt(cfg, 'CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS',  'n')
cfg = set_opt(cfg, 'CONFIG_TRANSPARENT_HUGEPAGE_MADVISE', 'y')

# ── Append ACM to LSM list ──────────────────────────────────────────────────
m = re.search(r'(CONFIG_LSM=")([^"]*?)(")', cfg)
if m and 'acm' not in m.group(2):
    cfg = re.sub(r'(CONFIG_LSM=")([^"]*?)(")', r'\1\2,acm\3', cfg)

open(path, 'w').write(cfg)
print('SCPA + Mint-safe configuration applied.')
PYEOF

    step "Resolving configuration dependencies (olddefconfig) ..."
    make -C "$KSRC" ARCH=x86_64 olddefconfig 2>&1 | tail -3

    # Verify modules are set
    for sym in CONFIG_SECURITY_ACM CONFIG_NETFILTER_RBPF CONFIG_MISC_MMOA; do
        if grep -q "^${sym}=y" "$KSRC/.config"; then
            ok "$sym=y"
        else
            warn "$sym not set — check $KSRC/.config"
        fi
    done

    # Verify Mint-safe settings applied
    for sym in CONFIG_SYSTEM_TRUSTED_KEYS CONFIG_SYSTEM_REVOCATION_KEYS; do
        val=$(grep "^${sym}=" "$KSRC/.config" 2>/dev/null || echo "NOT FOUND")
        ok "  $sym = $val"
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
    echo -e "  ${YLW}Watch for errors below. Full log → $BUILD_DIR/build.log${NC}"
    echo ""

    # Run make, tee full output to log, and show filtered progress
    set +e
    make -C "$KSRC" ARCH=x86_64 -j"$JOBS" 2>&1 | tee "$BUILD_DIR/build.log" | \
        grep --line-buffered -E \
            "^  (CC|LD|AR|AS|LINK|BUILD|Kernel)|[Ee]rror:|[Ff]atal:|warning:.*error" || true
    MAKE_EXIT=${PIPESTATUS[0]}
    set -e

    if [[ $MAKE_EXIT -ne 0 ]]; then
        echo ""
        echo -e "${RED}============================================================${NC}"
        echo -e "${RED}  Compilation FAILED (exit $MAKE_EXIT)${NC}"
        echo -e "${RED}============================================================${NC}"
        echo ""
        echo -e "  Last 40 lines of build log:"
        tail -40 "$BUILD_DIR/build.log"
        echo ""
        die "Fix the errors above and re-run. Full log: $BUILD_DIR/build.log"
    fi

    [[ -f "$BZIMAGE" ]] || die "make succeeded but bzImage not found. Check $BUILD_DIR/build.log"

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

    # Copy busybox (static binary preferred — no library deps)
    cp "$BUSYBOX_BIN" "$INITRD/bin/busybox"
    chmod +x "$INITRD/bin/busybox"

    # Only copy shared libs if not a static binary
    if ldd "$BUSYBOX_BIN" 2>&1 | grep -q "not a dynamic executable"; then
        ok "BusyBox is statically linked — no library copy needed."
    else
        local INTERP
        INTERP=$(ldd "$BUSYBOX_BIN" 2>/dev/null | grep "ld-linux" | awk '{print $1}' | head -1 || true)
        [[ -n "$INTERP" && -f "$INTERP" ]] && cp "$INTERP" "$INITRD/lib64/" || true
        for lib in $(ldd "$BUSYBOX_BIN" 2>/dev/null | grep "=> /" | awk '{print $3}'); do
            [[ -f "$lib" ]] && cp "$lib" "$INITRD/lib/x86_64-linux-gnu/" 2>/dev/null || true
        done
    fi

    # Busybox applet symlinks
    for cmd in sh ash ls cat echo ps mount umount dmesg insmod rmmod lsmod \
               grep awk sed find mkdir rm cp mv ifconfig ip ping ping6 free df \
               uname sysctl mdev head tail wc tee tr cut sort uniq date \
               hostname vi more sleep chmod chown \
               nc netstat route wget httpget nslookup \
               traceroute arp; do
        ln -sf /bin/busybox "$INITRD/bin/$cmd" 2>/dev/null || true
    done

    # Copy init script
    if [[ -f "$SCRIPT_DIR/linux-build/initramfs/init" ]]; then
        cp "$SCRIPT_DIR/linux-build/initramfs/init" "$INITRD/init"
    else
        # Fallback init script
        cat > "$INITRD/init" << 'INITEOF'
#!/bin/sh
mount -t proc     none /proc
mount -t sysfs    none /sys
mount -t devtmpfs none /dev 2>/dev/null || mdev -s

echo ""
echo "============================================"
echo "  SecureKernel — Linux 6.6.140 LTS"
echo "  IT B TEAM 7 | Gnanamani College of Tech"
echo "============================================"
echo ""
echo "SecureKernel modules:"
dmesg 2>/dev/null | grep -E "ACM|MMOA|RBPF" || echo "  (check dmesg)"
echo ""
echo "Try: cat /proc/mmoa_stats"
echo "     cat /proc/rbpf_rules"
echo "     cat /proc/acm_policy"
echo "     dmesg | grep -E 'ACM|MMOA|RBPF'"
echo ""
exec /bin/sh
INITEOF
    fi
    chmod +x "$INITRD/init"

    ok "Initramfs root filesystem ready."
}

pack_initramfs() {
    step "Packing initramfs.cpio.gz ..."
    (cd "$INITRD" && find . -print0 | cpio --null -ov --format=newc 2>/dev/null \
        | gzip -9 > "$CPIO")
    ok "Initramfs packed: $(du -sh "$CPIO" | cut -f1)"
}

if [[ -f "$CPIO" && -f "$INITRD/init" && "$CPIO" -nt "$INITRD/init" ]]; then
    ok "Initramfs already packed: $(du -sh "$CPIO" | cut -f1)"
else
    build_initramfs
    pack_initramfs
fi

# =============================================================================
# Done — print summary or launch QEMU
# =============================================================================
banner "Build Complete!"

echo -e "  Kernel    : ${BOLD}$BZIMAGE${NC} ($(du -sh "$BZIMAGE" | cut -f1))"
echo -e "  Initramfs : ${BOLD}$CPIO${NC} ($(du -sh "$CPIO" | cut -f1))"
echo ""

if [[ "${NO_QEMU:-0}" == "1" ]]; then
    ok "NO_QEMU=1 — skipping QEMU launch."
    echo ""
    echo -e "  To boot manually:"
    echo -e "    ${BOLD}$QEMU_BIN \\${NC}"
    echo -e "      ${BOLD}-kernel $BZIMAGE \\${NC}"
    echo -e "      ${BOLD}-initrd $CPIO \\${NC}"
    echo -e "      ${BOLD}-append \"console=ttyS0 loglevel=4 lsm=capability,yama,acm nokaslr\" \\${NC}"
    echo -e "      ${BOLD}-m 512M -smp 2 -nographic -no-reboot${NC}"
    echo ""
    echo -e "  To install system-wide:"
    echo -e "    ${BOLD}sudo bash $SCRIPT_DIR/install.sh${NC}"
    exit 0
fi

# =============================================================================
# STEP 8 — Launch QEMU
# =============================================================================
banner "Step 8 — Launching SecureKernel in QEMU"

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
