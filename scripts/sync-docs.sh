#!/usr/bin/env bash
# sync-docs.sh [--check]
#
# Copies docs-src/ into every place the build needs it, and generates a
# manifest so downstream checks assert the EXACT expected set rather than a
# count.
#
# docs-src/ is the only tracked copy. The destinations are build products and
# are gitignored. Editing a destination is a mistake -- `--check` detects it,
# and `make test` runs that.
#
# Destinations, and why each exists:
#   etc/skel                      the ceremony user's home; what the operator sees
#   usr/local/share/ceremony      system copy; scripts and root read this
#   includes.binary               ISO filesystem root; readable without booting
#
# The triplication is deliberate -- someone holding this disc in ten years may
# mount it rather than boot it, and the running system must not depend on the
# medium still being present after `toram`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/docs-src"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

[[ -d "$SRC/docs" ]] || { echo "FATAL: $SRC/docs not found" >&2; exit 1; }

DESTS=(
	"$ROOT/config/includes.chroot/etc/skel"
	"$ROOT/config/includes.chroot/usr/local/share/ceremony"
	"$ROOT/config/includes.binary"
)

# The manifest is derived from docs-src, never hand-maintained. Adding a
# document used to mean editing a hardcoded list in three places; forgetting
# one produced a tree that looked healthy while missing a referenced file.
manifest() {
	( cd "$SRC" && find . -name '*.md' | sed 's|^\./||' | sort | while read -r f; do
		printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
	done )
}

if [[ $CHECK -eq 1 ]]; then
	want="$(manifest)"
	fail=0
	for d in "${DESTS[@]}"; do
		if [[ ! -d "$d/docs" ]]; then
			echo "STALE: $d/docs missing -- run: make docs"; fail=1; continue
		fi
		got="$( cd "$d" && find . -name '*.md' | sed 's|^\./||' | sort | while read -r f; do
			printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$f"
		done )"
		if [[ "$want" != "$got" ]]; then
			echo "STALE: $d differs from docs-src"
			diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") \
				| sed -n 's/^[<>] *[0-9a-f]*  /  /p' | sort -u | sed 's/^/    /'
			echo "  (did you edit a generated copy instead of docs-src?)"
			fail=1
		fi
	done
	[[ $fail -eq 0 ]] && echo "docs in sync with docs-src"
	exit $fail
fi

for d in "${DESTS[@]}"; do
	mkdir -p "$d/docs"
	# Remove stale files first: a renamed document would otherwise linger in
	# the destinations and be shipped alongside its replacement.
	find "$d" -maxdepth 2 -name '*.md' -delete
	cp "$SRC"/*.md "$d/"
	cp "$SRC"/docs/*.md "$d/docs/"
	chmod 0644 "$d"/*.md "$d"/docs/*.md
done

# Ship the manifest inside the image so the build hook can assert against the
# real set rather than a list someone remembered to update.
MAN="$ROOT/config/includes.chroot/usr/local/share/ceremony/docs.manifest"
# The previous run left it 0444; `> "$MAN"` would then fail. Drop it first so a
# second run in the same tree succeeds.
rm -f "$MAN"
manifest > "$MAN"
chmod 0444 "$MAN"

n=$(grep -c . "$MAN")
echo "synced ${n} document(s) from docs-src to ${#DESTS[@]} destination(s)"
