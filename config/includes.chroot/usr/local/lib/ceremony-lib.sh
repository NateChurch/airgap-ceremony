#!/usr/bin/env bash
# ceremony-lib.sh -- shared helpers for ceremony scripts.
# Source, do not execute:  . /usr/local/lib/ceremony-lib.sh

c_ok=$'\033[32m'; c_bad=$'\033[31m'; c_warn=$'\033[33m'; c_b=$'\033[1m'; c_off=$'\033[0m'
[[ -t 1 ]] || { c_ok=""; c_bad=""; c_warn=""; c_b=""; c_off=""; }

pass()    { printf '  %sPASS%s  %s\n' "$c_ok"   "$c_off" "$*"; }
fail()    { printf '  %sFAIL%s  %s\n' "$c_bad"  "$c_off" "$*"; }
warn()    { printf '  %sWARN%s  %s\n' "$c_warn" "$c_off" "$*"; }
info()    { printf '        %s\n' "$*"; }
section() { printf '\n%s%s%s\n' "$c_b" "$*" "$c_off"; }
die()     { printf '\n%sFATAL%s %s\n\n' "$c_bad" "$c_off" "$*" >&2; exit 1; }

# Refuse to proceed unless the operator types the exact expected word.
# Deliberately not y/n: reflexive "y" is how people confirm things they have
# not read.
confirm_exact() {  # confirm_exact <word> <prompt>
	local want="$1" prompt="$2" got
	printf '%s\n' "$prompt"
	read -r -p "Type '${want}' to continue: " got
	[[ "$got" == "$want" ]] || die "not confirmed (got '${got}')"
}

