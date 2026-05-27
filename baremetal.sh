#!/bin/sh -e

log()  { printf '\033[32m->\033[m %s\n' "$*"; }
ok()   { printf '\033[32mOK\033[m  %s\n' "$*"; }
warn() { printf '\033[33m!>\033[m %s\n' "$*"; }
err()  { printf '\033[31mERR\033[m %s\n' "$*"; exit 1; }

ROOTFS_TAR="kiss-chroot-24.12.18.tar.xz"
ROOTFS_URL="https://codeberg.org/kiss-community/repo/releases/download/24.12.18/$ROOTFS_TAR"
ROOTFS_SHA256="4e5ecef56e747029d2665a038b17a156a0cffd8ba9c99a776226aaf02bd9ff72"

[ "$(id -u)" = 0 ] || err "Must be run as root"

cat << 'BANNER'
  _  ___ _____ _____   ___    _   _
 | |/ (_)  __ \_   _| / _ \  | \ | |
 | ' / _| |__) || |  / /_\ \ |  \| |
 |  < | |  ___/ | |  |  _  | | . ` |
 | . \| | |    _| |_ | | | | | |\  |
 |_|\_\_\_|   |_____|\_| |_/ |_| \_|
   KISS Linux — Bare-Metal Installer
BANNER

PART_ESP="/dev/nvme0n1p1"
PART_ROOT="/dev/nvme0n1p2"

echo ""
log "=== Step 1: Verify partitions ==="
log "EFI  partition : $PART_ESP"
log "Root partition : $PART_ROOT"
[ -b "$PART_ESP"  ] || err "EFI  partition not found: $PART_ESP"
[ -b "$PART_ROOT" ] || err "Root partition not found: $PART_ROOT"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT /dev/nvme0n1 2>/dev/null

log "Formatting $PART_ESP as FAT32..."
mkfs.fat -F32 "$PART_ESP"
log "Formatting $PART_ROOT as ext4..."
mkfs.ext4 -F "$PART_ROOT"

log "Mounting..."
KISS_ROOT="/mnt"
mount "$PART_ROOT" "$KISS_ROOT"
mkdir -p "$KISS_ROOT/boot"
mount "$PART_ESP" "$KISS_ROOT/boot"

echo ""
log "=== Step 2: Extract rootfs ==="
curl -Lo "/tmp/$ROOTFS_TAR" "$ROOTFS_URL"
echo "$ROOTFS_SHA256  /tmp/$ROOTFS_TAR" | sha256sum -c || err "Checksum mismatch"
tar xf "/tmp/$ROOTFS_TAR" -C "$KISS_ROOT"

echo ""
log "=== Step 3: Clone repos ==="
if ! command -v git >/dev/null 2>&1; then
    log "git not found — attempting to install..."
         if command -v kiss    >/dev/null 2>&1; then kiss b git && kiss i git
    elif command -v apk     >/dev/null 2>&1; then apk add --no-cache git
    elif command -v apt-get >/dev/null 2>&1; then apt-get install -y git
    elif command -v pacman  >/dev/null 2>&1; then pacman -Sy --noconfirm git
    elif command -v xbps-install >/dev/null 2>&1; then xbps-install -Sy git
    else err "Cannot install git — install it manually then rerun this script"
    fi
fi
command -v git >/dev/null 2>&1 || err "git still not available after install attempt"
ok "git available: $(git --version)"

export GIT_TERMINAL_PROMPT=0
git_clone() {
    url="$1" dest="$2" tries=0 delay=5
    while :; do
        tries=$((tries+1))
        log "Cloning $url ($tries/5)..."
        git clone --depth 1 --single-branch "$url" "$dest" 2>/dev/null && { ok "$dest"; return 0; }
        rm -rf "$dest"
        git clone "$url" "$dest" 2>/dev/null && { ok "$dest"; return 0; }
        rm -rf "$dest"
        [ "$tries" -ge 5 ] && err "Failed to clone $url"
        warn "Clone failed — retrying in ${delay}s..."
        sleep "$delay"; delay=$((delay*2))
    done
}

mkdir -p "$KISS_ROOT/home/repos"
git_clone https://github.com/kiss-community/repo      "$KISS_ROOT/home/repos/repo"
git_clone https://github.com/kiss-community/community  "$KISS_ROOT/home/repos/community"
git_clone https://github.com/echawk/kiss-xorg          "$KISS_ROOT/home/repos/xorg"
git_clone https://github.com/fahmiirsyadk/kiss         "$KISS_ROOT/home/repos/custom"

echo ""
log "=== Step 4: Chroot setup ==="
mount --bind /dev      "$KISS_ROOT/dev"
mount --bind /dev/pts  "$KISS_ROOT/dev/pts"
mount -t proc  proc    "$KISS_ROOT/proc"
mount -t sysfs sys     "$KISS_ROOT/sys"
cp /etc/resolv.conf    "$KISS_ROOT/etc/resolv.conf"

log "Generating chroot setup script..."

cat > "$KISS_ROOT/setup-chroot.sh" << 'SETUP_EOF'
#!/bin/sh -e

log()  { printf '\033[32m->\033[m %s\n' "$*"; }
ok()   { printf '\033[32mOK\033[m  %s\n' "$*"; }
warn() { printf '\033[33m!>\033[m %s\n' "$*"; }

PART_ESP="__PART_ESP__"
PART_ROOT="__PART_ROOT__"
D="/home/repos"

export KISS_PATH="$D/xorg/extra:$D/xorg/xorg:$D/xorg/community:$D/repo/core:$D/repo/extra:$D/repo/wayland:$D/community/community:$D/custom/packages"
export KISS_PROMPT=0

echo ""
log "=== Step 5: Build kernel ==="
log "Installing kernel build deps..."
for pkg in flex bison perl libelf pkgconf; do
    kiss l "$pkg" >/dev/null 2>&1 && ok "$pkg installed" || { kiss b "$pkg" && kiss i "$pkg" || warn "$pkg failed"; }
done
log "Building kernel..."
kiss build kernel && kiss install kernel && ok "kernel installed" || warn "kernel build failed"
KVERSION=$(ls /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|/boot/vmlinuz-||')

echo ""
log "=== Step 6: Install firmware ==="
if find /sys/class/net -name 'wlan*' | grep -q wlan 2>/dev/null; then
    log "WiFi detected — downloading firmware..."
    mkdir -p /usr/lib/firmware/intel/sof
    curl -sLo /usr/lib/firmware/iwlwifi-so-a0-gf-a0-100.ucode https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/iwlwifi-so-a0-gf-a0-100.ucode
    curl -sLo /usr/lib/firmware/intel/sof/sof-tgl.ri https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/intel/sof/sof-tgl.ri
    ok "Firmware installed"
else
    warn "No WiFi — skipping firmware"
fi

echo ""
log "=== Step 7: Build freetype-harfbuzz ==="
kiss build freetype-harfbuzz && kiss install freetype-harfbuzz && ok "freetype-harfbuzz" || warn "freetype-harfbuzz failed"

echo ""
log "=== Step 8: Build packages ==="
for pkg in fontconfig libpng xorgproto libXau libXdmcp libxcb xcb-proto xtrans xorg-util-macros libX11 libXext libXfixes libXi libXtst libfontenc libXfont tinyx xf86-video-intel xf86-input-libinput xkeyboard-config sowm st sx; do
    kiss search "$pkg" >/dev/null 2>&1 || { warn "$pkg not found"; continue; }
    log "Building $pkg..."
    kiss build "$pkg" && kiss install "$pkg" && ok "$pkg" || warn "$pkg failed"
done

echo ""
log "=== Step 9: Configure system ==="
mkdir -p /root/.config/sx
cat > /root/.config/sx/sxrc << 'XEOF'
#!/bin/sh
exec sowm
XEOF
chmod +x /root/.config/sx/sxrc

[ -f /usr/bin/sx ] && grep -q Xorg /usr/bin/sx 2>/dev/null && sed -i 's/Xorg/Xfbdev/;s/-keeptty//' /usr/bin/sx
grep -q "exec sx" /root/.profile 2>/dev/null || printf '\n[ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ] && exec sx\n' >> /root/.profile

mkdir -p /etc/iwd
cat > /etc/iwd/main.conf << 'XEOF'
[General]
EnableNetworkConfiguration=true
UseDefaultInterface=true
[Network]
NameResolvingService=resolvconf
[Scan]
DisablePeriodicScan=true
XEOF
ln -sf /etc/sv/eiwd /var/service/ 2>/dev/null || true

echo ""
log "=== Step 10: Install bootloader ==="
DISK="${PART_ROOT%p[0-9]*}"
ESP_PARTNUM="${PART_ESP##*p}"
if [ -d /sys/firmware/efi ]; then
    log "UEFI — installing GRUB..."
    kiss b grub && kiss i grub
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=KISS
    grub-mkconfig -o /boot/grub/grub.cfg
    ok "GRUB installed"
else
    log "BIOS — installing GRUB on $DISK..."
    kiss b grub && kiss i grub
    grub-install --target=i386-pc "$DISK"
    grub-mkconfig -o /boot/grub/grub.cfg
    ok "GRUB installed"
fi

echo ""
log "=== Step 11: System config ==="
echo "nier-kiss" > /etc/hostname
echo "127.0.1.1 nier-kiss" >> /etc/hosts
ok "Hostname: nier-kiss"

log "Set root password:"
passwd root

log "Creating user..."
useradd -m -G wheel,video,audio archuser
log "Set password for archuser:"
passwd archuser

mkdir -p /home/archuser/.config/sx
cp /root/.config/sx/sxrc /home/archuser/.config/sx/sxrc
chown -R archuser:archuser /home/archuser/.config
grep -q "exec sx" /home/archuser/.profile 2>/dev/null || printf '\n[ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ] && exec sx\n' >> /home/archuser/.profile

for sv in eiwd dhcpcd alsa; do
    [ -d "/etc/sv/$sv" ] && ln -sf "/etc/sv/$sv" /var/service/ && ok "$sv enabled" || warn "$sv not found"
done

echo ""
echo "============================================"
ok "KISS Linux installation complete!"
echo "  1. exit"
echo "  2. umount -R /mnt"
echo "  3. reboot"
echo "============================================"
SETUP_EOF

sed -i \
    -e "s|__PART_ESP__|${PART_ESP}|g" \
    -e "s|__PART_ROOT__|${PART_ROOT}|g" \
    "$KISS_ROOT/setup-chroot.sh"
chmod +x "$KISS_ROOT/setup-chroot.sh"

grep -q "^PART_ROOT=\"/dev/" "$KISS_ROOT/setup-chroot.sh" || err "PART_ROOT placeholder not replaced"
grep -q "^PART_ESP=\"/dev/"  "$KISS_ROOT/setup-chroot.sh" || err "PART_ESP placeholder not replaced"
ok "chroot script ready"

log "Entering chroot — run: /setup-chroot.sh"
echo ""
chroot "$KISS_ROOT" /usr/bin/env -i \
    HOME=/root TERM="$TERM" SHELL=/bin/sh USER=root LOGNAME=root \
    PATH="/usr/bin:/usr/sbin:/bin" \
    KISS_PROMPT=0 \
    /bin/sh -l

log "Chroot exited. Unmounting..."
umount -R "$KISS_ROOT" 2>/dev/null
ok "Done. You can now reboot."
