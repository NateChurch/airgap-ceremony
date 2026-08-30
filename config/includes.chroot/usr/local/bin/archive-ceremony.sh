#!/usr/bin/env bash
# archive-ceremony.sh [-n SHARES] [-t THRESHOLD] [-d DEV] [--no-burn] <dir>
#
# Package a completed ceremony's output, encrypt it in a way that does not
# depend on anything inside it, split the passphrase, burn to write-once media,
# and verify by reading the disc back.
#
# Encryption is ALWAYS passphrase-based (age -p). Recipient mode was removed:
# for root key material the recipient is almost always inside the archive
# (the circular case), and a mode that is usually wrong AND has no tested
# recovery path is worse than no mode. assert_not_circular is retained and
# tested because the reasoning still governs anything built on top of this.
#
# The script never holds the passphrase after displaying it. age -p reads from
# /dev/tty by design, so every subsequent step is typed by the operator from
# their own paper -- which turns each step into a transcription check.

set -uo pipefail

LIB="${CEREMONY_LIB:-/usr/local/lib/ceremony-lib.sh}"
[[ -r "$LIB" ]] || LIB="$(dirname "${BASH_SOURCE[0]}")/ceremony-lib.sh"
# shellcheck source=config/includes.chroot/usr/local/lib/ceremony-lib.sh
. "$LIB" || { echo "cannot load ceremony-lib.sh" >&2; exit 1; }

SHARES=3
THRESHOLD=2
DEV="/dev/sr0"
NO_BURN=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		-n) SHARES="${2:?}"; shift 2 ;;
		-t) THRESHOLD="${2:?}"; shift 2 ;;
		-d) DEV="${2:?}"; shift 2 ;;
		--no-burn) NO_BURN=1; shift ;;
		-h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) die "unknown option: $1" ;;
		*)  break ;;
	esac
done

SRC="${1:?usage: archive-ceremony.sh [options] <dir>}"
[[ -d "$SRC" ]] || die "not a directory: $SRC"
[[ -n "$(ls -A "$SRC")" ]] || die "nothing to archive in $SRC"

require_bins age tar sha256sum
[[ $NO_BURN -eq 1 ]] || require_bins xorriso
command -v dvd+rw-mediainfo >/dev/null 2>&1 || warn "dvd+rw-mediainfo absent; media type cannot be enforced"
command -v ssss-split >/dev/null 2>&1 || warn "ssss-split not found; passphrase will not be split"

LABEL="CEREMONY-$(date -u +%Y%m%d)"
WORK="$(mktemp -d /tmp/archive.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

section "Environment"
require_airgap
if grep -qw toram /proc/cmdline; then
	pass "booted with toram; scratch space is RAM-backed"
else
	warn "toram not in effect -- /tmp may be on persistent media"
fi

# --- 1. circularity ---------------------------------------------------------
assert_not_circular "$SRC" ""

# --- 2. inventory -----------------------------------------------------------
section "Contents"
( cd "$SRC" && find . -type f | sort | sed 's|^\./|        |' )
( cd "$SRC" && find . -type f -exec sha256sum {} + | sed 's|\./||' | sort -k2 ) > "$WORK/SHA256SUMS"
info ""
info "$(wc -l < "$WORK/SHA256SUMS") file(s) checksummed"

confirm_exact "yes" "
Everything listed above will be encrypted and burned to write-once media.
A CD-R cannot be erased. Confirm the contents are correct and contain no
plaintext you did not intend to commit permanently."

tar -C "$SRC" -cf "$WORK/payload.tar" . || die "tar failed"
cp "$WORK/SHA256SUMS" "$WORK/SHA256SUMS.txt"

# --- 3. encrypt -------------------------------------------------------------
section "Encryption"
info "mode: passphrase (age -p, scrypt) -- depends on no other key material"

PASSPHRASE=""
if command -v diceware >/dev/null 2>&1; then
	PASSPHRASE="$(diceware -n 8 2>/dev/null)" || PASSPHRASE=""
