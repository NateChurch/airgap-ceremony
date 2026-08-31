#!/usr/bin/env bash
# ceremony-ssh-ca.sh [-n SHARES] [-t THRESHOLD] [-d DEV] [--no-burn]
#
# Stand up the SSH certificate authorities for the fleet, on the air-gapped
# machine, in one sitting:
#
#   1. generate the host and user CA keypairs OFF-CARD (ECDSA P-256)
#   2. generate a fresh PIV PIN, PUK and management key per token
#   3. import the CA keys into TWO YubiKeys (Key 3 and its off-site twin)
#   4. prove each token can actually sign, by issuing throwaway certs and
#      parsing them back
#   5. archive the private keys and the PIV secrets through the existing
#      archive-ceremony.sh flow (age -p, Shamir split, write-once media)
#   6. prove recovery from the disc plus the paper shares BEFORE anyone
#      leaves the room, including that the recovered key matches the tokens
#
# This is a PEER of archive-ceremony.sh, not a step inside it. It reuses that
# script for the encrypt/split/burn path rather than reimplementing it.
#
# Why off-card generation: the off-site twin must carry the SAME CA key, and a
# YubiKey cannot export a key generated on it. So the key is generated here and
# imported to both. The private keys therefore exist, briefly, in tmpfs on this
# machine and then only inside the encrypted archive.
#
# Why ECDSA P-256: `ssh-keygen -D` through the ykcs11 PKCS#11 module is the
# exercised signing path, and it does not support Ed25519 (nor does YubiKey
# PIV). P-256 is the tested path; do not "upgrade" it.
#
# Several steps are interactive by necessity -- age -p reads /dev/tty, and the
# YubiKey prompts for PIN and touch on a real console. Like archive-ceremony.sh
# this cannot run from a pipe or a harness. Tier 3 (`make dry-run`) is the only
# full test.

set -uo pipefail

LIB="${CEREMONY_LIB:-/usr/local/lib/ceremony-lib.sh}"
[[ -r "$LIB" ]] || LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/ceremony-lib.sh"
# shellcheck source=config/includes.chroot/usr/local/lib/ceremony-lib.sh
. "$LIB" || { echo "cannot load ceremony-lib.sh" >&2; exit 1; }

# ===========================================================================
# DECLARATIVE CONFIG -- every slot, policy, path and parameter is set here
# ONCE. Slots and policies come from ceremony-lib.sh (ca_slot, ca_policy_flags)
# so there is no "9a"/"9c" typed at a call site anywhere in this file.
# ===========================================================================
CA_KINDS=(host user)

# Organisation label baked into the CA certificate subjects and key comments.
# A label, not a secret -- but it ends up in every certificate this CA ever
# signs and on the printed inventory, so it is a variable rather than a literal
# typed in four places. Override for your own estate:  CEREMONY_ORG=acme ...
CA_ORG="${CEREMONY_ORG:-ceremony}"

declare -A CA_SUBJECT=(
	[host]="CN=${CA_ORG} SSH Host CA"
	[user]="CN=${CA_ORG} SSH User CA"
)
declare -A CA_COMMENT=(
	[host]="${CA_ORG}-ssh-host-ca"
	[user]="${CA_ORG}-ssh-user-ca"
)

CA_KEYTYPE=ecdsa          # ssh-keygen -t
CA_KEYBITS=256            # ssh-keygen -b   (P-256)

# Throwaway verification certificate. Never trusted anywhere; it exists only so
# the ceremony can read a real signature back and check it.
TEST_USER_PRINCIPAL="ceremony-verify-user"
TEST_HOST_PRINCIPAL="host.ceremony.invalid"
TEST_VALIDITY="+1d"

# Names inside the archive. Private keys are PEM ("BEGIN EC PRIVATE KEY") so a
# future recoverer needs only openssl or ssh-keygen, no OpenSSH key format.
ARCHIVE_PRIV()   { printf '%s-ca.pem' "$1"; }          # <kind>-ca.pem
ARCHIVE_PUB()    { printf '%s-ca.pub' "$1"; }          # <kind>-ca.pub (OpenSSH)
FPR_FILE="ssh-ca-fingerprints.txt"                     # non-secret record
piv_secret_file() { printf 'piv-%s-%s.txt' "$1" "$2"; } # piv-<serial>-<kind>.txt

