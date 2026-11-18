# Project logbook

Chronological record of every action and change on this repository. Newest
entry last. ASCII only.

## Rules

1. Append an entry immediately, in the same session as the action. Do not batch
   entries for later.
2. Never rewrite, reorder, or delete an entry, including this preface.
3. A correction is a new entry that names the entry it corrects. The original
   stays as written, even when it is wrong.
4. One entry per action or change. Heading form, stable and greppable:
   `### <UTC date-time> | <actor> | <action>`.
5. Every entry states the files touched, the evidence path, and the outcome.
   Evidence that is not in the tree lives under `/mega/tmp/sm750/` and is named
   as a scratch path.
6. Timestamps are UTC. Where an evidence file records its own `# utc:` header,
   that value is used for the entry. Task-record times were kept on the host's
   local clock (UTC+03:00) and are converted here; where the two disagree the
   entry states both. Evidence files regenerated after their task finished carry
   the later mtime, so a capture can postdate the entry that first produced it
   (`docs/evidence/baseline/capture.sh` overwrites in place).
7. `docs/plan/20261117-sm750-driver-prod/plan.yaml` is the plan of record; this
   file is the record of what actually happened. When the two disagree, the
   entry names the disagreement instead of editing the plan.

Scope: work on `sm750hdmifb` under the plan of record. Host root actions are
additionally consolidated, with their exact commands and hashes, in
`docs/ROOT-ACTIONS.md`.

---

### 2026-11-17T15:42Z | gem-planner | plan created, wave 1 dispatched

- Action: wrote the plan of record and dispatched T1 (specification archive) and
  T2 (repository audit) as wave 1.
- Files: `docs/plan/20261117-sm750-driver-prod/plan.yaml`.
- Evidence: `docs/plan/20261117-sm750-driver-prod/plan.yaml:1-25` (tldr,
  `created_at`, revision), `:91-160` (T1, T2).
- Outcome: plan accepted at revision 3; T1 and T2 started. Planning discovery
  replaced three handoff premises: the repo is already an atomic DRM/KMS
  driver, the declared kernel floor is 6.17, and the SM750 is present and bound
  but unreachable without root. The record time is 18:42 host local; the
  `created_at` field says `2026-11-17T18:56:00Z`, which is the same clock
  labelled with `Z`, 14 minutes later.

### 2026-11-17T17:12Z | gem-researcher | discovery: rootless libdrm chain probed

- Action: verified that `make check` is reachable without root by extracting
  libdrm with `rpm2cpio`.
- Files: `docs/evidence/audit/rootless-libdrm-check.txt`.
- Evidence: `docs/evidence/audit/rootless-libdrm-check.txt` (927 B).
- Outcome: the rootless method is normative, not a fallback. Captured during
  planning discovery, so the file predates the plan write in this log.

### 2026-11-17T17:18Z | gem-researcher | discovery: identity and layout recorded

- Action: recorded HEAD, branch, remotes, layout and the declared kernel range.
- Files: `docs/evidence/audit/identity-and-range.txt`.
- Evidence: `docs/evidence/audit/identity-and-range.txt`.
- Outcome: HEAD `27db03b2e9e7e0b0afef0a52ff4b2e8cd175fb1b` on `main`, origin
  `polaris.root.sx`, upstream `github.com/KodeMunkie/sm750hdmifb`, 76 tracked
  files, `src/` 7427 `.c` LOC and 2006 `.h` LOC.

### 2026-11-17T17:20Z | gem-researcher | discovery: release gate and toolchain recorded

- Action: recorded the failing release gate and the host toolchain.
- Files: `docs/evidence/audit/release-gate-and-environment.txt`.
- Evidence: `docs/evidence/audit/release-gate-and-environment.txt` (3246 B).
- Outcome: `tests/audit-release.sh` fails for want of an `rpmbuild` spec;
  `gcc` is 15.3.1 against kernel `CONFIG_GCC_VERSION=150301`.

### 2026-11-17T17:22Z | gem-researcher | T1 register map written

- Action: mapped every MMIO register used by `src/*.c` to a citation.
- Files: `docs/specs/REGISTER-MAP.md`, `docs/specs/GAPS.md`.
- Evidence: `docs/specs/GAPS.md` and `docs/specs/REGISTER-MAP.md`.
- Outcome: each unresolved specification question names a fallback rung, so no
  fix is blocked on a vendor document.

### 2026-11-17T17:25Z | gem-researcher | T1 complete, specification archive indexed

- Action: wrote the source index and the checksum list; closed T1.
- Files: `docs/specs/INDEX.md`, `docs/specs/SHA256SUMS`.
- Evidence: `docs/specs/INDEX.md`.
- Outcome: T1 `completed`. Source URL, version, date, SHA-256 and authority are
  recorded per document; no vendor PDF is committed, which keeps
  `docs/PROVENANCE.md` true and the source tarball free of vendor material.

### 2026-11-17T17:26Z | gem-researcher | T2 complete, defect inventory published

- Action: closed T2 with `docs/AUDIT.md`, 24 defects ranked S1-S4, each with a
  reproduction command and an observed result.
- Files: `docs/AUDIT.md`, `docs/evidence/audit/privilege-probe.txt`.
- Evidence: `docs/evidence/audit/privilege-probe.txt` (2244 B);
  `docs/AUDIT.md`.
- Outcome: T2 `completed`. `sudo -n -l` permitted only `/usr/bin/dmidecode`,
  `/usr/local/cuda/bin/ncu` and `/usr/local/cuda/bin/nvprof`.

### 2026-11-17T17:36Z | gem-devops | T3 complete, rootless toolchain and baseline captured

