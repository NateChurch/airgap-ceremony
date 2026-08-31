# Ceremony worksheet

The sheet you carry into the room. Print it blank **before** the ceremony —
either from an ordinary machine, or from this one if printing was enabled at
build time (`docs/12-appendix.md`). `ceremony-guide -r 10 > worksheet.txt`
gives you the raw text.

**Everything on this worksheet is secret.** It carries the passphrase and the
shares. It has two parts with different lifetimes — do not treat it as one
sheet. Cut along the rule lines and separate the parts before you leave:

- **Section 1 — SCRATCH.** Working notes needed only during the ceremony,
  including the full passphrase. Destroyed in the room, before you leave.
- **Section 2 — SHARE CARDS.** One card per passphrase share. Separated
  immediately and sent to three different locations. Never stored together,
  never stored with Section 1, and never stored with each other.

A page holding both the full passphrase and where a disc lives defeats the
2-of-3 split — anyone who finds it has everything. Keeping these apart is the
entire point of cutting this sheet up.

The two companion forms are deliberately **separate documents**, not sections
here, so that the secret and non-secret material never share a page:

| Form | When | Fate |
|---|---|---|
| Planning worksheet — `docs/02-prerequisites.md` | Filled in before the ceremony | Kept; holds no keys |
| **This worksheet** | Filled in during the ceremony | Section 1 destroyed, Section 2 dispersed |
| Durable inventory — `docs/11-inventory.md` | Filled in during and after | Kept with the discs; holds no keys |

Record serials, fingerprints and locations on the **inventory**, not here.

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
`docs/07-troubleshooting.md`. Do not leave the room on a FAIL.

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

--------------------------------------------------------------------------------

END OF WORKSHEET. Before you leave the room:

  [ ] Section 1 destroyed — shredded or burned, not filed
  [ ] Three share cards cut apart, sealed, and going to three different places
  [ ] Serials, fingerprints and locations written on the durable inventory
      (`docs/11-inventory.md`), which is a different sheet and stays

================================================================================
