#!/usr/bin/env bash
# =============================================================================
# SecureKernel — Debian Package Builder
# =============================================================================
# Creates a distributable .deb that installs on any Debian/Ubuntu/Kali/WSL.
#
# Usage:
#   bash build_deb.sh
#
# Output:
#   securekernel_1.0_amd64.deb   (in project root, ~13 MB)
#
# Distribute:
#   USB stick / GitHub Release / any file host — recipients install with:
#     sudo dpkg -i securekernel_1.0_amd64.deb
#   Then run:
#     securekernel             # graphical (native) or serial (WSL)
#     securekernel --serial    # serial TTY always
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; BLU='\033[0;34m'
CYN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GRN}[ OK ]${NC} $*"; }
step() { echo -e "${BLU}[    ]${NC} $*"; }
die()  { echo -e "${RED}[ERR ]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BZIMAGE="$SCRIPT_DIR/linux-build/linux-6.6.140/arch/x86/boot/bzImage"
CPIO="$SCRIPT_DIR/linux-build/initramfs.cpio.gz"
LAUNCHER_SRC="$SCRIPT_DIR/linux-build/launcher.sh"

VERSION="1.0"
ARCH="amd64"
PKG_NAME="securekernel_${VERSION}_${ARCH}"
PKG_DIR="$SCRIPT_DIR/$PKG_NAME"
OUT_DEB="$SCRIPT_DIR/securekernel_${VERSION}_${ARCH}.deb"

echo ""
echo -e "${BOLD}${CYN}============================================================${NC}"
echo -e "${BOLD}${CYN}  SecureKernel — Building .deb package v${VERSION}${NC}"
echo -e "${BOLD}${CYN}============================================================${NC}"
echo ""

# ── Verify artefacts ─────────────────────────────────────────────────────────
step "Checking pre-built kernel artefacts ..."
[[ -f "$BZIMAGE" ]]      || die "bzImage not found at $BZIMAGE — run setup.sh first."
[[ -f "$CPIO" ]]         || die "initramfs.cpio.gz not found at $CPIO — run setup.sh first."
[[ -f "$LAUNCHER_SRC" ]] || die "launcher.sh not found at $LAUNCHER_SRC."
ok "bzImage   : $(du -sh "$BZIMAGE" | cut -f1)"
ok "initramfs : $(du -sh "$CPIO"    | cut -f1)"

command -v dpkg-deb &>/dev/null || die "dpkg-deb not found. Install: sudo apt-get install dpkg"

# ── Package tree ──────────────────────────────────────────────────────────────
step "Creating package structure ..."
rm -rf "$PKG_DIR"
install -d "$PKG_DIR/DEBIAN"
install -d "$PKG_DIR/usr/bin"
install -d "$PKG_DIR/usr/share/securekernel"
install -d "$PKG_DIR/usr/share/doc/securekernel"

# ── Payload ───────────────────────────────────────────────────────────────────
step "Copying artefacts ..."
install -m 644 "$BZIMAGE"      "$PKG_DIR/usr/share/securekernel/bzImage"
install -m 644 "$CPIO"         "$PKG_DIR/usr/share/securekernel/initramfs.cpio.gz"
install -m 755 "$LAUNCHER_SRC" "$PKG_DIR/usr/bin/securekernel"
ok "Artefacts and launcher copied."

# ── Docs ──────────────────────────────────────────────────────────────────────
cat > "$PKG_DIR/usr/share/doc/securekernel/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Source: SecureKernel — IT B TEAM 7, Gnanamani College of Technology
License: GPL-2.0

All SecureKernel module source files are released under the
GNU General Public License v2.0, consistent with the Linux kernel licence.
EOF
gzip -9 -c /dev/null > "$PKG_DIR/usr/share/doc/securekernel/changelog.Debian.gz"

# ── DEBIAN/control ────────────────────────────────────────────────────────────
INSTALLED_KB=$(du -sk "$PKG_DIR/usr" | cut -f1)

step "Writing DEBIAN/control ..."
cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: securekernel
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: IT B TEAM 7 <team7@gctn.ac.in>
Depends: qemu-system-x86
Installed-Size: ${INSTALLED_KB}
Section: misc
Priority: optional
Description: SecureKernel — Linux 6.6 LTS hardened kernel (QEMU demo)
 A custom-built Linux 6.6 LTS kernel with four security and performance
 modules compiled in: SCPA (kernel lightening), MMOA (memory optimisation),
 RBPF (packet filtering), and ACM (mandatory access control LSM).
 .
 Platforms: native Linux, Ubuntu, Kali, WSL1, WSL2.
 Run with: securekernel  (graphical or serial, auto-detected)
 .
 IT B TEAM 7 · Gnanamani College of Technology, Namakkal.
EOF
ok "control written."

# ── DEBIAN/postinst ───────────────────────────────────────────────────────────
cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

IS_WSL=0
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1

echo ""
echo "  SecureKernel installed successfully!"
echo ""
if [ "$IS_WSL" = "1" ]; then
    echo "  You are inside WSL."
    echo "  Run:  securekernel --serial"
    echo "        wsl securekernel --serial    (from PowerShell/CMD)"
else
    echo "  Run:  securekernel              (graphical window)"
    echo "        securekernel --serial     (serial TTY)"
fi
echo "        securekernel --help        (all options)"
echo ""
EOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# ── DEBIAN/prerm ──────────────────────────────────────────────────────────────
cat > "$PKG_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e
echo "  Removing SecureKernel ..."
EOF
chmod 755 "$PKG_DIR/DEBIAN/prerm"

# ── md5sums ───────────────────────────────────────────────────────────────────
step "Computing md5sums ..."
(cd "$PKG_DIR" && find usr -type f | sort | xargs md5sum > DEBIAN/md5sums)
ok "md5sums written."

# ── Build .deb ────────────────────────────────────────────────────────────────
step "Building $OUT_DEB ..."
dpkg-deb --build --root-owner-group "$PKG_DIR" "$OUT_DEB"
rm -rf "$PKG_DIR"

DEB_SIZE=$(du -sh "$OUT_DEB" | cut -f1)
ok ".deb built: $(basename "$OUT_DEB") ($DEB_SIZE)"

echo ""
echo -e "${BOLD}${GRN}============================================================${NC}"
echo -e "${BOLD}${GRN}  Package ready: securekernel_${VERSION}_${ARCH}.deb  (${DEB_SIZE})${NC}"
echo -e "${BOLD}${GRN}============================================================${NC}"
echo ""
echo -e "  On any Debian / Ubuntu / Kali (native or WSL):"
echo -e "    ${BOLD}sudo dpkg -i securekernel_${VERSION}_${ARCH}.deb${NC}"
echo ""
echo -e "  On Windows — use the PowerShell installer:"
echo -e "    ${BOLD}powershell -ExecutionPolicy Bypass -File install_windows.ps1${NC}"
echo ""
echo -e "  After install:"
echo -e "    ${BOLD}securekernel${NC}             — graphical (native) / serial (WSL, auto)"
echo -e "    ${BOLD}securekernel --serial${NC}    — serial TTY always"
echo -e "    ${BOLD}securekernel --help${NC}"
echo ""
