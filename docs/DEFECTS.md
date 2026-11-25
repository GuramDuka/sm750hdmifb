<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Defect dispositions

One row per defect inventoried in [AUDIT.md](AUDIT.md), plus nineteen found
later:
`A25`, in the kernel log of the running 0.5.9 build, `A26`, in the IGT
`kms_addfb_basic` run, `A27`, isolated by a targeted reproduction of the
same 0.5.9 kernel log episode, `A28`, by the static-analysis gate added in
T19, `A29`, by the release gate itself, `A30`, by the acceptance review of
that same static gate, `A32`, by the root restore-path run of T20 and the
RCA that followed, `A33`, by the coverage review of the stale-DKMS purge
in T36, `A34`, by the black-panel diagnosis of A31 in T37, `A35`, by
running the release audit of T37, and `A37`, `A38` and `A39`, by a real
package upgrade of 0.6.2-1 on the target host in T41 (the module was not
installed; the transcript is `docs/evidence/runtime/27-posttrans-install-failure.txt`),
and `A40`, by the T42 review of that same host state: the three
`/var/lib/dkms/sm750hdmifb/kernel-<kernel>-x86_64` links still pointed at the
erased 0.6.1 version, and that alone was enough to abort the install
(`docs/evidence/runtime/28-dangling-kernel-link.txt`), and `A41`, by the T44
adjudication of the long-open R3 question, which found it is not a defect
(`docs/evidence/runtime/29-scanout-offset-reset-rca.txt`), and `A42`, by the
0.6.3 readiness review of the target host's kernel log after a monitor power
cycle (`docs/evidence/runtime/30-sii9024a-readiness-and-timeout.txt`), and
`A43` and `A44`, by the T56 headless-compositor work and the vblank
investigation that unblocked `make check`
(`docs/evidence/runtime/35-kmscube-exit-semantics.txt`,
`docs/evidence/runtime/34-vblank-idle-freeze.txt`), and `A45`, by the T57
render-node work, which delivered the node and observed it live on the host
(`docs/evidence/runtime/36-render-node.txt`), and `A46`, by the 0.6.6
scanout readback window work (`docs/evidence/runtime/37-plasma-wayland.txt`
records the 256 KiB / 68-scanline limit it removes).
They are
recorded here because this
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
| A34 | S4 | A module load on a foreground VT in `KD_GRAPHICS` leaves the panel scanning the fbdev client's all-zero buffer (A31), so a host with no console producer shows a dead-black panel between load and the first client frame, and indefinitely when no client ever attaches. The symptom is indistinguishable from a broken display path without a register dump | fixed; opt-out available | bounded fallback, `test_pattern` (default `auto`, `off`/`auto`/`always`, mode 0644, `src/sm750_drm.c:243`, `:289-290`), `test_pattern_period_ms` (default `5000`, `src/sm750_drm.c:244`, `:290`, `:292-293`) and `test_pattern_anim_ms` (default `40`, `0` stops the disc, clamped 10-1000, `src/sm750_drm.c:245`, `:291`, `:296-297`). `sm750_test_pattern_pixel()` (`src/sm750_drm.c:3574-3615`) computes any background pixel from x, y and the palette phase: seven EBU bars plus a black right bar over the top two thirds, an 8-step grayscale band, a 16x12 grid, a centred crosshair and circle, a 1 px inset border and a 3 px sweep. `sm750_test_pattern_rect()` (`src/sm750_drm.c:3641-3686`) writes any rectangle through one probe-time line buffer, padded to `scanout_pitch` and copied with `memcpy_toio()` (`:3668`, `:3671`, `:3676`); the full card and an animation tick both go through it. The disc is `sm750_test_pattern_disc_pixel()` (`:3617-3639`), moved by `sm750_test_pattern_disc_move()` (`:3770-3818`) with reflection off the inner border and a colour change per bounce, so a 25 fps tick writes only two bounding boxes (`sm750_test_pattern_disc_tick()`, `:3821-3850`). Encoding: `u16` RGB565 or `u32` 0x00RRGGBB (`sm750_test_pattern_put()`, `:3554-3572`). Guards, all in `sm750_test_pattern_ctx_init()`: `softscale_active` (`:3700`), missing pitch or buffers (`:3696`), below 320x200 (`:3702`), pitch outside the line buffer (`:3704`), and the frame not fitting `vram_size - scanout_offset` (`:3706`). The paint runs in the `sm750_pipe_enable()` success block after the blank diagnostic and before `drm_crtc_vblank_on()` (`:4077-4104`), from the single `blank` sample shared with A31; the buffers are `devm_kmalloc_array` at probe (`:4774-4788`). The one `delayed_work` (`sm750_test_pattern_work()`, `:3901-3959`) moves the disc every `test_pattern_anim_ms` and rotates the palette once per `test_pattern_period_ms`, and is cancelled in `sm750_pipe_disable()` (`:4226`), in `sm750_pipe_update()` before any upload (`:4184`), on the enable fail path (`:4112`) and in `sm750_pci_remove()` (`:4970`); the commit that painted the card skips its own upload through `test_pattern_fresh` (`:4174`). Both snapshots are invalidated after every paint (`:3682-3683`). Seen on the panel 2026-11-20: colour bars, with the palette jump every 5 s; the animated disc is not yet observed | `docs/evidence/runtime/23-test-card-fallback.txt`, `docs/evidence/runtime/25-test-card-animation.txt` |
| A35 | S2 | The 0.6.1 tree could not pass its own release gate: `tools/sm750-restore-cycle.sh:36` embedded an absolute home path as `REPO=${HOME}/sm750hdmifb`, and `tests/audit-release.sh:98` rejects a literal local path in anything that ships (the harness is under `tools/`, which `packaging/source-excludes.sh` does not exclude). `./build-package.sh` exit 0 but `./tests/audit-release.sh` exit 1 with `Local path, machine identifier, or credential pattern remains.`, reproduced in a clean `git worktree` of HEAD 1f74688 with no working-tree changes, so the defect predates T37 | fixed | `tools/sm750-restore-cycle.sh:36-41` now resolves the checkout the way the sibling helper already does: `OWNER=coder`, `owner_home=$(getent passwd "$OWNER" | cut -d: -f6 || true)`, `REPO=${SM750_REPO:-${owner_home:-}/sm750hdmifb}` (the idiom documented at `tools/sm750-crc-cycle.sh:21-26`). No gate was weakened; the audit check is unchanged. Behaviour is unchanged for the intended root user and `SM750_REPO` still overrides | `docs/evidence/runtime/23-test-card-fallback.txt` (section 9) |
| A36 | S2 | The test card corrupted the scanout CRC stream: `tests/check-scanout-crc.sh` failed with `FAIL: CRC is not stable for a static frame: 3 distinct values in 12 frames` because the `test_pattern_fresh` flag introduced in T37 was consumed one commit too late. With the driver's default commit tail, `drm_atomic_helper_commit_tail()` runs `commit_planes()` before `commit_modeset_enables()` (`drm_atomic_helper.c:1984-2003`; `src/sm750_drm.c` sets only `.atomic_commit`), so `sm750_pipe_enable()` set the flag after the enabling commit's own `sm750_pipe_update()` had already run. The flag therefore skipped the *client's* first present - the opposite of what the comment claimed - and its `goto event` also skipped the `sm750_test_pattern_cancel()` below it, so the 5 s palette rotation kept rewriting the 262144-byte window that `sm750_scanout_crc32()` reads in 256-byte chunks, and one entry straddling a repaint returned a torn value | fixed; CRC conflict closed | `src/sm750_drm.c:3972-3990` (`sm750_test_pattern_should_paint()` now takes the device, returns false first when `READ_ONCE(sdev->crc_enabled)`, and requires `!READ_ONCE(sdev->drm.master) && blank`); `sm750_crc_enable()` cancels the card before `sm750_crc_arm()` (`sm750_drm.c` CRC ownership block, forward declaration above `sm750_crc_enable()`); the work tick re-checks `!READ_ONCE(sdev->crc_enabled)` under `mode_lock`; the `test_pattern_fresh` field and every use removed; `sm750_pipe_update()` keeps the cancel as its first test-card action. `tests/check-test-pattern.sh` gained `check_crc_ownership()` plus five planted controls (18 total) | `docs/evidence/runtime/24-test-card-crc-conflict-rca.txt`, `docs/evidence/runtime/26-test-card-crc-fix.txt` |
| A37 | S2 | The 0.6.2-1 package installed but installed no module. The transaction printed `Error! Could not locate dkms.conf file.` / `File: /var/lib/dkms/sm750hdmifb/0.6.1/source/dkms.conf does not exist.` / `warning: dkms install failed for 7.3.4-100.fc43.x86_64; run it manually` for every installed kernel, then `warning: no supported installed kernel has usable headers; the module was not built` (false: the headers were present), and `cat /sys/module/sm750hdmidrm/version` still printed `0.6.1`, so the freshly built module never reached `/lib/modules`. Mechanism: `%posttrans` ran the build+install loop before the stale-registration purge, and `dkms install -m sm750hdmifb -v 0.6.2 -k <kernel> --force` first uninstalls the older registered version for that kernel; the 0.6.1 registration was broken because rpm had erased the 0.6.1 package's files, so `/var/lib/dkms/sm750hdmifb/0.6.1/source` dangled, dkms exited non-zero and installed nothing, and the purge that would have cleared the entry ran afterwards - after the step it exists to protect. The load-bearing property is the order: a purge after the install cannot unblock the install | fixed | purge moved ahead of the build loop with the ordering rationale inline (`packaging/sm750hdmifb.spec:146-227` purge, `:230` build loop); the failed-removal branch escalates once and deletes a demonstrably broken registration tree after `warning: removing broken DKMS registration tree: <path>` (`packaging/sm750hdmifb.spec:221-226`), which is what dkms itself instructs (`If this module version is no longer needed, you can remove the stale directory.`); `$stale_version` is skipped before it can reach a path if it is empty, contains `/`, is `.` or `..`, or carries a byte outside `[0-9A-Za-z._-]` (`:198`, `:207-212`); `dkms_root=${SM750_RPM_DKMS_ROOT:-/var/lib/dkms}` lets the test point the tree at a sandbox (`:139-144`); the zero-build warning no longer claims headers are the reason (`:257`). Guards: `tests/check-rpm-dkms.sh:639-651` (`purge_before_build()`, line numbers taken from the extracted scriptlet), `:532-580` (`broken_scenario()`), `:582-616` (`unsafe_scenario()`), plus the planted controls at `:680-715` | `docs/evidence/runtime/27-posttrans-install-failure.txt`, `docs/evidence/packaging/06-posttrans-missing-headers.log` |
| A38 | S3 | Every `dkms add` printed `Deprecated feature: CLEAN (/var/lib/dkms/sm750hdmifb/0.6.2/source/dkms.conf)`, and `docs/PACKAGING-RPM.md` told the reader it was expected and harmless. The directive had no effect at all: dkms 3.4.4 contains one occurrence of `CLEAN` in the whole script (`/usr/sbin/dkms:582-585`) and it exists only to emit that warning, so the configured clean command was never run | fixed | `CLEAN="make KDIR=${kernel_source_dir} clean"` deleted from `dkms.conf` (the file now ends at `MAKE[0]`, `dkms.conf:9`); `docs/PACKAGING-RPM.md` section 8 replaces the "expected, harmless" paragraph with the reason the warning is gone and the rule that no shipped directive may produce one. Guard: `tests/check-rpm-dkms.sh:618-626` (`no_deprecated_directive()`, applied to the working tree and to the payload extracted from the built RPM) plus the `plant_clean_directive` control at `:697-699`, `:709` | `docs/evidence/packaging/06-posttrans-missing-headers.log` |
| A39 | S3 | `tools/sm750-console.sh show` printed `(crc32 0xe20eea22 is 262144 zero bytes: nothing has painted the window)` unconditionally, including on a frame that was not zero: observed with the test card on screen as `scanout nonzero: 200323`, `scanout crc32: 0x3972ef44` followed by that zero-frame hint, which points an operator at the wrong cause. The line was a fact about one CRC value, not about the frame that had just been read | fixed | the helper captures the field once and prints the hint only when the read CRC is exactly `0xe20eea22`; otherwise it prints `(crc32 0xe20eea22 is 262144 zero bytes; this frame is not it)` (`tools/sm750-console.sh:102-107`). Every other output field is byte-identical, the script is still POSIX sh. Guard: `tests/check-rpm-dkms.sh:628-637` (`hint_is_conditional()`) plus the `plant_unconditional_hint` control at `:700-704`, `:711` | `docs/evidence/runtime/27-posttrans-install-failure.txt` (section 2) |
| A40 | S2 | A dangling DKMS active-version link still aborted the install after A37's ordering fix: on the host, `/var/lib/dkms/sm750hdmifb/kernel-7.2.15-100.fc43.x86_64-x86_64`, `kernel-7.3.3-100.fc43.x86_64-x86_64` and `kernel-7.3.4-100.fc43.x86_64-x86_64` each pointed at `0.6.1/<kernel>/x86_64`, a version rpm had erased. Mechanism, read from dkms 3.4.4 `/usr/sbin/dkms`: `do_install()` at `:1768` computes `active_link=...` at `:1778` and `active_link="$dkms_tree/$module/kernel-$kernelver-$arch"`, `:1783-1784` reads `old_active_version=$(readlink "$active_link")` and keeps only the first path component, so it takes `0.6.1` from the link target without checking that the version is still registered or still on disk, and `:1866-1868` runs `(module_version="$old_active_version" delayed_depmod=1 do_uninstall ...) || die 6 "Failed to uninstall ..."`. `do_uninstall` needs `$dkms_tree/$module/$module_version/source/dkms.conf`, which is gone, so the install dies per kernel while `dkms status -m sm750hdmifb` lists only `0.6.2, <kernel>, x86_64: built`. A dangling link is not a registration, so the version-driven purge of A37 never saw it | fixed; host-verified for 0.6.2-3 | a second loop after the version purge and before the build loop (`packaging/sm750hdmifb.spec:231-251`, loop at `:245-251`) iterates `"$dkms_root/%{dkms_name}"/kernel-*`, skips anything that is not a symlink, and removes a link with `rm -f -- "$dkms_link"` plus `removing dangling DKMS kernel link: <path>` on stderr only when `[ ! -d "$dkms_link/" ]` says it does not resolve; a resolving link, a non-symlink of that name and every path outside the module directory are never touched, and every expansion is quoted. Releases 0.6.2-3. Guards: `tests/check-rpm-dkms.sh:230-252` (marker present in the extracted `%posttrans` and the spec, its line after the version purge and before the build loop, `rm -f -- \"$dkms_link\"` present), `:644-691` (`dangling_link_scenario()`, fake dkms root with a resolvable link, two dangling links, a plain file and a canary outside the module tree), and the `plant_no_link_purge` mutation behind control `plant_dangling_link_kept` at `:776-781`, `:801-802` | `docs/evidence/runtime/28-dangling-kernel-link.txt`, `docs/evidence/packaging/06-posttrans-missing-headers.log` |
| A41 | S3 | Long-open suspicion R3: `sm750_pipe_enable()` sets `scanout_offset = 0` (`src/sm750_drm.c:4018`) after the enabling commit's plane update has already run, so that commit's frame could be dropped or clobbered. Adjudicated as not a defect. The ordering is real - the default commit tail calls `commit_planes()` before `commit_modeset_enables()` - but no flip is pending at the reset: the only staging path, `sm750_begin_staged_frame()`, requires `sdev->backbuffer_ready` (`src/sm750_drm.c:2427-2428`), which `sm750_pipe_disable()` cleared earlier in the same commit (`:4274`) or which was never set while the CRTC was off, and `sm750_present_staged_frame()` completes synchronously under `mode_lock` (`:2442-2479`), so nothing can still be in flight. The reset is also consumed inside the same function: `:4053-4058` uploads the whole plane frame of this commit into VRAM offset 0 and `:4076-4077` programs `PANEL_FB_ADDRESS` with that offset, so the panel scans this commit's frame either way | closed; not a defect - RCA | comment-only clarification at `src/sm750_drm.c:4010-4017`; no behaviour change. The previous offset must not be preserved across the enable: the test card (`:3676`, `:3679`) and its bounds check (`:3712`) address VRAM through the same field, so a stale value would let the card paint outside the scanned buffer or refuse to paint | `docs/evidence/runtime/29-scanout-offset-reset-rca.txt` |
| A42 | S3 | The SiI9024A enable gated readiness on the wrong 0x3d bit and treated a transient I2C timeout as fatal. `sii902x_wait_receiver_ready()` required the live `RX_SENSE_STATUS` (bit 3) to be stable for 100 ms inside a 2000 ms budget. SiI-PR-1064-A says bit 2 is the plugged state and bit 3 the powered receiver, and that a plugged, unpowered sink - `0x3d` = `0x04` - is a documented normal state whose EDID is readable and whose documented action is to read EDID, not to wait. The consequence was measured: one monitor power cycle produced 20 `SiI9024A receiver not ready after 2000 ms: ... status=04; enabling for compatibility` lines in 2.5 minutes, all spending the full 2 s, with the `a0` (sink electrically absent), `06` (latched receiver event) and `0e` (powered receiver) samples interleaved and no pass condition for either documented state. `0x0e` sets bit 3 while bit 2 is also set, so the old code did not report it as ready whenever the bit did not stay set across the window, and the log could not tell a powered sink from a plugged one. Separately, a TPI block write that timed out on the default software bit-bang path (`-ETIMEDOUT` when SCL never rises, unrelated to a missing ACK, which is `-ENXIO`) propagated out of `sm750_sii902x_enable()` and the whole enable failed at stage `sii902x_enable` | fixed | `sii902x_wait_receiver_ready()` accumulates `PLUGGED_STATUS` and `RX_SENSE_STATUS` separately, breaks on either after 100 ms, and polls a 500 ms budget (`src/sii902x.c:62-64`), matching TPLUG_DLY; the ready line reports both bits and the not-ready line keeps its shape and compatibility fallback. A retrying TPI write (`sii902x_write_block_retrying()`, `sii902x_write_recovering()`, `src/sii902x.c:299-347`) clears the bus with `sm750_sw_i2c_recover_bus()` only on the software path, waits 10-15 ms, retries to three attempts, and retries only `-ETIMEDOUT`; a final timeout warns `... (transient I2C timeout, retried N times); enabling for compatibility` with the stage name and returns 0, so the enable continues. It covers the option-ROM step, the initialization register, the video block, the AVI InfoFrame and the HPD workaround, never reads. `sm750_sii902x_read_edid()` skips the DDC request and returns `-ENODATA` while `SII902X_SYS_CTRL_PWR_DWN` is set. Guards: `tests/check-sii902x-recovery.sh` via `tests/check-drm-policy.sh`, with nine planted controls | `docs/evidence/runtime/30-sii9024a-readiness-and-timeout.txt` |
| A43 | S4 | The headless helper mis-modelled a compositor run five ways before it produced a single honest verdict: `LIBSEAT_BACKEND=builtin` does not exist in libseat 0.9.3 (only `logind`, `seatd`, `noop`), so weston died with `No backend matched name builtin`; the verdict passed a compositor that had already exited because a frame count alone says nothing about who owns the card; `WLR_DRM_DEVICES` was exported as the by-path symlink and wlroots splits that variable on `:`, so cage found zero GPUs; kmscube was given `-n 300` where `-n` is a connector id, not a count; and cage was given `-s`, which permits VT switching on seat0. A sixth was found on the first real sudo run: kmscube is launched with `-c 300` (fixed frame count), so its clean early exit was reported as FAIL | fixed; all five modes exercised through the installed root helper 2026-11-25 | `tools/sm750-headless.sh:168-178` (`LIBSEAT_BACKEND=noop`, `WLR_DRM_DEVICES=$CARD_NODE`, `WLR_LIBINPUT_NO_DEVICES=1`), `:179` `CARD_NODE` resolution guard, `:43` the usage line listing `diagnose`, `:202` kmscube `-A -D "$CARD" -c 300`, `:209` cage without `-s`, `:246-247` the two-line honesty comment, `:248-265` the per-mode verdict chain (zero-vblank guard first, then the kmscube exit model, then the weston/cage survivor model); gates `tests/check-headless-helper.sh` (10 assertions, 10 planted controls) with its registration in `tests/check-drm-policy.sh:263-269` and the scratch census; measured sudo runs: probe PASS, diagnose (no fd holders, refcount 0, fbcon bind 1) PASS, weston 30 PASS vblank 21248 to 21581, cage 20 PASS 21966 to 22307, kmscube 15 clean rc=0 with 22692 to 23135 | `docs/evidence/runtime/35-kmscube-exit-semantics.txt` |
| A44 | S4 | The live vblank gate asserted a hardcoded 60 Hz expectation, so `make check` failed on a panel the driver had programmed to 75 Hz: `vblank rate is outside the 5% tolerance / Measured 75.21 DRM vblanks/s over 120 events (expected 60.00)`. The same investigation cleared the driver: a frozen `vblank_count` on an idle pipe is DRM core's `vblankoffdelay` (default 5000 ms) disabling the source, measured freezing 5.51 s after the last `WAIT_VBLANK` returned and resuming immediately for a new waiter, so it is not a driver defect and no `src/` file was touched | fixed; `make check` exits 0 | `tests/check-drm-module.sh:30-31` attribute paths, `:39-41` `plausible_refresh()` awk range 20..250, `:43-47` `fallback_refresh()` with a stderr note, `:49-75` `resolve_expected_refresh()` with the preference `SM750_DRM_EXPECTED_HZ` > `/sys/class/drm/<card>/device/active_mode_refresh_hz` > `/sys/bus/pci/devices/0000:01:00.0/active_mode_refresh_hz` > fallback 60, `:208-216` `--self-test` with three planted controls; `tests/check-vblank.c` untouched | `docs/evidence/runtime/34-vblank-idle-freeze.txt` |
| A45 | S4 | The driver advertised no render node, so a userspace compositor that refuses a card-only device skipped the SM750 entirely. The string `Skipping device %s without a render node` is present in the installed `/usr/lib64/libkwin.so.6.7.5`, and the strace of a kwin 6.7.5 run shows it never opens card0 - it only `newfstatat`s `/dev/dri/card0` and `readlink`s the DRM class entry - so the skip is a library-level verdict formed before any open, not a permission failure. The device was therefore unusable to that compositor no matter what the node permissions were | fixed; node delivered and observed live, not sufficient on its own for kwin_wayland | `DRIVER_RENDER` added to both `drm_driver` instances, on the same line as `DRIVER_MODESET`: `src/sm750_drm.c:4527` (TTM/VRAM) and `:4542` (shmem shadow); the rationale block above them states that the node carries dumb-buffer and PRIME primitives only and is not a claim of GL. A render-only device would lose card0 and every mode, so the gate rejects any line that sets `DRIVER_RENDER` without `DRIVER_MODESET`. Guards: `tests/check-render-node.sh` (five assertions - both `driver_features` lines carry `DRIVER_RENDER`, no line carries it without `DRIVER_MODESET`, `SM750_DRM_VERSION` agrees with `build-package.sh`, and the live render node resolved from `/sys/class/drm/renderD*` by its `device/driver` basename exists and is writable - plus three planted controls `render_dropped`, `render_only`, `version_drift` under `--self-test`); registered at `tests/check-drm-policy.sh:270-276` and counted in the `tests/check-scratch-policy.sh:46` census (19 -> 20 scripts); it adds no `make check` recipe command, so the count stays 18. Measured on the installed 0.6.5: the node was `/dev/dri/renderD131`, `crw-rw-rw- root:render 226:131`, present in sysfs as `/sys/class/drm/card0/device/drm/renderD131`, and `DRM_IOCTL_VERSION` on it reported `sm750hdmidrm` 0.6.5 - after the 2026-11-25 19:29 reboot the same device is `/dev/dri/renderD128`, so a minor number is never a stable handle; use `/dev/dri/by-path/pci-0000:01:00.0-render` with the shadow driver's description, proving the shmem driver struct is the one instantiated. Two independent barriers remain and neither is fixed here: Mesa ships no SM750 driver (`ls /usr/lib64/dri/` has no sm750/smi entry, and `eglQueryDevicesEXT` returns zero devices), so the node has no acceleration; and the service account has no logind seat (`loginctl list-seats` lists only seat0), which kwin checks separately. `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` with `KWIN_DRM_DEVICES` and `LIBSEAT_BACKEND=noop` changed nothing, and kwin 6.7.5 has no `--drm-device` option. Plasma runs on this driver through X11 instead (`/usr/libexec/Xorg :1` on card0 at 1920x1080, kwin_x11 managing windows), with compositing off because the server's GLX is DRISWRAST without `GLX_EXT_texture_from_pixmap` | `docs/evidence/runtime/36-render-node.txt` |
| A46 | S4 | The scanout readback window could not be widened at runtime: `crc_window_bytes` was exposed with mode `0444` (`src/sm750_drm.c:265` before this change), so the 262144-byte default was the hard ceiling. At 1920x1080 with XRGB8888 pitch 7680 the visible frame is 8294400 bytes, so the `sm750_scanout` dump and the CRC source could only reach 262144 bytes, 68 of 1080 scanlines, and reading back a whole frame required a module reload with a command-line parameter. The clamp arithmetic was already correct and needed no change; only the file mode and the documented description were wrong. | fixed in 0.6.6 | `module_param(crc_window_bytes, uint, 0644)` with one comment line stating that the reader's `min()` bounds any oversized write (`src/sm750_drm.c:265-267`); `MODULE_PARM_DESC` now reads `Bytes of the visible scanout region read per CRC (default 262144, minimum 4096, clamped to the visible frame; writable at runtime)` (`src/sm750_drm.c:290-291`); the default stays 262144 and the reader is untouched apart from one comment (`src/sm750_drm.c:3127-3129`, clamp still `window = round_down(min(window, visible), 4)` at `:3144`). The CRC source and the debugfs dump share the window through `sm750_crc_region()`, so a write changes both. Guards: `tests/check-crc-uapi.sh` gained `check_window()` (parameter mode 0644, default 262144, `READ_ONCE` at use time, the `min(window, visible)` clamp and the `min_t` frame-size bound) and `check_release()` (version 0.6.6 agreeing across `build-package.sh`, `dkms.conf`, `SM750_DRM_VERSION`, `DRIVER_MAJOR/MINOR/PATCHLEVEL`, both spec files and the CI artifact names), with three planted controls `window_readonly`, `clamp_dropped`, `version_drift`; the gate adds no `make check` recipe command. Honest limit: a full-frame dump is 8294400 bytes printed as hex, so it is a diagnostic action, not something to poll | `docs/evidence/runtime/37-plasma-wayland.txt` |

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

