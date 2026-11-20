# Acceptance report - SM750 HDMI DRM driver

Independent verification of acceptance criteria AC-1 .. AC-7 of
`docs/plan/20261117-sm750-driver-prod/plan.yaml` (revision 3, criteria text at
`docs/plan/20261117-sm750-driver-prod/plan.yaml:113-120`) against the committed
tree at HEAD `332b997`. Reviewer: gem-reviewer, task T8, critic mode, scope
full. Every command below was run by the reviewer in this session; builds ran in
a clone at `/mega/tmp/sm750/t8/repo` and in scratch space under
`/mega/tmp/sm750/t8/`, never inside the repository working tree. The repository
`git status --short` was empty before and after every command.

Round 1 reviewed HEAD `332b997` and returned 4 PASS, 0 FAIL, 3 GAP. Round 2
reviews HEAD `2f0d48b`, which carries T23 (the seven documentation findings) and
T24 (the static-gate non-determinism). Round-1 text is kept below as history:
where round 2 re-verdicts a criterion its detail heading carries the new verdict
and a `Round 2:` note instead of being rewritten.

## Verdict

ACCEPT WITH ONE GAP - 6 PASS, 0 FAIL, 1 GAP (AC-3).

The driver, its build, its test suite, its packaging and its documentation index
are verified and reproducible at `2f0d48b`. Every documentation finding of round
1 is closed at its source and each corrected number is reproducible by the
command recorded next to it; the static gate is now deterministic over ten
consecutive runs in the environment that used to break it.

The single remaining GAP is AC-3, and it is a hardware-observation gap, not an
unverified code claim: tiers 1-3 of the validation ladder are evidenced, tiers 4
and 5 are now stated as unavailable with the mechanism, and tier 6 (pixel proof
at the panel) needs a human looking at the monitor or capture hardware, neither
of which exists on this host. No criterion failed in the sense of a claim
contradicted by an artefact.

## Criterion verdicts

| Criterion | Verdict | Evidence path | Command used | Notes |
| --- | --- | --- | --- | --- |
| AC-1 | PASS | `docs/specs/INDEX.md`, `docs/specs/SHA256SUMS`, `docs/specs/REGISTER-MAP.md`, `docs/specs/GAPS.md` | `sha256sum` cross-check of `docs/specs/SHA256SUMS`; the register-map coverage heredoc verbatim from `docs/specs/REGISTER-MAP.md`; `git ls-files docs/specs` | Datasheet and brief hashes agree with `SHA256SUMS` and no vendor binary is tracked. Round 2: the map now covers all 70 registers - 64 with a DS-1 page, 6 without - and reports `missing []`, including the 16 dump-table registers round 1 found absent. |
| AC-2 | PASS | `docs/AUDIT.md`, `docs/DEFECTS.md` | `grep -cE '^.[[:space:]]A[0-9]' docs/AUDIT.md docs/DEFECTS.md` -> 24, 30 | Every AUDIT row carries severity and an observation; every DEFECTS row carries fixed/accepted/deferred plus justification. Round 2: 30 rows after A29 (T18) and A30 (T24). |
| AC-3 | GAP | `docs/evidence/baseline/03-connector.txt`, `docs/evidence/runtime/02-modetest-connector.txt`, `04-modeset.txt`, `16-modeset-0.6.0.txt`; `docs/TEST-STRATEGY.md` section 5; `docs/evidence/EVIDENCE-GAPS.md` | `grep -rn 'nonzero bytes\|8294400' docs/TEST-STRATEGY.md docs/evidence/` -> no claim; `grep -c 'get_crc_sources' src/*.c src/*.h` -> 0 | Tiers 1-3 are evidenced and reproduced on 0.6.0. Round 2: tier 4 no longer carries an unsupported number - it states the three independent blockers (`CONFIG_FB_DEVICE` unset so no `/dev/fb*`, no writeback connector, a foreign framebuffer cannot be mapped) and the tier-5 closing command was replaced by a statement that no CRC source exists. The gap is now exactly the one thing that cannot be done here: seeing the panel. |
| AC-4 | PASS | `docs/TEST-STRATEGY.md` | evidence-existence loop over every `docs/evidence/...` path named in `docs/TEST-STRATEGY.md`; `make check` for the PASS rows that are in-repo suites | Suites S1-S8 are named and every PASS row is backed by a file that exists. Round 2: both prose defects are closed - `docs/DELIVERABLES.md` 2.4 now states 13 PASS / 2 FAIL / 3 GAP as the source does, and the 0.6.0 re-runs are listed as a separate record beside the 0.5.9 R table instead of being unmentioned. |
| AC-5 | PASS | `docs/evidence/builds/13-make-check-0.6.0.log`, `docs/evidence/builds/14-check-all-kernels-0.6.0.log`, `docs/evidence/builds/15-kernel-6.17.1-0.6.0.log`, `docs/evidence/builds/11-warnings-scan.log` | `make CC=/usr/bin/gcc check` with the rootless libdrm environment; `JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh` | `make check` exit 0, 17 recipe commands, `Ran 4 tests ... OK`, zero compiler diagnostics attributable to `src/`. Matrix reproduces `Built 9`; the 6.17.1 floor tree still exists and reproduces `Built 3`. |
| AC-6 | PASS | `packaging/sm750hdmifb.spec`, `tests/check-rpm-dkms.sh`, `docs/evidence/runtime/12-rpmbuild-0.6.0.txt`, `20-rollback.txt`, `21-final-state.txt`, `22-dkms-stale-purge.txt` | `bash tests/check-rpm-dkms.sh`; `rpmbuild -ba`; `rpm -qip`, `rpm -qlp`, `rpm -qp --scripts`, `rpmspec -q --requires`, `rpm -qpR`; `sudo -n dkms status` | Rootless half reproduced end to end (payload, deps, scriptlets, sandbox `built`). Root half is now also executed and evidenced (install, erase, reinstall, stale purge). Archived packaging logs are 0.5.9-era and understate the payload. |
| AC-7 | PASS | `docs/DELIVERABLES.md`, `README.md`, `docs/ROOT-ACTIONS.md`, `docs/PROVENANCE.md` | `comm -23 <(git ls-files docs \| sort) <(grep -o 'docs/[A-Za-z0-9._/-]*' docs/DELIVERABLES.md \| sort -u)` -> empty | Round 2: the document's own self-check now emits nothing, section 1's counts match `docs/AUDIT.md` (24) and `docs/DEFECTS.md` (30), 2.4 matches `docs/TEST-STRATEGY.md`, the AC-3 row cites the successful dump and section 5.4 covers GAP-B1 .. GAP-B8. |

## AC-1 .. AC-7 detail

### AC-1 Device specifications located, read and archived - PASS (round 1: GAP)

Claimed: `docs/specs/INDEX.md` carries source URL, version, date and SHA-256 for
the SM750 datasheet and product brief; `docs/specs/REGISTER-MAP.md`
cross-references every MMIO register used by `src/*.c`; unresolved items are in
`docs/specs/GAPS.md`; no vendor binary enters the tree.

