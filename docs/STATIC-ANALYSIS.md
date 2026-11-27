<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Static analysis: gate, findings and triage

`make static` runs sparse, smatch, cppcheck, coccinelle and pahole over
`src/`, compares the findings against a recorded baseline and fails on any
fingerprint the baseline does not already contain. It is deliberately **not**
part of `make check`: that target's recipe command count is asserted by
`tests/check-drm-module.sh` and documented in [AUDIT.md](AUDIT.md), and none of
the analysers is a build requirement. The gate is opt-in, needs no root, and
exits 0 with an `analysers not installed, skipping` notice when the toolchain is
absent, so building, packaging and `make check` keep working everywhere.

Raw output of the run this document describes:
`docs/evidence/builds/20-static-sparse.log` to `25-static-gate.log`.

## 1. Running the gate

```sh
make static                                    # configured tree, compare to baseline
KDIR=/usr/src/kernels/7.3.4-100.fc43.x86_64 \
  STATIC_KERNELS=/path/to/6.17.1-300.fc43.x86_64 \
  ./tests/check-static.sh --logs /tmp/static    # two trees, keep raw output
./tests/check-static.sh --update                # rewrite ALL trees' entries
KDIR=/usr/src/kernels/7.3.5-100.fc43.x86_64 \
  ./tests/check-static.sh --update-kernel       # rewrite only 7.3.5's entries
```

`CC` defaults to `/usr/bin/gcc`: the `gcc` on `PATH` on this host is the CUDA
toolchain, and the kernel rejects it. `KDIR` defaults to
`/lib/modules/$(uname -r)/build`; `STATIC_KERNELS` adds further header trees,
space separated. The first tree also drives the cppcheck and pahole runs, and
the tree version (`<release>.fc43.<arch>`) is part of every sparse and smatch
fingerprint. The baseline is compared per tree, so a finding that only one tree
produces cannot be hidden by another tree's line, and an installed tree with no
baseline of its own is reported as a missing baseline rather than as a new
finding.

## 2. Fingerprints and the baseline

The gate must fail on a new defect and must not fail because a line moved. Each
analyser's output is therefore normalised to a multiset of fingerprints that
carry no line numbers:

| Tool | Fingerprint | Example |
| --- | --- | --- |
| sparse | `<tree> sparse <file> <warning text>` | `7.3.4-100.fc43.x86_64 sparse sm750_drm.c warning: symbol 'x' was not declared. Should it be static?` |
| smatch | `<tree> smatch <file> <function> <severity>: <message>` | `7.3.4-100.fc43.x86_64 smatch sii902x.c sii902x_begin_control() warn: shift has higher precedence than mask` |
| cppcheck | `cppcheck <file> <severity> <id>` | `cppcheck sii902x.c error arrayIndexOutOfBounds` |
| coccinelle | `coccinelle <rule> <file>` | `coccinelle sizeof-pointer sii902x.c` |

`tests/static/baseline/<tool>.txt` stores `<count> <fingerprint>` lines, sorted,
and the comparison is `comm -13 baseline run`. Counts, not just set membership,
so a *second* copy of an already-known finding is reported as new while a pure
line shift is not. pahole is informational (struct layout and BTF status): it
fails the gate only if the probe build fails.

The `<tree>` field is compared, not ignored. sparse and smatch fingerprints
start with the kernel release, and the gate splits both the run and the
baseline on that field, then compares one tree's lines against that same
tree's baseline lines. Identity inside a tree is the rest of the fingerprint,
so a line shift is still invisible while a distinct finding, or a second copy
of one, still fails. cppcheck and coccinelle fingerprints carry no tree because
they analyse `src/` itself; they keep the single global comparison.

Consequences, all deliberate:

- A tree that reports findings but has no baseline line of its own fails with
  `no baseline for kernel tree <release>: run ./tests/check-static.sh
  --update-kernel`. That message is not `NEW <tool> findings beyond the
  recorded baseline`: the first says the tree was never baselined, the second
  says a baselined tree produced a new fingerprint.
- A tree that reports nothing needs no baseline line, so installing a tree and
  running the gate clean does not demand an update.
- `--update-kernel` rewrites only the analysed trees' lines and keeps every
  other tree's entries verbatim; `--update` still rewrites the whole file and
  therefore drops the entries of trees that are not in that run.

### A new kernel tree

Installing a kernel whose headers the driver builds against adds a new tree
value to every sparse and smatch fingerprint. The procedure is:

1. Run the gate once to confirm the failure is the missing baseline, not a
   `NEW ... findings` line: the message must name the tree and
   `--update-kernel`.
2. `KDIR=/usr/src/kernels/<release> ./tests/check-static.sh --update-kernel`.
   It prints the tree and how many baseline lines it wrote.
3. Review the added lines with `git diff tests/static/baseline/` and compare
   them against rows ST-05 to ST-09. The known set is one `sii902x.c`
   `sii902x_begin_control()` warning and four `sm750_drm.c` `sm750_dma_init()`
   warnings, all `shift has higher precedence than mask` from `GENMASK_TYPE()`.
4. If a line is not one of those, do not accept it. Triage it as a new row in
   section 4 first; a genuinely new message is a finding, and the baseline is
   the record of a triage, not a way to silence one.

## 3. Result counts

`sparse` and `smatch` were run per tree with kbuild's own checker hook
(`make C=2 CHECK=tests/static/sparse-check`), so every translation unit is
listed as `CHECK`ed in the evidence log - that is the proof the invocation
actually analysed the files rather than skipping them.

| Tool | Version | Tree | Exit | Raw lines | Driver findings | After triage |
| --- | --- | --- | --- | --- | --- | --- |
| sparse | 0.6.4 | 7.3.4-100 | 0 | 4 | 4 | 0 (fixed) |
| sparse | 0.6.4 | 6.17.1-300 | 0 | 4 | 4 | 0 (fixed) |
| smatch | 1.73-8.fc43 | 7.3.4-100 | 0 | 5 | 5 | 5 false positives (baseline) |
| smatch | 1.73-8.fc43 | 6.17.1-300 | 0 | 21 | 3 | 3 false positives (baseline) |
| smatch | 1.73-8.fc43 | 7.3.5-100 | 0 | 5 | 5 | 5 false positives (baseline) |
| cppcheck | 2.19.1 | 7.3.4-100 | 0 | 1 | 1 | 1 suppressed (documented) |
| coccinelle | 1.3 | 7.3.4-100 | 0 | 0 | 0 | 0 |
| pahole | 1.32 | 7.3.4-100 | 0 | n/a | informational | no action |

The 18 non-driver smatch lines on 6.17.1-300 are inside the kernel tree's own
`include/linux/fortify-string.h` (lines 497, 597, 599, 724, 726). The gate
matches findings that begin with a driver basename, so they never enter the
baseline; see section 5.

## 4. Triage table

One row per distinct finding. `real` means the tool found something in the
driver that is worth changing; `style` means it is a code-hygiene point with no
behavioural effect; `false-positive` means the message describes the *kernel
macro* the driver expands, not the driver's expression.

No finding is classified `real`: every message either names a kernel macro the
driver cannot change or is a declaration-hygiene point. The four `style` rows
were fixed anyway, because they are free to fix and sparse then reports nothing;
they are also the only rows with a source change, so no defect row is owed for a
`real` finding (A28 records the accepted residuals).

