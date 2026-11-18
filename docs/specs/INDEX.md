<!-- SPDX-License-Identifier: GPL-2.0-only -->
# SM750 device specification archive

Metadata and authored cross-reference material for the Silicon Motion SM750
display controller used by this driver. This directory stores no third-party
document bytes. It records what was retrieved, from where, with which checksum,
and what each source can and cannot support.

## Rules

- Third-party binary documents are not committed. They are downloaded to a
  scratch directory outside the tree (`/tmp/opencode/specs/` during the audit)
  and referenced here by URL plus SHA-256.
- `git ls-files docs/specs` must list only text artifacts. Vendor PDFs are not
  shipped by `build-package.sh`, and `docs/PROVENANCE.md:47` stays true.
- Every checksum below is the SHA-256 of the exact bytes served on the
  retrieval date, computed with `sha256sum`. The command in
  "Re-download and verify" reproduces the same value.
- Page numbers in this directory are the printed page numbers in the document
  footer (`Revision 1.4 <n>`). For the datasheet the physical PDF page equals
  the printed page (verified against sampled sections 2.2.1, 3.2.1, 6.2.1,
  7.3, 8.2 and 10.2).
- ASCII only, matching the rest of `docs/`.

## Archived documents

| ID | Document | Version and date | Source URL | Retrieved | SHA-256 | Authority | Rung |
|---|---|---|---|---|---|---|---|
| DS-1 | SM750 Datasheet | Revision 1.4, "Updated: September 27, 2012"; PDF ModDate 2014-02-08 | https://d3v.versalogic.com/wp-content/themes/vsl-new/assets/resources/support/mpee-v5/SM750_Datasheet_v.1.4.pdf | 2026-11-17 | `fac31257bb6ab058573bdb3fa255e6c5146522b0dee8aa6376cd59e500531889` | Vendor datasheet (distributor mirror) | 1 |
| PB-1 | SM750 Product Brief, "LynxExp Embedded Graphics Processor" | V2, document code `SM750-PB-201910`, (c) 2019 Silicon Motion | https://www.siliconmotion.com/download/3PS/a/SM750_PB_EN_201910.pdf | 2026-11-17 | `6eafa7240ead440fe6bf374fbeb393d75f26191148e3e8595f42accbb3bfd19f` | Vendor product brief (capability summary) | 1 |
| SUB-REG | `ddk750_reg.h` from mainline Linux `drivers/staging/sm750fb/` | `torvalds/linux` master at retrieval; 80088 bytes | https://raw.githubusercontent.com/torvalds/linux/master/drivers/staging/sm750fb/ddk750_reg.h | 2026-11-17 | not archived: moving branch, file is reproducible from the URL | Substitute: upstream GPL-2.0 register header | 2 |
| SUB-SII | `drivers/gpu/drm/bridge/sii902x.c` from mainline Linux | `torvalds/linux` master at retrieval; 36025 bytes | https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/bridge/sii902x.c | 2026-11-17 | not archived: moving branch, file is reproducible from the URL | Substitute: upstream GPL-2.0 SiI902x bridge driver | 2 |

Retrieval date is 2026-11-17 for every row.

### Re-download and verify

```
cd /tmp/opencode/specs

curl -sSL -o SM750_Datasheet_v1.4.pdf \
  https://d3v.versalogic.com/wp-content/themes/vsl-new/assets/resources/support/mpee-v5/SM750_Datasheet_v.1.4.pdf
sha256sum SM750_Datasheet_v1.4.pdf
# fac31257bb6ab058573bdb3fa255e6c5146522b0dee8aa6376cd59e500531889

curl -sSL -o SM750_PB_EN_201910.pdf \
  https://www.siliconmotion.com/download/3PS/a/SM750_PB_EN_201910.pdf
sha256sum SM750_PB_EN_201910.pdf
# 6eafa7240ead440fe6bf374fbeb393d75f26191148e3e8595f42accbb3bfd19f
```

`sha256sum -c SHA256SUMS` in this directory verifies both files when they are
placed there under the same names. The file names in `SHA256SUMS` are the
download names, not files tracked in git.

Vendor-site trap: `https://www.siliconmotion.com/download/3PS/a/SM750_Datasheet_v1.4.pdf`
and `https://www.siliconmotion.com/download/3PS/a/SM750_Datasheet.pdf` both
return HTTP 200 with 660306 bytes whose SHA-256 is identical to PB-1. That path
serves the product brief, not the datasheet. The datasheet is only reachable
through the distributor mirror recorded above. See `GAPS.md` GAP-1.

## Authority classification

| Class | Meaning | Applies to |
|---|---|---|
| Authoritative (vendor) | Register layout, bit fields, reset values, timing formulas. Still a hypothesis for boundary, count and completion semantics. | DS-1 |
| Vendor summary | Capability and packaging claims only. Not a programming reference. | PB-1 |
| Substitute (rung 2) | Upstream GPL-2.0 source used where the vendor document is silent or contradicts hardware. Functional hardware facts, not linked external code. | SUB-REG, SUB-SII |
| Absent | No public document found; recorded in `GAPS.md`. | SiI9024 TPI programming guide; SM750LE register appendix |

Fallback ladder actually used: rung 1 for the datasheet and product brief; rung 2
for three registers the datasheet lacks and for the SiI9024 control-bus
registers the SM750 datasheet does not cover; rung 3 (local vendor SDK or DDK
headers) was searched for and not present on this host.

## Coverage table

