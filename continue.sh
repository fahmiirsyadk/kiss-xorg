#!/bin/bash
set -e

log()  { printf '\033[32m->\033[m %s\n' "$*"; }
ok()   { printf '\033[32mOK\033[m  %s\n' "$*"; }
warn() { printf '\033[33m!>\033[m %s\n' "$*"; }

log "=== Enable NetworkManager (for after reboot) ==="
ln -sf /usr/lib/systemd/system/NetworkManager.service /etc/systemd/system/multi-user.target.wants/
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service /etc/systemd/system/network-online.target.wants/
ok "NetworkManager will start on boot"

log "=== Configure X session for xo ==="
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
ok "Chroot setup complete!"
echo ""
echo "  Next steps:"
echo "  1. exit"
echo "  2. umount -R /mnt"
echo "  3. reboot"
echo ""
echo "  After reboot, login as xo then run:"
echo "  bash <(curl -fsSL https://raw.githubusercontent.com/fahmiirsyadk/kiss/master/setup/post-install.sh)"
echo "============================================"
