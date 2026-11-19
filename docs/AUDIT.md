<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Repository audit - sm750hdmifb 0.5.9

Audit date: 2026-11-17. Read-only audit of the source tree; the only tracked
file added by this audit is this document plus text captures under
`docs/evidence/audit/`. No source, test, packaging, Makefile or dkms.conf file
was modified.

This document records what was observed on the audit date and is not updated
when a defect is fixed. The disposition of each of the 24 rows - `fixed`,
`accepted` or `deferred`, with the change reference - is in
[DEFECTS.md](DEFECTS.md), which is the current state; `A01` and `A02` are fixed
there. Rows that name a header-tree set (for example A06, which lists 7.2.13,
7.2.15 and 7.3.3) describe the host as it was on 2026-11-17; the current matrix
is in [ENVIRONMENT.md](ENVIRONMENT.md) section 2.

Path note (2026-11-18, after the audit date): every reference below to
`.github/workflows/build.yml` describes where the CI recipe was on the audit
date. GitHub Actions is now disabled and the recipe moved to
[docs/ci/build.yml](ci/build.yml); see
[ENVIRONMENT.md](ENVIRONMENT.md) section 1.3. The rows are left as observed.

Severity rubric used below:

| Severity | Meaning |
| --- | --- |
| S1 | Release or installation is blocked, or untrusted content/data can escape the project. |
| S2 | A documented workflow or a required capability is broken or absent; a workaround exists. |
| S3 | Portability, observability or maintainability defect; normal operation continues. |
| S4 | Documentation or cosmetic defect. |

## 1. Repository identity and state

| Item | Value |
| --- | --- |
| HEAD commit | `27db03b2e9e7e0b0afef0a52ff4b2e8cd175fb1b` |
| Subject | `Release 0.5.9 with newer kernel support` |
| Branch | `main` |
| Remote `origin` | `https://polaris.root.sx/code/duka/sm750hdmifb.git` |
| Remote `upstream` | `https://github.com/KodeMunkie/sm750hdmifb.git` |
| Tags | `v0.5.5`, `v0.5.6`, `v0.5.7`, `v0.5.9` (no `v0.5.8` tag, though commit `60903c5` is titled `Bump version to 0.5.8`) |
| Tracked files | 76 |
| Worktree at audit start | clean except one untracked directory `docs/plan/` |
| Worktree at audit end | clean except untracked `docs/plan/` (pre-existing), `docs/specs/` (added by a parallel task), and `docs/evidence/` (this audit). No tracked file changed. |

Source size:

| Area | Files | Lines |
| --- | --- | --- |
| `src/*.c` | 15 | 7427 |
| `src/*.h` | 8 | 2006 |
| `src/` total (incl. `Makefile`, `Kconfig`) | 23 | 9433 |
| `tests/*.sh` | 12 | 1217 |
| `tests/*.c` | 2 | 545 |
| `tests/*.py` | 2 | 370 |
| `tests/` total | 20 | - |
| `packaging/` | 8 | - |
| `tools/` | 7 | 539 |
| `docs/` (tracked) | 11 (8 `.md`) | 815 |

Largest sources: `src/sm750_drm.c` (121488 B), `src/ddk750_reg.h` (80145 B),
`src/sii902x.c` (35812 B), `src/sm750_dither.c` (17855 B). Three tracked
screenshots under `docs/images/` are 2.9-3.3 MB each.

Identity is split between two names:

| Name | Kind | Evidence |
| --- | --- | --- |
| `sm750hdmidrm` | kernel module | `src/Makefile:2` `obj-m += sm750hdmidrm.o`; `src/Makefile:3-5` object list; `modinfo src/sm750hdmidrm.ko` reports `name: sm750hdmidrm`, `license: GPL v2`, `description: Atomic DRM/KMS driver for SM750G10 SiI9024A HDMI boards`, `alias: pci:v0000126Fd00000750sv*sd*bc*sc*i*`, `depends: drm_vram_helper,drm_ttm_helper` |
| `sm750hdmifb` 0.5.9 | source package | `dkms.conf:2-3`, `build-package.sh:6-8`, `.deb` control field `Package: sm750hdmifb`, `Version: 0.5.9` |