require_bins() {
	local b missing=()
	for b in "$@"; do command -v "$b" >/dev/null 2>&1 || missing+=("$b"); done
	[[ ${#missing[@]} -eq 0 ]] || die "missing required tools: ${missing[*]}"
}

# Refuse to run a ceremony on a machine that is not actually air-gapped.
require_airgap() {
	local ifpath ifname state bad=0
	for ifpath in /sys/class/net/*; do
		ifname="$(basename "$ifpath")"
		[[ "$ifname" == "lo" ]] && continue
		state="$(cat "$ifpath/operstate" 2>/dev/null || echo unknown)"
		[[ "$state" == "up" ]] && { fail "interface ${ifname} is UP"; bad=1; }
	done
	ip route show default 2>/dev/null | grep -q . && { fail "a default route exists"; bad=1; }
	[[ $bad -eq 0 ]] || die "not air-gapped. Unplug the cable and re-run ceremony-selftest."
	pass "air gap confirmed"
}

# ---------------------------------------------------------------------------
# THE CIRCULARITY CHECK
#
# Encrypting a backup to a key that is inside that backup produces a file only
# recoverable by the thing it exists to recover. It is silent at ceremony time
# and total at recovery time.
#
# This walks the archive, derives the public key of every age identity it
# finds, and refuses if any of them matches the intended recipient.
#
# Returns 0 if safe, dies otherwise.
# ---------------------------------------------------------------------------
assert_not_circular() {  # assert_not_circular <dir> <recipient-pubkey-or-empty>
	local dir="$1" recipient="${2:-}"
	local f pub found=0

	# Passphrase-based encryption depends on no key material at all, which is
	# precisely why it is the default for root secrets.
	if [[ -z "$recipient" ]]; then
		pass "passphrase-based encryption: no key dependency to be circular"
		return 0
	fi

	section "Circularity check"
	info "intended recipient: ${recipient}"

	while IFS= read -r -d '' f; do
		# An age identity file contains a line beginning AGE-SECRET-KEY-
		grep -qs '^AGE-SECRET-KEY-' "$f" || continue
		found=1
		pub="$(age-keygen -y "$f" 2>/dev/null || true)"
		[[ -n "$pub" ]] || { warn "could not derive public key from $(basename "$f")"; continue; }
		info "archive contains identity -> ${pub}"
		if [[ "$pub" == "$recipient" ]]; then
			fail "archive contains the private identity for the recipient"
			die "CIRCULAR: this archive could only be decrypted by a key stored
      inside it. Encrypt with a passphrase instead (drop -r), or use a
      recipient that is independently recoverable and NOT in this archive."
		fi
	done < <(find "$dir" -type f -print0)

	if [[ $found -eq 1 ]]; then
		pass "no archived identity matches the recipient"
	else
		pass "no age identities found in archive"
	fi

	# A second, cruder net: a recipient whose public key appears verbatim
	# anywhere in the archive is at minimum worth stopping over.
	if grep -rqs -- "$recipient" "$dir" 2>/dev/null; then
		warn "the recipient public key appears somewhere in the archive"
		info "that alone is not fatal, but confirm it is not the matching identity"
	fi
	return 0
}

# Warn about other dependency traps that are not mechanically detectable.
print_dependency_reminders() {
	section "Dependency reminders"
	cat <<'EOF'
        Before you finish, confirm each of these is FALSE:

          [ ] The passphrase is stored only in a password manager unlocked
              by a YubiKey that this archive backs up
          [ ] The only copy of the passphrase is on the encrypted volume
          [ ] This archive is SOPS-encrypted into your infrastructure repo
              using an identity that is inside this archive
          [ ] Every passphrase share is going to the same physical location

        If any is TRUE, stop and restructure before burning anything.
EOF
}

# ---------------------------------------------------------------------------
# WRITE-ONCE MEDIA CHECK
#
# The entire archive design rests on the disc being physically unrewritable.
# A CD-RW in the tray passes every other check and silently voids that. This
# is an invariant, not guidance.
#
# Parses `dvd+rw-mediainfo` output. Kept as a separate function taking text so
# it can be unit-tested against captured fixtures without a drive attached.
# ---------------------------------------------------------------------------
classify_media() {  # classify_media <mediainfo-text> -> writeonce|rewritable|blank|unknown
	local t="$1"
	# Mirror media are rewritable regardless of what else they claim.
	if grep -qiE 'Mounted Media:.*(CD-RW|DVD-RW|DVD\+RW|DVD-RAM|BD-RE)' <<<"$t"; then
		echo rewritable; return
	fi
	if grep -qiE 'Mounted Media:.*(CD-R|DVD-R|DVD\+R|BD-R)' <<<"$t"; then
		echo writeonce; return
	fi
	grep -qi 'no media mounted\|no medium found' <<<"$t" && { echo blank; return; }
	echo unknown
}

assert_write_once() {  # assert_write_once <device>
	local dev="$1" out kind
	if ! command -v dvd+rw-mediainfo >/dev/null 2>&1; then
		warn "dvd+rw-mediainfo not available -- cannot confirm the media is write-once"
		info "verify by hand that this is a CD-R, not a CD-RW, before continuing"
		return 0
	fi
	out="$(dvd+rw-mediainfo "$dev" 2>&1)"
	kind="$(classify_media "$out")"
	case "$kind" in
		writeonce)
			pass "media is write-once ($(grep -m1 -i 'Mounted Media:' <<<"$out" | sed 's/.*Media:[[:space:]]*//'))"
			return 0 ;;
		rewritable)
			fail "media is REWRITABLE ($(grep -m1 -i 'Mounted Media:' <<<"$out" | sed 's/.*Media:[[:space:]]*//'))"
			die "The archive design assumes the disc cannot be silently rewritten.
      Replace it with a CD-R or DVD-R and re-run." ;;
		blank)
			fail "no media detected in ${dev}"
			die "insert a blank CD-R and re-run" ;;
		*)
			warn "could not determine media type; raw output follows"
			sed 's/^/        /' <<<"$out"
			confirm_exact "cd-r" "Confirm by hand that this is write-once media."
			return 0 ;;
	esac
}

# ===========================================================================
# SSH CERTIFICATE AUTHORITY CEREMONY
#
# Helpers for ceremony-ssh-ca.sh. The pure ones (no hardware, no prompts) are
# unit-tested in tests/cases/70-ssh-ca.sh; the interactive assert_* wrappers
# are exercised only in tier 3. Keeping the logic here, not in the script,
# means the slot/policy derivation and the verification parsing have exactly
# one definition and one set of tests.
# ===========================================================================

# --- slot and policy derivation -------------------------------------------
# One source of truth for which PIV slot and which touch/PIN policy each CA
# lands in. ceremony-ssh-ca.sh must call these, never write "9a"/"9c" inline.
#
#   host CA -> slot 9a, touch=always  pin=always   (signs once per host/year;
#              the touch is affordable and the always-PIN is a second gate)
#   user CA -> slot 9c, touch=cached  pin=always   (batch signing; the 15s
#              touch cache makes a run of certs workable, PIN still every op)
ca_slot() {  # ca_slot <host|user>
	case "$1" in
		host) printf '9a' ;;
		user) printf '9c' ;;
		*) return 1 ;;
	esac
}
ca_touch_policy() {  # ca_touch_policy <host|user>
	case "$1" in
		host) printf 'always' ;;
		user) printf 'cached' ;;
		*) return 1 ;;
	esac
}
ca_pin_policy() {  # ca_pin_policy <host|user>
	case "$1" in
		host|user) printf 'always' ;;
		*) return 1 ;;
	esac
}
ca_policy_flags() {  # ca_policy_flags <host|user> -> flags for `ykman piv keys import`
	local kind="$1" t p
	t="$(ca_touch_policy "$kind")" || return 1
	p="$(ca_pin_policy   "$kind")" || return 1
	printf -- '--pin-policy=%s --touch-policy=%s' "$p" "$t"
}

