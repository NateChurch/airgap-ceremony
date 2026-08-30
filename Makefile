# Air-gapped key ceremony image.
#
# Build host requirements: Debian trixie (or bookworm) with live-build, run as
# root. See README.md -- do not build this in WSL.

SHELL := /bin/bash
IMAGE_NAME ?= airgap-ceremony
DEBIAN_SUITE ?= trixie
INCLUDE_FIRMWARE ?= false
# live-build's output filename has changed across versions (live-image-amd64.iso,
# <name>-amd64.hybrid.iso, ...). Discover it instead of asserting it -- the check
# that matters is "an ISO exists", not "an ISO with the name I guessed exists".
FIND_ISO = ls -1t *.iso 2>/dev/null | head -1
STAMP := $(shell date -u +%Y%m%dT%H%M%SZ)
SUITE_STAMP := .build/suite-stamp
ARTIFACTS := artifacts/$(STAMP)

export DEBIAN_SUITE
export INCLUDE_FIRMWARE
export IMAGE_NAME

.PHONY: help preflight fix-modes docs test test-all dry-run binaries build verify artifacts clean distclean write

help:
	@echo "Targets:"
	@echo "  preflight  Check build host has what it needs and binaries.env is filled in"
	@echo "  binaries   Fetch+verify non-Debian binaries and stage them into the image"
	@echo "  build      Build the ISO (requires root)"
	@echo "  artifacts  Copy ISO + manifest + checksums to artifacts/<timestamp>/"
	@echo "  verify     Re-verify checksums of the most recent artifact set"
	@echo "  write      Write ISO to a USB device: make write DEV=/dev/sdX"
	@echo "  clean      lb clean, keep the config"
	@echo "  distclean  clean + remove artifacts and caches"
	@echo "  purge      FULL reset: drop chroot+cache so the next build re-bootstraps"
	@echo "  fix-modes  Restore executable bits lost copying between machines"
	@echo "  docs       Regenerate shipped docs from docs-src/ (single source)"
	@echo "  test       Tier 1: unit tests, no crypto tools needed, runs anywhere"
	@echo "  test-all   Tier 2: adds a real encrypt/split/recover round trip"
	@echo "  dry-run    Tier 3: guided sacrificial ceremony on real hardware"
	@echo ""
	@echo "Variables: DEBIAN_SUITE=$(DEBIAN_SUITE) INCLUDE_FIRMWARE=$(INCLUDE_FIRMWARE)"

preflight:
	@fail=0; \
	if [ "$$(id -u)" -ne 0 ]; then echo "FAIL: must run as root"; fail=1; fi; \
	for b in lb debootstrap xorriso mksquashfs curl; do \
		command -v $$b >/dev/null || { echo "FAIL: missing $$b"; fail=1; }; \
	done; \
	if grep -qi microsoft /proc/version 2>/dev/null; then \
		echo "FAIL: this looks like WSL. Build on a real Debian VM -- see README."; fail=1; \
	fi; \
	if [ ! -r config/binaries.env ]; then \
		echo "FAIL: config/binaries.env missing. cp config/binaries.env.example config/binaries.env and fill it in."; fail=1; \
	else \
		. ./config/binaries.env; \
		[ -n "$$SOPS_URL" ]    || { echo "FAIL: SOPS_URL empty in config/binaries.env"; fail=1; }; \
		[ -n "$$SOPS_SHA256" ] || { echo "FAIL: SOPS_SHA256 empty in config/binaries.env"; fail=1; }; \
	fi; \
	for f in scripts/*.sh auto/config auto/build auto/clean \
	         config/hooks/normal/*.hook.chroot \
	         config/includes.chroot/usr/local/bin/*; do \
		[ -f "$$f" ] || continue; \
		if [ ! -x "$$f" ]; then echo "FAIL: not executable: $$f"; fail=1; fi; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo; echo "preflight failed"; \
		echo "if only modes failed:  make fix-modes"; \
		exit 1; \
	fi; \
	echo "preflight ok"

binaries:
	@# Fetch on the host, not in the chroot: the image must not ship curl, and
	@# the build must not depend on the chroot resolving DNS.
	./scripts/stage-binaries.sh

build: preflight check-suite docs binaries
	@# Start stamp for the "did this build make its own ISO" check below. Must
	@# exist BEFORE lb build, or `iso -nt .build/build-start` is vacuously true
	@# (test treats a missing second operand as "older") and a stale ISO passes.
	@mkdir -p .build && : > .build/build-start
	@# 0050-stage-env.hook.chroot asserts /tmp/binaries.env arrived. Stage it
	@# here, before lb runs, so a missing binaries.env fails at the top of the
	@# hook chain rather than deep inside it. Both this line and the matching
	@# cleanup were dropped in e9cf4e9, which left the asserting hook in place --
	@# make build has been unable to finish since.
	install -D -m 0444 config/binaries.env config/includes.chroot/tmp/binaries.env
	lb config
	lb build 2>&1 | tee build.log
	@iso=$$($(FIND_ISO)); \
	 if [ -n "$$iso" ] && [ ! "$$iso" -nt .build/build-start ]; then \
		echo "FAIL: $$iso predates this build -- it is stale output, not a new ISO"; \
		echo "      run 'make clean' (or 'make purge') and build again"; \
		exit 1; \
	 fi; \
	 if [ -z "$$iso" ]; then \
		echo "FAIL: no .iso produced"; \
		echo "      contents of $$(pwd):"; ls -la | sed 's/^/      /'; \
		exit 1; \
	 fi; \
	 echo "built $$iso ($$(du -h $$iso | cut -f1))"
	@$(MAKE) --no-print-directory artifacts

artifacts:
	@iso=$$($(FIND_ISO)); \
	 test -n "$$iso" || { echo "no ISO to collect"; exit 1; }; \
	 mkdir -p $(ARTIFACTS); \
	 cp "$$iso" $(ARTIFACTS)/
	@cp -f build.log $(ARTIFACTS)/ 2>/dev/null || true
	@cp -f binary.packages $(ARTIFACTS)/packages.txt 2>/dev/null || true
	@cp -f *.packages $(ARTIFACTS)/ 2>/dev/null || true
	@cd $(ARTIFACTS) && sha256sum * > SHA256SUMS && chmod 0444 SHA256SUMS
	@echo "artifacts in $(ARTIFACTS)"
	@cat $(ARTIFACTS)/SHA256SUMS

verify:
	@latest=$$(ls -1d artifacts/*/ 2>/dev/null | sort | tail -1); \
	if [ -z "$$latest" ]; then echo "no artifacts to verify"; exit 1; fi; \
	echo "verifying $$latest"; \
	cd "$$latest" && sha256sum -c SHA256SUMS

