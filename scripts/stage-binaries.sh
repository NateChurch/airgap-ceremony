#!/usr/bin/env bash
# stage-binaries.sh -- fetch non-Debian binaries on the BUILD HOST and stage
# them into the live filesystem tree.
#
# This deliberately does NOT run inside the chroot. Fetching there would mean
# shipping curl or wget on an image whose entire purpose is having no network,
# and would make the build depend on the chroot resolving DNS. The build host
# has network and tooling; the image should have neither.
#
# Every version and SHA-256 comes from config/binaries.env. If a variable is
# unset or a checksum does not match, this FAILS. There is deliberately no path
# that produces an unverified binary -- an image you cannot attest to is worse
# than no image.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/config/binaries.env"
BIN_DIR="${ROOT}/config/includes.chroot/usr/local/bin"
SHARE_DIR="${ROOT}/config/includes.chroot/usr/local/share/ceremony"
DEB_DIR="${ROOT}/config/packages.chroot"

if [[ ! -r "$ENV_FILE" ]]; then
	echo "FATAL: ${ENV_FILE} missing." >&2
	echo "       cp config/binaries.env.example config/binaries.env and fill it in." >&2
	exit 1
fi
# shellcheck disable=SC1090
. "$ENV_FILE"

command -v curl >/dev/null || { echo "FATAL: curl not found on build host" >&2; exit 1; }

mkdir -p "$BIN_DIR" "$SHARE_DIR" "$DEB_DIR"
PROV="${SHARE_DIR}/external-binaries.txt"
: > "$PROV"

fetch_verify_install() {
	local name="$1" url="$2" sha="$3" kind="$4" tmp actual

	if [[ -z "$url" || -z "$sha" ]]; then
		echo "FATAL: ${name}: url or sha256 unset in binaries.env." >&2
		echo "       Fill in the real values -- do not build without them." >&2
		exit 1
	fi

	tmp="$(mktemp -d)"
	echo "==> fetching ${name}"
	echo "    ${url}"
	curl -fsSL --proto '=https' --tlsv1.2 -o "${tmp}/dl" "$url"

	actual="$(sha256sum "${tmp}/dl" | cut -d' ' -f1)"
	if [[ "$actual" != "$sha" ]]; then
		echo "FATAL: ${name} checksum mismatch." >&2
		echo "       expected ${sha}" >&2
		echo "       actual   ${actual}" >&2
		rm -rf "$tmp"; exit 1
	fi
	echo "    checksum ok: ${actual}"

	case "$kind" in
		binary)
			install -m 0755 "${tmp}/dl" "${BIN_DIR}/${name}"
			echo "    staged -> config/includes.chroot/usr/local/bin/${name}" ;;
		targz)
			tar -xzf "${tmp}/dl" -C "$tmp"
			install -m 0755 "$(find "$tmp" -type f -name "$name" | head -1)" "${BIN_DIR}/${name}"
			echo "    staged -> config/includes.chroot/usr/local/bin/${name}" ;;
		deb)
			# live-build installs any .deb dropped in config/packages.chroot/
			install -m 0644 "${tmp}/dl" "${DEB_DIR}/${name}.deb"
			echo "    staged -> config/packages.chroot/${name}.deb" ;;
		*)
			echo "FATAL: unknown kind '${kind}' for ${name}" >&2
			rm -rf "$tmp"; exit 1 ;;
	esac

	# Provenance travels with the image so the running system can prove what it has.
	printf '%s %s %s %s\n' "$name" "$kind" "$sha" "$url" >> "$PROV"
	rm -rf "$tmp"
}

fetch_verify_install sops "${SOPS_URL:-}" "${SOPS_SHA256:-}" "${SOPS_KIND:-binary}"

# talosctl is optional. Leave TALOSCTL_URL empty to omit it.
if [[ -n "${TALOSCTL_URL:-}" ]]; then
	fetch_verify_install talosctl "${TALOSCTL_URL}" "${TALOSCTL_SHA256:-}" "${TALOSCTL_KIND:-binary}"
else
	echo "==> talosctl: TALOSCTL_URL empty, skipping"
fi

chmod 0444 "$PROV"
echo
echo "staged binaries:"
sed 's/^/  /' "$PROV"
