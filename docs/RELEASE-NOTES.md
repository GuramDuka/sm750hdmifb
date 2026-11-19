<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Release notes

## 0.6.0 - Version reporting, register dump and RPM packaging

- **The driver reports its real version.** Both `drm_driver` instances used to
  leave `.major`/`.minor` at the default, so `modetest -c` printed
  `version 0.1.0 at 0` for every build. The numbers now come from
  `DRIVER_MAJOR`/`DRIVER_MINOR`/`DRIVER_PATCHLEVEL`, defined next to
  `SM750_DRM_VERSION`, and `modetest` reports `0.6.0`. This is what makes a
  fixed build distinguishable from the 0.5.9 package still installed on some
  hosts.
- **Read-only register dump.** `debugfs_create_file("regs", 0444, ...)` exposes
  the tracked SM750 register file at
  `/sys/kernel/debug/dri/<N>/regs`; `docs/REGISTERS.md` lists the 49 registers
  and how to resolve `<N>` from `/dev/dri/by-path`. The file is read-only and
  needs no module parameter.
- **Defect fixes carried since 0.5.9.** The source archive ships only tracked
  files (no plan/evidence/screenshots); `make check` fails early with an
  install hint when libdrm or ripgrep is missing instead of deep in a compile;
  `postinst`/`prerm` take the version from `@VERSION@` instead of hardcoding
  it, and `postinst` falls back to `dracut` when `update-initramfs` is absent;
  the generated Xorg snippet was renamed to `20-sm750hdmidrm-device.conf` so it
  cannot collide with the shipped file; the `.deb` carries `DEBIAN/md5sums`;
  and `tests/check-release-version.sh` now also gates the RPM spec and the
  version the driver reports. See [DEFECTS.md](DEFECTS.md).
- **The hardware cursor declares its blend mode.** The cursor plane exposed
  `ARGB8888` without a blend-mode property, so every probe logged
  `[PLANE:40:sm750-cursor] pixel format with alpha exposed but blend mode not
  setup`. The plane now offers `PREMULTI`, which is the contract the palette
  conversion already implements - the driver unpremultiplies alpha before
  quantising - so the warning is answered by describing the hardware, not by
  dropping the alpha format. The format, the palette conversion and the
  `hardware_cursor` default are unchanged. See [DEFECTS.md](DEFECTS.md) `A25`.
- **An abandoned modeset now finishes its commit.** When `sm750_pipe_enable`
  failed after the commit had already been armed - the HDMI bridge answering
  `-110` in the field - the failure path returned without ever starting vblank
  or consuming the commit's completion event. The DRM core then warned in
  `drm_atomic_helper_commit_hw_done`, three 10 s commit waits expired, and the
  later release path hit `refcount_t: underflow; use-after-free`. The failure
  path now calls `drm_crtc_vblank_on()` and `sm750_arm_vblank_event()`, so a
  failed enable is still a finished commit. The root cause of the `-110` itself
  is still open as `GAP-B8`; this fix makes the failure survivable, not
  impossible. See [DEFECTS.md](DEFECTS.md) `A27`.
- **Stale DKMS registrations are purged on upgrade.** Both 0.5.9 and 0.6.0
  declare `/updates/dkms` as their module destination and Fedora's `dkms`
  rewrites that to `/extra`, so an upgraded host kept a 0.5.9 registration that
  could resurface on a future kernel. The spec's `%posttrans` now removes every
  registration of this package whose version is not the installed one. See
  [DEFECTS.md](DEFECTS.md) and `tests/check-rpm-dkms.sh`.
- **RPM/DKMS packaging path.** `packaging/sm750hdmifb.spec` builds a `noarch`
  DKMS source carrier with the same file set as the `.deb`;
  `tests/check-rpm-dkms.sh` re-verifies it rootlessly. Recipe:
  [RPM packaging](PACKAGING-RPM.md).
- **The release tarball and its gate agree on what is development-only.** One
  shared list, `packaging/source-excludes.sh`, now drives the packager and the
  audit, so the two can no longer disagree about `docs/plan`, `docs/evidence`
  and `docs/images`. See [DEFECTS.md](DEFECTS.md) `A29`.
- **Opt-in static analysis and option-ROM reconstruction.** `make static` runs
  sparse, smatch, cppcheck, coccinelle and pahole against `src/` with a pinned
  baseline, and `make vbios-re` rebuilds the card's option ROM from mnemonics
  and compares it byte for byte. Both stay outside `make check`, so the default
  gate is unchanged and works without the analysers or the ROM image. See
  [Static analysis](STATIC-ANALYSIS.md) and
  [VBIOS reconstruction](VBIOS-REVERSE-ENGINEERING.md).
- **Version consistency.** The release version is declared in
  `build-package.sh`, `dkms.conf`, `src/sm750_drm.c` and the RPM spec, and
  `tests/check-release-version.sh` fails when any of them drift.
- **Validated kernels.** Offline builds and the full `make check` gate passed
  against 6.17.1-300, 7.2.15-100, 7.3.3-100 and 7.3.4-100; the per-kernel logs
  are in `docs/evidence/builds/`.
- **Runtime-validated on one kernel, build-validated on three.** The module
  was loaded and exercised on 7.3.4-100 (the release host's running kernel):
  modeset, the IGT `kms_*` subset, the vblank timer test, the hardware cursor
  and the in-kernel console all passed there. 7.2.15-100 and 7.3.3-100 were
  built and installed by DKMS but never booted, and 6.17.1-300 was a build-only
  floor check. Kernels above 7.3.4-100 have not been built or booted; final
  7.4 needs a build check when it is released. DKMS keeps `AUTOINSTALL="yes"`
  so a kernel update rebuilds the module; if that build fails the module is
  simply not installed for that kernel and the previous entry still boots.
  See [Testing and recovery](TESTING.md).

## 0.5.9 - Newer kernel support

- Add compatibility with newer Linux kernel interfaces through the current
  7.4 development code, including the 7.2 atomic transaction rename and the
  state-creation callbacks needed after removal of the old CRTC reset API.
- Preserve compatibility with the existing Linux 6.17 and 7.0 interfaces.
- **Kernels >= 7.1 are untested.** Superseded by 0.6.0, which is built and
  installed for 7.2.15-100, 7.3.3-100 and 7.3.4-100 and loaded on 7.3.4-100.
  Offline build and regression checks passed
  against 7.1, 7.2, 7.3-rc3 and a 7.4 merge-window snapshot; these results do
  not establish boot or runtime behavior. Final 7.4 requires another build
  check when it is released.
- DKMS keeps `AUTOINSTALL="yes"` so a kernel update rebuilds the module
  automatically. This is deliberate: without it a kernel upgrade silently
  drops the display driver. It also means kernels above the last offline-tested
  version are attempted without a hardware boot test. If a rebuild fails, the
  module is simply not installed for that kernel and the previous kernel entry
  still boots; see [Testing and recovery](TESTING.md).
- The module now reports its version through `MODULE_VERSION`, so
  `modinfo sm750hdmidrm` shows `version: 0.5.9` and the loader can report a
  mismatch against the source package.

The offline validation matrix and hardware verification steps are documented
in [Testing and recovery](TESTING.md).
