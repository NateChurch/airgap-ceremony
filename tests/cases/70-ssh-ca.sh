# SSH CA ceremony -- tier 1. Pure logic only: slot/policy derivation,
# location-collision detection, reader counting, factory-secret detection, and
# the certificate-verification parsers run against captured `ssh-keygen -L`
# text. No hardware, no crypto, no ssh-keygen invocation.
. "$REPO_ROOT/config/includes.chroot/usr/local/lib/ceremony-lib.sh"

SCRIPT="$REPO_ROOT/config/includes.chroot/usr/local/bin/ceremony-ssh-ca.sh"
[[ -r "$SCRIPT" ]] || { no "ceremony-ssh-ca.sh exists"; return; }

# --- slot / policy derivation -------------------------------------------
assert_eq "$(ca_slot host)" 9a "host CA -> slot 9a"
assert_eq "$(ca_slot user)" 9c "user CA -> slot 9c"
( ca_slot bogus ) ; assert_eq $? 1 "ca_slot rejects an unknown kind"

assert_eq "$(ca_touch_policy host)" always "host CA touch policy is always"
assert_eq "$(ca_touch_policy user)" cached "user CA touch policy is cached (batch signing)"
assert_eq "$(ca_pin_policy host)"   always "host CA PIN policy is always"
assert_eq "$(ca_pin_policy user)"   always "user CA PIN policy is always"

assert_eq "$(ca_policy_flags host)" "--pin-policy=always --touch-policy=always" \
	"host policy flags"
assert_eq "$(ca_policy_flags user)" "--pin-policy=always --touch-policy=cached" \
	"user policy flags"

# --- concentration-risk detection ------------------------------------
assert_eq "$(normalize_location '  Bank   BOX ')" "bank box" \
	"normalize_location trims, collapses, casefolds"

( locations_collide "Bank box" "Home safe" "bank   BOX" "Cousin" )
assert_eq $? 0 "twin location equal to a share location -> collision"
( locations_collide "Bank box" "Home safe" "Office" "Cousin" )
assert_eq $? 1 "twin distinct from every share -> no collision"
( locations_collide "Bank box" "Home safe" "" "Cousin" )
assert_eq $? 0 "a blank share location cannot be certified distinct -> collision"
( locations_collide "" "Home safe" "Office" )
assert_eq $? 0 "a blank twin location cannot be certified distinct -> collision"
( locations_collide "Safe deposit box 12" "safe deposit box 12" )
assert_eq $? 0 "collision detection is case- and whitespace-insensitive"

# --- reader counting -------------------------------------------------
r0="No smart card readers found."
r1=$'Nr.  Card  Features  Name\n0    Yes             Yubico YubiKey CCID 00 00'
r2=$'Nr.  Card  Features  Name\n0    Yes             Yubico A 00 00\n1    No              Yubico B 01 00'
assert_eq "$(count_pcsc_readers "$r0")" 0 "zero readers counted"
assert_eq "$(count_pcsc_readers "$r1")" 1 "one reader counted"
assert_eq "$(count_pcsc_readers "$r2")" 2 "two readers counted"

# --- factory PIV secret detection ----------------------------------
( piv_secret_is_factory pin  123456 )                                             ; assert_eq $? 0 "factory PIN detected"
( piv_secret_is_factory pin  481902 )                                             ; assert_eq $? 1 "non-factory PIN passes"
( piv_secret_is_factory puk  12345678 )                                           ; assert_eq $? 0 "factory PUK detected"
( piv_secret_is_factory mgmt 010203040506070801020304050607080102030405060708 )  ; assert_eq $? 0 "factory management key detected"
( piv_secret_is_factory mgmt 0102030405060708010203040506070801020304050607FF )  ; assert_eq $? 1 "non-factory management key passes"
( piv_secret_is_factory bogus x )                                                 ; assert_eq $? 2 "unknown secret kind is an error"

# --- ykcs11 module path -------------------------------------------
if m="$(ykcs11_module_path)"; then
	[[ -r "$m" ]] && ok "ykcs11_module_path returns a readable file ($m)" \
		|| no "ykcs11_module_path returns a readable file" "got '$m'"
else
	ok "ykcs11_module_path fails cleanly when no module is installed (this host)"
fi

