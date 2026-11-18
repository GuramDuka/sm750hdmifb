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

### 2026-11-18T11:46Z | gem-debugger | T16: HDMI -110 episode reproduced once in 205 attempts; fail path identified

- Isolated the one kernel error episode from the 0.5.9 runtime log
  (`[8523..8586]`, `docs/evidence/runtime/07-kernel-log.txt:50-110`). It is
  reproducible: 1 hit in 205 controlled attempts.
- Trigger: SIGINT a kmscube about 300 ms into its first commit, then
  `modetest -s 35@38:1024x768-60`. The `failed to enable HDMI mode: -110`
  appears 330.003 ms later on the 1920x1080 fbdev-restore commit issued from
  `drm_release`, with the same `drm_atomic_helper.c:2758` WARNING, the same
  `Code:` bytes and the same call path as the original episode. The original's
  signal exit (`get_signal` -> `do_group_exit`) is incidental; the reproduction
  exited through an ordinary `close(2)`.
- Matrix: 205 attempts, 1 hit. 36 attempts of the 300 ms shape (1 hit, 2.8 %);
  169 attempts of every other shape (plain modeset, detect races, two masters,
  SIGKILL at 2 s, SIGINT/SIGTERM at 2 s, 25-run soak, mode churn, kill delays
  0.1/0.2/0.4/1.0/2.0 s): 0 hits. Three 10 s commit-wait timeouts followed the
  hit; the refcount underflow did not recur within the 60 s watch.
- Driver-side cause: `sm750_pipe_enable`'s `fail:` label (`src/sm750_drm.c:3105`)
  returns without `drm_crtc_vblank_on()`/`sm750_arm_vblank_event()` (success path
  `:3101-3102`), so `WARN_ON(new_crtc_state->event)` fires and the commit never
  completes. Which of the five fallible calls in `sm750_program_mode`
  (`src/sm750_drm.c:1312`, `:1316`, `:1319`, `:1346`, `:1349`) returns -110 is
  not observable on 0.5.9: that path has no `dev_dbg`/`drm_dbg` at all,
  dynamic debug is root-only, and 0.5.9 has no `regs` debugfs file. The 330.003 ms
  gap admits exactly one 100 ms `wait_display_value()` timeout after the fixed
  ~155 ms of `sii902x` quiesce, ranking `ddk750_set_display_control(0, false)`
  (`src/sm750_drm.c:1316`) first.
- Files: `docs/evidence/runtime/09-hdmi-minus-110.txt` (new),
  `docs/DEFECTS.md` (row and section A27; header line updated to three
  post-audit defects). No source, test, packaging or Makefile change; nothing
  committed.
- Evidence: `docs/evidence/runtime/09-hdmi-minus-110.txt`; raw per-attempt logs
  and dmesg deltas in `/mega/tmp/sm750/t16/` (matrix.log, matrix2.log,
  matrix3.log, matrix3b.log, matrix4.log and the matching `*-deltas.txt`).
- Outcome: A27 opened at S3, status open; production-clean claim blocked until the
  fail path is fixed or the risk is accepted with the measured rate. The panel
  was left connected/enabled/On at 1920x1080 after every attempt.

### 2026-11-18T12:10Z | gem-documentation-writer | T21: root actions updated for v3 helper and tty0 ACL; second output documented

- Action: brought `docs/ROOT-ACTIONS.md` up to date with what is staged for the
  host owner, and stated the permanent second output in the user-facing docs.
  Documentation only; no source, test, packaging or Makefile change.
- Files: `docs/ROOT-ACTIONS.md` (action table rows 5-7, section 3.3 rewritten to
  the v3 body, new section 4.1 for the `/dev/tty0` ACL, section 5 split into
  5.1 and 5.2, section 6 rows for VBIOS and tty0), `README.md` (new subsection
  "What the HDMI output actually shows"), `docs/DELIVERABLES.md` (new section
  3.1, VBIOS and KMS rows updated), `docs/LOGBOOK.md`.
- Re-verified on disk before writing, all matching:
  `/mega/tmp/sm750/sm750-vbios-dump` 1725 B, 52 lines, sha256
  `07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e`,
  `EXPECT=49152` at line 19;
  `/mega/tmp/sm750/99-sm750-coder-tty0-acl.rules` 762 B, sha256
  `248d76743dd1fa5aca03e55432e53bf02647900038b330439033f569117f7c4b`;
  `/mega/tmp/sm750/sm750-tty0-acl.conf` 299 B, sha256
  `3072aa4ecfd3f67d3c85be6076574d8d1b5afb47e5f4910df15d7f11c3f14538`. The v3
  body and both tty0 bodies printed in the document were extracted back out and
  compared byte-for-byte against the staged files: identical. The installed
  `/usr/local/sbin/sm750-vbios-dump` is still v2 (1092 B, sha256 `9e6c5db7`,
  `EXPECT=65536`), so the v3 install stays pending.
- Corrected two stale claims while editing: section 3.3 no longer says the v2
  body is staged (v2 was installed at 2026-11-18T10:12Z), and the VBIOS gap row
  no longer reports a truncated 4096-byte capture (the 48 KiB capture closed
  GAP-B1 at 2026-11-18T10:11Z). Section 6's VBIOS row said "PARTIAL: 4096 of
  65536 bytes" and now says CLOSED with the 49152-byte sha256.
- Second output, verified this session: `drm_client_setup()` at
  `src/sm750_drm.c:3784` registers the in-kernel fbdev client; dmesg
  `[6.265979]` staging, `[6.291648]` console switch to 240x67, `[6.341676]`
  `fb0: sm750hdmidrmdrm frame buffer device`. No `/dev/fb*` node exists
  (CONFIG_FB_DEVICE unset, A24). `card0-HDMI-A-1` status `connected`,
  `card1-DVI-D-1` `connected` with `kwin_wayland` pid 2252. Stated as observed
  behaviour with those dmesg lines cited; the phrase "Plasma session on
  connector 35" is not used.
