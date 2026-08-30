# The single most important safeguard in the repo. Every case here is a way
# someone could produce an archive recoverable only by the thing it recovers.
. "$REPO_ROOT/config/includes.chroot/usr/local/lib/ceremony-lib.sh"

if ! have age-keygen; then skip "age-keygen absent" "cannot derive public keys"; return; fi

D="$(mktemp -d)"
mkdir -p "$D/flat" "$D/nested/keys/deep" "$D/empty" "$D/text"
printf 'AGE-SECRET-KEY-1ABCDEF\n' > "$D/flat/id.txt"
echo "notes" > "$D/flat/notes.txt"
printf 'AGE-SECRET-KEY-1ABCDEF\n' > "$D/nested/keys/deep/id.txt"
echo "notes" > "$D/empty/notes.txt"
echo "recipient is age1external" > "$D/text/notes.txt"
PUB="$(age-keygen -y "$D/flat/id.txt")"

run_check() { ( assert_not_circular "$1" "${2:-}" ) >/dev/null 2>&1; echo $?; }

assert_eq "$(run_check "$D/flat")"              0 "passphrase mode always passes (no key dependency)"
assert_eq "$(run_check "$D/flat" "$PUB")"       1 "recipient IS the archived identity -> refuses"
assert_eq "$(run_check "$D/flat" age1other)"    0 "unrelated recipient -> allowed"
assert_eq "$(run_check "$D/nested" "$PUB")"     1 "identity nested in subdirectory -> still caught"
assert_eq "$(run_check "$D/empty" age1other)"   0 "archive with no identities -> allowed"
assert_eq "$(run_check "$D/text" age1external)" 0 "pubkey as plain text -> allowed (warns only)"

out="$( ( assert_not_circular "$D/text" age1external ) 2>&1 )"
assert_contains "$out" "appears somewhere in the archive" "plain-text pubkey produces a warning"

out="$( ( assert_not_circular "$D/flat" "$PUB" ) 2>&1 )"
assert_contains "$out" "CIRCULAR" "refusal message names the failure mode"

rm -rf "$D"
