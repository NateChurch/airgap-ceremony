# Ceremony worksheet

Print this before you start (`ceremony-guide --print 7`). It has three parts
with different lifetimes — do not treat it as one sheet. Cut along the rule
lines and separate the parts as you finish each ceremony:

- **Section 1 — SCRATCH.** Working notes needed only during the ceremony.
  Destroyed before you leave the room.
- **Section 2 — SHARE CARDS.** One card per passphrase share. Separated
  immediately and sent to three different locations. Never stored together,
  and never stored with Section 1 or with each other.
- **Section 3 — DURABLE INVENTORY.** Contains nothing secret. Safe to store
  alongside the discs, and the sheet an executor actually needs.

A page holding both the full passphrase and where a disc lives defeats the
2-of-3 split — anyone who finds it has everything. Keeping these separate is
the entire point of this worksheet.

================================================================================
SECTION 1 — SCRATCH
***DESTROY THIS PAGE BEFORE LEAVING THE ROOM***
================================================================================

## Ceremony

Date: __________________________   Operator: __________________________

## Passphrase (write it twice, then compare)

`archive-ceremony.sh` shows the passphrase once. Write it below immediately.
Then, without looking at the first line, write it again on the second line —
this is a transcription check, not a formality; it is how you catch a
misread character while the plaintext still exists in tmpfs.

First write:

________________________________________________________________________

________________________________________________________________________

Second write (write this without looking at the line above):

________________________________________________________________________

________________________________________________________________________

Compared character by character, the two match:   [ ] yes

## Shares, as `ssss-split` emits them

Note which lettered share is which as they print, before copying each one onto
its own Section 2 card.

Share A: ________________________________________________________________

Share B: ________________________________________________________________

Share C: ________________________________________________________________

## Rehearsal

`rehearse-recovery.sh` run against device: __________________

Result:   [ ] PASS      [ ] FAIL

If FAIL: fix it now, while the material is still in tmpfs. See
`docs/05-troubleshooting.md`. Do not leave the room on a FAIL.

## SSH CA ceremony only (`ceremony-ssh-ca.sh`)

Token 1 serial: ______________   Token 2 (twin) serial: ______________

Throwaway user + host certificate signed and verified:

  Token 1:  [ ] yes        Token 2:  [ ] yes

Recovery proof — recovered CA key matches BOTH tokens:   [ ] yes

Both boxes on each line must be ticked. One good token is a failed ceremony.

--------------------------------------------------------------------------------
***DESTROY THIS PAGE BEFORE LEAVING THE ROOM — shred or burn it; do not file it
with anything else on this worksheet***
================================================================================


SECTION 2 — SHARE CARDS
Cut apart. Each card leaves the room separately, in a different direction.
================================================================================

## Share card — A

This is passphrase share **A of 3**. The threshold is **2 of 3** — this card
by itself recovers nothing and is safe to hold even if someone sees it.

Share text (copy exactly, character by character):

________________________________________________________________________

________________________________________________________________________

QR code (write the share by hand regardless; the QR is a fallback if the
handwriting becomes ambiguous, not a replacement for it):

    [                                        ]
    [                                        ]
    [                                        ]
    [                                        ]

Goes to:  Location A  —  real place: __________________________________

To recover anything, this share must be combined with **one of** Share B or
Share C. If asked to produce this share, confirm the request is from the
operator or the named contact below, then hand it over — do not transmit it
electronically.

Contact for recovery: __________________________________________________

--------------------------------------------------------------------------------

## Share card — B

This is passphrase share **B of 3**. The threshold is **2 of 3** — this card
by itself recovers nothing and is safe to hold even if someone sees it.

Share text (copy exactly, character by character):

________________________________________________________________________

________________________________________________________________________

QR code:

    [                                        ]
    [                                        ]
    [                                        ]
    [                                        ]

Goes to:  Location B  —  real place: __________________________________

To recover anything, this share must be combined with **one of** Share A or
Share C. If asked to produce this share, confirm the request is from the
operator or the named contact below, then hand it over — do not transmit it
electronically.

Contact for recovery: __________________________________________________

--------------------------------------------------------------------------------

## Share card — C

**Read this even if you have no technical background. You may be reading it
long after it was written, including after the operator's death.**

This card holds one of three pieces needed to recover an encrypted backup
belonging to:  __________________________________ (operator's name)

**This piece is useless by itself.** It cannot be used to read, unlock, or
recover anything on its own — it must be combined with one more piece like it,
which is held somewhere else.

What this is for: the operator keeps important digital keys backed up in a
form that nobody — including the operator — can lose access to by accident.
That backup is deliberately split into three pieces so that no single loss,
theft, or single point of failure destroys it. You are holding one piece.

When this gets used:

- The operator has died, or
- The operator asks you for it directly, or
- The other two storage locations have both become unavailable at once
  (for example, a fire and a burglary)

What to do:

1. Do not attempt to use this yourself, and do not read it aloud or send a
   photo of it to anyone electronically.
2. Contact the person below. They hold, or know how to obtain, a second share
   and a copy of the encrypted disc.
3. Give them this card in person, or through a trusted, verified channel.

Contact:  __________________________________ (name)

          __________________________________ (phone)

          __________________________________ (email)

Share text (copy exactly, character by character):

________________________________________________________________________

________________________________________________________________________

QR code:

    [                                        ]
    [                                        ]
    [                                        ]
    [                                        ]

Threshold reminder: **2 of 3 shares are required.** Holding this card alone
recovers nothing. Keep it sealed and stored safely, and tell no one but the
contact above where it is.

================================================================================


SECTION 3 — DURABLE INVENTORY
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

## Your locations (see `docs/04-storage.md`)

Location A — frequently accessed, physically secured, at home

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

[ ] Section 1 (scratch page carrying the full passphrase) was destroyed

[ ] Second CD-R burned and stored at the location above

[ ] Annual re-verify date set: __________________

SSH CA ceremony only:

[ ] Both tokens signed and verified; recovery proof matched both

[ ] Key 3 twin location differs from every passphrase-share location
    (`ceremony-ssh-ca.sh` refuses to proceed otherwise — tick to confirm
    you did not work around it)

## Notes

________________________________________________________________________

________________________________________________________________________

________________________________________________________________________

Nothing above this line is secret — it is public keys, serial numbers, dates,
and where things are. That is exactly why it can be printed, stored openly
alongside the discs, and handed to an executor who has none of your other
context.
