#!/bin/bash
set -e

log()  { printf '\033[32m->\033[m %s\n' "$*"; }
ok()   { printf '\033[32mOK\033[m  %s\n' "$*"; }
warn() { printf '\033[33m!>\033[m %s\n' "$*"; }
err()  { printf '\033[31mERR\033[m %s\n' "$*"; exit 1; }

[ "$(id -u)" = 0 ] || err "Must be run as root"

cat << 'BANNER'
    _              _       _
   / \   _ __ ___ | |__   | |    _   _  ___  _   _
  / _ \ | '__/ __|| '_ \  | |   | | | |/ _ \| | | |
 / ___ \| | | (__ | | | | | |___| |_| | (_) | |_| |
/_/   \_\_|  \___||_| |_| |_____|\__, |\___/ \__,_|
                                  |___/
  Arch Linux — Bare-Metal Installer (ThinkPad E14 Gen 5)
BANNER

PART_ESP="/dev/nvme0n1p1"
PART_ROOT="/dev/nvme0n1p2"
PART_WIN="/dev/nvme0n1p3"

echo ""
log "=== Step 1: WiFi connection ==="
log "You'll need internet for pacstrap. Connect to WiFi now."
iwctl
ok "WiFi configured"

echo ""
log "=== Step 2: Verify partitions ==="
log "ESP  partition : $PART_ESP (Windows bootloader — NOT formatted)"
log "Root partition : $PART_ROOT (will be formatted ext4)"
log "Windows        : $PART_WIN (untouched)"
[ -b "$PART_ESP"  ] || err "ESP partition not found: $PART_ESP"
[ -b "$PART_ROOT" ] || err "Root partition not found: $PART_ROOT"
[ -b "$PART_WIN"  ] || warn "Windows partition not found: $PART_WIN (dual boot may not work)"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT /dev/nvme0n1

log "Formatting $PART_ROOT as ext4..."
mkfs.ext4 -F "$PART_ROOT"

log "Mounting..."
mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_ESP" /mnt/boot

echo ""
log "=== Step 3: Select mirrors ==="
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
ok "Mirrors updated"

echo ""
log "=== Step 4: Install base system ==="
pacstrap -K /mnt base linux linux-firmware intel-ucode sof-firmware networkmanager sudo nano base-devel git
ok "Base system installed"

echo ""
log "=== Step 5: Generate fstab ==="
genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab generated"

echo ""
log "=== Step 6: Chroot setup ==="

cat > /mnt/setup-chroot.sh << 'SETUP_EOF'
#!/bin/bash
set -e

log()  { printf '\033[32m->\033[m %s\n' "$*"; }
ok()   { printf '\033[32mOK\033[m  %s\n' "$*"; }
warn() { printf '\033[33m!>\033[m %s\n' "$*"; }

echo ""
log "=== Timezone ==="
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
hwclock --systohc
ok "Timezone: Asia/Jakarta"

echo ""
log "=== Locale ==="
sed -i '/en_US.UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ok "Locale: en_US.UTF-8"

echo ""
log "=== Hostname ==="
echo "yorha" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 yorha.localdomain yorha" >> /etc/hosts
ok "Hostname: yorha"

echo ""
log "=== Root password ==="
passwd

echo ""
log "=== Create user: xo ==="
useradd -m -G wheel,video,audio -s /bin/bash xo
passwd xo
ok "User xo created"

echo ""
log "=== Sudoers ==="
sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers
ok "wheel group enabled in sudoers"

echo ""
log "=== Install X11 stack ==="
pacman -S --noconfirm xorg-server xf86-video-intel xf86-input-libinput xorg-xinit
ok "X11 installed"

echo ""
log "=== Install audio (pipewire) ==="
pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber
ok "Pipewire installed"

echo ""
log "=== Install bootloader (grub + os-prober) ==="
pacman -S --noconfirm grub efibootmgr os-prober
echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg
ok "GRUB installed (dual boot with Windows enabled)"

echo ""
log "=== Enable NetworkManager ==="
systemctl enable NetworkManager
ok "NetworkManager enabled"

echo ""
log "=== Connect to WiFi (nmtui) ==="
log "Use nmtui to connect to your WiFi network now."
nmtui
ok "WiFi configured"

echo ""
log "=== Install yay (AUR helper) ==="
su - xo -c '
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd /tmp
rm -rf yay
'
ok "yay installed"

echo ""
log "=== Install AUR packages (sowm, st) ==="
su - xo -c 'yay -S --noconfirm sowm st'
ok "sowm and st installed"

echo ""
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
ok "X session configured"

echo ""
log "=== Root X session (optional) ==="
cat > /root/.xinitrc << 'XEOF'
#!/bin/sh
exec sowm
XEOF
chmod +x /root/.xinitrc

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
SETUP_EOF

chmod +x /mnt/setup-chroot.sh
ok "Chroot script ready"

log "Entering chroot — run: /setup-chroot.sh"
echo ""
arch-chroot /mnt

log "Chroot exited. Unmounting..."
umount -R /mnt 2>/dev/null || true
ok "Done. You can now reboot."
