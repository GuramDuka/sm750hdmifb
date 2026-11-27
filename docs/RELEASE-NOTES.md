<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Release notes

## 0.6.9 - The sleep path becomes measurable

- **A root-only `pm_probe` attribute drives the PM callbacks directly.**
  Writing `suspend`, `resume` or `cycle` to
  `/sys/bus/pci/devices/0000:01:00.0/pm_probe` calls the driver's suspend and
  resume bodies once and logs each result with the `pm probe: ` prefix. The
  file is mode 0200, refuses to run while a DRM client holds master or the
  device is not registered, and holds the device with `drm_dev_enter()` for
  the duration.
- **A callback failure is now a failed write.** A successful invocation
  returns the byte count and a non-zero callback return is passed back to the
  caller, so `echo cycle > pm_probe` fails visibly and a script under `set -e`
  stops. An unknown word is still `-EINVAL`.
- **This is a measurement aid, not a system sleep.** No PCI config space is
  saved or restored, the device never enters D3hot and no power state changes,
  so a pass here says nothing about system sleep. The devices-level cycle was
  owed after a reboot with `nvidia.NVreg_PreserveVideoMemoryAllocations=0`; two
  neighbouring Tesla P100s refused it while the parameter was 1
  (`docs/DEFECTS.md` A66).
- **The sleep path was measured and passed.** With
  `nvidia.NVreg_PreserveVideoMemoryAllocations=0` on the command line, the armed
  devices cycle returned PASS on 2026-11-27 on kernel 7.3.5-100: all four `pm:`
  edges once, `suspend_stats` unchanged, and the panel back at 1024x768 and
  75 Hz. A66 is `fixed; measured on the host`
  (`docs/evidence/runtime/49-pmtest-devices-cycle.txt`).
- **A67: the probe helper misread a successful cycle.** It matched only
  `<cmd> returned <n>`, a line `cycle` never writes, and two further faults sat
  in the same block; `tools/sm750-pm-probe.sh` now matches the per-command
  result literals, and `tests/check-pm-probe.sh` section k pins them against the
  driver so a drift fails `make check`
  (`docs/evidence/runtime/50-pm-probe-cycle.txt`).

## 0.6.8 - What a production-readiness review found

- **The direct scanout path can no longer be pointed outside its buffer.**
  Nothing checked that a primary plane's framebuffer covered the mode, nor
  that the window programmed into the display engine stayed inside VRAM, so
  any DRM master committing a small buffer made the engine read past the GEM
  object. `sm750_pipe_check()` now rejects an undersized direct-path plane
  and the direct branch bounds `offset + frame_size` against the VRAM size.
  Defect D1.
- **A failed modeset is now a visible failure.** The hardware enable used to
  log its error and then arm vblank, resume the CRC source and consume the
  commit event, so the commit reported success on a dark panel. It now leaves
  the pipe down and lets the commit time out, and `sm750_pipe_update()`
  retries the enable on the next commit unless a mode change is pending.
  Defect A1, superseding the older A27 contract.
- **A monitor with absent DDC no longer stalls unrelated modesets.**
  `get_modes` used to retry EDID once with a three-second sleep inside the
  helper, under the connection mutex, and the connector is polled every ten
  seconds; there is now a single bounded read. Defect E1.
- **Two smaller ordering fixes.** `drm_crtc_vblank_get()` moved out from
  under `event_lock`, so the spinlock only guards the NULL check and the arm;
  and `INT_MASK_DMA1` is re-armed after `ddk750_init_hw()`, so the first
  upload after a resume cannot leave the DMA path disabled for the rest of
  the load. Defects C1 and P2.
- **Parameter and probe hardening.** `test_pattern` is parsed once at probe
  into an enum instead of being compared as a string on the commit path,
  where root could replace the buffer. The SWI2C pin parameters are validated
  before they narrow to `u8`. A VRAM size below the driver's minimum is
  refused at probe instead of underflowing the DMA test carve. Defects D2,
  D3 and D4.