- tty0 state confirmed unchanged and still root-only: `crw------- root tty`,
  `getfacl /dev/tty0` shows no named user entry, `/etc/udev/rules.d/` holds only
  `72-vkms-seat.rules` and `99-sm750-coder-acl.rules`, `/etc/tmpfiles.d/` is
  empty. The 19-entry sudoers allowlist is untouched; neither action needs a
  sudoers change.
- Verification: no non-ASCII bytes in the three edited files, no `TODO`/`TBD`,
  no "connector 35", `65536` survives only where it is the subject (the v1/v2
  bodies, the page-cap explanation, and the v2 stale constant).
- Outcome: both actions are documented as staged and pending, with install,
  verify and revoke commands; nothing committed.

### 2026-11-18T12:22Z | gem-documentation-writer | T21 post-edit re-verification; check failures confirmed pre-existing

- Corrects one detail in the `### 2026-11-18T12:10Z` entry above: its
  verification line says "three edited files", but four files were touched -
  `README.md`, `docs/DELIVERABLES.md`, `docs/ROOT-ACTIONS.md` and this log.
  No content claim in that entry changes.
- Re-verified after the edits, all matching: `sha256sum` of
  `/mega/tmp/sm750/sm750-vbios-dump` =
  `07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e`,
  `/mega/tmp/sm750/99-sm750-coder-tty0-acl.rules` =
  `248d76743dd1fa5aca03e55432e53bf02647900038b330439033f569117f7c4b`,
  `/mega/tmp/sm750/sm750-tty0-acl.conf` =
  `3072aa4ecfd3f67d3c85be6076574d8d1b5afb47e5f4910df15d7f11c3f14538`.
  The bodies printed in `docs/ROOT-ACTIONS.md` were extracted back out
  programmatically: section 3.3 holds exactly two `sh` blocks, the first equal
  to `/mega/tmp/sm750/sm750-vbios-dump.v1.bak` and the second equal to the
  staged v3 file (1725 B, sha256 `07fe5499...`); section 4.1 block 0 equals the
  udev rule and block 1 equals the tmpfiles file, both byte-identical.
- `make check` in the isolated copy `/mega/tmp/sm750/t21/build` builds the
  module and every test binary, then fails at `Makefile:32`
  (`./tests/check-drm-module.sh`) with `DRM_IOCTL_WAIT_VBLANK: Invalid argument`
  from `tests/check-vblank` against the live device. The same failure occurs in
  a `git archive HEAD` extraction once `tests/check-vblank` is copied in, so it
  is independent of these edits.
- `./tests/audit-release.sh` exits 1 with `Source archive contains development-
  only content: docs/plan` in the working tree and in the copy; in a pristine
  `git archive HEAD` extraction it exits 1 earlier with `Missing release
  input: .../src/sm750hdmidrm.ko`. Both are pre-existing and unrelated to the
  documentation change.
- `git diff --stat -- src tests packaging Makefile` is empty. Nothing committed.

### 2026-11-18T12:45Z | gem-devops | T11: install 0.6.0 from the rebuilt RPM, reload, close GAP-B4 and GAP-B7

- Rebuilt the package from the current tree before installing anything: the
  staged RPM at `/mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/` was pre-T13 (zero
  `drm_plane_create_blend_mode_property` strings in its payload). Rootless
  `rpmbuild -ba packaging/sm750hdmifb.spec` over the 80 tracked files produced
  `sm750hdmifb-0.6.0-1.fc43.noarch.rpm`, 90281 bytes, sha256
  `265449aa59446feb580d3d0d68a7a7597e08c30c73331455d7a5cd4a864563c5`. Payload
  gate passed: the packaged `src/sm750_drm.c` is byte-identical to the tree file
  (sha256 `026c31ac041ec9c05d0d0c933cff76093a841f54451ddfc69f790f3d3989382b`)
  and carries `debugfs_create_file("regs", ...)` at line 3343, the blend-mode
  property at 3491 and `MODULE_VERSION` at 3897.
- `sudo -n dnf install -y <allowlisted path>` exit 0. `%posttrans` built the
  module for 7.2.15-100, 7.3.3-100 and 7.3.4-100 (6.18.13-200 skipped: matching
  kernel headers absent) and reported each 0.5.9 module `ACTIVE on this kernel`
  before replacing it. `/lib/modules/7.3.4-100.fc43.x86_64/extra/sm750hdmidrm.ko.xz`
  is now 61620 bytes (was 60360) and reports `version: 0.6.0`.
- First unload attempt failed: `modprobe: FATAL: Module sm750hdmidrm is in use.`
  The single reference was T16's `matrix4.sh` kill-delay sweep holding the card
  open, not the driver or the fbdev client. Retried after that sweep finished:
  `modprobe -r` and `modprobe` both exit 0, `/proc/modules` shows 167936 bytes
  and refcnt 0, `/sys/module/sm750hdmidrm/{version,srcversion}` now exist.
- Runtime result: `modinfo -F version` 0.6.0; `modetest -c` prints
  `(version 0.6.0 at 0)`, was 0.1.0; IGT `core_getversion` prints
  `sm750hdmidrm v0.6`; the cursor warning is gone - the only
  `blend mode not setup` line in the whole boot is at `[3.681998]`, four
  milliseconds before the `Initialized sm750hdmidrm 0.1.0` of the stale probe,
  and neither 0.6.0 probe emits it. The property is visible as `42 pixel blend
  mode` / `Pre-multiplied=0` on plane 40.
