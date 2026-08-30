# SSH certificate authority ceremony

Stand up the fleet's SSH host and user CAs. One sitting, on the air-gapped
machine, with two YubiKeys and a blank CD-R.

`ceremony-ssh-ca.sh` runs the whole thing and refuses to finish unless both
tokens sign and recovery is proven. Read this first anyway — the script cannot
type your paper for you, and a room with no network is a bad place to be
guessing.

---

## What this produces

| Artifact | Where it ends up |
|---|---|
| Host CA private key (ECDSA P-256) | PIV slot **9a** on both tokens, and the encrypted archive |
| User CA private key (ECDSA P-256) | PIV slot **9c** on both tokens, and the encrypted archive |
| PIV PIN, PUK, management key | One set **per token**, in the encrypted archive |
| `ssh-ca-fingerprints.txt` | The archive (not secret — a record) |

Two tokens: Key 3 and its bank-box twin. They carry the **same** CA keys —
that is the point of a twin — but **different** PIN/PUK/management keys.

### Why off-card generation

A YubiKey cannot export a key generated on it. The twin needs the same CA key,
so the key is generated here, in tmpfs, and imported to both. It then exists
only inside the encrypted archive. This is a change from older revisions of
these docs, which generated on-card — that never actually held once a twin
entered the design, because a twin is an import.

### Why ECDSA P-256, not Ed25519

Signing goes through `ssh-keygen -D` and the ykcs11 PKCS#11 module. That path
does not do Ed25519, and neither does YubiKey PIV. P-256 is the exercised path.
Do not change it.

### Why these slots and policies

| CA | Slot | Touch | PIN | Reason |
|---|---|---|---|---|
| Host | 9a | always | always | Signed once per host per year. The touch is affordable; the PIN is a second gate. |
| User | 9c | cached (15s) | always | Signed in batches. The touch cache makes a run of certs workable. |

---

## Before you start