write:
	@test -n "$(DEV)" || { echo "usage: make write DEV=/dev/sdX"; exit 1; }
	@test -b "$(DEV)" || { echo "$(DEV) is not a block device"; exit 1; }
	@iso=$$($(FIND_ISO)); test -n "$$iso" || { echo "no ISO built"; exit 1; }; \
	 echo "Source: $$iso"; \
	 echo "About to OVERWRITE $(DEV):"; lsblk -o NAME,SIZE,MODEL,TRAN "$(DEV)"; \
	 read -p "Type the device name again to confirm: " c; \
	 [ "$$c" = "$(DEV)" ] || { echo "mismatch, aborting"; exit 1; }; \
	 dd if="$$iso" of=$(DEV) bs=4M status=progress oflag=direct conv=fsync; \
	 sync; \
	 echo "Verifying written bytes against source ISO..."; \
	 sz=$$(stat -c %s "$$iso"); \
	 a=$$(sha256sum "$$iso" | cut -d' ' -f1); \
	 b=$$(head -c $$sz $(DEV) | sha256sum | cut -d' ' -f1); \
	 if [ "$$a" = "$$b" ]; then echo "PASS: device matches ISO ($$a)"; \
	 else echo "FAIL: device does not match ISO"; echo "  iso $$a"; echo "  dev $$b"; exit 1; fi

fix-modes:
	@chmod +x scripts/*.sh auto/config auto/build auto/clean \
	          config/hooks/normal/*.hook.chroot \
	          config/includes.chroot/usr/local/bin/* 2>/dev/null || true
	@echo "modes fixed; re-run make preflight"

docs:
	@./scripts/sync-docs.sh

test: docs
	@./tests/run-tests.sh

test-all:
	@./tests/run-tests.sh -t 2

dry-run:
	@./tests/dry-run.sh

check-suite:
	@mkdir -p .build
	@if [ -f $(SUITE_STAMP) ] && [ "$$(cat $(SUITE_STAMP))" != "$(DEBIAN_SUITE)" ]; then \
		echo "FAIL: chroot/cache was bootstrapped for '$$(cat $(SUITE_STAMP))',"; \
		echo "      but this build targets '$(DEBIAN_SUITE)'."; \
		echo "      Mixing suites yields dozens of misleading 'unmet dependencies'"; \
		echo "      errors naming real packages. Run: make purge"; \
		exit 1; \
	fi
	@echo "$(DEBIAN_SUITE)" > $(SUITE_STAMP)

purge:
	-lb clean --purge
	rm -rf cache chroot binary local .build
	rm -rf config/includes.chroot/tmp
	rm -f  *.contents *.files *.packages binary.modified_timestamps build.log
	@echo "purged -- next build re-runs debootstrap from scratch"

clean:
	lb clean

distclean:
	lb clean --purge
	rm -rf artifacts cache .build build.log
	rm -f  config/includes.chroot/usr/local/bin/sops
	rm -f  config/includes.chroot/usr/local/bin/talosctl
	rm -f  config/includes.chroot/usr/local/share/ceremony/external-binaries.txt
	rm -rf config/includes.chroot/tmp
	rm -rf config/packages.chroot