The module carries no `MODULE_VERSION()` anywhere in `src/`, so `modinfo`
cannot report the package version (defect A15).

## 2. Build and package entry points

| Entry point | Location | What it does |
| --- | --- | --- |
| Kernel module build | `Makefile:2` (`KDIR ?= /lib/modules/$(shell uname -r)/build`), `Makefile:6-7` (`all`), `src/Makefile:1-18` | kbuild of `src/sm750hdmidrm.ko` |
| Clean | `Makefile:9-12` | `make -C $(KDIR) M=$(src)` clean plus local outputs |
| `check` | `Makefile:14-32` | builds `all`, `tests/check-vblank`, `tests/test-bbdither-rgb565`, `tests/test-scale-optimizations`, then runs 17 commands (see below) |
| `check-all-kernels` | `Makefile:34-35` | runs `tests/build-all-kernels.sh` |
| `module-info` | `Makefile:37-38` | `modinfo src/sm750hdmidrm.ko` |
| `tests/check-vblank` rule | `Makefile:40-42` | compiles the libdrm vblank tool; uses `pkg-config --cflags libdrm` and `--libs libdrm` |
| `test-bbdither-rgb565`, `test-scale-optimizations` | `Makefile:44-48` | compile and run the two C regression binaries |
| `package` | `Makefile:50-51` | invokes `./build-package.sh` |
| `staging-benchmark`, `tools/staging-pattern` | `Makefile:53-56` | benchmark helper, links X11 |
| Debian package builder | `build-package.sh` | builds `dist/sm750hdmifb_0.5.9_all.deb` (`:77`) and `dist/sm750hdmifb-0.5.9-source.tar.gz` (`:79-90`), then `dist/SHA256SUMS` (`:92-95`) |
| DKMS registration | `dkms.conf:2-10` | package/version/module names, `BUILD_EXCLUSIVE_KERNEL`, `MAKE[0]`, `CLEAN` |
| Release audit | `tests/audit-release.sh` | checks the built module, deb and source tarball, forbidden content, private paths and licence markers; writes `dist/RELEASE-AUDIT.txt` |
| CI | `.github/workflows/build.yml` | Ubuntu 24.04 only, `workflow_dispatch` only, 6.17 headers, `make check`, `build-package.sh`, `audit-release.sh`, artifact upload |

The `check` recipe contains exactly 17 commands at `Makefile:16-32`:
`check-drm-module.sh`, `check-drm-policy.sh`, `check-drm-xorg-config.sh`,
`check-drm-packaging.sh`, `check-release-version.sh`, `check-softscale-map.sh`,
`check-softscale-sharpen.sh`, `check-softscale-codegen.sh`,
`check-hardware-cursor.sh`, `check-shadow-dma.sh`, `check-backbuffer-staging.sh`,
`check-shadow-async.sh`, `check-shadow-source-damage.sh`,
`python3 tests/test-vblank-timer.py`, `./tests/test-bbdither-rgb565`,
`./tests/test-scale-optimizations`, `python3 tests/test-staging-results.py`.
The planning note that described this target as 18 commands is wrong (A23).
`check-drm-policy.sh` in turn runs `tests/check-crc-uapi.sh`, so the CRC uapi
gate and its negative controls add no recipe command and the count stays 17.

## 3. Declared kernel support range

Every in-tree statement of the floor says 6.17:

