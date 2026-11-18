<!-- SPDX-License-Identifier: GPL-2.0-only -->
# SM750 register cross-reference

Register-level cross-check of `src/ddk750_reg.h` against the sources archived in
`INDEX.md`. Every MMIO register defined in the header and referenced by driver C
code is listed with its datasheet page, or with the substitute source used when
the datasheet does not describe it.

## Method

- Register set: every `#define NAME 0xADDR` in `src/ddk750_reg.h` whose name
  appears in `src/*.c`. A register read only through the
  `sm750_reg_dump_registers[]` table (`src/sm750_drm.c:3282-3331`) counts as
  referenced, because that table is C code in `src/sm750_drm.c`; 16 of the rows
  below are cited to it alone. Bit-field and mask macros are derived constants
  and are listed separately; they are not registers. `INT_MASK` is a register
  (0x000028) despite the name.
- Datasheet page: DS-1 (SM750 Datasheet revision 1.4) register description
  header, located by the `MMIO_base + 0xNNNNNN` line in the page body. Printed
  page equals PDF page for this file.
- Reproduction:

```
pdftotext -layout SM750_Datasheet_v1.4.pdf ds.txt
awk 'BEGIN{p=1} /\f/{p++} /MMIO_base \+ 0x080000/{print "page " p": "$0}' ds.txt
grep -n 'define PANEL_DISPLAY_CTRL ' src/ddk750_reg.h
```

The `awk` prints the printed page number of the page containing the register
description header (`p` starts at 1 and increments on each form feed).

- Coverage count. This parses the header with a pattern that tolerates leading
  whitespace, because `src/ddk750_reg.h:1142,1144,1146,1149` define
  `CRT_AUTO_CENTERING_TL`, `CRT_AUTO_CENTERING_TL_LEFT_MASK`,
  `CRT_AUTO_CENTERING_BR` and `CRT_AUTO_CENTERING_BR_RIGHT_MASK` inside an
  indented block; it also counts the rows of this file:

```sh
python3 - <<'EOF'
import glob, re
hdr = open("src/ddk750_reg.h").read()
src = "".join(open(f).read() for f in sorted(glob.glob("src/*.c")))
mp = open("docs/specs/REGISTER-MAP.md").read()
defs = re.findall(r"^[ \t]*#define[ \t]+([A-Za-z0-9_]+)[ \t]+0x[0-9A-Fa-f]+", hdr, re.M)
ref = [d for d in defs if re.search(r"\b" + d + r"\b", src)]
# INT_MASK is a register (0x000028) whose name ends in _MASK; every other
# _MASK macro is a bit-field constant.
regs = [d for d in ref if d == "INT_MASK" or not d.endswith("_MASK")]
row = r"^\| `([A-Z0-9_]+)` \| `0x([0-9A-F]+)` \| src/ddk750_reg.h:(\d+) \| (.*)$"
rows = re.findall(row, mp, re.M)
cited = set(r[0] for r in rows if re.match(r"p\d+ \| \d", r[3]))
rows_reg = [r for r in rows if r[0] in regs]
print("hex defines           ", len(defs))
print("referenced in src/*.c ", len(ref))
print("registers             ", len(regs))
print("bit-field/mask macros ", len(ref) - len(regs))
print("registers documented  ", len(set(r[0] for r in rows_reg)))
print("  with a DS-1 citation", len(cited))
print("  without             ", len(rows_reg) - len(cited))
print("  missing             ", sorted(set(regs) - set(r[0] for r in rows_reg)))
EOF
```

- Substitute SUB-REG is mainline Linux `drivers/staging/sm750fb/ddk750_reg.h`.
  A parsed comparison of the two headers found 331 common `#define` values, zero
  value differences, and zero macros present only in `src/ddk750_reg.h`. The
  driver header carries no private register encoding.
