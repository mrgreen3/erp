# Installing to a USB drive

erp builds a small, sparse `.img` (currently `IMG_SIZE=8G` nominal in
`build/build.sh`, ~3G actually written) that grows to fill whatever drive
you write it to on first boot — RPi-OS style. Write it to a USB stick
bigger than the source image and the root filesystem expands to use the
rest of the space automatically the first time it boots.

**UEFI only.** The image ships `systemd-boot`, not GRUB, and has no BIOS
boot code. The target machine must boot in UEFI mode.

## 1. Identify the target drive

```
lsblk
```

Find the USB stick by size/model — **do not guess**. Writing to the wrong
device destroys its contents with no warning and no undo. If unsure, unplug
everything else and re-run `lsblk` to confirm which device just disappeared
and reappeared.

Below, `$USB` is that device, e.g. `/dev/sdX` — **not** a partition
(`/dev/sdX1`).

## 2. Write the image

If you have the raw build output (`build/expandable-poc.img`):

```
sudo dd if=build/expandable-poc.img of=$USB bs=4M status=progress conv=fsync
```

If you have a compressed release (see
[erp image compression](../docs/status.md) — currently shipped as
`xz -6`, ~1.2G):

```
xz -dc erp.img.xz | sudo dd of=$USB bs=4M status=progress conv=fsync
```

`conv=fsync` makes `dd` actually flush to the device before exiting —
don't skip it, and don't unplug the drive until the command returns and the
prompt comes back.

## 3. Verify the write (optional but recommended)

```
sudo eject $USB    # or: udisksctl power-off -b $USB
```

Re-plug and check the partition table landed correctly:

```
sudo sgdisk -p $USB
```

Expect two partitions: a small FAT32 ESP (`ef00`) and the ext4 root
(`8304`), matching the source image's layout — they haven't grown yet,
that happens on first boot.

## 4. First boot

Boot the target machine from the USB stick (UEFI boot menu, not legacy/CSM).
On first boot:

1. `systemd-repart.service` grows the GPT root partition entry to
   consume the rest of the disk (minus an 8M tail reserved by
   `repart.d/50-root.conf` — deliberate slack, not a bug).
2. `systemd-growfs-root.service` grows the ext4 filesystem to match.

Both run automatically, no prompts. Expect a few seconds of extra delay
around the login prompt on this first boot only — subsequent boots are a
fast no-op (`systemd-repart` reports "No changes").

Log in as the built-in user (currently `bang` / `bang` — see
`build/build.sh`'s `TARGET_USER`/`USER_PASSWORD`, PoC-only credentials, not
meant to survive as-is for anything beyond testing) or `root` / `root`.
MangoWM starts automatically via `.bash_profile`'s tty1 exec.

## Known limitations

- **Not yet tested on real hardware** — proven in QEMU/OVMF only so far
  (see `docs/status.md`). Real firmware, disk geometry, and CSM/legacy
  quirks could still differ.
- If the target disk happens to be **exactly** the same size as the source
  image (byte-for-byte), first-boot repart can fail with "Can't fit
  requested partitions into available free space" — not expected with a
  real USB stick, which is never bit-identical to the source, and not
  something you'll hit if the target is genuinely bigger (the normal case).
- Credentials, hostname (`archbang`), and image size are all hardcoded in
  `build/build.sh` for this PoC stage — expect to rebuild with your own
  values rather than relying on these defaults for anything beyond testing.