| Source | Text |
| --- | --- |
| `dkms.conf:8` | `BUILD_EXCLUSIVE_KERNEL="^(6\.(1[7-9]|[2-9][0-9])\.|[7-9]\.|[1-9][0-9]\.)"` - 6.17.0 through 6.99.x, 7.x-9.x, 10.x and above |
| `README.md:53` | "intended for **Linux 6.17 and newer**" |
| `README.md:55-58` | compatibility work listed for 6.17, 7.0, 7.2 (atomic transaction rename) and 7.3/7.4 (state-creation callbacks, CRTC reset removal) |
| `docs/TESTING.md:44` | `| Ubuntu 6.17.0-42 | Minimum supported series |` |
| `docs/TESTING.md:45-50` | tested matrix: 6.18.0-061800, 7.0.0-38/42, 7.1.0-070100, 7.2.0-070200, 7.3.0-070300rc3, 7.3.0-070300daily20261028 |
| `tests/build-all-kernels.sh:22-25` | `case` accepts `6.1[7-9].*`, `6.[2-9][0-9].*`, `[7-9].*`, `[1-9][0-9].*`; otherwise exits 1 with `No supported header-backed kernels were found.` (`:59-62`) |
| `packaging/drm-postinst:59` | same 6.17+ `case` filter for post-install kernel selection |

Contrast with the planning handoff: there is **no 5.14 baseline anywhere in the
tree**. `git grep -n '5\.14'` returns zero hits; the only 5.14 mention in the
working directory is in the untracked planning file. The 5.14 premise is
therefore unsupported: the floor is 6.17.

`docs/RELEASE-NOTES.md:10-13` also states "**Kernels >= 7.1 are untested.**",
which conflicts with `dkms.conf:7` `AUTOINSTALL="yes"` (A20) and with the fact
that the audit host runs 7.3.3 with the module loaded.

## 4. Executed verification (rootless)

Environment: Fedora 43, kernel `7.3.3-100.fc43.x86_64`, gcc 14.4.1, kernel
built with gcc 15.3.1, no root. Full command log in
`docs/evidence/audit/release-gate-and-environment.txt`.

| Command | Exit | Result |
| --- | --- | --- |
| `make check` (no libdrm available) | 2 | `tests/check-vblank.c:11:10: fatal error: xf86drm.h: No such file or directory`, then `make[1]: *** [Makefile:41: tests/check-vblank] Error 1` |
| `make check-all-kernels` (no libdrm) | 2 | same failure through `Makefile:35` |
| `pkg-config --modversion libdrm` | 1 | `Package 'libdrm' not found` |
| `make check` with the rootless libdrm chain (see below) | 0 | all 17 commands pass; `Ran 4 tests ... OK` |
| `make check-all-kernels` with the same chain | 0 | `Built 9 sm750hdmidrm kernel/format combinations` |
| `make check` in a pristine `git archive HEAD` copy with the chain | 0 | `Ran 4 tests in 0.218s ... OK` |
| `./tests/check-vblank /dev/dri/card0 60` | 1 | `open /dev/dri/card0: Permission denied` |
| `./tests/audit-release.sh` on a working-tree copy | 1 | `Restrictive licence marker found in releasable code.` |
| `tests/check-release-version.sh` with `rg` removed from `PATH` | 1 | `rg: command not found` (line 24) |
| `dkms install -m sm750hdmifb -v 0.5.9` | 1 | `Error! You must be root to use this command.` |
| `rpm -i --root=<tmpdir> <pkg>` | 1 | `Unable to change root directory: Operation not permitted` |
| `ls -d /lib/modules/6.17*/build` | 2 | no such directory |
| `./tests/audit-release.sh` on a `git archive HEAD` copy plus this document and `docs/evidence/audit/` | 0 | `Release audit passed` - confirms the audit artifacts themselves contain no private path or restrictive licence marker |

Rootless libdrm chain that makes `make check` pass (no root, no install):

```
mkdir -p /tmp/opencode/libdrm && cd /tmp/opencode/libdrm
dnf download libdrm libdrm-devel
for r in *.rpm; do rpm2cpio "$r" | cpio -idmv; done
cd <repo copy>
PKG_CONFIG_PATH=/tmp/opencode/libdrm/usr/lib64/pkgconfig \
PKG_CONFIG_SYSROOT_DIR=/tmp/opencode/libdrm \
LD_LIBRARY_PATH=/tmp/opencode/libdrm/usr/lib64 \
C_INCLUDE_PATH=/tmp/opencode/libdrm/usr/include \
make check
```