### A34 - the panel falls back to a test card instead of dead black (fixed)

A31 named the black panel; A34 makes it visible. With the foreground VT in
`KD_GRAPHICS` nothing paints the fbdev client's buffer, so the window the panel
scans is all zeros and the panel is dead-black until a client attaches, which on
this host means never. That state is indistinguishable, without a register
dump, from a transmitter or timing fault.

The fallback is bounded on every side where it could do harm:

- It paints only inside `sm750_pipe_enable()`, in the success block, after
  `sm750_program_mode()` and after the A31 diagnostic, before
  `drm_crtc_vblank_on()`. The A31 blank sample is taken once and feeds both the
  diagnostic and the paint decision.
- It skips a softscaled window (the scanout pitch is 2048 there, not the
  display width, so a card painted at the display width would shear), a missing
  pitch or line buffer, a mode below 320x200, a pitch that does not fit the
  single probe-time line buffer, and a frame that does not fit the VRAM left
  after the scanout offset.
- The first real client commit cancels the rotation, and the commit that
  painted the card skips its own upload (`test_pattern_fresh`), so a client is
  never overwritten by a tick or by the enabling commit's own plane update.
- The card animates: a bouncing disc moves at `test_pattern_anim_ms` (default
  40 ms, 25 fps, clamped 10-1000, `0` stops it) while the palette rotates once
  per `test_pattern_period_ms`. A tick writes two bounding boxes, not a frame,
  because every pixel is recomputed from `(x, y, phase)`.