| Subsystem | Driver files | Cited source and section | Rung |
|---|---|---|---|
| Display controller: primary graphics plane, formats, panel enable | `src/ddk750_display.c`, `src/ddk750_mode.c`, `src/sm750_drm.c` | DS-1 section 6.2.1 "Primary Graphics Control Registers", p146-156; register summary Table 11 p142; programmer's model 6.1 p141 | 1 |
| Panel and CRT timing generators | `src/ddk750_mode.c` (`CRT_HORIZONTAL_TOTAL` .. `CRT_VERTICAL_SYNC`), `src/sm750_drm.c` | DS-1 section 6.2.1 p154-156 (primary), 6.2.6 p182-184 (secondary/analog) | 1 |
| Mode and clock tables | `src/sm750_drm.c:410` `sm750_standard_modes`, `:564` `sm750_custom_modes`, `:650` `sm750_safe_1920_modes`, `:662` `sm750_wide_modes`; `src/ddk750_chip.c:385` `sm750_format_pll_reg` | Clock synthesis: DS-1 section 1.3.12 "Clock Control" p32-33 (output = input x M / N / 2^OD; bit fields [17] enable, [18] bypass, [16] test clock, [15:14] POD, [13:12] OD, [11:8] N, [7:0] M) and 3.2.3 p96-100 for 0x00005C, 0x000060, 0x000064/0x000068, 0x000070. Mode timings themselves are driver-authored VESA CVT-RBv2 and CTA entries (`docs/MODES.md`); the datasheet contains no mode table | 1 |
| DMA engine (staging copy path) | `src/sm750_drm.c:1424-1449` | DS-1 section 10 "DMA Controller (DMAC)" p226-230, register summary Table 16 p228, 0x0D0018 bit 31 Act p230 | 1 |
| GPIO (bit-banged I2C) | `src/ddk750_swi2c.c` | DS-1 section 7 "GPIO" p194-200, register summary Table 13 p196, 7.3.1 p197-200 | 1 (rung 2 for the SM750LE bank, see GAP-3) |
| I2C host controller | `src/ddk750_hwi2c.c` | DS-1 section 8 "I2C Interface" p207-211, register summary Table 14 p208 | 1 |
| HDMI bridge control bus (SiI9024A) | `src/sii902x.c` | SM750 side: DS-1 section 8 p207-211 for the bus. SiI9024 side: SUB-SII (mainline `sii902x.c`) for 11 of 20 register defines; 9 TPI registers have no public citation (GAP-4) | 2 |
| Primary hardware cursor | `src/sm750_drm.c` (`PANEL_HWC_*` aliases at :110-119) | DS-1 section 6.2.4 "Primary Display Cursor Control Registers" p171-173 | 1 |
| Alpha and video overlay planes | `src/ddk750_display.c`, `src/sm750_drm.c` | DS-1 section 6.2.2 p157-164, 6.2.3 p165-170, 6.2.5 p174-178 | 1 |
| Power and clock gating | `src/ddk750_power.c`, `src/ddk750_chip.c` | DS-1 section 3.2.1 p71-89, 3.2.2 "Power Management" p90-93 | 1 |
| VGA configuration shadow (0x000088) | `src/ddk750_chip.c:228-230` | DS-1 section 2.2.1 p37 | 1 |
| Chip revision detection (SM718 / SM750 / SM750LE) | `src/ddk750_chip.c:18-32`, `src/ddk750_chip.h:5-6` | DS-1 has no revision-ID register table and does not mention SM750LE at all; substitute SUB-REG (GAP-3) | 2 |
| Not used by this driver: 2D drawing engine, ZV port, PWM | none | DS-1 sections 5 p115-140, 9 p212-225, 11 p231-235. Listed for completeness; no driver code references these blocks | n/a |

## Document map (DS-1)

| Chapter | Page |
|---|---|
| 1 General Description (1.3.5 video layers p21, 1.3.8 GPIO p29, 1.3.10 DMA p31, 1.3.12 clock control p32, 1.3.14 MMIO space p35) | 5 |
| 2 VGA Register (2.2.1 register descriptions p37) | 37 |
| 3 System Configuration (3.2.1 configuration 1 p71, 3.2.2 power management p90, 3.2.3 configuration 2 p94) | 70 |
| 4 PCI Configuration Space | 101 |
| 5 Drawing Engine (5.3.1 2D registers p118, 5.3.2 CSC p133) | 115 |
| 6 Display Controller (6.2.1 primary graphics p146, 6.2.2 video p157, 6.2.3 video alpha p165, 6.2.4 primary cursor p171, 6.2.5 alpha p174, 6.2.6 secondary graphics p179, 6.2.7 secondary cursor p187, 6.2.8 palette RAM p190) | 141 |
| 7 GPIO (7.3 register descriptions p196) | 194 |
| 8 I2C Interface (8.2 register descriptions p208) | 207 |
| 9 ZV Port | 212 |
| 10 DMA Controller (10.2 register descriptions p228) | 226 |
| 11 PWM | 231 |
| 12 Specifications | 236 |
| 13 Packaging | 245 |
| 14 Ordering | 245 |

## Known defects in the archived specification

DS-1 is known to be wrong about at least one hardware-observed boundary case:
narrow partial updates require one more output pixel than the documented
coverage model predicts (`docs/HARDWARE.md:23`). Documented boundary, count and
completion semantics are therefore hypotheses to be validated on hardware, not
authority. Two further defects were found during this audit and are recorded in
`GAPS.md` and `REGISTER-MAP.md`: the GPIO data-direction address (GAP-2) and the
absence of any SM750LE register appendix (GAP-3).

## Related files

- `SHA256SUMS` - checksums for the two archived vendor documents.
- `REGISTER-MAP.md` - register-by-register cross-check against DS-1, with every
  uncited register listed by `file:line`.
- `GAPS.md` - what could not be obtained, which substitute was used, and why
  the stage is not blocked.