- GAP-B4: `sudo -n /usr/local/sbin/sm750-regs` now exit 0, 49 registers. Method
  note: dump while a `modetest -s` client is held in the background, not after
  it returns - on the last close the fbdev client restore re-asserts 1920x1080,
  so an immediate dump samples the restored mode. Held at 1024x768, 12 of 49
  registers change; after restore 3 of 49 differ from baseline and only two are
  real (`PANEL_FB_ADDRESS` re-allocated, `MISC_CTRL` bit 17 cleared). A
  633-sample race control confirmed both states are reachable, so the register
  write is real and not a sampling artefact.
- AFTER suite re-run with T10's commands: `modetest -c`, `modetest -p`, one
  `modetest -s 35@38:1024x768-60` with restoration, kmscube 120/300 frames,
  `core_getversion`, full `kms_addfb_basic` (26 SUCCESS / 14 SKIP / 1 FAIL, the
  same tally as T10; size-max still fails at `tests/kms_addfb_basic.c:594`), and
  a kernel-log capture. The standalone `--run-subtest size-max` invocation is
  not citable: it interleaves `is_intel_device(fd)` requirement lines from the
  sibling tiling fixtures that read as a skip.
- The `-110` episode reproduced once on 0.6.0 during the `kmscube -c 300` exit:
  same `failed to enable HDMI mode: -110`, same `drm_atomic_helper.c:2758`
  warning, three `flip_done timed out`, then
  `refcount_t: underflow; use-after-free` from
  `drm_fb_helper_damage_work`. Display survived, refcnt 0. Handed to T16 with
  `/mega/tmp/sm750/t11/minus110-full.txt`; this task does not diagnose it.
- Rollback: `sudo -n dnf remove -y sm750hdmifb` exit 0. `%preun` ran
  `dkms remove --all`; `rpm -q` -> not installed, on-disk object gone, display
  survived. Recorded hazard: erase unlinks the module file while the module
  stays loaded, so a reboot would leave card0 driverless. Reinstalled 0.6.0
  immediately and cycled `modprobe -r`/`modprobe` to prove the fresh package
  loads. Final state: 0.6.0 installed and loaded (refcnt 0), display
  connected/enabled/On at 1920x1080, dkms reports 0.6.0 for all three kernels.
  The two orphaned `sm750hdmifb/0.5.9 ... built` rows and
  `/usr/src/sm750hdmifb-0.5.9` remain; 0.5.9 is outside this package version.
- `/dev/fb*` is still absent while `fb0:` is logged: `CONFIG_FB_DEVICE` is unset.
  Unchanged behaviour, recorded as such rather than as a defect.
- Files: `docs/evidence/runtime/08-register-dump.txt`, `13-module-reload.txt`,
  `14-modetest-connector-0.6.0.txt`, `15-modetest-properties-0.6.0.txt`,
  `16-modeset-0.6.0.txt`, `17-kmscube-0.6.0.txt`, `18-kernel-log-0.6.0.txt`,
  `19-igt-0.6.0.txt`, `20-rollback.txt`, `21-final-state.txt` (all new);
  `docs/evidence/runtime/11-preconditions.txt` and `12-rpmbuild-0.6.0.txt`
  (new, already committed in db7ecd3); `docs/evidence/EVIDENCE-GAPS.md` (B4 and
  B7 closed, B3 re-scoped, B8 complementary path noted);
  `docs/DEFECTS.md` (A25 after-capture, A26 0.6.0 re-test); `docs/ROOT-ACTIONS.md`
  (section 6 rows for GAP-B4 and GAP-B7). Nothing committed.
- Outcome: GAP-B4 and GAP-B7 closed with executed closing commands; GAP-B3 stays
  PARTIAL (CRC readback and external capture outstanding); GAP-B8 stays GAP but
  its `regs` half is now executable.

### 2026-11-18T12:54Z | gem-documentation-writer | T21 correction: v3 helper and tty0 rule are installed, not pending

- Corrects the `### 2026-11-18T12:10Z` and `### 2026-11-18T12:22Z` entries
  above. Both said the installed `/usr/local/sbin/sm750-vbios-dump` was v2 and
  that v3 was still pending, and both treated the `/dev/tty0` rule as staged
  only. Both statements were wrong: the host owner installed the v3 helper at
  12:07Z and the two tty0 files at 12:08Z (15:07 and 15:08 local, MSK), before
  the document was edited.
- Re-verified read-only, each matching: `ls -l /usr/local/sbin/sm750-vbios-dump`
  -> `-rwxr-xr-x 1 root root 1725 Nov 18 15:07`;
  `sha256sum /usr/local/sbin/sm750-vbios-dump` ->
  `07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e`;
  `grep -n '^EXPECT=' /usr/local/sbin/sm750-vbios-dump` -> `19:EXPECT=49152`.
  `sha256sum` of `/etc/udev/rules.d/99-sm750-coder-tty0-acl.rules` ->
  `248d7674...`, of `/etc/tmpfiles.d/sm750-tty0-acl.conf` -> `3072aa4e...`,
  both `0644 root:root`, both byte-identical to the staged copies.
  `ls -l /dev/tty0` -> `crw-rw----+ 1 root tty 4, 0`; `getfacl -p /dev/tty0`
  shows `user:coder:rw-` with `mask::rw-`.
- The v3 helper has been run twice: 49152 bytes, `signature 55aa, checksum ok`,
  exit 0 both times, into `/mega/tmp/sm750/vbios.bin` (15:07:53 local) and
  `/mega/tmp/sm750/vbios-v3.bin` (15:11:15 local). Both, plus the earlier
  `/mega/tmp/sm750/vbios-01-00-0.bin`, hash to
  `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`, the same
  value as the pre-v3 capture. GAP-B1 is closed end to end.
