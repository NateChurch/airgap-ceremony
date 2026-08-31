# Prerequisites

What must exist before you boot this image. Read it in advance — most of what
follows takes days to arrange, and none of it can be arranged from a machine
with no network.

The ceremony itself is short. The decisions below are the part that is hard to
change afterwards: once key material is on a token and a disc is burned, moving
a share to a different location means a new ceremony.

---

## The three locations

Everything in these documents refers to **Location A**, **Location B** and
**Location C**. They are roles, not places. What matters is the property each
one holds, not what kind of container it is.

| | Property it must have | Typical form |
|---|---|---|
| **A** | Reachable by you today, secured against casual theft, at home | A safe or locked cabinet where you live |
| **B** | Survives the total loss of Location A — fire, flood, burglary — and is not on the same premises | A safety deposit box, or a safe at another property you control |
| **C** | Held by a person who is not you, who can be reached after your death | A trusted individual, given a sealed envelope |

A fourth place appears in the tables and is **not** part of the split:

| | Property | Typical form |
|---|---|---|
| **Daily-use storage** | Wherever the working CA token lives between signings | A desk, a drawer, a bag |

### Why exactly this shape

The passphrase is split 2-of-3 (`ssss`), one share to each of A, B and C. The
encrypted discs are copied to A and B. So:

- **A alone** holds ciphertext and one share. One of two. Cannot decrypt.
- **B alone** holds ciphertext and one share. One of two. Cannot decrypt.
- **C alone** holds one share and no ciphertext. Cannot decrypt.
- **Any two** recover everything.

That is the whole design. Verify it still holds after any change you make to
the distribution — it is easy to break by accident and the break is invisible
until the day it matters.

### Choosing them well

**A and B must fail independently.** A safe in the house and a fire box in the
garage are the same location for this purpose: one fire takes both. If a single
plausible event destroys or seizes both, you have a 1-of-2 scheme with extra
steps.

**C must be a person, not a place.** The point of C is that it survives events
that take out both of your own locations, including your death. A storage unit
you rent is a third place, not a third party — nobody opens it when you are
gone. Choose someone who will still be reachable in ten years, who can keep a
sealed envelope sealed, and who is not the person most likely to be affected by
the same house fire.

**The Key 3 twin must not live with a share.** The twin token can sign as your
CA on its own. A location holding both the twin and enough shares to rebuild
the passphrase can recover everything unaided, which defeats the split.
`ceremony-ssh-ca.sh` asks where the twin goes and where each share goes, and
**refuses to proceed** if the twin's location matches any share's. Decide this
before you start; the script will not let you improvise it. See
`docs/05-ssh-ca.md`.

**Blank answers count as failures.** An unrecorded location cannot be checked
against the others, and cannot be found by an executor. If you do not know
where something is going, you are not ready to run the ceremony.

Distribution, estate planning and the annual maintenance schedule: see
`docs/06-storage.md`.

---

## Hardware

| Item | Quantity | Notes |
|---|---|---|
| YubiKey 5 series | 4 | Firmware **5.7 or later**. See below |
| Blank CD-R | 2+ per ceremony | **CD-R, not CD-RW.** Buy spares; burns fail |
| Optical drive, writing | 1 | USB is fine. Verify it burns, not just reads |
| USB stick for the ISO | 1 | Removed after boot; `toram` is in effect |
| The ceremony machine | 1 | See below |

**Firmware 5.7+ is a requirement, not a preference.** EUCLEAK
(CVE-2024-45678) affects earlier firmware, and YubiKey firmware cannot be
updated after manufacture — a key that ships old stays old. Buy direct from
Yubico so the supply chain is short. The Security Key, Bio and FIPS lines are
excluded: they lack the PIV or OpenPGP applets used here.

**Check the firmware before the ceremony, not during it.** `ykman info` on any
networked machine reports it. A token that turns out to be 5.4 when you are
already in the room costs you the session.

**The machine** needs roughly 4 GB of RAM for `toram`, no fixed disk it can
accidentally write to (or one you are willing to leave untouched), and a
physical way to be offline — an unplugged cable, not a disabled interface.
`ceremony-selftest` verifies the air gap on boot; see
`docs/07-troubleshooting.md` for what each failure means.

---

## Paper and printing

Everything that leaves the room leaves on paper. Bring:

- **Pens** that do not smear. Shares are transcribed by hand and read back
  years later.
- **Blank paper** for the scratch section of the worksheet.
- **Three envelopes that can be sealed** — one per share. The Location C
  envelope also carries its instruction card.
- **A shredder or a way to burn paper**, for the scratch page. It carries the
  full passphrase and must not leave the room intact.

Printing is **not installed by default** — it adds 200–250 MB for a capability
most ceremonies never use, and it is a build-time option. If you want to print
the worksheet, the inventory or a QR code on the ceremony machine, you must
enable it *before you build the image*: see `docs/12-appendix.md`, "Printing
from the command line".

Without a printer, print the blank forms from any ordinary machine beforehand
and fill them in by hand. That is the common case and it is fine. What must
**never** happen is carrying secret material to another machine to print it —
that puts plaintext on that machine's spool.

