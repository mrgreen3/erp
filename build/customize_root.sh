#!/usr/bin/env bash
# Run inside the target chroot by build.sh (mirrors archbang's
# customize_airootfs.sh, but for a real install rather than a live ISO).
# Expects TARGET_USER / USER_PASSWORD as env vars from build.sh.
set -euo pipefail

: "${TARGET_USER:?TARGET_USER not set}"
: "${USER_PASSWORD:?USER_PASSWORD not set}"

locale-gen

# archbang's skel configs hardcode the live ISO's "live" username in a few
# absolute paths (e.g. mango's wallpaper exec-once) — rewrite to the real
# target user before useradd -m copies skel into the new home.
grep -rlZ '/home/live' /etc/skel 2>/dev/null | xargs -0r sed -i "s#/home/live#/home/$TARGET_USER#g"

# Auto-enable pipewire user services for any new user — symlinked into skel
# *before* useradd -m so the new home picks them up, same technique
# archbang's customize_airootfs.sh uses.
USER_UNIT_DIR="/etc/skel/.config/systemd/user/default.target.wants"
mkdir -p "$USER_UNIT_DIR"
for service in wireplumber.service pipewire.service pipewire-pulse.service xdg-user-dirs.service; do
    if [[ -f "/usr/lib/systemd/user/$service" ]]; then
        ln -sf "/usr/lib/systemd/user/$service" "$USER_UNIT_DIR/$service"
    else
        echo "Warning: user service not found: $service" >&2
    fi
done

useradd -m -G wheel -s /bin/bash "$TARGET_USER"
echo "$TARGET_USER:$USER_PASSWORD" | chpasswd

# Real install: wheel sudo requires a password (unlike the live ISO's
# NOPASSWD convenience).
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
chown -c root:root /etc/sudoers
chmod -c 0440 /etc/sudoers

systemctl enable NetworkManager
systemctl set-default graphical.target

# greetd (cage + gtkgreet, lightweight graphical greeter) takes over tty1.
# Its unit Conflicts=/After= getty@tty1.service so no manual masking needed.
# Session options come from /etc/greetd/environments (gtkgreet doesn't scan
# .desktop files itself). The 'greeter' system user is created automatically
# by greetd's own sysusers.d entry.
systemctl enable greetd.service

# GTK_THEME via /etc/environment (read by pam_env in every session,
# including the greeter's) so gtkgreet picks up the same adw-gtk3-dark
# theme the desktop itself uses (overlay/etc/skel/.config/gtk-3.0/settings.ini)
# instead of falling back to bare default GTK styling.
echo "GTK_THEME=adw-gtk3-dark" >> /etc/environment