- Module state re-verified: `rpm -q sm750hdmifb` ->
  `sm750hdmifb-0.6.0-1.fc43.noarch`, `cat /sys/module/sm750hdmidrm/version` ->
  `0.6.0`, `lsmod` -> `sm750hdmidrm 167936 0`, `sudo -n
  /usr/local/sbin/sm750-regs` exits 0 with a 49-register dump.
- Timestamps: the review's "15:07Z-15:08Z" and "15:26Z" were local MSK, not
  UTC; the file mtimes are `2026-11-18 15:07:20 +0300`. The document states
  12:07Z/12:08Z install times and a 12:26Z re-check, each with its local time
  in parentheses, so a reader can re-derive them with `ls -l --time-style=full-iso`.
- Files: `docs/ROOT-ACTIONS.md` only. Header restated (rows 6 and 7 installed
  2026-11-18T12:07Z-12:08Z by the host owner); row 5 marked superseded; row 6
  dated with GAP-B1 CLOSED; row 7 dated with the node state; section 3.3 version
  table now marks v3 installed and v2 superseded, with the ls/sha256sum/EXPECT
  block; section 4.1 opens with the installed state and the ls/getfacl output,
  including `test -w /dev/tty0` -> `writable` (confirmed again during this
  revision with a real `open('/dev/tty0', O_WRONLY)` as uid 1005);
  section 5 retitled from "Pending root actions" to "Root actions: installed
  state and re-verification"; section 5.1 drops the "installed body is v2"
  paragraph for the verified v3 state; section 5.2 carries the installed-state
  block; section 6 VBIOS and tty0 rows restated.
- Still stale outside the edited scope, reported not changed:
  `docs/DELIVERABLES.md:140` says the v3 body "is not installed yet" and
  `docs/DELIVERABLES.md:143` says the tty0 ACL "is not installed yet". Both
  sentences are now false. Left untouched because the review limited this
  revision to `docs/ROOT-ACTIONS.md`.
- Verification: no non-ASCII bytes in the edited file, no `TODO`/`TBD`, the
  printed v3 body and both tty0 bodies still compare byte-identical to the
  staged files, and nothing under `src/`, `tests/`, `packaging/`, `Makefile`,
  `docs/plan/` or `docs/evidence/` was touched. Nothing committed.

### 2026-11-18T13:56Z | gem-implementer | T19: static-analysis gate - sparse, smatch, cppcheck, coccinelle, pahole over src/

- Scope: the driver had passed `make check`, the build matrix and the rootless
  runtime suite but had never been through kernel-oriented static analysis. New
  opt-in target `make static` -> `tests/check-static.sh`; it is deliberately not
  a recipe line of `check`, whose 17-command count is asserted by
  `tests/check-drm-module.sh` and documented in `docs/AUDIT.md`.
- Files added: `tests/check-static.sh`, `tests/static/sparse-check`,
  `tests/static/smatch-check`, `tests/static/mk-cppdb.py`,
  `tests/static/cocci/sizeof-pointer.cocci`,
  `tests/static/cocci/deref-under-null-check.cocci`,
  `tests/static/cocci/missing-unlock.cocci`,
  `tests/static/baseline/{sparse,smatch,cppcheck,coccinelle}.txt`,
  `docs/STATIC-ANALYSIS.md`, evidence `docs/evidence/builds/20-static-sparse.log`
  to `25-static-gate.log`. Files changed: `Makefile` (`static` target, `.PHONY`),
  `src/ddk750_chip.h`, `src/ddk750_mode.c`, `src/sii902x.c`, `docs/DEFECTS.md`
  (A28), `docs/DELIVERABLES.md` (section 2.8, 5.2 row, 5.4 evidence rows).
- Tool versions: sparse 0.6.4, smatch 1.73-8.fc43, cppcheck 2.19.1, coccinelle
  / spatch 1.3, pahole v1.32, bear 3.1.6, `/usr/bin/gcc` 15.3.1. Trees:
  `/usr/src/kernels/7.3.4-100.fc43.x86_64` and
  `/mega/tmp/sm750/t5/k617/usr/src/kernels/6.17.1-300.fc43.x86_64`.
- Results. sparse: 4 warnings on each tree before the fix, 0 after, exit 0.
  smatch: 5 findings on 7.3.4 and 3 on 6.17.1, exit 0, all
  `shift has higher precedence than mask`, all false positives from
  `GENMASK_TYPE()` (`include/linux/bits.h:52`) reached through
  `DMA_BIT_MASK()` / `GENMASK()`, reproduced by a five-line out-of-tree probe
  with no driver code. cppcheck: 0 findings after the documented suppressions
  (`missingIncludeSystem`, `unusedFunction`, `unknownMacro`); with bear's raw
  database it silently analysed nothing (5 of 975 checkers active), which is
  why `tests/static/mk-cppdb.py` strips the kernel include flags and why the
  evidence carries a planted-defect control. coccinelle: 0 findings across 3
  local and 9 kernel patches. pahole: no `.BTF` in the out-of-tree module
  (kbuild skips BTF generation without a `vmlinux`), DWARF layouts only 1-5 byte
  alignment gaps.
- Fix: the 4 sparse findings are the `sm750_test_*` module-parameter backing
  stores at `src/sm750_drm.c:135-138`, which must stay non-static (read from
  `src/ddk750_mode.c` and `src/sii902x.c`). Declared `extern` at
  `src/ddk750_chip.h:21-24`; the three ad-hoc `extern` lines in
  `src/ddk750_mode.c` and the one in `src/sii902x.c` removed. No behaviour
  change; sparse clean on both trees afterwards.
