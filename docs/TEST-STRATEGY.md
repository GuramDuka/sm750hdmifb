<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Test strategy and recorded results

Scope: sections 1 to 9 are the 0.5.9 record - the driver and packaging artifacts
at version 0.5.9, tested after the fixes recorded in [DEFECTS.md](DEFECTS.md).
The later 0.6.0 re-runs form a separate record, named in section 4; the 0.5.9
rows are kept unchanged as the before-fix half. Every result row below is a run
performed on 2026-11-18 after T5 completed, or a blocked probe whose denial was
observed on the same day. Baseline captures taken on 2026-11-17 (connector
state, EDID, tool matrix) are cited only as state description, never as a test
result.

The runtime rows R13-R17 and suites S4-S6 were added by T10 on 2026-11-18,
after a udev ACL made `/dev/dri/card0` openable by `uid=1005(coder)`. They are
labelled **pre-fix baseline**: the module loaded on the host during that run was
the previously installed 0.5.9 build (no `/sys/module/sm750hdmidrm/version`, no
`regs` debugfs node, `dkms status` reports `sm750hdmifb/0.5.9`), so they are the
BEFORE half of a before/after pair and not results for the fixed build.

Two rules govern this document:

1. A PASS requires an evidence file that exists in this repository. A suite
   that cannot touch the hardware is a GAP, not a PASS and not a FAIL.
2. "Suite passes" and "hardware proven" are different claims. `make check`
   passing proves the software checks and the compile, not that a modeset
   produced the expected pixels on the panel.

## 1. Environment and constraints

The normative test path is rootless: `uid=1005(coder)`, no `video` group. A
sudoers allowlist (`/etc/sudoers.d/10-sm750-debug`) covers the debugfs read,
`dmesg`, `journalctl -k`, DKMS, module load and RPM install/erase; it is not a
general sudo grant, and its two `lspci` lines are rejected for unescaped colons,
so PCI config space beyond 0x40 stays out of reach.

`/dev/dri/card0` is `0660 root:video` **with a udev ACL for `coder`**
(`getfacl` shows `user:coder:rw-`, and `/dev/dri/by-path/pci-0000:01:00.0-card`
resolves to `../card0`). KMS clients therefore open it as uid 1005; this is what
unblocked S4-S6 in T10. Two device nodes remain out of reach unprivileged and
are the current blockers: `/dev/tty0` is `crw------- root tty` (blocks any IGT
test that switches VT graphics mode) and `/sys/kernel/debug` is `drwx------
root` (blocks the register dump, GAP-B4).
Full detail: [ENVIRONMENT.md](ENVIRONMENT.md) section 5,
[EVIDENCE-GAPS.md](evidence/EVIDENCE-GAPS.md) GAP-B3, and
`docs/evidence/runtime/01-original-state.txt`.

Environment chain used by every build and check run:

```sh
export PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm
export LD_LIBRARY_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64
export C_INCLUDE_PATH=/mega/tmp/sm750/t3/libdrm/usr/include
```

| Item | Value used in the recorded runs |
| --- | --- |
| Running kernel | `7.3.4-100.fc43.x86_64` |
| Compiler | `/usr/bin/gcc`, GCC 15.3.1 20260722 (matches `CONFIG_GCC_VERSION=150301`) |
| libdrm headers and library | 2.4.134, extracted from `libdrm-2.4.134-1.fc43` into `/mega/tmp/sm750/t3/libdrm` |
| Header trees built | `/usr/src/kernels/{7.2.15,7.3.3,7.3.4}-100.fc43.x86_64`; `6.17.1-300.fc43.x86_64` extracted from Fedora koji into `/mega/tmp/sm750/t5/k617` |
| `make check` build KDIR | `/lib/modules/7.3.3-100.fc43.x86_64/build` (recorded in `01-make-check.log`) |

No run installs, loads, or replaces the running module. The DKMS module loaded
on the host is the previously installed 0.5.9 build, not the binaries produced
by these runs. That is also true of the T10 runtime tiers: they exercise the
0.5.9 build and are the before-fix baseline.

## 2. Suite selection

Selection rule: use the in-repo suite first. Add an external suite only where
it proves something the in-repo suite cannot, and record it as blocked when the
device node is denied. Exclude tools that cannot produce a result on this board.

Status wording: "pre-fix baseline" marks a row produced on 2026-11-18 by T10
against the stale 0.5.9 module that was loaded on the host. Such a row is real
evidence about that build, but it is the BEFORE half of a before/after pair and
must not be read as a result for the fixed build.

Transient output from every suite goes to `/mega/tmp/sm750/tmp` (each script
exports `TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}`), never to `/tmp`.

