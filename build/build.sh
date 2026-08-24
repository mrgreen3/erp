#!/bin/bash
# Build an expandable Arch rootfs image: full ArchBang (MangoWM/Wayland)
# desktop stack on top of the grow-on-first-boot PoC, UEFI/systemd-boot.
# Must be run as root (or via sudo).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$HERE")"
ARCHBANG_AUR_REPO="/home/mrgreen/Projects/archbang/aur_repo"

IMG="$HERE/expandable-poc.img"
MNT="$HERE/mnt"
IMG_SIZE="8G"
ESP_SIZE="300M"
ROOT_PASSWORD="root"    # PoC only — not for anything beyond isolated test boots
TARGET_USER="bang"      # PoC only — not Kev's real name, this isn't a live/personal env
USER_PASSWORD="bang"    # PoC only — not for anything beyond isolated test boots

if [[ $EUID -ne 0 ]]; then
    echo "must run as root" >&2
    exit 1
fi

cleanup() {
    set +e
    if mountpoint -q "$MNT/boot"; then umount "$MNT/boot"; fi
    if mountpoint -q "$MNT"; then umount "$MNT"; fi
    if [[ -n "${LOOPDEV:-}" ]]; then losetup -d "$LOOPDEV" 2>/dev/null; fi
}
trap cleanup EXIT

rm -f "$IMG"
truncate -s "$IMG_SIZE" "$IMG"

echo "==> partitioning $IMG"
sgdisk --zap-all "$IMG"
sgdisk -n1:0:+"$ESP_SIZE" -t1:ef00 -c1:ESP "$IMG"
sgdisk -n2:0:0            -t2:8304 -c2:root "$IMG"
sgdisk -p "$IMG"

LOOPDEV=$(losetup --find --show -P "$IMG")
echo "==> loop device: $LOOPDEV"
udevadm settle
sleep 1

ESP_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

mkfs.vfat -F32 -n ESP "$ESP_PART"
mkfs.ext4 -L root -F "$ROOT_PART"

mkdir -p "$MNT"
mount "$ROOT_PART" "$MNT"
mkdir -p "$MNT/boot"
mount "$ESP_PART" "$MNT/boot"

echo "==> pacstrap (ArchBang MangoWM/Wayland desktop stack, minus live-ISO/grub-only bits)"
pacstrap -c "$MNT" \
    base linux mkinitcpio systemd linux-firmware \
    pipewire pipewire-pulse \
    zip unzip 7zip xz \
    foot \
    swaybg waybar xorg-xwayland wlr-randr grim slurp wl-clipboard \
    brightnessctl swaylock mako reflector rofi \
    greetd greetd-gtkgreet cage \
    thunar thunar-volman gvfs udisks2 \
    vim l3afpad \
    adw-gtk-theme adwaita-icon-theme ttf-jetbrains-mono ttf-nerd-fonts-symbols-mono ttf-dejavu \
    htop fastfetch laptop-detect \
    gparted parted gptfdisk ddrescue testdisk ntfs-3g \
    networkmanager usb_modeswitch broadcom-wl \
    polkit libsecret xdg-user-dirs \
    dialog sudo fontconfig kbd \
    openssh arch-install-scripts curl pacman-contrib fzf eza \
    firefox imv \
    squashfs-tools rsync pv dosfstools btrfs-progs \
    intel-ucode amd-ucode \
    bash bzip2 coreutils cryptsetup device-mapper diffutils e2fsprogs file \
    filesystem findutils gawk gcc-libs gettext glibc grep gzip inetutils \
    iproute2 iputils less licenses nano ex-vi-compat logrotate lvm2 man-db \
    man-pages pacman pciutils perl procps-ng psmisc sed shadow sysfsutils \
    systemd-sysvcompat tar usbutils util-linux which archlinux-keyring

echo "==> installing AUR-built packages (mango, deps) from erp's local aur_repo"
mkdir -p "$PROJ/aur_repo"
cp -u "$ARCHBANG_AUR_REPO"/*.pkg.tar.zst "$PROJ/aur_repo/"
mkdir -p "$MNT/root/aur_pkgs"
cp "$PROJ"/aur_repo/*.pkg.tar.zst "$MNT/root/aur_pkgs/"
arch-chroot "$MNT" /bin/bash -c 'pacman -U --noconfirm /root/aur_pkgs/*.pkg.tar.zst'
rm -rf "$MNT/root/aur_pkgs"

echo "==> configuring fstab"
genfstab -U "$MNT" >> "$MNT/etc/fstab"

echo "==> installing repart.d config (real-root systemd-repart.service only)"
install -Dm644 "$PROJ/repart.d/50-root.conf" "$MNT/etc/repart.d/50-root.conf"

sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)/' \
    "$MNT/etc/mkinitcpio.conf"

echo "==> installing overlay (etc config + skel, from archbang)"
cp -a "$PROJ/overlay/etc/." "$MNT/etc/"

echo "==> basic system config"
echo "archbang" > "$MNT/etc/hostname"
ln -sf /usr/share/zoneinfo/UTC "$MNT/etc/localtime"
echo "en_US.UTF-8 UTF-8" >> "$MNT/etc/locale.gen"
echo "LANG=en_US.UTF-8" > "$MNT/etc/locale.conf"

ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PART")
echo "==> root PARTUUID: $ROOT_PARTUUID"

echo "==> customizing root (user creation, sudo, NetworkManager)"
install -Dm755 "$HERE/customize_root.sh" "$MNT/root/customize_root.sh"
arch-chroot "$MNT" /bin/bash -c "TARGET_USER='$TARGET_USER' USER_PASSWORD='$USER_PASSWORD' /root/customize_root.sh"
rm -f "$MNT/root/customize_root.sh"

arch-chroot "$MNT" /bin/bash -c "
    set -e
    echo root:$ROOT_PASSWORD | chpasswd
    mkinitcpio -P
    bootctl install --path=/boot
    # systemd-growfs-root.service is normally pulled in dynamically by
    # systemd-gpt-auto-generator via the root partition's GPT 'grow' flag
    # (set by GrowFileSystem=yes in repart.d/50-root.conf). That generator
    # skips root-partition auto-discovery entirely when root= is set
    # explicitly on the kernel cmdline (our deliberate choice, decoupled
    # from repart.d's GPT-type matching for reliability on real hardware)
    # — so wire it in statically instead of relying on the generator.
    # The unit has no [Install] section (it's meant to be pulled in only
    # by the generator, or symlinked statically like this), so
    # 'systemctl enable' is a silent no-op here — go straight to the
    # symlink it would have created.
    mkdir -p /etc/systemd/system/sysinit.target.wants
    ln -sf /usr/lib/systemd/system/systemd-growfs-root.service \
        /etc/systemd/system/sysinit.target.wants/systemd-growfs-root.service
"

mkdir -p "$MNT/boot/loader/entries"
cat > "$MNT/boot/loader/loader.conf" <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

KVER=$(arch-chroot "$MNT" /bin/bash -c 'ls /usr/lib/modules' | head -1)
cat > "$MNT/boot/loader/entries/arch.conf" <<EOF
title   Arch Linux (expandable rootfs PoC)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$ROOT_PARTUUID rw console=tty0 console=ttyS0,115200
EOF

echo "==> build complete: $IMG"
sgdisk -p "$IMG"