- Action: provisioned the rootless toolchain and captured the readable hardware
  baseline; wrote the host document and the gap list.
- Files: `docs/ENVIRONMENT.md`, `docs/evidence/EVIDENCE-GAPS.md`,
  `docs/evidence/baseline/capture.sh`, `docs/evidence/baseline/00..17-*.txt`.
- Evidence: `docs/evidence/baseline/00-host-identity.txt`, header
  `# utc: 2026-11-17T18:31:29Z`; `docs/evidence/baseline/09-denials.txt`.
- Outcome: T3 `completed` at 20:36 host local. `make check` exits 0 with 17
  recipe commands rootless. Every privilege denial is recorded verbatim with its
  exit status. The captures were written 55 minutes after the completion mark,
  because `capture.sh` rewrites them in place; the corpus is the later run, and
  its `# utc:` headers are authoritative for the content.

### 2026-11-17T18:33Z | gem-implementer | T5 started (retry after provider outage)

- Action: dispatched T5 (surgical fixes, debugfs register dump, build matrix)
  again after the first attempt was lost to a provider outage.
- Files: none at dispatch.
- Evidence: `docs/plan/20261117-sm750-driver-prod/plan.yaml` T5 record,
  `retries_used: 1`.
- Outcome: T5 running. The retry did not change T5 scope or file ownership.

### 2026-11-18T04:42Z | gem-implementer | T5 `make check` green after fixes

- Action: ran `make check` under the rootless libdrm chain after the fixes.
- Files: `docs/evidence/builds/01-make-check.log`.
- Evidence: `docs/evidence/builds/01-make-check.log`, header
  `# utc: 2026-11-18T04:42:22Z`.
- Outcome: exit 0, 17 recipe commands, no compiler diagnostic from `src/`.

### 2026-11-18T04:44Z | gem-implementer | T5 build matrix over the installed trees

- Action: built all three scanout defaults against every installed header tree.
- Files: `docs/evidence/builds/02-check-all-kernels.log`.
- Evidence: `docs/evidence/builds/02-check-all-kernels.log`, header
  `# utc: 2026-11-18T04:44:36Z`.
- Outcome: exit 0, `Built 9 sm750hdmidrm kernel/format combinations`.

### 2026-11-18T04:45Z | gem-implementer | T5 per-tree matrix logs

- Action: recorded each tree separately, 7.2.15-100, 7.3.3-100, 7.3.4-100.
- Files: `docs/evidence/builds/03-kernel-7.2.15-100.log`,
  `docs/evidence/builds/04-kernel-7.3.3-100.log`,
  `docs/evidence/builds/05-kernel-7.3.4-100.log`.
- Evidence: headers `2026-11-18T04:45:56Z`, `04:46:10Z`, `04:46:24Z`.
- Outcome: `Built 3` per tree. 7.2.13-100 no longer has a `build` link on this
  host, so the recorded matrix is 7.2.15/7.3.3/7.3.4.

### 2026-11-18T04:48Z | gem-implementer | T5 6.17.1 floor tree built

- Action: built against the `rpm2cpio`-extracted 6.17.1-300.fc43 tree.
- Files: `docs/evidence/builds/06-kernel-6.17.1.log`.
- Evidence: `docs/evidence/builds/06-kernel-6.17.1.log`, header
  `# utc: 2026-11-18T04:48:03Z`.
- Outcome: exit 0, `Built 3`; the declared floor is covered rootless.

### 2026-11-18T04:48Z | gem-implementer | T5 package and release audit

- Action: built the `.deb` and source tarball, then ran the release audit.
- Files: `docs/evidence/builds/07-build-package.log`,
  `docs/evidence/builds/08-audit-release.log`.
- Evidence: headers `# utc: 2026-11-18T04:48:48Z` in both files.
- Outcome: both exit 0. The audit still reports the absent RPM spec, which T6
  owns.

### 2026-11-18T04:49Z | gem-implementer | T5 register dump attempted, denied without root

- Action: exercised the new debugfs `regs` file as uid 1005.
- Files: `docs/evidence/builds/09-register-dump.log`.
- Evidence: `docs/evidence/builds/09-register-dump.log`, header
  `# utc: 2026-11-18T04:49:02Z`.
- Outcome: read denied, because the file is `0444` under a root-only debugfs
  directory. GAP-B4 stays open with `sudo /usr/local/sbin/sm750-regs` as its
  closing command.

### 2026-11-18T04:51Z | gem-implementer | T5 complete, before/after and warning scan

- Action: recorded the before/after form of every fixed defect and scanned all
  build logs for warnings attributable to `src/`.
- Files: `docs/evidence/builds/10-defect-before-after.log`,
  `docs/evidence/builds/11-warnings-scan.log`, `docs/DEFECTS.md`.
- Evidence: headers `2026-11-18T04:51:14Z` and `04:51:54Z`.
- Outcome: T5 `completed`. No warning originates in `src/*.c` or `src/*.h`; the
  only remaining notes are `pahole version differs` and `compiler differs`.

### 2026-11-18T05:43Z | gem-devops | T6 RPM spec and DKMS gate accepted after one rejection

- Action: ran `./tests/check-rpm-dkms.sh` against the first spec, was rejected,
  corrected the scriptlet assertions, and passed review.
- Files: `docs/evidence/packaging/0.5.9/01..07-*.log`,
  `docs/PACKAGING-RPM.md`, `packaging/sm750hdmifb.spec`.
- Evidence: `docs/evidence/packaging/0.5.9/01-rpmbuild.log`, header
  `# utc: 2026-11-18T05:43:46Z`; acceptance mark in the task record at 08:20
  host local.
