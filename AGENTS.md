# Contributor contract

Repository: Linux DRM/KMS driver for the Silicon Motion SM750 (module
`sm750hdmidrm`, package `sm750hdmifb`). Host: Fedora 43, kernel 7.3.4-100.

## Records

- `docs/LOGBOOK.md` is the chronological record of what actually happened.
  Append an entry to it immediately for every action and change, in the same
  session as the action: UTC timestamp, actor, action, files touched, evidence
  path, outcome. Never rewrite, reorder or delete an entry; a correction is a
  new entry that names the entry it corrects.
- `docs/plan/20261117-sm750-driver-prod/plan.yaml` is the plan of record: task
  scope, acceptance criteria, decisions and assumptions. Do not edit a past
  decision; record the change in the logbook and the plan.
- `docs/evidence/` holds the captured transcripts. A claim in prose that no
  evidence file supports is a gap, not a result.
- Host root actions are recorded in `docs/ROOT-ACTIONS.md` with the exact
  command and the GAP row it closes. Read it before asking for a new privilege;
  the sudoers allowlist and the three helpers in `/usr/local/sbin` already cover
  the register dump, PCI config space and the VBIOS image.

## Rules

- ASCII only, in every file. No Unicode, no emoji, no typographic dashes.
- Scratch files go under `/mega/tmp/sm750/` only. Never write to `$HOME`, never
  leave scratch files in the project tree; the tree carries committed
  deliverables only.
- No vendor binaries, no firmware blobs, no closed libraries. See
  `docs/PROVENANCE.md`.
- `src/` is the truth for behaviour. Do not document a stack, a file or a
  function that does not exist; cite `file:line` for implementation claims.
- Preserve empirically validated workarounds even where the datasheet disagrees
  (`docs/HARDWARE.md`).
- Do not weaken a check to make a suite pass. A changed check needs a stated
  reason and an evidence path.

## Where things are

| Question | File |
| --- | --- |
| What happened, when, by whom | `docs/LOGBOOK.md` |
| What is planned and why | `docs/plan/20261117-sm750-driver-prod/plan.yaml` |
| What root actions exist on this host | `docs/ROOT-ACTIONS.md` |
| What is blocked and how to unblock it | `docs/evidence/EVIDENCE-GAPS.md` |
| Known defects and dispositions | `docs/AUDIT.md`, `docs/DEFECTS.md` |
| Test suites and recorded results | `docs/TEST-STRATEGY.md` |
| Host, toolchain, privilege state | `docs/ENVIRONMENT.md` |
| Reproduction and deliverables | `docs/DELIVERABLES.md` |
| Registers and modes | `docs/REGISTERS.md`, `docs/MODES.md` |
| Packaging | `docs/PACKAGING-RPM.md`, `packaging/sm750hdmifb.spec` |

## Verification before you commit

```sh
make check
./tests/audit-release.sh
git status --short
```

`make check` needs libdrm headers; the rootless recipe is in
`docs/ENVIRONMENT.md` section 3. Commit only the paths your task owns, and check
the result with `git show --stat`.
