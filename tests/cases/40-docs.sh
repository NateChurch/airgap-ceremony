# Documentation has ONE tracked source (docs-src/). Everything else is a build
# product. These tests assert the generated copies match, that nothing was
# edited in the wrong place, and that no document references a missing one.
SRC="$REPO_ROOT/docs-src"

if [[ ! -d "$SRC/docs" ]]; then no "docs-src exists"; return; fi
ok "docs-src is the single tracked source"

# Expectations are derived, never hardcoded -- adding a document should not
# require editing this file.
EXPECT="$(cd "$SRC" && find . -name '*.md' | sed 's|^\./||' | sort)"
n="$(wc -l <<<"$EXPECT")"
[[ "$n" -ge 8 ]] && ok "docs-src holds $n documents" \
	|| no "docs-src holds a plausible number of documents" "found $n"

if "$REPO_ROOT/scripts/sync-docs.sh" --check >/dev/null 2>&1; then
	ok "generated copies are in sync with docs-src"
else
	out="$("$REPO_ROOT/scripts/sync-docs.sh" --check 2>&1 | head -6)"
	no "generated copies are in sync with docs-src" "$out"
fi

# The manifest the build hook checks against must exist and match.
MAN="$REPO_ROOT/config/includes.chroot/usr/local/share/ceremony/docs.manifest"
if [[ -r "$MAN" ]]; then
	ok "docs.manifest present"
	got="$(cut -d' ' -f3- "$MAN" | sort)"
	assert_eq "$got" "$EXPECT" "manifest lists exactly the docs-src contents"
else
	no "docs.manifest present" "run scripts/sync-docs.sh"
fi

# Every doc referenced from another doc must exist.
dangling=""
for src in "$SRC"/*.md "$SRC"/docs/*.md; do
	[[ -r "$src" ]] || continue
	while read -r ref; do
		[[ -n "$ref" ]] || continue
		[[ -r "$SRC/docs/$ref" ]] || dangling="$dangling $(basename "$src")->$ref"
	done < <(grep -oE 'docs/[0-9]{2}-[a-z-]+\.md' "$src" | sed 's|docs/||' | sort -u)
done
[[ -z "$dangling" ]] && ok "all inter-document references resolve" \
	|| no "all inter-document references resolve" "dangling:$dangling"

# Generated copies must not be tracked -- that is how they drift.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	for d in config/includes.binary/docs config/includes.chroot/etc/skel/docs; do
		if git -C "$REPO_ROOT" check-ignore -q "$d" 2>/dev/null; then
			ok "git ignores generated $d"
		else
			no "git ignores generated $d" "generated docs must not be tracked"
		fi
	done
else
	skip "generated docs are gitignored" "not a git repository"
fi