- Outcome: T6 `completed` with `retries_used: 1`. The first attempt was rejected
  for its scriptlet assertions, not for the build; `rpmbuild -ba` exited 0 and
  the payload matched `git ls-files` (73 files). The record order is odd and is
  kept as found: the 0.5.9 gate log is archived 23 minutes after the acceptance
  mark, so the log is a re-run, not the run that was reviewed.

### 2026-11-18T06:15Z | host owner | udev ACL rule installed

- Action: installed `/etc/udev/rules.d/99-sm750-coder-acl.rules`, reloaded the
  rules and triggered the DRM subsystem, granting `u:coder:rw` on the SM750
  card node at every probe.
- Files: `/etc/udev/rules.d/99-sm750-coder-acl.rules` (0644 `root:root`, 710 B),
  staged copy `/mega/tmp/sm750/99-sm750-coder-acl.rules`.
- Evidence: `docs/ENVIRONMENT.md` section 5.1;
  `docs/evidence/builds/12-version-and-gapb3.log`; exact command in
  `docs/ROOT-ACTIONS.md`.
- Outcome: `getfacl /dev/dri/by-path/pci-0000:01:00.0-card` reports
  `user:coder:rw-` and `modetest -c` opens `card0` unprivileged. GAP-B3 moves
  from `GAP` to `PARTIAL`; the manual `setfacl` sudoers line stays commented.

### 2026-11-18T06:18Z | gem-documentation-writer | T7 complete, deliverables index published

- Action: wrote the deliverable index mapping acceptance criteria 1-7 to paths
  and verification commands, plus the clean-checkout reproduction guide.
- Files: `docs/DELIVERABLES.md`, `README.md` (Developers list).
- Evidence: `docs/DELIVERABLES.md` sections 1-5.
- Outcome: T7 `completed`. Section 2.7 defines the `comm -23` check that every
  file under `docs/` is named by the index. The index was saved again at 09:56
  host local, 32 minutes after the completion mark.

### 2026-11-18T06:39Z | gem-implementer | T9 gates at 0.6.0

- Action: re-ran the 6.17.1 floor tree and the build matrix at 0.6.0, then
  `make check`, the package build and the release audit.
- Files: `docs/evidence/builds/15-kernel-6.17.1-0.6.0.log`,
  `docs/evidence/builds/14-check-all-kernels-0.6.0.log`,
  `docs/evidence/builds/13-make-check-0.6.0.log`,
  `docs/evidence/builds/16-build-package-0.6.0.log`.
- Evidence: headers `06:41:24Z`, `06:39:01Z`, `06:53:59Z`, `06:54:20Z`.
- Outcome: all exit 0; `Built 3`, `Built 9` and 17 recipe commands reproduced at
  0.6.0.

### 2026-11-18T06:51Z | gem-implementer | T9 version and access capture

- Action: proved the 0.6.0 declarations in spec, `dkms.conf` and driver agree,
  and captured the card-node access state.
- Files: `docs/evidence/builds/12-version-and-gapb3.log`.
- Evidence: `docs/evidence/builds/12-version-and-gapb3.log`, header
  `# utc: 2026-11-18T06:51:50Z`.
- Outcome: version declarations consistent; the built object reports 0.6.0.

### 2026-11-18T06:54Z | gem-devops | RPM/DKMS gate and sudoers regeneration verified

- Action: ran the full RPM/DKMS gate at 0.6.0 and re-verified the regenerated
  sudoers allowlist.
- Files: `docs/evidence/builds/17-check-rpm-dkms-0.6.0.log`,
  `docs/evidence/builds/18-sudoers-verify-0.6.0.log`,
  `docs/evidence/packaging/01..07-*.log`.
- Evidence: header `# utc: 2026-11-18T06:54:35Z`;
  `docs/evidence/packaging/01-rpmbuild.log`, header
  `# utc: 2026-11-18T06:55:24Z`.
- Outcome: gate exit 0. Colon audit of the allowlist returns 0; `visudo -c -f`
  parses it standalone and appended to a copy of the stock `/etc/sudoers`.

### 2026-11-18T06:59Z | gem-implementer | T9 complete, release 0.6.0

- Action: closed the version bump: `dkms.conf`, spec, `MODULE_VERSION`, release
  notes and the built artifacts all say 0.6.0.
- Files: `dkms.conf`, `packaging/sm750hdmifb.spec`, `src/sm750_drm.c`,
  `docs/RELEASE-NOTES.md`, `dist/`.
- Evidence: `dist/sm750hdmifb_0.6.0_all.deb`,
  `dist/sm750hdmifb-0.6.0-source.tar.gz`, `dist/SHA256SUMS`,
  `dist/RELEASE-AUDIT.txt` (written 09:54 host local);
  `docs/evidence/builds/12-version-and-gapb3.log`.
- Outcome: T9 `completed`. The loaded module is still the 0.5.9 build, so no
  0.6.0 behaviour is live until T11 reloads it.

### 2026-11-18T08:19Z | gem-devops | T10 runtime validation running

- Action: started the rootless runtime tiers against the live device and
  captured the pre-fix baseline.
- Files: `docs/evidence/runtime/01-original-state.txt`,
  `docs/evidence/runtime/02-modetest-connector.txt`,
  `docs/evidence/runtime/03-modetest-properties.txt`.
- Evidence: `docs/evidence/runtime/01-original-state.txt`, capture point
  `2026-11-18T09:27:44+03:00`.
- Outcome: in progress. The module under test is the stale pre-fix 0.5.9 build
  (no `/sys/module/sm750hdmidrm/version`, no `regs` entry), so every runtime
  result is labelled a pre-fix baseline.

### 2026-11-18T08:23Z | gem-planner | T13 dispatched

