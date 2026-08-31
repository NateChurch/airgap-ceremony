# airgap-ceremony

A reproducible Debian live ISO for offline key ceremonies: YubiKey provisioning,
SSH/host CA generation, age identity creation, and Shamir splitting.

The image is amnesiac (RAM-only, no swap, no persistence), has no network stack
that can be brought up, and carries the complete toolchain — because the machine
that boots it has no apt.

## Why an image and not "some small distro"

The tempting answer to "smallest Debian" is antiX-core at ~250 MB. That is the
wrong optimization. On an air-gapped box, whatever is on the ISO is the entire
universe of available tooling. A 250 MB image means sneakernetting `.deb` files
and hand-resolving dependencies partway through a procedure that is supposed to
be auditable — the same class of error as a hand-typed path in an acme.sh
`.conf`.

So: the package set is declared in `config/package-lists/`, the image properties
are declared in `auto/config`, and the resulting ISO is verified rather than
assumed. Expect ~900 MB–1.1 GB with the default lists.

## Layout

```
auto/config                                 image properties (the declaration)
config/package-lists/ceremony.list.chroot   the toolchain
config/package-lists/*.disabled             optional: printing, X
config/binaries.env.example                 template for non-Debian binaries
config/hooks/normal/                        build-time: fetch, harden, manifest
config/includes.chroot/                     files baked into the live filesystem
  etc/gnupg/scdaemon.conf                   the pcscd/CCID fix
  etc/modprobe.d/airgap-blacklist.conf      radios and DMA refused at module load
  usr/local/bin/ceremony-selftest           on-boot verification
scripts/verify-iso.sh                       host-side ISO verification
Makefile                                    build / artifacts / verify / write
```

## Build

Build host: **Debian trixie or bookworm, as root, in a VM or privileged LXC.**

```sh
apt install live-build debootstrap xorriso squashfs-tools curl
cp config/binaries.env.example config/binaries.env
$EDITOR config/binaries.env        # fill in real URLs and sha256 values
make preflight
make build
```

`make build` runs `lb build`, asserts the ISO actually exists (exit 0 from
`lb build` is not proof), then collects the ISO, build log, package list and a
`SHA256SUMS` into `artifacts/<timestamp>/`.

```sh
make write DEV=/dev/sdX     # writes, then reads the device back and compares
                            # the hash against the source ISO
```

## First boot

Log in as `ceremony` (no password). `ceremony-selftest` runs automatically on
login and also on demand. It asserts, against live system state:

- `toram` in effect and root is overlay/tmpfs — the boot medium can be removed
- no swap active
- no interface up, no default route, 802.11/Bluetooth modules not loaded
- no wifi firmware shipped
- every required binary present, including `sops`
- `scdaemon.conf` has `disable-ccid`, and if a token is inserted, that `ykman`
  and `gpg --card-status` both succeed against it
- build manifest present

Exit 1 on any failure. Do not proceed with a ceremony on a box that fails.

## Sharp edges

**Do not build this in WSL.** `make preflight` refuses. live-build's chroot
bind-mounts and loop handling are an unnecessary variable in a build whose whole
point is reproducibility. Build in a VM (Proxmox, libvirt, whatever you run) or
a privileged LXC. WSL is fine for editing the config; not for producing the artifact.

**pcscd and scdaemon contend for the CCID interface.** `ykman` and
`yubico-piv-tool` go through pcscd; GnuPG's internal driver wants exclusive
access to the same device. Whichever touches the token first wins and the other
reports "card not present" or hangs. `etc/gnupg/scdaemon.conf` ships
`disable-ccid` so GnuPG routes through pcscd too. The selftest verifies both
paths work against the same inserted token, which is the only check that
actually proves it.

**`sops` is not in Debian.** Neither is `talosctl`. They are fetched at build
time by `0100-external-binaries.hook.chroot`, which **fails the build** if the
URL or SHA-256 is unset or does not match. There is deliberately no bypass.
Fill in `config/binaries.env` from the projects' published checksum files, and
verify those files' signatures before trusting them. `config/binaries.env` is
gitignored — a stale committed checksum is worse than none.

**Firmware is omitted by default** (`INCLUDE_FIRMWARE=false`). A machine with no
wifi firmware cannot associate even if something tries; the module blacklist
covers adapters that carry their own. If the target laptop needs firmware to
reach a usable console for storage or graphics, set `INCLUDE_FIRMWARE=true` and
accept that the selftest will warn about it.

**`toram` needs RAM.** The default image plus decompression wants roughly 4 GB
free. If the ceremony laptop has 2 GB, either trim the package lists or drop
`toram` from `--bootappend-live` and keep the USB stick inserted — but then the
medium is load-bearing and the selftest will fail that assertion, correctly.

**`--apt-recommends false` is set.** It keeps the image lean and the manifest
honest, but it means a package you add may not pull a helper it expects. If
something is missing at ceremony time, add it explicitly to the list and rebuild
rather than working around it on the box.

## Reproducibility

For a build that reproduces years from now, pin a snapshot mirror:

```sh
make build MIRROR=https://snapshot.debian.org/archive/debian/20260801T000000Z/
```

Snapshot is slow and rate-limits; use it for the archival build you record in
the estate documentation, and the normal mirror for iteration. Either way,
`artifacts/<timestamp>/SHA256SUMS` plus the embedded package manifest is what
makes a given ISO attestable. `scripts/verify-iso.sh` extracts that manifest
from an ISO without booting it, so two builds can be diffed directly.

## Deferred

- Secure Boot signing of the ISO — currently unsigned, so the ceremony laptop
  needs Secure Boot off or a custom MOK. Worth doing; not blocking.
- Hardware entropy source (TPM or a dedicated RNG) beyond `rng-tools5` +
  `haveged`. The selftest warns below 256 bits available.
