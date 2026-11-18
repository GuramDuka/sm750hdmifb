# SM750 VBIOS: C semantic model

A buildable, host-side reading aid for what the captured SM750 option ROM does.
It is **not** driver code and nothing in `src/` includes it: the model exists so
the ROM's behaviour can be reasoned about without a 16-bit disassembler in the
loop, and so every claim in `docs/VBIOS-REVERSE-ENGINEERING.md` has an
executable statement behind it.

The captured image is **not** in this repository. Offsets below are file
offsets; the image loads at linear `0xC0000`, so file offset `0x1256` is
`0xc1256` in the assembly and in `docs/VBIOS-REVERSE-ENGINEERING.md`.

## Building

```sh
cd vbios-re/model
for f in *.c; do /usr/bin/gcc -std=c99 -Wall -Wextra -Werror -c "$f" -o "/mega/tmp/sm750/t17/${f%.c}.o"; done
```

`/usr/bin/gcc` explicitly: on this host bare `gcc` resolves to
`/usr/local/cuda/bin/gcc`. Compile per file, because `-c` with several inputs
and a single `-o` is an error. No object files are kept in the tree.

## Files

| File | ROM routines modelled |
| --- | --- |
| `rom.c` | port and MMIO access, the sequencer/CRTC index-value protocol, GC register 6 panel test, vsync poll |
| `clock.c` | clock table (`0xaf3`), field extraction (`0xc5b3e`), PLL field programming (`0xc0220`), reset pulse (`0xc0277`), clock-select copy (`0xc5e79`), panel clock select (`0xc02a0`) |
| `panel.c` | MMIO record table (`0xc01f4`), Misc Output init (`0xc0327`), panel/CRT clock bits and `0x98000` (`0xc5e16`), window programming (`0xc5cec`) |
| `dpms.c` | display blank (`0xc340d`, reachable), display unblank (`0xc33d9`, no direct caller) |
| `mode_table.c` | mode row addressing (`0xc344c`), attribute row select (`0xc17e8`), VGA replay (`0xc334a`), keyed record table lookup (`0xc3382`) |
| `sii9024a.c` | I2C unreset (`0xc70c3`), register write shape (`0xc745e`), the 30-pair bring-up list (`0xc1317`) |

`rom.h` holds the register offsets, the trace structure and every prototype.
Register offsets carry the name `docs/specs/REGISTER-MAP.md` uses, or a
`ROM_MMIO_UNNAMED_*` macro where it has no name, so an unnamed offset is visible
as such rather than silently invented.

Every routine records its accesses in `rom_trace[]`. The trace is the point of
the model: a caller can drive a routine against a stub and compare the resulting
access order with the ROM's, which is what `0xc5e16`'s three uses of one Misc
Output read (see `panel.c`) were validated with.

## What the model establishes

* The clock path is **table-driven, not computed**: 43 stride-3 entries at file
  `0xaf3` give `(index, CRTC register, (shift << 4) | mask)`; `0xc0220` reads
  two of them and places them at bit 18 and bit 14 of `PANEL_DISPLAY_CTRL`, and
  the same bit-14 field into `CRT_DISPLAY_CTRL`. No M/N/OD/POD arithmetic
  happens anywhere in the ROM.
* `MXCLK_PLL_CTRL` is set from **two fixed constants** - `0x0002045c` or the
  board dword at file `0x167` = `0x00020451` - selected by the flat-panel bit.
* The display enable is a **two-bit latch**: sequencer register 1 bit 5 plus
  bit 2 of the low byte of both display controls, flipped together, with fixed
  retrace counts rather than a poll. Blanking sets bit 5 and clears bit 2;
  unblanking clears bit 5 and sets bit 2. `0xc340d` (blank) is the routine the
  image calls; `0xc33d9` (unblank) has no direct caller, so the unblank in the
  mode path comes from the mode's own sequencer values being replayed.
* The mode table is `0x40`-byte records at `0x7c80`, walked by
  `shl bx, 0x6` in `0xc344c`.
* The SiI9024A is brought up by 30 register writes at device `0x72`, one I2C
  transaction each, after a prologue that clears two bits in MMIO `0x08` and
  releases the two gate bits.

## Divergences from `src/*.c`

The ROM and the driver program some of the same registers differently. Both
values are recorded, because which is right is a hardware question, not a
reading question.