`make check` passes under that chain (exit 0, 17 commands). Without it the
documented primary gate fails on this host (A03). The only build warnings in a
clean module build are "the compiler differs from the one used to build the
kernel" and "pahole version differs"; `__counted_by` "attribute directive
ignored" messages come from kernel headers
(`include/linux/fs.h:1302`, `include/linux/irqdomain.h:196`), not from driver
sources.

## 5. Defect inventory

### 5.1 Table

| ID | Sev | Symptom | Reproduction | Observed evidence |
| --- | --- | --- | --- | --- |
| A01 | S1 | No RPM spec and no Fedora packaging path; the only install artifact is a Debian package | `find . -name '*.spec'`; `ls dist`; `grep -n 'dpkg-deb\|rpmbuild' build-package.sh` | no `.spec` anywhere; `build-package.sh:77` is the only package builder (`dpkg-deb --root-owner-group --build`); no `rpmbuild` invocation in the tree |
| A02 | S1 | Source tarball ships untracked working-tree files, and the release audit then fails on them | `make all && ./build-package.sh && tar -tzf dist/sm750hdmifb-0.5.9-source.tar.gz > /tmp/t.txt; grep -c 'docs/plan' /tmp/t.txt; ./tests/audit-release.sh` | 3 `docs/plan` entries in the tarball; audit exit 1, `Restrictive licence marker found in releasable code.` |
| A03 | S2 | `make check` cannot run on a host without libdrm; the documented install line has no Fedora equivalent | `pkg-config --modversion libdrm; make check` | exit 1 then exit 2; `xf86drm.h: No such file or directory` at `tests/check-vblank.c:11` |
| A04 | S2 | The only test that opens the DRM device is compiled but never executed by any target | `grep -n 'check-vblank' Makefile` | only `Makefile:11` (clean), `:14` (prerequisite), `:40` (build rule); no recipe line invokes it; manual run exits 1 with `Permission denied` |
| A05 | S2 | No register-dump facility in the driver | `make all && modinfo -p src/sm750hdmidrm.ko; grep -n 'debugfs' src/sm750_drm.c` | no `reg`/`register` parameter; `.debugfs_init = drm_vram_mm_debugfs_init` only, `src/sm750_drm.c:3256`; `/dev/mem` closed by `CONFIG_STRICT_DEVMEM=y` and `CONFIG_IO_STRICT_DEVMEM=y` |
| A06 | S2 | No 6.17 header tree is installed, so the declared floor is never built or tested here | `ls -d /lib/modules/6.17*/build; make check-all-kernels` | exit 2 for the `ls`; the matrix build covers only 7.2.13, 7.2.15 and 7.3.3 (9 combinations) and still exits 0 |
| A07 | S2 | Module is compiled by a different gcc than the kernel | `gcc --version; grep CONFIG_GCC_VERSION /boot/config-$(uname -r)` | gcc 14.4.1 vs `CONFIG_GCC_VERSION=150301` (gcc 15.3.1); build prints "compiler differs from the one used to build the kernel" |
| A08 | S2 | The `.deb` post-install script calls `update-initramfs` unconditionally under `set -e`, and `initramfs-tools` is not a dependency | `command -v update-initramfs; sed -n '56,74p' packaging/drm-postinst` | `update-initramfs` absent on this host (dracut 107-8.fc43 present); `packaging/drm-postinst:68` calls it per kernel; `Depends: dkms, make, gcc` only |
| A09 | S2 | `postinst` and `prerm` hardcode 0.5.9 and no check ties them to the declared version | `grep -n '0\.5\.9' packaging/drm-postinst packaging/drm-prerm; sed -n '10,26p' tests/check-release-version.sh` | `drm-postinst:6`, `drm-prerm:6`; the version check only compares `build-package.sh` with `dkms.conf` and the CI artifact names, so a version bump passes `make check` while the scripts still target 0.5.9 |
| A10 | S2 | Two Xorg configuration files with the same name but different content are installed and generated | `dpkg-deb -c dist/sm750hdmifb_0.5.9_all.deb; sed -n '22,25p' packaging/drm-postinst` | package installs `/usr/share/X11/xorg.conf.d/20-sm750hdmidrm.conf` (OutputClass, `PrimaryGPU yes`); postinst writes `/etc/X11/xorg.conf.d/20-sm750hdmidrm.conf` (ServerLayout/Device with `kmsdev`, no `PrimaryGPU`); both are read by Xorg |
| A11 | S3 | No archived hardware specification or register reference is tracked | `git ls-files > /tmp/f.txt; grep -Ei '\.(pdf|docx?|rom|bin)$' /tmp/f.txt` | no matches; only the untracked `docs/specs/` scratch directory added during this plan, and `docs/HARDWARE.md:23-29` refers to "the official SM750 specification" |
| A12 | S3 | No independent KMS conformance tool is available or referenced | `command -v igt_info kmscube modetest; modetest -c` | `igt_info`/`kmscube` absent; `modetest` present but prints `no device found` without the `video` group or root |
| A13 | S3 | Documented install dependencies omit `ripgrep`, which the tests require | `grep -n 'ripgrep' README.md .github/workflows/build.yml; tests/check-release-version.sh` on a host without `rg` | `README.md:34` lists build-essential dkms linux-headers libdrm-dev git only; CI installs ripgrep at `.github/workflows/build.yml:32`; without it the check exits 1 (`rg: command not found`) |
| A14 | S3 | The `.deb` has no `md5sums` member, so `dpkg --verify` cannot detect modified files | `dpkg-deb -I dist/sm750hdmifb_0.5.9_all.deb` | control archive contains only `conffiles`, `control`, `postinst`, `postrm`, `prerm` |
| A15 | S3 | The loaded module cannot report its package version | `make all && modinfo src/sm750hdmidrm.ko` | no `version:` line; no `MODULE_VERSION` in `src/` |
| A16 | S3 | The stale-version release gate only covers 0.5.0-0.5.5 and misses 0.5.6-0.5.8 | `sed -n '19,23p' tests/audit-release.sh` | pattern `sm750hdmifb[-_]0\.5\.[0-5]` |
| A17 | S3 | Documentation says parameters cannot change at runtime, but two are writable | `grep -n 'cannot be changed at runtime' docs/PARAMETERS.md; sed -n '196,208p' src/sm750_drm.c` | `docs/PARAMETERS.md:4`; `dma_batch_rows` and `staging_timing` are `0644` at `src/sm750_drm.c:207-208` and `docs/PARAMETERS.md:22-23` says "Writable through sysfs" |
| A18 | S3 | CI never runs on push, pull request or schedule | `sed -n '1,10p' .github/workflows/build.yml` | only `on: workflow_dispatch` (`:4-5`) |
| A19 | S3 | The primary test target never builds or installs the package; packaging is checked only by shell syntax checks and fixed-string greps | `sed -n '14,32p' Makefile; sed -n '1,40p' tests/check-drm-packaging.sh` | no `build-package.sh`/`dpkg-deb` call in `check`; `check-drm-packaging.sh:9-12` runs `bash -n`/`sh -n`, the rest are `grep -F` assertions; `audit-release.sh` is a separate manual step |
| A20 | S3 | DKMS auto-installs on kernels the release notes declare untested | `grep -n 'AUTOINSTALL\|BUILD_EXCLUSIVE_KERNEL' dkms.conf; sed -n '10,13p' docs/RELEASE-NOTES.md` | `AUTOINSTALL="yes"` (`dkms.conf:7`), floor regex accepts all 7.x and 10+ (`:8`), release notes say >= 7.1 untested |
| A21 | S3 | No committed evidence exists for the claimed 6.17-7.4 kernel matrix | `git ls-files docs > /tmp/d.txt; grep -c evidence /tmp/d.txt` | 0 tracked evidence files; `docs/TESTING.md:45-50` is prose only |
| A22 | S4 | Source tarball carries about 9 MB (uncompressed) of screenshots irrelevant to a DKMS build | `tar -tzf dist/sm750hdmifb-0.5.9-source.tar.gz > /tmp/t.txt; grep -c 'docs/images' /tmp/t.txt; ls -l dist/*.tar.gz` | 3 images shipped; tarball 6.3 MB |
| A23 | S4 | Planning note says `make check` runs 18 commands; it runs 17 | `sed -n '16,32p' Makefile` | exactly 17 command lines |
| A24 | S4 | fbdev is compiled in but never appears and is not documented | `ls /dev/fb*; ls /sys/class/graphics; sed -n '3640,3648p' src/sm750_drm.c` | `/dev/fb*` absent, `/sys/class/graphics` has only `fbcon`, yet `src/sm750_drm.c:3645` calls `drm_client_setup()` and `:3259` sets `DRM_FBDEV_TTM_DRIVER_OPS` |

