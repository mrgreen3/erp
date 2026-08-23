# Status (2026-08-23)

## Working end to end (QEMU/OVMF verified)
Full cycle proven: build 4G image → boot on a larger disk (8G in testing)
→ GPT partition and ext4 filesystem both grow in a single boot → reboot →
clean idempotent no-op (repart reports "No changes", growfs re-resizes to
the same size with no error). Not yet tested on real hardware/USB.

## Bugs found and fixed getting here
Five separate issues, found by actually booting the image rather than just
building it — build.sh completing successfully said nothing about whether
any of this worked:

1. `systemd-boot` package no longer exists — `bootctl` merged into the
   main `systemd` package. Dropped from pacstrap list.
2. Custom mkinitcpio `repart` hook referenced
   `/usr/lib/systemd/systemd-repart`; the binary moved to
   `/usr/bin/systemd-repart`. Fixed the `add_binary` path.
3. `systemd-repart` in the initrd failed immediately: `Shared library
   'libfdisk.so.1' is not available`. It dlopen()s libfdisk at runtime
   rather than linking it normally, so mkinitcpio's ldd-based dependency
   resolution in `add_binary` never bundles it. Added an explicit
   `add_binary /usr/lib/libfdisk.so.1`.
4. Even with libfdisk fixed, the initrd-stage repart still failed:
   `add_systemd_unit` auto-enables a unit via its packaged `[Install]
   WantedBy=sysinit.target` (meant for the real system) *in addition to*
   the `initrd-root-fs.target.wants` symlink it copies from the host (the
   correct initrd timing, after the root device is found). The initrd's
   own `sysinit.target` is reached before `/sysroot` even exists, so that
   premature copy fired first and failed ("Failed to determine if
   '/sysroot' points to the root directory"), and since systemd doesn't
   retry a failed unit within the same boot, the correctly-timed copy
   never got a turn. The hook now deletes the premature
   `sysinit.target.wants` symlink after `add_systemd_unit`, and also
   explicitly `add_dir /sysroot` (Arch's minimal initrd has no
   dracut-style module pre-creating that mountpoint dir this early).
5. `systemd-growfs-root.service` never ran at all — it's normally pulled
   in dynamically by `systemd-gpt-auto-generator` via the root
   partition's GPT "grow" flag, but that generator skips root-partition
   auto-discovery entirely when `root=` is set explicitly on the kernel
   cmdline (our deliberate choice, decoupled from repart.d's GPT-type
   matching for reliability on real hardware). Wired it in statically in
   `build.sh` instead — but `systemctl enable` on it is a silent no-op
   (exit 0, does nothing) since the unit has no `[Install]` section, so
   `build.sh` now creates the `sysinit.target.wants` symlink directly.

## Known limitation (not fixed, not expected to matter)
`systemd-repart` fails with "Can't fit requested partitions into available
free space" if the underlying disk is an *exact* byte-for-byte match for
the already-built image (zero slack for GPT alignment/backup-header
overhead) — confirmed this is unrelated to Weight/PaddingWeight tuning,
any `[Partition] Type=root` rule fails identically on a zero-slack disk.
Worked around for the steady state by reserving a permanent `PaddingMinBytes=8M`
tail in `repart.d/50-root.conf` so root never claims the disk's very last
byte (this is also what makes post-grow reboots idempotent instead of
failing every time). The *very first* boot of a never-resized image
would still hit this if the target disk happened to be byte-identical in
size — not expected in practice since a real USB stick is never
bit-identical to the source image, and it wasn't observed in any of the
grow-test boots (which used a genuinely larger disk, as real usage would).

## Design (unchanged from original plan)
Using Arch's native systemd tooling rather than cloud-guest-utils:
- `systemd-repart.service` (shipped + enabled "static" in Arch's systemd
  package) grows the GPT partition table entry in the initrd, before root
  is mounted, driven by `repart.d/50-root.conf` (Type=root,
  GrowFileSystem=yes, PaddingMinBytes=8M).
- `systemd-growfs-root.service` (shipped but NOT auto-wired when root= is
  explicit — see bug 5 above) then grows the ext4 filesystem to match,
  after switch-root.
- Boot: UEFI via systemd-boot, GPT (ESP ef00 + root 8304 "Linux x86-64
  root"), explicit `root=PARTUUID=...` on the kernel cmdline.

## Files in this repo
- `build/build.sh` — builds the 4G sparse image end to end, verified
  working.
- `mkinitcpio/repart` — the custom initrd install hook (bugs 2-4 above).
- `repart.d/50-root.conf` — the repart definition (bug 5's workaround).
- `qemu/serial_drive.py` — scripts a serial-console login + command
  sequence against a running QEMU instance over a unix socket, for
  non-interactive boot testing. Reusable for future boot tests.

## Next steps
1. Real hardware test: dd the built image to an actual USB stick bigger
   than 4G, boot a real machine, confirm the same grow-on-first-boot
   behaviour (QEMU/OVMF should be representative, but real firmware,
   real disk geometry, and CSM/legacy-vs-UEFI quirks could still differ).
2. Consider whether the ~4 second delay between "Reached target Login
   Prompts" and the repart/growfs work completing (observed in testing)
   is worth measuring properly as boot-time overhead.
3. Nothing else currently blocking — the core PoC goal (prove a small
   image can grow to fill a bigger real drive on first boot, RPi-OS style)
   is met.