fi
if [[ -z "$PASSPHRASE" ]]; then
	command -v pwgen >/dev/null 2>&1 || die "no diceware or pwgen available"
	PASSPHRASE="$(pwgen -sy 40 1)"
fi

printf '\n%s  WRITE THIS ON SECTION 1 OF THE WORKSHEET. Shown once.%s\n\n' "$c_b" "$c_off"
printf '      %s%s%s\n\n' "$c_b" "$PASSPHRASE" "$c_off"
confirm_exact "written" "Transcribe it by hand. Write it twice and compare."

# age reads passphrases from /dev/tty by design; it cannot be piped, and that
# is deliberate on age's part. Rather than fight it, use it: from here on the
# operator types the passphrase FROM THEIR PAPER at every prompt. A typo means
# the step fails here, in the room, instead of at recovery in ten years.
PASSPHRASE_HINT="$PASSPHRASE"
unset PASSPHRASE   # the script does not hold it past this point

cat <<EOF

  age will now prompt for the passphrase, twice.

  Type it FROM YOUR PAPER, not from the screen above. That is the point --
  if what you wrote down is wrong, this step fails now rather than at
  recovery. Do not copy and paste.

EOF
if [[ -t 0 ]]; then
	age -p -o "$WORK/payload.tar.age" "$WORK/payload.tar" \
		|| die "age encryption failed or was cancelled"
else
	die "no terminal available; age -p requires one. Run this interactively."
fi
pass "encrypted with passphrase"

shred -u "$WORK/payload.tar" 2>/dev/null || rm -f "$WORK/payload.tar"

# --- 4. round-trip BEFORE burning ------------------------------------------
section "Round-trip check"
cat <<EOF

  Now decrypt it back, again typing from your paper. This proves the paper
  copy is correct before anything is committed to write-once media.

EOF
if age -d -o /dev/null "$WORK/payload.tar.age"; then
	pass "ciphertext decrypts with the passphrase as transcribed"
else
	fail "decryption failed"
	info "the passphrase on your paper does not match what encrypted the archive"
	info "for reference, the generated passphrase was:"
	printf '\n      %s%s%s\n\n' "$c_b" "$PASSPHRASE_HINT" "$c_off"
	die "correct your transcription and re-run"
fi

# --- 5. split the passphrase ------------------------------------------------
if command -v ssss-split >/dev/null 2>&1; then
	section "Passphrase shares (${THRESHOLD}-of-${SHARES})"
	printf '  Write each share on its own SHARE CARD (worksheet section 2).\n'
	printf '  Any %s shares reconstruct the passphrase. Any %s reveal nothing.\n\n' \
		"$THRESHOLD" "$((THRESHOLD - 1))"
	printf '  ssss-split will prompt for the secret. Type it from your paper.\n\n'
	ssss-split -t "$THRESHOLD" -n "$SHARES" -w ceremony || die "ssss-split failed"
	printf '\n'
	confirm_exact "written" "Transcribe every share by hand onto its card. Verify each."
else
	warn "ssss-split not available -- the passphrase is NOT split"
	warn "a single piece of paper now holds full access. Fix before storing."
fi

# --- 6. assemble the disc ---------------------------------------------------
section "Disc image"
# The output disc carries the full documentation set. Someone opening a safety
# deposit box in ten years will have the disc and nothing else.
DOCS_SRC="/usr/local/share/ceremony"
if [[ -d "$DOCS_SRC" ]]; then
	cp "$DOCS_SRC/README.md" "$WORK/README.md" 2>/dev/null || true
	cp "$DOCS_SRC/AGENTS.md" "$WORK/AGENTS.md" 2>/dev/null || true
	if [[ -d "$DOCS_SRC/docs" ]]; then
		mkdir -p "$WORK/docs" && cp "$DOCS_SRC/docs/"*.md "$WORK/docs/" 2>/dev/null || true
		info "including $(ls "$WORK/docs" | wc -l) documentation file(s)"
	fi
else
	warn "no documentation found to include -- the disc will be hard to recover from"
fi

