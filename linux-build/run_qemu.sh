#!/usr/bin/env bash
# Boot SecureKernel in QEMU with a serial TTY
#
# Usage: ./run_qemu.sh
# Press Ctrl-A X to exit QEMU

set -euo pipefail

BUILDDIR="$(dirname "$0")"
KSRC="$BUILDDIR/linux-6.6.140"
INITRD="$BUILDDIR/initramfs"
BZIMAGE="$KSRC/arch/x86/boot/bzImage"
CPIO="$BUILDDIR/initramfs.cpio.gz"

# ── Build initramfs cpio if not current ───────────────────────────────────────
if [[ ! -f "$CPIO" ]] || [[ "$INITRD/init" -nt "$CPIO" ]]; then
    echo "[*] Packing initramfs ..."
    (cd "$INITRD" && find . -print0 | cpio --null -ov --format=newc 2>/dev/null \
        | gzip -9 > "$CPIO")
    echo "[*] initramfs.cpio.gz: $(du -sh "$CPIO" | cut -f1)"
fi

# ── Check kernel image ────────────────────────────────────────────────────────
[[ -f "$BZIMAGE" ]] || { echo "ERROR: $BZIMAGE not found. Run 'make -j8' first."; exit 1; }
echo "[*] Kernel:    $BZIMAGE ($(du -sh "$BZIMAGE" | cut -f1))"
echo "[*] Initramfs: $CPIO ($(du -sh "$CPIO" | cut -f1))"

# ── Launch QEMU ───────────────────────────────────────────────────────────────
echo ""
echo "[*] Booting SecureKernel ... (Ctrl-A X to quit)"
echo ""

qemu-system-x86_64 \
    -kernel "$BZIMAGE" \
    -initrd "$CPIO" \
    -append "console=ttyS0 earlyprintk=serial,ttyS0,115200 loglevel=4 lsm=capability,yama,acm nokaslr" \
    -m 512M \
    -smp 2 \
    -nographic \
    -no-reboot \
    -device virtio-rng-pci \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0
