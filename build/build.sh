#!/bin/bash
# Build a minimal expandable Arch rootfs image.
# PoC only: base + boot essentials, small 4G image, UEFI/systemd-boot.
# Must be run as root (or via sudo).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$HERE")"

IMG="$HERE/expandable-poc.img"
MNT="$HERE/mnt"
IMG_SIZE="4G"
ESP_SIZE="300M"
ROOT_PASSWORD="root"   # PoC only — not for anything beyond isolated test boots

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

echo "==> pacstrap (base + boot essentials only)"
pacstrap -c "$MNT" base linux linux-firmware mkinitcpio systemd sudo vi

echo "==> configuring fstab"
genfstab -U "$MNT" >> "$MNT/etc/fstab"

echo "==> installing custom mkinitcpio repart hook"
install -Dm755 "$PROJ/mkinitcpio/repart" "$MNT/etc/initcpio/install/repart"
install -Dm644 "$PROJ/repart.d/50-root.conf" "$MNT/etc/repart.d/50-root.conf"

sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems repart fsck)/' \
    "$MNT/etc/mkinitcpio.conf"

echo "==> basic system config"
echo "expandable-poc" > "$MNT/etc/hostname"
ln -sf /usr/share/zoneinfo/UTC "$MNT/etc/localtime"
echo "en_US.UTF-8 UTF-8" >> "$MNT/etc/locale.gen"
echo "LANG=en_US.UTF-8" > "$MNT/etc/locale.conf"

ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PART")
echo "==> root PARTUUID: $ROOT_PARTUUID"

arch-chroot "$MNT" /bin/bash -c "
    set -e
    locale-gen
    echo root:$ROOT_PASSWORD | chpasswd
    mkinitcpio -P
    bootctl install --path=/boot
    # systemd-growfs-root.service is normally pulled in dynamically by
    # systemd-gpt-auto-generator via the root partition's GPT 'grow' flag
    # (set by GrowFileSystem=yes in repart.d/50-root.conf). That generator
    # skips root-partition auto-discovery entirely when root= is set
    # explicitly on the kernel cmdline (our deliberate choice, decoupled
    # from repart.d's GPT-type matching for reliability on real hardware)
    # — so enable it statically instead of relying on the generator.
    systemctl enable systemd-growfs-root.service
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
