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

| Location | Holds | Threat it addresses |
|---|---|---|
| Home safe | CD-R 1, share A, paperkey, BitLocker keys, inventory | Everyday loss, theft of loose items |
| Bank safety deposit box | CD-R 2, share B, Key 3 twin, inventory | House fire, flood, burglary |
| Trusted family member | Share C, sealed, with instructions | Both of the above at once; your death |
| Gun safe | Key 2, Key 4 | Quick access, physically secured |
| Desk drawer | Key 3 | Daily CA operations |

### Why no location is sufficient alone

- Home safe: CD-R + one share = 1 of 2 needed. Cannot decrypt.
- Bank box: CD-R + one share = 1 of 2 needed. Cannot decrypt.
- Family member: one share, no ciphertext. Cannot decrypt.

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
If they are not on paper in the home safe, your executor cannot read your disks.
Print them.

---

## Maintenance schedule

| Interval | Task |
|---|---|
| Annually | Verify each CD-R reads and checksums cleanly |
| Annually | Confirm all three shares are still where the inventory says |
| Annually | Confirm the family member still has theirs and knows what it is |
| On any key rotation | Full ceremony, new discs, new shares, destroy the old |
| On any life change | Re-read the estate section; update the named contact |

Verifying media annually is not paranoia — dye degrades, and you want to find
out while you still hold the material to burn a replacement.

---

## Inventory

The fill-in-the-blanks inventory lives in `docs/02-artifacts.md`. Print two
copies, one for the home safe and one for the bank box. Nothing in it is
secret; it is public keys, serial numbers, and locations. It is exactly what an
executor needs and exactly what an attacker gains nothing from.