- Result, as printed by the coverage count above: 330 address-bearing
  `#define`s in `src/ddk750_reg.h`, 90 referenced in `src/*.c`, of which 70 are
  registers and 20 are bit-field or mask macros. All 70 registers are documented
  here: 64 with a DS-1 page citation and 6 without.
- Of those 70, the 16 that earlier revisions of this map omitted are the
  registers read only through the `sm750_reg_dump_registers[]` table
  (`src/sm750_drm.c:3282-3331`). They now have rows below: 13 carry a DS-1 page,
  and 3 do not (`GPIO_INTERRUPT_SETUP`, `DE_STATE1`, `DE_STATE2`).
  `docs/REGISTERS.md:49-99` lists the same offsets in dump order.

## Registers with a datasheet citation

| Register | Address | Header line | DS-1 page | Section | Driver uses |
|---|---|---|---|---|---|
| `SYSTEM_CTRL` | `0x000000` | src/ddk750_reg.h:14 | p71 | 3.2.1 | src/ddk750_display.c:79, src/ddk750_display.c:89, src/ddk750_power.c:15, src/ddk750_power.c:18 |
| `MISC_CTRL` | `0x000004` | src/ddk750_reg.h:46 | p73 | 3.2.1 | src/ddk750_chip.c:196, src/ddk750_chip.c:255, src/ddk750_chip.c:257, src/ddk750_chip.c:260 (+2 more) |
| `GPIO_MUX` | `0x000008` | src/ddk750_reg.h:79 | p75 | 3.2.1 | src/ddk750_hwi2c.c:27, src/ddk750_hwi2c.c:31, src/ddk750_swi2c.c:70, src/ddk750_swi2c.c:75 (+2 more) |
| `INT_STATUS` | `0x000024` | src/ddk750_reg.h:252 | p85 | 3.2.1 | src/sm750_drm.c:1365 |
| `INT_MASK` | `0x000028` | src/ddk750_reg.h:274 | p87 | 3.2.1 | src/sm750_drm.c:1350, src/sm750_drm.c:1353, src/sm750_drm.c:1391, src/sm750_drm.c:1392 |
| `CURRENT_GATE` | `0x000040` | src/ddk750_reg.h:296 | p90 | 3.2.2 | src/ddk750_chip.c:108, src/ddk750_chip.c:160, src/ddk750_chip.c:222, src/ddk750_power.c:91 (+3 more) |
| `MODE0_GATE` | `0x000044` | src/ddk750_reg.h:333 | p91 | 3.2.2 | src/ddk750_chip.c:191, src/ddk750_chip.c:193, src/ddk750_power.c:81 |
| `MODE1_GATE` | `0x000048` | src/ddk750_reg.h:356 | p92 | 3.2.2 | src/ddk750_power.c:79 |
| `POWER_MODE_CTRL` | `0x00004C` | src/ddk750_reg.h:379 | p93 | 3.2.2 | src/ddk750_power.c:26, src/ddk750_power.c:37, src/ddk750_power.c:73 |
| `PCI_MASTER_BASE` | `0x000050` | src/ddk750_reg.h:390 | p94 | 3.2.3 | src/sm750_drm.c:1434 |
| `DEVICE_ID` | `0x000054` | src/ddk750_reg.h:393 | p95 | 3.2.3 | src/sm750_drm.c:3289 |
| `PANEL_PLL_CTRL` | `0x00005C` | src/ddk750_reg.h:400 | p96 | 3.2.3 | src/ddk750_display.c:72, src/ddk750_mode.c:218 |
| `CRT_PLL_CTRL` | `0x000060` | src/ddk750_reg.h:418 | p97 | 3.2.3 | src/ddk750_mode.c:161 |
| `MXCLK_PLL_CTRL` | `0x000070` | src/ddk750_reg.h:428 | p100 | 3.2.3 | src/ddk750_chip.c:42, src/ddk750_chip.c:81 |
| `VGA_CONFIGURATION` | `0x000088` | src/ddk750_reg.h:430 | p37 | 2.2.1 | src/ddk750_chip.c:228, src/ddk750_chip.c:230 |
| `GPIO_DATA` | `0x010000` | src/ddk750_reg.h:437 | p197 | 7.3.1 | src/ddk750_swi2c.c:71, src/ddk750_swi2c.c:76, src/ddk750_swi2c.c:434, src/ddk750_swi2c.c:442 |
| `PANEL_DISPLAY_CTRL` | `0x080000` | src/ddk750_reg.h:537 | p148 | 6.2.1 | src/ddk750_display.c:35, src/ddk750_display.c:73, src/ddk750_display.c:103, src/ddk750_display.c:106 (+9 more) |
| `PANEL_PAN_CTRL` | `0x080004` | src/ddk750_reg.h:573 | p150 | 6.2.1 | src/sm750_drm.c:3298 |
| `PANEL_COLOR_KEY` | `0x080008` | src/ddk750_reg.h:579 | p150 | 6.2.1 | src/sm750_drm.c:3299 |
| `PANEL_FB_ADDRESS` | `0x08000C` | src/ddk750_reg.h:583 | p151 | 6.2.1 | src/sm750_drm.c:71 |
| `PANEL_FB_WIDTH` | `0x080010` | src/ddk750_reg.h:588 | p151 | 6.2.1 | src/sm750_drm.c:74 |
| `PANEL_WINDOW_WIDTH` | `0x080014` | src/ddk750_reg.h:593 | p152 | 6.2.1 | src/sm750_drm.c:1319 |
| `PANEL_WINDOW_HEIGHT` | `0x080018` | src/ddk750_reg.h:598 | p152 | 6.2.1 | src/sm750_drm.c:1322 |
| `PANEL_PLANE_TL` | `0x08001C` | src/ddk750_reg.h:603 | p153 | 6.2.1 | src/sm750_drm.c:1325 |
| `PANEL_PLANE_BR` | `0x080020` | src/ddk750_reg.h:608 | p153 | 6.2.1 | src/sm750_drm.c:1326 |
| `PANEL_HORIZONTAL_TOTAL` | `0x080024` | src/ddk750_reg.h:613 | p154 | 6.2.1 | src/ddk750_mode.c:225 |
| `PANEL_HORIZONTAL_SYNC` | `0x080028` | src/ddk750_reg.h:618 | p154 | 6.2.1 | src/ddk750_mode.c:227 |
| `PANEL_VERTICAL_TOTAL` | `0x08002C` | src/ddk750_reg.h:623 | p155 | 6.2.1 | src/ddk750_mode.c:234 |
| `PANEL_VERTICAL_SYNC` | `0x080030` | src/ddk750_reg.h:628 | p155 | 6.2.1 | src/ddk750_mode.c:241 |
| `PANEL_CURRENT_LINE` | `0x080034` | src/ddk750_reg.h:633 | p156 | 6.2.1 | src/sm750_drm.c:82 |
| `VIDEO_DISPLAY_CTRL` | `0x080040` | src/ddk750_reg.h:638 | p157 | 6.2.2 | src/ddk750_chip.c:267, src/ddk750_chip.c:269 |
| `VIDEO_FB_0_ADDRESS` | `0x080044` | src/ddk750_reg.h:661 | p159 | 6.2.2 | src/sm750_drm.c:3316 |
| `VIDEO_FB_WIDTH` | `0x080048` | src/ddk750_reg.h:666 | p160 | 6.2.2 | src/sm750_drm.c:3317 |
| `VIDEO_FB_0_LAST_ADDRESS` | `0x08004C` | src/ddk750_reg.h:670 | p160 | 6.2.2 | src/sm750_drm.c:3318 |
| `VIDEO_PLANE_TL` | `0x080050` | src/ddk750_reg.h:674 | p161 | 6.2.2 | src/sm750_drm.c:3319 |
| `VIDEO_PLANE_BR` | `0x080054` | src/ddk750_reg.h:678 | p161 | 6.2.2 | src/sm750_drm.c:3320 |
| `VIDEO_ALPHA_DISPLAY_CTRL` | `0x080080` | src/ddk750_reg.h:709 | p166 | 6.2.3 | src/ddk750_chip.c:272, src/ddk750_chip.c:274 |
| `PANEL_HWC_ADDRESS` | `0x0800F0` | src/ddk750_reg.h:846 | p172 | 6.2.4 | src/sm750_drm.c:110 |
| `PANEL_HWC_LOCATION` | `0x0800F4` | src/ddk750_reg.h:851 | p172 | 6.2.4 | src/sm750_drm.c:113 |
| `PANEL_HWC_COLOR_12` | `0x0800F8` | src/ddk750_reg.h:857 | p173 | 6.2.4 | src/sm750_drm.c:118 |
| `PANEL_HWC_COLOR_3` | `0x0800FC` | src/ddk750_reg.h:861 | p173 | 6.2.4 | src/sm750_drm.c:119 |
| `ALPHA_DISPLAY_CTRL` | `0x080100` | src/ddk750_reg.h:881 | p175 | 6.2.5 | src/ddk750_chip.c:277, src/ddk750_chip.c:279 |
| `ALPHA_FB_ADDRESS` | `0x080104` | src/ddk750_reg.h:896 | p176 | 6.2.5 | src/sm750_drm.c:3322 |
| `CRT_DISPLAY_CTRL` | `0x080200` | src/ddk750_reg.h:999 | p180 | 6.2.6 | src/ddk750_display.c:40, src/ddk750_display.c:153, src/ddk750_display.c:158, src/ddk750_mode.c:79 (+4 more) |
| `CRT_FB_ADDRESS` | `0x080204` | src/ddk750_reg.h:1048 | p181 | 6.2.6 | src/sm750_drm.c:3324 |
| `CRT_FB_WIDTH` | `0x080208` | src/ddk750_reg.h:1053 | p182 | 6.2.6 | src/sm750_drm.c:3325 |
| `CRT_HORIZONTAL_TOTAL` | `0x08020C` | src/ddk750_reg.h:1058 | p182 | 6.2.6 | src/ddk750_mode.c:169 |
| `CRT_HORIZONTAL_SYNC` | `0x080210` | src/ddk750_reg.h:1063 | p183 | 6.2.6 | src/ddk750_mode.c:177 |
| `CRT_VERTICAL_TOTAL` | `0x080214` | src/ddk750_reg.h:1068 | p183 | 6.2.6 | src/ddk750_mode.c:185 |
| `CRT_VERTICAL_SYNC` | `0x080218` | src/ddk750_reg.h:1073 | p184 | 6.2.6 | src/ddk750_mode.c:193 |
| `CRT_CURRENT_LINE` | `0x080220` | src/ddk750_reg.h:1087 | p185 | 6.2.6 | src/sm750_drm.c:3327 |
| `CRT_MONITOR_DETECT` | `0x080224` | src/ddk750_reg.h:1090 | p185 | 6.2.6 | src/sm750_drm.c:3328 |
| `CRT_AUTO_CENTERING_TL` | `0x080280` | src/ddk750_reg.h:1142 | p191 | 6.2.6 | src/ddk750_mode.c:38 |
| `CRT_AUTO_CENTERING_BR` | `0x080284` | src/ddk750_reg.h:1146 | p192 | 6.2.6 | src/ddk750_mode.c:40 |
| `I2C_BYTE_COUNT` | `0x010040` | src/ddk750_reg.h:1243 | p209 | 8.2 | src/ddk750_hwi2c.c:52 |
| `I2C_CTRL` | `0x010041` | src/ddk750_reg.h:1246 | p209 | 8.2 | src/ddk750_hwi2c.c:34, src/ddk750_hwi2c.c:37, src/ddk750_hwi2c.c:58, src/ddk750_hwi2c.c:59 |
| `I2C_STATUS` | `0x010042` | src/ddk750_reg.h:1253 | p210 | 8.2 | src/ddk750_hwi2c.c:62 |
| `I2C_RESET` | `0x010042` | src/ddk750_reg.h:1259 | p210 | 8.2 | src/ddk750_hwi2c.c:50 |
| `I2C_SLAVE_ADDRESS` | `0x010043` | src/ddk750_reg.h:1262 | p211 | 8.2 | src/ddk750_hwi2c.c:51 |
| `I2C_DATA0` | `0x010044` | src/ddk750_reg.h:1266 | p211 | 8.2 | src/ddk750_hwi2c.c:56, src/ddk750_hwi2c.c:78 |
| `DMA_1_SOURCE` | `0x0D0010` | src/ddk750_reg.h:1424 | p229 | 10.2 | src/sm750_drm.c:1437 |
| `DMA_1_DESTINATION` | `0x0D0014` | src/ddk750_reg.h:1429 | p229 | 10.2 | src/sm750_drm.c:1438 |
| `DMA_1_SIZE_CONTROL` | `0x0D0018` | src/ddk750_reg.h:1434 | p230 | 10.2 | src/sm750_drm.c:1447 |
| `DMA_ABORT_INTERRUPT` | `0x0D0020` | src/ddk750_reg.h:1438 | p230 | 10.2 | src/ddk750_chip.c:282, src/ddk750_chip.c:284, src/sm750_drm.c:1366, src/sm750_drm.c:1373 (+9 more) |

