# MiniBang login shell configuration
# Starts Xorg + i3 on TTY1 via startx (no display manager)

. $HOME/.bashrc

# Boot cheat code: append `nox` to the kernel command line (edit at the
# syslinux/systemd-boot/GRUB prompt) to skip Xorg and stay at this console.
if [[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && ! grep -qw nox /proc/cmdline; then
    exec startx
fi



