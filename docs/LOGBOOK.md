

### 2026-11-28T01:05Z | orchestrator | T6: a soak that can fail, and cannot touch the console

- `tools/sm750-soak.sh` (690 lines, `076078578d01...`) samples once per interval
  for a configurable duration: 29 tab-separated columns per sample covering the
  panel cell (`mode:refresh:crtc:hpd:rx:link_state`), `vram_used`/`vram_total`,
  `refcnt`, module version and size, `MemAvailable`, the vblank counter, the
  panel current line, a crc cell or its unavailable reason, the eleven GAP-B8
  counters, the last recorded gate results, and the dmesg line and fault deltas.
  Eleven criteria are counted, never judged from one sample; `verdict.json` plus
  `summary.txt` make the outcome machine-readable; exit codes are 0 PASS, 1 FAIL,
  2 usage, 3 environment.
- The five prohibitions are structural, not promises: the helper never opens a
  card node, never grabs a console, never switches a VT, never unshares
  /dev/input, never starts a graphical server and never signals a process. Its
  gate plants each construct into a copy and rejects it, verbatim:
  `FAIL: c: no chvt (found: chvt)`, `no VT_ACTIVATE`, `no unshare`,
  `no access to /dev/input`, `no compositor launch`, `no signal to a process`.
- A run that is interrupted writes a verdict with `complete=false`, so a killed
  soak fails coverage instead of looking like a short pass. A fault that exists
  before sample 0 cannot fail the run; a fault logged inside the window can.
- Real 5-minute dry run on this host: 6 of 6 samples, exit 0, verdict PASS, every
  sample `panel_cell 1024x768:75.00:0:1:1:connected`, `refcnt 1`, version
  0.6.10, and six distinct `panel_line` values while `vblank_count` stayed
  frozen on an idle pipe. That freeze is recorded and explicitly not treated as
  a failure.
- Limits written into the evidence rather than left implicit: six samples over
  300 s prove nothing about 24-48 h, a leak, a mode set, a reload or a suspend;
  the eleven `b8_*` columns read `-` because the loaded 0.6.10 predates the
  counters, so counters-monotonic passed with no evidence and must not be cited
  as counter evidence; the crc column is structurally an unavailable reason until
  a read-only CRC entry point is allowlisted; and the owner should write the gate
  output to `/mega/tmp/sm750/soak/last-gate-results.txt` before the long run.
- Deliberate deviation recorded: this is the thirteenth helper but its NOPASSWD
  line is documented and NOT granted, because the helper runs unprivileged except
  for the `sm750-regs` fallback, and a version-free grant added "on the path"
  would be the widest line in the allowlist. The owner decides.
- Gate: `soak helper checks passed (111 assertions, 11 planted controls)`, wired
  through `tests/check-drm-policy.sh:330`; the make check recipe count stays 18.

### 2026-11-28T08:35Z | devops | T7 (install half): 0.6.11 built, packaged, installed, and loaded by the boot

- Bumped 0.6.10 -> 0.6.11 at every site measured at HEAD `13f36d5`:
  `src/sm750_drm.c:81` `#define SM750_DRM_VERSION` (and `DRIVER_PATCHLEVEL` 11),
  `build-package.sh:9`, `dkms.conf:3`, `packaging/sm750hdmifb.spec:22` `:26`
  plus a changelog entry, `packaging/sm750hdmifb-tools.spec:21` plus a changelog
  entry, and the artifact names in `docs/ci/build.yml` that
  `tests/check-release-version.sh` greps. `tests/check-soak-helper.sh:219` is a
  fixture and stays at 0.6.10. A 0.6.11 section was added to
  `docs/RELEASE-NOTES.md`.
- Built from the tree, not from a staged RPM: `./build-package.sh` under the
  rootless libdrm recipe produced `dist/sm750hdmifb_0.6.11_all.deb`,
  `dist/sm750hdmifb-tools_0.6.11_amd64.deb` and the 156-entry source tarball
  (sha256 `b54643a46dd3...`), then both RPMs were rebuilt in the RPM build root
  (`sm750hdmifb-0.6.11-1.fc43.noarch.rpm` 151090 B, `sm750hdmifb-tools-0.6.11-1.fc43.x86_64.rpm`
  28786 B). The tools spec needs `--nodeps` with the pinned libdrm tree because
  `libdrm-devel` is not in the rpmdb. Verified by extraction, not by trusting the
  commit: the packaged `src/sm750_drm.c` sha256 `eb72303def3c...` is the tree's,
  and the payload carries the ordered teardown at `:5957` -> `:5971` -> `:5975`
  and all eleven `DEVICE_ATTR_RO(b8_*)`.
- `sudo -n /usr/local/sbin/sm750-pkg install` at 2026-11-27T21:53:18Z replaced
  both 0.6.10 packages, purged the stale DKMS registration in `%posttrans` and
  DKMS-built and signed 0.6.11 for all four kernels. It then exited 1 on its own
  guard, `loaded module reports '0.6.10', installed RPM is '0.6.11'`: correct,
  because this session was forbidden to reload with the owner's browser holding
  two `/dev/dri/renderD128` fds (pids 570903, 570922, refcnt 1).
- The host rebooted at 2026-11-28T07:52:12Z and the boot autoloaded the installed
  module. The deferral therefore ended without this session touching the module:
  `/sys/module/sm750hdmidrm/version` reads `0.6.11`, loaded srcversion
  `95E21EB1B858C08574A4974` equals the installed `.ko.xz`, `sm750-vt show` reports
  `version=0.6.11` refcnt 0, and `sm750-pkg install` re-run at 08:14:32Z exits 0
  with `installed, loaded module reports 0.6.11`. All eleven `b8_*` attributes
  read live (eight zero, `b8_mode_attempts=2`, `b8_edid_reads=1`,
  `b8_counters_epoch_s=3`); `a65_trace=N` and no `A65:` line is emitted, so the
  nineteen marks stay owner-gated to a run with the parameter armed.
- Per-kernel payload, all version 0.6.11 and srcversion `95E21EB1B858C08574A4974`,
  sha256 `130981341edf...` (7.2.15-100), `7fcc74010166...` (7.3.3-100),
  `2ce25ea44415...` (7.3.4-100), `b7972196c8ed...` (7.3.5-100); every DKMS
  artefact hashes the same as the installed file.
- Evidence: `docs/evidence/builds/30-instrumented-install.log` (build, tarball,
  RPMs, payload diff, install, per-kernel table, what the install did not do,
  gates) and `docs/evidence/runtime/57-instrumented-load.txt` (the deferral and
  its cause with the pre-install `refcnt 1` and the two holders quoted, then the
  live post-boot identity and the eleven counter reads).
- Gates, all exit 0: `tests/check-release-version.sh` (`0.6.11`),
  `tests/check-drm-packaging.sh`, `tests/check-rpm-dkms.sh` (`0.6.11`, 8 planted
  controls rejected), `tests/audit-release.sh`, `make ... check` under the
  documented rootless libdrm recipe (its first bare run exits 2 in `check-deps`
  because `libdrm-devel` is absent; nothing was relaxed), and `git diff --check`.
- Counts re-measured after `git add -A` and the docs corrected where they had
  drifted: 156 payload files (was 154/132 in three places). Not achieved and
  reported as such: the T4 evidence files `docs/evidence/a65/02-mark-and-ordering-gate.txt`
  and `docs/evidence/builds/29-a65-ordering-build.log` do not exist in the tree
  even though `tests/check-a65-trace.sh` passes; and the A65 mark capture needs
  the parameter armed by the owner.