Totals: S1 = 2, S2 = 8, S3 = 11, S4 = 3 (24 defects).

### 5.2 Notes on the mandatory rows

**A01 - no RPM packaging.** `build-package.sh` is a hand-rolled `dpkg-deb`
assembler; there is no `.spec`, no `%post`/`%preun` scriptlet pair, no
`dkms` integration macro, no `akmods`/`kmodtool` path, no Secure Boot MOK
signing step and no RPM file manifest. The audit host is Fedora 43, where the
only supported install route (`sudo apt install ./dist/...deb`) does not
exist.

**A02 - release tarball leaks untracked files.** `build-package.sh:79-90`
packs the whole working tree (`src docs tests tools packaging .github`) and
excludes only VCS metadata and build artifacts. Untracked planning files are
therefore packaged, and `tests/audit-release.sh:33-59` scans `docs` among the
releasable paths, so any private path or restrictive licence phrase in those
files fails the release. This is both a leak and a release blocker. Note for
future work: this audit's own `docs/AUDIT.md` and `docs/evidence/audit/` are
inside the scanned `docs` tree; they were written to avoid matching those
patterns, but the underlying packaging defect remains.

**A03 - `make check` needs libdrm.** `Makefile:14` makes
`tests/check-vblank` a prerequisite of `check`, and `Makefile:40-42` resolves
it through `pkg-config libdrm`. The Debian package name is `libdrm-dev`;
`README.md:34` documents that name only, and the host has no libdrm at all.
The rootless extract chain above is the only way to run the gate here.

