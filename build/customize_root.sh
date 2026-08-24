#!/usr/bin/env bash
# Run inside the target chroot by build.sh (mirrors minibang's
# customize_airootfs.sh, but for a real install rather than a live ISO).
# Expects TARGET_USER / USER_PASSWORD as env vars from build.sh.
set -euo pipefail

: "${TARGET_USER:?TARGET_USER not set}"
: "${USER_PASSWORD:?USER_PASSWORD not set}"

locale-gen

useradd -m -G wheel -s /bin/bash "$TARGET_USER"
echo "$TARGET_USER:$USER_PASSWORD" | chpasswd

# Real install: wheel sudo requires a password (unlike the live ISO's
# NOPASSWD convenience).
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
chown -c root:root /etc/sudoers
chmod -c 0440 /etc/sudoers

systemctl enable NetworkManager