- **The CRC reader no longer reports a dead window as if it were live.**
  After the last client exits, the scanout dump printed `0x0 pitch 3840` -
  no active mode carrying the previous mode's pitch. A zero mode now counts
  as a missing region, `sm750_pipe_disable()` clears the pitch and frame
  size, the shadow upload refuses zero geometry, and the dump says
  `no active mode`. Defect A55.
- **Nothing else changed.** No new module parameter, no UAPI change, and the
  module version string, `dkms.conf`, both spec files and the CI recipe all
  carry 0.6.8.
- **Suspend and resume remain unexercised, deferred by decision.** No
  route on this host executes the driver's PM callbacks without a
  host-wide device cycle: the owner's desktop session runs on the same
  machine, so a `pm_test=devices` cycle would also put that GPU and its
  input devices through D3hot, and the owner declined it. The VFIO/QEMU
  alternative is blocked because IOMMU DMA translation is off here (zero
  IOMMU groups, only IRQ remapping on; it needs `intel_iommu=on` and a
  reboot), and it would run the guest copy of the callbacks, not the
  host's. The driver now logs its PM entry points, so the next attempt,
  whenever a maintenance window exists, leaves four `pm:` lines in
  `dmesg` as proof. The panel also goes dark after the last client exits,
  because the DRM core disables the CRTC by design when the last
  framebuffer goes away; `tools/sm750-headless.sh` now works around it by
  restoring a text VT on teardown, while the reason the fbdev last-close
  restore never issued a commit remains unexplained. Route assessment:
  `docs/evidence/runtime/45-suspend-route-assessment.txt`.

## 0.6.7 - The device withdraws framebuffer modifiers

- **KWin 6.7.5 can present instead of failing AddFB2.** A kwin session on
  `card0` logged `kwin_wayland_drm: Failed to create framebuffer` with EINVAL
  359 times and then stopped scanning. The plane was not at fault: the driver
  passes NULL as the `format_modifiers` argument of
  `drm_simple_display_pipe_init()`, so the plane advertises
  `DRM_FORMAT_MOD_LINEAR` alone, and a probe showed AddFB2 succeeding with no
  flag and with that modifier, and failing only for modifiers the plane does
  not list. The device now sets `fb_modifiers_not_supported` in
  `sm750_modeset_init()`, so core reports `DRM_CAP_ADDFB2_MODIFIERS=0` and
  every client takes the modifiers-free AddFB2. `KWIN_DRM_USE_MODIFIERS=0`
  still works on this and older modules. Defect A47, gate S23.
- **Nothing else changed.** No new parameter, no new modifier list, and the
  NULL `format_modifiers` argument is kept.

## 0.6.4 - Sysfs attributes for sm750-smi

- **`sm750-smi` reads the driver instead of guessing.** The module now
  publishes twelve monitoring attributes on the PCI device, so they appear as
  `/sys/class/drm/cardN/device/<name>`: `mem_info_vram_total`,
  `vram_total_bytes`, `vram_used_bytes`, `active_mode`,
  `active_mode_refresh_hz`, `active_mode_pixel_clock_khz`, `hpd`, `rxsense`,
  `link_state`, `active_crtc`, `vblank_count` and `crc_supported`. The
  `memory.*`, `display.hpd`, `display.rxsense`, `display.link`,
  `crtc.index`, `vblank.count` and `crc.support` rows are live instead of
  `n/a`; `display.mode`, `display.refresh_hz` and
  `display.pixel_clock_khz` prefer the driver's view of the active pipe. The
  tool's libdrm, debugfs and `n/a` fallbacks stay, so an older module is still
  picked up with no rebuild. Gate: `tests/check-sysfs-attributes.sh`.
- **A monitoring read never disturbs the link.** `hpd`, `rxsense` and
  `link_state` read the SiI9024A interrupt status with `clear_events = false`,
  so polling them cannot consume a latched link event. The read is a pair of
  bit-banged i2c register reads, roughly a millisecond, which is acceptable for
  a monitoring poll and documented as such.
- **`vram_used_bytes` reports driver-reserved VRAM, not TTM usage.** It sums
  the regions the driver owns: the shadow front buffer, the backbuffer when it
  is staged, the hardware cursor buffer and the DMA1 test buffer. An exact
  VRAM-manager figure is not available on the shadow path, which has no
  `vram_mm` helper at all, and the attribute says so in the source comment
  rather than inventing a number.
