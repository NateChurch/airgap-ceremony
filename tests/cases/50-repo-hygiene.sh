# Executable bits are the single most frequent failure in this repo. Git tracks
# them; a clone that loses them fails in confusing ways.
cd "$REPO_ROOT" || return

# ceremony-lib.sh is sourced, never executed; 0644 is correct for it. Everything
# else in these paths must be runnable.
if [[ -f config/includes.chroot/usr/local/lib/ceremony-lib.sh ]]; then
	if [[ -x config/includes.chroot/usr/local/lib/ceremony-lib.sh ]]; then
		no "ceremony-lib.sh is not executable (it is sourced)" "found mode +x"
	else
		ok "ceremony-lib.sh is not executable (it is sourced)"
	fi
fi

missing=""
for f in scripts/*.sh auto/config auto/build auto/clean \
         config/hooks/normal/*.hook.chroot \
         config/includes.chroot/usr/local/bin/* tests/run-tests.sh; do
	[[ -f "$f" ]] || continue
	[[ -x "$f" ]] || missing="$missing $f"
done
[[ -z "$missing" ]] && ok "all scripts are executable" \
	|| no "all scripts are executable" "not executable:$missing"

# Shell syntax across everything.
bad=""
for f in scripts/*.sh config/includes.chroot/usr/local/bin/* \
         config/includes.chroot/usr/local/lib/*.sh tests/*.sh tests/cases/*.sh; do
	[[ -f "$f" ]] || continue
	head -1 "$f" | grep -q 'bin/sh' && { sh -n "$f" 2>/dev/null || bad="$bad $f"; continue; }
	bash -n "$f" 2>/dev/null || bad="$bad $f"
done
for f in auto/config auto/build auto/clean config/hooks/normal/*.hook.chroot; do
	[[ -f "$f" ]] || continue
	sh -n "$f" 2>/dev/null || bad="$bad $f"
done
[[ -z "$bad" ]] && ok "all shell scripts parse" || no "all shell scripts parse" "failed:$bad"

# Secrets and build products must never be committed. Ask git rather than
# pattern-matching .gitignore -- '*.log' covers 'build.log' and a literal
# grep would report a false failure.
for p in config/binaries.env config/includes.chroot/tmp/binaries.env \
         build.log airgap-ceremony-amd64.hybrid.iso chroot/x cache/x; do
	if git -C . rev-parse --git-dir >/dev/null 2>&1; then
		git check-ignore -q "$p" && ok "git ignores $p" || no "git ignores $p"
	else
		skip "git ignores $p" "not a git repository"
	fi
done

# Every runtime script must be either tracked by git OR deliberately gitignored
# (sops/talosctl are staged at build time). A file that is NEITHER is invisible
# to a clean checkout: the ISO builds correctly on the machine that has the
# file and ships without it from a fresh clone. Same silent class as a lost
# executable bit. This is why `.gitignore` line 6 is `/local/`, anchored --
# a bare `local/` also matched `config/includes.chroot/usr/local/` and hid new
# scripts there.
if git -C . rev-parse --git-dir >/dev/null 2>&1; then
	orphan=""
	while IFS= read -r f; do
		[[ -f "$f" ]] || continue
		git ls-files --error-unmatch "$f" >/dev/null 2>&1 && continue   # tracked
		git check-ignore -q "$f" && continue                            # deliberately ignored
		orphan="$orphan $f"
	done < <(find config/includes.chroot/usr/local/bin \
	              config/includes.chroot/usr/local/lib -type f 2>/dev/null)
	[[ -z "$orphan" ]] \
		&& ok "every file under usr/local/{bin,lib} is tracked or gitignored" \
		|| no "every file under usr/local/{bin,lib} is tracked or gitignored" \
		      "neither (needs 'git add' or an ignore rule):$orphan"
else
	skip "usr/local scripts are tracked or gitignored" "not a git repository"
fi

# The two AGENTS.md files serve different audiences and must not be merged.
if [[ -r AGENTS.md && -r config/includes.binary/AGENTS.md ]]; then
	if cmp -s AGENTS.md config/includes.binary/AGENTS.md; then
		no "repo and ISO AGENTS.md are distinct" "they are identical"
	else
		ok "repo and ISO AGENTS.md are distinct"
	fi
fi