- Action: dispatched the cursor-plane alpha warning fix as wave 8.
- Files: none at dispatch.
- Evidence: `docs/plan/20261117-sm750-driver-prod/plan.yaml` T13 record; the
  warning text is in `docs/evidence/runtime/07-kernel-log.txt`.
- Outcome: T13 running. The defect is new evidence from the now-readable kernel
  log, not a reopen of a `docs/AUDIT.md` row.

### 2026-11-18T08:37Z | host owner | helpers installed, sudoers replaced, first VBIOS dump

- Action: installed the three helpers in `/usr/local/sbin`, replaced
  `/etc/sudoers.d/10-sm750-debug` with the 0.6.0 allowlist, and ran the VBIOS
  helper once.
- Files: `/usr/local/sbin/sm750-regs` (0755, 1165 B),
  `/usr/local/sbin/sm750-lspci` (0755, 792 B),
  `/usr/local/sbin/sm750-vbios-dump` (0755, 648 B, v1 body),
  `/etc/sudoers.d/10-sm750-debug` (0440 `root:root`).
- Evidence: `sudo -n -l` lists 19 NOPASSWD entries, all dkms lines and the
  `dnf install` path at 0.6.0; `/mega/tmp/sm750/vbios-01-00-0.bin` (4096 B,
  11:42 host local); `docs/ROOT-ACTIONS.md`.
- Outcome: the allowlist is live and the grants work. The dump is 4096 bytes of
  a 65536-byte ROM, which is the defect root-caused 17 minutes later.

### 2026-11-18T08:54Z | gem-devops | v1 VBIOS truncation root-caused, v2 staged

- Action: proved the truncation is a sysfs read-size cap and staged helper v2.
- Files: `/mega/tmp/sm750/sm750-vbios-dump` (v2, 1092 B, sha256
  `9e6c5db7853e3a58160d83c63aaee01144b20061a98a57c241188b3b6dd62a8f`),
  `/mega/tmp/sm750/sm750-vbios-dump.v1.bak`,
  `/mega/tmp/sm750/vbios-probe.bin`.
- Evidence: the cap reproduces on an unrelated attribute:
  `/sys/kernel/btf/nf_conntrack` is 26549 bytes, `dd bs=65536 count=1` yields
  4096, `dd bs=4096` yields all 26549.
- Outcome: v1 used `dd bs=65536 count=1`; a sysfs binary attribute returns at
  most one page per `read(2)`, so dd takes the short read as end of file. v2 uses
  `dd bs=4096` with no count and exits 2 when the size is not 65536. The
  reinstall is the one outstanding root action.

### 2026-11-18T09:29Z | gem-devops | T10 runtime captures 04-07 written

- Action: captured the modeset, kmscube, IGT and kernel-log tiers.
- Files: `docs/evidence/runtime/04-modeset.txt`,
  `docs/evidence/runtime/05-kmscube.txt`, `docs/evidence/runtime/06-igt.txt`,
  `docs/evidence/runtime/07-kernel-log.txt`.
- Evidence: `docs/evidence/runtime/07-kernel-log.txt`, capture point
  `2026-11-18T12:19:39+03:00`, `sudo -n dmesg` exit 0 with 2017 lines.
- Outcome: S4 and S5 pass as pre-fix baselines, S6 IGT stays a gap. The file also
  records that `docs/evidence/EVIDENCE-GAPS.md:87-89` (journalctl `-k -b` gives
  0 lines) is contradicted by measurement; that file was not edited by T10.

### 2026-11-18T09:41Z | gem-documentation-writer | T14 logbook and root-action runbook written

- Action: created this logbook, the contributor contract and the consolidated
  root-action runbook; refreshed the sudoers section of the host document and
  the root-only table of the deliverables index; added the README pointers.
- Files: `docs/LOGBOOK.md`, `AGENTS.md`, `docs/ROOT-ACTIONS.md`,
  `docs/ENVIRONMENT.md` section 5.2, `docs/DELIVERABLES.md` section 3,
  `README.md`.
- Evidence: `git show --stat` of commit `docs: add project logbook and
  root-action runbook`; `docs/ROOT-ACTIONS.md`.
- Outcome: the logging rule now has a home a future contributor will read, and
  every host root action is reproducible from one file after `/mega/tmp/` is
  wiped. Backfilled from `plan.yaml`, `docs/evidence/` and `git log`; nothing
  before 2026-11-17T17:12Z is claimed, because no record of it exists here.

### 2026-11-18T09:56Z | gem-implementer | T13 cursor alpha warning captured before the fix

- Action: reproduced the cursor-plane alpha warning from the loaded module and
  stored the before-fix capture.
- Files: `docs/evidence/runtime/cursor-alpha-01-warning-before.txt`.
- Evidence: same file, capture point `2026-11-18T12:56:12+03:00`; the warning is
  `[drm] [PLANE:40:sm750-cursor] pixel format with alpha exposed but blend mode
  not setup. Please fix.`
- Outcome: T13 evidence collected. The loaded module is still the pre-fix 0.5.9
  build, so the fix is verifiable only in the 0.6.0 object until T11 installs it.

### 2026-11-18T10:01Z | gem-documentation-writer | T14 committed

- Action: committed the six T14 paths and confirmed the commit boundary.
- Files: `AGENTS.md`, `README.md`, `docs/DELIVERABLES.md`, `docs/ENVIRONMENT.md`,
  `docs/LOGBOOK.md`, `docs/ROOT-ACTIONS.md`.
- Evidence: `git show --stat HEAD` lists exactly those six paths and nothing
  else; each of the six is ASCII (0 non-ASCII bytes).