- **`crc_supported` tracks the kernel range that registers the CRTC CRC
  callbacks.** It reports `1` only where `sm750_crtc_funcs` carries
  `.get_crc_sources`, and `0` otherwise.

## 0.6.3 - SiI9024A readiness, write timeout recovery, split tools package

- **A plugged but unpowered sink no longer reads as "not ready".** The SiI9024A
  readiness wait now gates on the live HPD bit stable for 100 ms within a
  500 ms budget, instead of requiring the powered-receiver bit for 2000 ms, so
  a receiver that is connected but not yet powered stops failing the modeset.
  Defect A42.
- **A timed-out TPI write recovers instead of failing the modeset.** When a
  bit-banged i2c write times out, the bus is cleared, the driver waits 10 ms and
  retries, three attempts in total, before continuing on the compatibility path;
  a transient stall no longer surfaces as `-110`. The EDID read is skipped while
  the transmitter is powered down. Gate: `tests/check-sii902x-recovery.sh`.
- **`sm750-smi` ships as its own package.** The monitoring utility is now
  installed as `/usr/bin/sm750-smi` by `sm750hdmifb-tools` on both formats -
  `sudo dnf install sm750hdmifb sm750hdmifb-tools`, or
  `sm750hdmifb-tools_0.6.3_amd64.deb` from `build-package.sh`. It is
  architecture-dependent and separate from the noarch DKMS module package,
  because rpm cannot attach an arch subpackage to a noarch parent; a source
  build still installs it to `/usr/local/sbin/sm750-smi` via
  `make install-tools`. Run `sm750-smi` for the device block or
  `sm750-smi --query=name,driver.version` for values only. The module package's
  file list is unchanged. See `docs/PACKAGING-RPM.md` section 10.

## 0.6.2 - Test card, console helper, CRC ownership

- **A panel with no client is never dead-black.** When the pipe is enabled with
  a frame that is entirely blank and no userspace DRM master owns the display,
  the driver now paints a test card: seven EBU colour bars with a black
  right-edge bar, an eight-step grayscale staircase, a 16x12 grid, a centred
  crosshair and circle, and a 1 px border. `test_pattern` selects `auto`,
  `always` or `off`. This closes the case where the foreground VT is in
  `KD_GRAPHICS`, the kernel drops console output before fbcon and the card scans
  a frame nobody painted.
- **The card resists burn-in and shows motion.** `test_pattern_period_ms`
  (default 5000) rotates the palette, and `test_pattern_anim_ms` (default 40, `0`
  stops it) drives a bouncing disc across the frame; a tick repaints only the two
  bounding boxes it touches, about 35 KiB at 1080p in 32 bpp instead of the
  8 MiB frame, so 25 frames per second cost no measurable bandwidth.
- **A scanout CRC source now owns the window.** An armed CRC source cancels the
  card and the paint predicate returns false while `crc_enabled` is set, so a
  repaint can no longer tear the CRC stream (defect A36: three distinct values in
  twelve static frames). The one-shot `test_pattern_fresh` flag is gone: it was
  consumed one commit too late, because `drm_atomic_helper_commit_tail()` runs
  `commit_planes` before `commit_modeset_enables`, so it dropped the client's
  first present instead of the enabling commit. Painting is gated on "no
  userspace DRM master and a blank frame", so a master's black output stays a
  picture.
- **Console helper.** `tools/sm750-console.sh` reports the active VT, its
  `KDGETMODE`, the fbcon bind state and the scanout content, and switches the VT
  back to `KD_TEXT` or to `KD_GRAPHICS`. Installation needs root; see
  `docs/ROOT-ACTIONS.md` 3.4.
- **New gates.** `tests/check-test-pattern.sh` plants eighteen defects,
  including a paint before `sm750_program_mode()`, a missing softscale guard, a
  repaint that ignores a backbuffer, a paint while a CRC source is armed, a
  restored one-shot upload skip, a missing master check, a velocity that never
  inverts and a full-frame repaint on every tick.