- Gate mechanism: fingerprints carry no line numbers (`<tree> <tool> <file>
  <message>`; `cppcheck <file> <severity> <id>`; `coccinelle <rule> <file>`),
  stored as `<count> <fingerprint>` lines and compared with `comm -13`, so a
  line shift stays quiet, a second copy of a known finding is new, and a new
  finding fails the gate. Proven both ways: `static gate: PASS` exit 0 on the
  tree, `static gate: FAIL` exit 1 on `/mega/tmp/sm750/t19/gateproof` with a
  planted undeclared global, an array overrun, a `sizeof(pointer)`, a null
  deref under a NULL check and a mutex leak, each caught by the expected tool.
  With no analyser on `PATH` it prints `analysers not installed, skipping` and
  exits 0.
- Tooling caveats recorded so the next run does not repeat them: kbuild's
  `scripts/checker-valid.sh` makes sparse 0.6.4 fail its `__typeof_unqual__`
  probe, so `make C=2` silently disables checking - the wrapper defines
  `__typeof_unqual__(x)` and `__builtin_strlen(s)` (the driver uses neither);
  the kernel `Makefile` does `unexport LC_ALL`, so the gate sets `LANG` and
  `LC_MESSAGES` too or the logs come out in the host locale; and `make -C ...
  clean` must precede each run or kbuild checks nothing.
- Verification: `make check` exit 0, all 17 commands; `docs/STATIC-ANALYSIS.md`
  AC-7 check names every file under `docs/`. Nothing committed.

### 2026-11-18T13:57Z | gem-devops | T22: purge stale DKMS registrations of sm750hdmifb from the RPM %posttrans

- Defect: `dkms status` listed `sm750hdmifb/0.5.9` as `built` for 7.3.3-100 and
  7.3.4-100 next to `sm750hdmifb/0.6.0` `installed` for all three kernels.
  Both `dkms.conf` files declare `DEST_MODULE_LOCATION[0]="/updates/dkms"` and
  `override_dest_module_location()` (`/usr/sbin/dkms:509-521`,
  `case ... in fedora*|centos*|rhel*) echo "/extra"`) rewrites that to `/extra`,
  so every registered version writes the single path
  `/lib/modules/<kver>/extra/sm750hdmidrm.ko.xz`. `dkms autoinstall` installs
  only the newest registered version and skips kernels where
  `_is_module_installed()` (`/usr/sbin/dkms:2020-2029`) is already true, so
  unregistering 0.6.0 would have made the next kernel install silently
  reinstall the pre-fix 0.5.9. The spec never removed it: `%preun` removes only
  `%{dkms_version}` and only when `$1 -eq 0`, and no `%postun` exists on
  purpose.
- Fix: bounded, idempotent purge at the end of `%posttrans`
  (`packaging/sm750hdmifb.spec`), after the kernel build loop so that 0.6.0
  owns the shared `/extra` path first. It reads `dkms status`, keeps only lines
  whose module name is exactly `%{dkms_name}` (the `name/` prefix means
  `sm750hdmifb-*` can never match), skips `%{dkms_version}`, and runs
  `dkms remove -m %{dkms_name} -v <version> --all` once per distinct stale
  version, downgrading any failure to a warning. Fields are parsed with `cut`:
  rpm halves every `%%` in a scriptlet, so a `%`-based parameter expansion
  silently became its shortest-suffix form during the first attempt and would
  have removed the wrong version. `%preun` untouched, no `%postun` added.
- Files: `packaging/sm750hdmifb.spec` (+56), `tests/check-rpm-dkms.sh`
  (+99/-15), `docs/PACKAGING-RPM.md` (+79/-15), new evidence
  `docs/evidence/runtime/22-dkms-stale-purge.txt`, this entry. No change under
  `src/`; the `check` recipe list in `Makefile` is untouched (still 17
  commands).
- Tests: `tests/check-rpm-dkms.sh` grew a canned `dkms status` listing with
  two `0.5.9` rows, a `0.6.0: added` row, a `sm750hdmifb-ng/0.9.0` row and an
  `othermodule/1.0` row; it asserts the resulting call log is exactly
  `dkms status` + `dkms remove -m sm750hdmifb -v 0.5.9 --all`. Negative
  controls: deleting the block fails with `%posttrans has no stale-registration
  purge`, neutering the version guard fails with `%posttrans purge does not
  skip 0.6.0`. Rootless run exit 0 with 9 OK and 8 SKIP lines; `make check`
  exit 0, all 17 commands.
- Verification on the host, allowlisted pair only, in order: `dnf remove` exit 0
  (0.6.0 uninstalled from all three kernels), `dnf install` of
  `sm750hdmifb-0.6.0-1.fc43.noarch.rpm` (sha256 `991a2217...57d5`, A27 fix
  included) exit 0 with the %posttrans printing `removing stale DKMS
  registration: sm750hdmifb/0.5.9` and `Deleting module sm750hdmifb/0.5.9
  completely from the DKMS tree`; afterwards `dkms status` printed exactly 3
  lines, `sm750hdmifb/0.6.0 ... installed` for 7.2.15-100, 7.3.3-100 and
  7.3.4-100, and `/var/lib/dkms/sm750hdmifb/` holds only `0.6.0`.
  `modprobe -r` + `modprobe` exit 0, `/sys/module/sm750hdmidrm/version` =
  0.6.0, srcversion unchanged; `sm750-regs` exit 0 with its 49 registers.
- Leftover by design: `/usr/src/sm750hdmifb-0.5.9` (21 MB, root:root, Nov 16
  21:36) is not owned by the RPM (`rpm -ql sm750hdmifb | grep -c 0.5.9` -> 0)
  and predates packaging, so the scriptlet does not delete it. Manual step for
  the host owner: `sudo rm -rf /usr/src/sm750hdmifb-0.5.9`.

