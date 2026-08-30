#!/usr/bin/env bash
# dry-run.sh -- a full sacrificial ceremony with fake material.
#
# Tier 3. This is NOT automated, on purpose.
#
# The riskiest code in this repo touches a real terminal (age reads /dev/tty),
# a real burner, and real media. A harness that faked those would make broken
# code pass -- which is the precise failure this whole project is built to
# avoid. So this script sets up throwaway material, hands you the real
# commands, and gets out of the way.
#
# Run it on the ceremony hardware, booted from the ISO, before you ever trust
# the process with real key material.
#
#   dry-run.sh [--no-burn]

set -uo pipefail

LIB="${CEREMONY_LIB:-/usr/local/lib/ceremony-lib.sh}"
[[ -r "$LIB" ]] || LIB="$(dirname "${BASH_SOURCE[0]}")/../config/includes.chroot/usr/local/lib/ceremony-lib.sh"
# shellcheck source=config/includes.chroot/usr/local/lib/ceremony-lib.sh
. "$LIB" || { echo "cannot load ceremony-lib.sh" >&2; exit 1; }

NO_BURN=""
[[ "${1:-}" == "--no-burn" ]] && NO_BURN="--no-burn"

DIR=/tmp/dry-run
ARCHIVE="$(command -v archive-ceremony.sh || echo ./config/includes.chroot/usr/local/bin/archive-ceremony.sh)"
REHEARSE="$(command -v rehearse-recovery.sh || echo ./config/includes.chroot/usr/local/bin/rehearse-recovery.sh)"

cat <<'EOF'

  DRY RUN -- SACRIFICIAL CEREMONY
  ==============================

  This generates FAKE key material and walks the complete flow: archive,
  encrypt, split, burn, rehearse. Nothing here is real; the point is to find
  out where the procedure breaks while it costs nothing.

  Do this at least once before a real ceremony. Budget 30 minutes and a
  blank CD-R you are willing to throw away.

  What you are testing:
    - that age prompts and accepts your typed passphrase
    - that ssss-split output is transcribable by hand
    - that the burner works and the disc reads back
    - that YOU can follow the procedure without improvising

  That last one is the real subject of the test.

EOF
confirm_exact "dry-run" "Confirm you understand this produces throwaway material."

section "1. Generate fake material"
rm -rf "$DIR"; mkdir -p "$DIR"
{
	echo "DRY RUN -- NOT REAL KEY MATERIAL"
	echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$DIR/README-FAKE.txt"

if command -v age-keygen >/dev/null 2>&1; then
	age-keygen -o "$DIR/fake-age-identity.txt" 2>/dev/null
	age-keygen -y "$DIR/fake-age-identity.txt" > "$DIR/fake-age-recipient.txt" 2>/dev/null
	pass "fake age identity created (real format, throwaway key)"
else
	printf 'AGE-SECRET-KEY-1FAKEFAKEFAKE\n' > "$DIR/fake-age-identity.txt"
	warn "age-keygen absent; wrote a placeholder identity"
fi
head -c 2048 /dev/urandom > "$DIR/fake-master-key.bin"
pass "fake key material in $DIR"
ls -la "$DIR" | sed 's/^/        /'

section "2. Environment"
if command -v ceremony-selftest >/dev/null 2>&1; then
	ceremony-selftest || warn "selftest reported problems -- note them, they are real"
else
	warn "ceremony-selftest not on PATH (are you running from the repo rather than the ISO?)"
fi

section "3. Archive"
cat <<EOF

  Now run the real archive script against the fake material:

      ${ARCHIVE} ${NO_BURN} ${DIR}

  Watch specifically for:
    - does age actually prompt you for a passphrase, twice?
    - does the round-trip decrypt succeed with what you typed?
    - is the ssss-split output legible enough to write down?
    - does the media-type check see your disc, and is it right?

  Write things on paper as though this were real. The transcription is the
  part most likely to fail, and the only way to find out is to do it.

EOF
confirm_exact "done" "Run the command above in another terminal, then come back."

section "4. Rehearse"
cat <<EOF

  Now recover from what you just made, using ONLY the paper:

      ${REHEARSE} /dev/sr0

  Type the shares from your handwriting. Do not look at any terminal
  scrollback. If you cannot read your own writing twenty minutes later, you
  will not read it in ten years.

EOF
confirm_exact "done" "Run the rehearsal, then come back."

section "4b. SSH CA ceremony (optional -- needs two YubiKeys)"
cat <<EOF

  ceremony-ssh-ca.sh is a separate ceremony: it generates the SSH host and
  user CAs off-card, imports them to TWO tokens, and archives the private
  keys through archive-ceremony.sh. It cannot be rehearsed without hardware
  and it is not part of the flow above.

  If you have two sacrificial YubiKeys (factory PIV state -- 'ykman piv reset'
  first), rehearse it now:

      $(command -v ceremony-ssh-ca.sh || echo ./config/includes.chroot/usr/local/bin/ceremony-ssh-ca.sh) --no-burn

  Watch for:
    - does it refuse to start with zero readers, or with more than one?
    - does it prompt for the twin and share locations, and refuse if the
      twin location matches a share location?
    - do BOTH tokens sign the throwaway certs, and does ssh-keygen -L show
      the principals, validity and CA fingerprint it claims to check?
    - does the recovery proof decrypt from the shares AND report the
      recovered key matches both tokens byte-for-byte?

  'ykman piv reset' BOTH tokens afterwards -- the dry run leaves real
  (throwaway) CA keys and a non-default PIN/PUK/management key on them.

EOF
confirm_exact "noted" "Rehearse it if you have the hardware, then come back. Skipping is fine for an age/GPG-only rehearsal."

section "5. Debrief"
cat <<'EOF'

  Answer honestly. Anything that went wrong here is a defect in the
  procedure, not in you -- that is what the dry run is for.

    [ ] Did every step work without improvising a command?
    [ ] Did the docs answer every question that came up?
    [ ] Was any output ambiguous to transcribe? (0/O, 1/l/I)
    [ ] Did the rehearsal pass on the first attempt?
    [ ] How long did it take? Is that sustainable for the real thing?
    [ ] Was anything unclear that a stranger would find worse?

  File anything that failed as an issue before the real ceremony.

EOF

section "6. Destroy the evidence"
cat <<EOF

  The fake material is in tmpfs and vanishes at power-off, but the DISC does
  not. Destroy it -- do not leave a dry-run disc lying around to be confused
  later with a real archive. They look identical.

      shred -u ${DIR}/* 2>/dev/null; rm -rf ${DIR}

  Then physically destroy the CD-R.

EOF
printf '  %sDry run complete.%s\n\n' "$c_ok" "$c_off"
