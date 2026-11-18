# SPDX-License-Identifier: GPL-2.0-only
KDIR ?= /lib/modules/$(shell uname -r)/build

.PHONY: all clean check check-deps check-package check-all-kernels module-info package

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/src clean
	$(RM) tests/check-vblank tests/test-bbdither-rgb565 \
		tests/test-scale-optimizations

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
		tests/test-scale-optimizations
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

check-all-kernels:
	./tests/build-all-kernels.sh

module-info: all
	/sbin/modinfo src/sm750hdmidrm.ko

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