| ID | Suite | Role | Status |
| --- | --- | --- | --- |
| S1 | In-repo `make check` (18 recipe commands since 2026-11-22; the archived captures record 17) | Primary software regression gate | PASS |
| S2 | In-repo build matrix (`tests/build-all-kernels.sh`) | Kernel-range and scanout-format gate | PASS |
| S3 | Package build and release audit | Release-artifact gate | PASS |
| S4 | `modetest` (libdrm) | Minimal KMS enumeration and modeset client | PASS (pre-fix baseline) |
| S5 | `kmscube` | Independent KMS rendering client | PASS (pre-fix baseline) |
| S6 | IGT GPU Tools KMS subset | Independent conformance, stretch artifact | FAIL (pre-fix baseline, 1 real) + GAP (VT-blocked subset) |
| S7 | `v4l-utils` | Excluded: no capture path on this board | Not run by design |
| S8 | `edid-decode` | EDID decoder, baseline diagnostic only | Reference only |
| S9 | In-repo `tests/check-console-blank.sh` (via `make check`) | Source-level gate: the blank-console precondition is named, ordered after the modeset and inert | PASS |
| S10 | In-repo `tests/check-console-scanout.sh` (`make console-check`, opt-in) | Root-only: the console reaches the panel on a `KD_TEXT` VT; skips with a named cause under `KD_GRAPHICS` | PASS on the card under `KD_TEXT` (2026-11-20, all three assertions); the script still skips with exit 77 when the VT is `KD_GRAPHICS` or the caller is not root |
| S11 | In-repo `tests/check-restore-path.sh` (via `make check`) | Source-level restore-path gate: masked transition compare with re-poke, mode-derived budget, kept display-off result, terminal fail path | PASS (source gate) plus PASS on hardware 2026-11-20: 30 restore cycles, 20 mode changes, 95 enable events, zero fault lines |
| S12 | In-repo `tests/check-test-pattern.sh` (via `make check`) | Source-level test-card gate: the three writable parameters and their defaults and clamps, the bounded painter, the rectangle writer used by both the full card and the animation tick, the pitch-padded row copy, both pixel encodings, the card elements, the disc's motion and reflection, the exact paint message and call ordering, the rotation's cancel sites and tick silence, and the CRC-ownership rules (an armed scanout CRC source owns the window; a userspace master's black frame is a picture) | PASS (source gate); eighteen planted defects rejected. Bars and the 5 s palette jump observed on the panel 2026-11-20; the animated disc is not yet observed |
| S13 | In-repo `tests/check-rpm-dkms.sh` (outside `make check`) | Evidence-hygiene gate on the packaging transcripts: every captured command runs under `LC_ALL=C LANG=C`, and after the last transcript is written the run fails on any non-ASCII byte in `docs/evidence/packaging/0[1-6]-*.log`, printing the file and its line numbers | PASS; `plant_localized_evidence` (one injected Russian `rpmbuild` line) rejected. 01-06 regenerated ASCII-clean at 0.6.2; the frozen `0.5.9/` archive predates the fix and is not covered |
| S14 | In-repo `tests/check-sii902x-recovery.sh` (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level A42 gate: the readiness wait accumulates the plugged bit (and accepts a stable powered receiver) inside a 500 ms budget, a timed-out TPI write is retried after a software bus clear with only `-ETIMEDOUT` recoverable, the retrying write covers the option-ROM step, the initialization register, the video block, the AVI InfoFrame and the HPD workaround but never a read, a final timeout warns with the stage name and does not fail the enable, and the EDID read is skipped while the transmitter is powered down | PASS (source gate); nine planted defects rejected (readiness keyed on `RX_SENSE`, retry on `-ENXIO`, retry with no bus clear, the helper used on the EDID read, the wrapper returning the timeout, a literal DDC poll interval, a raised grant budget, a third grant attempt, no per-mode-set bus clear). T53 added the DDC grant budget (200 ms poll, 2000 ms budget, one retry after a bus clear) and the per-mode-set software bus clear. Post-fix power-cycle behaviour is not yet observed on hardware |
| S15 | In-repo `tests/check-sm750-smi.sh` (via `make check`) | Fixture-driven gate for the `sm750-smi` monitoring tool: all 27 fields resolved from synthetic sysfs/DRM trees, eleven fixture shapes, `--strict` exit codes, CSV and JSON parsed by `python3`, five planted controls rejected; no GPU and no root needed | PASS (2026-11-25) |
| S16 | In-repo `tests/check-sysfs-attributes.sh` (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level gate for the twelve monitoring attributes `sm750-smi` reads from `/sys/class/drm/cardN/device/`: one `DEVICE_ATTR_RO()` and one array entry per name, the group registered on `&pdev->dev` before `drm_dev_register()`, every show function using `dev_get_drvdata()` with a NULL guard and `sysfs_emit()` and neither sleeping nor taking a lock other than the mode lock, `clear_events = false` on the link-status read, and `vblank_count` reading DRM core's counter | PASS (2026-11-22); five planted defects rejected (renamed attribute, `clear_events` true, `msleep` in a show function, group on the DRM class device, spin lock in a show function) |
| S17 | In-repo `tests/check-sm750-pkg.sh` (`make check-pkg`, opt-in) | Self-tests for the sudo package helper: newest-pair selection, version agreement, symlink refusal, argv refusal, the unprivileged status path, the root requirement, a single `dkms` invocation, missing-tools reporting, and the ownership/mode policy. dnf, dkms, rpm, modprobe and lsmod are stubbed through a temporary PATH, so no package is installed, removed or loaded and no root is needed | PASS (nine groups); added a `check-pkg` make target on 2026-11-22 |

| S18 | In-repo `tests/check-kunit-drm.sh` (`make check-kunit`, opt-in) | DRM KUnit sweep: discovers the DRM KUnit suites under `/lib/modules/$(uname -r)/internal/drivers/gpu/drm/tests/` (floor of 8 so an empty directory fails), modprobes each (KUnit autorun runs it at load), parses the TAP output (`# Subtest:`, `ok N - name`, `not ok N - name`, `# Totals: pass:N fail:N skip:N`) from the kernel log via `DMESG_CMD`, fails naming the suite and subtest, and unloads every module in an EXIT trap. Needs root, or the allowlisted loader of `docs/ROOT-ACTIONS.md` section 3.9 (`MODPROBE_CMD='sudo -n /usr/bin/modprobe'`); without either an unprivileged run exits 77 with one SKIP line. Four planted parser defects rejected plus two negative controls in `--self-test` | Live on 2026-11-22 through the installed per-module allowlist: 23 modules discovered, 21 suites loaded and unloaded, all 21 printed only `kunit: disabled` because `# CONFIG_KUNIT_DEFAULT_ENABLED is not set` on this kernel, so the gate skips with exit 77 naming that prerequisite (`docs/ROOT-ACTIONS.md` section 3.10) instead of passing; self-test PASS; the suites' real pass/fail census is NOT YET OBSERVED |
| S19 | In-repo `tests/check-oops-delta.sh` (`make check-oops`, opt-in; standalone `-- <command...>`) | Reusable oops detector: snapshots the kernel log before and after the wrapped command through `DMESG_CMD` (default `dmesg`, this host `sudo -n dmesg`), diffs the delta, filters `--allow` regexes or `OOPS_ALLOW_FILE`, and fails on any new `BUG:`, `WARNING:`, `Oops`, `general protection fault`, `kernel NULL pointer dereference`, `lockdep`, `call trace` or `RIP:` line; exits 77 when the log is unreadable. Three planted defects rejected (new `WARNING:`, new `BUG:`, wrapped command failing) plus four negative controls (unchanged log, allow-filtered warning, allow wins over BUG, allowlist file) in `--self-test`; exercised live by wrapping `tests/check-drm-policy.sh` and `tests/check-sm750-pkg.sh` | PASS (2026-11-22, `sudo -n dmesg` reader, both wrapped gates clean) |
| S20 | In-repo `tests/check-headless-helper.sh` (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level gate for the operator helper `tools/sm750-headless.sh`: POSIX `sh` that passes `sh -n`, the five modes `probe`, `diagnose`, `weston`, `cage` and `kmscube` with a usage path that exits 2 for anything else, the `0000:01:00.0` and `sm750hdmidrm` driver binding test, `LIBSEAT_BACKEND=noop` exported and never `builtin`, the weston arm carrying `--backend=drm`, `--drm-device=card0` and `--shell=kiosk-shell.so`, the cage arm without `-s` (which would permit VT switching) and the kmscube arm with `-c` and without `-n` (which is a connector id), the `SECONDS` numeric test and the 1..600 clamp, the verdict failing on a died compositor and on a vblank delta `<= 0`, TERM before KILL on an EXIT trap, no local absolute path or non-ASCII byte, and that **both** compositor arms run inside a private mount namespace with an empty `/dev/input` (A49): `--mount --propagation private`, the exact `tmpfs -o size=1M,mode=0755` mount over `/dev/input`, `isolate ` present in the weston arm and in the cage arm and absent from the kmscube arm, the mount line before both compositor calls, and `WLR_LIBINPUT_NO_DEVICES` documented as wlroots-only, and section `n`'s `diagnose` hold - the card and render nodes enumerated by device number, each inode printed, and the processes holding a node counted. Static only: it runs no compositor, needs no root and never touches the card | PASS (2026-11-26); fourteen assertions; twenty planted controls rejected - the twelve below (the `LIBSEAT_BACKEND` export deleted, `noop` changed to `builtin`, `-s` added to cage, `-c` changed to `-n` in kmscube, the survivor check deleted, the vblank check deleted, a clean kmscube completion reported as a failure, a kmscube exit code ignored, an absolute local path appended, the lower clamp loosened to 0, the input isolation dropped from both compositor arms, the isolation dropped from the cage arm alone), the six `x11` controls of S26, `console-restore-dropped` (the text-VT restore removed, the A54 workaround) and `diagnose-card0-only` - plus a pristine control accepted, in `--self-test`; the helper is input-isolated, so a run cannot take the owner's keyboard or mouse |
| S21 | In-repo `tests/check-render-node.sh` (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level gate for the render node: both `driver_features` lines in `src/sm750_drm.c` carry `DRIVER_RENDER` on the same line as `DRIVER_MODESET`, no executable line carries `DRIVER_RENDER` without `DRIVER_MODESET` (a render-only device would lose card0 and every mode), and `SM750_DRM_VERSION` agrees with the `readonly version=` line of `build-package.sh`. The live half walks `/sys/class/drm/renderD*`, keeps the node whose `device/driver` basename is `sm750hdmidrm`, and requires the matching `/dev/dri/renderDN` character device and write access for the invoking user; with no such node it prints one `SKIP:` line and still exits 0, which is the state before a 0.6.5 module is loaded | PASS (2026-11-25); seven assertions, six source-level (two `DRIVER_RENDER` lines, no `DRIVER_RENDER` without `DRIVER_MODESET`, the two mode_config funcs structs present and installed, the withdrawn modifier capability, the version agreement) and one live on the render node resolved by driver name, plus five planted defects rejected (`render_dropped`, `render_only`, `version_drift`, `fb_modifiers_dropped`, `fb_modifiers_branched`) in `--self-test`. The modifier assertion is described as S23 |
| S22 | None (observed by hand; no script, no gate) | Session-level result: a full Plasma 6.7.5 Wayland session on `card0`, recorded as evidence rather than enforced, because the session needs a live seatless remote login, a private bus and a real panel | OBSERVED 2026-11-25: the compositor initializes, plasmashell presents, and the panel reads a non-zero scanout window; input and screencast are NOT measured |
| S23 | In-repo `tests/check-render-node.sh`, extended (via `make check`, called by `tests/check-drm-policy.sh`) | Device-level check that the driver withdraws the framebuffer-modifier capability: both `drm_mode_config_funcs` structs (`sm750_mode_config_funcs`, `sm750_shadow_mode_config_funcs`) must exist and be installed, `drm->mode_config.fb_modifiers_not_supported = 1;` must be present, and it must sit on the line immediately after the two-line `drm->mode_config.funcs` ternary so a guard cannot withdraw the capability for one device only. Reasoning: the plane advertises `DRM_FORMAT_MOD_LINEAR` alone, KWin 6.7.5 submitted a modifier it could not match and AddFB2 failed with EINVAL, so core must report `DRM_CAP_ADDFB2_MODIFIERS=0` and every client must take the modifiers-free path | PASS (2026-11-25); seven assertions (six source-level, one live) and five planted defects rejected (`render_dropped`, `render_only`, `version_drift`, `fb_modifiers_dropped`, `fb_modifiers_branched`) in `--self-test` |
| S24 | In-repo `tests/check-vt-helper.sh` (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level gate for the root-only helper `tools/sm750-vt.sh`, which hot-reloads `sm750hdmidrm` by unbinding fbcon from the SM750 vtconsole (A50): POSIX `sh` that passes `sh -n`, the three modes `show`, `off`, `on` in the usage and in the dispatcher with `usage` exiting 2 for anything else, a root check that still lets `show` run unprivileged, the target vtconsole resolved by globbing `/sys/class/vtconsole/vtcon*` and confirmed against `basename $(readlink -f /sys/bus/pci/devices/0000:01:00.0/driver)` = `sm750hdmidrm` with no executed `vtconN` literal, zero and multiple candidates both refused, `write_bind "$TARGET" 0` to detach and `write_bind "$TARGET" 1` to restore with every write read back from the `bind` file, one EXIT trap that restores the module, the device and then the console on a non-zero exit, disarmed by `FINISHED=1` so a successful run does not undo itself, with a restore function that ends in an explicit `return`, the userspace holder refusal gating the unload with the scan matched on node identity - the by-path card and render links resolved to a `dev:inode` pair and compared against each fd target - rather than on a node name, since the card is not `card0` after a reload, the PCI unbind step that releases the framebuffer reference (A51) between the console detach and the unload with the refcount printed before it and again after it, the device re-bound and read back after the load, `modprobe -r` before `modprobe` by line order, and the loaded version read back from `/sys/module/sm750hdmidrm/version` after the load with a missing file failing as `is missing after the load`. Static only: it writes no sysfs, calls no modprobe, needs no root and never runs the helper | PASS (2026-11-26); thirteen assertions and ten planted defects rejected (`never-restore`, `hardcoded-vtcon`, `modprobe-order-reversed`, `version-readback-removed`, `holder-check-dropped`, `pci-unbind-dropped`, `pci-rebind-dropped`, `refcount-not-reported`, `trap-restores-fbcon-only`, `holder-scan-name-glob`) plus a pristine control accepted, in `--self-test`; the reload itself is NOT YET OBSERVED |
| S25 | None (observed by hand; no script, no gate) | Panel-level proof of the 0.6.7 modifier withdrawal (A47), recorded as evidence rather than enforced: with the module loaded by the hot reload, a userspace probe on the same 1920x1080 buffer gets `OK fb=42` for plain XRGB8888 AddFB2 and `FAIL errno=22` for `MODIFIERS + LINEAR`, where 0.6.5 accepted both; a KWin 6.7.5 session started with `KWIN_DRM_USE_MODIFIERS` explicitly unset logs `drmModeAddFB2WithModifiers is not supported on GPU "/dev/dri/card0"`, reaches an initialised compositor with output PHL 243V7, and `grep -c 'Failed to create framebuffer'` returns **0** where the 0.6.5 session returned **359**; `PANEL_CURRENT_LINE` advances and twelve scanout samples read `nonzero 262144` with `crc32 0x976e751b` while the offset alternates between 0 and 4147200 | OBSERVED 2026-11-26, module 0.6.7 on kernel `7.3.4-100.fc43.x86_64` with kwin and Plasma `6.7.5`. Evidence, not a gate: there is no script and no new `make check` recipe, so `make check` stays at 18 commands, and no CI job reproduces it. Input injection and screencast are unmeasured, as S22 records; `docs/evidence/runtime/42-modifier-withdrawal-proof.txt` is the transcript |
| S26 | In-repo `tests/check-headless-helper.sh`, extended (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level gate for the `x11` mode of `tools/sm750-headless.sh`: the arm writes its server config once per run, execs `/usr/libexec/Xorg :1` directly (never the setuid-capable wrapper) from the run directory with a bare `-config` filename, carries `-sharevts -novtswitch` and `-nolisten tcp`, declares `AutoAddDevices` off with no `InputDevice` section so a root server opens no input device, must not pass an absolute or `..`-bearing config path, clamps the run length, and generates `run-plasma-x11.sh` with the `/etc/environment` variables unset and `DISPLAY=:1` exported; the plan text must name those variables and the four-crash consequence of leaking them. Static only: it starts no server, needs no root and never touches the card | PASS (2026-11-26); fourteen assertions and twenty planted controls, six of them x11-specific (`x11-sharevts-dropped`, `x11-input-device`, `x11-abspath-config`, `x11-primarygpu-reintroduced`, `x11-env-note-dropped`, `x11-session-script-unset-dropped`). The arm then ran once as root on 2026-11-26 (`x11 240`) and reached the panel: the server was up on `:1` in 4 s with `kmsdev` `/dev/dri/card0`, `kwin_x11` held pid 1979033 with zero crash lines, and the connector read `enabled` |
| S27 | In-repo `tests/check-pmtest-helper.sh` (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level gate for the PM test helper `tools/sm750-pmtest.sh`, installed as `/usr/local/sbin/sm750-pmtest`: POSIX `sh` that passes `sh -n`, the three subcommands with a usage path that exits 2 for anything else, the root check read out of `require_root` and pinned to precede the first write to `/sys/power/pm_test`, the level validated against `none core processors platform devices freezer`, the EXIT trap that writes `none` and prints the readback, the trap armed before the level write, the journal snapshot taken before `freeze` is written to `/sys/power/state` with only the delta read, the verdict requiring `pm: suspend complete`, `pm: resume complete`, no `pm: .* failed` line and unchanged `suspend_stats` error counters, no `fb0`, `/dev/fb*` or `/sys/class/graphics` in executable text, and the no-S3 explanation (`s2idle`, `freeze`, `D3hot`, the `suspend debug: Waiting for` fingerprint) in the usage. Static only: it writes no sysfs, suspends nothing, needs no root and never runs the helper | PASS (2026-11-26); ten assertion sections and six planted controls rejected (trap removed, level validation removed, readback removed, verdict passes without the completion lines, journal snapshot removed, suspend_stats read as a flat file instead of the directory this kernel publishes) plus a pristine copy accepted. The host-wide cycle it guards then ran: on 2026-11-27 at 16:12 host clock on kernel `7.3.5-100.fc43.x86_64` with driver 0.6.9 (`srcversion 67300D6D1C065017A0D1328`), `sudo -n /usr/local/sbin/sm750-pmtest run devices` printed `verdict: PASS` and exited 0 with 73 journal lines added; the driver logged all four edges exactly once (`pm: suspend entry`, `pm: suspend complete`, `pm: resume entry`, `pm: resume complete`), `suspend_stats` kept every error counter at zero with `last_failed_dev` empty, the armed fingerprint `PM: suspend debug: Waiting for 5 second(s).` was present, `PM: suspend devices took 4.919 seconds` and `PM: resume devices took 3.363 seconds`, and the panel came back at 1024x768 at 75 Hz with `vblank.count` 6508 advancing and raster `0x182 -> 0x122`. No power was removed: the host has no S3, and the two Tesla P100s did not save or restore VRAM because `nvidia.NVreg_PreserveVideoMemoryAllocations=0` was set deliberately. Transcript `docs/evidence/runtime/49-pmtest-devices-cycle.txt` |
| S28 | In-repo `tests/check-pm-probe.sh` (via `make check`, called by `tests/check-drm-policy.sh`) | Source-level gate for the 0.6.9 `pm_probe` diagnostic attribute (A66), which calls `sm750_pm_suspend()` and `sm750_pm_resume()` from a root-only sysfs write: the attribute is `DEVICE_ATTR_WO` (mode 0200) and sits in the existing `sm750_attrs[]` group registered on the PCI device; the store reads `dev_get_drvdata()` and refuses without it; a DRM client holding master refuses the write before either callback, while the fbcon client still can; an unregistered or unplugged device refuses and the callbacks run inside `drm_dev_enter()`; a dedicated mutex serialises invocations and `mode_lock` is not used, because the callbacks take it themselves; exactly `suspend`, `resume` and `cycle` are accepted and anything else is `-EINVAL`; every invocation logs `pm probe: command ...` and the callback result under the `pm probe: ` prefix; `cycle` skips resume when suspend failed; the write returns the byte count on success and the callback's own error otherwise. Section k pins the delivery path: `tools/sm750-pm-probe.sh` writes `ATTR=$SYS/bus/pci/devices/0000:01:00.0/pm_probe`, refuses to run unprivileged, implements `status` and `suspend \| resume \| cycle`, never calls `systemctl suspend`, states that a pass is not a system sleep, and carries the three driver result literals (`pm probe: suspend returned 0`, `pm probe: resume returned 0`, `pm probe: cycle suspend ok, resume ok`) and the two failure fragments (`cycle suspend failed:`, `resume failed:`) verbatim, so a drift in `src/sm750_drm.c` or in the helper fails the gate. Static only: it reads the source text, runs no callback, writes no sysfs and needs no root | PASS (2026-11-27); eleven assertion sections a..k and six planted controls rejected (`master-guard-removed`, `attribute-read-write`, `mode-lock-instead-of-mutex`, `cycle-resumes-anyway`, `result-not-logged`, `result-swallowed`) plus a pristine copy accepted. The assertion count in the pass line is derived from the sections that ran, so it cannot drift away from them. The installed helper was stale against this gate until the A67 fix; the gate is what turned a wrong verdict, reported on a cycle that had in fact succeeded, into a `make check` failure in either file |
### S1: in-repo `make check`

- Package/version: the repository itself at 0.5.9; no external package. The
  `check` target is `Makefile:30-48` and contains 17 command lines.
- Command (exactly as archived in `01-make-check.log:5`):

```sh
make check KDIR=/lib/modules/7.3.3-100.fc43.x86_64/build CC=/usr/bin/gcc
```

- Pass criterion: exit 0, all 17 recipe commands execute, and no command
  reports an error. The live vblank probe inside
  `tests/check-drm-module.sh:290-301` is allowed to print `SKIP` only because
  `/dev/dri/card0` was denied at the time of that run (before the T10 udev ACL);
  that SKIP is not a pass. The probe has since been run against the device, and
  it now derives its expectation from the driver instead of assuming 60 Hz:
  `resolve_expected_refresh` (`tests/check-drm-module.sh:49-76`) prefers a
  non-empty `SM750_DRM_EXPECTED_HZ`, otherwise reads `active_mode_refresh_hz`
  through `/sys/class/drm/card0/device/` (`:34`) and falls back to
  `/sys/bus/pci/devices/0000:01:00.0/active_mode_refresh_hz` (`:35`). A value
  that is not a number in 20..250 substitutes 60 Hz and says so on stderr, so
  the probe can never silently skip. The pass line names the refresh and its
  source. A hardcoded 60 Hz failed a panel programmed at 1024x768@75, which
  was a false failure in the gate and not a driver defect.
  `tests/check-drm-module.sh --self-test` (`:208-216`) plants the three
  regressions that matter - a restored hardcoded value, a dropped 20..250 range
  check, and a removed sysfs fallback that would yield 0 Hz - and requires each
  to fail while the pristine copy passes, so the derivation is load-bearing.
  A frozen `vblank_count` on an idle pipe is DRM core's `vblankoffdelay`, not a
  defect: the core disables the source about 5 s after the last waiter returns
  and a new waiter restarts it, so a 0 Hz idle reading must never be read as a
  failure (`docs/evidence/runtime/34-vblank-idle-freeze.txt`).
- Evidence: `docs/evidence/builds/01-make-check.log` (exit 0);
  `docs/evidence/runtime/34-vblank-idle-freeze.txt` (live probe at 75.00 Hz).

### S2: in-repo build matrix

- Package/version: `kernel-devel` trees 7.2.15-100.fc43, 7.3.3-100.fc43 and
  7.3.4-100.fc43 installed on the host; `kernel-devel-6.17.1-300.fc43`
  extracted with `rpm2cpio` from Fedora koji into `/mega/tmp/sm750/t5/k617`
  (not installed). Script: `tests/build-all-kernels.sh`.
- Command (as archived in `02-check-all-kernels.log:5`):

```sh
JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh
```

Per-tree form:

```sh
JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh \
    /lib/modules/7.2.15-100.fc43.x86_64/build
```

- Pass criterion: exit 0 and the script's final line
  `Built <N> sm750hdmidrm kernel/format combinations`, with N=9 for the three
  installed trees and N=3 for the extracted 6.17.1 tree. The
  `rgb565-bbdither` build of each tree runs the full `check` suite
  (`tests/build-all-kernels.sh:33-34,46-54`); the other two formats are
  required to compile and pass the metadata/compile-flag checks only.
- Evidence: `02-check-all-kernels.log` (Built 9, exit 0),
  `03-kernel-7.2.15-100.log`, `04-kernel-7.3.3-100.log`,
  `05-kernel-7.3.4-100.log`, `06-kernel-6.17.1.log` (each Built 3, exit 0).

### S3: package build and release audit

- Package/version: repository `build-package.sh` at 0.5.9; host `dpkg-deb`;
  audit script `tests/audit-release.sh`.
- Commands (as archived in `07-build-package.log:4` and
  `08-audit-release.log:4`):

```sh
./build-package.sh
./tests/audit-release.sh
```

- Pass criterion: `build-package.sh` exits 0 and prints the `.deb` and source
  tarball paths; `audit-release.sh` exits 0 and writes
  `dist/RELEASE-AUDIT.txt` after checking the shipped archive against the
  tracked tree (`tests/audit-release.sh:61-107`).
- Evidence: `07-build-package.log`, `08-audit-release.log` (both exit 0).

### S4: libdrm `modetest`

- Package/version: `drm-utils-2.4.134-1.fc43.x86_64` (installed; provides
  `modetest`, which has no `--version` flag), with libdrm 2.4.134.
- Command:

```sh
modetest -c
modetest -p
modetest -s 35@38:1920x1080        # re-apply the already-active mode
modetest -s 35@38:1024x768-60      # one alternate mode
modetest -s 35@38:1920x1080        # restore (also run from a trap on any exit)
```

- Pass criterion: `modetest -c` exits 0 and lists connector 35
  (`card0-HDMI-A-1`) with its modes and CRTC/plane properties; the `-s`
  modeset exits 0 and the connector remains `connected`/`enabled` with
  `dpms: On`.
- Evidence/status: **PASS for the pre-fix baseline** (T10, 2026-11-18, uid 1005
  `coder`, udev ACL on `/dev/dri/card0`). Files:
  `docs/evidence/runtime/01-original-state.txt` (state captured before any
  modeset), `02-modetest-connector.txt`, `03-modetest-properties.txt` (verbatim
  `-c` and `-p`, both exit 0), `04-modeset.txt` (every command, exit code and
  the restore). Connector 35 has **28** modes, not 36 as this section
  previously stated; `#0 1920x1080 60.00` is preferred.
- The CRTC had an active mode before the run (crtc 38 -> fb 43 at `(0,0)`
  1920x1080, `connected`/`enabled`/`dpms: On`), so a modeset on this connector
  is visible to the logged-in Plasma session. The original state was captured
  first and the original mode was restored as the last action.
- Modeset outcome: the alternate mode (1024x768-60) IS programmed and then
  reverted when the client exits. Proof is in dmesg, not in the exit code:
  `full-frame backbuffer staging enabled (1572864 bytes per buffer)` at the
  set, then `(4147200 bytes)` 2.576 s later on process exit. The alternate mode
  is therefore not retained by a one-shot `modetest -s`.
- Tooling caveat that matters for reading any `modetest` result: **exit 0 is
  not proof of a modeset.** `modetest -s 35@38:9999x9999` also exits 0 while
  printing `failed to find mode "9999x9999"` and `failed to create dumb buffer:
  Invalid argument`. The `-a` atomic form is a silent no-op on this stack
  (exit 0, no output, no state change, zero dmesg lines); only the legacy `-s`
  path reprograms the CRTC.
- Note: `modetest -c -M sm750hdmidrm` is not a useful denied-state probe on
  this libdrm: it fails at `failed to open device 'sm750hdmidrm'` before it
  enumerates cards. `modetest -c` is the command that reaches the permission
  error.
- Scope limit: the module under test is the **stale pre-fix 0.5.9 build**
  (no `/sys/module/sm750hdmidrm/version`, no `regs` debugfs node, `dkms status`
  reports 0.5.9). This row is the BEFORE half of the before/after pair, not a
  result for 0.6.0.

### S5: `kmscube`

- Package/version: `kmscube-0-11.20241006.git311eaaa.fc43.x86_64`, available
  in the `fedora` repository; downloaded to `/mega/tmp/sm750/t3-tools`, not
  installed. T10 ran it straight from the extracted payload
  (`/mega/tmp/sm750/t10/x/kmscube-0-11.20241006.git311eaaa.fc43.x86_64/usr/bin/kmscube`);
  `ldd` was fully satisfied, so no install was needed.
- Command (flags verified against the extracted binary's usage output):

```sh
tail -f /dev/null | kmscube -D /dev/dri/card0 -c 60
```

- Pass criterion: exit 0 after rendering 60 frames on `card0-HDMI-A-1` at a
  mode the connector advertises.
- Evidence/status: **PASS for the pre-fix baseline** (T10, 2026-11-18). File:
  `docs/evidence/runtime/05-kmscube.txt`. `-c 300` exits 0 with
  `Rendered 299 frames in 5.066709 sec (59.012665 fps)`; `-c 120` exits 0 with
  `Rendered 119 frames in 2.100066 sec (56.664892 fps)`. strace confirms the
  real KMS path: `DRM_IOCTL_MODE_SETCRTC`, `ADDFB2` and `PAGE_FLIP` all return 0
  with no failing syscalls, and a second client saw crtc 38's `fb_id` switch
  from 43 to kmscube's own 42/44 while it rendered.
- The stdin redirect is mandatory. kmscube polls stdin for the interrupt key;
  with stdin at EOF (`/dev/null`) it prints `user interrupted!` and exits 0
  **before** printing its frame counter. That behaviour, not a driver fault,
  caused the old GAP. It is recorded as a tooling gap in `05-kmscube.txt`.
- Renderer is `llvmpipe (LLVM 21.1.8, 256 bits)` - Mesa software rasterization,
  not SM750 acceleration. The fps figure therefore measures the KMS/vblank
  path, not GPU throughput.
- Not proven by this tier: panel pixel content. `-A` (atomic) exits 255 with
  `no eglDupNativeFenceFDANDROID`, and `-n 35` exits 255 because kmscube's
  `-n` is a connector index, not the DRM connector id.
- Scope limit: same **stale pre-fix 0.5.9** module as S4; BEFORE half only.

### S6: IGT GPU Tools KMS subset

- Package/version: `igt-gpu-tools-2.4-1.fc43.x86_64`, available in `updates`;
  downloaded to `/mega/tmp/sm750/t3-tools`, not installed. The KMS binaries
  live under `/usr/libexec/igt-gpu-tools/`, not `/usr/bin` (the package ships
  63 `/usr/bin` programs and no `igt-info`). T10 extracted the payload to
  `/mega/tmp/sm750/t10/x/igt-gpu-tools-2.4-1.fc43.x86_64` and found 359
  binaries under `usr/libexec/igt-gpu-tools`.
- Proposed subset, all generic KMS tests that do not require Intel ioctls:
  `kms_setmode`, `kms_atomic`, `kms_flip`, `kms_pipe_crc_basic`, plus
  `kms_addfb_basic`, `kms_rmfb`, `kms_getfb`, `dumb_buffer`, `core_getversion`.
- Command (after extraction; `libgsl.so.28` and `libgslcblas.so.0` come from
  `gsl-2.8-2.fc43.x86_64`, which is not installed):

```sh
IGT=/mega/tmp/sm750/t10/x/igt-gpu-tools-2.4-1.fc43.x86_64
LD_LIBRARY_PATH=$IGT/usr/lib64:/mega/tmp/sm750/t10/gsl/gsl-2.8-2.fc43.x86_64/usr/lib64 \
  "$IGT/usr/libexec/igt-gpu-tools/kms_setmode" --device /dev/dri/card0 --run-subtest basic
```

- Pass criterion: the test exits 0 with `SUCCESS` (a SKIP is not a pass,
  because the only acceptable skip reason is absent CRC support, not absent
  device access).
- Evidence/status: **FAIL for the pre-fix baseline, with one genuine driver
  failure and a separate tooling blocker.** File:
  `docs/evidence/runtime/06-igt.txt`; raw output and exit codes in
  `/mega/tmp/sm750/t10/f_<test>.out|.err` and `igt_exitcodes.txt`. The GSL
  dependency chain is now solved rootlessly (nested path
  `gsl/gsl-2.8-2.fc43.x86_64/usr/lib64`), so IGT binaries start.
- Exit codes: `core_getversion` 0, `dumb_buffer` 0, `kms_addfb_basic` 98,
  `kms_getfb` 98, `kms_rmfb` 98, `kms_fb_coherency` 77, `kms_dirtyfb` 77,
  `kms_setmode` 98, `kms_flip` 79, `kms_atomic` 98, `kms_pipe_crc_basic` 79.
- The one real driver failure: `kms_addfb_basic` subtest `size-max` fails at
  `../tests/kms_addfb_basic.c:594` with `Last errno: 22, Invalid argument` on
  `DRM_IOCTL_MODE_ADDFB2` - the driver rejects the maximum-size framebuffer.
  It emits no kernel message. The other 26 subtests pass and 14 skip as
  Intel-only (`is_i915_device` / `is_intel_device`).
- `kms_setmode`, `kms_atomic`, `kms_flip`, `kms_pipe_crc_basic` and `kms_rmfb`
  never reach the driver: they abort in `kmstest_set_vt_graphics_mode`
  (`../lib/igt_kms.c:1558`, `Failed assertion: ret >= 0`,
  `Last errno: 13, Permission denied`) because IGT opens `/dev/tty0`, which is
  `crw------- root tty`. Closing that needs root or an ACL on `/dev/tty0`,
  neither of which is in scope. Recorded as the blocker, not as a driver
  failure.
- `kms_getfb`'s two failures (`getfb-handle-protection`,
  `getfb2-handle-protection`) are `igt_aux-CRITICAL: ... igt_drop_root ...
  Failed assertion: getuid() == 0 / error: 1005 != 0` - the test needs uid 0 to
  drop privileges. Tooling, not driver.
- `kms_fb_coherency` and `kms_dirtyfb` SKIP (exit 77) with
  `No known gpu found for chipset flags 0x129 (other)`; IGT has no device-filter
  entry for `sm750hdmidrm`, and `IGT_FORCE_DRIVER=sm750hdmidrm` did not change
  it. Tooling/capability gap.
- Caveat: `kms_pipe_crc_basic` still cannot prove pixels on this driver, now
  for a different reason. Round 2 recorded that `src/` implemented no CRC
  source, so the subtest had nothing to enable. The driver now registers a
  `scanout` CRTC CRC source (`sm750_crtc_get_crc_sources`,
  `src/sm750_drm.c`) and a `sm750_scanout` debugfs dump that share one bounded
  VRAM read path. The `/dev/tty0` blocker that stopped the subtest in
  `kmstest_set_vt_graphics_mode` (section 8) has since been given an ACL
  (2026-11-18T12:08Z, `docs/ROOT-ACTIONS.md` section 4.1), so the access part is
  closed; no post-ACL IGT run is recorded, so the subtest is still unproven.
- Scope limit: same **stale pre-fix 0.5.9** module as S4; BEFORE half only.

### S7: `v4l-utils` (excluded)

- Package/version: `v4l-utils-1.32.0-1.fc43.x86_64`, available in `updates`;
  downloaded to `/mega/tmp/sm750/t3-tools`, not installed.
- Reason for exclusion: the `SE-DP750A-HDMI` board has one HDMI output driven
  by the SM750/SiI9024A and no V4L2 capture device. `v4l2-ctl --list-devices`
  could only enumerate unrelated host devices, so it cannot prove any driver
  claim. There is no capture node to exercise and no pass criterion that maps
  to this product.
- What is retained: `edid-decode` from the same RPM payload was used once on
  the world-readable sysfs EDID (S8). That is an EDID decode, not a V4L2
  capture test.

### S8: `edid-decode` (baseline reference only)

- Package/version: `edid-decode` from `v4l-utils-1.32.0-1.fc43.x86_64`,
  extracted into `/mega/tmp/sm750/t3/v4l`.
- Evidence: `docs/evidence/baseline/15-edid-decode.txt`.
- Status: reference capture from 2026-11-17, before T5. It is not a result row
  and is not used to claim a post-fix pass. It records the panel identity and
  extension-block checksum so later EDID comparisons have a baseline.

### S9: source-level blank-console diagnostic

- Command: `./tests/check-console-blank.sh` (also run by
  `tests/check-drm-policy.sh`, which is the 17th command of `make check`, so
  the recipe stays at 17). Takes an optional source path, defaulting to
  `src/sm750_drm.c`.
- Holds: `sm750_shadow_frame_is_blank()` exists and samples the shadow source
  on a coarse 16-row/16-pixel grid with a NULL-map bail-out and no allocation;
  the exact text `console framebuffer is blank` is emitted inside
  `sm750_pipe_enable()` after the `sm750_program_mode()` call; the line is
  behind a `static bool` latch so it prints once per module load; the guard
  contains no `return`/`goto`, so it cannot change behaviour.
- Negative controls, each planted on a temporary copy and rejected with exit 1:
  message deleted, diagnostic moved above the mode programming call, NULL-map
  bail-out removed, once-per-load latch removed.
- Status: PASS, `Console blank-frame diagnostics checks passed`.

### S10: root console-scanout content

- Command: `sudo ./tests/check-console-scanout.sh` or `make console-check`.
  Opt-in, outside `make check`, because it needs root, the card and a mounted
  debugfs; the target turns exit 77 into success.
- Holds: on a `KD_TEXT` foreground VT, 40 lines written to `/dev/tty0` leave a
  non-blank `sm750_scanout` window (nonzero bytes > 0), a `crc32` that is not
  the all-zero sentinel `0xe20eea22`, and an `offset` equal to
  `PANEL_FB_ADDRESS` in the register dump.
- Skip paths, each one `SKIP:` line and exit 77: no root, no debugfs, no SM750
  card, no readable `sm750_scanout`, no `/dev/tty0`, no `python3`, unreadable
  VT mode, and the measured precondition `KD_GRAPHICS`:
  `SKIP: foreground VT is KD_GRAPHICS; the kernel console discards output
  before fbcon, so an all-zero scanout window is expected - run this on a text
  VT`.
- Status: PASS on the card, 2026-11-20. With the foreground VT measured at
  `KDGETMODE` 0 (`KD_TEXT`) while `/sys/class/tty/tty0/active` still read
  `tty1`, the three assertions held: `sm750_scanout` `offset` 0 equal to
  `PANEL_FB_ADDRESS` 0x00000000, `nonzero` 28766 of 262144, `crc32` 0x0204dd04
  (not the all-zero sentinel 0xe20eea22). That is the check passing for real,
  replacing the earlier root-gate and `KD_GRAPHICS` SKIPs. Transcript:
  `docs/evidence/runtime/22-restore-fix-hardware-proof.txt` section 10. The
  script's own skip paths are unchanged, so it still exits 77 with a `SKIP:`
  line when the VT is `KD_GRAPHICS` or the caller is not root.

### S11: source-level restore-path invariants

- Command: `./tests/check-restore-path.sh` (also run by
  `tests/check-drm-policy.sh`, which is the 17th command of `make check`, so
  the recipe stays at 17). Takes an optional source directory and a
  `--single` mode the negative controls use.
- Holds, against `src/ddk750_display.c`, `src/ddk750_mode.c` and
  `src/sm750_drm.c`, four properties that the A32 RCA needs: the display
  transition wait takes a mask, compares `(last & mask) == (value & mask)`,
  re-pokes inside the poll loop, keeps the 100 ms budget and logs
  `want`/`mask`/`last`; the mode transition loop has no `cnt > N` cap, derives
  its budget from `mode_param->vertical_frequency` with a 20 ms floor, re-pokes
  per iteration and still returns `-ETIMEDOUT`; `sm750_pipe_disable()` assigns
  the display-off result, contains no unchecked display-off call and warns with
  the `PANEL_DISPLAY_CTRL` readback; the `sm750_pipe_enable()` fail path names
  the stage, calls `drm_crtc_vblank_on()` before `sm750_arm_vblank_event()` and
  prints the four registers on one `enable-fail state:` line.
- Negative controls, each planted on a temporary copy and rejected with exit 1:
  whole-register compare restored (`& ~mask`), event armed before
  `drm_crtc_vblank_on()`, display-off result discarded again, register-state
  line deleted.
- Status: PASS, `Restore path checks passed`; all four controls rejected. The
  behaviour it guards is in `docs/evidence/runtime/21-fbdev-restore-fix.txt`
  sections 1-5.
- The on-card half is `tools/sm750-restore-cycle.sh` (root only, outside
  `make check`): it repeats the client-exit restore trigger against the loaded
  module and fails on any of the three new log lines. Exit 0 clean, 1
  environment, 2 no scanout readback, 3 failure seen.
- Hardware result instead, recorded 2026-11-20 on the module built from this
  tree (srcversion `14ED4F27A83A6BB8AA445D2`, kernel 7.3.4-100.fc43), driven
  manually through the allowlisted sudo entries:
  - 30 consecutive `build/scanout-pattern /dev/dri/card0 white 2` exit/restore
    cycles: 30/30 succeeded, 0 failures.
  - 20 `modetest -M sm750hdmidrm -s 35@38:1024x768` mode changes, each followed
    by a client frame and exit: 20/20 completed.
  - 95 `staging enabled (` lines, the count of enable events that actually ran:
    75 at 1920x1080 (`4147200`) and 20 at 1024x768 (`1572864`).
  - `dmesg | grep -cE 'failed to enable HDMI mode|flip_done timed out|commit
    wait timed out|refcount_t: underflow|did not latch|panel did not
    acknowledge|enable-fail state|WARNING|BUG:'` -> 0. The pre-fix shape of run
    produced `failed to enable HDMI mode: -110` followed by `flip_done timed
    out`, `commit wait timed out` and a refcount underflow.
  - The T31 blank-console line fired once for the whole session, as the
    once-per-load latch intends.
- Why the harness form stays unexercised: its root check is a hard gate
  (`FAIL: must run as root`, exit 1, `tools/sm750-restore-cycle.sh:73`) and this
  session had no interactive root, so its 120-iteration run has not happened.
  The 50 cycles above reproduce the same trigger shape through the allowlisted
  helpers but do not exercise the harness's exit-code contract. Recorded in
  `docs/evidence/runtime/22-restore-fix-hardware-proof.txt` sections 5-11.

### S12: source-level test-card invariants

- Command: `./tests/check-test-pattern.sh` (also run by
  `tests/check-drm-policy.sh`, so `make check` stays at 17 commands). Takes an
  optional source file and a `--single` mode the negative controls use.
- Holds, against `src/sm750_drm.c`, the T37 fallback contract: `test_pattern`
  defaults to `auto`, `test_pattern_period_ms` to `5000` and
  `test_pattern_anim_ms` to `40`, all are `0644`, and their help names the three
  modes and both defaults; the painter skips a softscaled window, a missing
  pitch or line buffer, a mode below 320x200, a pitch larger than its line
  buffer and a frame that does not fit the VRAM left after the scanout offset;
  every row is padded to `scanout_pitch` and copied with `memcpy_toio()` through
  the scanout offset; both the RGB565 and the 32 bpp encodings exist; the bars,
  grayscale staircase, grid, sweep, crosshair, circle and border are all present;
  the paint message is exact; and the paint call sits after `sm750_program_mode()`
  and the blank-frame diagnostic and before `drm_crtc_vblank_on()`, with exactly
  one blank sample. It also holds the rotation: a `delayed_work`, initialised,
  phase advanced under `mode_lock`, no `drm_info` per tick, re-armed only with a
  live card and a delay, cancelled in `sm750_pipe_disable()`, in
  `sm750_pipe_update()` before the damage is queued, on the enable fail path and
  in `sm750_pci_remove()`, with the cancel as its first test-card action and
  with no one-shot upload skip.
- Holds the T38 animation: the disc's position, velocity and colour fields exist;
  the reset picks the 3 percent radius clamped to 24..64 px and speeds scaled
  from the frame height; the move inverts `test_pattern_disc_dx` and
  `test_pattern_disc_dy` on a bounce, clamps to `3 + reach` inside the border and
  advances the colour; a tick is two `sm750_test_pattern_rect()` calls around the
  bounding box and never a full-card rect; and the palette rotation is decided by
  the accumulated tick count against `test_pattern_period_ms`, not by every tick.
- Holds the T40 CRC-ownership contract (defect A36): arming a scanout CRC
  source cancels the card before `sm750_crc_arm()`, the paint decision returns
  false for any armed source and requires `!READ_ONCE(sdev->drm.master) && blank`
  otherwise, the tick re-checks the same flag under `mode_lock` before it
  paints, `sm750_pipe_update()` stops the card before any `goto event`, and no
  `test_pattern_fresh`-style one-shot exists anywhere in the file.
- Negative controls, each planted on a scratch copy and rejected with exit 1:
  default changed to `off`, paint call moved before `sm750_program_mode()`,
  softscale guard removed, row copy by width instead of pitch, rotation not
  cancelled on disable, rotation not cancelled on a client update, phase never
  advanced, a per-tick `drm_info`, period default changed to `0`, animation
  default changed to `0`, velocity never inverted, a `drm_info` inside the disc
  tick, the tick repainting the whole card, the paint decision ignoring an armed
  CRC source, arming the CRC source without cancelling the card, the tick
  ignoring the CRC flag, a one-shot upload skip in front of the cancel, and the
  paint condition dropping the userspace-master test.
- Status: PASS, `Test-pattern fallback checks passed`; all eighteen controls
  rejected. The behaviour it guards is described in
  `docs/evidence/runtime/23-test-card-fallback.txt`,
  `docs/evidence/runtime/25-test-card-animation.txt` and
  `docs/evidence/runtime/26-test-card-crc-fix.txt`. Colour bars and the 5 s
  palette jump were seen on the panel on 2026-11-20; the animated disc and the
  CRC-ownership fix have no on-panel observation yet, and the evidence files say
  so in a `NOT YET OBSERVED ON THE PANEL` section.

### S13: packaging-transcript ASCII gate

- Command: `./tests/check-rpm-dkms.sh` (not part of `make check`; it builds an
  RPM and a DKMS module).
- Why: the transcripts under `docs/evidence/packaging/` are committed tool
  output. On a localized host `rpm`/`rpmbuild` print translated messages, and
  nothing checked the produced files, so 11 non-ASCII lines in
  `01-rpmbuild.log`, 40 in `03-rpm-qlp.log` and 1 in `05-dkms-sandbox.log`
  (Russian dates and progress lines) were carried through several commits.
- Holds: `tests/check-rpm-dkms.sh:32-33` exports `LC_ALL=C LANG=C` for every
  command whose output reaches a transcript, so the capture is ASCII at the
  source and no output is scrubbed afterwards; `transcripts_ascii`
  (`tests/check-rpm-dkms.sh:89`, called at `:1002`) then walks `0[1-6]-*.log` and fails with the
  offending file and `grep -n` line numbers.
- Negative control: `plant_localized_evidence` appends one Russian `rpmbuild`
  status line, written as octal escapes so the gate script itself stays ASCII,
  to a copy of `01-rpmbuild.log`; `transcript_ascii` must reject that copy. It
  is counted in the run's planted-control total (7).
- Status: PASS, `OK: evidence transcripts 01-06: no non-ASCII byte, captured
  under LC_ALL=C`, `plant_localized_evidence: rejected`, zero non-ASCII lines
  in all six regenerated transcripts. The pre-fix shape reproduced the same
  counts (11/40/1) and failed the gate with exit 1. The
  `docs/evidence/packaging/0.5.9/` archive is the frozen transcript of the
  rejected 0.5.9 revision: regenerating it would fabricate a run that did not
  happen, so it is left unedited and the gate does not read it.

### S15: sm750-smi monitoring-tool gate

- Command: `./tests/check-sm750-smi.sh` (also the 18th recipe command of
  `make check`, `Makefile:49`). It takes no arguments and needs neither the
  card nor root. Scratch trees go under `${TMPDIR:-/mega/tmp/sm750/tmp}`.
- Holds: the tool is rebuilt from `tools/sm750-smi.c`; `--list-fields` lists
  the 27 supported fields exactly once and every one of them is queryable;
  nine synthetic trees under `--sysfs-root`/`--card`/`--proc-root` cover the
  full data set, an absent debugfs, a chmod-000 debugfs control (reason
  `needs root (debugfs)`), absent driver attributes (reason `driver attribute
  not present in this version`), a disconnected connector, an empty modes
  list, a 5000-byte `modes` file whose first line must still be read, and a
  malformed attribute (`12x4`, `abc`); `--strict` exits 0 when every field
  resolves and 3 with the reasons on stderr when one does not; a missing card
  node prints the PCI-only view and exits 2; CSV and JSON are parsed by
  `python3` rather than string-compared, and `--no-color` plus a non-tty
  never emit an ESC byte.
- Planted controls: a field listed in `--list-fields` with no getter (the
  table self-check exits 1), a hardcoded `0.6.2` driver version (fixture
  carries `9.9.9`), a field that prints `0` instead of `n/a` when the
  attribute is absent, and an ESC byte emitted under `--no-color`. Each is
  copied, patched and compiled into its own binary, and each must fail the
  gate for the stated reason; the script prints the observed failure.
- Status: PASS, `sm750-smi checks passed (27 fields, 11 fixtures, 5 planted
  controls)`. The real-run view is in the README.

### S16: sysfs attribute gate

- Command: `./tests/check-sysfs-attributes.sh` (called by
  `tests/check-drm-policy.sh`, which `make check` runs). It takes an optional
  source file and needs neither the card nor root. Scratch trees go under
  `${TMPDIR:-/mega/tmp/sm750/tmp}`.
- Holds: for each of the twelve names `sm750-smi` reads there is one
  `DEVICE_ATTR_RO()` and one `&dev_attr_*.attr` array entry; the block between
  the `BEGIN sysfs monitoring attributes` and `END sysfs monitoring attributes`
  markers lists exactly twelve attributes; `device_add_group()` appears once and
  is `devm_device_add_group(&pdev->dev, ...)` before
  `drm_dev_register()`; every `<name>_show()` takes its state from
  `dev_get_drvdata(dev)` behind an `if (!sdev)` guard, emits through
  `sysfs_emit()`, contains no sleep helper, and takes no lock other than
  `&sdev->mode_lock` with matched unlock count; the link-status call passes
  `clear_events = false` and `link_state_show()` carries all four state
  strings; `vblank_count_show()` reads `drm_crtc_vblank_count()` and the source
  keeps no second counter; `active_crtc_show()` defaults to `-1`;
  `crc_supported_show()` reports `SM750_CRC_SUPPORTED`, which is `1` only
  inside the `KERNEL_VERSION(7, 0, 0)` range that registers
  `.get_crc_sources` and has a `0` fallback.
- Planted controls: an attribute renamed so the tool cannot find it, the
  link-status call flipped to `clear_events = true`, `msleep()` inserted into a
  show function, the group registered on `&sdev->drm.dev` instead of
  `&pdev->dev`, and a spin lock taken in a show function. Each mutates a
  temporary copy and must exit non-zero naming the defect.
- Status: PASS, `Sysfs attribute checks passed (12 attributes, 5 planted
  controls)`. The live attribute values are in
  `docs/evidence/runtime/31-sysfs-attributes.txt`.

### S20: headless helper gate

- Command: `./tests/check-headless-helper.sh` (called by
  `tests/check-drm-policy.sh`, which `make check` runs). It takes an optional
  script path, defaults to `tools/sm750-headless.sh`, and needs neither the
  card, nor root, nor a compositor. `--self-test` runs the planted controls;
  plain invocation runs the assertions only. Scratch trees go under
  `${TMPDIR:-/mega/tmp/sm750/tmp}`.
- Holds: the helper is a POSIX `sh` script that passes `sh -n`; the mode
  dispatcher carries `probe`, `diagnose`, `weston`, `cage` and `kmscube` and
  every other word reaches `usage`, which exits 2; the BDF `0000:01:00.0` and
  the driver name `sm750hdmidrm` both appear and are compared in one
  `[ "$driver" = sm750hdmidrm ]` test; `export LIBSEAT_BACKEND=noop` is
  present and no export sets `builtin`; the compositor arms are read out of the
  switch body with comments stripped, so a flag is only credited where it is
  executed, and the weston arm must carry `--backend=drm`, `--drm-device=card0`
  and `--shell=kiosk-shell.so`, the cage arm must carry `-d` and must not carry
  `-s`, and the kmscube arm must carry `-c` and must not carry `-n`;
  `SECONDS` is rejected as non-numeric (`*[!0-9]*`) and clamped with `-ge 1`
  and `-le 600`; the verdict records `survived=0`, fails on
  `[ "$survived" -ne 1 ]`, computes `frames=$((vblank_after - vblank_before))`
  and fails on `[ "$frames" -le 0 ]`, writes `status=3` on both paths and keeps
  the sentence "a frame count alone never proves a compositor rendered";
  `trap cleanup EXIT` is installed and `kill -TERM` precedes `kill -KILL`; the
  script holds no absolute local path and no non-ASCII byte; section k pins the
  input isolation: `--mount --propagation private` and
  `-t tmpfs -o size=1M,mode=0755 tmpfs /dev/input` both appear, the isolation
  sentence and `00-plan.txt` are present, `isolate ` is reached from the weston
  arm and from the cage arm, `isolate ` is absent from the kmscube arm (which
  takes no input), the `/dev/input` mount line precedes the weston call line and
  the cage call line, `export WLR_LIBINPUT_NO_DEVICES=1` is still present and
  the script documents it as a wlroots variable (weston's DRM backend ignores
  it, so the namespace is the load-bearing guard - A49); section n drives
  `diagnose` against a synthetic DRM tree and requires every node of the
  device to be matched by device number rather than the literal `card0`, each
  inode printed, every holder line to name its node, and the fd tables the
  account cannot read to be counted (673 of 906 at the 2026-11-26 measurement)
  instead of silently skipped.
- Planted controls: `LIBSEAT_BACKEND` export deleted, `noop` changed to
  `builtin`, `-s` added to the cage arm, `-c 300` changed to `-n 300` in the
  kmscube arm, the `survived=0` assignment deleted, the
  `elif [ "$frames" -le 0 ]` branch disabled, the kmscube clean-exit branch
  turned into a failure, the kmscube exit code ignored so a crash reads as a
  pass, the lower clamp loosened from `-ge 1` to `-ge 0`, `isolate "$prog"`
  rewritten back to `exec "$prog"` in both compositor arms (the A49 incident:
  weston then opens the owner's `/dev/input/event*`), and the same rewrite in
  the cage arm only, so a single unprotected mode is caught; the six `x11`
  controls of S26; `console-restore-dropped` (the mutated helper no longer
  restores the recorded text VT - the A54 workaround); and
  `diagnose-card0-only` (a mutated `diagnose` that enumerates card0 alone).
  Each mutates a
  copy under the scratch directory and must exit non-zero naming the defect;
  the unmutated copy must pass.
- Status: PASS 2026-11-26, `Headless helper checks passed (14 assertions, 20
  planted controls)`; the `--self-test` run prints
  `Headless helper checks passed (14 assertions, 20 planted controls, self-test)`.
  The helper itself has not been run with the isolation in place: every mode
  needs root and the card, and the incident that produced A49 came from doing
  exactly that. The isolated run is in the NOT YET OBSERVED list of
  `docs/evidence/runtime/40-headless-input-isolation.txt`.

### S21: render-node gate

- Command: `./tests/check-render-node.sh` (called by
  `tests/check-drm-policy.sh:270-276`, which `make check` runs). It takes an
  optional repository directory and needs neither root nor a card; the live half
  reads `/sys/class/drm/renderD*` and only needs read access to the nodes.
  Scratch trees go under `${TMPDIR:-/mega/tmp/sm750/tmp}`.
- Holds: `src/sm750_drm.c` has exactly two `.driver_features = ` lines and both
  carry `DRIVER_RENDER`; no executable line (comment lines are skipped by the
  `awk` filter) carries `DRIVER_RENDER` without `DRIVER_MODESET`; and the
  `SM750_DRM_VERSION` define matches the `readonly version=` line of
  `build-package.sh`. The live assertion selects the `renderD*` node whose
  `device/driver` resolves to `sm750hdmidrm` and requires the matching
  `/dev/dri/renderDN` to be a character device writable by the invoking user.
  When no such node exists the live half prints
  `SKIP: the running module does not advertise a render node yet: install 0.6.5 or newer`
  and the gate still exits 0, so the gate is useful before the module is
  installed and becomes a real assertion the moment a 0.6.5 module is loaded.
- Planted controls: `render_dropped` (the `DRIVER_RENDER` flag removed from one
  of the two lines), `render_only` (a synthetic `DRIVER_RENDER` on a line
  without `DRIVER_MODESET`) and `version_drift` (the packaged version moved
  while the module define stayed). Each mutates a copy under the scratch
  directory and must exit non-zero naming the defect.
- Status: PASS on 2026-11-25. The plain run prints
  `Render node checks passed (7 assertions, 5 planted controls)` and the
  `--self-test` run prints
  `Render node checks passed (12 assertions, 5 planted controls)`: seven
  assertions (six source-level and one live) plus five planted controls. The
  earlier 0.6.5 run recorded five assertions and three controls. The gate adds
  no recipe command, so `make check` still runs 18 commands. The observed node
  and the kwin outcome are in `docs/evidence/runtime/36-render-node.txt`; the
  modifier assertions are S23.

### S22: a full Plasma Wayland session (observed by hand, not gated)

- Command: none. There is no script and no `make` target for this scenario, and
  no automated gate exists for it or is proposed; the recipe is the environment
  block of `docs/PLASMA-WAYLAND.md` section 4 and of
  `docs/evidence/runtime/37-plasma-wayland.txt` section 3, ending in
  `startplasma-wayland` as uid 1005 with no root.
- Holds: a full Plasma session (startplasma-wayland, kwin_wayland with
  `--socket wayland-0`, Xwayland `:1` and plasmashell) runs on `/dev/dri/card0`
  in a remote session that has no logind seat, with the SM750's own render node
  as `KWIN_RENDER_NODES`, and the panel scans a composited frame: `sm750-regs`
  reports `PANEL_FB_ADDRESS 0x003f4800`, pitch 3840, RGB565, and
  `sm750-crc dump` returns `offset 4147200`, `length 262144`,
  `nonzero 262144`, `crc32 0x976e751b` unchanged over three dumps of a static
  desktop. The earlier kwin-only run read `nonzero 0`, `crc32 0xe20eea22` and
  `PANEL_FB_ADDRESS 0x00000000`, so the difference is the presence of a
  presenting session, not a sampling artefact.
- Planted controls: none. Nothing is mutated and nothing is asserted
  mechanically; the two contrast states (a presenting session and a kwin-only
  session) are the comparison, and both are archived.
- Status: OBSERVED, 2026-11-25, module 0.6.5 on kernel `7.3.4-100.fc43.x86_64`
  with kwin and Plasma `6.7.5` and Mesa `25.3.6`. This is evidence, not a gate:
  it cannot be re-run by `make check` and no CI job reproduces it. The session
  could not be driven -- no input device is readable by this account -- and
  screencast, full-frame readback, interaction latency, multi-monitor and VT
  switching are unmeasured. The X11 contrast is in the same file: X11 runs but
  cannot composite, because the server's GLX is DRISWRAST without
  `GLX_EXT_texture_from_pixmap`.

### S24: VT hot-reload helper gate

- Command: `./tests/check-vt-helper.sh` (called by `tests/check-drm-policy.sh`,
  which `make check` runs). It takes an optional script path, defaults to
  `tools/sm750-vt.sh`, and needs neither root, nor the card, nor a writable
  sysfs. `--self-test` runs the planted controls; plain invocation runs the
  assertions and the controls the way the other gates do. Scratch trees go
  under `${TMPDIR:-/mega/tmp/sm750/tmp}`.
- Holds, in thirteen printed sections: (a) the helper exists, starts with
  `#!/bin/sh` and passes `sh -n`; (b) `show`, `off` and `on` are the only modes,
  `*) usage ;;` catches the rest and `usage` exits 2; (c) `[ "$(id -u)" -eq 0 ]`
  exists and the refusal names the problem, so an unprivileged `show` stays
  allowed while `off` and `on` do not; (d) the target comes from
  `resolve_target`, which globs `"$VTCLASS"/vtcon*`, refuses
  `[ "$count" -gt 1 ]` and is cross-checked against the PCI driver, and no
  executed line carries a `vtconN` literal (a comment may name one as an
  example, which is why the assertion filters comment-only lines); (e) the
  detach writes `0` and the restore writes `1` through the single writer
  `printf '%s\n' "$2" >"$1/bind"`, and every write is read back with
  `[ "$(cat "$1/bind" ...)" = "$2" ]`; (f) `restore_all` exists, writes `bind`
  1, ends in an explicit `return 0`, and the single EXIT trap is exactly
  `trap 'rc=$?; if [ "$rc" -ne 0 ]; then restore_all; fi; exit $rc' EXIT`, and
  `FINISHED=1` disarms it after a successful run; (g) the holder scan walks
  `/proc/[0-9]*`, the unload is gated on `if [ -n "$h" ]; then` and the refusal
  names the reason, and the line number of `"$MODPROBE" -r sm750hdmidrm`
  precedes the line number of `"$MODPROBE" sm750hdmidrm`; (h) `is missing after
  the load` appears after the load line, so a load without a version attribute
  fails instead of passing; (i) `off` reports `module unloaded` and a failed
  restore names the `on` mode; (k) the A51 PCI step: `write_dev unbind` and
  `write_dev bind` are present, `refcnt before any change` and `refcnt after
  the unbind` are printed, `if [ "$rc_after" != 0 ]` fails the run when the
  refcount did not drop, `if ! dev_bound; then` refuses an unbound device, the
  six calls appear in the order detach, unbind, unload, load, rebind, console
  (compared inside the `off` body only, because the restore function
  legitimately repeats two of them), and the restore function itself orders
  module, device, console and is armed by `mod_down` and `dev_unbound`;
  (l) the holder scan is pinned to node identity: the card and render nodes are
  addressed through `/dev/dri/by-path/pci-0000:01:00.0-card` and
  `-render`, `node_inode` resolves a path to a `dev:inode` pair with
  `stat -L -c`, `holders` compares that pair for the card and the render node
  and prints the matched node name for the operator, the reason string
  `holder scan pinned to the card identity, not to a node name` is present, and
  no executed line globs a node name (`*cardN*` in a comment is allowed, which
  is why the check filters comment-only lines); (j) the section counter.
- Planted controls: the EXIT trap rewritten to `exit $rc` only, so fbcon is
  left detached after a failed unload (`never-restore`); `TARGET` pinned to
  `/sys/class/vtconsole/vtcon1` before the resolve call (`hardcoded-vtcon`);
  the `modprobe -r` and `modprobe` bodies swapped so the load runs first
  (`modprobe-order-reversed`); the `is missing after the load` block deleted so
  a failed load reads as a success (`version-readback-removed`); and
  `if [ -n "$h" ]` rewritten to `if [ -n "" ]`, which drops the holder gate and
  lets the unload run while a process holds the card
  (`holder-check-dropped`); the `write_dev unbind` block deleted so the
  refcount never drops (`pci-unbind-dropped`); the re-probe block replaced by a
  bare `:`, so the device stays unbound after the load (`pci-rebind-dropped`);
  the second refcount print deleted, so the operator never sees the number that
  explains a failure (`refcount-not-reported`); and the device restore removed
  from the trap, so a failure leaves the card without a driver
  (`trap-restores-fbcon-only`); and the identity comparison rewritten back into
  a `*card0*` name glob, so the scan reports no holder while the card is really
  held (`holder-scan-name-glob`, the holder-scan name-glob failure mode). Each
  mutates a copy under the scratch directory and must exit non-zero with a
  message naming the defect; the unmutated copy must pass, otherwise the
  controls prove nothing.
- Status: PASS 2026-11-26, `VT helper checks passed (13 assertions, 10 planted
  controls)`; the `--self-test` run prints the same line with `, self-test`.
  The first live run of the installed helper failed and is recorded as defect
  A51: `vtcon*/bind` 0 detaches the console but does not release the framebuffer
  reference, so `modprobe -r` was still refused with
  `modprobe: FATAL: Module sm750hdmidrm is in use.`. Section k and the four new
  controls pin the corrected sequence, and the reload is still in the NOT YET
  OBSERVED list of `docs/evidence/runtime/41-vt-hot-reload.txt` (section 7
  records the failed attempt; attempt 2 needs the refreshed helper installed).

### S26: headless helper gate, `x11` arm

- Command: `./tests/check-headless-helper.sh`; `./tests/check-headless-helper.sh --self-test`
  runs the same gate under the planted controls. It is also reached from
  `make check` through `tests/check-drm-policy.sh`, and adds no recipe command,
  so the recipe stays at 18.
- Holds, in section l of the gate: the generated config contains
  `Section "ServerFlags"`, `AutoAddDevices` off, `AutoAddGPU` off,
  `DontVTSwitch` true, `DontZap` true, `Section "Device"` with
  `Driver "modesetting"`, the `kmsdev` of the card, `AccelMethod` none and
  `ShadowFB` true, and `Section "Screen"` plus `Section "ServerLayout"`; no
  `InputDevice` section and no `AutoAddDevices` true anywhere; the arm execs
  `/usr/libexec/Xorg` rather than a wrapper; it `cd`s into the run directory and
  passes a bare `-config` filename, with absolute paths and `..` elements
  rejected; it passes `-sharevts -novtswitch` and `-nolisten tcp`; it clamps the
  run length; and the session script it generates unsets `KWIN_DRM_DEVICES`,
  `KWIN_RENDER_NODES`, `__GLX_VENDOR_LIBRARY_NAME`, `KWIN_DISABLE_VULKAN`,
  `KWIN_COMPOSE`, `GBM_BACKEND`, `VK_DRIVER_FILES` and `VK_ICD_FILENAMES`
  before it execs `startplasma-x11`. The gate count is 14 assertions, section
  `l` being the one that inspects this arm, and 20 planted controls.
- Planted controls: six are x11-specific - `x11-sharevts-dropped` (a missing
  `-sharevts` would allocate a VT and take the owner's console),
  `x11-input-device` (an `InputDevice` section would let a root server read the
  owner's keyboard), `x11-abspath-config` (an absolute `-config` is refused
  under elevated privileges), `x11-primarygpu-reintroduced` (the unused
  Device-section `PrimaryGPU` the log warns about), `x11-env-note-dropped`
  (the plan would stop
  naming the environment that costs four crashes) and
  `x11-session-script-unset-dropped` (the generated script would inherit the
  NVIDIA selection). All six are rejected, alongside the twelve controls of
  the other modes, `console-restore-dropped` (the text-VT restore removed -
  the A54 workaround) and `diagnose-card0-only`, twenty in all.
- Status: gated statically, then run once as root on 2026-11-26 with the
  installed helper (sha256
  `bef39ba73cacdbcce93bc7319203689f98947a7556484d8cd51d06faf0591df7`, identical
  to the tree copy): `sudo -n /usr/local/sbin/sm750-headless x11 240` in run
  directory `/mega/tmp/sm750/headless/20261126T125401Z-x11` brought the server
  up on `:1` in 4 s with `modeset(0): Option "kmsdev" "/dev/dri/card0"`, the
  session ran as `coder` under `dbus-run-session` with the eight variables
  absent, `kwin_x11` held pid 1979033 at t=20 s, 40 s and 60 s with zero
  `crashing` lines, `card0-HDMI-A-1` read `connected` and `enabled=enabled`,
  `PANEL_CURRENT_LINE` advanced (`0x00000419`), and a 1920x1080 `x11grab`
  capture was 1836586 bytes. The transcript is section 12 of
  `docs/evidence/runtime/43-plasma-x11.txt`; the walkthrough is
  `docs/PLASMA-X11.md`.
- Harness lessons a future run must repeat. (a) A stale `/tmp/.X1-lock` aborts
  the server with `(EE) Server is already active for display 1`, and a live
  orphan `Xvfb :1` aborts it with
  `_XSERVTransSocketUNIXCreateListener: ...SocketCreateListener() failed` and
  `(EE) Cannot establish any listening sockets - Make sure an X server isn't
  already running`; the harness must remove the stale lock and kill the orphan
  by pid, and `pkill -x` cannot match names longer than 15 characters. (b)
  Killing the `sudo` process does not stop the helper - the root child runs
  until its own `seconds` value expires - so an early teardown needs a short
  `seconds`, not a kill. Both cost one failed attempt before the 2026-11-26
  run succeeded.
- Limits unchanged: no input device is opened by design (the log's
  `Failed to load module "mouse"` and `"kbd"` lines are that design), and the
  server has no GLX, so kwin composites through XRender on llvmpipe - the
  panel observation is software-composited, not accelerated, and `plasmashell`
  itself was not sampled for.

### S27: PM test helper gate

- Command: `./tests/check-pmtest-helper.sh`; `./tests/check-pmtest-helper.sh
  --self-test` runs the same gate under the planted controls. It is also reached
  from `make check` through `tests/check-drm-policy.sh`, and adds no recipe
  command, so the recipe stays at 18.
- What it protects: the helper runs the host-wide cycle that P1 needs, and the
  host has no S3 (ACPI reports S0 S4 S5 only and `/sys/power/mem_sleep` is
  `[s2idle]`, so `mem` and `freeze` are the same state and `freeze` is the
  correct spelling). The driver's callbacks are reached through
  `/sys/power/pm_test` instead, which is a global: a forgotten level turns every
  later real suspend into a test until reboot, and the fingerprint is the line
  `suspend debug: Waiting for`. The gate therefore pins the two properties that
  keep that window closed - the EXIT trap always writes `none` with a readback,
  and the root check precedes the first write - plus the level list, the journal
  snapshot before the freeze, and the verdict.
- Holds, in sections a..i of the gate: `#!/bin/sh` and `sh -n`; the three
  subcommands and `exit 2` for anything else; the level list
  `none|core|processors|platform|devices|freezer` with an unknown level reaching
  `usage`; `require_root` containing the `id -u` test and `must run as root`,
  called before the first `> "$PMTEST"`; the `cleanup` body writing
  `printf 'none\n' > "$PMTEST"`, calling `read_pm_test` and printing
  `readback after cleanup`, with the `trap 'cleanup; exit $?' EXIT` armed before
  the level write; the readback parsing the bracketed level list
  (`[none] core ...`, which is what this kernel prints) with a first-field
  fallback; `journal_before=` before `echo freeze > "$STATE"` and
  `journal_before + 1` when the delta is selected; the four verdict reductions
  (`suspend_complete -ge 1`, `resume_complete -ge 1`, `failed -eq 0`,
  `stats_same`); the `suspend_stats` counters read from the directory entries
  `fail`, `failed_*` and `last_failed_*` that this kernel publishes, with
  `status` printing the same directory; no `fb0` or `/dev/fb` outside a comment;
  and the no-S3 explanation in the usage.
- Planted controls, six, each deleting a property rather than a sentence:
  `trap-removed` (an interrupted run would leave `pm_test` armed),
  `level-validation-removed` (any string would be written to `pm_test`),
  `readback-removed` (the armed level would be trusted, not read),
  `verdict-without-completion` (`PASS` without both completion lines),
  `journal-snapshot-removed` (the whole boot log would be read, so an older
  cycle could satisfy the verdict) and `stats-file-only` (a `grep` on the
  `suspend_stats` directory returns nothing, so a failing cycle would pass).
  A pristine copy must still be accepted.
- Limits: static only. It writes no sysfs, suspends nothing, needs no root and
  never runs the helper; a green S27 says the helper cannot leave the machine in
  a test mode and cannot report a false `PASS`, not that the device left D0. The
  cycle it guards ran on 2026-11-27 at 16:12 and returned `verdict: PASS` with
  the four edges (the S27 row and `docs/ROOT-ACTIONS.md` section 3.14 record the
  values, `docs/evidence/runtime/49-pmtest-devices-cycle.txt` the transcript).

## 3. `make check`: the recipe commands

Since 2026-11-22 the recipe has 18 commands: `./tests/check-sm750-smi.sh`
(`Makefile:49`) is appended after `python3 tests/test-staging-results.py`.
The captures below, in section 4 and in
`docs/evidence/baseline/13-make-check-count.txt` record 17 and stay as they
were written.


Exact environment for this run:

```sh
export PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm
export LD_LIBRARY_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64
export C_INCLUDE_PATH=/mega/tmp/sm750/t3/libdrm/usr/include
make check KDIR=/lib/modules/7.3.3-100.fc43.x86_64/build CC=/usr/bin/gcc
```

The `check` prerequisites (`Makefile:30-31`) first build the module and three
test binaries (`Makefile:56-64`); the `check-deps` preflight (`Makefile:17-28`)
runs before them. Those are prerequisites, not recipe commands. The 17
commands below are `Makefile:32-48` and their observed results in
`01-make-check.log`:

| # | Command (Makefile line) | Observed result in `01-make-check.log` | Verdict |
| --- | --- | --- | --- |
| 1 | `./tests/check-drm-module.sh src/sm750hdmidrm.ko` (:32) | `SKIP` for the live probe (uid 1005, `/dev/dri/card0`); metadata checks passed | PASS (probe GAP) |
| 2 | `./tests/check-drm-policy.sh` (:33) | `DRM mode policy checks passed` (the CRC uapi gate it now calls prints `CRC uapi gate and negative controls passed` first, and the A42 gate prints `Sii902x readiness and I2C recovery checks passed`) | PASS |
| 3 | `./tests/check-drm-xorg-config.sh` (:34) | `DRM Xorg isolation checks passed` | PASS |
| 4 | `./tests/check-drm-packaging.sh` (:35) | `Unified DRM package checks passed` | PASS |
| 5 | `./tests/check-release-version.sh` (:36) | `Release version consistency checks passed: 0.5.9` | PASS |
| 6 | `./tests/check-softscale-map.sh` (:37) | `Softscale 2560/2464-to-2048 mapping checks passed` | PASS |
| 7 | `./tests/check-softscale-sharpen.sh` (:38) | `Softscale 8% contrast sharpening checks passed` | PASS |
| 8 | `./tests/check-softscale-codegen.sh src/sm750_dither.o` (:39) | `Softscale generated-code checks passed` | PASS |
| 9 | `./tests/check-hardware-cursor.sh` (:40) | `Hardware cursor plane checks passed` | PASS |
| 10 | `./tests/check-shadow-dma.sh` (:41) | `Shadow DMA safety checks passed` | PASS |
| 11 | `./tests/check-backbuffer-staging.sh` (:42) | `Full-frame backbuffer staging checks passed` | PASS |
| 12 | `./tests/check-shadow-async.sh` (:43) | `Asynchronous shadow mailbox checks passed` | PASS |
| 13 | `./tests/check-shadow-source-damage.sh` (:44) | `Shadow source-difference damage checks passed` | PASS |
| 14 | `python3 tests/test-vblank-timer.py` (:45) | Six schedules passed: normal, time-lock, event-lock, superseded, cancel-enable, sync-stop | PASS |
| 15 | `./tests/test-bbdither-rgb565` (:46) | `bbdither RGB565 checks passed` | PASS |
| 16 | `./tests/test-scale-optimizations` (:47) | `Packed scaler, unrolled span and fixed-sharpen checks passed` | PASS |
| 17 | `python3 tests/test-staging-results.py` (:48) | `Ran 4 tests ... OK` | PASS |

No command is excluded. Command 1's live probe was skipped in the recorded run
for one documented reason: the read-write `card0` guard in
`tests/check-drm-module.sh:295-296` refused, and the node was denied to this
user at the time. The script prints
that the skip is not a pass. The skipped probe is tracked as GAP row R12 in
section 4, not hidden inside the PASS row. Since T10 added the udev ACL for
`coder`, that probe could now be re-run; T10 did not re-run `make check`, so
R12 stays GAP until it is.

Without the libdrm chain, `check-deps` (`Makefile:18-23`) exits 1 with the
install hint; the pre-fix failure at `tests/check-vblank.c:11` is recorded in
`10-defect-before-after.log` (A03 section).

## 4. Recorded results

All rows are post-T5 runs or post-T5 probes on 2026-11-18. PASS rows point at
an existing file under `docs/evidence/builds/`. GAP rows point at the archived
denial or at the probe transcript in section 9.

This R table is the **0.5.9 record**: every row was run against the stale
pre-fix module described in section 1, and the rows are kept as they were. The
0.6.0 re-runs are a separate record and are not folded into these rows:
`docs/evidence/builds/13-make-check-0.6.0.log` (17 commands, exit 0),
`14-check-all-kernels-0.6.0.log` (Built 9), `15-kernel-6.17.1-0.6.0.log`
(Built 3), `16-build-package-0.6.0.log`, `17-check-rpm-dkms-0.6.0.log`,
`19-cursor-alpha-fix.log` for the build and packaging chain, and
`docs/evidence/runtime/16-modeset-0.6.0.txt`, `17-kmscube-0.6.0.txt`,
`18-kernel-log-0.6.0.txt`, `19-igt-0.6.0.txt` for the runtime tiers, with
`22-dkms-stale-purge.txt` for the installed-state cleanup.

| # | Run | Kernel | Tool version | Command | Evidence | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | `make check`, 17 commands | 7.3.4 running, KDIR 7.3.3 | GCC 15.3.1, libdrm 2.4.134 | `make check KDIR=/lib/modules/7.3.3-100.fc43.x86_64/build CC=/usr/bin/gcc` | `docs/evidence/builds/01-make-check.log` | PASS |
| R2 | Build matrix, 9 combinations | 7.3.4 running; headers 7.2.15/7.3.3/7.3.4 | GCC 15.3.1 | `JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh` | `docs/evidence/builds/02-check-all-kernels.log` | PASS |
| R3 | Build matrix, 3 combinations | headers 7.2.15 | GCC 15.3.1 | `./tests/build-all-kernels.sh /lib/modules/7.2.15-100.fc43.x86_64/build` | `docs/evidence/builds/03-kernel-7.2.15-100.log` | PASS |
| R4 | Build matrix, 3 combinations | headers 7.3.3 | GCC 15.3.1 | `./tests/build-all-kernels.sh /lib/modules/7.3.3-100.fc43.x86_64/build` | `docs/evidence/builds/04-kernel-7.3.3-100.log` | PASS |
| R5 | Build matrix, 3 combinations | headers 7.3.4 | GCC 15.3.1 | `./tests/build-all-kernels.sh /lib/modules/7.3.4-100.fc43.x86_64/build` | `docs/evidence/builds/05-kernel-7.3.4-100.log` | PASS |
| R6 | Build matrix, 3 combinations | headers 6.17.1-300 (extracted) | GCC 15.3.1 | `./tests/build-all-kernels.sh /mega/tmp/sm750/t5/k617/usr/src/kernels/6.17.1-300.fc43.x86_64` | `docs/evidence/builds/06-kernel-6.17.1.log` | PASS |
| R7 | Package build | 7.3.4 | `dpkg-deb` (host) | `./build-package.sh` | `docs/evidence/builds/07-build-package.log` | PASS |
| R8 | Release audit | 7.3.4 | `tests/audit-release.sh` | `./tests/audit-release.sh` | `docs/evidence/builds/08-audit-release.log` | PASS |
| R9 | Warning scan of all build logs | 7.3.4 | GCC 15.3.1 | `grep -nE '(warning\|error):' docs/evidence/builds/*.log` | `docs/evidence/builds/11-warnings-scan.log` | PASS |
| R10 | Defect before/after verification | 7.3.4 | GCC 15.3.1 | `bash /mega/tmp/sm750/t5/mk-before-after.sh` | `docs/evidence/builds/10-defect-before-after.log` | PASS |
| R11 | Register-dump read attempt | 7.3.4 | module 0.5.9 built for 7.3.3 | `cat /sys/kernel/debug/dri/0/regs` | `docs/evidence/builds/09-register-dump.log` | GAP |
| R12 | Live vblank probe (`check-vblank`) | 7.3.4 | libdrm 2.4.134 client | `tests/check-vblank /dev/dri/card0 60` (skipped by `check-drm-module.sh`) | `docs/evidence/builds/01-make-check.log:41` | GAP |
| R13 | `modetest` connector dump and modeset | 7.3.4 | drm-utils 2.4.134-1 | `modetest -c`, `modetest -p`, `modetest -s 35@38:1920x1080`, `modetest -s 35@38:1024x768-60` | `docs/evidence/runtime/01`-`04` | PASS (pre-fix baseline) |
| R14 | `kmscube` render | 7.3.4 | kmscube 0-11.20241006.git311eaaa | `tail -f /dev/null \| kmscube -D /dev/dri/card0 -c 300` | `docs/evidence/runtime/05-kmscube.txt` | PASS (pre-fix baseline) |
| R15 | IGT KMS subset | 7.3.4 | igt-gpu-tools 2.4-1 | 11 binaries, `--device /dev/dri/card0` | `docs/evidence/runtime/06-igt.txt` | FAIL (1 real) + GAP (VT-blocked) |
| R16 | Modeset before/after state capture | 7.3.4 | drm-utils 2.4.134-1 | `modetest -p` before, during and after each `-s` | `docs/evidence/runtime/01`, `04` | PASS (pre-fix baseline) |
| R17 | Kernel-log capture during runtime tiers | 7.3.4 | `dmesg`, `journalctl -k` | `sudo -n dmesg`, `sudo -n journalctl -k -b -q --no-pager` | `docs/evidence/runtime/07-kernel-log.txt` | FAIL (1 error episode, not reproducible) |

Counts: 13 PASS, 2 FAIL, 3 GAP. The PASS rows are backed by
`01-make-check.log`, `02-check-all-kernels.log`,
`03-kernel-7.2.15-100.log`, `04-kernel-7.3.3-100.log`,
`05-kernel-7.3.4-100.log`, `06-kernel-6.17.1.log`,
`07-build-package.log`, `08-audit-release.log`, `11-warnings-scan.log`,
`10-defect-before-after.log` and, for R13/R14/R16, the `docs/evidence/runtime/`
files. The FAIL rows are R15 (`kms_addfb_basic` `size-max`, errno 22 on
`ADDFB2`) and R17 (one kernel error episode at `[8523..8586]`); both are
backed by `06-igt.txt` and `07-kernel-log.txt`.

The two FAIL rows are the first failures recorded in this document. Both belong
to the **stale pre-fix 0.5.9** module and are the BEFORE half of the
before/after pair; neither is a 0.6.0 result.

A GAP is recorded when the operation was denied or a required device node was
absent; it is not a driver failure and is not upgraded to PASS by inference.
R11 (debugfs `regs`, `/sys/kernel/debug` is 0700) and R12 (live vblank probe
skipped by `check-drm-module.sh`) remain GAP; the third GAP is the VT-blocked
IGT subset inside R15, which never reached the driver.

## 5. Acceptance criterion 3: display behaviour on the panel

Claim under test: this driver drives the connected `card0-HDMI-A-1` panel at a
requested mode and outputs the expected pixels.

Evidence ladder, strongest last. The first three rungs now exist for the
pre-fix baseline; the pixel rungs do not.

| Evidence | What it proves | Recorded? |
| --- | --- | --- |
| Sysfs connector state and EDID | The driver registered the connector, read a 256-byte EDID, reports `connected`/`enabled`/`dpms: On` and 28 modes with 1920x1080 preferred. This is state description, not a modeset test: it is the state left by whatever configured the display before the test and does not prove this build produced it. | Yes, `docs/evidence/baseline/03-connector.txt`, `02-edid.txt`, `15-edid-decode.txt` (pre-T5 baseline) |
| `modetest -c` | libdrm can open the KMS device and enumerate connector 35, encoders, CRTCs and planes with their properties. | Yes, `docs/evidence/runtime/02-modetest-connector.txt` (pre-fix baseline, exit 0) |
| `modetest -s 35@38:1920x1080` | The atomic commit for the requested mode is accepted by the driver and the connector stays enabled with DPMS On. | Yes, `docs/evidence/runtime/04-modeset.txt` (pre-fix baseline; the alternate mode is programmed but reverted on client exit) |
| Framebuffer content readback | A known pattern written through the driver can be read back. The driver has a read path (T26): the `sm750_scanout` debugfs dump and the `scanout` CRTC CRC source read the bounded visible scanout region out of VRAM through one function, and `tests/check-scanout-crc.sh` (`make crc-check`) asserts that entries arrive, that the CRC is stable for a static frame, that it changes with the content, and that the dump agrees with the CRC path. The readback is of the scanout source buffer, not of the panel. | Yes, as root: `sudo -n /usr/local/sbin/sm750-crc-cycle --diag` exits 0 and prints `RESULT: scanout CRC check passed` with black 0xe20eea22 against white 0x06cf606c and 262144 of 262144 nonzero bytes for the white frame; transcript `docs/evidence/scanout/09-crc-single-owner.txt` section 5. The check keeps its drawer alive while it samples, because DRM's lastclose restores the fbdev console frame and would otherwise replace the pattern with the console's own black frame (same file, section 3b). A55 (fixed 2026-11-26) was a reader defect in this path: after the last client exits the CRTC mode is `0x0`, and the dump printed `scanout readback, 0x0 pitch 3840` until `sm750_crc_region_missing()` rejected a zero mode and `sm750_pipe_disable()` cleared the scanout geometry; `tests/check-drm-policy.sh` assertions R3-R5 pin it. |
| Scanout CRC | A CRC of the CRTC output proves the pixel stream at the connector; a CRC of the scanout source bytes proves only the buffer fed to the engine. The driver implements the `scanout` source over VRAM (`sm750_crc_work_fn()` calls `drm_crtc_add_crc_entry(crtc, true, frame, &crc)` once per frame) and exposes it through the three `drm_crtc_funcs` CRC callbacks; DRM core owns the files, publishing `crtc-N/crc/control` and `crtc-N/crc/data` and routing both to those callbacks. The driver hosts no crc debugfs file of its own: the T28 copy shadowed core's state, so a fresh open of `crc/data` failed with EINVAL, and it was deleted in T30. This is the second kind of CRC. The first is still unavailable: nothing on this host reads the emitted pixel stream. | Yes for the scanout source. Static gate `tests/check-crc-uapi.sh` (also run from `tests/check-drm-policy.sh`, so from `make check`) asserts the three callbacks and their wiring, that no crc `debugfs_create_*` call is left in `src/`, the `has_frame` push, the `auto` source name, the re-arm outside the region check and `values_cnt = 1`, and rejects seven planted defects. Runtime: `crc/control` reads `scanout` and `scanout*`, no `crc/source` exists, and `crc/data` returns entries - `docs/evidence/scanout/09-crc-single-owner.txt`. Proof of the emitted stream stays `GAP`. |
| External capture or photograph of the panel | The only end-to-end proof that the requested pixels reached the display. No capture hardware is attached to this host. | No |

Why connector status alone is insufficient: `enabled` and `dpms: On` are
attributes of the connector state, not a statement that the CRTC scanned the
expected framebuffer. The current state could come from the boot firmware, the
fbdev console, or the previously installed module. None of those is the
post-fix build under test.

AC-3 is therefore **GAP for pixel proof**, and **partly proven for the
modeset itself** on the pre-fix baseline: the driver accepts the commit, the
alternate mode is really programmed (dmesg staging bytes) and then reverted on
client exit, and the panel returns to its original mode. What remains unproven
is what the panel actually shows. The client-exit revert itself produced
defect A54: when the last client removes its framebuffer the core disables
the CRTC, the fbdev last-close restore did not commit on about a dozen exits,
and the console could not repaint because the VT was in `KD_GRAPHICS`, so the
panel stayed dark until a text VT was restored. Remaining closing sequence:

```sh
# already done in T10: udev ACL on /dev/dri/card0 lets uid 1005 open card0
modetest -c
modetest -s 35@38:1920x1080
modetest -s 35@38:1024x768-60
modetest -s 35@38:1920x1080
# still blocked: pixel proof needs an emitted-stream CRC source or an
# external capture; kms_pipe_crc_basic cannot help without one. (T26 added a
# scanout-source CRC, which proves the buffer, not the emitted stream.)
```

## 6. Acceptance criterion 5: kernel-range and regression coverage

Claim under test: the 6.17+ support statement is backed by a warning-clean
build and the regression suite across the declared kernel range, for all
three scanout defaults.

What proves it:

- A build exits 0 for each kernel tree and each of the three formats
  (`rgb565-bbdither`, `xrgb8888`, `rgb565`), with the format macro verified in
  the object command line (`tests/build-all-kernels.sh:41-54`).
- The `rgb565-bbdither` build of each tree runs the full 17-command `check`
  suite (`tests/build-all-kernels.sh:33-34`), not only the metadata checks.
- The warning scan attributes no warning or error to `src/*.c` or `src/*.h`
  (`11-warnings-scan.log`).
- The declared floor 6.17 is built, not merely declared.

Recorded:

| Coverage | Result | Evidence |
| --- | --- | --- |
| 7.2.15, three formats | Built 3, exit 0 | `03-kernel-7.2.15-100.log` |
| 7.3.3, three formats | Built 3, exit 0 | `04-kernel-7.3.3-100.log` |
| 7.3.4, three formats | Built 3, exit 0 | `05-kernel-7.3.4-100.log` |
| 6.17.1-300, three formats | Built 3, exit 0 | `06-kernel-6.17.1.log` |
| All installed trees in one run | Built 9, exit 0 | `02-check-all-kernels.log` |
| Driver-source warnings | none | `11-warnings-scan.log` |

Limits of this evidence:

- Only the dithered RGB565 build receives the full suite. XRGB8888 and plain
  RGB565 receive the module metadata and compile-flag checks; that is the
  script's design (`tests/build-all-kernels.sh:30-39`), not an accidental skip.
- 6.17.1-300 is an offline build against extracted headers. It is not
  installed or booted.
- 6.18, 7.0 and 7.1 header trees named in the README compatibility paragraph
  are not installed on this host, so that part of the matrix is not
  re-verified post-T5.
- 7.2.13-100 no longer has a build link; `readlink -f
  /lib/modules/7.2.13-100.fc43.x86_64/build` returns nothing on 2026-11-18.
  The 7.2.x row is covered by 7.2.15.
- The compiler-mismatch warning appears only for the 6.17.1 tree (the archive
  kernel was built with GCC 15.2.1; this host has 15.3.1). It is out of scope
  and attributed to tooling, not driver source.

AC-5 is **PASS for offline build and regression coverage** and **GAP for
runtime behaviour**: no kernel in the matrix was booted with the newly built
module, and no runtime claim is made.

## 7. Claims that remain unproven

| Claim | Why it is unproven | Blocking gap |
| --- | --- | --- |
| A post-fix build performs a modeset on the panel | The modeset works unprivileged on both builds. The 0.5.9 half is `docs/evidence/runtime/04-modeset.txt`; the after-fix half is `docs/evidence/runtime/16-modeset-0.6.0.txt`, recorded with 0.6.0 loaded, the 1024x768-60 mode set and the original mode restored | closed for the modeset; pixel proof stays GAP-B3 |
| The panel shows the expected pixels at 1920x1080 | The `scanout` CRC source (T26) reads the VRAM bytes the engine is fed, not the pixels it emits; there is no `/dev/fb*`, no writeback connector and no external capture, so no unprivileged reader of the emitted pixels exists (section 5) | GAP-B3 (partly), pixel proof open |
| Which `sm750_program_mode` call returns `-110` (GAP-B8) | T27 instruments the five fallible calls: the ordinary error line now ends with `at stage <name>` and needs no debug rebuild or dynamic debug. Confirmation on recurrence is textual - read the stage name and map it to the call in `src/sm750_drm.c` - but the instrumented module has not been loaded (root-only) and the 1-in-206 trigger has not been re-raised. The driver does not retry by design: a retry of a half-progressed modeset can corrupt state | GAP-B8 |
| Hotplug detect and the SiI902X workaround behave on hardware | The SiI9024A not-ready warning is now observed on every mode program (`HPD=1 RSEN=0 status=04`), but no hotplug event can be generated | GAP-B2 |
| Vblank timing meets 60 Hz on hardware | `check-vblank` live probe is still skipped; kmscube reaches 59.01 fps over 299 frames, which is suggestive but not a vblank-timing measurement | GAP-B3 |
| DMA upload and its failure fallback work on hardware | Software checks only; no device-path execution | GAP-B3 |
| Suspend/resume restores the display | No runtime test; `dmesg` is readable but no suspend was attempted. The architecture review raised the same gap as P1 and asked for a decision either way | GAP-B2 |
| The fbdev last-close restore re-commits when the last client exits (A54) | The restore runs when fbcon calls it (`fb_set_par`) but issued no commit on about a dozen client exits, and the stray-fd explanation is unproven: a `diagnose` run showed module refcount 1 with no holder on card0 or the render node | open; the helper restores a text VT on teardown, so the panel repaints |
| Register values before and after a modeset | The `regs` debugfs file exists but `/sys/kernel/debug` is 0700 | GAP-B4 |
| IGT KMS conformance | `kms_setmode`, `kms_atomic`, `kms_flip`, `kms_pipe_crc_basic` and `kms_rmfb` abort in `kmstest_set_vt_graphics_mode` because `/dev/tty0` is root-only; `kms_addfb_basic` `size-max` fails with errno 22 | GAP-B3 (VT), 1 real FAIL |
| `kmscube` renders on this card | Proven for the pre-fix baseline: 299 frames in 5.07 s, real `SETCRTC`/`PAGE_FLIP` | resolved (pre-fix baseline) |
| Kernel-log evidence of probe/remove or errors | Now readable: `dmesg` and `journalctl -k` both return the full 2017-line log. One error episode observed and not reproduced | resolved for access; episode open |
| VBIOS ROM contents and strap configuration | ROM image captured (T12): 49152 bytes, checksum valid, `PCIR` 126f:0750; strap configuration still not readable from the image | GAP-B1 closed for contents; strap unknown |
| PCI capabilities beyond 0x40 | Closed: the allowlisted `sudo -n /usr/local/sbin/sm750-lspci` returned the full space (9465 bytes, capabilities at 0x40, 0x50, 0x70, 0xb0, 0x100, 0x140), stored as `docs/evidence/baseline/19-pci-config-space-full.txt` | GAP-B5 closed |
| Runtime on 6.18, 7.0, 7.1 and final 7.4 | Headers absent or release not final; no boot | offline matrix only |
| `.deb` or RPM install/erase | Root-only packaging path; T6 owns it | out of T4 scope |

## 8. IGT as a stretch artifact

IGT conformance is a **stretch artifact, not a gating deliverable**. The
in-repo suite plus the build matrix are the gating evidence for this release.
IGT would add independent KMS coverage that no in-repo check can provide.

T10 got IGT to start and produced real results on the pre-fix baseline
(`docs/evidence/runtime/06-igt.txt`), but only a subset can reach the driver.
Both of the original blockers were closed; a third one was found behind them.

Blockers, in the order they are hit:

1. `libgsl.so.28` and `libgslcblas.so.0` are absent. They come from
   `gsl-2.8-2.fc43.x86_64` (available in `fedora`). **CLOSED rootlessly** by
   extraction; note the extracted directory is nested, so the library path ends
   in `gsl/gsl-2.8-2.fc43.x86_64/usr/lib64`, not `gsl/usr/lib64`:

```sh
mkdir -p /mega/tmp/sm750/t10/x /mega/tmp/sm750/t10/gsl
dnf download --destdir /mega/tmp/sm750/t10/x igt-gpu-tools kmscube drm-utils
dnf download --destdir /mega/tmp/sm750/t10/gsl gsl
for d in /mega/tmp/sm750/t10/x /mega/tmp/sm750/t10/gsl; do
    (cd "$d" && for r in *.rpm; do rpm2cpio "$r" | cpio -idm; done)
done
```

2. `/dev/dri/card0` is denied. **CLOSED** by a udev ACL:
   `getfacl /dev/dri/card0` shows `user:coder:rw-`, and uid 1005 opens the node.

3. `/dev/tty0` is `crw------- root tty`. **OPEN when recorded here; an ACL was
   installed afterwards.** Note added 2026-11-19: `getfacl /dev/tty0` now shows
   `user:coder:rw-` (installed 2026-11-18T12:08Z, `docs/ROOT-ACTIONS.md`
   section 4.1) and uid 1005 can open the node, so this blocker is closed for
   access. No post-ACL IGT run has been recorded, which is the remaining step.
   The original text follows. IGT's
   `kmstest_set_vt_graphics_mode` (`../lib/igt_kms.c:1558`) opens it to issue
   `KDSETMODE`, gets `errno 13 Permission denied`, and aborts the subtest before
   any KMS ioctl. This blocks `kms_setmode`, `kms_atomic`, `kms_flip`,
   `kms_pipe_crc_basic` and `kms_rmfb`. Closing it needs root or an ACL on
   `/dev/tty0`; neither is in T10's constraints.

The gate that can actually run today (no VT switch needed):

```sh
IGT=/mega/tmp/sm750/t10/x/igt-gpu-tools-2.4-1.fc43.x86_64
GSL=/mega/tmp/sm750/t10/gsl/gsl-2.8-2.fc43.x86_64
export LD_LIBRARY_PATH=$IGT/usr/lib64:$GSL/usr/lib64
B=$IGT/usr/libexec/igt-gpu-tools
for t in core_getversion dumb_buffer kms_addfb_basic kms_getfb; do
    "$B/$t" --device /dev/dri/card0 || echo "$t -> exit $?"
done
```

Observed on the pre-fix baseline: `core_getversion` exit 0 (2 SUCCESS),
`dumb_buffer` exit 0 (6 SUCCESS), `kms_addfb_basic` exit 98 (26 SUCCESS,
14 SKIP, 1 FAIL `size-max` errno 22 on `ADDFB2`), `kms_getfb` exit 98
(10 SUCCESS, 2 SKIP, 2 FAIL, both `igt_drop_root` needing uid 0).

Pass criterion: every selected test exits 0 with `SUCCESS`. SKIP is not a
pass. `kms_pipe_crc_basic` is listed as optional only: the driver now registers
a `scanout` CRC source (T26), so the subtest has something to enable. The
`/dev/tty0` VT blocker recorded in section 8 has since been given an ACL, so
access is no longer the obstacle; no post-ACL IGT run is recorded, which is the
remaining step. Even when it runs, its comparison covers the buffer the CRTC
scans, not the panel.

## 9. Post-T5 blocked-suite probes (historical) and the T10 unblocked run

Observed on 2026-11-18 between 05:10Z and 05:17Z, `uid=1005(coder)`, running
kernel 7.3.4-100.fc43.x86_64. These are the probes that originally created rows
R13-R15 and are kept as the record of the denied state.

```sh
$ modetest -c
no device found
trying to open device '/dev/dri/card3'... failed
trying to open device '/dev/dri/card2'... failed
trying to open device '/dev/dri/card1'... failed
trying to open device '/dev/dri/card0'... failed
[exit 255]
```

```sh
$ kmscube -D /dev/dri/card0 -c 60
could not open drm device
failed to initialize legacy DRM
[exit 255]
```

```sh
$ LD_LIBRARY_PATH=/tmp/opencode/t4-igt/usr/lib64 \
    /tmp/opencode/t4-igt/usr/libexec/igt-gpu-tools/kms_setmode --run-subtest basic
.../kms_setmode: error while loading shared libraries: libgsl.so.28: cannot open shared object file: No such file or directory
[exit 127]
```

`modetest -c -M sm750hdmidrm` was also tried and fails earlier at
`failed to open device 'sm750hdmidrm' with busid '(null)': No such file or
directory`, so `modetest -c` is the probe that reaches the permission check.

**Superseded by T10** (2026-11-18, after the udev ACL on `/dev/dri/card0`).
All three commands now run; the observed outcomes are in
`docs/evidence/runtime/01`-`07` and summarised in rows R13-R17:

```sh
$ modetest -c            # exit 0, connector 35 HDMI-A-1, 28 modes, 1920x1080 preferred
$ modetest -p            # exit 0, crtc 38 -> fb 43 (0,0) (1920x1080), dpms On
$ tail -f /dev/null | kmscube -D /dev/dri/card0 -c 300
                         # exit 0, Rendered 299 frames in 5.066709 sec (59.012665 fps)
$ kms_addfb_basic --device /dev/dri/card0
                         # exit 98, 26 SUCCESS / 14 SKIP / 1 FAIL (size-max)
$ kms_setmode --run-subtest basic --device /dev/dri/card0
                         # exit 98, FAIL at kmstest_set_vt_graphics_mode, errno 13
```

The remaining probes in section 9 are kept because the denied-state text is
still the correct description of a host without the ACL, and because the
`modetest -c -M` note above still applies.

## 10. Consistency with other documents

Where the plan or an older capture conflicts with the archived evidence, the
evidence wins. The conflicts resolved here:

| Conflict | Resolution |
| --- | --- |
| Task text says an "18-check" `make check`; `ENVIRONMENT.md` section 6 and `13-make-check-count.txt` say 17 | 17. The `check` recipe has 17 command lines (`Makefile:32-48`). A naive tab-line count over `Makefile:30-48` returns 18 because the prerequisite list at `Makefile:30-31` continues on a tab-indented second line; that line is not a recipe command. `01-make-check.log:8` records 17. |
| `ENVIRONMENT.md` section 6 cited `Makefile:16-32` for the recipe | That range is pre-T5. After T5's edits the recipe is `Makefile:30-48`; the count is unchanged. T7 refreshed `ENVIRONMENT.md` section 6 to the current line numbers. |
| `ENVIRONMENT.md` section 2 listed 7.2.13-100 as a usable tree | 7.2.13 no longer has a `build` link on 2026-11-18. The recorded matrix is 7.2.15/7.3.3/7.3.4 plus the extracted 6.17.1, matching `02`-`06`. T7 refreshed the table. |
| `ENVIRONMENT.md` section 1 recorded kernel 7.3.3 | The host now runs 7.3.4. T5 logs record 7.3.4 as the running kernel, and R1 still builds against the 7.3.3 `KDIR` explicitly. T7 refreshed the value and kept the T3 capture as the historical record. |
| `EVIDENCE-GAPS.md` GAP-B3 closing command uses `modetest -c -M sm750hdmidrm` | Keep `-M` for the post-access run; use plain `modetest -c` for the denied-state probe, because `-M` fails before card enumeration on this libdrm. |
| `EVIDENCE-GAPS.md:87-89` says `journalctl -k -b` returns 0 lines for this user | Not reproduced in T10: `sudo -n journalctl -k -b -q --no-pager` exits 0 with the full 2017-line boot log, identical to `sudo -n dmesg`. Recorded in `07-kernel-log.txt`; `EVIDENCE-GAPS.md` was not edited (out of T10 scope). |
| This document previously said connector 35 has 36 modes | 28 modes. `modetest -c` in `02-modetest-connector.txt` lists 28, with `#0 1920x1080 60.00` preferred. The 36 figure was a pre-T5 sysfs count and is corrected here. |
| S4/S5/S6 previously read GAP on the grounds that no KMS client could open `card0` | That was true before the udev ACL. T10 ran all three suites unprivileged; S4 and S5 pass on the pre-fix baseline, S6 produces one genuine driver failure (`size-max`) plus a VT-permission blocker. All of it is BEFORE-fix data on the stale 0.5.9 module. |
| `ENVIRONMENT.md` says IGT ships no `igt-info` | Correct. The KMS test binaries are in `/usr/libexec/igt-gpu-tools/`, not `/usr/bin`; no `igt-info` exists in the package. |
| Plan says the matrix covers 7.2.13-100 | Actual post-T5 matrix covers 7.2.15-100, 7.3.3-100 and 7.3.4-100. Recorded in `02`-`05`. |