- Outcome: commit `docs: add project logbook and root-action runbook` on `main`
  above `27db03b`. Unrelated in-flight work by other tasks stays uncommitted.
  The deliverables index gained a row for the T13 capture so its section 2.7
  `comm -23` check still returns nothing.

### 2026-11-18T10:05Z | gem-planner | T10 accepted, T15 and T16 added and dispatched

- Action: marked T10 completed, recorded its four findings in the plan of record as
  decisions, and added two diagnosis tasks (T15 addfb size-max, T16 HDMI -110 episode)
  at wave 8, then dispatched both to gem-debugger.
- Files: `docs/plan/20261117-sm750-driver-prod/plan.yaml` (T10 status; four decisions;
  T15 and T16 task blocks; T8 depends_on extended to both).
- Evidence: `docs/evidence/runtime/01-original-state.txt` .. `07-kernel-log.txt`
  (T10); the plan blocks carry the failure text and code locations for T15 and T16.
- Outcome: 9 of 16 tasks completed. T15 and T16 run diagnosis only and must not edit
  `src/`. Four tasks are now in flight: T13 (cursor alpha), T15, T16.
- Note: `docs/evidence/EVIDENCE-GAPS.md:87-89` still states that the kernel log yields
  0 lines, which T10 contradicted with 2017 lines from both `sudo -n dmesg` and
  `sudo -n journalctl -k -b -q --no-pager`. The correction belongs to T11, which owns
  that file; until then the contradiction stands recorded in
  `docs/evidence/runtime/07-kernel-log.txt`.

### 2026-11-18T10:07Z | gem-planner | T14 accepted

- Action: verified the T14 deliverables against its seven acceptance criteria and
  marked T14 completed in the plan of record.
- Files: `docs/plan/20261117-sm750-driver-prod/plan.yaml` (T14 status).
- Evidence: `git show --stat 6332870` lists exactly the six T14 paths
  (`AGENTS.md` 63 lines, `README.md`, `docs/DELIVERABLES.md`,
  `docs/ENVIRONMENT.md`, `docs/LOGBOOK.md` 373 lines, `docs/ROOT-ACTIONS.md`
  436 lines); 31 logbook entries with ascending UTC timestamps, first
  2026-11-17T15:42Z; helper bodies in `docs/ROOT-ACTIONS.md` match the real files
  by sha256 (sm750-regs `1a345ff0`, sm750-lspci `4b4f555a`, vbios v1 `e2f6f687`,
  vbios v2 `9e6c5db7`, udev rules `1bf4cf01`); zero non-ASCII bytes in all six.
- Outcome: accepted. Two documented deviations from the task text are correct
  behaviour, not errors: the root-only table now carries the values measured at
  2026-11-18T09:36Z (169860 bytes, 240 sm750 lines) instead of the earlier
  154236/150, and the T13 cursor capture was added to the deliverables index
  before the amend so the section 2.7 comm check stayed green.

### 2026-11-18T10:12Z | host owner | VBIOS helper v2 installed

- Action: reinstalled `/usr/local/sbin/sm750-vbios-dump` from the staged v2 body
  (`sudo install -m 0755 -o root -g root /mega/tmp/sm750/sm750-vbios-dump
  /usr/local/sbin/sm750-vbios-dump`).
- Files: `/usr/local/sbin/sm750-vbios-dump` (host path, not in the tree).
- Evidence: file is `-rwxr-xr-x root:root` 1092 bytes, sha256
  `9e6c5db7853e3a58160d83c63aaee01144b20061a98a57c241188b3b6dd62a8f`, identical to
  the staged copy; line 28 reads `dd if="$DEV/rom" of="$OUT" bs=4096`.
- Outcome: the page-cap defect is no longer installed. T12 was dispatched to take
  the full 64 KiB capture and close GAP-B1.

### 2026-11-18T10:24Z | orchestrator | VBIOS image size corrected: 49152 bytes, not 65536

- Action: corrected the image-size expectation after measuring the captured ROM
  `/mega/tmp/sm750/vbios-01-00-0.bin` directly, and sent a correction follow-up to
  T12 (session `ses_e11dc74e8ffeOvLqdWWNlBnyMk`).
- Files: `docs/LOGBOOK.md`, `docs/plan/20261117-sm750-driver-prod/plan.yaml`.
- Evidence: the capture is 49152 bytes, sha256
  `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`, whole-image
  byte sum 0 mod 256. Header byte at 0x02 is `0x60` (96 blocks of 512) and the PCIR
  image-length field at 0x2c is also `0x0060`, so the option ROM is 48 KiB.
- Outcome: this corrects the previous entry, which said T12 would take a 64 KiB
  capture. The helper's `exit 2` with `WARNING size is 49152, expected 65536` is a
  stale constant, not a truncated read; the installed helper is left unchanged
  because the sudoers grant is on the path and an edit needs the host owner again.

### 2026-11-18T10:24Z | orchestrator | T17 added: VBIOS reverse engineering to a bit-exact rebuild

- Action: inserted task T17 into the plan at wave 9 (`depends_on: [T12]`,
  agent `gem-implementer`, `context_cluster: vbios-re`, `critic_signals:
  [architecture]`), and moved T8 to wave 10 with T12 and T17 added to its
  dependencies.
- Files: `docs/plan/20261117-sm750-driver-prod/plan.yaml` (17 tasks, re-validated
  with `yaml.safe_load`), `docs/LOGBOOK.md`.
- Evidence: the byte-exact 16-bit pipeline was proven on this host in
  `/mega/tmp/sm750/probe16`: a `.code16` source assembled with `as --32` and linked
  with a script using `OUTPUT_FORMAT(binary)` produced exactly
  `ea 05 00 00 f0 b8 c0 03 c3`. `gcc -m16 -c` of a trivial function emitted
  `66 55 push %ebp`, so compiled C cannot emit byte-exact 16-bit code; binutils
  2.45.1 is present, nasm/yasm/radare2 are not.