- The rotation is a `delayed_work` cancelled synchronously in
  `sm750_pipe_disable()`, in `sm750_pipe_update()`, on the enable fail path and
  in `sm750_pci_remove()`: no tick outlives the pipe or races teardown.
- Both snapshot flags are invalidated after every paint, so a later client
  commit re-uploads every span instead of trusting a snapshot the card
  bypassed.

`test_pattern=off` restores the previous behaviour exactly, and
`test_pattern=auto` cannot tell "no producer" from "a producer that draws
black" - that ambiguity is the price of a default that is useful without an
operator. `sm750-console text` is the honest alternative: it puts the
foreground VT into `KD_TEXT` so fbcon paints the panel for real and the card
never appears.

Gates: `tests/check-test-pattern.sh` (source level, part of `make check`
through `tests/check-drm-policy.sh`) holds the parameters and their documented
defaults, the guard set, the pitch-padded row copy, both pixel encodings, the
card elements, the exact paint message and the ordering against
`sm750_program_mode()`, the blank diagnostic and `drm_crtc_vblank_on()`, plus
the rotation's phase, its silence and its four cancel sites; the disc, its
reflection and its two-rectangle tick; and both timing parameters; it rejects
eighteen planted defects, five of them for the CRC-ownership invariants
recorded in A36. `tests/check-console-blank.sh` was updated for the
single-sample restructure with its own negative controls intact.
Evidence: `docs/evidence/runtime/23-test-card-fallback.txt` and
`docs/evidence/runtime/25-test-card-animation.txt`.

