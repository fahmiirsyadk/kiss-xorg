#!/bin/bash
set -e

log()  { printf '\033[32m->\033[m %s\n' "$*"; }
ok()   { printf '\033[32mOK\033[m  %s\n' "$*"; }
warn() { printf '\033[33m!>\033[m %s\n' "$*"; }

log "=== Enable NetworkManager (for after reboot) ==="
ln -sf /usr/lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service /etc/systemd/system/network-online.target.wants/
ok "NetworkManager will start on boot"

log "=== Install Go (required for yay) ==="
pacman -S --noconfirm --needed go
ok "Go installed"

log "=== Install yay (AUR helper) ==="
su - xo -c '
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -s --noconfirm
'
pacman -U --noconfirm /tmp/yay/yay-*.pkg.tar.zst
rm -rf /tmp/yay
ok "yay installed"

log "=== Install AUR packages (sowm, st) ==="
for pkg in sowm st; do
    log "Building $pkg..."
    su - xo -c "cd /tmp && git clone https://aur.archlinux.org/$pkg.git && cd $pkg && makepkg -s --noconfirm"
    pacman -U --noconfirm /tmp/$pkg/$pkg-*.pkg.tar.zst
    rm -rf /tmp/$pkg
    ok "$pkg installed"
done

log "=== Configure X session ==="
cat > /home/xo/.xinitrc << 'XEOF'
#!/bin/sh
exec sowm
XEOF
chmod +x /home/xo/.xinitrc
chown xo:xo /home/xo/.xinitrc

cat >> /home/xo/.bashrc << 'BEOF'

# Auto-start X on tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec startx
fi
BEOF
chown xo:xo /home/xo/.bashrc

cat > /root/.xinitrc << 'XEOF'
#!/bin/sh
exec sowm
XEOF
chmod +x /root/.xinitrc
ok "X session configured"

echo ""
echo "============================================"
ok "Arch Linux installation complete!"
echo ""
echo "  Next steps:"
echo "  1. exit"
echo "  2. umount -R /mnt"
echo "  3. reboot"
echo ""
echo "  After reboot:"
echo "  - Login as xo"
echo "  - X will auto-start on tty1"
echo "  - Use nmtui to manage WiFi"
echo "============================================"