**A04 - the vblank test is dead code.** `tests/check-vblank.c` is the sole
test that opens `/dev/dri/card0` and samples `drmWaitVBlank` (120 samples, 5%
tolerance, `tests/check-vblank.c:56-78`), but no target runs it. `make check`
is green without ever exercising the vblank ioctl path.

**A05 - no register dump.** `src/sm750_drm.c:3256` registers only
`drm_vram_mm_debugfs_init`; there is no debugfs file that prints
`ddk750_reg.h` state and no `module_param` for register access. With
`CONFIG_STRICT_DEVMEM=y` and `CONFIG_IO_STRICT_DEVMEM=y`, and no root, there
is no supported way to capture register state for a hardware bring-up report.

**A06 - the floor is unverified locally.** Only 7.2.13-100, 7.2.15-100 and
7.3.3-100 header trees exist. `tests/build-all-kernels.sh:14` enumerates
`/lib/modules/*/build` and silently skips everything else, so a green
`check-all-kernels` says nothing about 6.17.

**A07 - compiler mismatch.** `CONFIG_GCC_VERSION=150301` against gcc 14.4.1
means the module is not built by the same compiler as the kernel; kbuild emits
the mismatch warning for every build. Not fatal, but module ABI diagnostics
and any `-Werror` work are not reproducible against the shipped kernel.

**A11/A12 - specifications and conformance tooling.** No datasheet, register
PDF or ROM image is tracked (`git ls-files` finds none of `.pdf`, `.doc`,
`.rom`, `.bin`), and no igt/kmscube harness is referenced anywhere. The only
userspace tool in the tree is `tests/check-vblank`, and it is never invoked.