| Subject | ROM behaviour | Driver behaviour |
| --- | --- | --- |
| PLL source | two fields read out of the table at file `0xaf3` and written into `PANEL_DISPLAY_CTRL`/`CRT_DISPLAY_CTRL` (`0xc0220`) | `sm750_calc_pll_value()` then `sm750_format_pll_reg()`, written wholesale (`src/ddk750_chip.c:57-83`, `src/ddk750_mode.c:214`) |
| `MXCLK_PLL_CTRL` `0x070` | `0x0002045c`, or `0x00020451` when the flat-panel bit is set (`0xc02e3`/`0xc02e9`) | the same computed PLL register, `src/ddk750_chip.c:81` |
| `MODE0_GATE` `0x044` / `MODE1_GATE` `0x048` | `(old & 0xfff)`, `or 0x5000` when the panel test fails, written to both (`0xc02a5`) | `MODE0_GATE_GPIO` ORed in `src/ddk750_chip.c:191-193`; `MODE1_GATE` written only by `ddk750_set_gate()`, `src/ddk750_power.c:78-81` |
| display enable | sequencer reg 1 bit 5 **and** display-control bit 2, both controllers, fixed bit patterns (`0xc340d` blank, `0xc33d9` unblank) | `DISPLAY_CTRL_TIMING` (bit 8) then `DISPLAY_CTRL_PLANE` (bit 2), with a `PANEL_DISPLAY_CTRL` bit-11 status poll (`src/ddk750_display.c:23-64`) |
| panel power | none: Misc Output bits 6-7 fan out to display-control bits 12-13 and to `0x98000` bits 14/13 (`0xc5e16`) | `sw_panel_power_sequence()` walks `FPVDDEN`/`DATA`/`VBIASEN`/`FPEN` bits 24-27 (`src/ddk750_display.c:103-135`) |
| DPMS | no `SYSTEM_CTRL` write, no DPMS levels; only the display-enable latch | `ddk750_set_dpms()` writes `SYSTEM_CTRL_DPMS_MASK`, or `CRT_DISPLAY_CTRL` on SM750LE (`src/ddk750_power.c:6-20`) |
| window | width/height **and** `PANEL_PLANE_TL = 0`, `PANEL_PLANE_BR = ecx & 0x07ff07ff`, from two 6-byte tables at `0xc47`/`0xc49` (`0xc5cec`) | width/height only, from the mode (`src/sm750_drm.c:1330-1333`) |
| `0x098000` | bits 14 (`= misc bit 7`) and 13 (`= NOT misc bit 6`), read-modify-write (`0xc5e16`) | never touched; `0x098000` appears only as `ZV1_CAPTURE_CTRL` (`src/ddk750_reg.h:1357`) |
| SiI9024A legacy pairs | `0x82`, `0x7c`, `0xf5`, `0xc7` (`0xc1317`) | `0x82`, `0x7c`, `0xf5` (`src/sii902x.c:113-117`); `0xc7` is written later as the TPI reset request, `src/sii902x.c:194` |
| SiI9024A `0x3c`, `0x00`-`0x08`, `0x1a` | written in the ROM order (`0xc1317`) | reproduced by an inline sequence, `src/sii902x.c:298-311` |
| SiI9024A `0x26` | `0x30` (`0xc1317`) | `0x30` in `sii9024_board_init`, but `0x00` in `sii9024_clean_init`, `src/sii902x.c:224-231` |
| SiI9024A transport | bit-banged SDA `0xc728b` / SCL `0xc72d0`, one transaction per register | SM750 hardware or software I2C engine, `src/sii902x.c:242` |
| SiI9024A interrupt enable `0x3c` | `0x01` (`0xc1317`) | `SII902X_INT_ENABLE` = `0x3c` written with hotplug **and** RX-sense, i.e. `0x03`, `src/sii902x.c:35-37`, `src/sii902x.c:213-216` and `src/sii902x.c:225-227` |

The display-enable row is the one with a practical consequence: the ROM sets a
sequencer bit the driver never writes, so state left behind by a ROM run is not
something the driver's display path would clear.

## UNDETERMINED

Listed so the model does not imply knowledge it does not have:

* Field names inside the `0x40`-byte mode records. The stride, the base and the
  extent are measured; which byte is which timing is not.
* The meaning of MMIO `0x98000` bits 13 and 14. They behave as a power/enable
  pair, but `docs/specs/REGISTER-MAP.md` has no name for the register.
* Which of the two 6-byte tables (`0xc47`, `0xc49`) is horizontal by intent.
  Index 0 yields 320x200 with `0xc49` supplying the horizontal word, so the
  model follows the call order and does not rename the fields.
* Whether `0x6f40`'s checksummed `0x40`-byte block accessor ever reads a real
  EDID: the shape matches, there is no caller and no `EDID` string.
* The keyboard-controller-pair "power and enable" reading of `0x98000` would
  need the pinout; the model records bits, not functions.

## Provenance

Everything here is my own code: register names from `docs/specs/REGISTER-MAP.md`
and `src/ddk750_reg.h`, structure from the ROM measured with `objdump`. The
only vendor-derived content is the register/value lists that *are* the ROM's
data (the 43 clock entries, the 30 SiI9024A pairs, the 56 record keys), quoted
because the behaviour cannot be described without them. No vendor binary and no
generated reconstruction is committed; see `docs/PROVENANCE.md`.