### A36 - the test card corrupted the scanout CRC stream (fixed)

T37 shipped a one-shot `test_pattern_fresh` flag whose stated job was to stop
the enabling commit's own plane update from overwriting the freshly painted
card. The RCA in `docs/evidence/runtime/24-test-card-crc-conflict-rca.txt`
proved the flag did the opposite. `sm750_pipe_update()` runs from
`commit_planes()`, which the default atomic tail
(`drm_atomic_helper_commit_tail()`, `drm_atomic_helper.c:1984-2003`) calls
before `commit_modeset_enables()`, and `sm750_pipe_enable()` is the modeset
enable. The flag was therefore set after the update it meant to skip, so the
first update it actually swallowed was the *client's* first present, and the
`goto event` around that branch also skipped the `sm750_test_pattern_cancel()`
directly below it. The card and its 5 s palette rotation then stayed alive on a
pipe a client had taken over.

That is what broke the CRC gate. `sm750_scanout_crc32()` reads the visible
window in 256-byte chunks; a rotation repainting rows between two chunks makes
one readback entry straddle two palettes, and the harness reports
`FAIL: CRC is not stable for a static frame: 3 distinct values in 12 frames`.

Two independent fixes, both required:

- The CRC source owns the window. `sm750_crc_enable()` cancels the card before
  it arms, `sm750_test_pattern_should_paint()` returns false for any armed
  source, and the tick re-checks under `mode_lock` so a work item that already
  lost the `cancel_delayed_work_sync()` race paints nothing. `always` does not
  override this: the flag stays set across a suspend/resume of the source, so
  the card cannot come back mid-session.