## 6. Packaging audit

Exists today:

- `build-package.sh` produces `dist/sm750hdmifb_0.5.9_all.deb` (68124 B) and
  `dist/sm750hdmifb-0.5.9-source.tar.gz` (6.3 MB), plus `dist/SHA256SUMS`.
- Package payload: module source under `/usr/src/sm750hdmifb-0.5.9`,
  `/etc/modprobe.d/sm750hdmidrm.conf`, `/etc/modules-load.d/sm750hdmidrm.conf`,
  `/usr/share/X11/xorg.conf.d/20-sm750hdmidrm.conf`,
  `/usr/lib/sm750hdmifb/write-xorg-config`, and two documents plus
  `copyright` under `/usr/share/doc/sm750hdmifb/`.
- Maintainer scripts: `packaging/drm-postinst` (disable predecessor files,
  remove stale DKMS trees, `dkms add`, `dkms install --force` per kernel,
  `depmod`, `update-initramfs`), `packaging/drm-prerm` (remove config,
  restore predecessor backups, `dkms remove --all`), `packaging/drm-postrm`
  (`update-initramfs -u || true`).
- Configuration assets: `packaging/sm750hdmidrm.conf` (blacklist/install
  guards for `sm750fb`, `sm750hdmifb`, and `options` for I2C pins and clock
  phase), `packaging/sm750hdmidrm.modules-load`,
  `packaging/20-sm750hdmidrm.conf`, `packaging/write-xorg-config.sh`,
  `packaging/copyright`.
- `dkms.conf` is complete for a DKMS source package and is what the `.deb`
  uses.

Missing for RPM/DKMS install verification:

- No `.spec`, no `%files` manifest, no `%post`/`%preun`/`%postun` scriptlets,
  no `Requires: dkms`, no `BuildRequires`, no `%license`.
- No Fedora-specific integration: `dracut`/`kernel-install` hooks,
  `modules-load.d` placement policy, `weak-modules`, or `kmod` dependency
  ordering. The shipped postinst is Debian-only (`update-initramfs`).
- No signing path (MOK enrollment, `sign-file`) for Secure Boot systems.
- No RPM payload test of any kind. `rpm -i --root=` is blocked in this
  environment, so even a hand-built RPM could not be verified here.
- No dependency declaration on kernel headers; the postinst skips kernels
  without a `build/Makefile` and fails if none remain
  (`packaging/drm-postinst:62-74`).

## 7. Privilege matrix

Verified as user `coder` (uid 1005, gid 1006), no root. Captures in
`docs/evidence/audit/privilege-probe.txt`.

| Capability | Exact probe | Observed result | Acceptance evidence blocked |
| --- | --- | --- | --- |
| sudo escalation | `sudo -n -l` | only `/usr/bin/dmidecode`, `/usr/local/cuda/bin/ncu`, `/usr/local/cuda/bin/nvprof` are permitted; everything else needs a password | `dkms install/remove`, `dpkg -i`, `modprobe`, debugfs mount, `update-initramfs`; blocks install verification and runtime parameter tests |
| DRM device access | `id; getfacl /dev/dri/card0` | `groups=1006(coder)`; `card0` is `root:video 0660` with ACL `user:duka:rw-`, `other ---` | running `tests/check-vblank`, `modetest -c`, any ioctl-level KMS/vblank evidence |
| Kernel log | `journalctl -k -b -n 3` | "You are currently not seeing messages from other users and the system", then "No entries" | probe-failure, EDID/timer and modeset error evidence |
| `dmesg` | `dmesg` | operation not permitted | same as above |
| PCI ROM | `cat /sys/bus/pci/devices/0000:01:00.0/rom` | permission denied | VBIOS/ROM capture and hardware identity evidence beyond `lspci` |
| DKMS install | `dkms install -m sm750hdmifb -v 0.5.9` | `Error! You must be root to use this command.` | end-to-end DKMS install verification |
| RPM into a chroot | `rpm -i --root=<tmpdir> <pkg>` | `Unable to change root directory: Operation not permitted` | RPM payload and scriptlet verification |
| Raw memory/registers | `/dev/mem` | blocked by `CONFIG_STRICT_DEVMEM=y` and `CONFIG_IO_STRICT_DEVMEM=y` | register-level hardware evidence |
| Module reload | `modprobe -r sm750hdmidrm` | requires root | parameter A/B testing and clean unload/reload evidence |

