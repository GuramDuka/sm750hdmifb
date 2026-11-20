<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Defect dispositions

One row per defect inventoried in [AUDIT.md](AUDIT.md), plus eight found later:
`A25`, in the kernel log of the running 0.5.9 build, `A26`, in the IGT
`kms_addfb_basic` run, `A27`, isolated by a targeted reproduction of the
same 0.5.9 kernel log episode, `A28`, by the static-analysis gate added in
T19, `A29`, by the release gate itself, `A30`, by the acceptance review of
that same static gate, `A32`, by the root restore-path run of T20 and the
RCA that followed, and `A33`, by the coverage review of the stale-DKMS purge
in T36. They are recorded here because this
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
| A18 | S3 | CI only ran on `workflow_dispatch` | fixed | `docs/ci/build.yml:15-17` (`push`, `pull_request`); the recipe is inactive since 2026-11-18, see `docs/ENVIRONMENT.md` 1.3 | `10` |
| A19 | S3 | `make check` never built or audited a package | fixed | `Makefile:71-74` (`check-package`); CI step at `docs/ci/build.yml:58` | `07`, `08`, `10` |
| A20 | S3 | DKMS auto-installs on kernels the release notes call untested | accepted | rationale now at `docs/RELEASE-NOTES.md:69-80` and `:95-100`; no change to `dkms.conf:7-8`. The 0.6.0 notes replace the blanket statement with an explicit coverage list (built 6.17-7.4, loaded on 7.3.4-100), so the risk that remains is limited to kernels newer than the last validated one, where a failed build only means no module for that kernel | `10` |
| A21 | S3 | No committed evidence for the claimed kernel matrix | fixed | `docs/evidence/builds/01`-`11` (this task's logs; T4 cites them) | `02`-`06`, `11` |
| A22 | S4 | Source tarball carried about 9 MB of screenshots | fixed | same fix as A02; `docs/images` excluded from the manifest (`build-package.sh:98`) | `07`, `10` |
| A23 | S4 | Planning note said 18 `make check` commands; it runs 17 | fixed | `docs/plan/20261117-sm750-driver-prod/plan.yaml:28` (corrected), count re-verified in `01-make-check.log` | `01`, `10` |
| A24 | S4 | fbdev compiled in but never appears and was not documented | accepted | behaviour and conditions documented at `README.md:307-313` | `10` |
| A25 | S3 | Found post-audit in the kernel log, not by the audit: `[PLANE:40:sm750-cursor] pixel format with alpha exposed but blend mode not setup. Please fix.` The cursor plane exposed `DRM_FORMAT_ARGB8888` with no blend-mode property, so the DRM core could not tell how the driver expresses alpha | fixed | `src/sm750_drm.c:3491` (`drm_plane_create_blend_mode_property()` offering `BIT(DRM_MODE_BLEND_PREMULTI)`); format list unchanged at `src/sm750_drm.c:3424`; gate `tests/check-hardware-cursor.sh:32-33` plus the negative assertion at `:43-45`; verified fixed on the installed module by T11 - the warning is absent from both 0.6.0 probes while the single boot-time occurrence (t=3.68 s, the 0.5.9 probe) remains, and `modetest -p` shows property `42 pixel blend mode` with `Pre-multiplied=0` on cursor plane 40 | `docs/evidence/runtime/cursor-alpha-01-warning-before.txt`, `docs/evidence/builds/19-cursor-alpha-fix.log`, `docs/evidence/runtime/13-module-reload.txt`, `docs/evidence/runtime/18-kernel-log-0.6.0.txt` |
| A26 | S4 | IGT `kms_addfb_basic --run-subtest size-max` fails with `DRM_IOCTL_MODE_ADDFB2` EINVAL. Not a driver defect and not a hardware limit: the subtest issues a `1024x2048` `DRM_FORMAT_RGB565` framebuffer at `tests/kms_addfb_basic.c:594` without a format probe, and the driver exposes only `DRM_FORMAT_XRGB8888` on the primary plane (`src/sm750_drm.c:3423`) with `max_height` declared as 1152 (`src/sm750_drm.c:95`, `:3437`). DRM core rejects it first on height (2048 > 1152) and would reject it again on format. The silicon allows it: DS-1 rev 1.4 p151 `PANEL_FB_WIDTH` permits 16368 bytes of pitch and p153 `PANEL_PLANE_BR` permits a 2048-line window, so the limit is driver policy, not hardware | accepted | no code change recommended; both rejections are generic DRM checks on declared limits, and raising `max_height` alone cannot make the subtest pass because the format gate rejects RGB565 independently. Contract and IGT gap documented in `docs/evidence/runtime/10-addfb-size-max.txt` section 5; unchanged on 0.6.0 (T11) | `docs/evidence/runtime/06-igt.txt:52,68-76,150,161`, `docs/evidence/runtime/10-addfb-size-max.txt`, `docs/evidence/runtime/19-igt-0.6.0.txt` |
| A27 | S3 | A single failed modeset becomes a kernel WARNING plus 30 s of stalled atomic commits, and once a refcount underflow. `sm750_pipe_enable`'s `fail:` label returns `-110` from `sm750_program_mode` without calling `drm_crtc_vblank_on()` and without consuming the commit's vblank event, so `drm_atomic_helper_commit_hw_done` trips `WARN_ON(new_crtc_state->event)` (`drivers/gpu/drm/drm_atomic_helper.c:2758` in 7.3.4), every later commit waits 10 s per atomic object (CRTC 38, CONNECTOR 35, PLANE 36) and a later `drm_release` restore can underflow a refcount in `__drm_atomic_helper_plane_destroy_state` via `drm_gem_simple_kms_destroy_shadow_plane_state` | fixed | trigger isolated by reproduction: SIGINT a kmscube ~300 ms into its first commit, then `modetest -s 35@38:1024x768-60`; the failure lands on the fbdev-restore commit issued from `drm_release`. Measured rate 1/36 (2.8 %) for that shape and 0/169 for every other shape, so the trigger is established and the rate is not; the fail path (`src/sm750_drm.c:3105-3117`, success path `:3101-3102`) is the defect and is independent of the trigger. Which of the five fallible calls in `sm750_program_mode` (`src/sm750_drm.c:1312`, `:1316`, `:1319`, `:1346`, `:1349`) returns `-110` is not identifiable on 0.5.9 (no debug output on that path, no `regs` debugfs); the 330.003 ms gap ranks `ddk750_set_display_control(0, false)` at `src/sm750_drm.c:1316` first (`src/ddk750_display.c:12-26`, `:68-97`, `src/ddk750_mode.c:285-305`). Re-produced on the installed 0.6.0 by T11, which rules out any T5/T9/T13 change as the cause; fixed in T20 by finishing the abandoned commit at the shared `fail:` label - `drm_crtc_vblank_on()` then `sm750_arm_vblank_event()` at `src/sm750_drm.c:3131`/`:3132`, the same two calls the success path makes at `:3101`/`:3102`, so `new_crtc_state->event` is consumed whether the event is armed on the driver timer or sent at once. Static gate: `tests/check-drm-policy.sh:141-167` asserts the fail block contains both calls and has no early `return;` (no new `make check` recipe line, so the count stays 17). Post-fix reproduction: 108/108 attempts with zero WARNING, zero `commit wait timed out` and zero refcount underflow, while the `-110` itself still fired 5 times in the run - the trigger is unchanged, the cascade is gone | `docs/evidence/runtime/09-hdmi-minus-110.txt`, `docs/evidence/runtime/07-kernel-log.txt:50-110`, `docs/evidence/runtime/18-kernel-log-0.6.0.txt`, `docs/evidence/runtime/17-a27-fix-build.txt`, `docs/evidence/runtime/18-a27-fix-install.txt`, `docs/evidence/runtime/19-a27-fix-reproduce.txt` |
| A28 | S4 | Found by static analysis, not by the audit: smatch reports `shift has higher precedence than mask` five times on 7.3.4 and three times on 6.17.1, at `src/sm750_drm.c:1651,1663,1665,1673` and `src/sii902x.c:741`. Not a driver defect and not fixable in the driver: the message is produced by `GENMASK_TYPE()` (`include/linux/bits.h:52`), which mixes `<<` with `&`/`>>` without inner parentheses and is reached through `DMA_BIT_MASK()` (`include/linux/dma-mapping.h:126`) and `GENMASK()`; the enclosing cast and parentheses make the value correct, and smatch's precedence check does not model the cast. A five-line out-of-tree probe reproduces the warning with no driver code. The four fixed sparse findings (`sm750_test_*` globals with no declaration in scope) and the cppcheck `unknownMacro` suppression are also recorded there | accepted | no code change: the driver expressions are correct and the header macro is not ours to edit. The residual findings are pinned in the opt-in gate baseline, so the gate fails on anything new while these stay quiet. Also records that the out-of-tree module has no `.BTF` section (`Skipping BTF generation ... due to unavailability of vmlinux`), so `pahole -F btf` is unavailable and layouts come from DWARF | `docs/STATIC-ANALYSIS.md`, `docs/evidence/builds/20-static-sparse.log` to `25-static-gate.log` |
| A29 | S2 | The packager and the release gate each carried their own copy of the development-only directory list, so they disagreed by construction: `build-package.sh:98-100` shipped the tracked tree minus `docs/images` only, while `tests/audit-release.sh:54-58` failed the archive if `docs/plan`, `docs/evidence` or `docs/images` appeared in it. Once `docs/plan/` and `docs/evidence/` became tracked, every fresh build produced a tarball the gate rejected: `./tests/audit-release.sh` exited 1 with `Source archive contains development-only content: docs/plan` on a 160-file archive that carried 1 `docs/plan` and 69 `docs/evidence` entries. The same divergence had a second consequence: the shipped `docs/ENVIRONMENT.md` named three absolute `$HOME` paths that the audit's own private-path scan rejects, hidden behind the earlier exit | fixed | one list, read by every consumer: `packaging/source-excludes.sh` declares `sm750_dev_only=(docs/plan docs/evidence docs/images)` and `sm750_dev_only_pathspecs()`; `build-package.sh:90-128` sources it for both the `git ls-files` pathspecs and the non-git `--exclude=` arguments; `tests/audit-release.sh:52-80` sources it for the forbidden-directory loop and for the manifest diff; `tests/check-rpm-dkms.sh:70-85` sources it for the DKMS payload. `tests/check-drm-packaging.sh:32-49` asserts all three paths are in the shared file, that both scripts read it, and that neither hard-codes `:(exclude)docs/` again. `docs/ENVIRONMENT.md:41-51` now writes those paths with `~/`. The gate is not narrowed: a tarball rebuilt without the list still fails it | `docs/evidence/builds/26-audit-release.log`, `docs/evidence/builds/27-source-archive-manifest.log` |
| A30 | S3 | The opt-in static gate was non-deterministic: over one unchanged tree, T8's acceptance run got `static gate: PASS` (exit 0) and another got `coccinelle: exit 255` / `spatch failed` (exit 1). The cause is an inherited variable, not the driver and not a patch: spatch's Python bridge locates libpython with `pkg-config --libs python-3.14`, which returns the empty string in a clean shell but `-L/mega/tmp/sm750/t3/libdrm/usr/lib64` once `docs/ENVIRONMENT.md` section 4's `PKG_CONFIG_SYSROOT_DIR` is exported, and spatch then dies with `Py.find_library_path: unable to parse the output of pkg-config ...` before analysing a file | fixed | `tests/check-static.sh:37-46` clears `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_PATH` and `PKG_CONFIG_LIBDIR` next to the existing locale sanitisation (the gate asks pkg-config nothing, so this removes a dependency and not a check); `:216` and `:237` name the patch behind a non-zero spatch exit; `:250` labels a 255 as a fatal spatch exit rather than a finding. No patch, no baseline line and no `src/` file was touched; the `check` recipe is still 17 commands | `docs/evidence/builds/28-static-determinism.log` |
| A32 | S3 | The fbdev reconsole restore path could fail with `-ETIMEDOUT` and leave the panel blank. When the last userspace DRM client closed the node, `drm_fbdev_client_restore` submitted the fbcon restore commit; `commit_tail` ran `sm750_pipe_disable()` (which discarded the result of `ddk750_set_display_control(..., false)`) and then `sm750_pipe_enable()` -> `sm750_program_mode()`, whose display-control transition wait returned `-ETIMEDOUT`. Both waits compared the whole `PANEL_DISPLAY_CTRL` snapshot minus a reserved mask, so bits the hardware rewrites mid-transition (live VSYNC, FIFO request, pan, phase, gamma, format) could make a latched transition look unlatched; the mode loop additionally capped itself at 1000 iterations of `udelay(10)` (under one 60 Hz frame) and re-poked a stale snapshot. A27 had already removed the WARNING, the 10 s stalls and the refcount underflow that followed, so what remained was the failure itself and an invisible disable half | fixed; confirmed on hardware 2026-11-20 | masked compare plus re-poke: `wait_display_bits()` (`src/ddk750_display.c:14-45`) compares only `DISPLAY_CTRL_TIMING | DISPLAY_CTRL_PLANE` (`src/ddk750_reg.h:561`, `:567`) and rewrites the control value on every poll, keeping the 100 ms budget and logging `want`/`mask`/`last` on timeout; `program_mode_registers()` (`src/ddk750_mode.c:299-318`) uses the same mask and re-poke with `budget_us = max(20000, 2 * 1000000 / mode_param->vertical_frequency)` instead of `cnt > 1000`; `sm750_pipe_disable()` (`src/sm750_drm.c:3648-3652`) keeps the display-off result and warns with the `PANEL_DISPLAY_CTRL` readback, and the `sm750_pipe_enable()` fail path (`:3549-3562`) keeps A27 byte-for-byte and adds one `enable-fail state:` line with `PANEL_DISPLAY_CTRL`, `PANEL_PLL_CTRL`, `SYSTEM_CTRL` and `PANEL_CURRENT_LINE`. Gates: `tests/check-restore-path.sh` (four structural properties, four planted defects, part of `make check` through `tests/check-drm-policy.sh`) and `tools/sm750-restore-cycle.sh` (root stress harness, exit 0/1/2/3). Confirmed on hardware 2026-11-20 on the module built from this tree (srcversion `14ED4F27A83A6BB8AA445D2`, kernel 7.3.4-100.fc43): the CRC cycle passed all six assertions, 30 consecutive client exit/restore cycles succeeded 30/30, 20 mode changes (`modetest -s 35@38:1024x768`) completed 20/20, 95 enable events ran across two geometries (75 at 1920x1080, 20 at 1024x768), and a `grep -cE` over the whole session's dmesg for `failed to enable HDMI mode\|flip_done timed out\|commit wait timed out\|refcount_t: underflow\|did not latch\|panel did not acknowledge\|enable-fail state\|WARNING\|BUG:` returned 0. The same run recorded S10 passing for real under `KD_TEXT` (`offset` 0 = `PANEL_FB_ADDRESS` 0x00000000, `nonzero` 28766, `crc32` 0x0204dd04). Remaining uncertainty: single card and single panel; the 50 cycles were driven manually through the allowlisted sudo entries because `tools/sm750-restore-cycle.sh` refuses to run as non-root (`:73`), so its 120-iteration form is still unexercised. Absence of a fault line over 95 enable events lowers the rate, it does not prove impossibility | `docs/evidence/runtime/20-fbdev-restore-timeout-rca.txt`, `docs/evidence/runtime/21-fbdev-restore-fix.txt`, `docs/evidence/runtime/22-restore-fix-hardware-proof.txt` |
| A33 | S4 | Observation, not a defect, found by the coverage review in T36: the `%posttrans` stale-registration purge carries a fallback branch that no test exercised. `packaging/sm750hdmifb.spec:227-228` runs `dkms remove -m %{dkms_name} -v "$stale_version" --all || echo "warning: dkms remove %{dkms_name}/$stale_version failed; remove it by hand" >&2`, but the dkms shim in `tests/check-rpm-dkms.sh` always ended in `exit 0`, so the property "a failed removal is a warning, the loop continues, the transaction survives" was asserted only by reading the source. The exit-code split that makes the branch reachable was measured on this host with `dkms` 3.4.4 against a scratch tree: a registration whose `source` symlink dangles gives `Error! sm750hdmifb/0.6.0 is broken!` / `Missing the source directory or the symbolic link pointing to it:` / `Manual intervention is required!` and exit **4**, while a source directory with no `dkms.conf` and no installed module gives `Deleting module sm750hdmifb/0.6.0 completely from the DKMS tree.` and exit **0**. The single real occurrence on this host was host state and not packaging: `/usr/src/sm750hdmifb-0.6.0` was a git checkout of the repository, so its registration pointed at a directory no RPM owned and `%posttrans` had no tree to remove | closed; no code change (test coverage added) | no driver, spec or scriptlet logic changed. `tests/check-rpm-dkms.sh:364-384` teaches the shim `SHIM_FAIL_REMOVE=<version>`, which logs the call first and then fails `dkms remove ... -v <version> --all` with the real dkms error text and exit 4; `:468-505` runs the purge with `SHIM_FAIL_REMOVE=0.5.9` (the first version the loop meets) and asserts exit 0, the exact spec warning, that 0.6.0 is still removed afterwards, that `%{dkms_version}` is never removed, and that no build or install ran. The evidence log gained a labelled failed-removal section; `docs/PACKAGING-RPM.md` section 4 gained "When a removal fails (exit-code semantics)" | `docs/evidence/packaging/06-posttrans-missing-headers.log` |

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

### A30 - the static gate flipped between PASS and a coccinelle failure (fixed)

T8's acceptance review ran `make static` twice over the same tree and got
different answers: `static gate: PASS` with exit 0 once, and
`coccinelle: exit 255` / `spatch failed` with exit 1 the other time. Every
other analyser agreed in both runs (sparse 0, smatch 5, cppcheck 0, pahole 0),
so the disagreement was confined to spatch.

Reproduction and cause are in
[`docs/evidence/builds/28-static-determinism.log`](evidence/builds/28-static-determinism.log);
the short form is that the gate inherited `docs/ENVIRONMENT.md` section 4's
`PKG_CONFIG_SYSROOT_DIR`. spatch's Python bridge resolves libpython by running
`pkg-config --libs python-3.14`; in a clean shell that prints nothing and
spatch continues, but with the sysroot exported it prints
`-L/mega/tmp/sm750/t3/libdrm/usr/lib64` and spatch exits 255 while printing,
verbatim,

```
Py.find_library_path: unable to parse the output of pkg-config '-L/mega/tmp/sm750/t3/libdrm/usr/lib64'
```

before analysing any file (that invocation has no `HANDLING:` line). All twelve
patches, the three local ones and the nine kernel ones, fail that way and all
twelve exit 0 with the variables cleared, so the flip was never patch-specific.
A shell that had just built a libdrm client failed the gate; a fresh shell
passed.

The fix is `tests/check-static.sh:37-46`, which clears `PKG_CONFIG_SYSROOT_DIR`,
`PKG_CONFIG_PATH` and `PKG_CONFIG_LIBDIR` beside the existing locale
sanitisation. The gate does not use pkg-config for anything else, so this
removes a dependency instead of a check: all twelve patches stay, and
`tests/static/baseline/` still holds 0 sparse, 0 cppcheck, 0 coccinelle and 4
smatch lines. A non-zero spatch exit still fails the run, and now names the
patch (`tests/check-static.sh:216`, `:237`) and distinguishes a 255, spatch's
fatal status, from a finding count (`:250`). Ten consecutive runs over an
unchanged tree in the environment that used to fail return exit 0 ten times; a
planted defect is still caught by sparse and by smatch; and a deliberately
corrupted patch still fails the gate and is attributed to the file. The `check`
recipe is untouched at 17 commands, so the gate stays opt-in via `make static`.

Residual limitation: 255 is spatch's generic fatal status and also covers a
`.cocci` that does not parse, so the exit code alone does not name the cause.
The raw log does, and the gate prints which patch produced it; it does not
assert that spatch can never fail for a reason other than these.

### A31 - black panel misdiagnosed as a display-path regression (accepted, diagnosed)

A multi-hour investigation read a black SM750 HDMI panel as a fault in the
driver's display path: the module loaded, the modeset reported success, and the
panel showed nothing. No driver code was at fault.

Observation: after a module load the in-kernel fbdev client registered by
`drm_client_setup()` (`src/sm750_drm.c:4305`) scans out an all-zero frame, and
`/sys/kernel/debug/dri/N/sm750_scanout` reported `nonzero 0` with
`crc32 0xe20eea22`.

Proof, three independent measurements:

- `crc32 0xe20eea22` is exactly `zlib.crc32()` of 262144 zero bytes, so the
  sampled window was arithmetically blank, not merely dark:
  `python3 -c 'import zlib; print(hex(zlib.crc32(bytes(262144))))'` prints
  `0xe20eea22`.
- `KDGETMODE` (ioctl `0x4B3B`) on `/dev/tty0` returned 1, `KD_GRAPHICS`, while
  `/sys/class/tty/tty0/active` read `tty1` and a Wayland session owned it:
  `python3 -c 'import fcntl,struct; f=open("/dev/tty0","rb"); print(struct.unpack("i", fcntl.ioctl(f.fileno(), 0x4B3B, struct.pack("i", 0)))[0])'`.
- A userspace DRM client's full-screen white frame displayed correctly
  (`docs/evidence/scanout/09-crc-single-owner.txt` section 5: white
  `0x06cf606c`, 262144 of 262144 nonzero bytes), so the path from VRAM to the
  panel was intact.

Conclusion: fbcon only paints while the foreground VT is in `KD_TEXT`;
`do_con_write()` in `drivers/tty/vt/vt.c` drops console output before fbcon when
`vc_mode != KD_TEXT`. On a graphical VT the fbdev client's buffer is therefore
born blank, the shadow path uploads the zeros faithfully, and the panel scans
them. This also corrects the earlier claim that the fbdev client is "inert
because `CONFIG_FB_DEVICE` is unset": that option removes `/dev/fbN`, not
fbcon, and the kernel log does register `fb0`. The remaining delay before the
first real frame is the console client's, not the driver's.

Disposition: accepted, with the precondition now named instead of silent. The
driver samples the frame it is about to commit
(`sm750_shadow_frame_is_blank()`, `src/sm750_drm.c:3404-3431`) and, at most once
per module load, logs one `drm_info` line from `sm750_pipe_enable()` after
`sm750_program_mode()` succeeded:
`console framebuffer is blank: the panel now scans a frame nobody has painted
(is the foreground VT in KD_TEXT?)`. Nothing else changes: no upload is
skipped, no stale frame is kept, no commit fails.

Two gates prevent recurrence as a misdiagnosis: `tests/check-console-blank.sh`
(source level, part of `make check` through `tests/check-drm-policy.sh`) holds
the helper, the exact text, the ordering after the mode is programmed and the
once-per-load latch, and rejects four planted defects; and
`tests/check-console-scanout.sh` (`make console-check`, root only) tells the two
console states apart on the card, skipping with a named cause under
`KD_GRAPHICS` and otherwise requiring content, a `crc32` other than the
all-zero sentinel and an `offset` equal to `PANEL_FB_ADDRESS`. Evidence:
`docs/evidence/runtime/19-console-blank-diagnosis.txt`.

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
