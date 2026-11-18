<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Defect dispositions

One row per defect inventoried in [AUDIT.md](AUDIT.md), plus five found later:
`A25`, in the kernel log of the running 0.5.9 build, `A26`, in the IGT
`kms_addfb_basic` run, `A27`, isolated by a targeted reproduction of the
same 0.5.9 kernel log episode, `A28`, by the static-analysis gate added in
T19, and `A29`, by the release gate itself. They are recorded here because this
table is the current defect state, not a copy of the audit. [AUDIT.md](AUDIT.md)
still describes the pre-fix tree and is not rewritten. Statuses:

- **fixed** - changed in this task and verified on this host.
- **deferred** - not fixed here; the reason names the blocker.
- **accepted** - deliberate behaviour; the residual risk is documented.

Evidence lives in `docs/evidence/builds/`; the numbers in the evidence column
refer to `<NN>-<slug>.log` in that directory.
`10-defect-before-after.log` shows the before (`git show HEAD:<path>`) and
after (working tree) form of every fixed item. All logs were produced unprivileged with `CC=/usr/bin/gcc` (GCC
15.3.1) against the header trees installed on this host.

| ID | Sev | Defect | Status | Change reference | Evidence |
| --- | --- | --- | --- | --- | --- |
| A01 | S1 | No RPM spec; Debian is the only packaging path | fixed | `packaging/sm750hdmifb.spec` (noarch DKMS source carrier, 36 files); rootless gate `tests/check-rpm-dkms.sh`; recipe `docs/PACKAGING-RPM.md` | `docs/evidence/packaging/01`-`07` |
| A02 | S1 | Source tarball ships untracked working-tree files | fixed | `build-package.sh:90-117` (tracked-only `git ls-files -z` manifest); `tests/audit-release.sh:36-73` (archive-rooted manifest diff) and `:75-101` (licence/path scan of what ships) | `02`, `07`, `08`, `10` |
| A03 | S2 | `make check` fails deep in the build when libdrm is missing | fixed | `Makefile:17-28` (`check-deps` preflight, prerequisite of `check` at `Makefile:30`); `README.md:41-52` | `10`, `01` |
| A04 | S2 | `tests/check-vblank` compiled but never executed | fixed | `tests/check-drm-module.sh:80-90` (live probe with explicit `SKIP` reasons) | `01`, `10` |
| A05 | S2 | No register-dump facility in the driver | fixed | `src/sm750_drm.c:3258-3352` (`regs` debugfs file), `:3363`, `:3376`; `docs/REGISTERS.md`; `README.md:290-305` | `09`, `10` |
| A06 | S2 | No 6.17 header tree, so the declared floor was never built here | fixed | extracted `kernel-devel-6.17.1-300.fc43` to `/mega/tmp/sm750/t5/k617` (scratch) and built all three formats | `06`, `10` |
| A07 | S2 | Module compiled by a different gcc than the kernel | fixed | build and CI pin `CC=/usr/bin/gcc`; documented at `README.md:53-59` | `01`-`05`, `10`, `11` |
| A08 | S2 | `postinst` calls Debian-only `update-initramfs` unconditionally under `set -e` | fixed | `packaging/drm-postinst:12-20,83` (`refresh_initramfs` with dracut fallback), `packaging/drm-postrm:5-13`; `build-package.sh:69` (`Recommends: initramfs-tools \| dracut`) | `10`, `08` |
| A09 | S2 | `postinst`/`prerm` hardcode 0.5.9 with no check | fixed | `packaging/drm-postinst:8`, `packaging/drm-prerm:7` (`version=@VERSION@`), `build-package.sh:56-59` (substitution), `tests/check-release-version.sh:15-24` | `10`, `01`, `08` |
| A10 | S2 | Two different Xorg snippets named `20-sm750hdmidrm.conf` | fixed | generated file renamed to `20-sm750hdmidrm-device.conf` (`packaging/drm-postinst:38`, `packaging/drm-prerm:19`); shipped asset name unchanged for the T6 file list | `10`, `01` |
| A11 | S3 | No tracked hardware specification or register reference | fixed (register reference); datasheet not redistributable | `docs/REGISTERS.md` (49-register table + dump instructions); `src/sm750_drm.c:3258-3309` | `10`, `09` |
| A12 | S3 | No independent KMS conformance tool available | fixed | ACL (`/etc/udev/rules.d/99-sm750-coder-acl.rules`) plus rootless extractions of `kmscube` and `igt-gpu-tools` under `/mega/tmp/sm750/t10/x/`; both now run unprivileged against `/dev/dri/card0` and were re-run on the installed 0.6.0 by T11 (`core_getversion` reports `v0.6`; `kms_addfb_basic` 26 SUCCESS / 14 SKIP / 1 FAIL, identical to the pre-fix baseline). Only scanout CRC and external capture remain blocked - `docs/evidence/EVIDENCE-GAPS.md` GAP-B3 | `docs/evidence/runtime/06-igt.txt`, `docs/evidence/runtime/05-kmscube.txt`, `docs/evidence/runtime/17-kmscube-0.6.0.txt`, `docs/evidence/runtime/19-igt-0.6.0.txt` |
| A13 | S3 | Install dependencies omit `ripgrep` | fixed | `README.md:34` (Ubuntu line), `README.md:41-52` (dependency paragraph and Fedora line) | `10`, `01` |
| A14 | S3 | `.deb` has no `DEBIAN/md5sums` | fixed | `build-package.sh:82-88`; verified by `tests/audit-release.sh:103-107` | `07`, `08`, `10` |
| A15 | S3 | Module cannot report its package version | fixed | `src/sm750_drm.c:70` (`SM750_DRM_VERSION`), `:3866` (`MODULE_VERSION`); `tests/check-drm-module.sh:14-17` | `09`, `10` |
| A16 | S3 | Stale-version release gate only covered 0.5.0-0.5.5 | fixed | `tests/audit-release.sh:22-31` (current version derived from `build-package.sh`) | `08`, `10` |
| A17 | S3 | Documentation claimed all parameters are load-time only | fixed | `docs/PARAMETERS.md:4-11` | `10` |
| A18 | S3 | CI only ran on `workflow_dispatch` | fixed | `.github/workflows/build.yml:4-7` (`push`, `pull_request`) | `10` |
| A19 | S3 | `make check` never built or audited a package | fixed | `Makefile:71-74` (`check-package`); CI step at `.github/workflows/build.yml:48` | `07`, `08`, `10` |
| A20 | S3 | DKMS auto-installs on kernels the release notes call untested | accepted | rationale at `docs/RELEASE-NOTES.md:14-19`; no change to `dkms.conf:7-8` | `10` |
| A21 | S3 | No committed evidence for the claimed kernel matrix | fixed | `docs/evidence/builds/01`-`11` (this task's logs; T4 cites them) | `02`-`06`, `11` |
| A22 | S4 | Source tarball carried about 9 MB of screenshots | fixed | same fix as A02; `docs/images` excluded from the manifest (`build-package.sh:98`) | `07`, `10` |
| A23 | S4 | Planning note said 18 `make check` commands; it runs 17 | fixed | `docs/plan/20261117-sm750-driver-prod/plan.yaml:28` (corrected), count re-verified in `01-make-check.log` | `01`, `10` |
| A24 | S4 | fbdev compiled in but never appears and was not documented | accepted | behaviour and conditions documented at `README.md:307-313` | `10` |
| A25 | S3 | Found post-audit in the kernel log, not by the audit: `[PLANE:40:sm750-cursor] pixel format with alpha exposed but blend mode not setup. Please fix.` The cursor plane exposed `DRM_FORMAT_ARGB8888` with no blend-mode property, so the DRM core could not tell how the driver expresses alpha | fixed | `src/sm750_drm.c:3491` (`drm_plane_create_blend_mode_property()` offering `BIT(DRM_MODE_BLEND_PREMULTI)`); format list unchanged at `src/sm750_drm.c:3424`; gate `tests/check-hardware-cursor.sh:32-33` plus the negative assertion at `:43-45`; verified fixed on the installed module by T11 - the warning is absent from both 0.6.0 probes while the single boot-time occurrence (t=3.68 s, the 0.5.9 probe) remains, and `modetest -p` shows property `42 pixel blend mode` with `Pre-multiplied=0` on cursor plane 40 | `docs/evidence/runtime/cursor-alpha-01-warning-before.txt`, `docs/evidence/builds/19-cursor-alpha-fix.log`, `docs/evidence/runtime/13-module-reload.txt`, `docs/evidence/runtime/18-kernel-log-0.6.0.txt` |
| A26 | S4 | IGT `kms_addfb_basic --run-subtest size-max` fails with `DRM_IOCTL_MODE_ADDFB2` EINVAL. Not a driver defect and not a hardware limit: the subtest issues a `1024x2048` `DRM_FORMAT_RGB565` framebuffer at `tests/kms_addfb_basic.c:594` without a format probe, and the driver exposes only `DRM_FORMAT_XRGB8888` on the primary plane (`src/sm750_drm.c:3423`) with `max_height` declared as 1152 (`src/sm750_drm.c:95`, `:3437`). DRM core rejects it first on height (2048 > 1152) and would reject it again on format. The silicon allows it: DS-1 rev 1.4 p151 `PANEL_FB_WIDTH` permits 16368 bytes of pitch and p153 `PANEL_PLANE_BR` permits a 2048-line window, so the limit is driver policy, not hardware | accepted | no code change recommended; both rejections are generic DRM checks on declared limits, and raising `max_height` alone cannot make the subtest pass because the format gate rejects RGB565 independently. Contract and IGT gap documented in `docs/evidence/runtime/10-addfb-size-max.txt` section 5; unchanged on 0.6.0 (T11) | `docs/evidence/runtime/06-igt.txt:52,68-76,150,161`, `docs/evidence/runtime/10-addfb-size-max.txt`, `docs/evidence/runtime/19-igt-0.6.0.txt` |
| A27 | S3 | A single failed modeset becomes a kernel WARNING plus 30 s of stalled atomic commits, and once a refcount underflow. `sm750_pipe_enable`'s `fail:` label returns `-110` from `sm750_program_mode` without calling `drm_crtc_vblank_on()` and without consuming the commit's vblank event, so `drm_atomic_helper_commit_hw_done` trips `WARN_ON(new_crtc_state->event)` (`drivers/gpu/drm/drm_atomic_helper.c:2758` in 7.3.4), every later commit waits 10 s per atomic object (CRTC 38, CONNECTOR 35, PLANE 36) and a later `drm_release` restore can underflow a refcount in `__drm_atomic_helper_plane_destroy_state` via `drm_gem_simple_kms_destroy_shadow_plane_state` | fixed | trigger isolated by reproduction: SIGINT a kmscube ~300 ms into its first commit, then `modetest -s 35@38:1024x768-60`; the failure lands on the fbdev-restore commit issued from `drm_release`. Measured rate 1/36 (2.8 %) for that shape and 0/169 for every other shape, so the trigger is established and the rate is not; the fail path (`src/sm750_drm.c:3105-3117`, success path `:3101-3102`) is the defect and is independent of the trigger. Which of the five fallible calls in `sm750_program_mode` (`src/sm750_drm.c:1312`, `:1316`, `:1319`, `:1346`, `:1349`) returns `-110` is not identifiable on 0.5.9 (no debug output on that path, no `regs` debugfs); the 330.003 ms gap ranks `ddk750_set_display_control(0, false)` at `src/sm750_drm.c:1316` first (`src/ddk750_display.c:12-26`, `:68-97`, `src/ddk750_mode.c:285-305`). Re-produced on the installed 0.6.0 by T11, which rules out any T5/T9/T13 change as the cause; fixed in T20 by finishing the abandoned commit at the shared `fail:` label - `drm_crtc_vblank_on()` then `sm750_arm_vblank_event()` at `src/sm750_drm.c:3131`/`:3132`, the same two calls the success path makes at `:3101`/`:3102`, so `new_crtc_state->event` is consumed whether the event is armed on the driver timer or sent at once. Static gate: `tests/check-drm-policy.sh:141-167` asserts the fail block contains both calls and has no early `return;` (no new `make check` recipe line, so the count stays 17). Post-fix reproduction: 108/108 attempts with zero WARNING, zero `commit wait timed out` and zero refcount underflow, while the `-110` itself still fired 5 times in the run - the trigger is unchanged, the cascade is gone | `docs/evidence/runtime/09-hdmi-minus-110.txt`, `docs/evidence/runtime/07-kernel-log.txt:50-110`, `docs/evidence/runtime/18-kernel-log-0.6.0.txt`, `docs/evidence/runtime/17-a27-fix-build.txt`, `docs/evidence/runtime/18-a27-fix-install.txt`, `docs/evidence/runtime/19-a27-fix-reproduce.txt` |
| A28 | S4 | Found by static analysis, not by the audit: smatch reports `shift has higher precedence than mask` five times on 7.3.4 and three times on 6.17.1, at `src/sm750_drm.c:1651,1663,1665,1673` and `src/sii902x.c:741`. Not a driver defect and not fixable in the driver: the message is produced by `GENMASK_TYPE()` (`include/linux/bits.h:52`), which mixes `<<` with `&`/`>>` without inner parentheses and is reached through `DMA_BIT_MASK()` (`include/linux/dma-mapping.h:126`) and `GENMASK()`; the enclosing cast and parentheses make the value correct, and smatch's precedence check does not model the cast. A five-line out-of-tree probe reproduces the warning with no driver code. The four fixed sparse findings (`sm750_test_*` globals with no declaration in scope) and the cppcheck `unknownMacro` suppression are also recorded there | accepted | no code change: the driver expressions are correct and the header macro is not ours to edit. The residual findings are pinned in the opt-in gate baseline, so the gate fails on anything new while these stay quiet. Also records that the out-of-tree module has no `.BTF` section (`Skipping BTF generation ... due to unavailability of vmlinux`), so `pahole -F btf` is unavailable and layouts come from DWARF | `docs/STATIC-ANALYSIS.md`, `docs/evidence/builds/20-static-sparse.log` to `25-static-gate.log` |
| A29 | S2 | The packager and the release gate each carried their own copy of the development-only directory list, so they disagreed by construction: `build-package.sh:98-100` shipped the tracked tree minus `docs/images` only, while `tests/audit-release.sh:54-58` failed the archive if `docs/plan`, `docs/evidence` or `docs/images` appeared in it. Once `docs/plan/` and `docs/evidence/` became tracked, every fresh build produced a tarball the gate rejected: `./tests/audit-release.sh` exited 1 with `Source archive contains development-only content: docs/plan` on a 160-file archive that carried 1 `docs/plan` and 69 `docs/evidence` entries. The same divergence had a second consequence: the shipped `docs/ENVIRONMENT.md` named three absolute `$HOME` paths that the audit's own private-path scan rejects, hidden behind the earlier exit | fixed | one list, read by every consumer: `packaging/source-excludes.sh` declares `sm750_dev_only=(docs/plan docs/evidence docs/images)` and `sm750_dev_only_pathspecs()`; `build-package.sh:90-128` sources it for both the `git ls-files` pathspecs and the non-git `--exclude=` arguments; `tests/audit-release.sh:52-80` sources it for the forbidden-directory loop and for the manifest diff; `tests/check-rpm-dkms.sh:70-85` sources it for the DKMS payload. `tests/check-drm-packaging.sh:32-49` asserts all three paths are in the shared file, that both scripts read it, and that neither hard-codes `:(exclude)docs/` again. `docs/ENVIRONMENT.md:41-51` now writes those paths with `~/`. The gate is not narrowed: a tarball rebuilt without the list still fails it | `docs/evidence/builds/26-audit-release.log`, `docs/evidence/builds/27-source-archive-manifest.log` |

## Deferred and accepted items in detail

### A01 - no RPM spec (closed in T6)
`packaging/sm750hdmifb.spec` is a noarch DKMS source carrier (`Version 0.6.0`,
`BuildArch noarch`) that ships the same 36 files as the `.deb` and replaces the
dpkg maintainer scripts with `%post` (`dkms add`, first install only),
`%posttrans` (`dkms build`, `dkms install --force`, `depmod -a`) and `%preun`
(`dkms remove --all`), with no `%postun`. `rpmbuild -ba` exits 0 from a fresh
`_topdir`; `tests/check-rpm-dkms.sh` re-verifies it rootlessly and exits 0.
The root-only transaction test was `GAP-B7` in
`docs/evidence/EVIDENCE-GAPS.md`; T11 closed it by installing, erasing and
reinstalling 0.6.0 through the allowlisted `dnf` path
(`docs/evidence/runtime/11-preconditions.txt`, `12-rpmbuild-0.6.0.txt`,
`20-rollback.txt`, `21-final-state.txt`). The build recipe is
`docs/PACKAGING-RPM.md`.

### A12 - no independent KMS conformance tool (closed in T10/T11)
`igt_info` and `kmscube` are not installed and cannot be installed without
root, and `modetest` originally printed `no device found` without `video` group
membership. Both halves of that were solved without installing anything:
`/etc/udev/rules.d/99-sm750-coder-acl.rules` grants `coder` `rw` on the card
node at every probe, and `kmscube` plus `igt-gpu-tools` were extracted from
their Fedora packages into `/mega/tmp/sm750/t10/x/` and run with
`LD_LIBRARY_PATH` pointed at the extracted libraries (including the extracted
`gsl`, which was the one missing dependency, exit 127). T10 ran the suite on the
stale 0.5.9 build; T11 re-ran it on the installed 0.6.0
(`docs/evidence/runtime/05-kmscube.txt`, `06-igt.txt`,
`17-kmscube-0.6.0.txt`, `19-igt-0.6.0.txt`). What remains unavailable is scanout
CRC and external capture, tracked as the residual `PARTIAL` in GAP-B3, not as a
tooling gap.

### A20 - DKMS AUTOINSTALL (accepted)
`AUTOINSTALL="yes"` is what makes a kernel update rebuild the module at all.
Removing it would silently drop the display driver on the next kernel upgrade,
and narrowing `BUILD_EXCLUSIVE_KERNEL` to the tested range would contradict the
project's declared 6.17+ support. The residual risk - an untested kernel above
the last verified version is attempted - is now stated in
`docs/RELEASE-NOTES.md:14-19`. The offline matrix in this task's evidence
reduces the risk for 6.17.1 through 7.3.4.

### A24 - fbdev (accepted)
`drm_client_setup()` and `DRM_FBDEV_TTM_DRIVER_OPS` are intentional. A
`/dev/fb0` node only appears when the kernel provides fbdev emulation and no
other framebuffer driver owns the device, so its absence on this host is
environmental rather than a driver defect. The conditions are documented in
`README.md:307-313`.

### A11 - datasheet (partially deferred by licensing)
The vendor SM750 datasheet cannot be redistributed in this repository.
`docs/REGISTERS.md` now tracks the register map the driver actually uses, which
is what the defect asked for at the level a GPL repository can carry.

### A25 - cursor plane exposes alpha without a blend mode (fixed; found post-audit)

The kernel log of the running pre-fix 0.5.9 module carries, on every probe:

```
sm750hdmidrm 0000:01:00.0: [drm] [PLANE:40:sm750-cursor] pixel format with alpha exposed but blend mode not setup. Please fix.
```

It is emitted by `validate_blend_mode_for_alpha_formats()` in the DRM core,
called from `drm_mode_config_validate()` during `drm_dev_register()`. The
function returns immediately when `plane->blend_mode_property` is set; otherwise
it walks the plane's format list and warns for the first format whose
`drm_format_info()` reports `has_alpha`. The driver's cursor plane advertised
`DRM_FORMAT_ARGB8888` at `src/sm750_drm.c:3424` and created no property, so the
warning was accurate.

**Route chosen: keep `ARGB8888` and create the blend-mode property**, not switch
to `XRGB8888`. The hardware does consume per-pixel alpha: `sm750_cursor_encode()`
uses alpha as a dithered transparent/opaque mask over three palette entries, and
`sm750_cursor_unpremultiply()` (`src/sm750_drm.c:2618`) divides the colour by
alpha before quantising, which means the input contract is premultiplied ARGB.
Exposing `XRGB8888` would deny the alpha the driver actually implements and
would hide it from compositors, which hand a cursor plane `ARGB8888` by
convention. The property is created at `src/sm750_drm.c:3491`:

```c
ret = drm_plane_create_blend_mode_property(&sdev->cursor_plane,
		BIT(DRM_MODE_BLEND_PREMULTI));
if (ret)
	return ret;
```

Only `PREMULTI` is offered. `COVERAGE` would state that the driver premultiplies
colour it receives unpremultiplied, which is the opposite of what
`sm750_cursor_unpremultiply()` does, so advertising it would be a second
mismatch. `PREMULTI` is also the one mode every supported kernel accepts: 6.17
rejects a mask without it (`WARN_ON` in `drivers/gpu/drm/drm_blend.c`), and 7.2
and 7.3 accept it, so the call needs no `LINUX_VERSION_CODE` guard. No plane
alpha property is created - `drm_plane_create_alpha_property()` is deliberately
absent - because the hardware has no plane-wide alpha and the core check does not
require one.

Nothing else changed: the format list (`src/sm750_drm.c:3424`), the palette
conversion and the enable message `64x64 hardware cursor plane enabled with ARGB
palette conversion` (`src/sm750_drm.c:3807`) are untouched, and the
`hardware_cursor` default stays on.

The before capture is `docs/evidence/runtime/cursor-alpha-01-warning-before.txt`
(kernel log plus the pre-fix `modetest` property surface, which shows plane 40
with `type` and `IN_FORMATS` only). The after side is
`docs/evidence/builds/19-cursor-alpha-fix.log`: the gate passes, the built
object calls the property helper with mask 1, and all four kernel builds carry
it.

The live capture T11 owed is now recorded. On the installed 0.6.0 module the
warning does not appear at either probe: the whole-boot log contains exactly one
occurrence, at `[3.681998]`, four milliseconds before the `Initialized
sm750hdmidrm 0.1.0` line, i.e. from the stale 0.5.9 probe at boot, and neither
`[1999.206388]` nor `[2095.796958]` (both 0.6.0) emits it
(`docs/evidence/runtime/18-kernel-log-0.6.0.txt`). The property is visible to
userspace: `modetest -p` lists `42 pixel blend mode:` with `flags: enum`,
`enums: Pre-multiplied=0`, `value: 0` on cursor plane 40
(`docs/evidence/runtime/15-modetest-properties-0.6.0.txt`). Fixed and verified
on hardware.

### A26 - IGT size-max asks for a format and a height the driver does not expose (accepted)

`kms_addfb_basic --run-subtest size-max` is the only genuine driver-behaviour
failure in the IGT baseline (`docs/evidence/runtime/06-igt.txt:52,150,161`):
`DRM_IOCTL_MODE_ADDFB2` returns EINVAL at `tests/kms_addfb_basic.c:594`.

The subtest builds three framebuffers on one 4 MiB XRGB8888 object
(`tests/kms_addfb_basic.c:577-578`): `f` = 1024x1024 XRGB8888 pitch 4096,
`f_16` = 1024x2048 RGB565 pitch 2048, `f_8` = 2048x2048 C8 pitch 2048. The
first addfb succeeds; the second, at `:594`, is the one that fails. Only the C8
step is gated on `igt_display_has_format_mod()` (`:597`), so the RGB565 request
is issued unconditionally even though the driver never advertises that format.

Two generic DRM checks reject the request, and neither is driver-local code:

- height: `drm_internal_framebuffer_create()` compares `r->height` against the
  driver's declared `max_height` and returns `-EINVAL` with
  `"bad framebuffer height %d, should be >= %d && <= %d\n"`. 2048 > 1152.
- format: `drm_gem_fb_init_with_funcs()` rejects a format no plane advertises
  (`drm_any_plane_has_format()`) because the driver sets `DRIVER_ATOMIC`; the
  message is `"Unsupported pixel format %p4cc / modifier 0x%llx\n"`. RGB565 is
  not in `src/sm750_drm.c:3423`.

The GEM `min_size` gate does not fire: the fixture object is exactly the
4194304 bytes the request needs.

The datasheet is not the constraint. DS-1 rev 1.4 p151 `PANEL_FB_WIDTH` allows
16368 bytes per line, p152 `PANEL_WINDOW_HEIGHT` allows 4095 lines and p153
`PANEL_PLANE_BR` allows a 2048-line window, with 64 MiB of VRAM available
(datasheet identity at `docs/specs/INDEX.md:29`). A 1024x2048 framebuffer at
2048-byte pitch is inside all of them, so this is
driver policy: `max_height` is the tallest catalogue mode (`docs/MODES.md:76-86`)
and RGB565 is the internal scanout conversion, not a KMS format
(`docs/MODES.md:91-96`, `docs/PARAMETERS.md:19`).

No code change is recommended. Raising `max_height` would not make the subtest
pass, because the format gate rejects RGB565 on its own; adding RGB565 to the
primary plane would require 16-bit source rows in a pipeline whose converters all
assume u32 XRGB8888 rows (`src/sm750_drm.c:1991-2015`), contradicting the
documented contract. The full probe matrix, the datasheet page quotes and the
re-test notes for 0.6.0 are in `docs/evidence/runtime/10-addfb-size-max.txt`.

Confirmed unchanged on the installed 0.6.0 by T11: the full-binary run gives the
identical 26 SUCCESS / 14 SKIP / 1 FAIL tally, and size-max fails at the same
line with the same `Last errno: 22, Invalid argument`
(`docs/evidence/runtime/19-igt-0.6.0.txt`). The standalone
`--run-subtest size-max` invocation is not citable - it interleaves unrelated
`is_intel_device(fd)` requirement lines from the sibling tiling fixtures, which
read as a skip - so the full run is the record.

### A27 - a failed modeset leaves the commit's vblank event unconsumed (fixed in T20; found post-audit)

The episode recorded in `docs/evidence/runtime/07-kernel-log.txt:50-110` is
reproducible, and its driver-side cause is the `fail:` label of
`sm750_pipe_enable`, not the hardware event that triggers it.

On the success path `src/sm750_drm.c:3095-3103` calls `drm_crtc_vblank_on()`
(`:3101`) and `sm750_arm_vblank_event()` (`:3102`) before returning. The
`fail:` label at `src/sm750_drm.c:3105` clears the staging fields and returns
`-110` without either call, so the atomic commit that carried a `PAGE_FLIP_EVENT`
still holds `new_crtc_state->event` when
`drm_atomic_helper_commit_hw_done()` runs its
`WARN_ON(new_crtc_state->event)` (`drivers/gpu/drm/drm_atomic_helper.c:2758` in
7.3.4). The commit is then never completed: the three atomic objects each wait
their 10 s and report `commit wait timed out`, and because the CRTC was left
with vblank accounting off, a later `drm_release` restore can underflow a
refcount in `__drm_atomic_helper_plane_destroy_state` (observed once, at
`[8586.308230]`, 62.4 s after the `-110`, in a different process).

Reproduction (`docs/evidence/runtime/09-hdmi-minus-110.txt` section 6): 205
controlled attempts, 1 hit. The hit requires SIGINT to a kmscube about 300 ms
into its first commit, followed by `modetest -s 35@38:1024x768-60`; the `-110`
then appears 330.003 ms later on the 1920x1080 restore that runs when modetest
closes the device, with the same WARNING site and the same `Code:` bytes as the
original. Every other shape tested - plain modeset-and-close, detect races, two
DRM masters, SIGKILL at 2 s, SIGINT/SIGTERM at 2 s, a 25-run soak, mode churn,
and kill delays of 0.1/0.2/0.4/1.0/2.0 s - produced nothing in 169 attempts.
The rate for the shape that works is 1/36, so the trigger is established and the
rate is not.

What remains open is narrower than the defect: which of the five fallible calls
in `sm750_program_mode` (`src/sm750_drm.c:1312`, `:1316`, `:1319`, `:1346`,
`:1349`) returns `-110`. That function and `src/ddk750_display.c`,
`src/ddk750_mode.c`, `src/ddk750_swi2c.c` and `src/ddk750_hwi2c.c` contain no
`dev_dbg`/`drm_dbg` at all, dynamic debug is root-only on this host, and 0.5.9
has no `regs` debugfs file, so the producer cannot be seen from an unprivileged
account. The 330.003 ms gap admits exactly one 100 ms `wait_display_value()`
timeout after the fixed ~155 ms of `sii902x` quiesce
(`src/sii902x.c:748` `msleep(150)` plus the control-bus setup), which ranks
`ddk750_set_display_control(0, false)` at `src/sm750_drm.c:1316` first and
`ddk750_set_logical_disp_out` at `:1346` second; the arithmetic and the rejected
alternatives are in `docs/evidence/runtime/09-hdmi-minus-110.txt` section 5.

The fix is local to the fail path: consume the event and re-enable vblank
accounting before returning, or complete the commit so the core does not wait on
an event the driver will never arm. It must be validated on 0.6.0 with the
instrumentation listed in `docs/evidence/runtime/09-hdmi-minus-110.txt` section
8 - one `drm_dbg_kms` per `sm750_program_mode` stage, and a `regs` snapshot
before and after the failing restore.

Re-produced on 0.6.0 (T11, 2026-11-18). The installed 0.6.0 module hit the same
episode during a plain `kmscube -c 300`, with the same four signatures and the
same stack: `*ERROR* failed to enable HDMI mode: -110` at `[2889.882009]`, the
`drm_atomic_helper.c:2758` WARNING whose call trace runs
`drm_release -> __fput -> task_work_run -> do_exit`, three `flip_done timed out`
/ `commit wait timed out` pairs for CRTC 38, PLANE 36 and CONNECTOR 35, and one
`refcount_t: underflow; use-after-free.` from `drm_fb_helper_damage_work`
through `drm_fbdev_shmem_helper_fb_dirty`. Full transcript:
`docs/evidence/runtime/18-kernel-log-0.6.0.txt`, raw window
`/mega/tmp/sm750/t11/minus110-full.txt`. Two things this adds: the defect is
present in 0.6.0 as well, so it is not a regression from T5/T9/T13; and the
display survived it again (CRTC 38 still at 1920x1080, module refcnt 0, kmscube
still reported 299 frames), so the damage is to the commit path and the refcount,
not to the output. T16 owns the diagnosis; the `-110` producer is still unnamed
and the `regs` snapshot now available (`docs/evidence/runtime/08-register-dump.txt`)
is the tool the closing plan in GAP-B8 needs.

Fixed in T20 (2026-11-18). The fix is at the shared `fail:` label, so it covers
all three abandoned paths at once: the two `goto fail` sites at
`src/sm750_drm.c:3059` (`sm750_dither_scale_map_init`) and `:3087`
(`sm750_scanout_offset`), and the fallthrough after a failed
`sm750_program_mode`. The label now ends with the same two calls the success
path makes, `drm_crtc_vblank_on(&pipe->crtc)` (`src/sm750_drm.c:3131`) and
`sm750_arm_vblank_event(pipe)` (`:3132`), after the staging reset and the
`drm_err`. Those are the right calls rather than a bespoke event drop because
`commit_tail` has already swapped the state in, so `pipe->crtc.state` is the
very state whose `event` `drm_atomic_helper_commit_hw_done` inspects;
`sm750_arm_vblank_event` (`src/sm750_drm.c:2952-2968`) takes the event under
`dev->event_lock`, clears `state->event`, and then either arms it with
`drm_crtc_arm_vblank_event` or, when `drm_crtc_vblank_get` fails, sends it
immediately - so the event is consumed on both branches and the commit
completes. The success path at `:3101-3102` is unchanged. The fail message now
carries a `(commit finished, event consumed)` suffix, which is what makes the
fixed build identifiable at run time.

A static gate keeps the label terminal: `tests/check-drm-policy.sh` extracts
the fail block with `awk` and fails if either call is missing or if the block
contains a bare `return;`. It lives inside an existing check rather than as a
new recipe line, so `make check` still runs 17 commands (A23). Verified RED on
the pre-fix source (`A27: abandoned modeset path lacks:
drm_crtc_vblank_on(&pipe->crtc);`, exit 1) and GREEN after (`DRM mode policy
checks passed`, exit 0).

Post-fix reproduction, 108 attempts of the trigger shape (SIGINT a kmscube
300 ms into its first commit, then `modetest -s 35@38:1024x768-60`, then restore
1920x1080), all on the installed fixed module (srcversion
`07E8F503FC7D839EEC5EE64`): zero `drm_atomic_helper.c:2758` WARNING, zero
`flip_done timed out`, zero `commit wait timed out`, zero `refcount_t:
underflow`, and every attempt ended `connected/enabled/On`. The `-110` itself
still occurred - five times, in attempts 76, 78, 79 and 82 - and each time the
log shows the fail path followed only by normal re-enables, so the trigger is
unchanged while the cascade is gone. A whole-boot audit puts all nine A27
markers before the module reload (`t=2889.882` to `t=2920.433`, the pre-fix
capture) and none after it. Evidence:
`docs/evidence/runtime/17-a27-fix-build.txt`,
`docs/evidence/runtime/18-a27-fix-install.txt`,
`docs/evidence/runtime/19-a27-fix-reproduce.txt`.

GAP-B8 is still open: the fix makes the driver survive a `-110`, it does not
identify which of the five fallible calls produces one. Closing that needs the
per-stage `drm_dbg_kms` instrumentation this section already asks for.

### A28 - static analysis: residual smatch macro false positives and the absent BTF (accepted)

T19 put `src/` through sparse 0.6.4, smatch 1.73, cppcheck 2.19.1, coccinelle
1.3 and pahole 1.32. Full triage: [STATIC-ANALYSIS.md](STATIC-ANALYSIS.md);
raw output `docs/evidence/builds/20-static-sparse.log` to
`25-static-gate.log`. Three groups of findings remain, none of them a driver
defect, so all three are accepted and pinned in the gate baseline
(`tests/static/baseline/`) rather than fixed.

*smatch `shift has higher precedence than mask`, five lines on 7.3.4 and three
on 6.17.1.* The expression is `DMA_BIT_MASK(31)` at `src/sm750_drm.c:1651` and
`:1663`, `GENMASK_ULL(22, 0)` at `:1665`, `GENMASK_ULL(22, 2)` at `:1673` and
`~SII902X_PWR_STATE_MASK` (`GENMASK(1, 0)`, `src/sii902x.c:28`) at
`src/sii902x.c:741`. The operator mix is inside the kernel header:
`GENMASK_TYPE()` at `include/linux/bits.h:52` is
`((t)(GENMASK_INPUT_CHECK(h, l) + (type_max(t) << (l) & type_max(t) >> (BITS_PER_TYPE(t) - 1 - (h)))))`
and `DMA_BIT_MASK(n)` is `GENMASK_ULL((n) - 1, 0)`
(`include/linux/dma-mapping.h:126`). The outer cast and parentheses make the
value correct; smatch's check does not model the cast. A five-line out-of-tree
probe (`u64 f(u64 a) { return a & DMA_BIT_MASK(31); }`) reproduces the warning
with no driver code involved, which is what separates this from a real
precedence bug. Editing the header is out of scope and rewriting correct driver
expressions to silence a checker would obscure them.

*The 6.17.1 run also reports 18 lines inside the kernel tree's own
`include/linux/fortify-string.h`* (lines 497, 597, 599, 724, 726). The gate only
accepts findings whose file is a driver basename, so they are excluded
structurally, not by a suppression that could later hide a driver finding.

*pahole reports no `.BTF` section in `src/sm750hdmidrm.ko`.* kbuild prints
`Skipping BTF generation for sm750hdmidrm.ko due to unavailability of vmlinux`:
an out-of-tree module needs a `vmlinux` with BTF for the target tree, and this
host has no `/boot/vmlinux*`. Not a driver property, and DWARF is present, so
`pahole -C` still reports every layout: `sm750_drm_device` is 9752 bytes with 8
alignment holes totalling 29 bytes, `mode_parameter` 112 with 8 bytes of holes,
and the rest are 1 to 5 byte alignment gaps in per-device structs. Nothing
cacheline-scale, nothing on a per-frame path.

Also recorded here because it is the only finding the triage fixed: sparse
reported four `symbol ... was not declared. Should it be static?` warnings for
the `sm750_test_*` module-parameter backing stores at `src/sm750_drm.c:135-138`.
They must stay non-static (read from `src/ddk750_mode.c` and `src/sii902x.c`),
so the fix is the missing declaration, now at `src/ddk750_chip.h:15-24`, with
the three ad-hoc `extern` lines in `src/ddk750_mode.c` and the one in
`src/sii902x.c` removed. No behaviour change; sparse is clean on both trees
afterwards.

## Evidence handling

`docs/plan/` and `docs/evidence/` are development-only: they are tracked in git
but never shipped. Both are declared in `packaging/source-excludes.sh`, the
single list `build-package.sh` and `tests/audit-release.sh` read (defect A29),
so `tests/audit-release.sh` fails if either appears in the source archive. The
logs in `docs/evidence/` contain absolute host paths that the release scan
rejects by design, which is why they cannot ship even though they are tracked.
The release documents added here (`docs/DEFECTS.md`, `docs/REGISTERS.md`,
`README.md`, `docs/PARAMETERS.md`, `docs/RELEASE-NOTES.md`) were verified to
pass `build-package.sh` plus `tests/audit-release.sh` while tracked.

## Out of scope diagnostics

No warning or error originates in `src/*.c` or `src/*.h` in any archived build
log; the scan and the exact residual kernel/tooling messages are recorded in
`docs/evidence/builds/11-warnings-scan.log`:

- `warning: pahole version differs from the one used to build the kernel` -
  emitted by `/usr/src/kernels/*/Makefile` because pahole is not installed
  (`You are using: 0`); BTF generation is skipped as a result.
- `warning: the compiler differs from the one used to build the kernel`
  (6.17.1-300.fc43 only) - the archived Fedora kernel was built by gcc 15.2.1
  and this host has 15.3.1; not fixable without the upstream compiler.
- `Skipping BTF generation for sm750hdmidrm.ko due to unavailability of
  vmlinux` - informational; the kernel tree ships no vmlinux.
