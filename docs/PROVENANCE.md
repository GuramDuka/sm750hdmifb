<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Provenance and licensing audit

## Conclusion

The releasable project is distributed under GNU GPL version 2 only. It does not
link or package a proprietary Silicon Motion driver, closed library, firmware
blob or precompiled vendor object.

Some DDK files were originally written by Silicon Motion and later contributed
to Linux. This project takes those files from Linux's open-source staging
`drivers/staging/sm750fb` tree, where they carry `SPDX-License-Identifier:
GPL-2.0`. In Linux SPDX usage that means GPL version 2 only. Silicon Motion's
copyright notice identifies authorship; it does not make those GPL copies
proprietary.

The recorded development baseline was Ubuntu Noble HWE package
`linux-source-7.0.0` version `7.0.0-28.28`. The retained files have since been
modified for the board-specific DRM implementation; upstream Linux links are
provided for provenance, not as a claim that this module is an unmodified
in-tree driver.

## Source groups

| Files | Origin | Release licence |
|---|---|---|
| `src/ddk750*` | Linux staging `sm750fb`, modified for this DRM driver | GPL-2.0-only |
| `src/sm750_drm.c`, `src/sm750_drm_mode.*` | Project DRM/KMS implementation using Linux kernel APIs | GPL-2.0-only |
| `src/sii902x.*` | Project board-specific implementation informed by public TPI documentation, Linux's GPL SiI902x bridge and hardware testing | GPL-2.0-only |
| `src/sm750_dither.*`, `tools/bbdither-*` | Benjamin Brown's custom dither and test implementation | GPL-2.0-only |
| Packaging, tests and documentation | Project work | GPL-2.0-only |

Relevant upstream files:

- [Linux staging SM750 driver](https://github.com/torvalds/linux/tree/master/drivers/staging/sm750fb)
- [Linux SiI902x DRM bridge](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/bridge/sii902x.c), licensed GPL-2.0-or-later

GPL-2.0-or-later code may be used under GPL version 2 when that version is
selected. Register addresses, bit meanings, electrical limits and short
register/value sequences are functional hardware facts rather than linked
external code.

## Vendor reference material

Development used private copies of newer vendor Linux/Xorg/WinCE drivers and a
board option ROM to compare register behaviour. Some of those files have
restrictive notices. None is included in this repository or source package.

`sii9024_rom_exact` retains a short diagnostic table of register/value pairs
read from the board's option ROM. It does not contain the ROM binary, executable
vendor code or a translated vendor function. The ordinary driver path does not
require the exact replay switch.

### Option ROM reconstruction

`tools/vbios-re/` and `vbios-re/model/` hold a reverse-engineering study of that
option ROM: a byte-range map of the image, a generator that re-encodes the code
regions as 16-bit assembly and rebuilds the image bit for bit, and a C model of
what the ROM does. See `docs/VBIOS-REVERSE-ENGINEERING.md`.

The reconstruction itself - the generated assembly and the rebuilt binary - is
**not** committed and is not part of any shipped artifact. It is produced on
demand from a capture that stays outside the tree, under
`/mega/tmp/sm750/`, and `make vbios-re` skips when that capture is absent.
The reasons:

* the generated assembly is a transliteration of vendor executable code, so
  committing it would put a translated vendor function in the repository;
* `build-package.sh` builds the source tarball from `git ls-files`, so anything
  committed would ship in the tarball and, if packaged, in the RPM payload;
* `tests/audit-release.sh` rejects `*.bin` and `*.rom` payload entries and
  grep-fails the ROM's own copyright banner text, so a committed rebuild could
  not pass the release gate anyway.

What is committed is the map, the generator, the verifier, the C model and the
evidence transcripts - original work that describes and reproduces the ROM
without containing it. Register addresses, bit fields and short
register/value sequences quoted in those files are functional hardware facts.

The alternative - committing the generated assembly and the rebuilt image so
the reconstruction is self-contained - was considered and rejected for the
three reasons above. If the basis changes, the decision changes here first.

## External dependencies

The kernel module resolves only Linux kernel and DRM symbols. DKMS, GCC, Make
and kernel headers are build tools, not linked redistributable components.
`libdrm` is used only by the optional userspace vblank test. No third-party code
is vendored by that test.

## Publication gate

Before a release, `tests/audit-release.sh` checks the tracked and packaged trees
for generated binaries, development-audit names, machine paths and unexpected
licence markers. The package-content and undefined-symbol reports are retained
in `dist/RELEASE-AUDIT.txt` for human review.