- Ownership, not emptiness, decides the paint. A userspace DRM master is
  producing frames by definition, so a black frame from one - a desktop, a
  screensaver, the CRC harness' own buffer - is a picture and must not be
  painted over. The condition is now `!READ_ONCE(sdev->drm.master) && blank`;
  the in-kernel fbdev client never becomes a master, so the KD_GRAPHICS case
  the card exists for still gets it.

The one-shot is gone rather than corrected: any equivalent flag would again
have to guess which commit it belongs to, and the ownership test needs no such
guess. `tests/check-scanout-crc.sh` passes unmodified, which is the acceptance
criterion for this fix. Evidence:
`docs/evidence/runtime/26-test-card-crc-fix.txt`.

### A37 - a broken stale registration blocked its own removal (fixed)

The owner installed the 0.6.2-1 RPM on the target host and the module was not
installed. For each installed kernel the transaction printed, verbatim:

```
>>> Module sm750hdmifb/0.6.1 for kernel 7.3.4-100.fc43.x86_64 (x86_64):
>>>
>>> Error! Could not locate dkms.conf file.
>>> File: /var/lib/dkms/sm750hdmifb/0.6.1/source/dkms.conf does not exist.
>>>
>>> Error! Failed to uninstall sm750hdmifb/0.6.1 for kernel 7.3.4-100.fc43.x86_64 (x86_64).
>>> warning: dkms install failed for 7.3.4-100.fc43.x86_64; run it manually
```

and closed with

```
>>> warning: no supported installed kernel has usable headers; the module was not built
>>> removing stale DKMS registration: sm750hdmifb/0.6.1
>>> Error! sm750hdmifb/0.6.1 is broken!
```