Notes on the cited registers:

- `I2C_STATUS` and `I2C_RESET` are the same address (0x010042), read and write
  respectively; DS-1 p210 documents both halves.
- `I2C_DATA0` (0x010044) is the first byte of the 16-byte I2C data window that
  DS-1 p211 documents as 0x010044-0x010053. The header also defines
  `I2C_DATA15` at 0x010053, which the driver does not use.
- `GPIO_MUX` is called "GPIO31:0 Control" in DS-1 Table 7 p70 and described on
  p75.
- `CURRENT_GATE` is called "Current Clock Status" in DS-1 p90.

## Registers without a datasheet citation

Three registers have no clean citation, all in the GPIO path. Count: 3.

The table below lists six: those three, plus three more that the dump table
reads and no datasheet page describes. Count: 6.

| Register | Address | Header line | Driver uses | Why uncited | Substitute | Status |
|---|---|---|---|---|---|---|
| `GPIO_DATA_DIRECTION` | `0x010004` | src/ddk750_reg.h:471 | src/ddk750_swi2c.c:72, src/ddk750_swi2c.c:77, src/ddk750_swi2c.c:435, src/ddk750_swi2c.c:443 | DS-1 Table 13 p196 and the description on p198 put "GPIO Data Direction" at 0x010008 | SUB-REG line 470: `#define GPIO_DATA_DIRECTION 0x010004`, identical to the driver; bit-banged I2C works on hardware | open: datasheet-versus-upstream address conflict, GAP-2 |
| `GPIO_DATA_SM750LE` | `0x020018` | src/ddk750_reg.h:1448 | src/ddk750_swi2c.c:387, src/ddk750_swi2c.c:394 | DS-1 never mentions SM750LE; 0x020000-0x02001C is the SSP clock block at p200 and defines different registers | SUB-REG line 1447: `#define GPIO_DATA_SM750LE 0x020018` | open: undocumented SM750LE register, GAP-3 |
| `GPIO_DATA_DIRECTION_SM750LE` | `0x02001C` | src/ddk750_reg.h:1452 | src/ddk750_swi2c.c:388, src/ddk750_swi2c.c:395 | same as above; 0x02001C is not described anywhere in DS-1 | SUB-REG line 1451: `#define GPIO_DATA_DIRECTION_SM750LE 0x02001C` | open: undocumented SM750LE register, GAP-3 |
| `GPIO_INTERRUPT_SETUP` | `0x010008` | src/ddk750_reg.h:505 | src/sm750_drm.c:3296 | DS-1 Table 13 p196 and the description on p198 put "GPIO Interrupt Setup" at 0x010010; 0x010008 is DS-1's "GPIO Data Direction" | none: SUB-REG line 470 has the same stride-4 value the driver uses | open: datasheet-versus-upstream address conflict, GAP-2 |
| `DE_STATE1` | `0x100054` | src/ddk750_reg.h:6 | src/sm750_drm.c:3329 | DS-1 has no register at 0x100054: the drawing-engine block in Table 10 p117 jumps from 0x10004C (p132) to 0x1000C8 (p133) | none | open: undocumented register, read only by the debugfs dump |
| `DE_STATE2` | `0x100058` | src/ddk750_reg.h:9 | src/sm750_drm.c:3330 | same as `DE_STATE1`; 0x100058 is absent from DS-1 | none | open: undocumented register, read only by the debugfs dump |