### 2026-11-18T14:06Z | gem-implementer | T20: fix A27 - an abandoned modeset now finishes its commit

- Defect: `sm750_pipe_enable`'s `fail:` label returned the `-110` from
  `sm750_program_mode` with the commit's vblank event still armed and vblank
  accounting still off. `drm_atomic_helper_commit_hw_done` then tripped
  `WARN_ON(new_crtc_state->event)` (`drivers/gpu/drm/drm_atomic_helper.c:2758`),
  the commit never completed, CRTC 38, CONNECTOR 35 and PLANE 36 each reported
  `commit wait timed out` after 10 s, and a later `drm_release` restore could
  underflow a refcount in `__drm_atomic_helper_plane_destroy_state`.
- Fix, one hunk at the shared label (`src/sm750_drm.c:3105-3133`, +17/-1): after
  the staging reset and the `drm_err`, call `drm_crtc_vblank_on(&pipe->crtc)`
  (`:3131`) and `sm750_arm_vblank_event(pipe)` (`:3132`) - the same two calls
  the success path makes at `:3101`/`:3102`, which are unchanged. All three
  abandoned paths (`goto fail` at `:3059`, `goto fail` at `:3087`, fallthrough
  after a failed `sm750_program_mode`) converge on that label, so one site
  covers them; during `commit_tail` the state has already been swapped in, so
  `pipe->crtc.state` is the object whose `event` the helper inspects, and
  `sm750_arm_vblank_event` consumes the event on both branches (armed on the
  driver timer, or sent at once when `drm_crtc_vblank_get` fails). The message
  gained a `(commit finished, event consumed)` suffix so the fixed build is
  identifiable at run time.
- Gate: `tests/check-drm-policy.sh:141-167` extracts the fail block with `awk`
  and fails if either call is missing or a bare `return;` remains. It was added
  inside an existing check on purpose - `tests/check-drm-module.sh` asserts the
  recipe count and A23 records 17, and it is still 17. RED on the pre-fix
  source: `A27: abandoned modeset path lacks: drm_crtc_vblank_on(&pipe->crtc);`
  exit 1. GREEN after: `DRM mode policy checks passed`, exit 0.
- Build: isolated copy `/mega/tmp/sm750/t20/tree` (the checkout is shared with
  T11/T19), `CC=/usr/bin/gcc` (bare `gcc` is the CUDA wrapper), rootless libdrm
  from `/mega/tmp/sm750/t3/libdrm`. `make check` exit 0, zero `warning:` and
  zero `error:` lines, all 17 checks pass; `JOBS=12 ./tests/build-all-kernels.sh`
  reports `Built 9 sm750hdmidrm kernel/format combinations` for the three
  installed kernels (7.2.15-100, 7.3.3-100, 7.3.4-100 - the
  `/lib/modules/6.18.13-200.fc43.x86_64` directory belongs to no package).
- RPM rebuilt at the same NEVRA, since that path is the only allowlisted install
  target: `sha256` before `265449aa...563c5` (90281 B), after
  `76a430ff...50721` (91064 B). Another task rebuilt the same path later in the
  day (`991a2217...57d5`, see the T22 entry); its `src/sm750_drm.c` is
  byte-identical to this fix.
- Delivery, allowlisted commands only, every exit code 0:
  `sudo -n dnf remove -y sm750hdmifb`, `sudo -n dnf install -y
  /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm`
  (dkms built and installed 0.6.0 for all three kernels), `sudo -n dkms status`,
  `sudo -n modprobe -r sm750hdmidrm`, `sudo -n modprobe sm750hdmidrm`. dnf
  history transactions 380 and 381, both `Status Ok`. No new privilege.
- Loaded code proven fixed: srcversion `F4E135E09C9898462FE24C5` ->
  `07E8F503FC7D839EEC5EE64`, and
  `/lib/modules/7.3.4-100.fc43.x86_64/extra/sm750hdmidrm.ko.xz` (sha256
  `0461d157...2145`) contains `commit finished, event consumed`.
- Reproduction, 108 attempts (three times the required 36, because the pre-fix
  rate was 1/36): zero WARNING, zero `flip_done timed out`, zero
  `commit wait timed out`, zero `refcount_t: underflow`, and every attempt ended
  `connected/enabled/On` at 1920x1080. The `-110` still fired five times
  (attempts 76, 78, 79, 82) and each was followed only by normal re-enables, so
  the trigger is untouched and the cascade is gone. Whole-boot audit: all nine
  A27 markers precede the reload (`t=2889.882` to `t=2920.433`), none follow it.
- Evidence: `docs/evidence/runtime/17-a27-fix-build.txt`,
  `18-a27-fix-install.txt`, `19-a27-fix-reproduce.txt`; raw logs under
  `/mega/tmp/sm750/t20/`. `docs/DEFECTS.md` A27 is now `fixed`; GAP-B8 (which
  call returns `-110`) stays open, since this fix survives the `-110` rather
  than preventing it. Nothing committed - the orchestrator commits.

### 2026-11-18T14:20Z | gem-implementer | T19 follow-up: build-matrix proof, doc line references, pre-existing audit-release failure

Corrects and extends the T19 entry above (`2026-11-18T13:56Z`); nothing in that
entry's findings or dispositions changes.

- Added the build-matrix proof that the four declarations did not change
  behaviour: `tests/build-all-kernels.sh` with `CC=/usr/bin/gcc` over
  `/usr/src/kernels/{7.2.15,7.3.3,7.3.4}-100.fc43.x86_64` exits 0 with
  `Built 9 sm750hdmidrm kernel/format combinations`, and over the 6.17.1-300
  floor tree exits 0 with `Built 3`. Logs in `/mega/tmp/sm750/t19/`
  (`build-matrix.log`, `build-matrix-617.log`); `docs/STATIC-ANALYSIS.md`
  section 8 now states both.
