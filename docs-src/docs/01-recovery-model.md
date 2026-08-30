# The recovery model

Read this before generating anything. It is short, and the mistake it describes
is silent at ceremony time and total at recovery time.

---

## The one rule

> **Recovery material must never depend on the thing it recovers.**

Every catastrophic, unrecoverable key-management failure is a version of this.
The failure is silent at ceremony time and only surfaces years later, in the
exact situation the backup existed for.

Concrete ways to get it wrong, all of which look reasonable at 11pm:

| Mistake | Why it fails |
|---|---|
| Encrypt the age identity backup to its own public key | You need the identity to decrypt the identity |
| Encrypt backups to a GPG key that lives only on a YubiKey | YubiKey lost is the case you're backing up against |
| Store the passphrase in a password manager unlocked by that YubiKey | Same circle, one step longer |
| SOPS-encrypt the age identity into the fablab repo | SOPS uses that identity to decrypt |
| Keep the only copy of the passphrase on the encrypted volume | Self-evident on paper, easy to do in practice |

The failure mode is not "hard to recover." It is **unrecoverable**, and you
find out at the worst possible moment.

`archive-ceremony.sh` refuses to encrypt an archive to a recipient whose
private identity is inside that archive. That check exists because the mistake
is easy and the consequence is total.

---

## The model

Two properties are deliberately separated, because they want opposite things.

**Durability** wants many copies in many places.
**Confidentiality** wants few copies in few places.

So:

```
  SECRET  ──age -p (passphrase)──>  CIPHERTEXT  ──> copy freely
                   │                                 CD-R x2, safe, bank box
                   │
                   └─ PASSPHRASE ──ssss 2-of-3──> SHARE A: home safe
                                                  SHARE B: bank box
                                                  SHARE C: trusted family member
```

The ciphertext is safe to replicate — it is useless alone. The passphrase is
Shamir-split, so no single location can decrypt, and losing any one location
still leaves recovery possible.

**Note the deliberate crossing:** a CD-R and a passphrase share live in the
same physical box only where that is unavoidable. Bank box holds ciphertext
plus one share; home safe holds ciphertext plus one share. Either box alone is
insufficient (needs 2 shares). Both boxes together, or one box plus the family
member, recovers.

### Why `age -p` and not `age -r`

`age -p` derives the key from a passphrase via scrypt. It depends on nothing
else — no keyfile, no YubiKey, no other ceremony artifact. That independence is
the entire point.

Recipient mode has been **removed from `archive-ceremony.sh`** entirely. The
reasoning below still governs anything you build on top of this, and
`assert_not_circular` is retained and unit-tested, but the tool offers one
path so that the one path is the tested one.

`age -r <recipient>` is correct **only** when the recipient identity is
demonstrably not part of what you're encrypting, and is itself independently
recoverable. For root material during a ceremony, that is almost never true.

### Why not GPG for archives

GPG works, but `gpg --symmetric` drags in keyring state, agent behaviour, and
version-dependent defaults. `age -p` is one binary, one file format, no agent,
no state directory. In ten years, fewer things will have changed underneath it.

GPG remains correct for its own domain: OpenPGP keys on the YubiKey, signing,
`paperkey` output.

---

## What recovers what

Fill this in as you perform each ceremony. It is the map future-you needs.

| To recover | You need | Stored at | Depends on a ceremony key? |
|---|---|---|---|
| age identity (SOPS) | 2 of 3 passphrase shares + any CD-R | safe / bank / family | **No** — by design |
| SSH user CA (PIV 9c) | The twin token, **or** 2 of 3 shares + any CD-R | desk drawer / bank box / archive | **No** — by design |
| SSH host CA (PIV 9a) | The twin token, **or** 2 of 3 shares + any CD-R | desk drawer / bank box / archive | **No** — by design |
| PIV PIN / PUK / mgmt key (per token) | 2 of 3 shares + any CD-R | archive | **No** — by design |
| GPG master key | 2 of 3 shares + any CD-R | safe / bank / family | **No** — by design |
| Daily GPG subkeys | GPG master key | see above | Yes — acceptable, subkeys are replaceable |
| Talos cluster CA | age identity → SOPS state | see age identity | Yes — acceptable, cluster is rebuildable |
| Infisical secrets | Its own root credential | password manager | Separate chain — do not entangle |

The rightmost column is the one to scrutinise. "Yes" is only acceptable when
the thing being recovered is *replaceable* — subkeys can be reissued, a cluster
can be rebuilt. Root material must always read **No**.

---

## Where the rest lives

- Step-by-step procedures: `docs/03-ceremonies.md`
- Physical locations and distribution: `docs/04-storage.md`
- What each key and printout is for: `docs/02-artifacts.md`