## Bit fields without datasheet coverage

The SM750LE display-control clock select is not in DS-1. DS-1 p180 marks
`CRT_DISPLAY_CTRL` bits 31:27 reserved and bit 25 reserved, while the driver
uses them on the SM750LE path:

| Field | Header line | Driver use | DS-1 p180 says |
|---|---|---|---|
| `CRT_DISPLAY_CTRL_CLK_MASK` (0x7 << 27) and `CRT_DISPLAY_CTRL_CLK_PLL25` .. `_PLL108` | src/ddk750_reg.h:1007-1016 | src/ddk750_mode.c:50-69 (SM750LE-only `display_control_adjust_SM750LE`) | bits 31:27 "Res" |
| `CRT_DISPLAY_CTRL_CRTSELECT` (BIT 25), `CRT_DISPLAY_CTRL_RGBBIT` (BIT 24) | src/ddk750_reg.h:1019-1020 | src/ddk750_mode.c:71 | bit 25 "Res", bit 24 "HAC" |

Both are annotated "SM750LE definition" in the header. Recorded as GAP-3.

## Derived field masks used by the driver

Not registers. The datasheet documents the field span; the literal mask value is
driver-authored. Reserved masks are the union of bits DS-1 marks reserved for
the parent register and are used to preserve those bits across
read-modify-write.