- Corrected the cited line range of the fix in `docs/STATIC-ANALYSIS.md`,
  `docs/DEFECTS.md` and `docs/evidence/builds/20-static-sparse.log` from
  `src/ddk750_chip.h:17-24` to `src/ddk750_chip.h:15-24` (the comment block
  starts at line 15; the four `extern` lines are 21-24), and `docs/DEFECTS.md`
  A28 now says four fixed sparse findings, not three.
- Pre-existing failure, not caused by T19 and not fixed here:
  `./tests/audit-release.sh` exits 1 with
  `Source archive contains development-only content: docs/plan` because
  `docs/plan/20261117-sm750-driver-prod/plan.yaml` is tracked at HEAD
  (`d33cfe3`) and `build-package.sh:98` ships exactly the tracked tree. Proven
  pre-existing by running the same two scripts in a clean clone of `d33cfe3`
  (`/mega/tmp/sm750/t19/headcheck`): identical failure, no T19 path involved.
  `docs/plan/` and `packaging/` are another task's scope, so this is reported,
  not touched.
- Unchanged outcome: `make check` exit 0 (17 commands), `make static` exit 0
  with `static gate: PASS`, and the gate still fails on the planted copy.


### 2026-11-18T15:30Z | gem-implementer | T18: one development-only list for the packager and the release gate (defect A29)

Fixes the failure T13 and T19 reported but did not own: `./tests/audit-release.sh`
exited 1 with `Source archive contains development-only content: docs/plan` on
every fresh build.

- Disagreement, with line references: `build-package.sh:98-100` shipped the
  tracked tree minus `docs/images` only, so `docs/plan/` (1 file) and
  `docs/evidence/` (69 files) travelled in the archive, while
  `tests/audit-release.sh:54-58` failed the archive if `docs/plan`,
  `docs/evidence` or `docs/images` appeared in it. Both are tracked at HEAD
  (`d33cfe3`), so the two disagreed by construction. The audit also encoded the
  same rule a second time at `:61-73`, where it compared the shipped manifest to
  its own hard-coded `git ls-files` exclusion.
- Rule chosen, and why: the audit rule is the correct one - `A02` and `A22`
  already decided that untracked notes and the screenshots never ship, and the
  transcripts carry absolute host paths the audit itself rejects - so the
  packager was the side that had drifted. The audit rule is unchanged in
  substance; it was narrowed to nothing. What changed is that the list now lives
  in exactly one place, so a future `docs/` addition cannot break the gate
  again.
- One place: new `packaging/source-excludes.sh` declares
  `sm750_dev_only=(docs/plan docs/evidence docs/images)` and
  `sm750_dev_only_pathspecs()`, which prints one `:(exclude)<path>` per line.
  `build-package.sh:90-128` sources it for the git pathspecs and derives the
  non-git `--exclude=` arguments from the same array;
  `tests/audit-release.sh:52-80` sources it for the forbidden-directory loop and
  for the manifest diff; `tests/check-rpm-dkms.sh:70-85` sources it for the DKMS
  payload.
- Guard: `tests/check-drm-packaging.sh:32-49` replaces its two literal pins with
  eight assertions - the three paths are present in the shared file, both
  scripts read it and call the helper, and neither hard-codes `:(exclude)docs/`
  again. No assertion was deleted.
- Second, latent failure closed with the same change: the shipped
  `docs/ENVIRONMENT.md` spelled three `$HOME` paths out in absolute form
  (`~/.rpmmacros`, `~/rpmbuild/` and `~/.cache/ccache` written as
  `/home/<user>/...`), which the audit's own private-path scan rejects at
  `tests/audit-release.sh:89-95`; the earlier exit had hidden it.
  `docs/ENVIRONMENT.md:41-51` now writes them with `~/` and says why.
- Result: in an isolated copy of the tree, `./build-package.sh` exit 0 and
  `./tests/audit-release.sh` exit 1 before, exit 0 after. The tarball went from
  160 entries (`docs/plan` 1, `docs/evidence` 69, `docs/images` 0) to 90
  entries with all three counts at 0, matching
  `git ls-files -- . ':(exclude)docs/plan' ':(exclude)docs/evidence' ':(exclude)docs/images'`
  (90) against 163 tracked files.
- The gate still bites: an archive repacked from an unfiltered `git ls-files`
  fails the audit with the same message, and deleting a path from the shared
  list makes `tests/check-drm-packaging.sh` exit 1. Adding `docs/specs` to the
  list in one edit moved both the packager and the gate (0 `docs/specs` entries,
  audit exit 0). The non-git fallback branch excludes the same list (104 entries,
  all three counts 0).
- `make CC=/usr/bin/gcc check` exit 0 with the 17-command recipe unchanged
  (`Makefile:16-32` untouched); `build-package.sh` still produces the deb, the
  tarball and `dist/SHA256SUMS`; nothing in `src/` changed.
- Docs: `docs/PACKAGING-RPM.md:52-81` and `docs/DELIVERABLES.md:319-336` each
  state the archive-content rule in one paragraph and derive their recipe from
  the shared file, as does the `README.md:62-64` quickstart;
  `docs/DEFECTS.md` records `A29` and corrects the stale sentence that called
  `docs/plan/` and `docs/evidence/` untracked.
- Evidence: `docs/evidence/builds/26-audit-release.log` (before/after exit
  codes, the still-biting negative run, the single-edit run, the fallback run)
  and `docs/evidence/builds/27-source-archive-manifest.log` (the 90-entry
  manifest with the zero counts and the 160/1/69 baseline). Both were produced
  in `/mega/tmp/sm750/t18/tree`, an isolated copy, so the concurrent T17/T19
  tasks were never touched.
