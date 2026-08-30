# Tier 2. A real encrypt -> split -> combine -> decrypt -> verify round trip
# with throwaway material.
#
# This drives age through a pseudo-terminal (util-linux `script`) because
# `age -p` reads from /dev/tty by design and cannot be piped. Faking that would
# make a broken invocation pass, which is exactly the bug this suite exists to
# catch -- so the pty is real, not simulated.
#
# What this still does NOT cover, and why tier 3 exists:
#   - burning to and reading back from a physical drive
#   - dvd+rw-mediainfo against real media
#   - YubiKey / smartcard flows
#   - operator transcription, which is the actual failure mode in practice

[[ "$TEST_TIER" -ge 2 ]] || { skip "tier 2 not requested" "run with -t 2"; return; }

for t in age ssss-split ssss-combine script tar sha256sum; do
	have "$t" || { skip "integration round trip" "missing: $t"; return; }
done

D="$(mktemp -d)"
PASS="correct-horse-battery-staple-$$"

mkdir -p "$D/src"
head -c 4096 /dev/urandom > "$D/src/fake-key.bin"
echo "throwaway ceremony output, not real key material" > "$D/src/notes.txt"
( cd "$D/src" && sha256sum ./* > "$D/SHA256SUMS.txt" )
tar -C "$D/src" -cf "$D/payload.tar" .

# --- encrypt through a pty --------------------------------------------------
script -qec "age -p -o '$D/payload.tar.age' '$D/payload.tar'" /dev/null \
	>/dev/null 2>&1 <<PTY || true
$PASS
$PASS
PTY

if [[ -s "$D/payload.tar.age" ]]; then
	ok "age -p produced ciphertext through a pty"
else
	no "age -p produced ciphertext through a pty" "no output file -- check the invocation"
	rm -rf "$D"; return
fi

if ! head -c 32 "$D/payload.tar.age" | grep -q 'age-encryption'; then
	no "ciphertext carries the age header"
else
	ok "ciphertext carries the age header"
fi

# The empty-passphrase trap: if age had silently accepted a piped/empty
# passphrase, decrypting with the WRONG one would succeed.
if script -qec "age -d -o /dev/null '$D/payload.tar.age'" /dev/null \
	>/dev/null 2>&1 <<<"definitely-not-the-passphrase"; then
	no "wrong passphrase is rejected" "decrypted with an incorrect passphrase"
else
	ok "wrong passphrase is rejected"
fi

# --- split and recombine ----------------------------------------------------
SHARES="$(printf '%s' "$PASS" | ssss-split -t 2 -n 3 -w test -Q 2>/dev/null)"
n="$(wc -l <<<"$SHARES")"
assert_eq "$n" 3 "ssss-split emits 3 shares"

two="$(head -2 <<<"$SHARES")"
COMBINED="$(printf '%s\n' "$two" | ssss-combine -t 2 -Q 2>&1 | tail -1)"
assert_eq "$COMBINED" "$PASS" "any 2 of 3 shares reconstruct the passphrase"

one="$(head -1 <<<"$SHARES")"
if printf '%s\n' "$one" | timeout 5 ssss-combine -t 2 -Q >/dev/null 2>&1; then
	no "a single share does not reconstruct" "one share was accepted"
else
	ok "a single share does not reconstruct"
fi

# --- decrypt with the reconstructed passphrase ------------------------------
script -qec "age -d -o '$D/out.tar' '$D/payload.tar.age'" /dev/null \
	>/dev/null 2>&1 <<<"$COMBINED" || true

if [[ -s "$D/out.tar" ]]; then
	ok "decrypted using the reconstructed passphrase"
	mkdir -p "$D/out" && tar -C "$D/out" -xf "$D/out.tar"
	if ( cd "$D/out" && sha256sum -c "$D/SHA256SUMS.txt" >/dev/null 2>&1 ); then
		ok "recovered files match their checksums"
	else
		no "recovered files match their checksums"
	fi
else
	no "decrypted using the reconstructed passphrase" "no plaintext produced"
fi

rm -rf "$D"
