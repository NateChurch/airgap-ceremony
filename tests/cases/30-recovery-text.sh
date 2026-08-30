# A future recoverer follows the text on the disc, not the flags someone used
# years earlier. The two must agree.
SCRIPT="$REPO_ROOT/config/includes.chroot/usr/local/bin/archive-ceremony.sh"

body="$(sed -n '/RECOVERY.txt/,/^EOF$/p' "$SCRIPT")"
assert_contains "$body" 'THRESHOLD' "RECOVERY.txt interpolates THRESHOLD"
assert_contains "$body" 'SHARES'    "RECOVERY.txt interpolates SHARES"

if grep -qE 'ssss-combine -t 2$|any 2 of the 3' <<<"$body"; then
	no "no hardcoded 2-of-3 in RECOVERY.txt" "found a literal threshold"
else
	ok "no hardcoded 2-of-3 in RECOVERY.txt"
fi

if grep -qE 'RECIPIENT' "$SCRIPT"; then
	no "recipient mode fully removed" "RECIPIENT still referenced"
else
	ok "recipient mode fully removed"
fi

if grep -q 'age -r ' "$SCRIPT"; then
	no "no age -r invocation remains" ""
else
	ok "no age -r invocation remains"
fi

# age -p cannot be piped; it reads /dev/tty. A piped invocation is a silent
# no-op that produces an archive encrypted with an empty passphrase prompt.
if grep -qE '\|[[:space:]]*age -p' "$SCRIPT"; then
	no "age -p is not fed from a pipe" "found a piped 'age -p' -- it reads /dev/tty"
else
	ok "age -p is not fed from a pipe"
fi

if grep -q 'AGE_PASSPHRASE' "$SCRIPT"; then
	no "no invented AGE_PASSPHRASE env var" "age has no such variable"
else
	ok "no invented AGE_PASSPHRASE env var"
fi
