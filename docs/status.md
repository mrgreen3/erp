# Status (2026-08-23)

## Blocked
Build halted mid-`build.sh`: this machine was running kernel 7.1.8-arch1-3
while pacman had already upgraded to 7.1.9-arch1-2, so
/lib/modules/7.1.8-arch1-3 didn't exist and the loop/nbd kernel modules
couldn't load — losetup failed on the image file. Build VM
(192.168.122.175) was also unreachable (no route to host) as a fallback.
Kev is rebooting to pick up 7.1.9; resume `sudo ./build/build.sh` after
that (it cleans up its own partial state via `truncate -s` + `sgdisk
--zap-all` at the top, so it's safe to just re-run).

## Design decided (see docs/findings.md once written up)
Using Arch's native systemd tooling rather than cloud-guest-utils:
- `systemd-repart.service` (already shipped + enabled "static" in Arch's
  systemd package) grows the GPT partition table entry in the initrd,
  before root is mounted, driven by `repart.d/50-root.conf`
  (Type=root, GrowFileSystem=yes, no SizeMaxBytes -> grows to fill disk).
- `systemd-growfs-root.service` (also already shipped + enabled) then
  grows the ext4 filesystem to match, after switch-root.
- Gap found: Arch's mkinitcpio `systemd` hook does NOT bundle
  systemd-repart or /etc/repart.d/*.conf into the initramfs by default,
  so repart can't see its config before root is mounted. Wrote a custom
  mkinitcpio install hook (`mkinitcpio/repart`) to close that gap —
  this is the one bit of custom scripting actually required; everything
  else is stock systemd behaviour and inherently idempotent (repart only
  grows/never shrinks, growfs no-ops once sizes already match).
- Boot: UEFI via systemd-boot, GPT (ESP ef00 + root 8304 "Linux x86-64
  root"), explicit root=PARTUUID=... on the kernel cmdline (not relying
  on gpt-auto-generator for mounting — decoupled from the GPT type-GUID
  matching that repart.d uses, for reliability on real hardware).

## Files in this repo
- `build/build.sh` — builds the 4G sparse image, partitions, pacstraps
  base+linux+systemd-boot, installs the custom mkinitcpio hook +
  repart.d config, runs mkinitcpio -P, installs systemd-boot.
  NOT YET SUCCESSFULLY RUN END TO END — died at the losetup step above,
  before pacstrap. Everything after losetup is unverified.
- `mkinitcpio/repart` — the custom install hook.
- `repart.d/50-root.conf` — the repart definition.

## Next steps after reboot
1. `cd ~/Projects/expandable-rootfs-poc && sudo ./build/build.sh`
2. Watch for pacstrap/mkinitcpio/bootctl errors.
3. Boot-test in QEMU+OVMF first (edk2-ovmf is installed,
   /usr/share/edk2/x64/OVMF_CODE.4m.fd) — resize the qcow2/raw image up
   before a second boot and confirm partition+fs actually grow, and
   confirm idempotency (boot a third time, confirm no-op / no errors).
4. Only after QEMU proves it out: dd to a real USB drive and repeat the
   grow-on-first-boot test on real hardware, per the original ask.
5. Write up docs/findings.md: what broke, what's idiomatic vs custom,
   whether the grow step adds meaningful boot delay.
