# Appendix: manual command reference

This machine has no network and no way to install anything mid-ceremony. If a
wrapper script is unavailable, or you need to reproduce or verify one step by
hand, these are the raw commands underneath it.

**This appendix is for backup and verification purposes, not a replacement
for the scripts.** `archive-ceremony.sh` and `rehearse-recovery.sh` run these
same operations plus the checks that make them safe: the circularity check,
a round-trip decrypt before burning, and a byte-identical read-back after.
Where a command below has a matching script step, that note is included —
prefer the script; use the raw command to inspect a single step, to recover
on a future machine that only has the underlying tools installed, or because
the script itself is what's failing.

---

## Printing from the command line

Printing is not installed by default — it adds ~200-250 MB for a capability
most ceremonies never use. It is a build-time option, not something you can
add on the running system.

### Enabling it (before you build the image)

```sh
mv config/package-lists/printing.list.chroot.disabled \
   config/package-lists/printing.list.chroot
make purge && make build
```

See `docs/06-image-build.md` for the full build procedure. Do this in
advance — you cannot install a package on the booted ceremony machine.

### Checking the printer is seen

```sh
systemctl status cups        # start it if inactive: systemctl start cups
lpinfo -v                    # every device CUPS can currently see
ls /dev/usb/lp*              # kernel-level check, independent of CUPS
dmesg | tail -30             # confirm the USB device enumerated at all
```

### Adding it

```sh
lpinfo -m | grep -i <printer-make>        # find a matching driver
lpadmin -p ceremony -E \
  -v <device-uri-from-lpinfo-v> \
  -m <driver-from-lpinfo-m>
lpstat -p -d                              # confirm idle, set default
```

### Printing pages, including the guide

```sh
ceremony-guide --print 7 > worksheet.txt   # raw text, no ANSI -- see ceremony-guide -h
lp worksheet.txt
lpr worksheet.txt                          # older alias, same daemon
lpq                                        # see the queue
cancel <job-id>                            # or: lprm <job-id>
```

*(script: `ceremony-guide`'s `--print`/`-w` flag produces the text these
commands send to the printer — the flag itself does not print anything. The
commands above are the rest of the path, for backup purposes if you're
printing outside of a simple pipe.)*

### Printing images, including QR codes

```sh
qrencode -o /tmp/share-a.png -s 8 "<share text>"
lp /tmp/share-a.png
```

*(script: none — the QR step is a manual part of the ceremony described in
`docs/02-artifacts.md`, "On QR codes". Printed here for backup purposes:
this is the command that gets the generated image onto paper.)*

### No printer attached — write a portable file instead

```sh
enscript -o worksheet.ps worksheet.txt
ps2pdf worksheet.ps worksheet.pdf
```

Only do this for material that is **not** secret (the blank worksheet, the
docs). Anything containing key material — a passphrase share, a paperkey
printout, a BitLocker key — must print on a printer directly attached to
this air-gapped machine. Carrying it to another machine to print puts
plaintext on that machine's spool; see the rationale comment in
`config/package-lists/printing.list.chroot.disabled`.

---

## The optical drive: checking, reading, verifying media, burning

### Confirm the drive is present and responding

```sh
lsblk                                  # /dev/sr0 should be listed, type "rom"
cat /proc/sys/dev/cdrom/info | head -20   # kernel driver: name, write capabilities
dmesg | grep -i -E 'sr0|cdrom'
xorriso -indev /dev/sr0 -toc           # reads the table of contents; fails loudly if the drive can't respond
```

### Telling CD-R from CD-RW before you trust a disc

A CD-RW can be silently rewritten later; a CD-R cannot. This project requires
CD-R specifically (see `AGENTS.md` invariant on write-once media) — verify
before you burn or before you trust an unlabeled disc someone hands you.

```sh
xorriso -as cdrecord dev=/dev/sr0 -atip
```

Look for `Is not erasable` (CD-R — correct) versus `Is erasable` (CD-RW — do
not use for a ceremony archive). Or, more directly:

