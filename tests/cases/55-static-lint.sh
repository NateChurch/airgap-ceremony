# Static analysis of every ceremony script.
#
# This exists because archive-ceremony.sh could not complete a burn from commit
# e9cf4e9 until the fix that added this case: that commit deleted the block
# assigning $STAGE but left `xorriso ... "$STAGE"` behind. Under `set -u` the
# script died at the disc-image step. Nothing caught it, because the only
# coverage of the burn path is tier 3, which is manual.
#
# The bug class is "a variable reference outlived the block that defined it."
# ShellCheck's SC2154 (referenced but not assigned) catches exactly that,
# statically, across all scripts -- so the guard is general, not a check that
# only knows the name STAGE.
cd "$REPO_ROOT" || { no "cannot cd to REPO_ROOT"; return; }

BIN_SCRIPTS=(
	config/includes.chroot/usr/local/bin/*
	config/includes.chroot/usr/local/lib/*.sh
	scripts/*.sh
	tests/run-tests.sh tests/lib.sh tests/dry-run.sh
)
SH_SCRIPTS=(
	auto/config auto/build auto/clean
	config/hooks/normal/*.hook.chroot
)

# --- parse (independent of shellcheck; runs anywhere) ----------------------
bad=""
for f in "${BIN_SCRIPTS[@]}"; do
	[[ -f "$f" ]] || continue
	bash -n "$f" 2>/dev/null || bad="$bad $f"
done
for f in "${SH_SCRIPTS[@]}"; do
	[[ -f "$f" ]] || continue
	sh -n "$f" 2>/dev/null || bad="$bad $f"
done
[[ -z "$bad" ]] && ok "every ceremony script parses" \
	|| no "every ceremony script parses" "failed:$bad"

# --- SC2154 must never be suppressed --------------------------------------
# The point of the guard is defeated if a future edit silences it inline.
sup="$(grep -rEn 'disable=[A-Za-z0-9,]*SC?2154' \
	"${BIN_SCRIPTS[@]}" "${SH_SCRIPTS[@]}" 2>/dev/null || true)"
[[ -z "$sup" ]] && ok "SC2154 is not disabled anywhere" \
	|| no "SC2154 is not disabled anywhere" "$sup"

# --- targeted regression pins: producer/consumer pairs from commit e9cf4e9 ---
# That commit deleted three producers and left their consumers in place:
#   1. $STAGE assembly in archive-ceremony.sh (the mkisofs consumer stayed)
#   2. the Makefile line staging binaries.env into the chroot (the asserting
#      hook 0050-stage-env stayed -- make build could not finish)
#   3. the .build/build-start stamp (the "did this build make its own ISO"
#      check stayed, but `iso -nt <missing>` is vacuously true)
# Each is cheap to pin and needs no tools.

AC=config/includes.chroot/usr/local/bin/archive-ceremony.sh
if [[ -f "$AC" ]]; then
	asn="$(grep -n '^[[:space:]]*STAGE=' "$AC" | head -1 | cut -d: -f1)"
	use="$(grep -n '"\$STAGE"\|\${STAGE}' "$AC" | head -1 | cut -d: -f1)"
	if [[ -n "$use" && ( -z "$asn" || "$asn" -gt "$use" ) ]]; then
		no "archive-ceremony.sh assigns \$STAGE before using it" \
			"assigned at line ${asn:-<never>}, first used at line $use"
	else
		ok "archive-ceremony.sh assigns \$STAGE before using it"
	fi
fi

HOOK=config/hooks/normal/0050-stage-env.hook.chroot
if [[ -f "$HOOK" && -f Makefile ]] && grep -q '/tmp/binaries.env' "$HOOK"; then
	if grep -qE 'install .*config/includes\.chroot/tmp/binaries\.env' Makefile; then
		ok "Makefile stages binaries.env into the chroot for 0050-stage-env to find"
	else
		no "Makefile stages binaries.env into the chroot for 0050-stage-env to find" \
			"the hook asserts /tmp/binaries.env but nothing in the Makefile installs it -- make build dies at the first hook"
	fi
fi

if [[ -f Makefile ]] && grep -q '\.build/build-start' Makefile; then
	if grep -qE '(:|touch|date|echo)[^|]*> *\.build/build-start' Makefile; then
		ok "Makefile writes .build/build-start before the stale-ISO check reads it"
	else
		no "Makefile writes .build/build-start before the stale-ISO check reads it" \
			"build-start is only ever read -- 'iso -nt .build/build-start' is vacuously true and a stale ISO passes"
	fi
fi

# --- ShellCheck SC2154 across all scripts --------------------------------
if ! have shellcheck; then
	skip "shellcheck SC2154 sweep" \
		"shellcheck not installed -- CI must provide it; the static half of the burn-path guard is not enforced on this host"
	return
fi

# Run from the repo root so the `# shellcheck source=config/.../ceremony-lib.sh`
# directive in the sourcing scripts resolves; then `-x` lets ShellCheck see the
# lib's own globals and stop reporting them. `--enable=check-unassigned-uppercase`
# is the whole point: default SC2154 skips UPPERCASE names as presumed
# environment, and every variable in these scripts -- $STAGE included -- is
# uppercase. With both flags, a real dangling reference is still caught while
# the lib's colour and PIV-default constants are not.
sc_hits=""
for f in "${BIN_SCRIPTS[@]}" "${SH_SCRIPTS[@]}"; do
	[[ -f "$f" ]] || continue
	h="$(shellcheck -x -f gcc --enable=check-unassigned-uppercase "$f" 2>/dev/null \
		| grep -E ': warning: .*\[SC2154\]' || true)"
	[[ -n "$h" ]] && sc_hits="${sc_hits}${h}"$'\n'
done
[[ -z "$(printf '%s' "$sc_hits" | tr -d '[:space:]')" ]] \
	&& ok "no ceremony script references an unassigned variable (SC2154)" \
	|| no "no ceremony script references an unassigned variable (SC2154)" \
	      "$(printf '%s' "$sc_hits" | sed 's/^/    /')"

# Syntax-level ShellCheck findings (error severity) are always a defect.
sc_err=""
for f in "${BIN_SCRIPTS[@]}" "${SH_SCRIPTS[@]}"; do
	[[ -f "$f" ]] || continue
	h="$(shellcheck -x -f gcc --severity=error "$f" 2>/dev/null || true)"
	[[ -n "$h" ]] && sc_err="${sc_err}${h}"$'\n'
done
[[ -z "$(printf '%s' "$sc_err" | tr -d '[:space:]')" ]] \
	&& ok "no ceremony script has an error-level ShellCheck finding" \
	|| no "no ceremony script has an error-level ShellCheck finding" \
	      "$(printf '%s' "$sc_err" | sed 's/^/    /')"