- Outcome: T17 is defined but not dispatched; it waits for T12 so the structure map
  and the capture agree. Requested by the repo owner (m00644): reverse engineering of
  the VBIOS into C with build verification accurate to the bit and byte.

### 2026-11-18T10:33Z | host owner + orchestrator | 16-bit toolchain completed and probed

- Action: the host owner installed nasm, yasm and radare2 (and reported clang/clang++/
  llvm); the orchestrator probed every candidate emitter and decoder and updated T17
  with the verified invocations.
- Files: `docs/plan/20261117-sm750-driver-prod/plan.yaml`, `docs/LOGBOOK.md`.
  Scratch probes: `/mega/tmp/sm750/probe-nasm`, `/mega/tmp/sm750/pylib`.
- Evidence: nasm 2.16.03 and yasm 1.3.0 with `-f bin` both produced the exact 13 bytes
  `ea 09 00 00 f0 b8 c0 03 c3 c8 0a 00 00`; ndisasm, objdump `-m i8086`, r2 raw mode,
  llvm-mc `--show-encoding` all decode/encode 16-bit code correctly; capstone 5.0.9 and
  unicorn 2.1.4 installed rootlessly into `/mega/tmp/sm750/pylib` and verified
  (`PYTHONPATH=/mega/tmp/sm750/pylib`); qemu-system-i386 exists but emulates no SM750.
- Outcome: two gotchas recorded - nasm has no `ljmp` (write `jmp 0xf000:label`), and
  `r2 -B 0xc0000` mis-seeks while raw offsets work; `gcc` on PATH is CUDA's 14.4.1, so
  scripts must call `/usr/bin/gcc` (15.3.1). No further packages are required for T17.

### 2026-11-18T10:33Z | gem-devops | T12: VBIOS captured at 48 KiB, GAP-B1 closed

- Action: ran the installed v2 helper through the existing path-based sudo grant
  (`sudo -n /usr/local/sbin/sm750-vbios-dump`, helper sha256 `9e6c5db7` re-verified
  identical to the staged copy), then verified the image, the ROM-enable restore and
  the ROM BAR state. No modeset, no module reload, no RPM install.
- Result: exit 2, 49152 bytes, sha256
  `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`. Exit 2 is
  SUCCESS here: the image is complete at 48 KiB (header size byte 0x02 = 0x60 = 96
  blocks, PCIR image length at 0x2c = 0x0060, file length equals declared length,
  whole-image byte sum 0 modulo 256, bytes 0x815d..0xbfff pure 0xcc padding). The
  helper's `EXPECT=65536` is a stale constant, not a short read; the earlier task
  premise that the layout is 64 KiB was wrong. A second read to
  `/mega/tmp/sm750/t12/retry.bin` was byte-identical.
- Structure as read: `55 aa` signature; entry `55 push bp / aa stos / 60 pusha /
  e9 50 12 jmp 0xc1256`; PCIR pointer at 0x18 -> structure at 0x1c; vendor 0x126f,
  device 0x0750, class 0x030000 (display controller), structure length 24, code type
  x86, indicator 0x80 (last image); VBE 2.0 block at 0x7f whose OEM-string far pointer
  resolves to the banner; strings "Version 1.00.59-", "05/14/19 16:25", "Silicon
  Motion SM750 VGA BIOS (CRT)", "SM750". Undetermined and left as such: the intended
  span of the PCIR checksum byte 0x6b, the VBE mode list, and the VBE total-memory
  field (not populated - the bytes at 0x91 are the ASCII string "SM750"). The CRT
  banner is a label, not a capability statement; nothing is claimed about HDMI from
  the image.