```sh
dvd+rw-mediainfo /dev/sr0
```

States the media type in plain text, e.g. `Mounted Media: 09h, CD-R`.

*(script: none — `archive-ceremony.sh` assumes `/dev/sr0` already holds
blank write-once media and does not check the media type itself. Run this by
hand before every burn, and whenever you re-verify an old disc per the
"re-verify CD-Rs annually" note in `docs/02-artifacts.md`.)*

### Reading a disc / verifying its contents

```sh
mount -o ro /dev/sr0 /mnt
ls /mnt
cmp /mnt/payload.tar.age <expected-file>
umount /mnt
```

*(script: `archive-ceremony.sh`, "Read-back verification" step, and
`rehearse-recovery.sh`, "Mount" step. This is the manual form of what both
already do automatically — useful for backup purposes such as re-checking a
disc a year later without running a full rehearsal.)*

### Burning manually

```sh
xorriso -as mkisofs -R -J -V "LABEL" -o /tmp/out.iso /path/to/staged/files
xorriso -as cdrecord -v dev=/dev/sr0 /tmp/out.iso
```

*(script: `archive-ceremony.sh`, "Disc image" and "Burn" steps. Prefer the
script — it also runs the circularity check, the pre-burn round-trip
decrypt, and the post-burn read-back that the raw commands above do not.)*

### Ejecting

```sh
xorriso -outdev /dev/sr0 -eject out
```

No `eject` binary ships on this image. The tray's physical button also
works.

---

## Manual encrypt / decrypt

Same caveat as above, more so: these are the operations the circularity
check and round-trip verification exist to guard. Prefer
`archive-ceremony.sh` / `rehearse-recovery.sh`. Use the raw commands to
verify a single ciphertext, or to recover on a future machine that has only
`age` and `ssss` installed — which is exactly the scenario
`docs/03-ceremonies.md`'s "Recovery" section describes.

### Encrypt with a passphrase (the default)

```sh
age -p -o payload.tar.age payload.tar
```

*(script: `archive-ceremony.sh`, "Encryption" section, passphrase branch.)*

### Encrypt to a recipient (opt-in)

```sh
age -r <recipient-public-key> -o payload.tar.age payload.tar
```

Do not run this by hand without first confirming the recipient's private
identity is not itself inside the archive you are encrypting — that is
exactly what `assert_not_circular` in `usr/local/lib/ceremony-lib.sh` exists
to catch automatically when you use the script instead. See
`docs/01-recovery-model.md`.

*(script: `archive-ceremony.sh`, "Encryption" section, recipient branch; the
circularity check itself lives in `ceremony-lib.sh`.)*

### Decrypt

```sh
age -d -o payload.tar payload.tar.age                        # passphrase: prompts
age -d -i age-identity.txt -o payload.tar payload.tar.age    # recipient mode
```

*(script: `rehearse-recovery.sh`, "Decrypt" step; also
`docs/03-ceremonies.md`, "Recovery" step 4 — the form meant for a future
machine that isn't this image at all.)*

### Split / reconstruct a passphrase

```sh
printf '%s' "<passphrase>" | ssss-split -t 2 -n 3 -w ceremony
ssss-combine -t 2
```

*(script: `archive-ceremony.sh`, "Passphrase shares" step; `rehearse-recovery.sh`,
"Reconstruct the passphrase" step.)*

### Verify a checksummed archive

```sh
sha256sum -c SHA256SUMS.txt
```

*(script: `rehearse-recovery.sh`, "Extract and verify" step.)*

### GPG master key backup (paperkey)

```sh
gpg --export-secret-keys --armor <KEYID> > gpg-master-secret.asc
gpg --export-secret-keys <KEYID> | paperkey --output gpg-master-paperkey.txt
```

*(script: none — a manual ceremony step, described in `docs/03-ceremonies.md`,
Ceremony B. Included here because paperkey output is, along with the
passphrase shares, one of the two things this whole appendix exists to help
you reproduce or verify by hand for backup purposes.)*
