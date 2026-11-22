# SPDX-License-Identifier: GPL-2.0-only
KDIR ?= /lib/modules/$(shell uname -r)/build

.PHONY: all clean check check-deps check-package check-pkg check-all-kernels module-info package static vbios-re vbios-trace crc-check console-check tools install-tools

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	$(RM) tests/check-vblank tests/test-bbdither-rgb565 \
		tests/test-scale-optimizations tools/sm750-smi

# Prerequisite target, not a recipe line, so the documented command count of
# the check target is unchanged. Fail here with an actionable message instead
# of a raw xf86drm.h compile error (defect A03).
check-deps:
	@pkg-config --exists libdrm || { \
		echo "libdrm development files are required by tests/check-vblank." >&2; \
		echo "  Debian/Ubuntu: sudo apt install libdrm-dev" >&2; \
		echo "  Fedora:        sudo dnf install libdrm-devel" >&2; \
		echo "  Rootless alternative: see docs/ENVIRONMENT.md" >&2; \
		exit 1; }
	@command -v rg >/dev/null 2>&1 || { \
		echo "ripgrep (rg) is required by the release checks." >&2; \
		echo "  Debian/Ubuntu: sudo apt install ripgrep" >&2; \
		echo "  Fedora:        sudo dnf install ripgrep" >&2; \
		exit 1; }

check: check-deps all tests/check-vblank tests/test-bbdither-rgb565 \
		tests/test-scale-optimizations tools/sm750-smi
	./tests/check-drm-module.sh src/sm750hdmidrm.ko
	./tests/check-drm-policy.sh
	./tests/check-drm-xorg-config.sh
	./tests/check-drm-packaging.sh
	./tests/check-release-version.sh
	./tests/check-softscale-map.sh
	./tests/check-softscale-sharpen.sh
	./tests/check-softscale-codegen.sh src/sm750_dither.o
	./tests/check-hardware-cursor.sh
	./tests/check-shadow-dma.sh
	./tests/check-backbuffer-staging.sh
	./tests/check-shadow-async.sh
	./tests/check-shadow-source-damage.sh
	python3 tests/test-vblank-timer.py
	./tests/test-bbdither-rgb565
	./tests/test-scale-optimizations
	python3 tests/test-staging-results.py
	./tests/check-sm750-smi.sh

check-all-kernels:
	./tests/build-all-kernels.sh

# Opt-in static analysis (sparse, smatch, cppcheck, coccinelle, pahole). Kept
# out of `check` on purpose: the recipe command count of `check` is asserted by
# tests/check-drm-module.sh and documented in docs/AUDIT.md, and the analysers
# are not a build requirement. Baseline: tests/static/baseline/, triage:
# docs/STATIC-ANALYSIS.md.
static:
	./tests/check-static.sh

module-info: all
	/sbin/modinfo src/sm750hdmidrm.ko

# Opt-in rebuild of the board option ROM from the 16-bit reconstruction. The
# captured image is vendor material and is never committed, so this SKIPS when
# it is absent (the harness exits 77, the recipe turns that into a skip); it is
# not a `check` dependency for the same reason `static` is not (see
# docs/VBIOS-REVERSE-ENGINEERING.md).
vbios-re:
	@./tools/vbios-re/check.sh; rc=$$?; \
	if [ $$rc -eq 77 ]; then exit 0; fi; \
	exit $$rc

# Opt-in execution trace of the captured ROM and of the reconstruction this
# tree generates, compared step by step (docs/VBIOS-REVERSE-ENGINEERING.md
# section 10.2). Same SKIP rule as vbios-re: the captured image is vendor
# material and is not in the tree, so an absent image is a successful skip.
vbios-trace:
	@./tools/vbios-re/trace.sh; rc=$$?; \
	if [ $$rc -eq 77 ]; then exit 0; fi; \
	exit $$rc

# Opt-in scanout readback check: needs the SM750 card, root and a mounted
# debugfs, so it is not part of `check` (the harness exits 77 when it cannot
# run and the recipe turns that into a skip), same rule as vbios-trace.
crc-check:
	@./tests/check-scanout-crc.sh; rc=$$?; \
	if [ $$rc -eq 77 ]; then exit 0; fi; \
	exit $$rc

# Opt-in console scanout check: proves the console reaches the panel when the
# foreground VT is in KD_TEXT, and exits 77 (a skip) when it is in KD_GRAPHICS
# or when root, debugfs or the card are missing. Root-only, so not in `check`.
console-check:
	@./tests/check-console-scanout.sh; rc=$$?; \
	if [ $$rc -eq 77 ]; then exit 0; fi; \
	exit $$rc

# Self-test gate for the sudo package helper (tools/sm750-pkg.sh, installed as
# /usr/local/sbin/sm750-pkg): stubs dnf/dkms/rpm/modprobe through a temporary
# PATH, so no package is touched and no root is needed. Not part of `check`
# for the same reason `static` is not - the recipe command count is asserted.
check-pkg:
	./tests/check-sm750-pkg.sh

tests/check-vblank: tests/check-vblank.c
	$(CC) -O2 -Wall -Wextra -Werror $$(pkg-config --cflags libdrm) \
		-o $@ $< $$(pkg-config --libs libdrm) -lm

tests/test-bbdither-rgb565: tests/test-bbdither-rgb565.c tools/bbdither-rgb565.c tools/bbdither-rgb565.h
	$(CC) -O3 -Wall -Wextra -Werror -Itools -o $@ tests/test-bbdither-rgb565.c tools/bbdither-rgb565.c

tests/test-scale-optimizations: tests/test-scale-optimizations.c
	$(CC) -O3 -Wall -Wextra -Werror -o $@ $<

package:
	./build-package.sh

# The package path was never exercised by a target (defect A19). This builds
# the .deb and source tarball and audits the produced artifacts.
check-package: check-deps all
	./build-package.sh
	./tests/audit-release.sh

staging-benchmark: tools/staging-pattern

tools/staging-pattern: tools/staging-pattern.c
	$(CC) -O2 -Wall -Wextra -Werror -o $@ $< -lX11

# Monitoring and control utility (tools/sm750-smi.c).  It reads sysfs, the
# DRM card node through libdrm and optional debugfs; the gate builds it from
# synthetic trees, so no GPU and no root are needed by `make check`.
tools: tools/sm750-smi

tools/sm750-smi: tools/sm750-smi.c
	$(CC) -O2 -Wall -Wextra -Werror $$(pkg-config --cflags libdrm) \
		-o $@ $< $$(pkg-config --libs libdrm)

install-tools: tools/sm750-smi
	install -D -m 0755 tools/sm750-smi $(DESTDIR)/usr/local/sbin/sm750-smi
