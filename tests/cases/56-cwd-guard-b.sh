# Regression guard for the run-tests.sh cwd leak (part B of two).
#
# Runs immediately after 56-cwd-guard-a, which chdir'd to / and recorded it.
# The runner must reset cwd before sourcing this file, or every case after a
# chdir silently fails to source.

CWD_GUARD_MARK="${TMPDIR:-/tmp}/ceremony-cwd-guard.$$"
left_at="$(cat "$CWD_GUARD_MARK" 2>/dev/null || echo '<not recorded>')"
rm -f "$CWD_GUARD_MARK"

# The test is only meaningful if part A actually moved the cwd.
if [[ "$left_at" != "$TESTS_DIR" && "$left_at" != '<not recorded>' ]]; then
	ok "part A did leak the cwd (to $left_at) -- the reset below is a real test"
else
	no "part A did leak the cwd" "recorded '$left_at'; expected something other than $TESTS_DIR"
fi

assert_eq "$PWD" "$TESTS_DIR" "runner reset cwd to the tests dir before sourcing part B"

if [[ -f "$PWD/lib.sh" && -d "$PWD/cases" ]]; then
	ok "sourced from a directory where a tests/-relative '. cases/NN.sh' resolves"
else
	no "sourced from a directory where a tests/-relative '. cases/NN.sh' resolves" \
		"pwd=$PWD"
fi

if declare -F assert_eq >/dev/null && declare -F ok >/dev/null && declare -F have >/dev/null; then
	ok "lib.sh helpers are defined in this case's scope"
else
	no "lib.sh helpers are defined in this case's scope"
fi
