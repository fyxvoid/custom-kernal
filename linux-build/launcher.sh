#!/usr/bin/env bash
# SecureKernel launcher
# Works on: native Linux, Ubuntu, Kali, WSL1, WSL2 (with or without WSLg)

SHARE=/usr/share/securekernel
BZIMAGE=$SHARE/bzImage
CPIO=$SHARE/initramfs.cpio.gz

[[ -f "$BZIMAGE" ]] || { echo "ERROR: $BZIMAGE not found. Re-install the package."; exit 1; }
[[ -f "$CPIO"    ]] || { echo "ERROR: $CPIO not found. Re-install the package."; exit 1; }

QEMU=$(command -v qemu-system-x86_64 2>/dev/null) || {
    echo "ERROR: qemu-system-x86_64 not found."
    echo "Fix:   sudo apt-get install qemu-system-x86"
    exit 1
}

# ── Environment detection ─────────────────────────────────────────────────────
IS_WSL=0
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1

HAS_KVM=0
[[ -w /dev/kvm ]] && HAS_KVM=1

HAS_DISPLAY=0
[[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] && HAS_DISPLAY=1

# ── Argument parsing ──────────────────────────────────────────────────────────
FORCE_SERIAL=0
FORCE_GRAPHICAL=0
MEM=512M
SMP=2

for arg in "$@"; do
    case "$arg" in
        --serial|-s)      FORCE_SERIAL=1 ;;
        --graphical|-g)   FORCE_GRAPHICAL=1 ;;
        --mem=*)          MEM="${arg#--mem=}" ;;
        --smp=*)          SMP="${arg#--smp=}" ;;
        --help|-h)
            echo "Usage: securekernel [OPTIONS]"
            echo ""
            echo "  (default)      Graphical GTK window on native Linux / WSLg"
            echo "                 Serial TTY in WSL without display"
            echo "  --serial  -s   Force serial TTY mode       (Ctrl-A X to quit)"
            echo "  --graphical -g Force graphical GTK window"
            echo "  --mem=SIZE     Guest RAM                   (default: 512M)"
            echo "  --smp=N        vCPU count                  (default: 2)"
            echo ""
            echo "Environment auto-detected at launch:"
            echo "  WSL:     $IS_WSL   |  KVM: $HAS_KVM   |  Display: $HAS_DISPLAY"
            exit 0 ;;
        *)
            echo "Unknown option: $arg  (try --help)"
            exit 1 ;;
    esac
done

# ── Serial vs graphical mode ──────────────────────────────────────────────────
USE_SERIAL=0
if   [[ $FORCE_SERIAL    -eq 1 ]]; then USE_SERIAL=1
elif [[ $FORCE_GRAPHICAL -eq 1 ]]; then USE_SERIAL=0
elif [[ $IS_WSL -eq 1 && $HAS_DISPLAY -eq 0 ]]; then USE_SERIAL=1
fi

if [[ $USE_SERIAL -eq 1 ]]; then
    DISPLAY_OPTS="-nographic"
    CONSOLE="console=ttyS0 earlyprintk=serial,ttyS0,115200"
    echo "[*] SecureKernel booting in serial mode ... (Ctrl-A X to quit)"
else
    DISPLAY_OPTS="-display gtk -vga std"
    CONSOLE="console=tty0"
    echo "[*] SecureKernel booting in graphical mode ..."
fi

# ── Acceleration ──────────────────────────────────────────────────────────────
if [[ $HAS_KVM -eq 1 ]]; then
    ACCEL="-enable-kvm -cpu host"
    echo "[*] KVM acceleration enabled."
else
    ACCEL="-accel tcg -cpu qemu64"
    if [[ $IS_WSL -eq 1 ]]; then
        echo "[*] WSL detected — KVM not available, using TCG (software emulation)."
        echo "    Tip: enable KVM in WSL2 for faster boot."
        echo "    See: https://learn.microsoft.com/en-us/windows/wsl/wsl-config"
    else
        echo "[*] KVM not available — using TCG (slower). Check /dev/kvm permissions."
    fi
fi

# ── Launch ────────────────────────────────────────────────────────────────────
exec "$QEMU" \
    -kernel "$BZIMAGE" \
    -initrd "$CPIO" \
    -append "$CONSOLE loglevel=4 lsm=capability,yama,acm nokaslr" \
    -m "$MEM" \
    -smp "$SMP" \
    $ACCEL \
    $DISPLAY_OPTS \
    -no-reboot \
    -device virtio-rng-pci \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0
