# Quickstart

The short path. Full detail is in the numbered documents that follow.

## First time?

Read `docs/02-prerequisites.md` first — hardware, media, the three storage
locations, and the forms to print. Most of it cannot be arranged from this
machine, which has no network.

Then do a sacrificial run with fake material before trusting this with
anything:

```sh
make dry-run
```

## Before touching key material

```sh
ceremony-selftest
```

Every check must **PASS** or **WARN**. FAIL blocks — do not proceed. WARN is
situational and must be read: "no YubiKey detected" is expected before you
insert one; low entropy resolves by waiting. If the air-gap section fails, a
cable is plugged in or a radio is live.

Remove the USB stick. `toram` means it is no longer needed, and a removed stick
cannot be written to.

## Generate

Work in `/tmp/ceremony/`. It is tmpfs; nothing survives power-off.

See `docs/04-ceremonies.md` for the specific procedure. Do not improvise the
commands — the details matter and the failures are silent.

## Archive

```sh
archive-ceremony.sh /tmp/ceremony
```

Which will, in order: refuse if the archive would be circularly encrypted,
checksum everything, generate and display a passphrase once, encrypt with
`age -p`, split the passphrase 2-of-3, burn to CD-R, and read the disc back to
verify.

Write the passphrase on scratch paper when shown. Write each share on a
separate sheet. Destroy the scratch paper before leaving.

## Rehearse — do not skip

```sh
rehearse-recovery.sh /dev/sr0
```

Reconstruct from two paper shares and decrypt. Use the paper, not anything
still on screen — you are testing whether your handwriting is legible.

A backup you have never restored is a hypothesis.

## End

1. Confirm the rehearsal passed
2. Burn a second copy
3. Fill in the durable inventory (`docs/11-inventory.md`) — serials,
   fingerprints, which location holds what
4. Destroy the scratch paper with the full passphrase (worksheet Section 1)
5. Cut apart the share cards and send them to three different places
6. Power off — do not reboot into anything else first