Read-only channels that remain usable: `/sys/class/drm/*`, `/dev/dri/by-path/*`,
`lspci -nnk`, `lsmod`, `dkms status`, `modinfo`, `/lib/modules/*/build`,
`/boot/config-*`, and the installed `/usr/src/sm750hdmifb-0.5.9` tree.
Privileged evidence collection is owned by a separate task; see
`docs/evidence/EVIDENCE-GAPS.md`.

## 8. Contradicted claims

| Claim | Where stated | Repo/environment evidence |
| --- | --- | --- |
| Kernel floor is 5.14 | planning handoff only | zero 5.14 hits in the tracked tree; floor is 6.17 in `dkms.conf:8`, `README.md:53`, `docs/TESTING.md:44`, `tests/build-all-kernels.sh:23`, `packaging/drm-postinst:59` |
| A fbdev userspace contract exists | planning handoff premise | no document promises fbdev; the driver registers fbdev through `src/sm750_drm.c:3645` and `:3259`, yet no `/dev/fb0` exists and `/sys/class/graphics` contains only `fbcon`; the contract is neither documented nor observable |
| Root access is available for install and diagnosis | `README.md:33-39` (`sudo apt ...`), `docs/TESTING.md:76-85` (`apt remove`, `update-initramfs -u`, reboot) | `sudo -n` allows three unrelated binaries only; the user is not in `video`; `dkms install`, `rpm --root`, `dmesg` and the DRM node are all denied (section 7) |
| Kernels >= 7.1 are untested | `docs/RELEASE-NOTES.md:10-13` | `dkms.conf:7` sets `AUTOINSTALL="yes"` and `:8` accepts every 7.x-99.x kernel; this host runs 7.3.3 with the module loaded |
| Parameters cannot be changed at runtime | `docs/PARAMETERS.md:4` | `dma_batch_rows` and `staging_timing` are `0644` (`src/sm750_drm.c:207-208`) and `docs/PARAMETERS.md:22-23` calls them writable through sysfs |
| libdrm is used only by an "optional" userspace vblank test | `docs/PROVENANCE.md:58` | libdrm is a hard build dependency of the mandatory `make check` (`Makefile:14`, `:40-42`), and the test it builds is never executed by any target (A04) |
| `make check` validates packaging | `docs/TESTING.md:6-10` | `tests/check-drm-packaging.sh` only greps strings; no target builds or installs a package (A19) |
| The install procedure is complete | `README.md:33-40` | it omits `ripgrep`, which `tests/check-release-version.sh:24` and `tests/audit-release.sh:19,49,54` require, and uses Debian package names only (A13) |

## 9. Evidence artifacts

- `docs/evidence/audit/identity-and-range.txt` - HEAD, remotes, file/LOC
  counts, tags, module and package identity, declared kernel range sources,
  zero-hit proof for 5.14.
- `docs/evidence/audit/rootless-libdrm-check.txt` - download/extract of
  libdrm plus the `make check` run and exit status.
- `docs/evidence/audit/release-gate-and-environment.txt` - release audit
  failure, tarball contents, host toolchain and configuration, and the full
  non-zero-exit table.
- `docs/evidence/audit/privilege-probe.txt` - every rootless denial listed in
  section 7.

## 10. Out of scope

Fix work for these defects is owned by separate tasks; this document does not
propose patches. The register-dump facility (A05) and the RPM spec (A01) are
tracked as implementation items elsewhere. Privileged capture that this audit
could not perform is tracked in `docs/evidence/EVIDENCE-GAPS.md`.