- Nothing committed - the orchestrator commits.

### 2026-11-18T17:25Z | gem-implementer | T17: VBIOS structure map, bit-exact 16-bit reconstruction, C model

Reverse-engineered the board option ROM capture at
`/mega/tmp/sm750/vbios-01-00-0.bin` (49152 bytes, sha256
`16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`, load
segment `0xC000`) into a byte-range map, a re-encoding generator that rebuilds
the image from 16-bit assembly, and a C model of what the ROM does. Analysis and
tooling only: nothing in `src/`, `tests/check-*.sh`, `packaging/`, `dkms.conf`
or `build-package.sh` changed, and the image is not in the tree.

- Files: `docs/VBIOS-REVERSE-ENGINEERING.md` (new, 1030 lines: image and header
  facts, the 239-region table over all 49152 bytes, code and data inventory,
  ROM behaviour for clock/PLL, panel and SiI9024A bring-up, blank/unblank,
  window and mode table, re-encoding and coverage, computed fields, decode
  equality, reproduction, provenance, the UNDETERMINED list and the divergence
  table); `tools/vbios-re/regions.txt` (239 regions, 120 code / 119 data),
  `tools/vbios-re/reencode.py` (generator and verifier),
  `tools/vbios-re/check.sh` (opt-in harness, exit 77 when the image is absent);
  `vbios-re/model/{rom.h,rom.c,clock.c,panel.c,dpms.c,mode_table.c,sii9024a.c,README.md}`;
  `docs/evidence/vbios-re/01-rebuild.txt`, `02-bitexact.txt`,
  `03-decode-equality.txt`, `04-toolchain.txt`; `Makefile` (`.PHONY` plus the
  `vbios-re:` target, `check:` untouched); `docs/PROVENANCE.md` (new
  "Option ROM reconstruction" subsection); this entry.
- Byte-exactness: `python3 tools/vbios-re/reencode.py` rebuilds 49152 bytes with
  0 differing bytes, sha256 equal to the capture, `cmp -l` empty with exit 0,
  and `objdump -D -b binary -m i8086 -M intel --adjust-vma=0xc0000` over both
  images produces 30283 identical lines (`diff` exit 0) and 7734 identical
  instruction slots. Transcripts in `docs/evidence/vbios-re/01`-`03`.
- Coverage: 17973 of 18034 code bytes re-encoded from mnemonics (99.66 percent,
  plan floor 85). 17 slots (61 bytes) are carried as `db` in two justified
  classes: vendor encodings nasm cannot emit (for example `mov ebp,dr0`,
  `fstp TBYTE PTR`, `addr32 fucomi`) and vendor redundant zero-displacement
  bytes. Each is listed with its bytes in section 7.3 of the document.
- Computed, not copied: the size byte at `0x02`, the PCIR image length at
  `0x2c` and the checksum byte at `0x34` are all derived by the build from the
  region table and the assembled bytes, and the build fails on a mismatch. The
  checksum is solved after the canonicalisation pass, because that pass rewrites
  bytes; solving it before the pass produced the observed
  `FAIL checksum byte ba captured 6b`.
- Toolchain constraint, measured: `/usr/bin/gcc -m16` emits `66 55` for
  `push ebp` and `67 66 8b 44 24` for a stack argument, clang 21.1.8 `-m16`
  emits the same, so neither compiler can produce 16-bit ROM bytes; nasm 2.16.03
  with `-f bin` does (`04-toolchain.txt`). The generator emits `bits 16` /
  `org 0` source and assembles it with one `nasm -f bin` call.
- Measured corrections to the model, both recorded in the document and the
  model: the display latch is inverted from the obvious reading - `0xc340d`
  sets sequencer register 1 bit 5 and clears `DISPLAY_CTRL_PLANE` (blank), while
  `0xc33d9` clears bit 5 and sets bit 2 (unblank) and no direct call or jump in
  the image targets `0xc33d9`; and the third word of the 12-byte MMIO record
  table at `0x11b` is inverted before the AND, so it is the mask of bits to
  clear, not a keep mask.
- UNDETERMINED, kept as such: which checksum convention the PCIR structure
  intends (its own span sums to 1, only the whole-image sum validates); the VBE
  mode-list pointer target (`c000:7aac` holds pointer words, not a VBE list);
  the VBE total-memory field; the font cell origin within `0x349f`-`0x34a9`;
  the mode-record field meanings; the name of MMIO `0x98000`; the two header
  words at `0x0a`/`0x0c`; and whether the SM750 VGA core inverts sequencer
  register 1 bit 5.
- Verification: `make CC=/usr/bin/gcc check` exit 0 with the rootless
  `libdrm` from `docs/ENVIRONMENT.md` section 4; `./tests/audit-release.sh`
  exit 0; `make vbios-re` exit 0 with a rebuild, and exit 0 with
  `SKIP: captured ROM not present at <path>` when `VBIOS_ROM` names a missing
  file, so the target can never fail a checkout without the image.
- Provenance: the reconstruction (generated `.asm` and `.bin`) stays under
  `/mega/tmp/sm750/t17/` and is not committed. `docs/PROVENANCE.md:54-82`
  states the basis and the rejected alternative: committing the rebuild would
  ship a translated vendor function in the source tarball, which
  `build-package.sh` builds from `git ls-files`, and `tests/audit-release.sh`
  rejects `*.bin`/`*.rom` payload entries and grep-fails the ROM's own banner.
- Nothing committed - the orchestrator commits. `Makefile` is shared with the
  concurrent T19 `static` target, so its diff carries both hunks.