# --- certificate parsers, against captured ssh-keygen -L output ------
read -r -d '' LCERT <<'EOF'
id_test-cert.pub:
        Type: ssh-ed25519-cert-v01@openssh.com user certificate
        Public key: ED25519-CERT SHA256:xn6ksOgbfK1xqAHo6Z10zTSp1ubxD6xdeOnyAMjtwrk
        Signing CA: ECDSA SHA256:CVPcejE4gZEdZrygV/bmJ7Q6yBD12bCAVpmesqtiebg (using ecdsa-sha2-nistp256)
        Key ID: "ceremony-verify-user"
        Serial: 0
        Valid: from 2026-08-28T20:53:00 to 2026-08-29T20:54:06
        Principals:
                ceremony-verify-user
        Critical Options: (none)
        Extensions:
                permit-pty
EOF
assert_eq "$(cert_type "$LCERT")"           user "cert_type reads 'user certificate'"
assert_eq "$(cert_ca_fingerprint "$LCERT")" "SHA256:CVPcejE4gZEdZrygV/bmJ7Q6yBD12bCAVpmesqtiebg" \
	"cert_ca_fingerprint extracts the signing-CA SHA256"
assert_eq "$(cert_key_id "$LCERT")"         ceremony-verify-user "cert_key_id unquotes the Key ID"
assert_eq "$(cert_principals "$LCERT")"     ceremony-verify-user "cert_principals lists the principal"
assert_contains "$(cert_validity "$LCERT")" "from 2026-08-28T20:53:00 to 2026-08-29T20:54:06" \
	"cert_validity returns the window"

read -r -d '' LHOST <<'EOF'
        Type: ssh-ed25519-cert-v01@openssh.com host certificate
        Signing CA: ECDSA SHA256:AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKKK (using ecdsa-sha2-nistp256)
        Key ID: "h"
        Valid: from 2026-08-28T00:00:00 to 2027-08-27T00:00:00
        Principals:
                host-a.example.com
                host-b.example.com
        Critical Options: (none)
EOF
assert_eq "$(cert_type "$LHOST")"       host "cert_type reads 'host certificate'"
assert_eq "$(cert_principals "$LHOST")" "host-a.example.com,host-b.example.com" \
	"cert_principals joins multiple principals in order"

assert_eq "$(printf 'ecdsa-sha2-nistp256 AAAABODY== a comment\n' | { read -r _ b _; echo "$b"; })" \
	"AAAABODY==" "sanity: pubkey body is field 2"

# --- ceremony-ssh-ca.sh: no hand-typed slots or module paths --------
body="$(grep -vE '^\s*#' "$SCRIPT")"
if grep -qE "(^|[^a-z_])9[ac]([^0-9a-z]|$)" <<<"$body"; then
	no "no bare PIV slot id in ceremony-ssh-ca.sh" \
		"$(grep -nE "(^|[^a-z_])9[ac]([^0-9a-z]|$)" <<<"$body")"
else
	ok "no bare PIV slot id in ceremony-ssh-ca.sh (slots come from ca_slot)"
fi
grep -qE '/libykcs11\.so' "$SCRIPT" \
	&& no "no hardcoded libykcs11 path in ceremony-ssh-ca.sh" \
	|| ok "no hardcoded libykcs11 path in ceremony-ssh-ca.sh (derived into YKCS11_MODULE)"
grep -qE '\|\s*ssh-keygen +-D' "$SCRIPT" \
	&& no "ssh-keygen -D is not fed from a pipe" \
	|| ok "ssh-keygen -D is not fed from a pipe"

# --- ceremony-ssh-ca.sh: the invariants are wired in --------------
for tok in \
	'assert_distinct_locations' 'assert_one_reader' 'assert_cert_matches_intent' \
	'assert_pubkey_identical' 'assert_no_factory_piv_secrets' \
	'ceremony-lib.sh' 'archive-ceremony.sh' 'rehearse-recovery.sh'; do
	grep -qF "$tok" "$SCRIPT" && ok "ceremony-ssh-ca.sh uses ${tok}" \
		|| no "ceremony-ssh-ca.sh uses ${tok}" "not referenced"
done
grep -qE 'BASH_SOURCE\[0\]. ==| == .\$\{0\}|"\$\{0\}"' "$SCRIPT" \
	&& ok "ceremony-ssh-ca.sh guards main() so it can be sourced for testing" \
	|| no "ceremony-ssh-ca.sh guards main() behind a source check"