# --- concentration risk: twin token vs passphrase shares -----------------
# assert_not_circular catches "recovery depends on what it recovers". This is
# different: the Key 3 twin and enough shares to rebuild the passphrase must
# not sit in ONE place, or that place alone reconstructs everything. Not
# mechanically derivable from the archive -- it depends on where paper goes --
# so it is a prompt plus this comparison.
normalize_location() {  # trim, collapse internal whitespace, casefold
	local s="$*"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s" | tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]'
}
# locations_collide <twin> <share>...
#   exit 0  -> collision (twin shares a location with a share, OR any input is
#              blank: an unrecorded location cannot be certified as distinct)
#   exit 1  -> all distinct
locations_collide() {
	local twin; twin="$(normalize_location "$1")"; shift
	[[ -z "$twin" ]] && return 0
	local s n
	for s in "$@"; do
		n="$(normalize_location "$s")"
		[[ -z "$n" ]] && return 0
		[[ "$n" == "$twin" ]] && return 0
	done
	return 1
}
assert_distinct_locations() {  # assert_distinct_locations <num-shares>
	local n="${1:?}" twin=() shares=() i loc
	section "Concentration-risk check"
	cat <<'EOF'
        The Key 3 twin and the passphrase shares are the two halves of
        recovery. If the twin lives with enough shares to rebuild the
        passphrase, that one location can recover everything on its own --
        which is the failure this split exists to prevent.

        Name the physical location of each. Be specific and consistent --
        use the exact wording you already wrote on the planning worksheet,
        not a different abbreviation each time.
EOF
	read -r -p "  Key 3 twin location: " loc
	twin=("$loc")
	for ((i = 1; i <= n; i++)); do
		read -r -p "  Passphrase share ${i} location: " loc
		shares+=("$loc")
	done
	if locations_collide "${twin[0]}" "${shares[@]}"; then
		fail "the twin shares a location with a passphrase share (or a location was left blank)"
		die "CONCENTRATION RISK: the Key 3 twin and a passphrase share are
      recorded as living in the same place. One location must not be able
      to reconstruct both the token and the archive passphrase. Separate
      them, or record the real distinct locations, and re-run."
	fi
	pass "twin and every passphrase share are in distinct, named locations"
}

# --- smartcard reader count --------------------------------------------
# Zero readers is a dead ceremony. More than one is ambiguity about which
# token is about to be written to, and the script must refuse rather than
# guess. Pure counter takes `opensc-tool --list-readers`-style text.
count_pcsc_readers() {  # count_pcsc_readers <text>
	printf '%s\n' "$1" | grep -cE '^[[:space:]]*[0-9]+[[:space:]]' || true
}
assert_one_reader() {  # assert_one_reader -- reads live state
	local out n
	if command -v opensc-tool >/dev/null 2>&1; then
		out="$(opensc-tool --list-readers 2>/dev/null || true)"
	else
		out="$(pcsc_scan -r 2>/dev/null || true)"
	fi
	n="$(count_pcsc_readers "$out")"
	case "$n" in
		1) pass "exactly one card reader visible" ;;
		0) fail "no card reader visible"
		   die "No token is present. Insert the YubiKey you intend to
      provision and re-run. Do not proceed to key generation without it." ;;
		*) fail "${n} card readers visible"
		   die "More than one reader is present and the script will not guess
      which token you mean to write to. Remove every token except the one
      you are provisioning, then re-run." ;;
	esac
}

# --- PKCS#11 module path ---------------------------------------------
# Never hardcoded. The unversioned libykcs11.so symlink is present on Debian
# trixie's `ykcs11` package but its location varies by distribution and
# release; deriving it here is what makes that variation irrelevant. A miss
# is fatal -- signing would otherwise fail mid-ceremony with no network.
ykcs11_module_path() {
	local m
	m="$(ls /usr/lib/*/libykcs11.so* /usr/lib/libykcs11.so* /usr/lib64/*/libykcs11.so* 2>/dev/null \
		| sort | head -n1)"
	[[ -n "$m" && -r "$m" ]] || return 1
	printf '%s\n' "$m"
}