| ID | Tool | Location | Class | Evidence or reasoning | Action |
| --- | --- | --- | --- | --- | --- |
| ST-01 | sparse | `src/sm750_drm.c:135` `sm750_test_reduced_pll_ratio` | style | Defined non-static here, used across translation units at `src/ddk750_mode.c:324,328,341`, but no declaration was in scope at the definition. sparse's suggested `static` would break the link. | fixed: declared `extern` at `src/ddk750_chip.h:21` |
| ST-02 | sparse | `src/sm750_drm.c:136` `sm750_test_low_vco_pll` | style | Same pattern; used at `src/ddk750_mode.c:324,328`. | fixed: `src/ddk750_chip.h:22` |
| ST-03 | sparse | `src/sm750_drm.c:137` `sm750_test_panel_fifo` | style | Same pattern; used at `src/ddk750_mode.c:260-314`. | fixed: `src/ddk750_chip.h:23` |
| ST-04 | sparse | `src/sm750_drm.c:138` `sm750_test_refresh_centihz` | style | Same pattern; used at `src/sii902x.c:331,346`. | fixed: `src/ddk750_chip.h:24` |
| ST-05 | smatch | `src/sm750_drm.c:1651` `dma_set_mask_and_coherent(..., DMA_BIT_MASK(31))` | false-positive | `DMA_BIT_MASK(n)` is `GENMASK_ULL((n) - 1, 0)` (`include/linux/dma-mapping.h:126`) and `GENMASK_TYPE()` (`include/linux/bits.h:52`) mixes `<<` with `&`/`>>` without inner parentheses. The outer cast and parentheses make the value correct; smatch's precedence check does not model the cast. A 5-line out-of-tree probe reproduces the same warning with no driver code involved. Every analysed tree reports it. ST-05 to ST-08 share one fingerprint (same tree, function and message), recorded as 4 copies on 7.3.4-100 and 7.3.5-100 and 2 on 6.17.1-300. | documented baseline |
| ST-06 | smatch | `src/sm750_drm.c:1663` `address > DMA_BIT_MASK(31)` | false-positive | Same macro expansion as ST-05, part of the same 4/4/2 copy count shared by ST-05 to ST-08. | documented baseline |
| ST-07 | smatch | `src/sm750_drm.c:1665` `(address & GENMASK_ULL(22, 0)) +` | false-positive | Same `GENMASK_TYPE()` expansion; `address & GENMASK_ULL(22, 0)` is a plain mask of a `dma_addr_t` with no shift outside the macro. Every analysed tree reports it (7.3.4-100, 7.3.5-100, 6.17.1-300). | documented baseline |
| ST-08 | smatch | `src/sm750_drm.c:1673` `(address & GENMASK_ULL(22, 2))` | false-positive | Same as ST-07, on the source-address programming path. Every analysed tree reports it (7.3.4-100, 7.3.5-100, 6.17.1-300). | documented baseline |
| ST-09 | smatch | `src/sii902x.c:741` `control & ~SII902X_PWR_STATE_MASK` | false-positive | `SII902X_PWR_STATE_MASK` is `GENMASK(1, 0)` (`src/sii902x.c:28`), so the same header expansion. No shift appears in the driver expression. Every analysed tree reports it (one copy each on 7.3.4-100, 7.3.5-100 and 6.17.1-300). (Line 743 before the ST-04 change removed two `extern` lines.) | documented baseline |
| ST-10 | cppcheck | `src/sm750_drm.c:815` `list_for_each_entry` | false-positive | `unknownMacro`: cppcheck cannot expand the kernel's list iterator when the kernel headers are intentionally not parsed (section 6). The same construct appears at every `list_for_each_entry` in the file, so the message carries no location information. | suppressed with `--suppress=unknownMacro`, reason recorded in `tests/check-static.sh` |
| ST-11 | pahole | `src/sm750hdmidrm.ko` | false-positive | No `.BTF` section: kbuild prints `Skipping BTF generation for sm750hdmidrm.ko due to unavailability of vmlinux`, because out-of-tree modules need a `vmlinux` with BTF for the *target* tree and `/boot/vmlinux*` does not exist here. Not a driver property. DWARF is present, so `pahole -C` reads the layouts. | documented baseline; layouts in `24-static-pahole.log` |
| ST-12 | pahole | `sm750_dither_scale_map` (2 bytes trailing padding), `sm750_drm_device` (8 holes, 29 bytes) | style | All gaps are 1 to 5 byte alignment padding between members of a struct allocated once per device; no hot-path struct is affected and there is no cacheline-scale waste. | no action |

## 5. Out of scope by construction, not by suppression

- Kernel-header findings. sparse with `CF=-Wsparse-all` and smatch's fortify
  strings report on `include/linux/*` expansions (`rculist.h`, `cred.h`,
  `cgroup-defs.h`, `rtmutex.h`, `mm.h`, `fortify-string.h`). These are not the
  driver's code and cannot be fixed here; the gate's parsers only accept lines
  that start with a driver basename, so they are excluded structurally rather
  than by a growing suppression list.
- `CONFIG_`-dependent branches the configured tree does not enable. All runs
  use the tree's own `.config`, i.e. the configuration this driver is built and
  tested against.

## 6. Tool configuration that is not the default, and why