- ROM restore: `/sys/bus/pci/devices/0000:01:00.0/rom` back to `-rw------- root:root
  65536` (mtime 13:12:28 +0300, the trap's `echo 0`) and the BAR reads
  `Expansion ROM at c7400000 [disabled] [size=64K]` again.
- Files: `docs/evidence/baseline/18-vbios-dump.txt` (new),
  `docs/evidence/EVIDENCE-GAPS.md` (GAP-B1 closed, summary row, journalctl
  correction), `docs/DELIVERABLES.md` (section 3 VBIOS row and the section 2.7
  index), `docs/TEST-STRATEGY.md` (the VBIOS row of the coverage table),
  `docs/LOGBOOK.md`. The image stays at `/mega/tmp/sm750/vbios-01-00-0.bin` and is
  not in the tree and not committed.
- Evidence: `docs/evidence/baseline/18-vbios-dump.txt`; verbatim helper streams in
  `/mega/tmp/sm750/t12/{dump.stdout,dump.stderr,r.out,r.err}`.
- Correction recorded in EVIDENCE-GAPS.md: the zero-line `journalctl -k -b` claim
  (GAP-B2 text) was measured without the sudo grant. With the grant the same command
  returns 2017 lines (T10, `docs/evidence/runtime/07-kernel-log.txt`) and the
  2026-11-18T09:36Z `sudo -n dmesg` capture is 169860 bytes / 240 `sm750` lines. The
  original paragraph is kept and the correction names it.
- Outcome: accepted. GAP-B1 is closed with the image verified, not merely captured.
  Two follow-ups for other owners: the helper's `EXPECT` constant should become
  49152 (root-owned host path; needs the host owner, not this task), and
  `docs/ROOT-ACTIONS.md` rows 4 and 5 (GAP-B1 attempt truncated / reinstall v2) are
  now both satisfied and should be marked done by that file's owner.

### 2026-11-18T10:36Z | gem-implementer | T13 cursor plane declares its blend mode (defect A25)

- Action: fixed the one defect the kernel log reported that `docs/AUDIT.md` never
  inventoried: `[PLANE:40:sm750-cursor] pixel format with alpha exposed but blend
  mode not setup`. The DRM core warns only when a plane exposes a format with
  alpha while `plane->blend_mode_property` is NULL
  (`validate_blend_mode_for_alpha_formats()` in `drivers/gpu/drm/drm_mode_config.c`,
  run from `drm_mode_config_validate()` at `drm_dev_register`). Route chosen: keep
  `DRM_FORMAT_ARGB8888` and create the blend-mode property, offering only
  `BIT(DRM_MODE_BLEND_PREMULTI)`; adding
  `drm_plane_create_blend_mode_property()` in the `hardware_cursor` block of
  `sm750_modeset_init` with a comment that records the reasoning. XRGB8888 was
  rejected because the cursor path really does consume alpha
  (`sm750_cursor_encode()` dithers it over three palette entries) and because
  `sm750_cursor_unpremultiply()` divides colour by alpha, so premultiplied ARGB is
  the contract the hardware already implements; dropping alpha would also break
  compositors that hand a cursor plane ARGB8888. COVERAGE is not offered: this
  driver unpremultiplies, it never premultiplies. `drm_plane_create_alpha_property()`
  is deliberately absent - the hardware has no plane-wide alpha factor, and the
  core check does not ask for one. No `LINUX_VERSION_CODE` guard is needed: the
  prototype is identical in 6.17, 7.2 and 7.3, and 6.17's `WARN_ON` requires
  PREMULTI in the mask while 7.2/7.3 accept it. `tests/check-hardware-cursor.sh`
  gained three requirements and a negative gate rejecting
  `drm_plane_create_alpha_property`; it failed red before the driver change.
- Files: `src/sm750_drm.c` (include at :30, comment :3473-3490, call :3491),
  `tests/check-hardware-cursor.sh` (:32-33, :43-45), `docs/DEFECTS.md` (header
  :4-8, row A25 :46, section :90-143), `docs/RELEASE-NOTES.md` (0.6.0 bullet),
  `docs/evidence/EVIDENCE-GAPS.md` (GAP-B2 :58-147, table row :398, closing
  paragraph :405-410), `docs/DELIVERABLES.md` (:25, :27, :394),
  `docs/evidence/runtime/cursor-alpha-01-warning-before.txt`,
  `docs/evidence/builds/19-cursor-alpha-fix.log`.
- Evidence: before capture from the running pre-fix 0.5.9 module, warning at
  `dmesg` line 1245 `[    3.638007]`, plus the pre-fix modetest property surface
  showing plane 40 with `type` and `IN_FORMATS` only
  (`docs/evidence/runtime/cursor-alpha-01-warning-before.txt`); the kernel check
  source, the diff, the gate, the object proof (`U
  drm_plane_create_blend_mode_property`, `mov $0x1,%esi` before the call, zero
  references to the alpha property), `make check` -> `Ran 4 tests ... OK`,
  `Built 9` over 7.2.15/7.3.3/7.3.4 and `Built 3` over 6.17.1-300
  (`docs/evidence/builds/19-cursor-alpha-fix.log`). Scratch transcripts in
  `/mega/tmp/sm750/t13/`.
- Outcome: `make check` exit 0 with 17 recipe commands and no warning from
  `src/`; the four-tree matrix is green. The live log still shows the warning
  because the running module is the stale pre-fix build - the built 0.6.0 module
  carries the property and the warning clears once T11 installs it and reloads.
  Unrelated finding reported, not fixed: `./tests/audit-release.sh` exits 1 with
  `Source archive contains development-only content: docs/plan` because
  `docs/plan/` and `.gem-team.yaml` became tracked while `build-package.sh:98-100`
  excludes only `docs/images`; that is a packaging-scope regression for the task
  that owns `build-package.sh`, and `dist/RELEASE-AUDIT.txt` is therefore still
  the 09:54 report next to the 13:25 artifacts.

### 2026-11-18T10:52Z | gem-implementer | T13 follow-up: transient check-vblank failure, then two clean runs

- Action: a `make check` run at 10:47Z failed at `tests/check-drm-module.sh`
  with `DRM_IOCTL_WAIT_VBLANK: Invalid argument` (exit 2), then passed when
  repeated. Re-ran the target twice in a row and ran `tests/check-vblank
  /dev/dri/card0 60` standalone; everything passed.
- Files: none changed (diagnosis only).
- Evidence: `/mega/tmp/sm750/t13/make-check-final2.log` (the failing run,
  `DRM_IOCTL_WAIT_VBLANK: Invalid argument`), `make-check-r1.log` and
  `make-check-r2.log` (exit 0, 17 recipe commands each), and the standalone
  `Measured 60.00 DRM vblanks/s over 120 events (expected 60.00)`.
- Outcome: the live vblank ioctl check is flaky, not broken by T13 - the module
  under test is the stale 0.5.9 build and the dmesg around that time shows
  repeated probe/modeset cycles from other work on the host, so a
  `DRM_VBLANK_RELATIVE` wait can return `EINVAL` while the CRTC is momentarily
  off. Do not treat a single `DRM_IOCTL_WAIT_VBLANK: Invalid argument` failure as
  a driver regression; re-run before investigating.

### 2026-11-18T10:50Z | orchestrator | T12 and T13 accepted; T18 added for the release-archive gate

- Accepted T12 (gem-devops): VBIOS captured at 49152 bytes, sha256
  `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`,
  reproduced byte-identically on a second read; GAP-B1 closed. The helper's
  `EXPECT=65536` is a stale constant, so its exit 2 is success - recorded as a
  plan decision rather than a defect.
- Accepted T13 (gem-implementer): the cursor plane keeps `DRM_FORMAT_ARGB8888`
  and declares `BIT(DRM_MODE_BLEND_PREMULTI)` at `src/sm750_drm.c:3491`; defect
  A25 recorded. The live probe warning can only clear after T11 reloads the
  module.
- Added T18 (wave 9) for a pre-existing gate defect: `./tests/audit-release.sh`
  exits 1 with "Source archive contains development-only content: docs/plan"
  because `build-package.sh:98` archives `git ls-files` while
  `tests/audit-release.sh:54-58` forbids `docs/plan`, `docs/evidence` and
  `docs/images`. T8 now depends on T18.
- Also recorded in the plan: the io_uring assessment (not applicable, with
  evidence), the QEMU harness route for T17 (generic loader + gdb; `-option-rom`
  cannot load this image), and the T11 rebuild requirement because the staged
  0.6.0 RPM predates T13.
- Files: `docs/plan/20261117-sm750-driver-prod/plan.yaml` (18 tasks, 32
  decisions), `docs/LOGBOOK.md`.
- Evidence: subagent reports for T12 and T13; measurements in this session's
  shell history under `/mega/tmp/sm750/`.
- Outcome: plan accepted at 13/18 completed; T11, T15, T16, T17, T18 and T8
  remain.

### 2026-11-18T11:30Z | orchestrator | T15 accepted; static-analysis toolchain adopted; T19 created

- T15 (gem-debugger) accepted. The `kms_addfb_basic` `size-max` EINVAL is
  correct by design: IGT puts a DRM_FORMAT_RGB565 1024x2048 pitch 2048
  framebuffer on the same 4 MiB object (`../tests/kms_addfb_basic.c:590-594`),
  and generic DRM rejects it twice - the height check against the declared
  `max_height` 1152 (`src/sm750_drm.c:3437`, from `SM750_DRM_MAX_HEIGHT`
  at `:95`) and the atomic plane-format gate, because the primary plane
  advertises XRGB8888 only. Every datasheet limit is satisfied, so the silicon
  is not the constraint. Decision recorded in the plan: no code change; the
  declared limits get documented and size-max stops counting as a driver FAIL.
- The live numbers in that report come from the stale 0.5.9 module and still
  need a 0.6.0 re-check after T11.
- Toolchain: the host owner installed sparse, dwarves (pahole), smatch,
  cppcheck, coccinelle, kmscube, bear, kernel-tools, v4l-utils and
  igt-gpu-tools. The orchestrator verified every binary on PATH and every RPM
  version. T19 was created and dispatched to turn that into an opt-in
  `make static` gate; it deliberately does not join the `check` target,
  whose 17 recipe commands are asserted by `tests/check-drm-module.sh` and
  documented in `docs/AUDIT.md` A23.
- T18 stays queued behind T11/T17 so only one `make` runs in the tree.
- Files: `docs/plan/20261117-sm750-driver-prod/plan.yaml` (19 tasks),
  `docs/LOGBOOK.md`.
- Evidence: `docs/evidence/runtime/10-addfb-size-max.txt` (476 lines);
  subagent report for T15.
- Outcome: 14/19 completed; T11, T16, T17, T19 running; T18, T8 pending.

### 2026-11-18T11:39Z | orchestrator | correct session ownership: Plasma is on the GTX 1070, not the SM750

- User correction (m00899): Plasma holds DRM on the GTX 1070, not on the SM750.
  Verified and extended rootlessly.
- Topology: card0 = 0000:01:00.0 SM750 (driver sm750hdmidrm, boot_vga=0);
  card1 = 0000:02:00.0 GP104 GTX 1070 (driver nvidia, card1-DVI-D-1 connected
  and enabled); card2/card3 = 83:00.0/84:00.0 Tesla P100. kwin_wayland
  (pid 2252, uid 1000) and plasmashell (pid 2392) are running; the ASPEED at
  09:00.0 has no DRM card because the kernel command line carries
  modprobe.blacklist=...,ast and rd.driver.blacklist=...,ast.
- Why card0 still shows an enabled CRTC at 1920x1080: the driver's own in-kernel
  fbdev client. drm_client_setup(&sdev->drm, drm_format_info(DRM_FORMAT_XRGB8888))
  at src/sm750_drm.c:3784; dmesg shows 'full-frame backbuffer staging enabled
  (4147200 bytes per buffer)' at [6.265979] (= 1920x1080x2) and
  'fb0: sm750hdmidrmdrm frame buffer device' at [6.341676], both before any
  userspace client attached. No /dev/fb* node exists despite the registration
  because CONFIG_FB_DEVICE is unset (recorded as A24).
- Corrections this retracts: the phrase 'Plasma session on connector 35' in
  T10's and T15's reports, and the T15 blocker line claiming IGT cannot run
  because Plasma holds master. The IGT VT subset is blocked only by /dev/tty0
  being crw------- root tty.
- Additional proof that card0 had no master: T10's 'modetest -s 35@38:1024x768-60'
  actually programmed the CRTC, which requires drmSetMaster to succeed, so no
  other process held master on card0 at that moment.
- Files: docs/plan/20261117-sm750-driver-prod/plan.yaml (35 decisions),
  docs/LOGBOOK.md.
- Evidence: this session's dmesg/journalctl captures under /mega/tmp/sm750/;
  /sys/class/drm/card*-*/{status,enabled}, /sys/class/drm/card*/device/boot_vga,
  pgrep output for kwin_wayland.
- Outcome: T11 was sent a correction; no plan scope change.
