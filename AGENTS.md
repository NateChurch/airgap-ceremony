# AGENTS.md

Guidance for an AI agent working on **this repository**.

> Not to be confused with `config/includes.binary/AGENTS.md`, which ships on the
> built ISO and addresses an agent reading a ceremony disc at runtime. Different
> audience, different constraints. Do not merge them.

## What this repo is

A `live-build` configuration producing a Debian live ISO for offline
cryptographic key ceremonies: generating root key material, provisioning
YubiKeys, and producing encrypted, Shamir-split backups.

The image is amnesiac (RAM-only, no swap, no persistence), has no working
network stack, and carries its full toolchain and documentation because the
machine that boots it cannot fetch anything.

## Build

Debian trixie, as root, in a VM or privileged LXC. **Not WSL** — `make
preflight` refuses.

```sh
cp config/binaries.env.example config/binaries.env   # fill in real checksums
make preflight     # host tools, modes, binaries.env
make binaries      # fetch + verify sops/talosctl on the HOST
make build         # lb config && lb build && collect artifacts
make purge         # FULL reset -- required when DEBIAN_SUITE changes
make artifacts     # collect ISO + SHA256SUMS + manifest
```

`make clean` keeps the cache. `make purge` does not. The distinction matters —
see "Traps" below.

## Layout

| Path | Goes where |
|---|---|
| `auto/config` | The single declaration of image properties. Change settings here, never as ad-hoc `lb` flags |
| `config/package-lists/*.list.chroot` | Packages installed into the image |
| `config/includes.chroot/` | Files inside the squashfs (the running system) |
| `config/includes.binary/` | Files on the ISO filesystem itself (visible when the disc is mounted, unbooted) |
| `docs-src/` | **The only tracked copy of the documentation.** Edit here |
| `config/includes.chroot/etc/skel/` | The ceremony user's home. Docs here are GENERATED |
| `config/hooks/normal/` | Build-time hooks; run in the chroot |
| `scripts/` | Host-side scripts, run before/around `lb build` |

Documentation has **one** tracked source: `docs-src/`. `scripts/sync-docs.sh`
copies it to three destinations at build time and writes `docs.manifest`, which
the build hook verifies by checksum. The destinations are gitignored build
products.

Why three destinations: `etc/skel` is what the operator sees; the running
system must not depend on the medium after `toram`, so it needs its own copy at
`usr/local/share/ceremony`; and `includes.binary` puts the docs on the ISO root
so the disc can be read without booting it.

**Never edit a generated copy.** `scripts/sync-docs.sh --check` detects drift
and `make test` runs it. `make docs` regenerates.

## Invariants — do not weaken these

These exist because their failure modes are silent at ceremony time and
permanent at recovery time. If one is failing, fix the underlying condition.
Never bypass, suppress, or "temporarily" disable.

1. **`assert_not_circular`** in `usr/local/lib/ceremony-lib.sh` refuses to
   encrypt an archive to a recipient whose private identity is inside that
   archive. This is the single most important line of code in the repo.
2. **`ceremony-selftest`** asserts amnesia, no-swap, air gap, toolchain, and
   smartcard access against live system state. Adding a check is welcome;
   removing one needs a reason written down.
3. **`rehearse-recovery.sh`** is a phase gate, not a formality. It must use only
   what a future recoverer would have — the disc and the paper shares. Do not
   "optimise" it to reuse session state; that would test nothing.
4. **Passphrase (`age -p`) is the only archive encryption mode.** Recipient
   mode was removed: for root key material the recipient is nearly always
   inside the archive, and a mode that is usually wrong with no tested
   recovery path is worse than no mode. `assert_not_circular` is retained and
   unit-tested — do not delete it as dead code; the reasoning governs anything
   built on top of this.
   `age -p` reads from `/dev/tty` and **cannot be piped**. Do not "fix" the
   interactive prompts; they are load-bearing. Each one is a transcription
   check against the operator's paper copy.
5. **Binaries are fetched on the build host**, never in the chroot. Fetching in
   the chroot would mean shipping `curl` on an air-gapped image and depending on
   chroot DNS.