| Macro | Value | Header line | Parent register (page) | Driver uses |
|---|---|---|---|---|
| `PANEL_DISPLAY_CTRL_RESERVED_MASK` | `0xC0F08000` | src/ddk750_reg.h:538 | PANEL_DISPLAY_CTRL (p148) | src/ddk750_display.c:37, src/ddk750_mode.c:257 |
| `PANEL_FB_ADDRESS_ADDRESS_MASK` | `0x1FFFFFF` | src/ddk750_reg.h:586 | PANEL_FB_ADDRESS (p151) | src/sm750_drm.c:73 |
| `PANEL_FB_WIDTH_OFFSET_MASK` | `0x3FFF` | src/ddk750_reg.h:591 | PANEL_FB_WIDTH (p151) | src/sm750_drm.c:77 |
| `PANEL_HWC_ADDRESS_ADDRESS_MASK` | `0x3FFFFFF` | src/ddk750_reg.h:849 | PANEL_HWC_ADDRESS (p172) | src/sm750_drm.c:112 |
| `CRT_DISPLAY_CTRL_RESERVED_MASK` | `0xFB008200` | src/ddk750_reg.h:1000 | CRT_DISPLAY_CTRL (p180) | src/ddk750_display.c:41 |
| `DMA_1_DESTINATION_ADDRESS_MASK` | `0x3FFFFFF` | src/ddk750_reg.h:1432 | DMA_1_DESTINATION (p229) | src/sm750_drm.c:1439 |
| `DMA_1_SIZE_CONTROL_SIZE_MASK` | `0xFFFFFF` | src/ddk750_reg.h:1436 | DMA_1_SIZE_CONTROL (p230) | src/sm750_drm.c:1449 |