1. `ceremony-selftest` — all PASS. The **SSH CA (PKCS#11)** section must show:
   - `ykcs11 PKCS#11 module present`
   - `exactly one smartcard reader visible` (once a token is in)

   If it says **zero readers**, no token is seen: reseat it, try another USB
   port, check `dmesg | tail`. Do not start the ceremony without a reader.

   If it says **more than one reader**, you have more than one token (or a
   separate reader) plugged in. Remove everything except the token you are
   about to provision. The script will not guess which one you mean and will
   refuse to run.

2. Two YubiKeys in **factory PIV state**. If either has been used before:

   ```sh
   ykman -d <serial> piv reset
   ```

   This wipes all PIV data and returns PIN/PUK/management key to defaults.
   `ykman list --serials` shows the serial.

3. A blank **CD-R** (not CD-RW) in the burner.

4. The printed worksheet (`ceremony-guide --print 9`), Sections 1–3.

5. Decide the three passphrase-share locations and the twin's location **now**,
   on paper. The script will ask, and will stop if the twin's location matches
   a share's — see below.

---

## Running it

```sh
mkdir -p /tmp/ceremony && cd /tmp/ceremony
ceremony-ssh-ca.sh
```

Options: `-n` shares (default 3), `-t` threshold (default 2), `-d` burner
device (default `/dev/sr0`), `--no-burn` (write the image to `/tmp`, for a
rehearsal).

The script walks these phases. Each one stops the ceremony if it fails.

### 1. Concentration-risk check

It asks for the physical location of the Key 3 twin and of each passphrase
share. Answer with the same wording each time — "bank box", not "the bank"
once and "SDB" the next.

If the twin's location matches any share's location, it **stops**. One place
must not hold both a spare CA token and enough shares to rebuild the archive
passphrase, or that place alone recovers everything. This is not the
circularity check (`assert_not_circular`) — it is about where paper goes, and
only you know that. A blank answer also stops it: an unrecorded location cannot
be called distinct.

Fix the distribution, or record the real distinct locations, and re-run.

### 2. Key generation

Off-card, in tmpfs. Nothing to do. It prints each CA's fingerprint — write
both on worksheet Section 3.

### 3. Per token: PIN, PUK, management key — then import

For each token in turn it will say "insert token N". Insert **only** that
token.

It generates a fresh 8-digit PIN, 8-digit PUK, and a random management key,
**before** importing anything (import needs the new management key). Then it
imports both CA keys and writes a certificate into each slot.

You will not be shown these secrets on screen to transcribe — they go straight
into the archive. If you want them on paper as well, read them from the
recovered archive during the rehearsal and write them then.

### 4. Per token: verification

It signs a **throwaway** user certificate and a **throwaway** host
certificate with that token, then reads them back with `ssh-keygen -L` and
checks the principals, the validity window, and the signing-CA fingerprint
against what it intended.

- Enter the **new PIN** when prompted (the ceremony just set it; if you
  fumble it, the sign fails and the phase fails — that is the check working).
- **Touch** the token when it blinks. Slot 9a asks every time; slot 9c caches
  for 15 seconds.

A token that was imported to but never signed with is **not** verified. Both
tokens must pass. One good token is a failed ceremony.

### 5. Archive

The script hands the CA private keys and the PIV secrets to
`archive-ceremony.sh`, which runs its own flow: the circularity check,
`age -p` (you transcribe the passphrase and type it back — from your paper,
not the screen), the Shamir split, the burn, and a read-back.

Follow `docs/03-ceremonies.md` "Archiving" and the worksheet for the
passphrase and shares. Everything there applies unchanged.

### 6. Recovery proof

It runs `rehearse-recovery.sh` against the burned disc, then does one more
thing specific to this ceremony: it reconstructs the passphrase from the
**minimum** number of shares, decrypts, and checks that the CA public key
recovered from the archive is **byte-identical** to what each token reports.
It will ask you to insert each token again for this.

"The archive decrypted" is not the bar. The key in it has to be the key on the
tokens.

If this fails, **do not end the ceremony** — the material is still in tmpfs
and can be re-burned. After power-off it is gone.

### 7. Before you leave

- Burn a **second** CD-R.
- Fill in worksheet Section 3: both serials, both CA fingerprints, the twin
  location, and tick the twin-vs-share box.
- **Destroy worksheet Section 1** — it carried the passphrase.
- The CA **public** keys still need to go into the fleet's trust config. This
  ceremony does not do that.
- Power off.

---

## Recovery

You need a ceremony CD-R and any **two** of the three passphrase shares.

```sh
apt install age ssss openssh-client        # any Debian/Ubuntu machine
ssss-combine -t 2                           # paste two shares
age -d -o payload.tar payload.tar.age       # enter the passphrase
tar -xf payload.tar
sha256sum -c SHA256SUMS.txt
```

You now have `host-ca.pem` and `user-ca.pem` (the CA private keys) and
`piv-<serial>-secrets.txt` for each token (PIN, PUK, management key).

To re-provision a replacement token, you need its management key — that is why
it is archived. `ssh-keygen -y -f host-ca.pem` gives the public half if you
need to re-check a fingerprint.

Recovery needs neither this ISO nor a YubiKey. That independence is deliberate.

---

## Troubleshooting

### `ykcs11 PKCS#11 module not found`

The image was built without the `ykcs11` package. It cannot be added here.
Rebuild — see `docs/06-image-build.md`.

### `More than one reader is present`

Another token or reader is plugged in. Remove all but the one you are
provisioning. The script will not choose for you.

### The token will not import — "wrong management key" or similar

The token is not in factory PIV state. `ykman -d <serial> piv reset` and
re-run. The ceremony sets the management key from the factory default; if
something already changed it, reset is the only way back.

### Signing hangs

It is waiting for a **touch**. The token blinks. Slot 9a (host CA) needs a
touch on every signature.

### `certificate signing-CA fingerprint is ... expected ...`

The token signed with a different key than intended — usually the wrong slot
or a stale certificate in the slot. Re-run the ceremony for that token from a
`piv reset`.

### The recovery proof says the key does not match

The archive does not contain the key the tokens hold. Do not power off. Re-run
`archive-ceremony.sh` against the staged directory if it still exists, or
re-run the whole ceremony. Investigate before trusting anything.
