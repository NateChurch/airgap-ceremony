#!/usr/bin/env bash
# rehearse-recovery.sh <device-or-iso>
#
# Prove the archive is recoverable BEFORE the ceremony ends.
#
# This performs a real recovery in a scratch directory: reconstruct the
# passphrase from shares, decrypt, extract, verify checksums. It uses only what
# a future recoverer would have -- the disc and the paper shares. Nothing from
# the current session is reused, because reusing it would test nothing.
#
# A backup you have never restored is a hypothesis, not a backup.

set -uo pipefail

LIB="${CEREMONY_LIB:-/usr/local/lib/ceremony-lib.sh}"
[[ -r "$LIB" ]] || LIB="$(dirname "${BASH_SOURCE[0]}")/ceremony-lib.sh"
# shellcheck source=config/includes.chroot/usr/local/lib/ceremony-lib.sh
. "$LIB" || { echo "cannot load ceremony-lib.sh" >&2; exit 1; }

SRC="${1:?usage: rehearse-recovery.sh <device-or-iso>}"
require_bins age tar sha256sum

WORK="$(mktemp -d /tmp/rehearse.XXXXXX)"; chmod 700 "$WORK"
MNT="$WORK/mnt"; OUT="$WORK/out"
mkdir -p "$MNT" "$OUT"
cleanup() { mountpoint -q "$MNT" && umount "$MNT"; rm -rf "$WORK"; }
trap cleanup EXIT

failures=0

section "Mount"
if [[ -b "$SRC" ]]; then
	mount -o ro "$SRC" "$MNT" || die "cannot mount $SRC"
	pass "mounted device $SRC read-only"
elif [[ -f "$SRC" ]]; then
	mount -o ro,loop "$SRC" "$MNT" || die "cannot loop-mount $SRC"
	pass "loop-mounted image $SRC read-only"
else
	die "not a device or file: $SRC"
fi

for f in payload.tar.age SHA256SUMS.txt RECOVERY.txt; do
	if [[ -r "$MNT/$f" ]]; then pass "found $f"; else fail "missing $f"; failures=1; fi
done
[[ -r "$MNT/README.md" ]] && pass "found README.md" \
	|| warn "no README.md on disc -- a recoverer will have no procedure"

section "Reconstruct the passphrase"
cat <<'EOF'
        Use the PAPER SHARES, not anything on screen from earlier. The point
        of this rehearsal is to test what a future recoverer will actually
        have in hand -- including whether your handwriting is legible.
EOF

PASSPHRASE=""
if command -v ssss-combine >/dev/null 2>&1; then
	printf '\n'
	read -r -p "Threshold (shares needed) [2]: " T; T="${T:-2}"
	printf '  Enter %s shares, one per line:\n\n' "$T"
	if PASSPHRASE="$(ssss-combine -t "$T" -q 2>&1 >/dev/null)"; then :; fi
	# ssss-combine writes the secret to stderr in quiet mode on some builds;
	# fall back to prompting rather than guessing wrong.
	if [[ -z "$PASSPHRASE" ]]; then
		warn "could not capture the combined secret automatically"
		read -r -s -p "  Paste the reconstructed passphrase: " PASSPHRASE; printf '\n'
	fi
else
	warn "ssss-combine not available"
	read -r -s -p "  Enter the passphrase: " PASSPHRASE; printf '\n'
fi
[[ -n "$PASSPHRASE" ]] || die "no passphrase; cannot rehearse"

section "Decrypt"
if printf '%s' "$PASSPHRASE" | age -d -o "$WORK/payload.tar" "$MNT/payload.tar.age" 2>/dev/null; then
	pass "decrypted with the reconstructed passphrase"
else
	fail "decryption FAILED"
	info "either the shares were transcribed wrong, or the passphrase differs"
	info "from what was used. Fix this NOW -- it is unfixable later."
	die "rehearsal failed"
fi

section "Extract and verify"
tar -C "$OUT" -xf "$WORK/payload.tar" || { fail "tar extraction failed"; failures=1; }
if ( cd "$OUT" && sha256sum -c "$MNT/SHA256SUMS.txt" >/dev/null 2>&1 ); then
	pass "every file matches its recorded checksum"
	info "$(wc -l < "$MNT/SHA256SUMS.txt") file(s) verified"
else
	fail "checksum mismatch after extraction"
	( cd "$OUT" && sha256sum -c "$MNT/SHA256SUMS.txt" 2>&1 | grep -v ': OK$' | sed 's/^/        /' )
	failures=1
fi

section "Recovered contents"
find "$OUT" -type f | sed "s|^${OUT}|        |" | sort

section "Result"
if [[ $failures -eq 0 ]]; then
	printf '  %sREHEARSAL PASSED.%s The archive is recoverable from the disc plus\n' "$c_ok" "$c_off"
	printf '  the paper shares alone.\n\n'
	printf '  Scratch copies are in RAM and vanish at power-off. Do not copy them\n'
	printf '  anywhere. Power the machine off when finished.\n\n'
	exit 0
fi
printf '  %sREHEARSAL FAILED.%s Do not end the ceremony. The material is still in\n' "$c_bad" "$c_off"
printf '  /tmp on this running system -- fix the problem and re-burn before\n'
printf '  powering off, or it is gone.\n\n'
exit 1
