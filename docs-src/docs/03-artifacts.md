# Artifacts

Every physical and digital object this system produces or depends on: what it
is, what it is for, what it can and cannot recover, and what gets printed.

An artifact whose purpose nobody remembers is functionally lost — record each
one on the durable inventory, `docs/11-inventory.md`, as you produce it.

---

## Hardware tokens

Four YubiKeys, Series 5 only, firmware 5.7 or later. Buying and verifying them
is a prerequisite, not a ceremony step — see `docs/02-prerequisites.md`, which
also explains why firmware 5.7 is a hard floor.

### Key 1 — daily carry

| | |
|---|---|
| Holds | OpenPGP signing/auth/encrypt subkeys, FIDO2 passkeys |
| Used for | Day-to-day signing, SSH auth, web passkeys |
| Location | On your person |
| If lost | Revoke subkeys, reprovision from the GPG master key |
| Recoverable from | Key 2 (identical), or master key + `docs/04` |

Expected to be lost eventually. Everything on it is replaceable — that is the
design.

### Key 2 — daily backup

| | |
|---|---|
| Holds | Identical provisioning to Key 1 |
| Location | Location A — secured, at home |
| Purpose | Continue working the same day Key 1 is lost |

Provision at the same time as Key 1, from the same master key, in one ceremony.

### Key 3 — certificate authority

| | |
|---|---|
| Holds | SSH user CA (PIV slot 9c), SSH host CA (PIV slot 9a), age identity |
| Used for | Signing SSH certificates; decrypting SOPS-encrypted state |
| Location | Daily-use storage — not part of the 2-of-3 split |
| Twin | Location B — off-site, **same CA keys** (imported), own PIN/PUK/mgmt key |
| If both lost | Rebuild CAs from the encrypted archive; reissue all certificates |

The most consequential key. Both CA slots require a PIN on every operation
(`--pin-policy=always`). They differ on **touch**: slot 9a (host CA) requires a
touch every time — host certificates are signed rarely, once per host per year;
slot 9c (user CA) caches the touch for 15 seconds — user certificates are
signed in batches and the cache makes a run workable.

The CA private keys are generated off-card and are in the encrypted archive.
See `docs/05-ssh-ca.md`.

### Key 4 — break-glass

| | |
|---|---|
| Holds | FIDO2 only, no PIV, no OpenPGP |
| Used for | Account recovery when Keys 1 and 2 are both unavailable |
| Location | Location A — secured, at home |

Deliberately minimal. It exists so that losing your carry key does not lock you
out of the accounts needed to fix the situation.

---

## Digital artifacts

### age identity

| | |
|---|---|
| Form | `AGE-SECRET-KEY-…`, one line |
| Used for | SOPS decryption of Terraform state, Talos cluster CA, secrets in your infrastructure repo |
| Lives on | Key 3 (and twin), plus the encrypted archive |
| Recovers | Talos CA, SOPS-encrypted repository content |
| Recovered by | 2-of-3 passphrase shares + any ceremony CD-R |

**Never** encrypt its own backup to itself. See `docs/01-recovery-model.md`;
`archive-ceremony.sh` enforces this mechanically.

### GPG master key

| | |
|---|---|
| Form | Certify-only primary key, kept offline |
| Used for | Issuing and revoking subkeys on Keys 1 and 2 |
| Lives on | The encrypted archive only — never on a token, never on a networked machine |
| Recovers | All OpenPGP subkeys |
| Recovered by | 2-of-3 passphrase shares + any ceremony CD-R, or paperkey printout |

Only ever loaded on this air-gapped machine, in tmpfs, and never written to
persistent storage in plaintext.

### SSH CA keys

| | |
|---|---|
| Form | ECDSA P-256. Generated off-card, imported to PIV 9a (host) and 9c (user) on **both** tokens |
| Used for | Signing host and user certificates, replacing `authorized_keys` fleet-wide |
| Lives on | Both tokens, and the encrypted archive (private keys, PEM) |
| Recovers | Nothing else — they are leaves |
| Recovered by | Either token, **or** 2-of-3 passphrase shares + any ceremony CD-R |

