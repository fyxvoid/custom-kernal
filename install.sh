#!/usr/bin/env bash
# =============================================================================
# SecureKernel — System Installer
# =============================================================================
# Installs the pre-built SecureKernel onto any Debian-based system and creates
# a 'securekernel' command available to all users.
#
# Supported platforms:
#   Native Linux   — Debian, Ubuntu, Kali, Mint, Pop!_OS, etc.
#   WSL1 / WSL2    — Ubuntu on Windows Subsystem for Linux
#
# Usage (from the cloned repo):
#   sudo bash install.sh           # install
#   sudo bash install.sh --remove  # uninstall
#
# After install, run:
#   securekernel              — graphical window (native) / serial (WSL)
#   securekernel --serial     — serial TTY always (Ctrl-A X to quit)
#   securekernel --graphical  — graphical always (needs display)
#   securekernel --help       — all options
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GRN}[ OK ]${NC} $*"; }
step() { echo -e "${BLU}[    ]${NC} $*"; }
warn() { echo -e "${YLW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERR ]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BZIMAGE="$SCRIPT_DIR/linux-build/linux-6.6.140/arch/x86/boot/bzImage"
CPIO="$SCRIPT_DIR/linux-build/initramfs.cpio.gz"
LAUNCHER_SRC="$SCRIPT_DIR/linux-build/launcher.sh"

INSTALL_DIR="/usr/share/securekernel"
BIN_LAUNCHER="/usr/bin/securekernel"

[[ $EUID -eq 0 ]] || die "Run as root:  sudo bash install.sh"

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--remove" || "${1:-}" == "uninstall" ]]; then
    echo -e "\n${BOLD}${CYN}  SecureKernel — Uninstalling${NC}\n"
    rm -rf "$INSTALL_DIR"  && ok "Removed $INSTALL_DIR"
    rm -f  "$BIN_LAUNCHER" && ok "Removed $BIN_LAUNCHER"
    echo ""
    ok "SecureKernel uninstalled."
    exit 0
fi

# ── Banner ────────────────────────────────────────────────────────────────────
# Detect environment for banner
IS_WSL=0
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1

echo ""
echo -e "${BOLD}${CYN}============================================================${NC}"
echo -e "${BOLD}${CYN}  SecureKernel — Linux 6.6 LTS Hardened Kernel Installer${NC}"
echo -e "${BOLD}${CYN}  IT B TEAM 7 · Gnanamani College of Technology${NC}"
echo -e "${BOLD}${CYN}============================================================${NC}"
if [[ $IS_WSL -eq 1 ]]; then
    echo -e "  ${YLW}Platform: Windows Subsystem for Linux (WSL)${NC}"
    echo -e "  ${YLW}QEMU will use serial mode by default (no KVM in WSL).${NC}"
fi
echo ""

# ── Distro check ─────────────────────────────────────────────────────────────
[[ -f /etc/os-release ]] || die "Cannot detect OS — /etc/os-release missing."
source /etc/os-release
case "${ID_LIKE:-$ID}" in
    *debian*|*ubuntu*) ok "System: ${PRETTY_NAME:-$ID}" ;;
    *)
        die "Requires Debian/Ubuntu/Kali/Mint/WSL-Ubuntu. Detected: ${PRETTY_NAME:-unknown}"
        ;;
esac

# ── Artefact check ────────────────────────────────────────────────────────────
step "Checking pre-built kernel artefacts ..."
[[ -f "$BZIMAGE" ]]      || die "bzImage not found at $BZIMAGE — run setup.sh first."
[[ -f "$CPIO" ]]         || die "initramfs.cpio.gz not found at $CPIO — run setup.sh first."
[[ -f "$LAUNCHER_SRC" ]] || die "launcher.sh not found at $LAUNCHER_SRC."
ok "bzImage      : $(du -sh "$BZIMAGE" | cut -f1)"
ok "initramfs    : $(du -sh "$CPIO"    | cut -f1)"

# ── Install QEMU ─────────────────────────────────────────────────────────────
step "Checking QEMU ..."
if ! command -v qemu-system-x86_64 &>/dev/null; then
    step "Installing qemu-system-x86 ..."
    apt-get update -qq
    apt-get install -y qemu-system-x86
fi
QEMU_BIN=$(command -v qemu-system-x86_64)
ok "QEMU: $($QEMU_BIN --version | head -1)"

# WSL: ensure current user can reach /dev/kvm if it exists
if [[ $IS_WSL -eq 1 && -e /dev/kvm ]]; then
    if ! groups | grep -qw kvm; then
        warn "Add yourself to the kvm group for KVM acceleration:"
        warn "  sudo usermod -aG kvm \$USER  (then re-open WSL)"
    fi
fi

# ── Install files ─────────────────────────────────────────────────────────────
step "Installing to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
install -m 644 "$BZIMAGE" "$INSTALL_DIR/bzImage"
install -m 644 "$CPIO"    "$INSTALL_DIR/initramfs.cpio.gz"
install -m 755 "$LAUNCHER_SRC" "$BIN_LAUNCHER"
ok "Files installed."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GRN}============================================================${NC}"
echo -e "${BOLD}${GRN}  Installation complete!${NC}"
echo -e "${BOLD}${GRN}============================================================${NC}"
echo ""
if [[ $IS_WSL -eq 1 ]]; then
    echo -e "  Run (serial mode, works in all WSL):  ${BOLD}securekernel --serial${NC}"
    echo -e "  Run (graphical, needs WSLg):          ${BOLD}securekernel${NC}"
    echo -e "  From PowerShell / CMD:                ${BOLD}wsl securekernel --serial${NC}"
else
    echo -e "  Run graphical window:  ${BOLD}securekernel${NC}"
    echo -e "  Run serial TTY:        ${BOLD}securekernel --serial${NC}"
fi
echo -e "  All options:           ${BOLD}securekernel --help${NC}"
echo -e "  Uninstall:             ${BOLD}sudo bash install.sh --remove${NC}"
echo ""
echo -e "  Inside QEMU try:"
echo -e "    ${CYN}cat /proc/mmoa_stats${NC}    ${CYN}cat /proc/rbpf_rules${NC}    ${CYN}cat /proc/acm_policy${NC}"
echo -e "    ${CYN}dmesg | grep -E 'ACM|MMOA|RBPF'${NC}"
echo ""