6. **Checksums are mandatory.** `stage-binaries.sh` fails if a URL or SHA-256 is
   unset or mismatched. There is deliberately no bypass path.
7. **Write-once media is enforced, not assumed.** `assert_write_once` refuses
   to burn to CD-RW or any rewritable type. The archive design rests on the
   disc being physically unrewritable.
8. **Documentation has one source.** `docs-src/`. Adding a document requires no
   list edits anywhere — the manifest is derived. If you find yourself updating
   a hardcoded filename list, that is the bug.
9. **A build must produce its own ISO.** The Makefile records a start stamp and
   rejects an ISO older than it; "an ISO exists" is not "this build made one".
10. **The Key 3 twin and the passphrase shares live in different places.**
    `assert_distinct_locations` in `ceremony-lib.sh` prompts for the twin's
    location and each share's, and refuses if the twin matches any share (or if
    any answer is blank). One location holding both a spare CA token and enough
    shares to rebuild the passphrase can recover everything alone. This is
    concentration risk, not circularity — `assert_not_circular` does not catch
    it, because it turns on where paper physically goes.
11. **The PKCS#11 module path is derived, never hardcoded.**
    `ceremony-ssh-ca.sh` signs through `ssh-keygen -D <libykcs11.so>`;
    `ykcs11_module_path` in `ceremony-lib.sh` finds it at runtime and dies if it
    is absent. The path varies by distribution and release — trixie's `ykcs11`
    package ships the unversioned `.so`, others put it in a `-dev` package.
    Hardcoding it means signing fails mid-ceremony, in a room with no network.
    `55-static-lint` and `70-ssh-ca` both guard against a literal path
    reappearing.

## Traps that have actually cost hours

**Executable bits.** The most frequent failure by far. A non-executable
`auto/config` causes `lb config` to *silently* use defaults, producing an ISO
that boots fine and is wrong in every invisible way — no `toram`, no `noswap`,
firmware present. The tell is the output filename: `live-image-amd64.hybrid.iso`
instead of `airgap-ceremony-*`. Run `make fix-modes`, and verify git records
`100755` before committing.