`cat /sys/module/sm750hdmidrm/version` then printed `0.6.1`, so the module
DKMS had just built and signed for 0.6.2 never reached `/lib/modules`.

Mechanism, and the reason the order is load-bearing: `dkms install` of a new
version is not a plain copy. It first uninstalls the older registered version
for that kernel. The 0.6.1 registration was broken - rpm had erased the 0.6.1
package's files, so `/var/lib/dkms/sm750hdmifb/0.6.1/source` dangled - and dkms
refused to touch it, exited non-zero, and installed nothing. The
`%posttrans` of 0.6.2-1 ran that install loop *before* the stale purge, so the
purge met the same broken entry afterwards and gave up with
`Manual intervention is required!`. The purge was correct and useless: it ran
after the step it exists to protect. The warning it printed also misattributed
the cause; the headers were present for all three kernels.

The fix moves the whole purge ahead of the build loop and gives a failed
removal one escalation: when the version directory exists and
`<tree>/source/dkms.conf` is not a readable file, the tree is deleted with
`rm -rf --` after `warning: removing broken DKMS registration tree: <path>`,
which is exactly what dkms asks for in its own message (`If this module
version is no longer needed, you can remove the stale directory.`). A tree
whose `dkms.conf` is readable is never deleted; `dkms remove` owns that case.
The tree path is built from `$dkms_root`, overridable through
`SM750_RPM_DKMS_ROOT` so the defective branch can be tested without touching
`/var/lib/dkms`; rpm never sets the variable.

Because the path now derives from a value parsed out of `dkms status`, the
version is validated before it reaches a path: empty, containing `/`, equal to
`.` or `..`, or carrying any byte outside `[0-9A-Za-z._-]` is skipped. The
existing properties are unchanged - only `%{dkms_name}` exactly, never
`%{dkms_version}`, each version at most once, a failed removal is a warning
and never a non-zero exit, and the scriptlet still ends in `exit 0`.

Gates: `purge_before_build()` reads the line numbers of the purge marker and
of the first `for kernel_dir in` out of the extracted scriptlet and fails
unless the purge comes first; `broken_scenario()` builds a sandbox dkms root
with a 0.6.1 tree that has no `source/dkms.conf`, a second module's canary and
a failing `dkms remove` shim, and asserts the tree is gone, the canary intact,
`%{dkms_version}` and the other module untouched, that `dkms install` for the
running kernel is still attempted afterwards, that the transcript contains no
`dkms install failed`, and that the scriptlet exits 0; `unsafe_scenario()`
feeds `sm750hdmifb/../etc`, `sm750hdmifb/..`, `sm750hdmifb/.` and a token with
a byte outside the class, and asserts no such version reaches `dkms remove`
and nothing outside the version tree is removed. Three planted controls
(`plant_purge_after_build`, `plant_broken_tree_escalation`,
`plant_unsafe_version`) prove each assertion can fail. Evidence:
`docs/evidence/runtime/27-posttrans-install-failure.txt`.

### A38 - a deprecated `dkms.conf` directive that did nothing (fixed)

`dkms add` printed `Deprecated feature: CLEAN
(/var/lib/dkms/sm750hdmifb/0.6.2/source/dkms.conf)`, and the troubleshooting
section of `docs/PACKAGING-RPM.md` told the reader to expect it and do
nothing. The directive was inert: in dkms 3.4.4 `/usr/sbin/dkms:582-585` is
the only occurrence of `CLEAN` in the file and it exists to print that
warning, so the clean command a reader would assume ran never ran.

`CLEAN="make KDIR=${kernel_source_dir} clean"` is deleted from `dkms.conf`,
which now ends at `MAKE[0]` (`dkms.conf:9`); the documentation paragraph is
replaced with the mechanism and with the rule that no shipped directive may
produce a deprecation warning. Guard: `no_deprecated_directive()` rejects
`^[[:space:]]*CLEAN[[:space:]]*=` in the working-tree `dkms.conf` and in the
`dkms.conf` extracted from the built RPM, and the `plant_clean_directive`
control re-adds the line to prove the check bites.

### A39 - the console helper's zero-frame hint fired on a non-zero frame (fixed)

`tools/sm750-console.sh show` ended with
`(crc32 0xe20eea22 is 262144 zero bytes: nothing has painted the window)`
whatever it had just read. Observed on this host with the test card on screen:

```
scanout nonzero: 200323
scanout crc32: 0x3972ef44
(crc32 0xe20eea22 is 262144 zero bytes: nothing has painted the window)
```

200323 nonzero bytes and a different CRC, followed by a hint that says the
opposite. The hint is a statement about one CRC value, so it is now gated on
that value: the helper captures the field once, prints the hint only for
`0xe20eea22`, and otherwise prints
`(crc32 0xe20eea22 is 262144 zero bytes; this frame is not it)`
(`tools/sm750-console.sh:102-107`). No other output line changed and the
script is still POSIX sh. Guard: `hint_is_conditional()` requires the CRC test
immediately before the hint and the alternative wording within three lines,
and `plant_unconditional_hint` inserts an unconditional copy to prove the
check bites.

### A40 - a dangling active-version link aborted the install (fixed; host-verified for 0.6.2-3)

A37 fixed the order but not the whole shape of the leftover. The host still
carried, one per installed kernel, a DKMS active-version symlink whose target
rpm had erased:

```
lrwxrwxrwx 1 root root 27 ... kernel-7.2.15-100.fc43.x86_64-x86_64 -> 0.6.1/7.2.15-100.fc43.x86_64/x86_64
lrwxrwxrwx 1 root root 27 ... kernel-7.3.3-100.fc43.x86_64-x86_64  -> 0.6.1/7.3.3-100.fc43.x86_64/x86_64
lrwxrwxrwx 1 root root 27 ... kernel-7.3.4-100.fc43.x86_64-x86_64  -> 0.6.1/7.3.4-100.fc43.x86_64/x86_64
```

`do_install()` in dkms 3.4.4 (`/usr/sbin/dkms:1768`, `:1783-1784`,
`:1866-1868`) takes the old version out of that link target alone and
uninstalls it before installing the new one, so it asked to uninstall `0.6.1`
for every kernel, found no `source/dkms.conf`, and died 6. `dkms status` lists
registrations only, and a dangling link is not one, which is why A37's purge -
driven by `dkms status` - could not see it, and why the only visible result was
`dkms status -m sm750hdmifb` showing `0.6.2, <kernel>, x86_64: built` with no
module loaded.