# --- factory PIV secrets ------------------------------------------------
# A CA key on a token still holding a factory PIN/PUK/management key is a live
# exposure. All three are generated during the ceremony and archived; these
# check none of the defaults survived.
PIV_FACTORY_PIN='123456'
PIV_FACTORY_PUK='12345678'
PIV_FACTORY_MGMT='010203040506070801020304050607080102030405060708'
piv_secret_is_factory() {  # piv_secret_is_factory <pin|puk|mgmt> <value>
	local kind="$1" val="$2"
	case "$kind" in
		pin)  [[ "$val" == "$PIV_FACTORY_PIN"  ]] ;;
		puk)  [[ "$val" == "$PIV_FACTORY_PUK"  ]] ;;
		mgmt) [[ "${val,,}" == "$PIV_FACTORY_MGMT" ]] ;;
		*) return 2 ;;
	esac
}

# --- certificate verification parsing --------------------------------
# All take the text of `ssh-keygen -L -f <cert>`. Parsing it, rather than
# trusting that signing exited 0, is the point: a token that was written to
# but never signed with is unverified.
cert_type() {  # -> user|host|""
	grep -m1 '^[[:space:]]*Type:' <<<"$1" | grep -oE '(user|host) certificate' | awk '{print $1}'
}
cert_ca_fingerprint() {  # -> SHA256:...
	grep -m1 '^[[:space:]]*Signing CA:' <<<"$1" | grep -oE 'SHA256:[A-Za-z0-9+/=]+'
}
cert_key_id() {  # -> the Key ID string, unquoted
	grep -m1 '^[[:space:]]*Key ID:' <<<"$1" | sed -E 's/.*Key ID: "([^"]*)".*/\1/'
}
cert_validity() {  # -> "from ... to ..."
	grep -m1 '^[[:space:]]*Valid:' <<<"$1" | sed -E 's/.*Valid:[[:space:]]*//'
}
cert_principals() {  # -> comma-separated, in listed order; "" if none
	awk '
		/^[[:space:]]*Principals:/ { grab = 1; next }
		grab && /^[[:space:]]*(Critical Options|Extensions|Serial|Valid):/ { grab = 0 }
		grab && /[^[:space:]]/ { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }
	' <<<"$1" | paste -sd',' -
}

# ssh_pubkey_body <keyfile>  -- the base64 blob only, no type prefix, no
# comment. Comparing this is how "the recovered key matches what the token
# reports" is checked: `ssh-keygen -y` and `ssh-keygen -D ... -e` agree on the
# body but not the comment.
ssh_pubkey_body() {  # ssh_pubkey_body <public-key-file>
	awk 'NF >= 2 { print $2; exit }' "$1"
}

assert_cert_matches_intent() {
	# assert_cert_matches_intent <cert-file> <expected-principal> <expected-ca-fpr> [<expected-type>]
	local cert="$1" want_princ="$2" want_ca="$3" want_type="${4:-}"
	local L; L="$(ssh-keygen -L -f "$cert" 2>/dev/null)" \
		|| die "ssh-keygen -L could not read ${cert} -- signing did not produce a certificate"
	local got_princ got_ca got_type got_valid
	got_princ="$(cert_principals "$L")"
	got_ca="$(cert_ca_fingerprint "$L")"
	got_type="$(cert_type "$L")"
	got_valid="$(cert_validity "$L")"

	[[ "$got_princ" == "$want_princ" ]] \
		|| die "certificate principals are '${got_princ}', expected '${want_princ}'"
	[[ -n "$got_ca" && "$got_ca" == "$want_ca" ]] \
		|| die "certificate signing-CA fingerprint is '${got_ca}', expected '${want_ca}'
      -- the token signed with a different key than intended"
	if [[ -n "$want_type" ]]; then
		[[ "$got_type" == "$want_type" ]] \
			|| die "certificate type is '${got_type}', expected '${want_type}'"
	fi
	[[ "$got_valid" == from*to* ]] \
		|| die "certificate validity window is unparseable: '${got_valid}'"

	pass "certificate: principals=${got_princ} type=${got_type:-?} CA=${got_ca}"
	info "validity: ${got_valid}"
}

assert_pubkey_identical() {  # assert_pubkey_identical <label> <keyfile-a> <keyfile-b>
	local label="$1" a="$2" b="$3" ba bb
	ba="$(ssh_pubkey_body "$a")"
	bb="$(ssh_pubkey_body "$b")"
	[[ -n "$ba" ]] || die "${label}: no key body in ${a}"
	if [[ "$ba" == "$bb" ]]; then
		pass "${label}: recovered key body is byte-identical to the token's"
	else
		fail "${label}: recovered key body does NOT match the token"
		info "recovered: ${ba:0:48}..."
		info "token:     ${bb:0:48}..."
		die "${label}: the archive does not contain the key the token holds.
      Do not end the ceremony -- the material is still in tmpfs."
	fi
}
