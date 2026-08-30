# Building this image

The image is built from the `airgap-ceremony` tree in the `fablab` monorepo.
Everything about it is declared in `auto/config` and `config/package-lists/`.

---

## Build host

Debian trixie, as root, in a VM or privileged LXC. **Not WSL** — `make
preflight` refuses, because live-build's chroot handling there is an
unnecessary variable in a build whose point is reproducibility.

```sh
apt install live-build debootstrap xorriso squashfs-tools curl gpgv
cp config/binaries.env.example config/binaries.env
$EDITOR config/binaries.env        # fill in real URLs and sha256 values
make preflight
make build
```

---

## What the build does

1. `make binaries` fetches `sops` and `talosctl` **on the host**, verifies their
   checksums, and stages them into `config/includes.chroot/usr/local/bin/`.
   Fetching inside the chroot would mean shipping `curl` on an air-gapped
   image.
2. `lb config` reads `auto/config` — the single declaration of image properties.
3. `lb build` bootstraps, installs the package lists, runs the hooks, and
   produces the ISO.
4. The Makefile asserts an ISO actually exists. `lb build` piped through `tee`
   can exit 0 while having failed.

Hooks that must pass:

- `0100-external-binaries` — sops/talosctl present and matching their staged
  checksums; ceremony scripts executable; README present
- `0200-harden` — masks networking units, disables core dumps, sudoers
- `0900-manifest` — records the exact package set into the image

---

## Traps that have actually bitten

**Stale chroot from a different suite.** `make clean` keeps the cache. If the
suite changes, you get dozens of misleading "unmet dependencies" errors naming
real packages. Use `make purge`. The `check-suite` target now catches this.

**`auto/config` not executable.** `lb config` silently ignores it and builds
with defaults — producing an ISO that boots fine and is wrong in every way you
cannot see: no `toram`, no `noswap`, firmware present. The tell is the output
filename: `live-image-amd64.hybrid.iso` instead of `airgap-ceremony-*`.

**`--apt-recommends false` drops helpers.** It keeps the image lean and the
manifest honest, but a package you add may not pull something it expects.
`user-setup` was the first casualty.

**Carriage returns in `build.log`.** apt's progress output uses `\r`; anchored
greps miss errors hidden behind progress lines. Filter with `tr '\r' '\n'`
before searching.

---

## Documentation

`docs-src/` is the only tracked copy. `make docs` (run automatically by
`make build` and `make test`) syncs it to three destinations and generates
`docs.manifest`; the build hook verifies every shipped file against that
manifest by checksum.

Editing a generated copy is the mistake this layout exists to prevent:

```sh
./scripts/sync-docs.sh --check    # reports drift and names the files
make docs                          # regenerate
```

Adding a document needs no list updated anywhere. Drop it in `docs-src/docs/`
and it flows through.

## Testing

```sh
make test        # tier 1, runs anywhere
make test-all    # tier 2, needs age + ssss
make dry-run     # tier 3, real hardware, sacrificial ceremony
```

See `docs/07-testing.md`. Tier 3 is deliberately not automated — mocking a
terminal, a burner, or a token tests the mock.

## Verifying an image

```sh
make artifacts
./scripts/verify-iso.sh artifacts/<stamp>/airgap-ceremony-amd64.hybrid.iso
```

Checks the recorded SHA256, confirms an El Torito boot record exists, and
extracts the embedded package manifest without booting — so two builds can be
diffed directly.

---

## Reproducibility

For an archival build, pin a snapshot mirror:

```sh
make purge
make build MIRROR=https://snapshot.debian.org/archive/debian/<timestamp>/
```

Slow and rate-limited; use it for the build you record in estate documentation,
and the normal mirror for iteration.

`artifacts/<stamp>/SHA256SUMS` plus the embedded manifest is what makes a given
ISO attestable years later.

---

## Deferred

- Secure Boot signing — the ISO is unsigned, so the ceremony machine needs
  Secure Boot off or a custom MOK
- Signing the ISO with Key 3 once it exists, making the environment disc
  verifiable rather than merely checksummed
