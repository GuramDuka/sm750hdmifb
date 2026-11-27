# Contributor contract

Repository: Linux DRM/KMS driver for the Silicon Motion SM750 (module
`sm750hdmidrm`, package `sm750hdmifb`). Host: Fedora 43, running kernel
7.3.5-100.fc43.x86_64; DKMS builds the module for 7.2.15-100, 7.3.3-100,
7.3.4-100 and 7.3.5-100.

## Records

- `docs/LOGBOOK.md` is the chronological record of what actually happened.
  Append an entry to it immediately for every action and change, in the same
  session as the action: UTC timestamp, actor, action, files touched, evidence
  path, outcome. Never rewrite, reorder or delete an entry; a correction is a
  new entry that names the entry it corrects.
- A logbook or history change is not finished until it is published: after
  every edit to `docs/LOGBOOK.md` or to the plan of record, commit it and run
  `git push origin main` in the same session. `origin` carries both push URLs
  (polaris and GitHub); `upstream` push is disabled. Verify with
  `git ls-remote origin refs/heads/main` matching `git rev-parse HEAD`.
- `docs/plan/20261117-sm750-driver-prod/plan.yaml` is the plan of record: task
  scope, acceptance criteria, decisions and assumptions. Do not edit a past
  decision; record the change in the logbook and the plan.
- `docs/evidence/` holds the captured transcripts. A claim in prose that no
  evidence file supports is a gap, not a result.
- Host root actions are recorded in `docs/ROOT-ACTIONS.md` with the exact
  command and the GAP row it closes. Read it before asking for a new privilege;
  the sudoers allowlist and the twelve `sm750*` helpers in `/usr/local/sbin`
  already cover the common needs: `sm750-regs` reads the register file,
  `sm750-lspci` reads PCI config space, `sm750-vbios-dump` saves the VBIOS
  image, and the others cover console and VT control, CRC capture, packaging,
  PM probing and module hang recovery.

## Rules

- Not ours: seat, VT, kwin, plasma. Never activate or switch a VT (`chvt`,
  `VT_ACTIVATE`, anything that changes `/sys/class/tty/tty0/active`), never run
  a compositor or X server on a console the owner may be using, never signal a
  process belonging to another uid, and never touch seat or logind state.
  Console-grabbing helpers (`sm750-headless` x11 mode, `weston`, `cage`) are
  owner-supervised tools, not agent tools: a run needs the owner present, an
  explicit agreement to it, and a stated duration. On 2026-11-27 a run of
  `sm750-headless x11` moved the owner's foreground VT to tty2 and he had to cut
  power; the VT belongs to him, not to this work.
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