cat > "$WORK/RECOVERY.txt" <<EOF
Ceremony archive: ${LABEL}
Created:          $(date -u +%Y-%m-%dT%H:%M:%SZ)
Encryption:       age passphrase (scrypt)
Sharing:          ${THRESHOLD}-of-${SHARES} Shamir (ssss)

TO RECOVER
----------
  1. Gather any ${THRESHOLD} of the ${SHARES} passphrase shares. They are on
     paper, stored in separate locations.

  2. ssss-combine -t ${THRESHOLD}
     Paste the shares when prompted, one per line.

  3. age -d -o payload.tar payload.tar.age
     Enter the reconstructed passphrase.

  4. tar -xf payload.tar

  5. sha256sum -c SHA256SUMS.txt

Tools needed: age, ssss     (Debian/Ubuntu: apt install age ssss)

You do NOT need the ceremony ISO, the machine that made this disc, or any
hardware token. That independence is deliberate.

Full procedure and rationale: README.md and docs/ on this disc.
EOF

# Assemble a clean staging directory holding EXACTLY the disc contents. This
# block was dropped in e9cf4e9, which left the mkisofs call below referencing an
# undefined $STAGE -- under `set -u` the script died here before any burn, and
# nothing caught it because tier-3 burn coverage is manual. Do not replace this
# with a default for $STAGE: burning an empty or wrong directory to write-once
# media is worse than a hard failure. $WORK also holds intermediates (the
# shredded payload.tar, the .iso itself) that must not land on the disc.
STAGE="$WORK/disc"; mkdir -p "$STAGE"
cp "$WORK/payload.tar.age" "$WORK/SHA256SUMS.txt" "$WORK/RECOVERY.txt" "$STAGE/" \
	|| die "could not assemble the disc staging directory"
[[ -r "$WORK/README.md" ]] && cp "$WORK/README.md" "$STAGE/"
[[ -r "$WORK/AGENTS.md" ]] && cp "$WORK/AGENTS.md" "$STAGE/"
[[ -d "$WORK/docs" ]]      && cp -r "$WORK/docs" "$STAGE/"

xorriso -as mkisofs -R -J -V "$LABEL" -o "$WORK/${LABEL}.iso" \
	"$STAGE" >/dev/null 2>&1 || die "mkisofs failed"
pass "image built: $(du -h "$WORK/${LABEL}.iso" | cut -f1)"

if [[ $NO_BURN -eq 1 ]]; then
	OUT="/tmp/${LABEL}.iso"
	cp "$WORK/${LABEL}.iso" "$OUT"
	pass "written to ${OUT} (not burned; --no-burn)"
	print_dependency_reminders
	exit 0
fi

# --- 7. burn and read back --------------------------------------------------
section "Burn"
[[ -b "$DEV" ]] || die "$DEV is not a block device (is the burner attached?)"
confirm_exact "burn" "Insert a blank CD-R in ${DEV}."
assert_write_once "$DEV"

xorriso -as cdrecord -v dev="$DEV" "$WORK/${LABEL}.iso" || die "burn failed"
pass "burn reported success"

section "Read-back verification"
info "A burn that exits 0 is not proof the disc is readable."
sleep 3
MNT="$(mktemp -d)"
if mount -o ro "$DEV" "$MNT" 2>/dev/null; then
	if cmp -s "$MNT/payload.tar.age" "$WORK/payload.tar.age"; then
		pass "payload on disc is byte-identical to the source"
	else
		umount "$MNT"; rmdir "$MNT"
		die "DISC DOES NOT MATCH SOURCE -- discard it and burn another"
	fi
	umount "$MNT"
else
	warn "could not mount ${DEV}; eject, reinsert, and verify manually:"
	info "  mount -o ro ${DEV} /mnt && cmp /mnt/payload.tar.age <source>"
fi
rmdir "$MNT" 2>/dev/null || true

section "Next"
cat <<EOF
        1. Burn a SECOND copy now (re-run with the same source directory
           only if you kept it; otherwise re-run this script from scratch).
        2. rehearse-recovery.sh ${DEV}
           Do not skip this. An untested backup is a hypothesis.
        3. Record locations in the README table, on paper.
EOF

print_dependency_reminders
