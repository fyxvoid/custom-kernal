# =============================================================================
# SecureKernel — Windows / WSL Installer
# =============================================================================
# Installs SecureKernel inside WSL (Ubuntu) and creates a desktop shortcut.
#
# Requirements:
#   - Windows 10 (build 19041+) or Windows 11
#   - The securekernel_1.0_amd64.deb must be in the same folder as this script
#     (run build_deb.sh on a Linux machine to produce it, then copy here)
#
# Run in PowerShell (no admin needed for WSL2; admin needed for WSL install):
#   powershell -ExecutionPolicy Bypass -File install_windows.ps1
#
# After install, run SecureKernel from PowerShell / CMD:
#   wsl securekernel --serial
# Or open the desktop shortcut "SecureKernel".
# =============================================================================

$ErrorActionPreference = "Stop"

$CYN  = [char]27 + "[36m"
$GRN  = [char]27 + "[32m"
$YLW  = [char]27 + "[33m"
$RED  = [char]27 + "[31m"
$BLD  = [char]27 + "[1m"
$NC   = [char]27 + "[0m"

function ok($msg)   { Write-Host "${GRN}[ OK ]${NC} $msg" }
function step($msg) { Write-Host "${CYN}[    ]${NC} $msg" }
function warn($msg) { Write-Host "${YLW}[WARN]${NC} $msg" }
function die($msg)  { Write-Host "${RED}[ERR ]${NC} $msg"; exit 1 }

Write-Host ""
Write-Host "${BLD}${CYN}============================================================${NC}"
Write-Host "${BLD}${CYN}  SecureKernel — Windows / WSL Installer${NC}"
Write-Host "${BLD}${CYN}  IT B TEAM 7 · Gnanamani College of Technology${NC}"
Write-Host "${BLD}${CYN}============================================================${NC}"
Write-Host ""

# ── Locate the .deb ──────────────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DebFile   = Get-ChildItem "$ScriptDir\securekernel_*.deb" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1

if (-not $DebFile) {
    die "No securekernel_*.deb found in $ScriptDir`nBuild it on Linux first: bash build_deb.sh"
}
ok "Package: $($DebFile.Name) ($([math]::Round($DebFile.Length/1MB, 1)) MB)"

# ── Check WSL is present ─────────────────────────────────────────────────────
step "Checking WSL ..."
$WslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $WslExe) {
    warn "WSL not found."
    Write-Host ""
    Write-Host "  Windows Subsystem for Linux is not installed."
    Write-Host "  Install it now by opening PowerShell as Administrator and running:"
    Write-Host ""
    Write-Host "    ${BLD}wsl --install -d Ubuntu${NC}"
    Write-Host ""
    Write-Host "  Then reboot and re-run this installer."
    exit 0
}
ok "wsl.exe found: $($WslExe.Source)"

# ── Check a Debian/Ubuntu distro is registered ───────────────────────────────
step "Checking for a Debian/Ubuntu WSL distro ..."
$Distros = wsl --list --quiet 2>$null | Where-Object { $_ -match '\S' }

$Target = $Distros | Where-Object { $_ -match 'Ubuntu|Debian|Kali' } | Select-Object -First 1
if (-not $Target) {
    warn "No Ubuntu/Debian/Kali WSL distro found."
    Write-Host ""
    Write-Host "  Install Ubuntu on WSL:"
    Write-Host "    ${BLD}wsl --install -d Ubuntu${NC}"
    Write-Host ""
    Write-Host "  Then reboot, complete the Ubuntu first-run setup, and re-run this installer."
    exit 0
}
$Target = $Target.Trim().TrimEnd([char]0)
ok "WSL distro: $Target"

# ── Convert Windows path to WSL path ─────────────────────────────────────────
step "Translating path for WSL ..."
$WslPath = (wsl -d $Target -- wslpath -u ($DebFile.FullName -replace '\\', '/')).Trim()
ok "WSL path: $WslPath"

# ── Install QEMU dependency then the .deb ────────────────────────────────────
step "Installing into WSL ($Target) ..."
Write-Host "  (sudo password may be required inside WSL)"
Write-Host ""

wsl -d $Target -- bash -c @"
set -e
echo '[*] Updating package lists ...'
sudo apt-get update -qq
echo '[*] Installing qemu-system-x86 ...'
sudo apt-get install -y qemu-system-x86 2>/dev/null || true
echo '[*] Installing SecureKernel package ...'
sudo dpkg -i '$WslPath'
"@

ok "SecureKernel installed inside WSL ($Target)."

# ── Desktop shortcut ─────────────────────────────────────────────────────────
step "Creating desktop shortcut ..."
try {
    $Desktop  = [Environment]::GetFolderPath("Desktop")
    $Shortcut = "$Desktop\SecureKernel.lnk"
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Link = $WScriptShell.CreateShortcut($Shortcut)
    $Link.TargetPath       = "wsl.exe"
    $Link.Arguments        = "-d $Target -- securekernel --serial"
    $Link.WorkingDirectory = $env:USERPROFILE
    $Link.Description      = "Boot SecureKernel (Linux 6.6 LTS hardened) in QEMU"
    $Link.IconLocation     = "C:\Windows\System32\shell32.dll,9"
    $Link.Save()
    ok "Desktop shortcut created: $Shortcut"
} catch {
    warn "Could not create shortcut (non-critical): $_"
}

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "${BLD}${GRN}============================================================${NC}"
Write-Host "${BLD}${GRN}  Installation complete!${NC}"
Write-Host "${BLD}${GRN}============================================================${NC}"
Write-Host ""
Write-Host "  Run from PowerShell / CMD:"
Write-Host ""
Write-Host "    ${BLD}wsl -d $Target -- securekernel --serial${NC}"
Write-Host ""
Write-Host "  Or open the ${BLD}SecureKernel${NC} desktop shortcut."
Write-Host ""
Write-Host "  Inside QEMU:"
Write-Host "    cat /proc/mmoa_stats      -- memory module"
Write-Host "    cat /proc/rbpf_rules      -- packet filter"
Write-Host "    cat /proc/acm_policy      -- access control"
Write-Host "    dmesg | grep -E 'ACM|MMOA|RBPF'"
Write-Host ""
Write-Host "  Press Ctrl-A then X to quit QEMU."
Write-Host ""
