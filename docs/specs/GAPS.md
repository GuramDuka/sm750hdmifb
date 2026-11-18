<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Specification gaps

Every gap below is recorded, not blocking. The spec-archive stage is a
degradable gate: later work continues with the substitute named here. No
third-party binary document is stored in this repository.

Legend for status: `substitute` means a named replacement source supports the
driver code today; `open` means no authoritative source was found and the
driver's value is either hardware-validated or unverified; `closed by policy`
means the gap is handled by a project rule rather than by a document.

## GAP-1: vendor datasheet URL serves the product brief

Attempted on 2026-11-17:

```
curl -sSL -o probe_sm_ds.pdf https://www.siliconmotion.com/download/3PS/a/SM750_Datasheet_v1.4.pdf
# HTTP 200, 660306 bytes
sha256sum probe_sm_ds.pdf
# 6eafa7240ead440fe6bf374fbeb393d75f26191148e3e8595f42accbb3bfd19f
```

That checksum is identical to PB-1 and `pdfinfo` reports
`Title: SM750_Product_Brief_V2`, `Pages: 2`. The same result came from
`https://www.siliconmotion.com/download/3PS/a/SM750_Datasheet.pdf`. The vendor
site's datasheet path returns the product brief, not a datasheet.

Substitute: DS-1 from the VersaLogic mirror (see `INDEX.md`). Status:
substitute. The datasheet is obtainable, so this gap does not block.

## GAP-2: GPIO data-direction address conflict

DS-1 Table 13 (p196) lists GPIO registers at 0x010000 (Data), 0x010008 (Data
Direction), 0x010010 (Interrupt Setup) and 0x010014 (Interrupt Status/Reset).
The register descriptions on p197-200 repeat those addresses. The driver and
mainline `drivers/staging/sm750fb/ddk750_reg.h` use a stride of 4:

| Register | Driver and SUB-REG | DS-1 |
|---|---|---|
| GPIO Data | 0x010000 | 0x010000 |
| GPIO Data Direction | 0x010004 | 0x010008 |
| GPIO Interrupt Setup | 0x010008 | 0x010010 |
| GPIO Interrupt Status | 0x01000C | 0x010014 |

Only `GPIO_DATA_DIRECTION` 0x010004 is used by this driver
(`src/ddk750_swi2c.c:72,77,435,443`). The bit-banged I2C path that uses it is
the path the driver actually runs for the SiI9024A control bus, so the
0x010004 value is hardware-validated in practice, but no document states it.
DS-1 also has an internal inconsistency in this chapter: the prose says "The
GPIO registers are shown in Table 12" while the caption is "Table 13".

Substitute: SUB-REG line 470. Status: substitute, open as a documentation
defect. Do not change the driver address without hardware evidence.

## GAP-3: SM750LE is not covered by the datasheet

The string `SM750LE` does not occur anywhere in DS-1. The driver distinguishes
the part by revision ID (`SM750LE_REVISION_ID 0xfe` at `src/ddk750_chip.h:5-6`,
used at `src/ddk750_chip.c:25`) and has SM750LE-only code paths
(`src/ddk750_chip.c:39,61,93,145,187,226,327`, `src/ddk750_swi2c.c:387-400,429`).
Three consequences:

- `GPIO_DATA_SM750LE` 0x020018 and `GPIO_DATA_DIRECTION_SM750LE` 0x02001C
  (`src/ddk750_reg.h:1448,1452`) are not in DS-1 at all. 0x020000-0x02001C is
  documented as the SSP block (SSP Control 0 at 0x020000, clock prescaler at
  0x020010), which is a different function.
- `CRT_DISPLAY_CTRL` clock-select bits 29:27 and CRT-select bits 25:24
  (`src/ddk750_reg.h:1007-1020`, used by `src/ddk750_mode.c:50-71`) are marked
  reserved in DS-1 p180.
- The 7 predefined SM750LE pixel clocks (25/41/62/65/74/80/108 MHz) have no
  vendor table in DS-1.

Substitute: SUB-REG lines 1152, 1447, 1451 plus the driver's own SM750LE paths.
Status: substitute, open. This board is SM750G10, so the SM750LE paths are not
exercised here; the gap does not affect this hardware.

## GAP-4: SiI9024A TPI programming guide is not publicly available

`docs/PROVENANCE.md:29` says `src/sii902x.*` is "informed by public TPI
documentation" but records no URL. No public SiI9024A/SiI9022 TPI register
programming guide was located. Of the 20 numeric register defines in
`src/sii902x.c`, 11 match mainline `drivers/gpu/drm/bridge/sii902x.c` and 9 do
not: 0x60, 0x61, 0x63, 0x6A, 0x6B, 0x6C, 0x6D, 0x0A (AVI output format, as
opposed to input format 0x09) and the 0x72 write address. The full list is in
`REGISTER-MAP.md`.

Substitute: SUB-SII for the 11 shared registers, plus hardware testing for the
9. Status: substitute, open. Recorded so nobody assumes the HDMI path has a
citable register reference.

## GAP-5: no vendor errata for the known boundary defect

`docs/HARDWARE.md:23` records that narrow partial updates need one more output
pixel than the documented model predicts. No Silicon Motion errata sheet,
application note or newer datasheet revision that corrects this was found; only
revision 1.4 (September 2012) is publicly reachable. The workaround in the
driver is empirical and must not be removed on the strength of the datasheet.

Status: open. No substitute document exists; the hardware observation is the
authority.

## GAP-6: fallback rung 3 (local vendor SDK or DDK headers) is empty

Searched the user home directory and `/opt` for SM750 SDK or DDK trees and for
`*ddk*` headers outside `src/`. Nothing was found. The only SM750 register source
on this host is `src/ddk750_reg.h` itself. Status: rung 3 unavailable, rung 2
used instead.

## GAP-7: SM718 datasheet not retrieved

The driver handles SM718 (`dev_id 0x718`, `src/ddk750_chip.c:19-21`) with the
same register header. The SM718 datasheet named in the fallback ladder was not
downloaded or hashed during this audit, so no SM718-specific claim is made here.
Status: open, unsearched. It does not affect the SM750G10 board.

## GAP-8: datasheet distribution terms

DS-1 is an encrypted PDF (owner password set; permissions deny copying) and
carries a 2012 Silicon Motion copyright. `pdftotext` extraction works, but the
file is not redistributable, which is the reason it is hashed rather than
stored. Status: closed by policy. This directory keeps only text.
