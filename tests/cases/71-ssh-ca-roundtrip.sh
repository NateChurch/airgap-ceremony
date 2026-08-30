# SSH CA ceremony -- tier 2. A real certificate round trip with NO hardware:
# generate a P-256 CA on disk, sign user and host certificates with the real
# ssh-keygen, and drive the ceremony's verification helpers against the actual
# `ssh-keygen -L` output. This is what proves cert_* / assert_cert_matches_intent
# / assert_pubkey_identical parse and judge real output correctly -- the tier-1
# case only feeds them a captured fixture.
#
# The token path (ssh-keygen -D through ykcs11, PIN and touch) is tier 3 only.

[[ "$TEST_TIER" -ge 2 ]] || { skip "tier 2 not requested" "run with -t 2"; return; }
for t in ssh-keygen; do
	have "$t" || { skip "ssh CA round trip" "missing: $t"; return; }
done

. "$REPO_ROOT/config/includes.chroot/usr/local/lib/ceremony-lib.sh"

D="$(mktemp -d)"
trap 'rm -rf "$D"' RETURN
rc_of() { ( "$@" ) >/dev/null 2>&1; echo $?; }

# --- a real P-256 CA, exactly as the ceremony generates it -----------
ssh-keygen -q -t ecdsa -b 256 -N '' -C fablab-ssh-user-ca -f "$D/user-ca"
ssh-keygen -q -t ecdsa -b 256 -N '' -C fablab-ssh-host-ca -f "$D/host-ca"
ssh-keygen -q -t ed25519 -N '' -C throwaway -f "$D/target"
USER_FPR="$(ssh-keygen -l -f "$D/user-ca.pub" | awk '{print $2}')"
HOST_FPR="$(ssh-keygen -l -f "$D/host-ca.pub" | awk '{print $2}')"
assert_contains "$USER_FPR" "SHA256:" "generated a P-256 user CA with a SHA256 fingerprint"

# --- sign a USER certificate ------------------------------------------
ssh-keygen -q -s "$D/user-ca" -I test-id -n alice,bob -V +1d "$D/target.pub"
L="$(ssh-keygen -L -f "$D/target-cert.pub")"

assert_eq "$(cert_type "$L")"           user       "signed a user certificate"
assert_eq "$(cert_principals "$L")"     alice,bob  "cert_principals reads real ssh-keygen -L output"
assert_eq "$(cert_ca_fingerprint "$L")" "$USER_FPR" "cert_ca_fingerprint matches ssh-keygen -l on the CA"
assert_eq "$(cert_key_id "$L")"         test-id    "cert_key_id matches -I"
[[ "$(cert_validity "$L")" == from*to* ]] && ok "cert_validity parses the window" \
	|| no "cert_validity parses the window" "got '$(cert_validity "$L")'"

# --- assert_cert_matches_intent: the positive case ------------------
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" alice,bob "$USER_FPR" user)" 0 \
	"assert_cert_matches_intent passes when principals, CA and type all match"

# --- assert_cert_matches_intent: negative cases (written first) -----
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" mallory "$USER_FPR" user)" 1 \
	"rejects a wrong principal"
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" alice "$USER_FPR" user)" 1 \
	"rejects a subset of principals (alice, not alice,bob)"
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" alice,bob "$HOST_FPR" user)" 1 \
	"rejects the wrong signing CA -- the token signed with a different key than intended"
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" alice,bob SHA256:deadbeef user)" 1 \
	"rejects a bogus CA fingerprint"
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" alice,bob "$USER_FPR" host)" 1 \
	"rejects a user cert when a host cert was expected"
assert_eq "$(rc_of assert_cert_matches_intent "$D/nonexistent-cert.pub" alice,bob "$USER_FPR" user)" 1 \
	"rejects a missing certificate file (signing produced nothing)"
assert_eq "$(rc_of assert_cert_matches_intent "$D/target.pub" alice,bob "$USER_FPR" user)" 1 \
	"rejects a plain public key that is not a certificate"

# --- sign a HOST certificate ---------------------------------------
ssh-keygen -q -s "$D/host-ca" -h -I h -n host-a.example.com,host-b.example.com -V +52w "$D/target.pub"
LH="$(ssh-keygen -L -f "$D/target-cert.pub")"
assert_eq "$(cert_type "$LH")" host "signed a host certificate (-h)"
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" host-a.example.com,host-b.example.com "$HOST_FPR" host)" 0 \
	"host cert with two principals verifies"
assert_eq "$(rc_of assert_cert_matches_intent "$D/target-cert.pub" host-a.example.com,host-b.example.com "$HOST_FPR" user)" 1 \
	"host cert is rejected when a user cert was expected"

# --- assert_pubkey_identical: the recovered-key match proof ---------
ssh-keygen -y -f "$D/user-ca" > "$D/user-ca.recovered.pub"
assert_eq "$(rc_of assert_pubkey_identical rec "$D/user-ca.recovered.pub" "$D/user-ca.pub")" 0 \
	"assert_pubkey_identical passes when the recovered key body matches"
assert_eq "$(rc_of assert_pubkey_identical rec "$D/user-ca.recovered.pub" "$D/host-ca.pub")" 1 \
	"assert_pubkey_identical fails on a different key"

# a single flipped base64 character in the body must be caught
body="$(ssh_pubkey_body "$D/user-ca.pub")"
first="${body:0:1}"; rest="${body:1}"
flip=$([ "$first" = "A" ] && echo B || echo A)
printf 'ecdsa-sha2-nistp256 %s%s tampered\n' "$flip" "$rest" > "$D/tampered.pub"
assert_eq "$(rc_of assert_pubkey_identical rec "$D/user-ca.recovered.pub" "$D/tampered.pub")" 1 \
	"assert_pubkey_identical catches a single flipped byte in the key body"

# --- ssh-keygen -y on a PEM private key (what recovery actually does) ---
# The archive stores CA private keys as PEM; ca_recovery_proof derives the
# public half with `ssh-keygen -y -f <pem>` and compares bodies.
cp "$D/user-ca" "$D/user-ca.pem"
ssh-keygen -q -p -N '' -m PEM -f "$D/user-ca.pem"
assert_contains "$(head -1 "$D/user-ca.pem")" "BEGIN EC PRIVATE KEY" \
	"CA private key converts to PEM (BEGIN EC PRIVATE KEY)"
ssh-keygen -y -f "$D/user-ca.pem" > "$D/from-pem.pub"
assert_eq "$(ssh_pubkey_body "$D/from-pem.pub")" "$(ssh_pubkey_body "$D/user-ca.pub")" \
	"public half derived from the PEM private key matches the original"