## SiI9024A TPI registers (HDMI bridge on the I2C bus)

`src/sii902x.c` defines 20 numeric register-address macros. 11 match a numeric
literal in mainline `drivers/gpu/drm/bridge/sii902x.c` (SUB-SII). 9 do not and
have no citation in DS-1, which covers the SM750 I2C controller but not the
SiI9024A register map.

| Register | Address | Header line | In SUB-SII | Status |
|---|---|---|---|---|
| `SII902X_I2C_ADDR_WRITE` | `0x72` | src/sii902x.c:14 | no (SUB-SII uses a 7-bit client address via I2C) | open: GAP-4 |
| `SII902X_TPI_AVI_OUTPUT_FORMAT` | `0x0A` | src/sii902x.c:16 | no (SUB-SII has `SII902X_TPI_AVI_IN_FORMAT` 0x09) | open: GAP-4 |
| `SII902X_SYNC_CONFIG` | `0x60` | src/sii902x.c:43 | no | open: GAP-4 |
| `SII902X_SYNC_DETECT` | `0x61` | src/sii902x.c:44 | no | open: GAP-4 |
| `SII902X_DE_GENERATOR` | `0x63` | src/sii902x.c:48 | no | open: GAP-4 |
| `SII902X_HRES_LSB` | `0x6A` | src/sii902x.c:49 | no | open: GAP-4 |
| `SII902X_HRES_MSB` | `0x6B` | src/sii902x.c:50 | no | open: GAP-4 |
| `SII902X_VRES_LSB` | `0x6C` | src/sii902x.c:51 | no | open: GAP-4 |
| `SII902X_VRES_MSB` | `0x6D` | src/sii902x.c:52 | no | open: GAP-4 |