---

## The printed forms, and when each is used

Three separate forms, with three different lifetimes. They are deliberately
separate documents: a single page holding both the passphrase and where a disc
lives defeats the split for anyone who finds it.

| Form | Printed | Filled in | Ends up |
|---|---|---|---|
| **Planning worksheet** (below) | Before the ceremony | Now, at your desk | Destroyed, or kept with the inventory — it holds no secrets |
| **Ceremony worksheet** (`docs/10-worksheet.md`) | Before the ceremony | During, in the room | Scratch page destroyed in the room; share cards leave separately |
| **Durable inventory** (`docs/11-inventory.md`) | Before the ceremony | During and after | Two copies, Locations A and B, stored with the discs |

Print all three before you boot.

---

## People

**The Location C holder** needs to be asked, in advance, whether they are
willing. Do not surprise someone with a sealed envelope.

They do not need to understand any of this. The instruction card in their
envelope (`docs/10-worksheet.md`, share card C) tells them what they hold,
that it is useless alone, and who to contact. Their only obligations are to
keep it, not to open it, and to be findable.

**Your executor** needs to be able to act without any of your context. The
durable inventory is the document written for them. Confirm they know it
exists and where the copies are.

---

## Before you boot — final check

- [ ] Four YubiKeys, Series 5, firmware ≥ 5.7, verified with `ykman info`
- [ ] Blank CD-Rs on hand, confirmed CD-R and not CD-RW
- [ ] Locations A, B and C decided, and A and B fail independently
- [ ] Location C holder asked and willing
- [ ] Key 3 twin's location decided, and it is **not** a share location
- [ ] Planning worksheet below, filled in
- [ ] Ceremony worksheet and inventory printed, blank
- [ ] Pens, envelopes, and a way to destroy paper
- [ ] `make dry-run` performed at least once with sacrificial material
- [ ] `docs/01-recovery-model.md` read

The dry run is not optional the first time. It is the cheapest place to
discover that your handwriting is ambiguous or that the drive does not burn.

================================================================================

PLANNING WORKSHEET
Fill this in BEFORE the ceremony. Nothing on it is secret.

================================================================================

Planned ceremony date: ____________________

Operator:              ____________________

## Locations

Write the real place. "Location A" is the label used in the documents; this
sheet is the only place the two are connected, which is why it holds no key
material.

Location A — secured, at home, reachable today

  Real place:   ________________________________________________________

  Will hold:    CD-R 1, share A, Key 2, Key 4, paperkey, BitLocker keys,
                inventory copy 1

Location B — off-site, survives the loss of Location A

  Real place:   ________________________________________________________

  Will hold:    CD-R 2, share B, Key 3 twin, inventory copy 2

  Independent of Location A? A single fire, flood or burglary
  cannot take both:                                              [ ] confirmed

Location C — a trusted person, reachable after your death

  Holder:       ________________________________________ (name)

                ________________________________________ (phone)

                ________________________________________ (email)

  Asked, and willing to hold a sealed envelope:                  [ ] yes

  Will hold:    Share C, sealed, with its instruction card

Daily-use storage — where Key 3 lives between signings. Not part of the split.

  Real place:   ________________________________________________________

## Twin separation check

`ceremony-ssh-ca.sh` will ask for these and stop if they collide. Answer with
the same wording here that you will type at the prompt.

  Key 3 twin goes to:      ______________________________________________

  Share A location:        ______________________________________________

  Share B location:        ______________________________________________

  Share C holder:          ______________________________________________

  The twin's location matches none of the three shares:          [ ] confirmed

## Hardware

  Key 1 (daily carry)     purchased [ ]   firmware ≥5.7 verified [ ]

  Key 2 (daily backup)    purchased [ ]   firmware ≥5.7 verified [ ]

  Key 3 (CA)              purchased [ ]   firmware ≥5.7 verified [ ]

  Key 3 twin (CA, off-site) purchased [ ] firmware ≥5.7 verified [ ]

  Key 4 (break-glass)     purchased [ ]   firmware ≥5.7 verified [ ]

  Blank CD-Rs, quantity: ______   confirmed not CD-RW [ ]

  Optical drive confirmed able to WRITE, not just read:          [ ] confirmed

## Materials

  [ ] Pens                        [ ] Three sealable envelopes

  [ ] Blank paper                 [ ] Shredder or a way to burn paper

  [ ] Ceremony worksheet printed, blank  (`docs/10-worksheet.md`)

  [ ] Durable inventory printed, blank   (`docs/11-inventory.md`)

## Readiness

  [ ] `docs/01-recovery-model.md` read

  [ ] `make dry-run` completed with sacrificial material — date: __________

  [ ] Executor told the inventory exists and where the copies will be

--------------------------------------------------------------------------------

This sheet connects the labels to the real places, so treat it as sensitive
even though it holds no keys: someone who has it knows where to go. It is safe
to file with the durable inventory at Location A, and it should not travel.

================================================================================