Observed. `docs/specs/INDEX.md` (129 lines) records DS-1 revision 1.4, "Updated:
September 27, 2012", URL
`https://d3v.versalogic.com/wp-content/themes/vsl-new/assets/resources/support/mpee-v5/SM750_Datasheet_v.1.4.pdf`
with sha256 `fac31257bb6ab058573bdb3fa255e6c5146522b0dee8aa6376cd59e500531889`,
and PB-1 `SM750-PB-201910` with sha256
`6eafa7240ead440fe6bf374fbeb393d75f26191148e3e8595f42accbb3bfd19f`. Both values
match `docs/specs/SHA256SUMS` (retrieval date 2026-11-17). `docs/specs/GAPS.md`
(122 lines) carries GAP-1 .. GAP-4 with an explicit open/substitute/closed
legend. `git ls-files docs/specs` returns exactly `GAPS.md`, `INDEX.md`,
`REGISTER-MAP.md`, `SHA256SUMS` - text only.

The register cross-reference is where the criterion is not met as written.
`docs/specs/REGISTER-MAP.md:9` states its own method: every `#define NAME 0xADDR`
in `src/ddk750_reg.h` whose name appears in a `src/*.c` file outside a comment,
and reports "54 MMIO registers are referenced by `src/*.c`; 51 have a DS-1 page
citation and 3 do not". Measured independently: 197 non-mask register defines
exist, 69 are referenced by `src/*.c`, 53 of those outside the register dump
table, and all 53 appear in the map. The remaining 16 are referenced by
`src/*.c` only inside `sm750_reg_dump_registers[]` at
`src/sm750_drm.c:3282-3332` and are absent from REGISTER-MAP.md: ALPHA_FB_ADDRESS,
CRT_CURRENT_LINE, CRT_FB_ADDRESS, CRT_FB_WIDTH, CRT_MONITOR_DETECT, DEVICE_ID,
DE_STATE1, DE_STATE2, GPIO_INTERRUPT_SETUP, PANEL_COLOR_KEY, PANEL_PAN_CTRL,
VIDEO_FB_0_ADDRESS, VIDEO_FB_0_LAST_ADDRESS, VIDEO_FB_WIDTH, VIDEO_PLANE_BR,
VIDEO_PLANE_TL. All 16 are documented in `docs/REGISTERS.md` (49-register table)
and all 49 appear in the live dump, so the information exists in the tree - it is
simply in a second document. By the map's own stated method those 16 qualify, so
the map is internally incomplete rather than out of scope.

Residual: add the 16 dump-table registers to `docs/specs/REGISTER-MAP.md` (or
state explicitly that the dump table is excluded from the cross-reference and
point at `docs/REGISTERS.md`).

Round 2: closed by T23. `docs/specs/REGISTER-MAP.md` now carries all 16 as
rows - 13 with a DS-1 page, 3 in the uncited table (`GPIO_INTERRUPT_SETUP`
0x010008 for the GAP-2 stride conflict, `DE_STATE1` and `DE_STATE2`, which DS-1
does not contain) - and its Method section carries the reproduction heredoc.
Running that heredoc verbatim prints 330 defines, 90 referenced, 70 registers,
20 mask macros, 70 documented, 64 with a DS-1 citation, 6 without, and
`missing []`. The 24-row discrepancy in this section was the reviewer's own
parser, which anchored `#define` at column 0 and missed the four indented
defines at `src/ddk750_reg.h:1142,1144,1146,1149`; the map states the
authoritative pattern instead of a count.

### AC-2 Repository audit and defect inventory - PASS

Claimed: `docs/AUDIT.md` records every defect with severity and evidence;
`docs/DEFECTS.md` gives each a status of fixed, accepted or deferred with
justification.

Observed. `docs/AUDIT.md` (340 lines) has a defect table at `:168-193` with
columns `| ID | Sev | Symptom | Reproduction | Observed evidence |`, rows
A01-A24, and a totals line "S1 = 2, S2 = 8, S3 = 11, S4 = 3 (24 defects)".
`docs/DEFECTS.md` (405 lines) carries A01-A29, each row with severity, status,
change reference and evidence reference: 24 `fixed`, 4 `accepted` (A20, A24,
A26, A28), 0 `deferred` - the word occurs only in the status legend. Each
accepted row carries a substantive justification rather than a bare label: A20
DKMS auto-install against `docs/RELEASE-NOTES.md:14-19` with `dkms.conf:7-8`
unchanged; A24 fbdev documented at `README.md:307-313`; A26 the `size-max`
EINVAL as driver policy with `max_height` 1152 at `src/sm750_drm.c:95` and
`:3437` against DS-1 pages 151 and 153; A28 the smatch precedence message traced
to `GENMASK_TYPE()` at `include/linux/bits.h:52` through `DMA_BIT_MASK()` at
`include/linux/dma-mapping.h:126` with sites at `src/sm750_drm.c:1651,1663,1665,1673`
and `src/sii902x.c:741`, reproduced by a five-line out-of-tree probe.

Residual: `docs/DELIVERABLES.md` section 1 and section 2.2 state "24 and 25" and
"24" respectively; the measured counts are 24 and 29. That is a defect in the
index, not in the audit; it is scored under AC-7.

### AC-3 Runtime and hardware validation ladder - GAP (unchanged in round 2)

Claimed: connector state, modetest enumeration, modeset, framebuffer readback,
scanout CRC, external capture, each tier backed by an evidence path; unreachable
tiers are GAP rows with closing commands.

Observed, tier by tier.
1. Connector state: `docs/evidence/baseline/03-connector.txt` exists. Live
   re-check: `/sys/class/drm/card0-HDMI-A-1/status` reads `connected`, with
   `enabled` and `dpms` reading `enabled` and `On`.
2. Modetest enumeration: `docs/evidence/runtime/02-modetest-connector.txt`
   exists.
3. Modeset: `docs/evidence/runtime/04-modeset.txt` (0.5.9 baseline) and
   `docs/evidence/runtime/16-modeset-0.6.0.txt` (0.6.0, held-client proof on
   CRTC 38 with restore) exist.
4. Framebuffer readback: `docs/TEST-STRATEGY.md:424` states a readback
   "returned a static, essentially blank buffer (48 nonzero bytes of 8294400,
   byte-identical across three samples while Plasma ran)". No evidence file
   backs that number: `grep -rln '8294400\|nonzero bytes' docs/evidence/` returns
   nothing, and `git ls-files` contains no readback script. The measurement was
   made with an untracked scratch script. This is a claim without observed
   evidence.
5. Scanout CRC: recorded as a GAP row whose closing command is
   `sudo cat /sys/kernel/debug/dri/0/crtc-0/crc/data`
   (`docs/evidence/EVIDENCE-GAPS.md:319`). That command cannot produce data:
   `src/` registers no CRC source (`grep -c 'get_crc_sources' src/*.c src/*.h`
   is 0), and DRM's `drm_debugfs_crtc_crc_add()` returns early when
   `crtc->funcs->get_crc_sources` is NULL
   (`/usr/src/kernels/7.3.4-100.fc43.x86_64/include/drm/drm_crtc.h:842-861`).
   The GAP row is honest about the state but its closing command is inert.
6. External capture: no capture hardware on the host and the monitor has not
   been visually inspected, so pixel correctness is not claimed and must not be.

The criterion tolerates unreached tiers, but it requires those tiers to be GAP
rows with closing commands. Tier 5 fails that requirement (dead command) and
tier 4 carries an unevidenced number. Hence GAP, not PASS.

Residual: replace the tier 5 closing command with the real prerequisite (add a
`get_crc_sources` callback, or drop the tier and state that pixel proof requires
external capture), and either commit the readback transcript or delete the
number from `docs/TEST-STRATEGY.md:424`.

### AC-4 Test strategy and results - PASS

Claimed: `docs/TEST-STRATEGY.md` names the in-repo and external suites, and every
PASS row is backed by an evidence file that exists in the tree.