Cited by SUB-SII (11): `SII902X_TPI_VIDEO_DATA` 0x00, `SII902X_TPI_AVI_INFOFRAME`
0x0C, `SII902X_SYS_CTRL_DATA` 0x1A, `SII902X_REG_CHIPID` 0x1B,
`SII902X_PWR_STATE_CTRL` 0x1E, `SII902X_REG_TPI_RQB` 0xC7,
`SII902X_IND_SET_PAGE` 0xBC, `SII902X_IND_OFFSET` 0xBD,
`SII902X_IND_VALUE` 0xBE, `SII902X_INT_ENABLE` 0x3C, `SII902X_INT_STATUS` 0x3D.

## Register-level discrepancies worth knowing

- Name collision in DS-1: both 0x080000 (p148) and 0x00005C (p96) are titled
  "Primary Display Control". 0x00005C is the primary display PLL and is cited as
  `PANEL_PLL_CTRL`; 0x080000 is the panel graphics control and is cited as
  `PANEL_DISPLAY_CTRL`.
- DS-1 register names differ from driver names for the primary plane stride
  registers: DS-1 calls 0x080010 "Primary Display FB Offset/Window Width" and
  0x080014 "Primary Display FB Width" and 0x080018 "Primary Display FB Height";
  the driver calls them `PANEL_FB_WIDTH` (0x080010), `PANEL_WINDOW_WIDTH`
  (0x080014) and `PANEL_WINDOW_HEIGHT` (0x080018). Same registers, shifted
  naming.
- `PANEL_FB_ADDRESS_ADDRESS_MASK` is 0x01FFFFFF (25 bits) while DS-1 p151
  documents the address field as bits 25:4 with 128-bit alignment, i.e. a 26-bit
  field ending at 0x03FFFFF0. The driver intentionally confines the frame buffer
  to the 16 MB integrated memory window; this is a driver policy mask, not a
  datasheet value.
- `CRT_AUTO_CENTERING_TL` and `CRT_AUTO_CENTERING_BR` are documented by DS-1 as
  3-register ranges (0x080280-0x080282 and 0x080284-0x080286); the driver uses
  only the first word of each.