**sparse and smatch wrappers** (`tests/static/sparse-check`,
`tests/static/smatch-check`) add two defines:
`__typeof_unqual__(x)=__typeof__(x)` and `__builtin_strlen(s)=(sizeof(s)-1)`.
Reason: `make C=2` first compiles a probe through
`scripts/checker-valid.sh`, and sparse 0.6.4 rejects `__typeof_unqual__`, so
kbuild silently disables checking ("C=2 specified, but /usr/bin/sparse is not
available or not up to date"). Independently, 7.3.4's `MODULE_INFO` uses
`static_assert(sizeof(info) - 1 == __builtin_strlen(info), ...)`, which sparse
cannot fold, so every `module_param_named()` would be reported as a bad constant
expression. The driver uses neither spelling (`rg` finds zero occurrences), so
the defines neutralise header tautologies only and cannot mask a driver finding;
gcc still enforces both in the real build.

**cppcheck** needs the kernel include paths stripped. Pointed at bear's raw
compile database it bails out on `__has_attribute(...)` in
`include/linux/compiler_types.h:37` and on the word-size `#error`, keeps 5 of
975 checkers active and reports nothing at all - including a deliberately
planted out-of-bounds write. `tests/static/mk-cppdb.py` therefore derives a
second database that keeps the kbuild `-D` configuration (so the same code paths
are selected) and drops `-I/usr/src/kernels*`, `-include`, `-nostdinc`, `-Wp,`,
`-f*`, `-m*`, `-O*`, `-std=*`, `-W*` and `-D__KERNEL__`, and injects
`KERNEL_VERSION(a,b,c)`. With it, 81 checkers report active, and the planted bug
is caught. Suppressions, all with a reason:

| Suppression | Reason |
| --- | --- |
| `missingIncludeSystem` | kernel headers are deliberately not parsed (see above) |
| `unusedFunction` | a module has no callers inside this translation-unit set |
| `unknownMacro` | cppcheck cannot expand the kernel's list iterator macros; the only occurrence is ST-10 |

## 7. Proven to analyse, not just to exit 0

A gate that prints nothing because an analyser silently gave up is worse than
no gate, so each tool was validated with a planted defect in a throwaway copy
(`/mega/tmp/sm750/t19/gateproof`, not in the tree):

| Tool | Planted defect | Detected as |
| --- | --- | --- |
| sparse | non-static global with no declaration | `warning: symbol 'sm750_planted_global_for_gate' was not declared. Should it be static?` |
| smatch | `u8 small[4]` written at index 4 | `error: buffer overflow 'small' 4 <= 4` (and the null-deref and inconsistent-return plants) |
| cppcheck | same array overrun | `error arrayIndexOutOfBounds` + `overlappingWriteFunction` + `nullPointerRedundantCheck` |
| coccinelle | same function | `sizeof-pointer`, `deref-under-null-check`, `missing-unlock`, one line each |

The gate's own status output is the check: `static gate: FAIL` on the planted
copy, `static gate: PASS` on the unmodified tree. Evidence:
`25-static-gate.log`.

Coccinelle runs twelve semantic patches against `src/`: the three in
`tests/static/cocci/` (`sizeof-pointer`, `deref-under-null-check`,
`missing-unlock`, the last covering both the `mutex_lock`/`spin_lock` and the
never-unlocked shapes) plus nine kernel-tree patches (`null/deref_null`,
`api/err_cast`, `misc/array_size`, `locks/double_lock`, `null/kmerr`,
`api/kfree_mismatch`, `misc/minmax`, `misc/struct_size`, `null/badzero`).
All report zero findings on `src/`; the planted control above shows the rules
fire, and the kernel patches need `-D report` (without it spatch reports "No
rules apply").

## 8. Determinism of the gate, and what a PASS means

The gate was observed both passing and failing over the same tree (T8 round 1):
`static gate: PASS` with exit 0 on one run, `coccinelle: exit 255` with
`spatch failed` and exit 1 on another. The cause is neither the driver nor the
patches nor the tree: it is one inherited environment variable.

spatch's Python bridge is loaded for every `.cocci` that carries a
`@script:python` rule (all three local patches, and the kernel patches' report
rules). At load time it locates libpython by running

```sh
pkg-config --libs python-3.14
```

`/usr/lib64/pkgconfig/python-3.14.pc` declares `Libs: -L${libdir}` with
`libdir=/usr/lib64`, and pkg-config suppresses a `-L` for a system directory,
so in a clean environment the probe prints nothing and spatch continues. With
`PKG_CONFIG_SYSROOT_DIR` set, the same query instead prints
`-L/mega/tmp/sm750/t3/libdrm/usr/lib64`; spatch's parser rejects that and the
process exits **255** after printing, verbatim,

```
Compilation OK!
Loading ML code of the SP...
Py.find_library_path: unable to parse the output of pkg-config '-L/mega/tmp/sm750/t3/libdrm/usr/lib64'
```

Nothing is analysed in that invocation: the capture holds no `HANDLING:` line
for it. 255 is spatch's own fatal exit, not a finding count - the run's finding
count is 0 and `coccinelle.fingerprints` is empty. It is also not a patch
defect: the same patch, the same files and the same spatch binary exit 0 in a
clean shell.

255 is spatch's generic fatal status and it covers two distinct situations,
both proved here: the `Py.find_library_path` failure above, and a `.cocci`
that does not parse (a deliberately corrupted `sizeof-pointer.cocci` gives
`minus: parse error:` and exits 255 as well). The exit code alone therefore
does not say which happened; the raw log does.

`PKG_CONFIG_SYSROOT_DIR` is exactly what `docs/ENVIRONMENT.md` section 4 tells
the operator to export for the rootless libdrm build. So a shell that had built
a libdrm client and then ran `make static` failed the gate, while a fresh shell
passed: same tree, different shell history, which is the flip T8 saw.

`tests/check-static.sh:37-46` now clears `PKG_CONFIG_SYSROOT_DIR`,
`PKG_CONFIG_PATH` and `PKG_CONFIG_LIBDIR` next to the existing locale
sanitisation. The gate analyses C and asks pkg-config nothing; those three
variables only decide what spatch's probe is told, so clearing them removes the
dependency rather than the check. Only `PKG_CONFIG_SYSROOT_DIR` was proved to
flip the result here; the other two are cleared because they move the same
probe's answer.

What a PASS means now:

- every listed analyser ran to completion over `src/` and exited 0, for every
  kernel tree in the run;
- every analysed tree's normalised fingerprint multiset equals that tree's
  slice of the baseline, i.e. no finding beyond `tests/static/baseline/`, no
  second copy of a recorded finding, and no analysed tree left unbaselined;
- the result does not depend on the caller's pkg-config resolver settings.

It is still a hard gate: a non-zero spatch exit fails the run, and a 255 is
labelled (`spatch fatal exit (255: internal error or patch parse error, not a
finding)`) and attributed to the patch that produced it (`spatch exit 255 on
<patch>`), so a future environment leak or a broken patch names itself instead
of failing anonymously. It does not assert that spatch never crashes for a
reason outside these three variables - only that such a crash is visible and
fatal, never a silent PASS.

Evidence: `docs/evidence/builds/28-static-determinism.log` (three failing runs
with the section-4 variables exported, the verbatim spatch tail, the
`pkg-config` probe outputs for both environments, ten consecutive passing runs
with the same variables still exported, the planted-defect control, and the
corrupted-patch control). The defect row is `A30` in `docs/DEFECTS.md`.

## 9. Changes made under this task

Only the four missing declarations (ST-01 to ST-04):

- `src/ddk750_chip.h:15-24`: comment plus `extern` declarations for
  `sm750_test_reduced_pll_ratio`, `sm750_test_low_vco_pll`,
  `sm750_test_panel_fifo` and `sm750_test_refresh_centihz`, next to the existing
  `extern void __iomem *mmio750` (`src/ddk750_chip.h:13`).
- `src/ddk750_mode.c`: three ad-hoc `extern` lines removed (the file includes
  `ddk750_chip.h`).
- `src/sii902x.c`: one ad-hoc `extern` line removed (same reason).

No behaviour changes: the declarations only give the existing definitions a
prototype in scope. Proof: sparse reports 0 warnings on both trees, smatch
finding counts are unchanged apart from the line shift of ST-09, `make check`
passes with all 17 commands (`Ran 4 tests ... OK`), and the three-tree build
matrix still reports `Built 9 sm750hdmidrm kernel/format combinations` with
`CC=/usr/bin/gcc` while the 6.17.1-300 floor tree reports `Built 3`, both exit
0. `make static` itself exits 0 with `static gate: PASS`.

## 10. Limits

- `-Wsparse-all` is unusable as a gate: it adds kernel-header noise from
  `rculist.h`, `cred.h`, `cgroup-defs.h`, `rtmutex.h` and `mm.h` and no driver
  finding, so the default warning set is used.
- cppcheck does not see kernel headers, so it cannot model a kernel API
  contract (for example a function that requires a lock). smatch covers the
  kernel-aware checks; cppcheck covers the local, language-level ones.
- smatch and sparse analyse the configured tree's code paths only. A defect in
  a `CONFIG` branch this host does not enable is invisible here.
- No BTF in the out-of-tree module (ST-11), so `pahole -F btf` cannot be used;
  the layouts come from DWARF in the object file built for this report.