- **Repository hygiene.** `tools/sm750-restore-cycle.sh` no longer hardcodes a
  developer home directory; it resolves the repository through `SM750_REPO` and
  `getent passwd`, so the release audit passes on a clean tree (defect A35).

**Packaging: 0.6.2-2** (same source, RPM `Release` 2). A 0.6.2-1 upgrade over a
host that still had a broken 0.6.1 DKMS registration installed the package but
not the module: `%posttrans` ran its build loop first, `dkms install` tried to
uninstall the older registered version, hit the dangling
`/var/lib/dkms/sm750hdmifb/0.6.1/source` with `Error! Could not locate dkms.conf
file.`, and installed nothing; `/sys/module/sm750hdmidrm/version` kept printing
`0.6.1`. The stale-registration purge now runs before the build loop, and a
failed removal deletes a registration tree that has no readable
`source/dkms.conf`, which is what dkms itself asks for (A37). Two smaller
packaging defects ride along: the inert `CLEAN=` directive is gone from
`dkms.conf`, so `dkms add` no longer prints `Deprecated feature: CLEAN` (A38),
and `tools/sm750-console.sh` prints its zero-frame hint only when the scanout
CRC really is `0xe20eea22` (A39). The 0.6.2-2 install has since been observed on
this host: `rpm -q sm750hdmifb` reported `0.6.2-2.fc43` before the -3 upgrade
(`docs/evidence/runtime/28-dangling-kernel-link.txt` section 6), and section 3
of that file records the 0.6.2-2 transaction failing to install the module. The
runbook is `docs/ROOT-ACTIONS.md` section 3.6.

**Packaging: 0.6.2-3** (same source, RPM `Release` 3). 0.6.2-2 fixed the order
but not the whole leftover: the host also carried a dangling DKMS
active-version link per kernel (`/var/lib/dkms/sm750hdmifb/kernel-<kernel>-<arch>`
pointing at the erased `0.6.1/<kernel>/x86_64`), and `do_install()` in dkms
3.4.4 reads the version out of that link without checking that it is registered,
so `dkms install` still died trying to uninstall `0.6.1` and no kernel received
the module (A40). A second purge loop, after the version purge and before the
build loop, now removes a link that does not resolve and leaves a link that
does. The upgrade from `0.6.2-2` to `0.6.2-3` has since run on this host
(`sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-3.fc43.noarch.rpm`,
by its owner): `%posttrans` completed for all three installed kernels, the
active-version branch of `dkms do_install()` ran against a healthy `0.6.2`
registration and succeeded, `dkms status` reports `0.6.2` `installed` for each
kernel, `/sys/module/sm750hdmidrm/version` prints `0.6.2`, and no
`removing dangling DKMS kernel link:` line appeared because no link dangled.
The transcript is section 8 of `docs/evidence/runtime/28-dangling-kernel-link.txt`.

## 0.6.1 - Display-control transition, blank-console diagnostic

- **A modeset no longer fails on this panel.** The display-control transition
  waited for two bits with an exact compare and discarded the display-off
  result; it now compares through a mask, re-pokes the register on every poll and
  derives the wait budget from the vertical period, so `failed to enable HDMI
  mode` no longer appears (defect A32, proven with 30 of 30 restore cycles and 20
  of 20 mode changes).
- **A blank console framebuffer is named once.** `sm750_shadow_frame_is_blank()`
  and one `drm_info` line report the case where the bright frame nobody painted
  is the frame being scanned, instead of leaving it to guesswork.
- **New gates.** `tests/check-restore-path.sh` and `tests/check-console-blank.sh`.

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

## 0.6.4

- The driver publishes twelve monitoring attributes on the device node
  (/sys/class/drm/cardN/device): mem_info_vram_total, vram_total_bytes,
  vram_used_bytes, active_mode, active_mode_refresh_hz,
  active_mode_pixel_clock_khz, hpd, rxsense, link_state, active_crtc,
  vblank_count, crc_supported. sm750-smi reads them, so memory, display and
  link fields report live values instead of n/a.
- The SiI9024A DDC grant waits up to 2000 ms in 200 ms polls with one bus
  clear and one retry per mode set; the grant switch is released on every
  exit path.
- sm750-smi banner rows pad to exactly 79 columns.
