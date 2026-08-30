# The write-once guarantee is the reason optical media is used at all. A CD-RW
# in the tray passes every other check and silently voids it.
. "$REPO_ROOT/config/includes.chroot/usr/local/lib/ceremony-lib.sh"

assert_eq "$(classify_media 'Mounted Media:         09h, DVD-R Sequential')"  writeonce  "DVD-R -> write-once"
assert_eq "$(classify_media 'Mounted Media:         08h, CD-R')"              writeonce  "CD-R -> write-once"
assert_eq "$(classify_media 'Mounted Media:         41h, BD-R SRM')"          writeonce  "BD-R -> write-once"
assert_eq "$(classify_media 'Mounted Media:         0Ah, CD-RW')"             rewritable "CD-RW -> rewritable"
assert_eq "$(classify_media 'Mounted Media:         13h, DVD-RW Restricted')" rewritable "DVD-RW -> rewritable"
assert_eq "$(classify_media 'Mounted Media:         1Ah, DVD+RW')"            rewritable "DVD+RW -> rewritable"
assert_eq "$(classify_media 'Mounted Media:         12h, DVD-RAM')"           rewritable "DVD-RAM -> rewritable"
assert_eq "$(classify_media ':-( no media mounted')"                          blank      "no media -> blank"
assert_eq "$(classify_media 'something unexpected')"                          unknown    "unparseable -> unknown"

# The dangerous direction. A false "writeonce" is the only classification error
# that silently voids the design, so assert it separately and explicitly.
for m in CD-RW DVD-RW DVD+RW DVD-RAM BD-RE; do
	r="$(classify_media "Mounted Media: 00h, ${m}")"
	if [[ "$r" != "writeonce" ]]; then
		ok "${m} never passes as write-once"
	else
		no "${m} never passes as write-once" "classified as $r"
	fi
done