**A file that needs `git add -f` is invisible to a clean checkout.** `.gitignore`
had a bare `local/` (meant for live-build's top-level `local/` output) that also
matched `config/includes.chroot/usr/local/`. New scripts under `usr/local/bin/`
were silently untracked: the ISO built correctly here and shipped without the
script from a fresh clone — the same silent, only-visible-from-a-clean-tree
class as a lost executable bit. Line 6 is now `/local/`, anchored.
`50-repo-hygiene` asserts every file under `usr/local/{bin,lib}` is tracked or
deliberately gitignored (`sops`/`talosctl` are staged at build). If you add a
script there, `git status` must show it — if it doesn't, that is the bug.

**Stale chroot from another suite.** `lb build` reuses a cached chroot. If the
suite changed, you get dozens of "unmet dependencies" errors naming real
packages, which looks like a broken package list and is not. `make purge`.

**`tee` masks the exit code.** `lb build | tee build.log` exits with `tee`'s
status. A failed build looks like success and downstream checks report
confusing things. `auto/build` uses `set -o pipefail`.

**Carriage returns in `build.log`.** apt progress output uses `\r`; anchored
greps miss errors hidden behind progress lines. Filter with `tr '\r' '\n'`
before searching. This wasted several rounds of debugging.

**`--apt-recommends false` drops helpers.** Keeps the image lean and the
manifest honest, but a package may not pull something it expects. `user-setup`
was the first casualty: without it live-config cannot create the live user and
autologin fails with "Authentication failure."

**`/sbin` is not on a non-root PATH.** `cryptsetup` and friends live there. A
naive `command -v` check reports installed tools as missing.

**Commit `e9cf4e9` deleted three producers and left their consumers.** All
three are the same shape — something is asserted or used, but the step that
creates it is gone — and all three were silent:

1. The `$STAGE` staging-dir assembly in `archive-ceremony.sh`; `xorriso …
   "$STAGE"` stayed. Under `set -u` the script died at the disc-image step, so
   `archive-ceremony.sh` could not complete a burn. Only covered by the manual
   dry run, which nobody had run.
2. The Makefile line `install -D … config/includes.chroot/tmp/binaries.env`;
   the hook `0050-stage-env.hook.chroot` that asserts `/tmp/binaries.env`
   stayed. `make build` died at the first chroot hook — it had not finished a
   build since. Needs a Debian VM as root, so no full build had run.
3. The `.build/build-start` stamp; the `iso -nt .build/build-start` check in
   the `build` target stayed. `test FILE -nt <missing>` is true, so the check
   was vacuous and a stale ISO from a prior build would pass — the opposite of
   invariant 9.

`tests/cases/55-static-lint.sh` now pins all three, plus the general case:
`bash -n` and ShellCheck `SC2154` (with `check-unassigned-uppercase`, since
every variable here is uppercase and default `SC2154` skips those) over every
ceremony script, `SC2154` un-suppressible. The dynamic halves — a real burn
produces a readable disc, a real build produces its own ISO — are still only
`make dry-run` and `make build` on a real VM. Run them after any change under
`usr/local/bin/` or to the `build` target.

**A test case that `cd`s away breaks every case after it.** `run-tests.sh`
sources each `tests/cases/*.sh` with a `tests/`-relative path. `50-repo-hygiene`
does `cd "$REPO_ROOT"` and never returned, so `. cases/60-roundtrip.sh` and
everything ordered later silently failed to source — no `set -e`, no error.
`make test-all`'s headline "real encrypt → split → recover round trip"
(`60-roundtrip`) had not run through the runner for months; `./tests/run-tests.sh
60` still worked, which hid it. Fixed in one place: the runner `cd`s back to
`$TESTS_DIR` before sourcing each case. Do **not** fix it with a `trap …
RETURN` in a case — a RETURN trap set in a sourced file keeps firing after
every later case, which is its own silent footgun. The runner also now fails
loudly if a case sources 0 assertions (`56-cwd-guard-a`/`-b` is the regression
test for this).

## Conventions

- **Verify, don't assume.** Every step that reports success should verify the
  thing it claims. `make build` asserts an ISO exists; `make write` re-hashes
  the written device; `archive-ceremony.sh` reads the burned disc back.
  "Exit 0 is not proof."
- **Derive from live state; never hand-type paths.** Values that appear in two
  places will eventually disagree.
- **Distinguish "wrong" from "unverifiable."** `BADSIG` means tampering;
  `NO_PUBKEY` means you cannot tell. Collapsing them loses the distinction that
  matters and cries wolf.
- Comments explain *why*, especially when the reason is a specific past
  failure. The code says what it does; the comment says what it prevents.
- Prefer failing loudly at build time over discovering a problem mid-ceremony
  on a machine with no network and no way to install anything.

## Testing

Three tiers. Full detail in `docs/07-testing.md`.

```sh
make test        # tier 1: logic, manifests, hygiene. Runs anywhere
make test-all    # tier 2: real age/ssss round trip through a pty
make dry-run     # tier 3: sacrificial ceremony on real hardware. NOT automated
```

Tier 3 is manual on purpose. `age -p` reads `/dev/tty`, so a harness that
faked a terminal would make a broken invocation pass — that is a bug this repo
actually shipped. The same applies to the burner and the smartcard.

When adding or changing a verification step:

1. Add a case in `tests/cases/`, numbered. Files are sourced, not executed.
2. **Write the negative case first.** A check that cannot fail is not a check.
3. Break the thing deliberately and confirm the test goes red. Every test here
   was validated that way, and one was silently inert until the mutation was
   applied correctly — a mutation that fails to mutate looks exactly like a
   passing test.
4. `make preflight` from a clean clone; executable bits are the most frequent
   failure in this repo.

## Publishing

This repo is intended to be built by whoever uses it, not distributed as a
binary. The ISO is unsigned. `config/binaries.env` is gitignored on purpose:
users should verify sops/talosctl checksums themselves rather than trusting a
value committed here.

The documentation under `config/includes.chroot/etc/skel/docs/` describes one
person's key architecture. The reasoning generalizes; the specific storage
distribution should not be copied without thought.