Off-card generation because the off-site twin must carry the **same** CA key
and a YubiKey cannot export one generated on it. The keys are archived, so
losing both tokens is a re-import from the archive, not a fleet-wide
certificate reissue. Full procedure: `docs/05-ssh-ca.md`.

### PIV secrets (PIN, PUK, management key)

| | |
|---|---|
| Form | One set **per token** — 8-digit PIN, 8-digit PUK, random management key |
| Generated | During the SSH CA ceremony, off the factory defaults, before import |
| Lives on | The token, and the encrypted archive (`piv-<serial>-secrets.txt`) |
| Recovered by | 2-of-3 passphrase shares + any ceremony CD-R |

The management key is required to re-import CA keys to a replacement token.
Losing it with both tokens gone means the CAs must be regenerated and every
certificate reissued — which is why it is archived alongside the CA keys, as
one bundle.

### Talos cluster CA

| | |
|---|---|
| Form | In Terraform state, SOPS-encrypted to the age identity |
| Recovered by | The age identity |
| Acceptable dependency? | Yes — a cluster is rebuildable |

Cannot be held on a YubiKey by design; Talos needs it non-interactively.

---

## Printed material

Paper outlives media formats, does not require electricity, and cannot be
remotely altered. It is also readable by an executor who has none of your
tooling.

| Printout | Contents | Copies | Where |
|---|---|---|---|
| Passphrase share A | One `ssss` share, handwritten + QR | 1 | Location A |
| Passphrase share B | One `ssss` share, handwritten + QR | 1 | Location B |
| Passphrase share C | One `ssss` share, handwritten + QR, **plus instructions** | 1 | Location C |
| Recovery procedure | `docs/` printed | 2 | With each CD-R |
| paperkey output | GPG master key secret portion | 1–2 | Locations A and B |
| BitLocker recovery keys | One per encrypted volume | 1 | Location A |
| Durable inventory | `docs/11-inventory.md`, filled in | 2 | Locations A and B |
| Planning worksheet | `docs/02-prerequisites.md`, filled in | 1 | Location A |

The share cards are cut from `docs/10-worksheet.md`; the inventory and the
planning worksheet are separate documents so that no single page carries both
a passphrase and the address of a disc.

Locations A, B and C are defined in `docs/02-prerequisites.md`, which is also
where the real places get written down. Distribution and estate planning:
`docs/06-storage.md`.

### On the Location C share

A hex string with no context will be thrown away. Include, in plain language:
what it is, that it is useless alone, who to give it to, and under what
circumstances. Seal it.

### On BitLocker recovery keys

Flagged separately because it is easy to miss: Microsoft has no estate-planning
mechanism, and keys escrowed to a Microsoft account are unreachable after death.
If they are not on paper, they do not exist for your executor. Print them.

### On QR codes

Add a QR alongside every handwritten share:

```sh
qrencode -o /tmp/share-a.png -s 8 "<share text>"
```

Handwriting is the fallback if the print fades; the QR is the fallback if the
handwriting is ambiguous. Neither is a single point of failure.

---

## Media

| Medium | Holds | Lifetime | Notes |
|---|---|---|---|
| Ceremony CD-R | `payload.tar.age` + docs | Decades if stored dark and cool | Write-once; cannot be securely erased |
| Environment ISO | This system | Rebuildable from the config repo at any time | Contains no secrets |
| YubiKey | See above | Indefinite, but firmware is fixed at manufacture | Cannot be backed up — only duplicated at provisioning time |

Re-verify CD-Rs annually. Dye degrades, and you want to discover that while you
still have the material to burn a replacement.

---

## The record

None of the above is any use if nobody remembers what it was for. Two separate
sheets carry that, and they are separate on purpose:

| Sheet | Holds | Secret? |
|---|---|---|
| `docs/11-inventory.md` | Serials, public keys, fingerprints, which location holds what | No — store it with the discs |
| `docs/02-prerequisites.md`, planning worksheet | Which real place is Location A, B and C | No keys, but it maps labels to places — keep it at Location A |

Fill the inventory in during the ceremony and print two copies, for Locations A
and B. It is the document an executor actually reads.

The third sheet, `docs/10-worksheet.md`, carries the passphrase and the shares
and does **not** survive the ceremony intact — its scratch page is destroyed in
the room and its share cards leave separately.