Observed. `docs/TEST-STRATEGY.md` (645 lines) names suites S1-S8 at `:78-87` and
carries results R1-R17 at `:377-391` with a totals line "13 PASS, 2 FAIL, 3 GAP"
at `:391`. That total is internally consistent with the rows. Every
`docs/evidence/...` path named in the document resolves to an existing file; the
single apparent miss, `MISSING docs/evidence/runtime/01`, is range notation
(`runtime/01`-`04` at `:385` and `:388`, `01`-`07` at `:612`), not a broken
link. The in-repo suites that back PASS rows were re-executed: `make check` exit
0 with `Ran 4 tests ... OK`, `tests/check-drm-policy.sh` exit 0,
`tests/check-drm-packaging.sh` exit 0, `tests/audit-release.sh` exit 0.

Two documentation defects are recorded rather than scored, because the criterion
concerns the naming of suites and the existence of PASS-row evidence:
`docs/DELIVERABLES.md` 2.4 reports "10 PASS, 0 FAIL, 5 GAP" against the
document's own "13 PASS, 2 FAIL, 3 GAP", and the document is still the 0.5.9
record (S1 names version 0.5.9; `:503` still says the 0.6.0 build "was not
loaded in T10") although the 0.6.0 re-runs exist as
`docs/evidence/builds/13`-`19` and `docs/evidence/runtime/16`-`19`. The 0.6.0
results are therefore present in the tree but not folded into the R table.

### AC-5 Build integrity - PASS

Claimed: `make check` green with 17 recipe commands, a build matrix covering the
declared 6.17 floor plus the installed 7.2 and 7.3 header trees, and no compiler
warnings originating in `src/`.

Observed. `make CC=/usr/bin/gcc check` in the clone with the documented rootless
libdrm environment exits 0 and ends `Ran 4 tests in 0.301s` / `OK`. The recipe is
17 commands at `Makefile:32-48`; `Makefile:30-31` is a tab continuation of the
prerequisite list, not a recipe, so a naive tab count over the whole file
overcounts. `sed -n '32,48p' Makefile | grep -c '^<TAB>'` returns 17. Zero
`warning:` and zero `error:` lines appear in the build output and no diagnostic
is attributed to a `src/` file. The matrix re-run with
`JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh` exits 0 with
`Built 9 sm750hdmidrm kernel/format combinations` across the three installed
header trees. The 6.17 floor tree still exists at
`/mega/tmp/sm750/t5/k617/usr/src/kernels/6.17.1-300.fc43.x86_64` and the archived
run `docs/evidence/builds/15-kernel-6.17.1-0.6.0.log` shows `Built 3`, exit 0,
with only the "compiler differs from the one used to build the kernel" warning
that comes from the kernel tree. `docs/evidence/builds/11-warnings-scan.log`
classifies every unique warning as 19 pahole-version and 3 compiler-version
messages and states "diagnostics attributed to driver sources (src/*.c or
src/*.h): none".

Residual, not scored against AC-5: the optional static gate
`PATH=/usr/bin:/bin ./tests/check-static.sh` is not deterministic on this host.
It returned exit 0 with `static gate: PASS` on one run and exit 1 with
`static gate: FAIL` on another, the failing step being `coccinelle: exit 255, 0
finding(s)` with `spatch failed`. sparse (0 warnings), smatch (the 5 findings
accepted as A28), cppcheck (0 findings) and pahole were stable. The gate is
documented as opt-in and is not one of the 17 `make check` commands, so AC-5 is
unaffected, but a release process that treats the gate as a hard gate would be
flaky on this host.

### AC-6 Packaging - PASS

Claimed: an rpmbuild spec produces a noarch DKMS source carrier with correct
scriptlets and dependencies, verified rootless, with root-only install and erase
documented as gaps with exact closing commands.

Observed rootless, re-run by the reviewer. `bash tests/check-rpm-dkms.sh` with
`SM750_RPM_WORK=/mega/tmp/sm750/t8/rpmb2` and
`SM750_RPM_EVIDENCE=/mega/tmp/sm750/t8/evid` exits 0 and reports: payload
matches `git ls-files` (115 files); `rpmbuild -ba` exit 0; runtime dependencies
`dkms` and `kmod` with `%post`/`%preun` requiring `dkms`; scriptlets add in
`%post`, build and install and depmod in `%posttrans`, remove in `%preun`, no
`%postun`; `%files: 36 files, 4 owned directories, 2 %config(noreplace)`;
missing kernel headers produce a warning and exit 0; stale purge removes only
`sm750hdmifb/0.5.9` and leaves 0.6.0 and other module names untouched; the DKMS
sandbox reaches `built` with a 321952-byte object; then 8 SKIP lines for the
root-only steps. A separate scratch rebuild produced a 308228-byte source
tarball with sha256
`61466750d8b6db548ae76878a3411bfd881e844cda9fb9ba5881f73dcba344d2`, byte-identical
to the tarball in `/mega/tmp/sm750/t6` and to `dist/`. The built RPM is 94538
bytes, `Architecture: noarch`, GPL-2.0-only, 36 files plus 4 directories;
`rpm -qp --scripts` matches the spec including the `%posttrans` kernel loop with
the missing-headers case and the stale-registration purge at
`packaging/sm750hdmifb.spec:200-229`; `rpmspec -q --requires` yields `/bin/sh`
three times, `dkms` three times and `kmod`; `rpm -qpR` adds `/usr/bin/bash`,
`config(sm750hdmifb) = 0.6.0-1.fc43` and four rpmlib entries; the only
config file is `/etc/modprobe.d/sm750hdmidrm.conf` plus
`/etc/modules-load.d/sm750hdmidrm.conf`.

Observed root-side state. `rpm -q sm750hdmifb` returns
`sm750hdmifb-0.6.0-1.fc43.noarch`; `sudo -n dkms status` returns exactly three
`0.6.0 ... installed` lines for 7.2.15-100, 7.3.3-100 and 7.3.4-100 with no 0.5.9
rows remaining, so the `%posttrans` purge is effective in practice and not only
in the sandbox; `/sys/module/sm750hdmidrm/version` reads `0.6.0`; the loaded
module's `srcversion` `07E8F503FC7D839EEC5EE64` equals
`modinfo -F srcversion /lib/modules/7.3.4-100.fc43.x86_64/extra/sm750hdmidrm.ko.xz`,
which proves the running module is the installed package's object. Install,
erase and reinstall are evidenced by `docs/evidence/runtime/12-rpmbuild-0.6.0.txt`,
`20-rollback.txt`, `21-final-state.txt` and `22-dkms-stale-purge.txt`. The
remaining root-only step in the packaging story is the documented erase hazard:
an erase leaves the loaded module with no file on disk.

Residual: `docs/evidence/packaging/01`-`07` and
`docs/evidence/builds/17-check-rpm-dkms-0.6.0.log` are 0.5.9-era and report "73
files" for the payload, and none of them contains the stale-purge OK line; the
current tree produces 115. The archived transcripts therefore do not correspond
to the shipped package and should be regenerated or clearly marked superseded.
`docs/DELIVERABLES.md` 2.6 repeats the stale "73 files" figure.

### AC-7 Deliverable index and clean-checkout reproduction - PASS (round 1: GAP)

Claimed: `docs/DELIVERABLES.md` maps AC-1 .. AC-7 to repo paths and verification
commands, README documents the RPM/DKMS path, and every root-only step is
labelled with its closing command.

Observed. The AC-1 .. AC-7 map exists (section 1), the per-criterion check
sections 2.1-2.8 exist with runnable commands, section 3 lists root-only steps
with commands, section 4 gives the clean-checkout recipe, section 5 is the
document inventory and section 6 names `Makefile:32-48` as the source of truth
for the 17 recipe commands. `README.md:49-82` documents the RPM/DKMS path
including the rootless `rpmbuild -ba` invocation, the `dnf install` of the exact
noarch RPM, the statement "The RPM build needs no root; only `dnf install` and
the reboot do", and `./tests/check-rpm-dkms.sh` as the rootless re-verification.
`docs/ROOT-ACTIONS.md` and `docs/PROVENANCE.md` are present and accurate as far
as the checks in this report reach.

Round 2: closed by T23. The self-check now emits nothing, because it counts
tracked files (`git ls-files docs`) instead of every file on disk. Section 1
matches its sources (`docs/AUDIT.md` 24 rows, `docs/DEFECTS.md` 30), section 2.4
states 13 PASS / 2 FAIL / 3 GAP as `docs/TEST-STRATEGY.md` does, the AC-3 row
cites `docs/evidence/runtime/08-register-dump.txt` as the successful dump and
keeps `docs/evidence/builds/09-register-dump.log` as the denied attempt, the
payload figure is 115 files (the command is in the document), and section 5.4
runs from GAP-B1 to GAP-B8.

The index fails its own gate. `docs/DELIVERABLES.md:120-124` documents a
self-check whose expected result is "no output, meaning every file under docs/ is
named by this file". Running that exact check emits 21 paths, and unioning the
README's own documentation references removes none of them:
`docs/VBIOS-REVERSE-ENGINEERING.md`, `docs/evidence/builds/26-audit-release.log`,
`docs/evidence/builds/27-source-archive-manifest.log`,
`docs/evidence/runtime/09-hdmi-minus-110.txt`,
`docs/evidence/runtime/10-addfb-size-max.txt`,
`docs/evidence/runtime/11-preconditions.txt`,
`docs/evidence/runtime/13-module-reload.txt`,
`docs/evidence/runtime/14-modetest-connector-0.6.0.txt`,
`docs/evidence/runtime/15-modetest-properties-0.6.0.txt`,
`docs/evidence/runtime/16-modeset-0.6.0.txt`,
`docs/evidence/runtime/17-a27-fix-build.txt`,
`docs/evidence/runtime/17-kmscube-0.6.0.txt`,
`docs/evidence/runtime/18-a27-fix-install.txt`,
`docs/evidence/runtime/18-kernel-log-0.6.0.txt`,
`docs/evidence/runtime/19-a27-fix-reproduce.txt`,
`docs/evidence/runtime/21-final-state.txt`,
`docs/evidence/runtime/22-dkms-stale-purge.txt`,
`docs/evidence/vbios-re/01-rebuild.txt`,
`docs/evidence/vbios-re/02-bitexact.txt`,
`docs/evidence/vbios-re/03-decode-equality.txt`,
`docs/evidence/vbios-re/04-toolchain.txt`. Section 5.4's inventory table stops at
`docs/evidence/builds/01` and omits `runtime/09`-`22`, `vbios-re/` and
`builds/20`-`27`, and its heading still says "GAP-B1 .. GAP-B7" although
`docs/evidence/EVIDENCE-GAPS.md` carries GAP-B8. Three further index errors: the
AC-2 row states "24 and 25" where the measured counts are 24 and 29, the AC-4 row
section 2.4 states "10 PASS, 0 FAIL, 5 GAP" against the source document's
13/2/3, and the AC-3 row cites `docs/evidence/builds/09-register-dump.log`, which
is the denied-read precursor, instead of the closed capture
`docs/evidence/runtime/08-register-dump.txt`.

Residual: bring section 5.4 up to the full `docs/` inventory, correct the three
counts and the AC-3 evidence path, and re-run the section 2.7 self-check to an
empty result.

## Reproduced checks

| Command | Exit | Observed |
| --- | --- | --- |
| `python3 tools/vbios-re/reencode.py --out /mega/tmp/sm750/t8/reencode` (in the clone) | 0 | `PASS coverage above floor 99.66`, `OK: rebuilt .../reencode.bin is byte-identical to /mega/tmp/sm750/vbios-01-00-0.bin`; rebuilt image 49152 bytes, sha256 `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`, 17 residual slots |
| `cmp -l /mega/tmp/sm750/t8/reencode/reencode.bin /mega/tmp/sm750/vbios-01-00-0.bin` | 0 | no output (0 differing bytes) |
| `PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm LD_LIBRARY_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64 C_INCLUDE_PATH=/mega/tmp/sm750/t3/libdrm/usr/include make CC=/usr/bin/gcc check` | 0 | ends `Ran 4 tests in 0.301s` / `OK`; 0 `warning:` and 0 `error:` lines; 0 diagnostics attributed to `src/` |
| `sed -n '32,48p' Makefile \| grep -c '^<TAB>'` | 0 | 17 recipe commands |
| `JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh` | 0 | `Built 9 sm750hdmidrm kernel/format combinations` |
| `bash tests/check-drm-policy.sh src/sm750_drm.c` | 0 | `DRM mode policy checks passed` |
| `./tests/check-drm-packaging.sh` | 0 | `Unified DRM package checks passed` |
| `./tests/audit-release.sh` | 0 | `Release audit passed: /mega/tmp/sm750/t8/repo/dist/RELEASE-AUDIT.txt` |
| `PATH=/usr/bin:/bin ./tests/check-static.sh` | 1 | `sparse: exit 0, 0 warning(s)`; `smatch: exit 0, 5 finding(s)` (A28); `cppcheck: exit 0, 0 finding(s)`; `coccinelle: exit 255, 0 finding(s)`, `spatch failed`; `static gate: FAIL`. An earlier run of the same command in this session returned exit 0 with `static gate: PASS`; the gate is opt-in and is not one of the 17 `make check` commands |
| `SM750_RPM_WORK=/mega/tmp/sm750/t8/rpmb2 SM750_RPM_EVIDENCE=/mega/tmp/sm750/t8/evid bash tests/check-rpm-dkms.sh` | 0 | payload matches `git ls-files` (115 files); `%files: 36 files, 4 owned directories, 2 %config(noreplace)`; `stale purge: only sm750hdmifb/0.5.9 removed`; `dkms sandbox: ... built`; object 321952 bytes; 8 SKIP lines for root-only steps |
| `rpmbuild -ba` from a fresh scratch topdir `/mega/tmp/sm750/t8/rpmb` | 0 | source tarball 308228 bytes, 115 entries, sha256 `61466750d8b6db548ae76878a3411bfd881e844cda9fb9ba5881f73dcba344d2` (identical to `/mega/tmp/sm750/t6` and `dist/`); RPM 94538 bytes |
| `rpm -qip /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm` | 0 | `Version: 0.6.0`, `Release: 1.fc43`, `Architecture: noarch`, `License: GPL-2.0-only` |
| `rpm -qlp ...rpm` | 0 | 40 paths = 36 files plus 4 owned directories |
| `rpm -qp --scripts ...rpm` | 0 | `%post` dkms add; `%preun` dkms remove `--all`; `%posttrans` kernel loop with missing-headers warning, `dkms build`, `dkms install --force`, `depmod -a`, stale purge; no `%postun` |
| `rpmspec -q --requires packaging/sm750hdmifb.spec` | 0 | `/bin/sh` x3, `dkms` x3, `kmod` |
| `rpm -qpR ...rpm` | 0 | the above plus `/usr/bin/bash`, `config(sm750hdmifb) = 0.6.0-1.fc43`, 4 rpmlib entries |
| `sudo -n dkms status` | 0 | exactly three lines, `sm750hdmifb/0.6.0, <kernel>: installed` for 7.2.15-100, 7.3.3-100, 7.3.4-100; no 0.5.9 rows |
| `sudo -n /usr/local/sbin/sm750-regs` | 0 | 52 lines; `# sm750hdmidrm register dump, 49 registers, read-only`; 49 register rows; `SYSTEM_CTRL 0x20a00000` |
| `cat /sys/module/sm750hdmidrm/version; cat /sys/module/sm750hdmidrm/srcversion` | 0 | `0.6.0`; `07E8F503FC7D839EEC5EE64` |
| `modinfo -F srcversion /lib/modules/7.3.4-100.fc43.x86_64/extra/sm750hdmidrm.ko.xz` | 0 | `07E8F503FC7D839EEC5EE64` - matches the loaded module |
| `rpm -q sm750hdmifb` | 0 | `sm750hdmifb-0.6.0-1.fc43.noarch` |
| `cat /sys/class/drm/card0-HDMI-A-1/{status,enabled,dpms}` | 0 | `connected`, `enabled`, `On` |
| `sudo -n -l` | 0 | 19 NOPASSWD entries; colon audit of the command lines returns 0 |
| `git ls-files \| grep -E '\.(asm\|bin\|rom\|pdf\|ko\|o\|rpm\|deb\|so\|a)$'` | 1 | no matches - no vendor binary or build artefact is tracked |
| `git ls-files docs/specs` | 0 | `GAPS.md`, `INDEX.md`, `REGISTER-MAP.md`, `SHA256SUMS` |
| `grep -cE '^.[[:space:]]A[0-9]' docs/AUDIT.md docs/DEFECTS.md` | 0 | `docs/AUDIT.md:24`, `docs/DEFECTS.md:29` |
| `grep -rln '8294400\|nonzero bytes' docs/evidence/` | 1 | no output - the tier-4 readback number has no evidence file |
| `grep -c 'get_crc_sources' src/*.c src/*.h` | 1 | 0 - the driver registers no CRC source, so the recorded tier-5 closing command cannot work |
| `comm -23 <(find docs -type f \| sort) <(grep -o 'docs/[A-Za-z0-9._/-]*' docs/DELIVERABLES.md \| sort -u)` | 0 | 21 unreferenced paths, against the document's own "expected: no output" |
| evidence-existence loop over every `docs/evidence/...` path in `docs/TEST-STRATEGY.md` | 0 | only `MISSING docs/evidence/runtime/01`, which is range notation; every full path exists |

## Claims without observed evidence

- AC-3 tier 4, framebuffer readback: "48 nonzero bytes of 8294400"
  (`docs/TEST-STRATEGY.md:424`). No evidence file in the tree contains the
  measurement and no tracked script produces it. The number is consistent with
  the same document's conclusion that the buffer was "static, essentially
  blank", but it is not reproducible from the repository.
- AC-3 tier 6, external capture / pixel correctness: not claimed anywhere and
  not observed. The monitor has not been visually inspected; no capture hardware
  is attached.
- AC-3 tier 5, scanout CRC: correctly recorded as a GAP, but the recorded closing
  command (`sudo cat /sys/kernel/debug/dri/0/crtc-0/crc/data`) cannot succeed
  because the driver exposes no CRC source.
- GAP-B5, PCI config space above 0x40: `docs/DELIVERABLES.md:167` and
  `docs/ROOT-ACTIONS.md:235` and `:648` record it as "CLOSED, GAP-B5. Exit 0,
  9465 bytes, capability list above 0x40 present", while
  `docs/evidence/EVIDENCE-GAPS.md:481` still records `Status: GAP-PARTIAL`. No
  tracked transcript contains a config-space line at or above `40:`
  (`docs/evidence/baseline/07-pci-config-space.txt` stops at `0x3f`, 452 bytes)
  and the 9465-byte artefact exists only in scratch. This claim is refused as
  PASS; the GAP-PARTIAL status is the accurate one.
  Note (2026-11-19, T27): this bullet is the round-1 record and is left as
  written. Round 2 closed the finding: the 9465-byte capture is now tracked as
  `docs/evidence/baseline/19-pci-config-space-full.txt`, `docs/evidence/EVIDENCE-GAPS.md`
  records `Status: `CLOSED`` for GAP-B5, and `docs/DELIVERABLES.md` and
  `docs/ROOT-ACTIONS.md` name the same file (round-2 closure table, row (e)).
  Where documents disagree, the "Status of record" line at the top of
  `docs/evidence/EVIDENCE-GAPS.md` decides.
- AC-2 and AC-4 counts in `docs/DELIVERABLES.md` section 1 and section 2.4:
  contradicted by the source documents and by direct count. Refused as stated;
  the source documents are correct.
- AC-6 archived payload figure "73 files" in `docs/evidence/packaging/07` and
  `docs/evidence/builds/17`: contradicted by the current tree, which yields 115.
  The archives are stale, not wrong at the time they were captured.

## Privilege audit

What the plan asserted versus what the host grants. `plan.yaml:29` states the
privilege-upgrade path "is separate and inert by default: it activates only if
sudo is later granted", and that "No task asserts granted privileges anywhere";
`plan.yaml:102` repeats it as an inert trigger and `plan.yaml:255` requires the
register dump to be "inert until a root user reads it". Verified: no task in the
plan claims a privilege the host does not have, and no evidence file records a
privileged command that the allowlist does not cover. Confirmed that the
privilege-upgrade path is documented as inert, with its activation procedure
(re-run the T3 captures and the T6 install/erase assertions, then flip the
corresponding GAP rows) written out in the plan and in `docs/ROOT-ACTIONS.md`.

What the host actually grants. `sudo -n -l` exits 0 and lists 19 NOPASSWD
entries: the 16 for this work (the three `/usr/local/sbin` helpers, `dmesg`,
`journalctl -k -b` in both forms, bare `dkms status`, `dkms
install|uninstall|build|remove -m sm750hdmifb -v 0.6.0`, `depmod -a`,
`modprobe` and `modprobe -r sm750hdmidrm`, `dnf install` of the exact t6 RPM
path, `dnf remove -y sm750hdmifb`) plus three pre-existing entries (`dmidecode`,
`ncu`, `nvprof`). The staged ruleset `/mega/tmp/sm750/10-sm750-debug.sudoers`
(4047 bytes, sha256
`d2141159a99e65ba3c150e20daba915babbe907674a80bfbce1fce598ed35a3b`) matches
`docs/ROOT-ACTIONS.md:46-49` and contains zero colons in its command lines, which
is why PCI addresses are reachable only through the three helpers. There is no
grant for a bare shell, `tee`, `cp`, `dnf` at large, `insmod` or `systemctl`.

Every root-required gap and its closing command, as of this report:
- PCI config space above 0x40 (GAP-B5, still GAP-PARTIAL):
  `sudo /usr/local/sbin/sm750-lspci > /mega/tmp/sm750/lspci-$(date -u +%Y%m%dT%H%M%SZ).txt`
  then store the transcript under `docs/evidence/` and flip the row.
  Note (2026-11-19, T27): superseded. This is the round-1 state; GAP-B5 is
  `CLOSED` against `docs/evidence/baseline/19-pci-config-space-full.txt`
  (round-2 closure table, row (e), and the GAP-B5 row in
  `docs/evidence/EVIDENCE-GAPS.md`).
- Scanout CRC (GAP, blocked by missing driver support): implement a
  `get_crc_sources` callback before any
  `sudo cat /sys/kernel/debug/dri/<N>/crtc-<M>/crc/data` can return data.
- External capture / pixel proof (GAP): attach a capture device or have the host
  owner inspect the SM750 monitor and record the observation.
- `dkms status -m sm750hdmifb -v 0.6.0` (used by `tests/check-rpm-dkms.sh` and by
  `docs/DELIVERABLES.md` section 3 as an assertion): not allowlisted, only bare
  `sudo -n dkms status` is. Closing command: grant the `-m`/`-v` form, or keep
  using the bare form and filter the output.
- `dkms remove -m sm750hdmifb -v 0.5.9 --all`: not allowlisted, so
  `tests/check-rpm-dkms.sh` skips it. It is no longer needed on this host (the
  `%posttrans` purge already removed the 0.5.9 registrations) but the closing
  command remains `sudo dkms remove -m sm750hdmifb -v 0.5.9 --all`.
- Removal of the orphan source tree: `sudo rm -rf /usr/src/sm750hdmifb-0.5.9`.
- Erase-state verification after `dnf remove`: the `%preun` behaviour is already
  evidenced in `docs/evidence/runtime/20-rollback.txt`; a repeat needs only the
  allowlisted `dnf remove -y sm750hdmifb` and bare `dkms status`.

## Residual risks for production

| Risk | Severity | Why it remains | Closing action |
| --- | --- | --- | --- |
| No pixel correctness proof: no scanout CRC, no external capture, no `/dev/dri` readback transcript | High | The driver registers no CRC source (`src/` has no `get_crc_sources`), no capture hardware is attached, and the monitor has not been visually inspected. Connector, modeset and client-attachment state are proven; what appears on the panel is not | Add a CRC source or capture the panel externally, then record the transcript under `docs/evidence/` and promote AC-3 tiers 4-6 |
| Untested kernels outside the three installed header trees (7.2.15-100, 7.3.3-100, 7.3.4-100) plus the 6.17.1 floor tree | Medium | The build matrix covers the 6.17 floor and the three installed trees only; `dkms.conf` `BUILD_EXCLUSIVE_KERNEL` admits 6.17 and newer, and A20 records that DKMS will auto-install on a kernel the release notes call untested | State the tested set in the release notes (already partly done at `docs/RELEASE-NOTES.md:14-19`) and re-run `tests/build-all-kernels.sh` against each new header tree before a distribution upgrade |
| GAP-B8: the source of the `-110` return among the five fallible `sm750_program_mode` calls is unidentified | Medium | A27 is fixed by surviving the failed-modeset vblank event (`src/sm750_drm.c:3105-3133`, `drm_crtc_vblank_on` at `:3131`, `sm750_arm_vblank_event` at `:3132`, 108/108 clean reproductions), but the failure still occurs; the fix removes the symptom, not the cause | Instrument the five call sites and record which one returns `-110`, then either retry or downgrade the mode explicitly. Note (2026-11-19, T27): the five sites are instrumented and the message names the stage (`docs/evidence/gap-b8/01-stage-instrumentation.txt`); the recording step waits on a recurrence, and no retry was added because a retry of a half-progressed modeset can corrupt state |
| IGT conformance limited to `kms_addfb_basic` | Medium | `docs/evidence/runtime/19-igt-0.6.0.txt` records 26 SUCCESS / 14 SKIP / 1 FAIL on one subtest family only; `kms_setmode`, `kms_cursor`, `kms_plane` and the rest of the IGT KMS suite are not run, and the VT ACL was installed late in the plan | Run the wider IGT KMS set as an unprivileged user now that the `/dev/tty0` ACL exists, and record the transcript |
| Reboot hazard after a package erase | Medium | `dnf remove` runs `%preun` `dkms remove --all`, which deletes the object file while the module stays loaded; a reboot in that state leaves card0 with no driver and the SM750 HDMI output dark (recorded at `docs/DELIVERABLES.md:167` and `docs/evidence/EVIDENCE-GAPS.md:591`) | Documented in [README.md](../README.md) section "If the card stops working after removing the package" (T27): ordered recovery from `dkms status` through `dnf install`/`dkms install` to `modprobe sm750hdmidrm`. The operational advice stands: avoid erasing the package on a machine whose only console is the SM750 output |
| Orphan source tree `/usr/src/sm750hdmifb-0.5.9` | Low | No RPM owns it (`rpm -ql sm750hdmifb` names no 0.5.9 path) and no task may remove it without root; it is inert but confuses anyone reading `/usr/src` | `sudo rm -rf /usr/src/sm750hdmifb-0.5.9` by the host owner; already documented in `docs/ROOT-ACTIONS.md` |
| Stale unowned directory `/lib/modules/6.18.13-200.fc43.x86_64` | None (cosmetic) | Left by the NVIDIA driver, owned by no package, containing only `extra/nvidia/*.ko` with no `build` link. It is not an installed kernel and no SM750 object was ever built for it. It makes `dkms` print "skipping 6.18.13-200.fc43.x86_64: matching kernel headers are absent" on every run, which reads like a packaging defect to a new reader | Documented at `docs/ENVIRONMENT.md:79-84`; the host owner may delete the directory, and nothing in the package needs to change |
| Optional static gate is not deterministic on this host | Low | `PATH=/usr/bin:/bin ./tests/check-static.sh` returned exit 0 on one run and exit 1 on another with `coccinelle: exit 255` / `spatch failed`, while sparse, smatch, cppcheck and pahole were stable | Treat the gate as advisory (as documented), or pin the coccinelle version and re-record `docs/evidence/builds/20`-`25` |

## What would change the verdict

To ACCEPT: (1) add the 16 dump-table registers to `docs/specs/REGISTER-MAP.md`
so its stated method covers all 69 registers referenced by `src/*.c`; (2) bring
`docs/DELIVERABLES.md` section 5.4 to the full `docs/` inventory and re-run its
section 2.7 self-check to an empty result, correcting the AC-2 and AC-4 counts
and the AC-3 evidence path; (3) either commit a readback transcript for the
tier-4 number and replace the tier-5 closing command with one that can work, or
delete both claims and let AC-3 rest openly on tiers 1-3 with pixel proof listed
as a gap.

To REJECT: (1) a `make check` or build-matrix failure in a clean clone, or any
compiler diagnostic attributed to `src/` - neither occurred; (2) a packaging
mismatch between the spec and the built RPM, or a `dkms` sandbox that does not
reach `built` - neither occurred; (3) evidence that the running module is not
the installed package's object - disproved here by the `srcversion` match; or
(4) a hardware claim that turns out to be contradicted by the device, which the
current evidence cannot reach because pixel proof is absent by design.

## Round 2 re-acceptance

Round 1 was reviewed at HEAD `332b997`. This round reviews HEAD `2f0d48b`,
which adds T23 (the seven documentation and evidence findings) and T24 (the
static-gate non-determinism). Reviewer: the orchestrator itself, inline, by
owner instruction; no subagent reviewed its own upstream work.

### Closure of the eight round-1 findings

| Finding | Closure | Verified by |
| --- | --- | --- |
| (a) register map covered 54 registers against 69 referenced | 16 dump-table registers added as rows; map now covers all 70 and reports `missing []` | the Map's own heredoc in `docs/specs/REGISTER-MAP.md` |
| (b) tier-4 readback claimed "48 nonzero bytes of 8294400" with no artefact | claim deleted; the tier now states the three independent blockers and a closing action | `grep -rn 'nonzero bytes\|8294400' docs/TEST-STRATEGY.md docs/evidence/` -> no hit |
| (c) tier-5 closing command could not work (no CRC source) | replaced by a statement that `src/` implements no CRC source, with the reason | `grep -c get_crc_sources src/*.c src/*.h` -> 0 |
| (d) `DELIVERABLES.md` self-check emitted 21 paths; counts and citations wrong | self-check emits nothing; 24/30 defect counts, 13/2/3 totals, AC-3 citation and GAP-B8 range all match their sources | `comm -23 <(git ls-files docs \| sort) <(grep -o 'docs/[A-Za-z0-9._/-]*' docs/DELIVERABLES.md \| sort -u)` -> empty |
| (e) GAP-B5 declared closed without a tracked capture | `docs/evidence/baseline/19-pci-config-space-full.txt` (174 lines, 9934 bytes) tracked; status `CLOSED` and the three citing places agree | `git ls-files --error-unmatch docs/evidence/baseline/19-pci-config-space-full.txt` |
| (f) three packaging logs were 0.5.9-era and unmarked | each carries a `# SUPERSEDED (T23, 2026-11-18):` header, unedited below it, pointing at the current run | file heads |
| (g) `TEST-STRATEGY.md` was still the 0.5.9 record | framing block names sections 1-9 as the 0.5.9 record and lists the 0.6.0 re-runs as a separate record | `docs/TEST-STRATEGY.md` sections 1 and 7 |
| (h) static gate flipped between PASS and coccinelle exit 255 | cause proved: spatch's libpython probe inherits `PKG_CONFIG_SYSROOT_DIR`; `tests/check-static.sh:37-46` clears the three variables, `:216`/`:237` name the patch, `:250` labels a 255 | ten consecutive runs, below |

Two round-1 claims were wrong and are corrected, not merely closed: the
orchestrator's own 326/87/28 register count (column-0 anchor) and the
reviewer's premise that `docs/evidence/builds/09-register-dump.log` does not
exist (it is tracked; the defect was that AC-3 cited only the denial).

### Re-run at `2f0d48b`

| Check | Command | Result |
| --- | --- | --- |
| Suite | `make CC=/usr/bin/gcc check` with the rootless libdrm environment | exit 0, `Ran 4 tests ... OK`, 17 recipe commands (`sed -n '32,48p' Makefile \| grep -cP '^\t'` -> 17) |
| Static gate, determinism | `./tests/check-static.sh` ten times with `PKG_CONFIG_SYSROOT_DIR`, `PKG_CONFIG_PATH` and `LD_LIBRARY_PATH` exported - the environment that used to fail | 10 of 10 exit 0, `static gate: PASS` ten times, `coccinelle: exit 0, 0 finding(s)` ten times |
| Release gate | `./build-package.sh` then `./tests/audit-release.sh` after the archive was rebuilt from the committed tree | "Release audit passed", exit 0; tarball 115 entries, 0 under `docs/plan`, `docs/evidence`, `docs/images` |
| Package and runtime | `sudo -n dkms status`; `/sys/module/sm750hdmidrm/version`; `modinfo -F srcversion` | exactly three `sm750hdmifb/0.6.0 ... installed` (7.2.15-100, 7.3.3-100, 7.3.4-100); `0.6.0`; `07E8F503FC7D839EEC5EE64` equals the loaded module |
| Specs | `git ls-files docs/specs` | `GAPS.md`, `INDEX.md`, `REGISTER-MAP.md`, `SHA256SUMS` - text only |

The stale `dist/` archive was the only failure seen while re-running: it had
been built before `332b997` was committed, so `audit-release.sh` reported
"Source archive does not match the tracked tree". Rebuilding it after the
commit resolved that; no source or test change was implicated.

### What is still open

- AC-3 tier 6: pixel proof. The monitor on the SM750 output has not been
  inspected; there is no `/dev/fb*`, no writeback connector and no CRC source,
  so nothing on this host can read back what the panel shows.
- `GAP-B8`: the fix makes an abandoned modeset finish its commit, but which of
  the five fallible calls in `sm750_program_mode` returns `-110` is still
  unproven (`src/sm750_drm.c:1312`, `:1316`, `:1319`, `:1346`, `:1349`).
- Host-owner cleanup, optional: `/usr/src/sm750hdmifb-0.5.9` (orphan tree, no
  RPM owns it) and `/lib/modules/6.18.13-200.fc43.x86_64` (unowned leftover
  directory; DKMS skips it with "matching kernel headers are absent").

### What would change this verdict

To REJECT: a failed `make check` or build-matrix run, a packaging mismatch
between spec and RPM, evidence that the running module is not the installed
object, or a hardware observation contradicting a claimed behaviour. None
occurred. AC-3 becomes PASS only with an external capture of the panel.

### Addendum 2026-11-19 (T26): driver-side scanout read path

The driver now owns a read path over the scanout region in VRAM: a CRTC CRC
source named `scanout` (`src/sm750_drm.c`:
`sm750_crtc_get_crc_sources`, `sm750_crtc_verify_crc_source`,
`sm750_crtc_set_crc_source`, and a vblank work item that calls
`drm_crtc_add_crc_entry`) and an `sm750_scanout` debugfs dump. Both read
through `sm750_crc_region()` and `sm750_scanout_crc32()`, both are bounded by
the `crc_window_bytes` parameter, and `tests/check-scanout-crc.sh` (opt-in
`make crc-check`) asserts their structural agreement on a live card.

Status after this addendum:

- AC-3 tier 4: the closing mechanism that round 2 listed as missing now
  exists. It is not yet evidenced on this host: `docs/evidence/scanout/04-checks.txt`
  records a `SKIP` because `/sys/kernel/debug` is mode 0700 and the run needs
  root, and `CONFIG_FB_DEVICE` is unset so there is no `/dev/fb*` to draw a
  pattern through. One root run produces the transcript; tier 4 stays `GAP`
  until that transcript exists.
- AC-3 tier 5: partial, and unchanged in substance. The CRC source is computed
  over the scanout source bytes in VRAM. It proves the buffer the display
  engine is fed, not the pixels it emits; the emitted stream is still not
  observable on this host. Tier 5 is not closed.

The round-2 text above is left as the historical record, including its
`get_crc_sources` -> 0 measurement, which was true of the tree it measured.
Two round-2 statements are therefore superseded rather than deleted: the
"still open" bullet that says the driver has no CRC source, and the defect row
that calls the absence of a readback path high risk.

### Addendum 2026-11-19 (T27): draw path without fbdev, and stage names

Two changes narrow the AC-3 tier-4 blocker to one item:

- The check no longer needs `/dev/fb*`. `tests/scanout-pattern.c` draws the
  black and the white frame through KMS (dumb buffer, `AddFB2`, `SetCrtc`), and
  that path was exercised unprivileged on the live card
  (`docs/evidence/scanout/03-readback.txt`). `CONFIG_FB_DEVICE` being unset
  (A24) therefore no longer blocks the tier-4 run; the only remaining blocker
  is that `/sys/kernel/debug` is mode 0700, so `crc/*` and `sm750_scanout`
  cannot be read or written as `uid 1005`. One root run of
  `tests/check-scanout-crc.sh` now produces the transcript; the row for it is
  proposed as row 8 in `docs/ROOT-ACTIONS.md` section 7.
- GAP-B8 identification no longer needs a debug rebuild. The `-110` line now
  reads `failed to enable HDMI mode: -110 at stage <name>`; the observation
  itself is still missing (`docs/evidence/gap-b8/01-stage-instrumentation.txt`).

Tier 4 and tier 5 stay `GAP`/partial: this addendum changes what blocks them,
not whether they are observed.

### Addendum 2026-11-19 (T26 follow-up): the driver publishes the CRC uapi

The T26 CRC source was unreachable: `drm_simple_display_pipe_init()` creates the
CRTC with the simple-pipe funcs and `sm750_crtc_funcs` is only swapped in
afterwards (`src/sm750_drm.c:4029`), so DRM's `drm_debugfs_crtc_crc_add()` saw no
CRC callbacks and never created `crtc-N/crc/`; that helper is not exported, so
the driver cannot ask for the files later. The driver now creates them itself,
`crtc-N/crc/{source,control,data}`, from `sm750_crtc_late_register()`
(`src/sm750_drm.c:3458`) and again from `sm750_regs_debugfs_add()`
(`src/sm750_drm.c:3909`), which covers both orders in which the kernel creates
the CRTC directory. The files implement the documented uapi: `source` reads
`scanout`; `control` reads `none`/`scanout` and accepts `none`, `auto` or
`scanout`; `data` emits the value count (`1`) once per open and then one
`"%u %08x"` line per frame (decimal vblank count, hex crc, no `0x` prefix) from
a 128-entry ring with one reader at a time.
`sm750_crc_work_fn()` computes the CRC once and feeds both the ring and
`drm_crtc_add_crc_entry()`.

Evidence and gates:

- Four kernels build with zero driver warnings, including 6.17.1-300 where the
  block compiles out: `docs/evidence/scanout/05-crc-debugfs-build.txt`.
- `tests/check-crc-uapi.sh`, called from `tests/check-drm-policy.sh` so from
  `make check`, asserts the three callbacks, the file creation, the data line
  format and the ring depth, and rejects four planted defects.

Status after this addendum:

- AC-3 tier 4: unchanged `GAP`. The run still needs root and the loaded module
  is still the packaged build (`docs/evidence/scanout/06-crc-debugfs-runtime.txt`).
- AC-3 tier 5: partial, and it stays partial until a root transcript exists. The
  source is now reachable from userspace, so IGT `igt_require_pipe_crc` no
  longer lacks `crc/control`; whether the entry stream is stable on the card is
  exactly what the missing run observes. The emitted pixel stream itself is
  still not observable on this host, so tier 5 would remain a statement about
  the scanout source buffer even after that run.

## Round 3: restore-path fix confirmed on hardware (2026-11-20)

This section is appended, not a rewrite: rounds 1 and 2 above stay as the
record of what they measured. Round 3 does not re-verdict AC-1 .. AC-7; it
records one hardware run that closes the "not proven on the card" caveat
carried by the A32 defect row and by the S10/S11 suite rows.

Run conditions: module built from the working tree, srcversion
`14ED4F27A83A6BB8AA445D2`, vermagic `7.3.4-100.fc43.x86_64`, version string
still `0.6.0` at the time of the run, loaded through
`sudo -n /usr/local/sbin/sm750-crc-cycle`. One card (`0000:01:00.0`), one panel
(`card0-HDMI-A-1`). Evidence:
`docs/evidence/runtime/22-restore-fix-hardware-proof.txt`.

### Affected criteria and their status after this run

| Criterion / row | Before round 3 | After round 3 | Basis |
| --- | --- | --- | --- |
| AC-3 tier 3, modeset with restore | PASS (0.5.9 and 0.6.0 held-client proofs) | PASS, unchanged | 20 mode changes `35@38:1024x768`, each followed by a client frame and exit, 20/20 completed |
| AC-3 tier 4, framebuffer readback | GAP (round 2: the "48 nonzero bytes of 8294400" readback was unevidenced; T26/T28/T30 later built the readback itself, still without a root transcript) | PASS for the scanout source buffer | Six PASS lines from the root CRC cycle, including `dump and CRC path agree for a black frame (offset 0, length 262144, crc 0xe20eea22)` and `nonzero scanout bytes are monotonic (black 0, white 262144 of 262144)` |
| AC-3 tier 5, scanout CRC stream | partial (round 2, and after the T26-T30 addendum: the source is reachable from userspace but stability on the card was unobserved) | PASS for the source buffer; the emitted pixel stream is still not observable | `CRC entries arrive and are stable over 12 static frames (crc 0xe20eea22)`; `CRC changes with frame content (black 0xe20eea22, white 0x06cf606c)` |
| AC-3 tier 6, external capture | GAP | GAP, unchanged | No capture hardware; nobody has looked at the panel in this run either |
| AC-3 overall | GAP | GAP, unchanged | Tier 6 is still open, so the criterion verdict does not move |
| Defect A32, restore path | fixed in source, pending on-card confirmation | fixed, confirmed on hardware | 95 enable events, zero fault lines, 30/30 restore cycles |
| Suite S11, restore-path gate | PASS (source gate only) | PASS (source gate) plus PASS on hardware | The run above; the harness form stays unexercised |
| Suite S10, console scanout | PASS (source), SKIP on this host | PASS on the card | `KDGETMODE` 0 (`KD_TEXT`) with `offset` 0 = `PANEL_FB_ADDRESS` 0x00000000, `nonzero` 28766, `crc32` 0x0204dd04 |

### Numbers from the run

| Measurement | Value |
| --- | --- |
| CRC cycle result | `RESULT: scanout CRC check passed`, exit 0, six PASS lines |
| Static-frame CRC | 0xe20eea22 over 12 static frames |
| Content-change CRC pair | black 0xe20eea22, white 0x06cf606c |
| Dump agreement (black) | offset 0, length 262144, crc 0xe20eea22 |
| Nonzero scanout bytes | black 0, white 262144 of 262144 |
| T31 blank-console diagnostic | 1 occurrence for the whole session (once-per-load latch) |
| Client exit/restore cycles | 30/30 succeeded, 0 failures |
| Mode changes `35@38:1024x768` with client frame and exit | 20/20 completed |
| Enable events (`staging enabled (`) | 95 total: 75 at 1920x1080 (`4147200`), 20 at 1024x768 (`1572864`) |
| Fault-line census over the session | 0 matches for `failed to enable HDMI mode`, `flip_done timed out`, `commit wait timed out`, `refcount_t: underflow`, `did not latch`, `panel did not acknowledge`, `enable-fail state`, `WARNING`, `BUG:` |
| S10 console scanout under `KD_TEXT` | `PANEL_FB_ADDRESS` 0x00000000, offset 0, nonzero 28766 of 262144, crc32 0x0204dd04 |

### What this run does not establish

- One card, one panel. Nothing about a second SM750, a second connector or a
  different panel.
- The 50 cycles were driven manually through the allowlisted sudo entries.
  `tools/sm750-restore-cycle.sh` refuses to run as non-root (`FAIL: must run as
  root`, exit 1, `tools/sm750-restore-cycle.sh:73`), so its 120-iteration form
  and its exit-code contract (0 clean / 1 environment / 2 no scanout readback /
  3 failure seen) are still unexercised.
- Two geometries only (1920x1080 and 1024x768); no 4K, no interlaced mode, no
  suspend/resume.
- Zero fault lines over 95 enable events lowers the failure rate; it does not
  prove the failure impossible. The RCA recorded the pre-fix rate as
  shape-dependent and low.
