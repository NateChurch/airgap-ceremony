# Durable inventory

The record of what exists, where it is, and how to identify it. Print two
copies, blank, before the ceremony. Fill them in as you go and complete them
before you leave the room.

**Nothing on this sheet is secret.** It is public keys, fingerprints, serial
numbers, dates and locations. That is deliberate and it is the point: it can be
stored openly alongside the discs, and it is exactly what an executor needs and
exactly what an attacker gains nothing from.

It is a separate document from `docs/10-worksheet.md` for the same reason the
worksheet is cut apart. The worksheet carries the passphrase and the shares and
is destroyed or dispersed; this sheet carries none of that and is kept. Merging
them would put a full passphrase on the one page you deliberately store with
the ciphertext.

| | |
|---|---|
| Print | Two copies, before the ceremony |
| Fill in | During the ceremony, and after any change |
| Store at | Location A and Location B, with the discs |
| Contains secrets | **No** |
| Replaces | Nothing — it is the only durable record |

An artifact whose purpose nobody remembers is functionally lost. This sheet is
what stops that.

Locations A, B and C are defined in `docs/02-prerequisites.md`; the real places
are on the planning worksheet there. Keep this sheet and that one together —
this one names labels, that one names places.

================================================================================

DURABLE INVENTORY
Contains nothing secret. Safe to store with the discs.

================================================================================

## Ceremony

Ceremony date:          ____________________

Operator:               ____________________

Image build identifier: ____________________________________________
  (from `/usr/local/share/ceremony/manifest.txt` — the `Built:` line)

## Hardware tokens

Key 1 serial:        ______________  provisioned: __________  location: on person

Key 2 serial:        ______________  provisioned: __________  location: __________

Key 3 serial:        ______________  provisioned: __________  location: __________

Key 3 twin serial:   ______________  provisioned: __________  location: __________

Key 4 serial:        ______________  provisioned: __________  location: __________

## Public keys and fingerprints (not secret)

age public key:      ________________________________________________________

GPG master fpr:      ________________________________________________________

SSH user CA fpr:     ________________________________________________________

SSH host CA fpr:     ________________________________________________________

  (SSH CA private keys and each token's PIV PIN/PUK/management key are in the
   encrypted archive, not here. Nothing on this page is secret.)

## Media

CD-R 1 label: ____________  burned: __________  location: __________________

CD-R 2 label: ____________  burned: __________  location: __________________

## Locations (see `docs/02-prerequisites.md`)

Location A — secured, at home, frequently accessed

  Real place:  ________________________________________________________

  Holds: CD-R 1, share A, Key 2, Key 4, paperkey, BitLocker keys, this inventory

Location B — off-site, disaster-resistant, infrequently accessed

  Real place:  ________________________________________________________

  Holds: CD-R 2, share B, Key 3 twin, this inventory

Location C — held by someone you trust, for when A and B are both unavailable

  Holder:      ________________________________________________________

  Contact:     ________________________________________________________

Daily-use storage — wherever Key 3 lives day to day, not part of the split

  Real place:  ________________________________________________________

## Confirmations

[ ] Rehearsal passed — date: __________________

[ ] Ceremony worksheet Section 1 (the scratch page carrying the full
    passphrase) was destroyed before leaving the room

[ ] Second CD-R burned and stored at the location above

[ ] Share cards separated and sent to three different locations

[ ] Annual re-verify date set: __________________

SSH CA ceremony only:

[ ] Both tokens signed and verified; recovery proof matched both

[ ] Key 3 twin location differs from every passphrase-share location
    (`ceremony-ssh-ca.sh` refuses to proceed otherwise — tick to confirm
    you did not work around it)

## Maintenance log

Re-verify the discs annually: dye degrades, and you want to find out while you
still hold the material to burn a replacement. Record each check.

  Date: __________  CD-R 1 reads and checksums clean [ ]   CD-R 2 [ ]

  Date: __________  CD-R 1 reads and checksums clean [ ]   CD-R 2 [ ]

  Date: __________  CD-R 1 reads and checksums clean [ ]   CD-R 2 [ ]

  Date: __________  CD-R 1 reads and checksums clean [ ]   CD-R 2 [ ]

  Date: __________  All three shares confirmed present where recorded [ ]

  Date: __________  All three shares confirmed present where recorded [ ]

  Date: __________  Location C holder confirmed, still has theirs, knows
                    what it is [ ]

  Date: __________  Location C holder confirmed, still has theirs, knows
                    what it is [ ]

## Notes

________________________________________________________________________

________________________________________________________________________

________________________________________________________________________

Nothing above this line is secret — it is public keys, serial numbers, dates,
and where things are. That is exactly why it can be printed, stored openly
alongside the discs, and handed to an executor who has none of your other
context.

================================================================================