The purge now has a second loop, after the version loop and before the build
loop (`packaging/sm750hdmifb.spec:245-251`): it walks
`"$dkms_root/%{dkms_name}"/kernel-*`, ignores anything that is not a symlink,
and removes a link only when `[ ! -d "$dkms_link/" ]` shows it does not
resolve - dkms always points these links at a version directory, so that is
the resolution test. A link that resolves is left alone, as is every path
outside the module directory. Guard: `dangling_link_scenario()` in
`tests/check-rpm-dkms.sh` builds a dkms root with one resolvable and two
dangling links plus a canary outside the module tree, and
`plant_dangling_link_kept` deletes the loop to prove the check bites.

The host was repaired by its owner while this fix was being written: the three
links now resolve to `0.6.2`, `dkms status` reports `installed` for all three
kernels and the loaded module reports version `0.6.2`, so the premise state
above no longer exists there. The 0.6.2-3 package was then installed on the
host by its owner and completed with the module installed for all three
kernels (`dkms status` lists `0.6.2, <kernel>, x86_64: installed (Original
modules exist)` and `/sys/module/sm750hdmidrm/version` prints `0.6.2`), and the
new loop printed no `removing dangling DKMS kernel link:` line because none of
the three links dangled - the loop acts only on a link that does not resolve.
That install did exercise the `do_install()` active-version branch against a
healthy registration, the same branch that died 6 in 0.6.2-1 and 0.6.2-2; what
it did not exercise is that branch over an unresolvable target, which still
needs a host carrying such a link. Section 6 of
`docs/evidence/runtime/28-dangling-kernel-link.txt` records the recovered
after-state, section 7 what is still unobserved and section 8 the 0.6.2-3
transcript.

### A41 - the enable-path offset reset drops no frame (closed; not a defect)

The suspicion is older than this task and was repeated three times: `sm750_pipe_enable()` sets `scanout_offset` to zero after the same commit's plane update has run, so an enabling commit's frame could be lost or clobbered. `docs/evidence/runtime/29-scanout-offset-reset-rca.txt` splits the claim into three premises and finds only the first true. The plane update does run before the enable - the default atomic tail calls `commit_planes()` before `commit_modeset_enables()` - but no flip is pending at that moment and the reset is consumed before the hardware is reprogrammed.

No flip can be pending. `sm750_present_staged_frame()` (`src/sm750_drm.c:2442-2479`) is synchronous under `mode_lock`: it either swaps the offsets or records the timeout, and there is no completion or deferred work that could finish afterwards. The only way a frame is staged is `sm750_begin_staged_frame()`, which requires `sdev->backbuffer_ready` (`:2427-2428`). That flag is cleared by `sm750_pipe_disable()` earlier in the same commit (`:4274`), was never set while the CRTC was off, and is set again only at `:4083`, after `sm750_program_mode()` succeeds. In every commit that reaches the enable, the staging gate is therefore closed when the plane update runs.

The reset is not a state transition that outlives the function. `:4053-4058` fills VRAM offset 0 with the whole plane frame of the commit and `:4076-4077` programs `PANEL_FB_ADDRESS` with that same offset, so the value written at `:4018` is exactly the buffer that path fills and scans. That is why it must be zero and must not inherit the previous offset: the test card (`:3676`, `:3679`) and its bounds check (`:3712`) address VRAM through the same field, so a preserved value would let the card paint outside the scanned buffer or refuse to paint.

Two limits are recorded rather than glossed.

- Layer 2 of the verdict - that the simple-pipe CRTC provides `.atomic_disable` and no `.atomic_prepare`, so its disable half runs before the plane update - could not be read from source on this host: `drm_simple_kms_helper.c` is absent from `/usr/src/kernels/7.3.4-100.fc43.x86_64` and `include/drm/drm_simple_kms_helper.h` carries no kernel-doc. Layer 1, which is what closes the item, does not depend on it: even if a swap did happen there, `:4053-4058` re-uploads the same framebuffer from the same plane state before the mode is programmed, so the frame at offset 0 is this commit's frame either way.
- The fragile part is the order, not the offset. The async damage queued earlier in the commit is built before `shadow_source_width` and `shadow_source_height` are set (`:4024-4025`), so its worker uploads nothing and the frame reaches VRAM only through `:4053-4058`. If that upload ever became conditional, the first frame of an enabling commit would be dropped; `:4059` re-seeds the async source afterwards, which is what keeps the two paths consistent.

No code change was made, and none should be: the only change recorded here is the comment at `src/sm750_drm.c:4010-4017`. `docs/DEFECTS.md` carries this row so the question is not re-opened as a defect; a correction is a new row that names A41.

### A42 - the readiness gate tested the wrong bit and a timeout killed the enable (fixed)

`sii902x_wait_receiver_ready()` polled `0x3d` every 25 ms for 2000 ms and required the live `RX_SENSE_STATUS` (bit 3) to stay set for 100 ms. The vendor register description (`docs/notes/sii9024a-vendor-research.md`, SiI-PR-1064-A rev A, `tpi.txt:2040-2041` and `:2050-2056`) says bit 2 is the plugged state - the bit that makes EDID readable and that stabilises within TPLUG_DLY, 400/480/600 ms - and bit 3 is the powered receiver. A plugged, unpowered sink reading `0x04` is therefore normal, and the documented action is to read EDID rather than to wait for bit 3.

The measured cost, from the 0.6.2 log of one monitor power cycle on the target host (transcript: `docs/evidence/runtime/30-sii9024a-readiness-and-timeout.txt`): 20 enable attempts, all within 2.5 minutes, each spending the full 2000 ms. One line carried `HPD=0 RSEN=0 status=a0` at the instant power was cut, the bulk carried `HPD=1 RSEN=0 status=04`, one carried `status=06` (the latched receiver event of bit 1) and one carried `status=0e` (both live bits set). No `-110` appeared in 418 mode sets. Because the gate keyed on one bit, the `0x04` bulk could never pass and the `0x0e` sample was reported through the same "not ready" branch whenever bit 3 did not hold across the window.

The fix keys the wait on `PLUGGED_STATUS` and keeps `RX_SENSE_STATUS` as a second, equal pass condition (`src/sii902x.c:635-674`): both accumulate a stability counter, either one breaks the loop after `SII902X_READY_STABLE_MS`, and the budget is `SII902X_READY_BUDGET_MS` = 500 ms (`:62-64`), the TPLUG_DLY maximum. The ready line now prints both bits, the not-ready line keeps its exact shape and the `enabling for compatibility` fallback, and the function still returns 0 either way.

The second half of the row is the timeout. On the default software bit-bang path `sm750_sw_i2c_write_block()` reports `-ETIMEDOUT` when SCL never rises (`src/ddk750_swi2c.c:292-306`); a missing ACK is `-ENXIO` (`:319`) and is a different event. Upstream handles the wedge rather than failing: dw-hdmi unwedges nine clocks and retries once with `-EAGAIN`, and the in-tree sii902x 2e7a66a8b5eb retries the `0x3d` read five times and continues. The driver now does the same for writes only:

- `sii902x_write_block_retrying()` (`src/sii902x.c:299-321`) retries while the result is `-ETIMEDOUT`, up to `SII902X_WRITE_ATTEMPTS` = 3 attempts, calling `sm750_sw_i2c_recover_bus()` only on the software path (the hardware path owns its own bus) and waiting `SII902X_RECOVER_DELAY_US` to +5 ms between attempts. A NACK is never retried and never clears the bus: the vendor notes that the DDC-release write `0x1a = 0x00` is designed to be unacknowledged.
- `sii902x_write_recovering()` (`:332-347`) wraps it: any result other than a timeout is returned unchanged, and a final timeout logs `SiI9024A %s write timed out at stage %s (transient I2C timeout, retried %u times); enabling for compatibility` and returns 0, so the enable finishes through the compatibility path and GAP-B8 stays diagnosable through the stage name that `sm750_sii902x_set_mode_stage()` (`:220-223`, called from `sm750_program_mode()`) recorded.
- It is applied to the option-ROM step, the initialization register, the video block, the AVI InfoFrame and the HPD workaround, and to nothing else. Reads stay direct: a read timeout is not what GAP-B8 shows, and a retry there would double the failure surface.

One precondition was missing from the EDID path. Kernel precedent (adv7511 powers the chip for the read) and the upstream sii902x readout patch both require the transmitter to be powered: `sm750_sii902x_read_edid()` now checks `SII902X_SYS_CTRL_PWR_DWN` in the saved system-control value and returns `-ENODATA` without a DDC request (`src/sii902x.c:1096-1100`), which `sm750_connector_read_edid()` already treats as "no EDID" - it logs `monitor identity EDID unavailable` and falls back to no EDID, so the mode list is unchanged.

Guard: `tests/check-sii902x-recovery.sh`, run from `tests/check-drm-policy.sh`, with nine planted controls (readiness keyed on `RX_SENSE`, retry on `-ENXIO`, retry with no bus clear, the helper used on the EDID read, the wrapper returning the timeout, a literal DDC poll interval, a raised grant budget, a third grant attempt, no per-mode-set bus clear). Post-fix behaviour on hardware is not yet observed; section 3 of the transcript says so.

T53 extended the same gate to the DDC grant wait: `SII902X_DDC_GRANT_POLL_MS` is 200 and `SII902X_DDC_GRANT_BUDGET_MS` 2000 with a single retry after one bus clear (`src/sii902x.c:69-75`, `:1138-1168`), the DDC switch is released on every exit path, and every mode set clears the software bus before touching the transmitter (`src/sii902x.c:870-895`). The vendor model this follows is `GetDDC_Access()` (`ddk750/siHdmiTx_902x_TPI.c`, the DDK drop), which polls 50 times at 200 ms and never treats a failed grant as fatal. Worst case under `mode_lock` is about 4.1 s when the sink never grants; `docs/evidence/runtime/32-sii9024a-ddc-grant.txt` records it.

## Evidence handling

`docs/plan/` and `docs/evidence/` are development-only: they are tracked in git
but never shipped. Both are declared in `packaging/source-excludes.sh`, the
single list `build-package.sh` and `tests/audit-release.sh` read (defect A29),
so `tests/audit-release.sh` fails if either appears in the source archive. The
logs in `docs/evidence/` contain absolute host paths that the release scan
rejects by design, which is why they cannot ship even though they are tracked.
`docs/notes/` is declared in the same list for the same reason, and its
quotations from vendor documents whose redistribution terms are unknown are why
it cannot ship.
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

### A46 - the scanout readback window could not grow to a full frame (fixed in 0.6.6)

`sm750_crc_region()` (`src/sm750_drm.c:3130-3153`) computes its window as
`max_t(u64, round_down((u64)READ_ONCE(crc_window_bytes), 4), 4096)`, then
`round_down(min(window, visible), 4)` where `visible` is
`min_t(u64, sdev->scanout_frame_size, sdev->vram_size - sdev->scanout_offset)`.
The arithmetic was already safe for any value: the `min()` against `visible`
means a write larger than the frame can only clamp to the frame. What made the
default a ceiling was the parameter mode. `module_param(crc_window_bytes, uint,
0444)` (`:265` before this change) made 262144 bytes the most the scanout CRC
source and the `sm750_scanout` debugfs dump could read, which at 1920x1080 with
XRGB8888 pitch 7680 is 68 of 1080 scanlines of an 8294400-byte frame.
`docs/evidence/runtime/37-plasma-wayland.txt` records that limit in the
Plasma/Wayland report, including that the dump's start offset alternates between
0 and 4147200 because the driver double-buffers.

The fix is a mode change, not a maths change: `module_param(crc_window_bytes,
uint, 0644)` (`src/sm750_drm.c:265-267`), with one comment line above it saying
the reader clamps to the visible scanout area so a larger value is bounded by
the geometry. `MODULE_PARM_DESC` now reads `Bytes of the visible scanout region
read per CRC (default 262144, minimum 4096, clamped to the visible frame;
writable at runtime)` (`:290-291`). The default stays 262144, and the reader body
is unchanged apart from the comment at `:3127-3129`; the clamp line stays
`window = round_down(min(window, visible), 4)` at `:3144`. Because the CRC tick
and the dump both go through `sm750_crc_region()`, one write changes both, and
because the value is read with `READ_ONCE()` on every use, it takes effect on
the next vblank or the next dump without a reload.

The honest limit is the cost, not the correctness: a full-frame dump at
1920x1080 XRGB8888 is 8294400 bytes printed as hex by
`sm750_scanout_show()` (`src/sm750_drm.c:4446`), so widening the window is a
diagnostic action, not something to poll. `docs/PARAMETERS.md` says so in the
parameter's own row.

Guard: `tests/check-crc-uapi.sh` gained `check_window()`, which asserts the
parameter mode is 0644, that the read-only form is gone, that the default is
still 262144, that the reader still uses `READ_ONCE(crc_window_bytes)`, that the
clamp `window = round_down(min(window, visible), 4)` is still present and that
`visible` is still bounded by `min_t(u64, sdev->scanout_frame_size, ...)`, plus
`check_release()`, which asserts one version across `build-package.sh`,
`dkms.conf`, `SM750_DRM_VERSION`, `DRIVER_MAJOR`/`DRIVER_MINOR`/
`DRIVER_PATCHLEVEL`, both spec files and the CI artifact names, and refuses a
tree that still says 0.6.5. Three planted controls (`window_readonly`,
`clamp_dropped`, `version_drift`) prove each new assertion can fail. The gate is
reached through `tests/check-drm-policy.sh:232`, so it adds no `make check`
recipe command.
