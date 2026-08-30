[ -f ~/.bashrc ] && . ~/.bashrc
# Run the selftest once per login shell so it is never skipped by habit.
if [ -z "${CEREMONY_SELFTEST_DONE:-}" ] && [ -t 0 ]; then
	export CEREMONY_SELFTEST_DONE=1
	/usr/local/bin/ceremony-selftest || true
fi
