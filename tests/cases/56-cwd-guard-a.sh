# Regression guard for the run-tests.sh cwd leak (part A of two).
#
# 50-repo-hygiene did `cd "$REPO_ROOT"` and never returned, so from
# 60-roundtrip onward `. "$c"` -- a tests/-relative path -- resolved against
# the wrong directory and silently did nothing. 60-roundtrip, the tier-2
# crypto round trip, had not run through the runner for months.
#
# This file deliberately leaks its working directory and records where it
# left it. 56-cwd-guard-b checks the runner put things back. Removing the
# runner's per-case `cd "$TESTS_DIR"` makes every case after this one fail to
# source -- the runner now reports each as "not found ... leaked its cwd".
CWD_GUARD_MARK="${TMPDIR:-/tmp}/ceremony-cwd-guard.$$"
cd / 2>/dev/null || true
printf '%s\n' "$PWD" > "$CWD_GUARD_MARK"
ok "56-cwd-guard-a left the cwd at $PWD (recorded for part B)"