# Defaults, overridable by flags.
SHARES=3
THRESHOLD=2
DEV="/dev/sr0"
NO_BURN=0

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------------------
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n) SHARES="${2:?}"; shift 2 ;;
			-t) THRESHOLD="${2:?}"; shift 2 ;;
			-d) DEV="${2:?}"; shift 2 ;;
			--no-burn) NO_BURN=1; shift ;;
			-h|--help) usage; exit 0 ;;
			-*) die "unknown option: $1" ;;
			*)  die "unexpected argument: $1 (this ceremony takes no positional args)" ;;
		esac
	done
	[[ "$THRESHOLD" -ge 2 ]] || die "threshold must be >= 2 (got $THRESHOLD)"
	[[ "$SHARES" -ge "$THRESHOLD" ]] || die "shares ($SHARES) < threshold ($THRESHOLD)"
}

# --- random secrets ------------------------------------------------------
rand_digits() {  # rand_digits <count>
	local n="$1" s=""
	while [[ ${#s} -lt "$n" ]]; do
		s="${s}$(od -An -N4 -tu4 /dev/urandom | tr -dc 0-9)"
	done
	printf '%s' "${s:0:n}"
}

# ---------------------------------------------------------------------------
setup_env() {
	require_bins ssh-keygen ykman yubico-piv-tool openssl age tar sha256sum \
		ssss-combine opensc-tool

	YKCS11_MODULE="$(ykcs11_module_path)" \
		|| die "ykcs11 PKCS#11 module not found under /usr/lib.
      The image is missing the 'ykcs11' package -- rebuild it in. Signing
      cannot proceed without a PKCS#11 provider and there is no network here
      to install one."
	info "PKCS#11 provider: ${YKCS11_MODULE}"

	section "Environment"
	require_airgap
	if grep -qw toram /proc/cmdline; then
		pass "booted with toram; scratch space is RAM-backed"
	else
		warn "toram not in effect -- /tmp may be on persistent media"
	fi

	WORK="$(mktemp -d /tmp/ssh-ca.XXXXXX)" || die "mktemp failed"
	chmod 700 "$WORK"
	ARCHIVE_DIR="$WORK/archive"
	mkdir -p "$ARCHIVE_DIR"
	# shred every private thing we can before releasing the tmpdir; toram means
	# it is RAM-backed, but do not rely on that alone.
	trap 'find "$WORK" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$WORK"' EXIT
}

# --- 1. off-card key generation ---------------------------------------
generate_ca_keypairs() {
	section "Generate CA keypairs (off-card, ${CA_KEYTYPE} ${CA_KEYBITS})"
	local kind
	for kind in "${CA_KINDS[@]}"; do
		ssh-keygen -q -t "$CA_KEYTYPE" -b "$CA_KEYBITS" -N '' \
			-C "${CA_COMMENT[$kind]}" -f "$WORK/${kind}-ca" \
			|| die "ssh-keygen failed for ${kind} CA"
		# PEM private copy for `ykman piv keys import` and for the archive.
		cp "$WORK/${kind}-ca" "$WORK/${kind}-ca.pem"
		ssh-keygen -q -p -N '' -m PEM -f "$WORK/${kind}-ca.pem" \
			|| die "could not convert ${kind} CA to PEM"
		# PKCS#8 public for `ykman piv certificates generate`.
		ssh-keygen -e -m PKCS8 -f "$WORK/${kind}-ca.pub" > "$WORK/${kind}-ca.pub.pem" \
			|| die "could not export ${kind} CA public key as PKCS8"
		CA_FPR[$kind]="$(ssh-keygen -l -f "$WORK/${kind}-ca.pub" | awk '{print $2}')"
		CA_BODY[$kind]="$(ssh_pubkey_body "$WORK/${kind}-ca.pub")"
		pass "${kind} CA: slot $(ca_slot "$kind")  ${CA_FPR[$kind]}"
	done
}

# --- token provisioning ---------------------------------------------
# Ordering is deliberate: set PIN/PUK/management key FIRST, then import (import
# needs the new management key), then sign the throwaway cert (which prompts for
# the new PIN). Each later step verifies the earlier one for free.
current_serial() {
	local s
	s="$(ykman list --serials 2>/dev/null | head -n1)"
	[[ -n "$s" ]] || die "no YubiKey serial reported by ykman"
	printf '%s' "$s"
}

provision_token() {  # provision_token <which:1|2>
	local which="$1" serial pin puk mgmt kind slot

	section "Token ${which}: insert it now"
	confirm_exact "ready" "Insert the YubiKey to provision as token ${which} and nothing else."
	assert_one_reader
	serial="$(current_serial)"
	info "serial: ${serial}"
	if [[ "$which" == 2 && "$serial" == "$TOKEN1_SERIAL" ]]; then
		die "this is the same token as token 1 (serial ${serial}). The twin must
      be a second physical YubiKey."
	fi
	[[ "$which" == 1 ]] && TOKEN1_SERIAL="$serial"
	TOKEN_SERIALS+=("$serial")

	# fresh secrets, distinct per token
	pin="$(rand_digits 8)"
	puk="$(rand_digits 8)"
	mgmt="$(openssl rand -hex 24)"
	piv_secret_is_factory pin  "$pin"  && die "generated PIN equals the factory default -- RNG problem, stop"
	piv_secret_is_factory puk  "$puk"  && die "generated PUK equals the factory default -- RNG problem, stop"
	piv_secret_is_factory mgmt "$mgmt" && die "generated management key equals the factory default -- RNG problem, stop"

	section "Token ${which}: set PIV PIN, PUK and management key"
	ykman -d "$serial" piv access change-pin \
		-P "$PIV_FACTORY_PIN" -n "$pin"  || die "change-pin failed (is this token factory-fresh?)"
	ykman -d "$serial" piv access change-puk \
		-p "$PIV_FACTORY_PUK" -n "$puk"  || die "change-puk failed"
	ykman -d "$serial" piv access change-management-key \
		-m "$PIV_FACTORY_MGMT" -n "$mgmt" --algorithm AES192 -f \
		|| die "change-management-key failed"
	pass "PIN, PUK and management key rotated off the factory defaults"

	section "Token ${which}: import CA keys"
	for kind in "${CA_KINDS[@]}"; do
		slot="$(ca_slot "$kind")"
		# ca_policy_flags returns two words (--pin-policy=X --touch-policy=Y) and
		# must word-split into two ykman arguments; the split is intentional.
		# shellcheck disable=SC2046
		ykman -d "$serial" piv keys import \
			-m "$mgmt" $(ca_policy_flags "$kind") \
			"$slot" "$WORK/${kind}-ca.pem" \
			|| die "importing ${kind} CA into slot ${slot} failed"
		ykman -d "$serial" piv certificates generate \
			-m "$mgmt" -P "$pin" -s "${CA_SUBJECT[$kind]}" -d 3650 \
			"$slot" "$WORK/${kind}-ca.pub.pem" \
			|| die "writing the ${kind} CA certificate into slot ${slot} failed"
		pass "${kind} CA in slot ${slot}  ($(ca_policy_flags "$kind"))"
	done

	# hand the secrets to the archive stager
	printf 'PIN %s\nPUK %s\nMGMT %s\n' "$pin" "$puk" "$mgmt" \
		> "$ARCHIVE_DIR/$(piv_secret_file "$serial" secrets)"

	verify_token "$serial" "$pin" "$puk" "$mgmt"
}

# --- verification gate -- exit 0 is not proof ------------------------
verify_token() {  # verify_token <serial> <pin> <puk> <mgmt>
	local serial="$1" pin="$2" puk="$3" mgmt="$4" kind slot bodies

	section "Token ${serial}: verify"

	# a) the token reports both CA public keys, and they are the ones we made
	bodies="$(ssh-keygen -D "$YKCS11_MODULE" -e 2>/dev/null | awk 'NF>=2{print $2}')"
	[[ -n "$bodies" ]] || die "ssh-keygen -D read no public keys from the token"
	for kind in "${CA_KINDS[@]}"; do
		grep -qxF "${CA_BODY[$kind]}" <<<"$bodies" \
			|| die "token ${serial} does not present the ${kind} CA public key we generated"
	done
	pass "token presents both CA public keys, matching what was generated"

	# b) it can actually SIGN with each slot, and the result is what we intended
	rm -f "$WORK/throwaway" "$WORK/throwaway.pub" "$WORK/throwaway-cert.pub"
	ssh-keygen -q -t ed25519 -N '' -C throwaway -f "$WORK/throwaway" \
		|| die "could not create the throwaway target key"

	info "Signing a throwaway USER certificate. Enter the NEW PIN when asked,"
	info "and touch the token. (slot $(ca_slot user), touch=$(ca_touch_policy user))"
	rm -f "$WORK/throwaway-cert.pub"
	ssh-keygen -D "$YKCS11_MODULE" -s "$WORK/user-ca.pub" \
		-I "$TEST_USER_PRINCIPAL" -n "$TEST_USER_PRINCIPAL" -V "$TEST_VALIDITY" \
		"$WORK/throwaway.pub" \
		|| die "the token could not sign with the user CA (slot $(ca_slot user))"
	assert_cert_matches_intent "$WORK/throwaway-cert.pub" \
		"$TEST_USER_PRINCIPAL" "${CA_FPR[user]}" user

	info "Signing a throwaway HOST certificate. Enter the NEW PIN when asked,"
	info "and touch the token. (slot $(ca_slot host), touch=$(ca_touch_policy host))"
	rm -f "$WORK/throwaway-cert.pub"
	ssh-keygen -D "$YKCS11_MODULE" -s "$WORK/host-ca.pub" -h \
		-I "$TEST_HOST_PRINCIPAL" -n "$TEST_HOST_PRINCIPAL" -V "$TEST_VALIDITY" \
		"$WORK/throwaway.pub" \
		|| die "the token could not sign with the host CA (slot $(ca_slot host))"
	assert_cert_matches_intent "$WORK/throwaway-cert.pub" \
		"$TEST_HOST_PRINCIPAL" "${CA_FPR[host]}" host
	rm -f "$WORK/throwaway" "$WORK/throwaway.pub" "$WORK/throwaway-cert.pub"

	# c) no factory PIV secret survived
	assert_no_factory_piv_secrets "$serial" "$pin" "$puk" "$mgmt"

	TOKENS_VERIFIED=$((TOKENS_VERIFIED + 1))
	pass "token ${serial} fully verified (${TOKENS_VERIFIED} of 2)"
}

assert_no_factory_piv_secrets() {  # <serial> <pin> <puk> <mgmt>
	local serial="$1" pin="$2" puk="$3" mgmt="$4"
	# the generated values are not the defaults (checked at generation), and a
	# no-op change with the NEW secret proves the token actually holds it -- if
	# any were still factory, these would fail.
	ykman -d "$serial" piv access change-pin -P "$pin" -n "$pin" \
		|| die "PIN self-check failed on ${serial}: the token is not holding the new PIN"
	ykman -d "$serial" piv access change-puk -p "$puk" -n "$puk" \
		|| die "PUK self-check failed on ${serial}: the token is not holding the new PUK"
	ykman -d "$serial" piv access change-management-key -m "$mgmt" -n "$mgmt" --algorithm AES192 -f \
		|| die "management-key self-check failed on ${serial}"
	piv_secret_is_factory pin "$pin"  && die "PIN is the factory default on ${serial}"
	piv_secret_is_factory puk "$puk"  && die "PUK is the factory default on ${serial}"
	piv_secret_is_factory mgmt "$mgmt" && die "management key is the factory default on ${serial}"
	pass "no factory PIN, PUK or management key remains on ${serial}"
}

# --- stage + archive ----------------------------------------------
stage_archive() {
	section "Stage the archive"
	local kind
	for kind in "${CA_KINDS[@]}"; do
		cp "$WORK/${kind}-ca.pem" "$ARCHIVE_DIR/$(ARCHIVE_PRIV "$kind")"
		cp "$WORK/${kind}-ca.pub" "$ARCHIVE_DIR/$(ARCHIVE_PUB "$kind")"
	done
	{
		echo "${CA_ORG} SSH certificate authorities"
		echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "algorithm: ${CA_KEYTYPE} ${CA_KEYBITS} (P-256)"
		echo
		for kind in "${CA_KINDS[@]}"; do
			printf '%-5s CA  slot %s  %s  fpr %s\n' \
				"$kind" "$(ca_slot "$kind")" "$(ca_policy_flags "$kind")" "${CA_FPR[$kind]}"
		done
		echo
		printf 'imported to tokens: %s\n' "${TOKEN_SERIALS[*]}"
		echo
		echo "The .pem files are the CA PRIVATE keys. The PIV PIN/PUK/management"
		echo "key for each token are in piv-<serial>-secrets.txt. Losing the"
		echo "management key means the token can never be re-imported to."
	} > "$ARCHIVE_DIR/$FPR_FILE"

	pass "archive directory assembled:"
	( cd "$ARCHIVE_DIR" && find . -type f | sort | sed 's|^\./|        |' )

	section "Hand off to archive-ceremony.sh"
	local arch_args=(-n "$SHARES" -t "$THRESHOLD" -d "$DEV")
	[[ $NO_BURN -eq 1 ]] && arch_args+=(--no-burn)
	local archive_sh
	archive_sh="$(command -v archive-ceremony.sh || echo "$(dirname "${BASH_SOURCE[0]}")/archive-ceremony.sh")"
	"$archive_sh" "${arch_args[@]}" "$ARCHIVE_DIR" \
		|| die "archive-ceremony.sh failed -- the CA keys are NOT safely stored"
}

# --- recovery proof ----------------------------------------------
# Uses only what a recoverer has: the disc and the paper shares. Proves the
# archive round-trips AND that the recovered key is the one the tokens hold.
ca_recovery_proof() {
	section "Prove recovery before anyone leaves"

	local target
	if [[ $NO_BURN -eq 1 ]]; then
		target="/tmp/CEREMONY-$(date -u +%Y%m%d).iso"
		[[ -f "$target" ]] || target="$(ls -1t /tmp/CEREMONY-*.iso 2>/dev/null | head -n1)"
		[[ -n "$target" && -f "$target" ]] || die "cannot find the archive image to rehearse against"
	else
		target="$DEV"
	fi

	local rehearse
	rehearse="$(command -v rehearse-recovery.sh || echo "$(dirname "${BASH_SOURCE[0]}")/rehearse-recovery.sh")"
	"$rehearse" "$target" || die "rehearse-recovery.sh failed -- do NOT end the ceremony"

	section "CA key-match proof"
	cat <<'EOF'
        The rehearsal proved the archive decrypts and checksums. Now prove the
        key it contains is the one on the tokens. Reconstruct the passphrase
        from EXACTLY the threshold number of shares, decrypt, and the recovered
        public halves are compared -- byte for byte -- against each token.
EOF
	local mnt out
	mnt="$(mktemp -d)"; out="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "umount '$mnt' 2>/dev/null; rm -rf '$mnt' '$out'; find \"$WORK\" -type f -exec shred -u {} + 2>/dev/null; rm -rf \"$WORK\"" EXIT

	if [[ -b "$target" ]]; then mount -o ro "$target" "$mnt" || die "cannot mount $target"
	else mount -o ro,loop "$target" "$mnt" || die "cannot loop-mount $target"; fi

	printf '  Enter %s shares, one per line:\n\n' "$THRESHOLD"
	local pass_recovered
	pass_recovered="$(ssss-combine -t "$THRESHOLD" -q 2>&1 >/dev/null)" || true
	[[ -n "$pass_recovered" ]] || read -r -s -p "  Paste the reconstructed passphrase: " pass_recovered
	printf '\n'
	[[ -n "$pass_recovered" ]] || die "no passphrase; cannot prove recovery"

	printf '%s' "$pass_recovered" | age -d -o "$out/payload.tar" "$mnt/payload.tar.age" 2>/dev/null \
		|| die "decryption failed with the reconstructed passphrase"
	tar -C "$out" -xf "$out/payload.tar" || die "tar extraction failed"

	local kind
	for kind in "${CA_KINDS[@]}"; do
		[[ -r "$out/$(ARCHIVE_PRIV "$kind")" ]] \
			|| die "recovered archive is missing $(ARCHIVE_PRIV "$kind")"
		ssh-keygen -y -f "$out/$(ARCHIVE_PRIV "$kind")" > "$out/${kind}.recovered.pub" \
			|| die "cannot derive public key from recovered ${kind} CA"
		# anchor 1: recovered key == what we generated this session
		assert_pubkey_identical "recovered ${kind} CA vs generated" \
			"$out/${kind}.recovered.pub" "$WORK/${kind}-ca.pub"
	done

	# anchor 2: recovered key == what EACH token actually holds, queried now
	local serial
	for serial in "${TOKEN_SERIALS[@]}"; do
		section "Re-query token ${serial} for the match proof"
		confirm_exact "ready" "Insert token ${serial} (only it) for the final check."
		assert_one_reader
		[[ "$(current_serial)" == "$serial" ]] || die "wrong token -- expected serial ${serial}"
		local tb
		ssh-keygen -D "$YKCS11_MODULE" -e 2>/dev/null | awk 'NF>=2{print $2}' > "$out/token.bodies"
		for kind in "${CA_KINDS[@]}"; do
			tb="$(grep -m1 -xF "$(ssh_pubkey_body "$out/${kind}.recovered.pub")" "$out/token.bodies" || true)"
			[[ -n "$tb" ]] \
				|| die "token ${serial} does not hold the recovered ${kind} CA key"
		done
		pass "token ${serial} holds both recovered CA keys, byte-identical"
	done

	umount "$mnt" 2>/dev/null || true
	rm -rf "$mnt" "$out"
	pass "recovery proven from the disc and the shares, and the key matches both tokens"
}

# ---------------------------------------------------------------------------
finish() {
	section "Before you leave"
	cat <<EOF
        1. Burn a SECOND copy now:  archive-ceremony.sh -n ${SHARES} -t ${THRESHOLD} -d ${DEV} <re-stage>
           (or re-run this ceremony; the staged dir is gone with tmpfs)
        2. Fill in the DURABLE INVENTORY (docs/11-inventory.md): both token
           serials, both CA fingerprints, the twin location, and tick the
           twin-vs-share location box. It is a separate sheet from the
           worksheet and it is the one you keep.
        3. Destroy worksheet Section 1 -- it carried the passphrase, and cut
           apart the Section 2 share cards.
        4. Both CA public keys go into the fleet trust config; nothing here
           does that for you.
EOF
	print_dependency_reminders
	cat <<'EOF'

        SSH-CA-specific, confirm each is FALSE:

          [ ] A passphrase share is being sent over SSH to a host this CA
              authenticates (recovery of the CA would then depend on the CA)
          [ ] The two tokens share a PIN/PUK/management key set
          [ ] The Key 3 twin will be stored with a passphrase share
EOF
}

# ---------------------------------------------------------------------------
main() {
	parse_args "$@"

	declare -gA CA_FPR CA_BODY
	declare -g YKCS11_MODULE WORK ARCHIVE_DIR TOKEN1_SERIAL=""
	declare -ga TOKEN_SERIALS=()
	declare -g TOKENS_VERIFIED=0

	setup_env
	assert_distinct_locations "$SHARES"      # concentration risk -- BEFORE generation
	generate_ca_keypairs
	provision_token 1
	provision_token 2

	[[ $TOKENS_VERIFIED -eq 2 ]] \
		|| die "only ${TOKENS_VERIFIED} token(s) verified. Two good tokens are
      required; one is a failed ceremony."

	stage_archive
	ca_recovery_proof
	finish

	section "Done"
	printf '  %sSSH CA ceremony complete.%s Power off when the worksheet is filled in\n' \
		"$c_ok" "$c_off"
	printf '  and Section 1 is destroyed.\n\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
