# Ceremonies

Each ceremony is self-contained. Run the preflight every time — it is cheap and
the conditions it checks can change between sessions.

---

## Preflight (every ceremony)

```sh
ceremony-selftest
```

All PASS required. Then remove the USB stick — `toram` is in effect and the
medium is no longer needed.

```sh
mkdir -p /tmp/ceremony && cd /tmp/ceremony
```

---

## Ceremony A — age identity

Produces the identity used by SOPS for Terraform state and the Talos CA.

```sh
age-keygen -o age-identity.txt
age-keygen -y age-identity.txt > age-recipient.txt
cat age-recipient.txt
```

Record the public key on the durable inventory (`docs/11-inventory.md`). It is
not secret.

Load onto Key 3 and its twin per Yubico's current age/PIV guidance, then:

```sh
archive-ceremony.sh /tmp/ceremony
```

Encryption is always passphrase-based. Recipient mode was removed from the
tool: for root key material the recipient is nearly always inside the archive
(the circular case), and a mode that is usually wrong with no tested recovery
path is worse than no mode at all.

You will be prompted for the passphrase by `age`, twice. **Type it from your
paper**, not from the screen — that is what makes it a transcription check.

---

## Ceremony B — GPG master key and subkeys

Produces an offline certify-only master key plus subkeys for Keys 1 and 2.

```sh
export GNUPGHOME=/tmp/ceremony/gnupg
mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"

gpg --expert --full-generate-key      # certify-only primary, no expiry
gpg --expert --edit-key <KEYID>       # addkey: sign, encrypt, auth
```

Back up before touching any token — `keytocard` **moves** the key, it does not
copy it:

```sh
gpg --export-secret-keys --armor <KEYID> > gpg-master-secret.asc
gpg --export --armor <KEYID>            > gpg-public.asc
gpg --export-secret-keys <KEYID> | paperkey --output gpg-master-paperkey.txt
```

Then move subkeys to Key 1, and repeat for Key 2 from the same backup:

```sh
gpg --edit-key <KEYID>                # key 1 / keytocard, key 2, key 3...
```

Archive:

```sh
archive-ceremony.sh /tmp/ceremony
```

Print `gpg-master-paperkey.txt`. It reconstructs the secret key given the
public key, which is why the public key must also be archived.

---

## Ceremony C — SSH certificate authorities

Full procedure, rationale, and troubleshooting: **`docs/05-ssh-ca.md`**. Read
it — this is a summary.

One command runs the whole ceremony, including its own archive and recovery
proof:

```sh
mkdir -p /tmp/ceremony && cd /tmp/ceremony
ceremony-ssh-ca.sh
```

It generates the host and user CA keypairs **off-card** (ECDSA P-256), imports
them to **two** YubiKeys — Key 3 and its off-site twin (Location B) — sets a
fresh PIV PIN,
PUK and management key on each, proves each token can sign by issuing throwaway
certificates and parsing them back, then archives the CA private keys and the
PIV secrets through `archive-ceremony.sh` and proves recovery before you leave.

Off-card generation is deliberate: a YubiKey cannot export a key generated on
it, and the twin must carry the **same** CA key. The private keys exist only in
tmpfs and then only inside the encrypted archive. (Earlier revisions generated
on-card and said the key "never leaves the token"; that stopped being true the
moment a twin entered the design — a twin is an import.)

Slots: host CA in **9a** (`--touch-policy=always`), user CA in **9c**
(`--touch-policy=cached`, 15s — batch signing). Both `--pin-policy=always`.

`ceremony-ssh-ca.sh` will **stop** if it sees zero card readers, more than one
card reader, or if the Key 3 twin is recorded as living in the same place as a
passphrase share. Both tokens must sign and the recovery proof must match, or
the ceremony fails.

There is no separate `archive-ceremony.sh` step for this ceremony — the script
calls it for you.

---

## Archiving and rehearsal (every ceremony)

```sh
archive-ceremony.sh /tmp/ceremony
rehearse-recovery.sh /dev/sr0
```

The rehearsal is a phase gate, not a formality. If it fails, the material is
still in tmpfs and fixable. After power-off it is not.

Burn a second copy before finishing.

---

## Recovery

What a future you, or an executor, actually does.

1. Obtain any ceremony CD-R and any **two** of the three passphrase shares.
2. On any Debian/Ubuntu machine: `apt install age ssss`
3. `ssss-combine -t 2` and paste the two shares.
4. `age -d -o payload.tar payload.tar.age` and enter the passphrase.
5. `tar -xf payload.tar && sha256sum -c SHA256SUMS.txt`

`RECOVERY.txt` on each disc repeats this in short form for someone with no
context.

Recovery does not require this ISO, this machine, or any YubiKey. That
independence is deliberate and is the property most worth preserving in any
future change to these procedures.
