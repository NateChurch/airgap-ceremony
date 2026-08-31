# Storage and distribution

Where every artifact physically lives, and why the distribution is shaped this
way.

---

## The principle

**Ciphertext replicates freely. Secrets are split.**

Durability and confidentiality want opposite things. More copies means better
survival and worse secrecy. Separating the two lets each be optimised
independently:

- Encrypted archives (CD-R): copy widely. Useless without the passphrase.
- Passphrase: split 2-of-3. No single location can decrypt; losing any one
  location still recovers.

---

## Locations

**Locations A, B and C are defined in `docs/02-prerequisites.md`** — what each
must be, how to choose them well, and the planning worksheet where you write
down which real place is which. That is the document to read first; this one
covers what ends up in each and what happens over the following years.

| Location | Holds | Threat it addresses |
|---|---|---|
| A | CD-R 1, share A, Key 2, Key 4, paperkey, BitLocker keys, inventory | Everyday loss, theft of loose items |
| B | CD-R 2, share B, Key 3 twin, inventory | House fire, flood, burglary |
| C | Share C, sealed, with instructions | Both of the above at once; your death |
| Daily-use storage (not part of the split) | Key 3 | Daily CA operations |

### Why no location is sufficient alone

- A: CD-R + one share = 1 of 2 needed. Cannot decrypt.
- B: CD-R + one share = 1 of 2 needed. Cannot decrypt.
- C: one share, no ciphertext. Cannot decrypt.

Any **two** of the three recover. That is the intended property; verify it
still holds after any change to the distribution.

---

## Estate planning

Your executor has none of your context. Assume they do not know what a YubiKey
is.

Each of the three share locations should carry a sealed envelope containing:

1. What the enclosed string is
2. That it is useless alone and needs one more from a named other location
3. Who to contact
4. Where the discs are
5. A printed copy of `docs/`

Also flagged: **BitLocker recovery keys.** Microsoft provides no estate-planning
mechanism, and keys escrowed to a Microsoft account are unreachable after death.
If they are not on paper at Location A, your executor cannot read your disks.
Print them.

---

## Maintenance schedule

| Interval | Task |
|---|---|
| Annually | Verify each CD-R reads and checksums cleanly |
| Annually | Confirm all three shares are still where the inventory says |
| Annually | Confirm the Location C holder still has theirs and knows what it is |
| On any key rotation | Full ceremony, new discs, new shares, destroy the old |
| On any life change | Re-read the estate section; update the named contact |

Verifying media annually is not paranoia — dye degrades, and you want to find
out while you still hold the material to burn a replacement.

---

## Inventory

The fill-in-the-blanks inventory is its own document: `docs/11-inventory.md`.
Print two copies, one for Location A and one for Location B. Nothing in it is
secret; it is public keys, serial numbers, and locations. It is exactly what an
executor needs and exactly what an attacker gains nothing from.

It is separate from the ceremony worksheet (`docs/10-worksheet.md`) because the
worksheet carries the passphrase and does not survive the ceremony. Keeping the
durable record on a different sheet is what makes it safe to store openly with
the discs.
