

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
