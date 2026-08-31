# Testing

Three tiers, deliberately. The boundary between them is the important part.

| Tier | Command | Needs | Covers |
|---|---|---|---|
| 1 | `make test` | bash; `ssh-keygen`; `shellcheck` for the SC2154 sweep (skips honestly without it — **CI must have it**) | Logic, manifests, hygiene, static analysis. Runs anywhere, including WSL and CI |
| 2 | `make test-all` | `age`, `ssss`, `script`, `ssh-keygen` | Real encrypt → split → recombine → decrypt round trip; real SSH certificate signing and verification |
| 3 | `make dry-run` | ceremony hardware, a blank CD-R, two YubiKeys for the SSH CA path | The whole procedure, including you |

---

## Why tier 3 is not automated

`age -p` reads the passphrase from `/dev/tty`, deliberately, so it cannot be
piped. An early version of `archive-ceremony.sh` did exactly that — piped a
passphrase into `age -p` — which silently does nothing useful.

A test harness that faked a terminal would have made that broken line pass.
The same applies to the burner, the media-type check, and the smartcard flows:
mocking them tests the mock.

So tier 3 sets up throwaway material, hands you the real commands, and gets out
of the way. The subject of the test is whether the procedure survives contact
with a real operator, real media, and real handwriting.

Run `make dry-run` at least once before trusting the process with anything.

---

## Tier 1 — unit

```sh
make test                    # everything
./tests/run-tests.sh 10      # one case, by numeric prefix
./tests/run-tests.sh -t 2    # promote to tier 2
```

| Case | Asserts |
|---|---|
| `10-circularity` | The refusal to encrypt an archive to a key inside it. Flat, nested, absent, and plain-text-mention cases |
| `20-media-type` | CD-R/DVD-R/BD-R classify write-once; every rewritable type never does |
| `30-recovery-text` | `RECOVERY.txt` reflects the actual `-n`/`-t`; recipient mode is gone; `age -p` is not piped |
| `40-docs` | Generated docs match `docs-src`; manifest matches; every inter-document reference resolves; generated copies are gitignored |
| `50-repo-hygiene` | Executable bits, shell syntax, gitignore coverage, the two `AGENTS.md` files are distinct |
| `55-static-lint` | Every ceremony script parses; ShellCheck `SC2154` (uppercase names included) finds no reference to an unassigned variable; `SC2154` is not suppressed inline. Guards the class of bug where a variable reference outlives the block that defined it — see `$STAGE` in `AGENTS.md` |
| `60-roundtrip` | Tier 2 only. See below |
| `70-ssh-ca` | SSH CA slot/policy derivation; concentration-risk (twin vs share) location detection; reader counting; factory-PIV-secret detection; the `ssh-keygen -L` parsers against captured output; and that `ceremony-ssh-ca.sh` types no bare slot ids or module paths and wires every invariant in |
| `71-ssh-ca-roundtrip` | Tier 2 only. See below |

Skips are honest: a case that cannot run says so and why, rather than silently
passing.

---

## Tier 2 — integration

Drives `age` through a real pseudo-terminal (`script` from util-linux) because
that is the only way to exercise the actual invocation.

Notably it asserts the **empty-passphrase trap**: decrypting with a deliberately
wrong passphrase must fail. If `age` had silently accepted a piped or empty
passphrase, that assertion is what catches it.

Also verifies that one Shamir share reconstructs nothing and two reconstruct
exactly the original.

`71-ssh-ca-roundtrip` adds a real SSH certificate round trip with no hardware:
generate a P-256 CA on disk, sign user and host certificates with `ssh-keygen`,
and drive the ceremony's `cert_*` / `assert_cert_matches_intent` /
`assert_pubkey_identical` helpers against the real `ssh-keygen -L` output —
principals, signing-CA fingerprint, type, validity. Negative cases (wrong
principal, wrong CA, wrong type, a flipped byte in the key body) are checked
first.

Still does not cover: burning, media type against real discs, the
`ssh-keygen -D` / ykcs11 signing path, PIN and touch, `ykman` against a real
token, or transcription.

---

## Tier 3 — the dry run

```sh
make dry-run
```

Generates fake key material, walks you through the complete flow with the real
scripts, and debriefs. Budget 30 minutes and a CD-R you will destroy.

Write things on paper as though it were real. Type passphrases from your
handwriting rather than the screen. The transcription is the step most likely
to fail and the only way to find out is to do it.

**Destroy the dry-run disc afterwards.** It is physically indistinguishable
from a real archive, and confusing the two later would be bad in both
directions.

### SSH CA path

`make dry-run` has an optional SSH CA section. It needs **two** YubiKeys in
factory PIV state (`ykman -d <serial> piv reset` first) and exercises the parts
no lower tier can: `ssh-keygen -D` through the ykcs11 module, PIN entry, touch,
`ykman piv keys import`, and the recovery proof that re-queries both tokens.
`ykman -d <serial> piv reset` **both** tokens afterwards — the dry run leaves
real throwaway CA keys and a non-default PIN/PUK/management key on them.

---

## Adding a test

Drop a file in `tests/cases/`, numbered. It is sourced, not executed, and has
`assert_eq`, `assert_contains`, `assert_exit`, `ok`, `no`, `skip`, and `have`
available, plus `$REPO_ROOT` and `$TEST_TIER`.

Gate anything needing tools or hardware:

```sh
[[ "$TEST_TIER" -ge 2 ]] || { skip "tier 2 not requested"; return; }
have age || { skip "integration" "missing: age"; return; }
```

**Write the negative case first.** A check that cannot fail is not a check.
Before trusting a new test, break the thing it covers and confirm it goes red —
every test in this suite was validated that way, and one of them was silently
inert until the mutation was applied correctly.

---

## Before publishing or after any change to the invariants

1. `make test` — clean
2. `make test-all` on a host with `age` and `ssss`
3. `make preflight` from a fresh clone — catches lost executable bits
4. `make build`, boot the ISO, run `ceremony-selftest` on real hardware
5. `make dry-run` end to end with fake material

Steps 4 and 5 cannot be skipped by running steps 1–3 harder.
