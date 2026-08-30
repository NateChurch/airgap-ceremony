#!/usr/bin/env bash
# run-tests.sh [-t TIER] [case-name...]
#
#   -t 1   unit only: pure logic, no crypto tools, runs anywhere (default)
#   -t 2   unit + integration: needs age, ssss, and a pty
#   -t 3   refuses -- tier 3 is the manual dry run. See `make dry-run`.
#
# Tier 3 is deliberately NOT automated. The riskiest code paths are the ones
# that touch a real terminal, a real burner, and a real token; a harness that
# fakes those would make broken code pass.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
TESTS_DIR="$PWD"
. ./lib.sh

TIER=1
while [[ $# -gt 0 ]]; do
	case "$1" in
		-t) TIER="${2:?}"; shift 2 ;;
		-h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) break ;;
	esac
done

if [[ "$TIER" == "3" ]]; then
	echo "Tier 3 is the manual dry run. Run: make dry-run" >&2
	exit 2
fi

export REPO_ROOT="$(cd .. && pwd)"
export TEST_TIER="$TIER"
export PATH="$PWD/mocks:$PATH"

cases=()
if [[ $# -gt 0 ]]; then
	for a in "$@"; do cases+=("cases/${a}"*.sh); done
else
	cases=(cases/*.sh)
fi

printf '\033[1mCeremony test suite\033[0m  (tier %s)\n' "$TIER"
total_fail=0
for c in "${cases[@]}"; do
	# A case file may cd elsewhere and not cd back (50-repo-hygiene and
	# 55-static-lint do). This is the ONE place cwd is restored -- do not push
	# it into the cases (a `trap ... RETURN` in a sourced file lingers and
	# fires after every later case too, which hid this very bug). Without this
	# line, every case after a chdir resolves `. "cases/NN.sh"` against the
	# wrong directory and silently fails to source -- how 60-roundtrip went
	# unrun for months. The TESTS_RUN==0 check below turns that silence loud.
	cd "$TESTS_DIR" || exit 1
	if [[ ! -f "$c" ]]; then
		# An unexpanded glob (no cases matched) is fine; a named case that has
		# gone missing means the cwd moved out from under a relative source path.
		[[ "$c" == *'*'* ]] && continue
		printf '\n  \033[31mFAIL\033[0m case %s not found from %s -- an earlier case leaked its cwd\n' "$c" "$PWD"
		total_fail=$((total_fail + 1))
		continue
	fi
	printf '\n  %s\n' "$(basename "$c" .sh)"
	TESTS_RUN=0; TESTS_PASS=0; TESTS_FAIL=0; TESTS_SKIP=0
	# shellcheck source=/dev/null
	. "$c"
	# Every real case emits at least one ok/no/skip. Zero means `. "$c"` did
	# not actually source -- the failure mode of the cwd-leak bug, where the
	# path is tests/-relative and the cwd moved. Make it loud, not silent.
	if [[ "$TESTS_RUN" -eq 0 ]]; then
		printf '    \033[31mFAIL\033[0m %s\n' \
			"case sourced 0 assertions -- did '. $c' fail? (cwd was $PWD)"
		total_fail=$((total_fail + 1))
	fi
	total_fail=$((total_fail + TESTS_FAIL))
	grand_run=$((${grand_run:-0} + TESTS_RUN))
	grand_pass=$((${grand_pass:-0} + TESTS_PASS))
	grand_skip=$((${grand_skip:-0} + TESTS_SKIP))
done

printf '\n\033[1mResult\033[0m\n'
printf '  %d run, %d passed, %d failed, %d skipped\n\n' \
	"${grand_run:-0}" "${grand_pass:-0}" "$total_fail" "${grand_skip:-0}"
[[ $total_fail -eq 0 ]] || exit 1
