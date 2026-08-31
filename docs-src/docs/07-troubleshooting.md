# Troubleshooting

What each failure means, and what to do.

---

## ceremony-selftest

### Amnesia — FAIL `toram absent from /proc/cmdline`

The boot medium is still load-bearing and cannot be removed. Usually means the
image was booted through something that rewrote the kernel command line — a
chainloader, or Ventoy.

Boot the ISO directly from a dd'd stick. Do not run a ceremony without `toram`.

### Amnesia — FAIL `root filesystem is <type>, not overlay`

You are not in the live system. Check you booted the ISO rather than an
installed system.

### No swap — FAIL `swap is ACTIVE`

Key material can be paged to disk. `swapoff -a`, confirm, re-run. If swap
re-enables itself, something in the image changed; do not proceed.

### Air gap — FAIL `interface X is UP` / `a default route exists`

A cable is plugged in, or a radio is live. Unplug it. If an interface stays up
with no cable, check for a USB NIC.

This is the check most likely to fire and the one least worth overriding.

### Toolchain — FAIL `missing binaries: …`

If it names something you can see in `/sbin`, the selftest's PATH is wrong —
that was a real bug, fixed by prepending `/usr/sbin:/sbin`. If the binary is
genuinely absent, the image was built without it: add it to
`config/package-lists/` and rebuild. You cannot install it here.

### Smartcard — FAIL `ykman sees the token but gpg --card-status does not`

CCID contention. `pcscd` and GnuPG's internal driver are fighting over the
token. Confirm `/etc/gnupg/scdaemon.conf` contains `disable-ccid`, then:

```sh
gpgconf --kill scdaemon
sudo systemctl restart pcscd
gpg --card-status
```

### Smartcard — WARN `no YubiKey detected`

Expected before you insert one. Insert and re-run to validate the full path
before generating anything.

### Entropy — WARN `entropy_avail` low

Move the mouse, type, wait. On hardware without an RNG this can take a minute.
`rng-tools5` and `haveged` are installed and running.

---

## archive-ceremony.sh

### FATAL `CIRCULAR: …`

Working as designed. You asked to encrypt an archive to a key that is inside
that archive. Drop `-r` and use passphrase mode, or choose a recipient that is
independently recoverable and not in the archive.

See `docs/01-recovery-model.md`. Do not work around this.

### FATAL `media is REWRITABLE`

Working as designed. A CD-RW in the tray would void the write-once guarantee
the whole archive design rests on. Replace it with a CD-R or DVD-R.

If you get `could not determine media type`, `dvd+rw-mediainfo` produced
something unexpected — the raw output is printed. Confirm by hand.

### `no terminal available; age -p requires one`

`age` reads passphrases from `/dev/tty` by design and cannot be piped. Run
`archive-ceremony.sh` interactively, not from a script, cron job, or pipeline.

### Decryption fails at the round-trip check

The passphrase you typed does not match what encrypted the archive — meaning
your paper copy is wrong. The script prints the generated passphrase at this
point so you can correct the transcription. This is the check working: it
caught the error in the room rather than at recovery in ten years.

### FATAL `not air-gapped`

Same as the selftest air-gap failure.

### `could not verify non-interactively`

`age` wanted the passphrase on a terminal. Verify by hand before burning:

```sh
age -d -o /dev/null /tmp/archive.*/payload.tar.age
```

Do not burn until this succeeds.

### `DISC DOES NOT MATCH SOURCE`

The burn completed but produced a bad disc. Discard it — physically destroy it,
since it may contain a partial copy of the ciphertext — and burn another. If it
recurs, suspect the media or the drive.

---

## rehearse-recovery.sh

### `decryption FAILED`

Either the shares were transcribed incorrectly, or the passphrase differs from
what was used. **Fix this now.** You still have the plaintext in tmpfs; after
power-off you do not.

Re-read the shares carefully — `0`/`O` and `1`/`l`/`I` are the usual culprits.
If the shares are wrong, re-split from the scratch-paper passphrase and
re-transcribe.

### `checksum mismatch after extraction`

The archive decrypted but its contents do not match what was recorded. Suspect
media. Burn a new disc and rehearse again.

### `no README.md on disc`

The disc will be unusable by anyone without context. Re-burn with the docs
included.

---

## Build

### `FAIL: <iso> predates this build`

An ISO from an earlier build is still in the tree and this build did not
produce a new one. Do not ship it. `make clean` (or `make purge` if the suite
changed) and build again.

### `make test` fails after a change

Read which case. `40-docs` failing usually means a doc was added or renamed in
one of the three locations but not the others. `50-repo-hygiene` failing on
executable bits means `make fix-modes`.

## Boot

### `Authentication failure` at autologin

`user-setup` is missing from the image. It is only a *Recommends* of
`live-config`, and `--apt-recommends false` drops it. Add `user-setup` to
`config/package-lists/ceremony.list.chroot` and rebuild.

### `Permission denied` running a ceremony script

The executable bit was lost, usually copying files between machines or through
a filesystem that does not preserve modes. Fix in the source tree and rebuild:

```sh
chmod +x config/includes.chroot/usr/local/bin/*
```

The build hook now fails on this, so a fresh image cannot have the problem.
