#!/bin/bash
# Independent verification of a built ISO, runnable on any machine.
#
# Confirms: checksum matches the recorded SHA256SUMS, the ISO is bootable
# (has an El Torito record), and prints the package manifest embedded in the
# squashfs so you can diff two builds without booting either.
set -euo pipefail

ISO="${1:?usage: verify-iso.sh <path-to-iso> [SHA256SUMS]}"
SUMS="${2:-$(dirname "$ISO")/SHA256SUMS}"

fail=0
say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=1; }

echo "Verifying: $ISO"

if [[ -r "$SUMS" ]]; then
	if (cd "$(dirname "$ISO")" && sha256sum -c --ignore-missing "$(basename "$SUMS")" >/dev/null 2>&1); then
		ok "checksum matches $SUMS"
	else
		bad "checksum MISMATCH against $SUMS"
	fi
else
	bad "no SHA256SUMS found at $SUMS -- provenance unverifiable"
fi

say "sha256: $(sha256sum "$ISO" | cut -d' ' -f1)"
say "size:   $(du -h "$ISO" | cut -f1)"

if command -v xorriso >/dev/null 2>&1; then
	if xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null | grep -q 'El Torito'; then
		ok "El Torito boot record present"
	else
		bad "no El Torito boot record -- ISO will not boot"
	fi
else
	say "xorriso absent; skipped boot record check"
fi

# Extract the manifest without mounting, if 7z or bsdtar is available.
if command -v bsdtar >/dev/null 2>&1; then
	tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
	if bsdtar -xOf "$ISO" live/filesystem.squashfs > "$tmp/fs.squashfs" 2>/dev/null \
		&& command -v unsquashfs >/dev/null 2>&1; then
		if unsquashfs -q -d "$tmp/sq" -e usr/local/share/ceremony/manifest.txt "$tmp/fs.squashfs" >/dev/null 2>&1; then
			m="$tmp/sq/usr/local/share/ceremony/manifest.txt"
			ok "embedded manifest extracted ($(grep -c '^ii ' "$m") packages)"
			head -4 "$m" | sed 's/^/          /'
			cp "$m" "$(dirname "$ISO")/manifest.txt"
			say "manifest written next to ISO for diffing"
		fi
	fi
fi

echo
[[ $fail -eq 0 ]] && { echo "  All checks passed."; exit 0; } || { echo "  Verification FAILED."; exit 1; }
