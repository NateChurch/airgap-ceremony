#!/usr/bin/env bash
# Test assertions. Sourced by run-tests.sh and by each case file.

TESTS_RUN=0; TESTS_PASS=0; TESTS_FAIL=0; TESTS_SKIP=0
_c_ok=$'\033[32m'; _c_bad=$'\033[31m'; _c_warn=$'\033[33m'; _c_off=$'\033[0m'
[[ -t 1 ]] || { _c_ok=""; _c_bad=""; _c_warn=""; _c_off=""; }

ok()   { TESTS_RUN=$((TESTS_RUN+1)); TESTS_PASS=$((TESTS_PASS+1))
         printf '    %sok%s   %s\n' "$_c_ok" "$_c_off" "$1"; }
no()   { TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAIL=$((TESTS_FAIL+1))
         printf '    %sFAIL%s %s\n' "$_c_bad" "$_c_off" "$1"
         [[ -n "${2:-}" ]] && printf '           %s\n' "$2"; }
skip() { TESTS_RUN=$((TESTS_RUN+1)); TESTS_SKIP=$((TESTS_SKIP+1))
         printf '    %sskip%s %s\n' "$_c_warn" "$_c_off" "$1"
         [[ -n "${2:-}" ]] && printf '           %s\n' "$2"; }

assert_eq() {  # assert_eq <actual> <expected> <label>
	[[ "$1" == "$2" ]] && ok "$3" || no "$3" "expected '$2', got '$1'"
}
assert_contains() {  # assert_contains <haystack> <needle> <label>
	[[ "$1" == *"$2"* ]] && ok "$3" || no "$3" "output did not contain '$2'"
}
assert_exit() {  # assert_exit <expected-code> <label> -- <command...>
	local want="$1" label="$2"; shift 3
	"$@" >/dev/null 2>&1; local got=$?
	[[ $got -eq $want ]] && ok "$label" || no "$label" "expected exit $want, got $got"
}
have() { command -v "$1" >/dev/null 2>&1; }
