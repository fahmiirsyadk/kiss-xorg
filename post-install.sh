#!/bin/bash
set -e

log()  { printf '\033[32m->\033[m %s\n' "$*"; }
ok()   { printf '\033[32mOK\033[m  %s\n' "$*"; }
warn() { printf '\033[33m!>\033[m %s\n' "$*"; }
err()  { printf '\033[31mERR\033[m %s\n' "$*"; exit 1; }

[ "$(whoami)" = "xo" ] || err "Run this script as user xo, not root"

log "=== Connect to WiFi (nmtui) ==="
nmtui
ok "WiFi configured"

log "=== Install yay (AUR helper) ==="
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd /tmp
rm -rf yay
ok "yay installed"

log "=== Install AUR packages (sowm, st) ==="
yay -S --noconfirm sowm st
ok "sowm and st installed"

log "=== Install additional packages ==="
sudo pacman -S --noconfirm firefox
ok "Firefox installed"

echo ""
echo "============================================"
ok "Post-install complete!"
echo ""
echo "  Your system is ready:"
echo "  - Window manager: sowm"
echo "  - Terminal: st"
echo "  - Browser: firefox"
echo "  - X auto-starts on tty1"
echo ""
echo "  Reboot or logout/login to start X"
echo "============================================"
