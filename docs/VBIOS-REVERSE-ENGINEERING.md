# SM750 VBIOS: structure map and bit-exact reconstruction

Status: analysis complete for the captured image. Scope: this document
describes the board option ROM of the SM750 card on this host, byte for byte,
and records how a 16-bit assembly source rebuilds it exactly. It changes no
driver behaviour; nothing here is on the driver's code path.

Companion material:

| What | Where |
| --- | --- |
| Rebuild generator and verifier | `tools/vbios-re/reencode.py` |
| Region table the generator walks | `tools/vbios-re/regions.txt` |
| Skip-aware wrapper used by `make vbios-re` | `tools/vbios-re/check.sh` |
| C semantic model of the ROM | `vbios-re/model/` |
| Captured transcripts | `docs/evidence/vbios-re/` |

The captured image itself is vendor material. It is **not** in this repository,
it is never copied into the tree, and it is never part of a source package or
package payload. See `docs/PROVENANCE.md` for the decision and its basis.

## 1. The image

| Property | Value |
| --- | --- |
| Size | 49152 bytes (48 KiB, 96 blocks of 512) |
| Load address | linear `0xC0000`, segment `0xC000` |
| sha256 | `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551` |
| Whole-image byte sum | `0 mod 256` |
| Checksum byte | file offset `0x34` = `0x6b` |
| Signature | `0x55 0xaa` at `0x00` |
| Entry point | `0x03` holds `e9 50 12`, a near jump to file offset `0x1256` |

The image is 48 KiB, not the 64 KiB a full VGA BIOS bank would occupy: byte
`0x02` says 96 blocks, and the region `0x815d`-`0xc000` is 16035 bytes of pure
`0xcc` fill. The fill is what an assembler leaves behind when the source pads
to a fixed image size, so the padding is part of the deliverable and is carried
as data in the reconstruction.

All offsets in this document are **file offsets**. Add `0xC0000` for the linear
address, or read them as `0xC000:offset` for the segment form the ROM itself
uses in its far pointers.

## 2. Header, PCI data structure and VBE block

The first 466 bytes (`0x0000`-`0x01d2`) hold three structures and the string
table. They are one data region in the region table because the structures are
small, adjacent and interleaved with strings.

### 2.1 Option ROM header

| Offset | Size | Value | Meaning |
| --- | --- | --- | --- |
| `0x00` | 2 | `55 aa` | option ROM signature |
| `0x02` | 1 | `0x60` | image size in 512-byte blocks (96) |
| `0x03` | 3 | `e9 50 12` | near jump to `0x1256` |
| `0x06` | 4 | `00 00 00 00` | unused |
| `0x0a` | 2 | `0x00d9` | not determined, see section 12 |
| `0x0c` | 2 | `0x006c` | not determined, see section 12 |
| `0x0e` | 10 | zeros | unused |
| `0x18` | 2 | `0x001c` | pointer to the PCI data structure |
| `0x1a` | 2 | `0xc000` | load segment |

### 2.2 PCI data structure (`PCIR`, at `0x1c`)

| Offset | Size | Value | Field |
| --- | --- | --- | --- |
| `0x1c` | 4 | `PCIR` | signature |
| `0x20` | 2 | `0x126f` | vendor id (Silicon Motion) |
| `0x22` | 2 | `0x0750` | device id (SM750) |
| `0x24` | 2 | `0x0000` | vital product data pointer (none) |
| `0x26` | 2 | `0x0018` | structure length |
| `0x28` | 1 | `0x00` | structure revision |
| `0x29` | 3 | `00 00 03` | class code (display controller, VGA) |
| `0x2c` | 2 | `0x0060` | image length in 512-byte blocks |
| `0x2e` | 2 | `0x0000` | code revision |
| `0x30` | 1 | `0x00` | code type (x86, not EFI) |
| `0x31` | 1 | `0x80` | indicator: last image in this ROM |
| `0x32` | 2 | `00 00` | reserved |
| `0x34` | 1 | `0x6b` | checksum |
| `0x35` | 1 | `0x09` | first byte after the structure |

The `PCIR` checksum byte is `0x6b` at `0x34`, which is offset `0x18` from the
`PCIR` signature, so the checksum byte is the last byte of a 24-byte structure.
The byte at `0x33` is `0x00` and the sum of `0x1c`-`0x33` is 1, so **the
structure does not self-validate under the PCI firmware convention**. The only
convention that validates is the whole-image sum: `sum(all 49152 bytes) == 0
mod 256`, with byte `0x34` carrying the complement. The build computes that
byte from the rebuilt image and fails if it differs from the captured value
(section 10). Which span the vendor intended the `0x34` byte to cover is
UNDETERMINED (section 12).

### 2.3 VBE block (at `0x7f`)

| Offset | Size | Value | Field |
| --- | --- | --- | --- |
| `0x7f` | 4 | `VESA` | signature |
| `0x83` | 2 | `0x0200` | VBE version 2.0 |
| `0x85` | 4 | `c000:005b` | far pointer to the OEM string |
| `0x89` | 4 | `0x00000000` | capabilities |
| `0x8d` | 4 | `c000:7aac` | far pointer to the mode list |

The OEM string at `0x5b` is `Silicon Motion SM750 VGA BIOS (CRT)`.

Two VBE fields do not resolve:

* The mode-list pointer `c000:7aac` lands on `df 7a d7 7a cf 7a c9 7a`, four
  little-endian word pointers (`0x7adf`, `0x7ad7`, `0x7acf`, `0x7ac9`) followed
  by zeros. That is not a VBE mode list: there is no `0xffff` terminator and
  the first word is not a mode attribute word. UNDETERMINED.
* VBE 2.0 puts the total video memory in MiB at `0x91`. The byte at `0x91` is
  `S`, the first character of the ASCII string `SM750`, so the field is
  occupied by a string and no memory size can be read from it. UNDETERMINED.

### 2.4 String table

| Offset | Text |
| --- | --- |
| `0x36` | `Version 1.00.59-` then spaces, NUL at `0x48` |
| `0x4a` | `05/14/19 16:25` (build date and time) |
| `0x5b` | `Silicon Motion SM750 VGA BIOS (CRT)` |
| `0x7f` | `VESA` |
| `0x91` | `SM750` |
| `0x99` | vendor copyright banner, NUL-terminated, ending `0x0d 0x0a 0xf9` at `0xf9` |

The banner at `0x99` is elided here: it contains the phrase that
`tests/audit-release.sh` rejects in shipped text, which is one of the reasons
the reconstruction is not committed (section 11). The bytes are carried
verbatim by the generator from the captured image, so the rebuild is still
exact.

A keyword count over the whole image is worth recording because it bounds what
the ROM can claim: `HDMI` 0, `CRT` 1 (the banner above), `LVDS` 0, `DVI` 0,
`TMDS` 0, `EDID` 0, `SiD9024` 0, `DDC` 0. The `(CRT)` in the banner is a
label, not a statement that the ROM drives only an analogue output, and it
implies nothing about HDMI support. The ROM does contain an I2C/SiI9024A
register sequence (section 6.6) with the device address `0x72`.

## 3. Region map

The map below covers all 49152 bytes: 239 contiguous regions, 120 code and 119
data, with no gap and no overlap. `tools/vbios-re/reencode.py` asserts that the
table tiles `0..0xc000` before it emits anything, so a table edit that leaves a
hole fails the build rather than producing a short image.

The evidence column is computed from the bytes by a tag pass over the
`objdump` listing of the image, using the tags below. The pass is scratch-only
(the rules are listed here so the column can be re-derived from the image and
`objdump` alone, without the script):

| Tag | Test |
| --- | --- |
| `dec` | the span decodes to complete instructions, ending exactly on its last byte, with no undecodable byte and no mnemonic real-mode BIOS code would not use |
| `tbl` | none of the other tests apply: a table, a pointer list or mixed data |
| `print` | at least 85 percent of the bytes are printable ASCII or NUL |
| `rec-22`, `rec-12` | a run of fixed-stride records, at least four of them, length divisible by the stride |
| `ptr6` | a run of 6-byte far pointers whose segment field is `0xc000` |
| `fill` | every byte is `0xcc` |
| `straddle` | a code region that does not decode cleanly from its first byte |

Counts: `dec` 119, `tbl` 112, `print` 6, `straddle` 1, `fill` 1.

The single `straddle` is `0x805b`-`0x815d`, the VBE/FP entry point. Its third
instruction is `66 9a 51 61 00 c0`, a 32-bit-operand far call to `c000:6151`.
objdump prints the seven-byte `66 9a` form as an eight-byte instruction and
then re-syncs, so its text shows a spurious `xor WORD PTR [si],0xc000` at
`0x8073`. The generator detects the `66 9a ... 66 9a` wrap and re-splits the
slot into two six-byte instructions, which is why the rebuild is exact while
objdump's own text for this region is not. Nothing about the encoding is
ambiguous: the ROM bytes are `66 9a 51 61 00 c0`, and both nasm and the
generator emit exactly that.

### 3.1 Per-region table

One row per region, in address order. `len` is the byte count; `kind` is the
class the generator uses to decide whether to decode or to emit `db`; `evidence`
is the tag defined above; the last column is the first twelve bytes, so a reader
can find the region in a hex dump without the image.

| Span | Len | Kind | Evidence | First bytes |
| --- | --- | --- | --- | --- |
| `0000`-`01d2` |   466 | data | tbl | `55 aa 60 e9 50 12 00 00 00 00 d9 00` |
| `01d2`-`01f0` |    30 | code | dec | `ff 50 53 52 33 db 2e 8a 97 08 01 80` |
| `01f0`-`01f4` |     4 | data | tbl | `5a 5b 58 c3 33 ff 66 2e 8b 9d 1b 01` |
| `01f4`-`021f` |    43 | code | dec | `33 ff 66 2e 8b 9d 1b 01 66 83 fb ff` |
| `021f`-`0220` |     1 | data | tbl | `c3 53 b2 02 e8 18 59 50 66 bb 00 00` |
| `0220`-`02f1` |   209 | code | dec | `53 b2 02 e8 18 59 50 66 bb 00 00 08` |
| `02f1`-`02f8` |     7 | data | print | `53 51 52 e8 6e 5d 73 04 b0 a0 eb 06` |
| `02f8`-`047a` |   386 | code | dec | `04 b0 a0 eb 06 b5 08 e8 08 5d ec 5a` |
| `047a`-`0500` |   134 | data | tbl | `e8 ee 2f 2e 0f b6 9f eb 64 c3 ee 04` |
| `0500`-`062a` |   298 | code | dec | `4c 8b 38 10 24 85 37 87 05 86 0a 84` |
| `062a`-`0634` |    10 | data | tbl | `fe c3 c3 33 ff b9 08 00 ab d1 c8 e2` |
| `0634`-`07e7` |   435 | code | dec | `c8 e2 fb c3 50 52 ba cc 03 ec 8a d8` |
| `07e7`-`085b` |   116 | data | tbl | `00 0f 00 00 00 00 00 00 00 00 00 00` |
| `085b`-`0903` |   168 | code | dec | `4b 29 6f 29 b8 05 00 03 10 01 14 05` |
| `0903`-`094e` |    75 | data | tbl | `6b d1 6b d7 6b 28 03 00 08 6c 11 09` |
| `094e`-`09e2` |   148 | code | dec | `66 75 66 8c 66 a4 66 b0 66 c5 66 f0` |
| `09e2`-`09e8` |     6 | data | tbl | `e2 f0 61 44 44 c3 32 ff d1 e3 2e 8b` |
| `09e8`-`0a40` |    88 | code | dec | `32 ff d1 e3 2e 8b 31 89 76 10 81 fe` |
| `0a40`-`0a44` |     4 | data | tbl | `61 07 1f c3 8e 5e 12 8f 46 12 61 07` |
| `0a44`-`0a4d` |     9 | code | dec | `8e 5e 12 8f 46 12 61 07 c3 52 b2 00` |
| `0a4d`-`0a55` |     8 | data | tbl | `52 b2 00 e8 eb 50 5a c3 50 53 51 8a` |
| `0a55`-`0af2` |   157 | code | dec | `50 53 51 8a d8 e8 25 29 0f 82 8d 00` |
| `0af2`-`0fb7` |  1221 | data | tbl | `c3 00 96 08 01 95 62 02 95 42 06 95` |
| `0fb7`-`101b` |   100 | code | dec | `38 3f d1 e3 2e 8b b7 56 0f 33 db 2e` |
| `101b`-`101c` |     1 | data | tbl | `c3 33 d2 33 c9 33 db 51 52 80 fb 06` |
| `101c`-`10a3` |   135 | code | dec | `33 d2 33 c9 33 db 51 52 80 fb 06 75` |
| `10a3`-`10a9` |     6 | data | tbl | `bf 10 00 eb d4 c3 c8 0c 00 00 60 53` |
| `10a9`-`1134` |   139 | code | dec | `c8 0c 00 00 60 53 89 7e f4 89 7e f8` |
| `1134`-`1158` |    36 | data | tbl | `fc ff fc ff f8 ff f8 ff fa ff fa ff` |
| `1158`-`1197` |    63 | code | dec | `8a e3 8a c6 e8 11 00 8a f0 8a c5 e8` |
| `1197`-`11d9` |    66 | data | tbl | `0f 20 0f 30 2f 50 33 50 37 50 3b 50` |
| `11d9`-`124b` |   114 | code | dec | `0b f0 0c f0 0d f0 56 52 8a d4 32 e4` |
| `124b`-`1253` |     8 | data | tbl | `50 b0 3d e8 ef 21 f6 c4 08 58 c3 c8` |
| `1253`-`1634` |   993 | code | dec | `08 58 c3 c8 0a 00 00 1e 66 60 06 e8` |
| `1634`-`1639` |     5 | data | tbl | `3b 16 23 00 74 03 e9 c1 00 f6 06 4a` |
| `1639`-`1658` |    31 | code | dec | `03 e9 c1 00 f6 06 4a 00 01 75 14 f6` |
| `1658`-`165e` |     6 | data | tbl | `f6 06 49 00 01 75 f7 e9 8a 04 80 c2` |
| `165e`-`16ca` |   108 | code | dec | `f7 e9 8a 04 80 c2 06 ec b2 c0 b0 20` |
| `16ca`-`16e1` |    23 | data | tbl | `a0 48 00 8a c8 80 e1 f0 24 0f 3c 0b` |
| `16e1`-`1c12` |  1329 | code | dec | `0a c1 a2 48 00 f6 06 49 00 80 74 11` |
| `1c12`-`1c13` |     1 | data | print | `32 e4 c3 e8 19 ee e8 09 16 72 0d a2` |
| `1c13`-`1d3e` |   299 | code | dec | `e4 c3 e8 19 ee e8 09 16 72 0d a2 22` |
| `1d3e`-`1d45` |     7 | data | tbl | `e8 e3 14 72 06 e8 eb 14 74 01 c3 c8` |
| `1d45`-`2001` |   700 | code | dec | `14 74 01 c3 c8 1a 00 00 b4 08 88 7e` |
| `2001`-`2030` |    47 | data | tbl | `00 b8 59 21 f9 21 f9 21 00 b8 5f 21` |
| `2030`-`2159` |   297 | code | dec | `65 00 a0 ae 21 ad 22 d9 22 00 a0 ae` |
| `2159`-`215c` |     3 | data | tbl | `03 f2 03 f6 ad c3 c6 46 fc 00 c1 e6` |
| `215c`-`21f9` |   157 | code | dec | `f6 ad c3 c6 46 fc 00 c1 e6 02 03 f2` |
| `21f9`-`2200` |     7 | data | tbl | `03 fd 03 ff f3 ab c3 e8 71 00 60 b9` |
| `2200`-`233f` |   319 | code | dec | `e8 71 00 60 b9 04 00 ac e8 e6 0f ab` |
| `233f`-`2366` |    39 | data | tbl | `dc 23 dc 23 dd 23 6b 24 14 24 98 24` |
| `2366`-`23dc` |   118 | code | dec | `23 46 25 00 a0 00 b8 e8 c1 e6 8b f0` |
| `23dc`-`23dd` |     1 | data | tbl | `c3 2e 8e 06 6b 23 8b d9 8b fa 80 e2` |
| `23dd`-`2668` |   651 | code | dec | `2e 8e 06 6b 23 8b d9 8b fa 80 e2 fe` |
| `2668`-`2678` |    16 | data | tbl | `fe ca 7d cf 32 d2 eb cb b9 02 00 bb` |
| `2678`-`2683` |    11 | code | dec | `e3 e8 b5 e3 3c 03 76 03 e9 94 00 0b` |
| `2683`-`2686` |     3 | data | tbl | `0b c9 75 03 e9 8d 00 8b f0 8b fb c1` |
| `2686`-`27a8` |   290 | code | dec | `03 e9 8d 00 8b f0 8b fb c1 ef 08 52` |
| `27a8`-`27a9` |     1 | data | print | `32 db e8 46 00 8a 1e 26 00 eb 22 80` |
| `27a9`-`280e` |   101 | code | dec | `db e8 46 00 8a 1e 26 00 eb 22 80 3e` |
| `280e`-`2815` |     7 | data | tbl | `e8 20 e2 b3 11 e8 7d 0a b3 10 eb e6` |
| `2815`-`2867` |    82 | code | dec | `0a b3 10 eb e6 e8 14 e2 8b f2 06 e8` |
| `2867`-`286f` |     8 | data | tbl | `e8 c7 e1 e8 0f 0a 88 7e 09 e9 cd e1` |
| `286f`-`291e` |   175 | code | dec | `09 e9 cd e1 e8 bb e1 b3 11 e8 ec ff` |
| `291e`-`2934` |    22 | data | tbl | `e8 10 e1 e3 0f 8b fa ba c7 03 8a c3` |
| `2934`-`293f` |    11 | code | dec | `e8 fa e0 8a c3 ba c6 03 ee eb 2d e8` |
| `293f`-`2947` |     8 | data | tbl | `e8 ef e0 ba c6 03 ec 88 46 08 eb 21` |
| `2947`-`29ec` |   165 | code | dec | `46 08 eb 21 e8 e3 e0 b3 10 e8 29 09` |
| `29ec`-`29f1` |     5 | data | tbl | `e8 42 e0 be 0c 00 b7 10 eb be e8 38` |
| `29f1`-`2a2c` |    59 | code | dec | `00 b7 10 eb be e8 38 e0 ba c4 03 b0` |
| `2a2c`-`2a31` |     5 | data | tbl | `e8 02 e0 be 04 00 b1 0e eb 6b e8 f8` |
| `2a31`-`2a40` |    15 | code | dec | `00 b1 0e eb 6b e8 f8 df be 06 00 b1` |
| `2a40`-`2a45` |     5 | data | tbl | `e8 ee df be 0c 00 b1 10 eb 57 e8 e4` |
| `2a45`-`2a62` |    29 | code | dec | `00 b1 10 eb 57 e8 e4 df 80 ff 07 77` |
| `2a62`-`2a69` |     7 | data | tbl | `75 08 66 26 ff 36 0c 01 eb 0e c1 eb` |
| `2a69`-`2a91` |    40 | code | dec | `01 eb 0e c1 eb 08 d1 e3 8c ca 2e 8b` |
| `2a91`-`2a9b` |    10 | data | tbl | `00 00 00 00 9a 3c 99 34 99 38 9a 4a` |
| `2a9b`-`2b47` |   172 | code | dec | `9a 4a c8 4a c8 5a 6a 00 07 2e 8b 84` |
| `2b47`-`2b7a` |    51 | data | tbl | `c8 64 64 64 64 64 64 af af f0 f0 64` |
| `2b7a`-`2c10` |   150 | code | dec | `47 2b 2e d7 32 e4 d1 e0 eb 1a b8 90` |
| `2c10`-`2c16` |     6 | data | tbl | `c6 46 0e 12 e9 29 de c6 46 0e 00 e9` |
| `2c16`-`2cfb` |   229 | code | dec | `de c6 46 0e 00 e9 22 de e8 10 de 8a` |
| `2cfb`-`2d03` |     8 | data | tbl | `e8 33 dd e9 16 ff e8 2d dd 0e e8 4e` |
| `2d03`-`2d11` |    14 | code | dec | `dd 0e e8 4e e5 e9 05 ff e8 23 dd e9` |
| `2d11`-`2d12` |     1 | data | tbl | `e8 1d dd e9 00 ff e8 17 dd 80 0e 49` |
| `2d12`-`2d33` |    33 | code | dec | `1d dd e9 00 ff e8 17 dd 80 0e 49 00` |
| `2d33`-`2d3f` |    12 | data | tbl | `e8 d7 06 e9 d7 fe c6 46 0e 1a e9 00` |
| `2d3f`-`2dbd` |   126 | code | dec | `dd c6 46 0e 00 e9 f9 dc e8 e7 dc 8a` |
| `2dbd`-`2dc3` |     6 | data | tbl | `e8 71 dc 0b db 74 03 e9 79 ff b8 c2` |
| `2dc3`-`2eb8` |   245 | code | dec | `03 e9 79 ff b8 c2 2e ab 8c c8 ab b9` |
| `2eb8`-`2ecf` |    23 | data | tbl | `06 02 0a 04 0e 08 08 01 0c 10 ff e0` |
| `2ecf`-`2f43` |   116 | code | dec | `00 3f 00 c6 46 0e 1c e9 67 db e8 55` |
| `2f43`-`2f7a` |    55 | data | tbl | `53 52 55 1e 06 8b 2e 23 00 26 89 3f` |
| `2f7a`-`2f86` |    12 | code | dec | `00 32 c0 e8 3a 00 8b d5 80 c2 06 8a` |
| `2f86`-`2f95` |    15 | data | tbl | `fa b9 15 00 32 db ec b2 c0 8a c3 ee` |
| `2f95`-`2fba` |    37 | code | dec | `8a d7 fe c3 e2 f1 ec b2 c0 b0 20 ee` |
| `2fba`-`2fc7` |    13 | data | tbl | `ee fe c2 eb 00 6c fe ca fe c0 e2 f4` |
| `2fc7`-`3019` |    82 | code | dec | `ee fe c2 50 ac ee 58 fe ca fe c0 e2` |
| `3019`-`302d` |    20 | data | tbl | `51 26 89 7f 04 ba c8 03 6c 4a 4a 6c` |
| `302d`-`31f1` |   452 | code | dec | `17 10 9c 0e e8 36 d9 59 c3 60 1e 06` |
| `31f1`-`3206` |    21 | data | tbl | `bb 08 32 8a d0 24 0f 2e d7 8a e0 8a` |
| `3206`-`32cc` |   198 | code | dec | `e6 c3 00 03 0c 0f 30 33 3c 3f c0 c3` |
| `32cc`-`32d4` |     8 | data | tbl | `ba ba 03 ec b2 da ec c3 51 b9 ff ff` |
| `32d4`-`3392` |   190 | code | dec | `51 b9 ff ff e8 e9 00 83 c2 06 0b c9` |
| `3392`-`3394` |     2 | data | print | `2e 38 87 9b 63 74 05 83 c3 05 eb e9` |
| `3394`-`33b4` |    32 | code | dec | `87 9b 63 74 05 83 c3 05 eb e9 66 2e` |
| `33b4`-`33b5` |     1 | data | tbl | `e8 c8 ff e8 b1 00 c3 8a e7 ef fe c0` |
| `33b5`-`3440` |   139 | code | dec | `c8 ff e8 b1 00 c3 8a e7 ef fe c0 8a` |
| `3440`-`344c` |    12 | code | dec | `e8 81 ff ee ed c3 ba d4 03 ee ed c3` |
| `344c`-`345f` |    19 | code | dec | `b8 44 00 8e d8 32 ff c1 e3 06 c5 36` |
| `345f`-`3461` |     2 | data | tbl | `e8 62 ff 32 c0 b9 19 00 e8 59 fe c3` |
| `3461`-`3499` |    56 | code | dec | `ff 32 c0 b9 19 00 e8 59 fe c3 e8 14` |
| `3499`-`5b2c` |  9875 | data | tbl | `00 00 00 00 00 00 00 00 7e 81 a5 81` |
| `5b2c`-`5b33` |     7 | code | dec | `9c ba c4 03 ee eb 00 42 86 e0 ec 86` |
| `5b33`-`5b3e` |    11 | data | tbl | `42 86 e0 ec 86 e0 eb 00 4a 9d c3 53` |
| `5b3e`-`5b83` |    69 | code | dec | `53 51 52 33 db 2e 80 bf f3 0a ff 74` |
| `5b83`-`5b88` |     5 | data | tbl | `f9 5a 59 5b c3 50 53 51 52 33 db 2e` |
| `5b88`-`5bd1` |    73 | code | dec | `50 53 51 52 33 db 2e 80 bf f3 0a ff` |
| `5bd1`-`5bd7` |     6 | data | tbl | `f9 5a 59 5b 58 c3 fc 2e ad 83 f8 ff` |
| `5bd7`-`5be5` |    14 | code | dec | `fc 2e ad 83 f8 ff 74 0a ee 42 86 e0` |
| `5be5`-`5bea` |     5 | data | tbl | `ee 4a eb ef c3 2e 8a 24 46 ef 40 e2` |
| `5bea`-`5c7b` |   145 | code | dec | `2e 8a 24 46 ef 40 e2 f8 c3 66 60 e8` |
| `5c7b`-`5c83` |     8 | data | tbl | `e8 75 ff e8 ab ff e8 f5 01 c3 66 60` |
| `5c83`-`5da6` |   291 | code | dec | `01 c3 66 60 66 bb 0c 00 08 00 e8 91` |
| `5da6`-`5da8` |     2 | data | tbl | `be b1 0d eb 03 be c1 0d 2e 8a 0e b3` |
| `5da8`-`5fdf` |   567 | code | dec | `0d eb 03 be c1 0d 2e 8a 0e b3 0e 2e` |
| `5fdf`-`5fe7` |     8 | data | tbl | `b0 11 e9 5c d4 52 e8 14 00 93 e8 02` |
| `5fe7`-`604b` |   100 | code | dec | `00 93 e8 02 00 5a c3 53 52 56 33 db` |
| `604b`-`604d` |     2 | data | tbl | `f8 c3 e8 15 00 fe c7 80 ff 20 75 08` |
| `604d`-`6063` |    22 | code | dec | `e8 15 00 fe c7 80 ff 20 75 08 fe c3` |
| `6063`-`6070` |    13 | data | tbl | `f9 c3 32 db 32 ff e8 bd ff c3 c3 c3` |
| `6070`-`607a` |    10 | code | dec | `8b cf 8a e9 32 c9 e8 91 ff c3 e8 f3` |
| `607a`-`607f` |     5 | data | tbl | `e8 f3 ff ec 86 c1 f8 c3 e8 eb ff ed` |
| `607f`-`6092` |    19 | code | dec | `c1 f8 c3 e8 eb ff ed 91 f8 c3 e8 e4` |
| `6092`-`60a2` |    16 | data | tbl | `51 e8 da ff 58 ee f8 c3 51 e8 d2 ff` |
| `60a2`-`60ad` |    11 | code | dec | `66 51 e8 c9 ff 66 58 66 ef f8 c3 c3` |
| `60ad`-`60af` |     2 | data | tbl | `c3 c3 50 66 be de 5a 00 00 2e 8b 04` |
| `60af`-`6106` |    87 | code | dec | `50 66 be de 5a 00 00 2e 8b 04 0b c0` |
| `6106`-`610b` |     5 | data | tbl | `e8 ed ff c1 e0 0a c3 50 e8 d3 fe c1` |
| `610b`-`6118` |    13 | code | dec | `0a c3 50 e8 d3 fe c1 e0 03 86 c1 58` |
| `6118`-`611f` |     7 | data | tbl | `50 b2 41 e8 20 fa a8 01 58 c3 50 b2` |
| `611f`-`613d` |    30 | code | dec | `01 58 c3 50 b2 41 e8 16 fa 3c 02 58` |
| `613d`-`6144` |     7 | data | tbl | `50 b2 33 e8 fb f9 a8 01 58 c3 50 b2` |
| `6144`-`61ad` |   105 | code | dec | `01 58 c3 50 b2 12 e8 f1 f9 a8 01 58` |
| `61ad`-`61b3` |     6 | data | tbl | `53 bb 01 00 e8 be ff 5b c3 50 e8 25` |
| `61b3`-`62a5` |   242 | code | dec | `ff 5b c3 50 e8 25 fe 80 e4 7f ef 58` |
| `62a5`-`62ad` |     8 | data | tbl | `e8 8d ff 66 5a 66 58 c3 66 50 53 b0` |
| `62ad`-`6309` |    92 | code | dec | `66 50 53 b0 e2 e6 43 e4 40 24 06 3c` |
| `6309`-`6310` |     7 | data | tbl | `33 db c3 e8 b1 fe e8 59 d1 c3 51 b9` |
| `6310`-`639b` |   139 | code | dec | `59 d1 c3 51 b9 2c 01 e8 0e 0d e2 fb` |
| `639b`-`63df` |    68 | data | tbl | `00 60 57 80 01 01 60 57 80 01 02 60` |
| `63df`-`63e9` |    10 | code | dec | `11 17 29 c8 af 11 2d 2b c8 cf 11 6a` |
| `63e9`-`640d` |    36 | data | tbl | `11 6a 30 cb 61 16 05 32 cb a1 16 0a` |
| `640d`-`6435` |    40 | code | dec | `05 41 ca a1 10 0a 42 ca 61 11 05 43` |
| `6435`-`64a7` |   114 | data | tbl | `05 49 ca a1 16 0a 4a c7 4a 19 03 4b` |
| `64a7`-`6619` |   370 | code | dec | `14 1f 72 c8 a9 14 3e 74 c8 c9 14 76` |
| `6619`-`6622` |     9 | data | tbl | `c7 46 0e 5f 00 e9 1f a4 c7 46 0e 5f` |
| `6622`-`6656` |    52 | code | dec | `46 0e 5f 01 e9 17 a4 e8 05 a4 c7 46` |
| `6656`-`665f` |     9 | data | tbl | `e8 d8 a3 eb be e8 d3 a3 eb b9 e8 ce` |
| `665f`-`666d` |    14 | code | dec | `b9 e8 ce a3 eb b4 e8 c9 a3 e8 da f8` |
| `666d`-`6674` |     7 | data | tbl | `e8 c1 a3 e8 ac f8 eb a4 e8 b9 a3 66` |
| `6674`-`66a4` |    48 | code | dec | `a4 e8 b9 a3 66 bb 00 02 08 00 e8 a0` |
| `66a4`-`66a5` |     1 | data | tbl | `e8 8a a3 e8 a3 a3 88 46 08 e9 69 ff` |
| `66a5`-`66f0` |    75 | code | dec | `8a a3 e8 a3 a3 88 46 08 e9 69 ff e8` |
| `66f0`-`66f1` |     1 | data | tbl | `e8 3e a3 e9 23 ff c7 46 0e 4f 03 e9` |
| `66f1`-`6976` |   645 | code | dec | `3e a3 e9 23 ff c7 46 0e 4f 03 e9 42` |
| `6976`-`697a` |     4 | data | tbl | `80 fa 02 74 03 e9 88 fd f6 c1 01 75` |
| `697a`-`69dc` |    98 | code | dec | `03 e9 88 fd f6 c1 01 75 07 b0 01 e8` |
| `69dc`-`69de` |     2 | data | tbl | `e9 27 fd e8 4f a0 e8 47 f8 0f 82 89` |
| `69de`-`6a6f` |   145 | code | dec | `fd e8 4f a0 e8 47 f8 0f 82 89 00 0b` |
| `6a6f`-`6a73` |     4 | data | tbl | `e9 8c fc e9 91 fc e8 b9 9f e8 fa c8` |
| `6a73`-`6ae2` |   111 | code | dec | `91 fc e8 b9 9f e8 fa c8 80 fb 08 74` |
| `6ae2`-`6ae9` |     7 | data | tbl | `e8 4c 9f e8 eb 02 89 46 0c e9 20 fc` |
| `6ae9`-`6b66` |   125 | code | dec | `46 0c e9 20 fc e8 40 9f e8 ff 02 e8` |
| `6b66`-`6b67` |     1 | data | tbl | `e8 c8 9e e8 87 02 66 0d 00 00 00 80` |
| `6b67`-`6b85` |    30 | code | dec | `c8 9e e8 87 02 66 0d 00 00 00 80 e8` |
| `6b85`-`6b93` |    14 | data | tbl | `b7 06 eb 08 80 ff 06 74 03 e9 6d fb` |
| `6b93`-`6bb7` |    36 | code | dec | `09 e9 77 fb e8 97 9e 8a c2 ba c8 03` |
| `6bb7`-`6bd6` |    31 | data | tbl | `e8 77 9e 8a c2 ba c7 03 ee 42 42 6c` |
| `6bd6`-`6c08` |    50 | code | dec | `fb e8 57 9e 66 c1 e2 10 b0 01 e8 49` |
| `6c08`-`6c0c` |     4 | data | tbl | `bb 10 07 eb f7 e8 21 9e e8 d6 f9 e8` |
| `6c0c`-`6c72` |   102 | code | dec | `f7 e8 21 9e e8 d6 f9 e8 f3 f9 66 bb` |
| `6c72`-`6c73` |     1 | data | tbl | `e8 bc 9d e8 81 f9 66 bb 4c 00 00 00` |
| `6c73`-`6caa` |    55 | code | dec | `bc 9d e8 81 f9 66 bb 4c 00 00 00 e8` |
| `6caa`-`6cae` |     4 | data | print | `56 42 45 2f 46 50 ff 00 01 03 00 00` |
| `6cae`-`6d9a` |   236 | code | dec | `46 50 ff 00 01 03 00 00 00 00 00 00` |
| `6d9a`-`6da1` |     7 | data | tbl | `57 32 c0 f3 aa 5f c3 2e a1 83 00 ab` |
| `6da1`-`6dcb` |    42 | code | dec | `2e a1 83 00 ab 8c c8 66 c1 e0 10 b8` |
| `6dcb`-`6dcd` |     2 | data | tbl | `9a 81 34 00 c0 8b d0 cb e8 2c f4 e8` |
| `6dcd`-`6e82` |   181 | code | dec | `34 00 c0 8b d0 cb e8 2c f4 e8 33 f5` |
| `6e82`-`6e86` |     4 | data | tbl | `b8 ff 3f c3 e8 d4 ff 50 e8 79 f2 92` |
| `6e86`-`7028` |   418 | code | dec | `e8 d4 ff 50 e8 79 f2 92 58 2b d0 8b` |
| `7028`-`702b` |     3 | data | tbl | `50 58 c3 66 bb 08 00 00 00 e8 ed f2` |
| `702b`-`711c` |   241 | code | dec | `66 bb 08 00 00 00 e8 ed f2 66 25 ff` |
| `711c`-`7121` |     5 | data | tbl | `50 b0 01 e8 69 01 b0 01 e8 a9 01 32` |
| `7121`-`7152` |    49 | code | dec | `01 b0 01 e8 a9 01 32 c0 e8 5f 01 58` |
| `7152`-`7158` |     6 | data | tbl | `50 e8 d1 01 e8 c2 01 58 c3 e8 ff 01` |
| `7158`-`716d` |    21 | code | dec | `01 58 c3 e8 ff 01 72 0c e8 b2 01 e8` |
| `716d`-`7175` |     8 | data | tbl | `e8 b8 fe b8 4f 00 f8 c3 50 66 53 0b` |
| `7175`-`7315` |   416 | code | dec | `50 66 53 0b f6 75 42 0a c0 74 16 66` |
| `7315`-`7316` |     1 | data | print | `32 c0 e8 e6 fe c3 b0 01 e8 e0 fe c3` |
| `7316`-`7321` |    11 | code | dec | `c0 e8 e6 fe c3 b0 01 e8 e0 fe c3 32` |
| `7321`-`7328` |     7 | data | tbl | `32 c0 e8 4f fe c3 b0 01 e8 49 fe c3` |
| `7328`-`7336` |    14 | code | dec | `01 e8 49 fe c3 b0 01 e8 ce fe e8 40` |
| `7336`-`733d` |     7 | data | tbl | `34 01 e8 c5 fe e8 37 fe c3 52 e8 ca` |
| `733d`-`7432` |   245 | code | dec | `fe c3 52 e8 ca fd 50 e8 43 01 8a c3` |
| `7432`-`7436` |     4 | data | tbl | `e8 d8 fc e8 52 00 0a e4 74 02 eb 1d` |
| `7436`-`7449` |    19 | code | dec | `52 00 0a e4 74 02 eb 1d 8a c3 e8 47` |
| `7449`-`744a` |     1 | data | tbl | `8a c1 e8 3c 00 0a e4 74 02 eb 07 e8` |
| `744a`-`745b` |    17 | code | dec | `c1 e8 3c 00 0a e4 74 02 eb 07 e8 d7` |
| `745b`-`7463` |     8 | data | tbl | `b0 01 c3 e8 bb fc e8 78 00 0b c0 74` |
| `7463`-`7475` |    18 | code | dec | `00 0b c0 74 02 eb 1d 8a c3 e8 6d 00` |
| `7475`-`7476` |     1 | data | tbl | `8a c1 e8 62 00 0b c0 74 02 eb 07 e8` |
| `7476`-`7487` |    17 | code | dec | `c1 e8 62 00 0b c0 74 02 eb 07 e8 bd` |
| `7487`-`7488` |     1 | data | tbl | `b0 01 c3 51 52 8a d0 b9 08 00 e8 81` |
| `7488`-`7532` |   170 | code | dec | `01 c3 51 52 8a d0 b9 08 00 e8 81 fe` |
| `7532`-`753a` |     8 | data | tbl | `ee 42 6c 4a 40 e2 f9 c3 ee 42 50 ac` |
| `753a`-`7603` |   201 | code | dec | `ee 42 50 ac ee 58 4a 40 e2 f6 c3 e8` |
| `7603`-`7634` |    49 | data | tbl | `51 55 e8 bc bd 8b ea 57 83 c7 3c ba` |
| `7634`-`7640` |    12 | code | dec | `00 32 c0 e8 f8 fe 8b d5 83 c2 06 8a` |
| `7640`-`764e` |    14 | data | tbl | `fa b9 15 00 32 db ec b2 c0 8a c3 ee` |
| `764e`-`7769` |   283 | code | dec | `8a d7 fe c3 e2 f2 ec b2 c0 b0 20 ee` |
| `7769`-`7771` |     8 | data | tbl | `51 ba c8 03 6c b2 c6 6c 42 32 c0 ee` |
| `7771`-`779a` |    41 | code | dec | `42 32 c0 ee b9 00 03 b2 c9 f3 6c 59` |
| `779a`-`77d3` |    57 | data | tbl | `1b 01 1a 01 07 01 18 01 17 01 05 01` |
| `77d3`-`7826` |    83 | code | dec | `2d 27 28 90 2b a0 bf 1f 00 c7 06 07` |
| `7826`-`79c0` |   410 | data | tbl | `50 40 df 00 e3 ff 00 01 02 03 04 05` |
| `79c0`-`79cc` |    12 | code | dec | `00 00 00 00 00 10 0a 00 ff a0 3f 10` |
| `79cc`-`7c80` |   692 | data | tbl | `00 fa 01 0f 03 0e 2b ce 9f 9f 00 a7` |
| `7c80`-`7ca6` |    38 | code | dec | `00 00 00 00 00 00 05 0f ff 50 18 10` |
| `7ca6`-`7dfd` |   343 | data | tbl | `28 1f e3 06 a3 ff 00 08 08 08 08 08` |
| `7dfd`-`7e6b` |   110 | code | dec | `00 0f 08 00 00 00 00 00 10 0e 00 ff` |
| `7e6b`-`7e99` |    46 | data | tbl | `ff 00 3f 3f 3f 3f 3f 3f 3f 3f 3f 3f` |
| `7e99`-`7ea6` |    13 | code | dec | `0b 3e 00 40 00 00 00 00 00 00 e9 8b` |
| `7ea6`-`7f0e` |   104 | data | tbl | `28 00 e7 00 e3 ff 00 01 02 03 04 05` |
| `7f0e`-`7f18` |    10 | code | dec | `02 60 00 df 01 0c 02 e9 01 02 00 00` |
| `7f18`-`805b` |   323 | data | tbl | `00 00 30 00 00 d3 3f 00 00 7f 02 47` |
| `805b`-`815d` |   258 | code | straddle | `b4 01 84 db 75 1b 80 ff 01 77 16 74` |
| `815d`-`c000` | 16035 | data | fill | `cc cc cc cc cc cc cc cc cc cc cc cc` |

## 4. Code regions

The 120 code regions cover 18034 bytes. They are not laid out as one block:
the ROM interleaves short functions with the data they index, which is why the
region table alternates rather than separating code and data into two halves.
The entry points and the functional islands are:

| Offset | What it is |
| --- | --- |
| `0x01d2`-`0x01f4` | walker over the `0xff`-terminated byte list at `0x108`, one byte per `call 0x5b88` |
| `0x01f4`-`0x021f` | applier for the 12-byte MMIO records at `0x11b` (offset, OR mask, AND-NOT mask) |
| `0x021f`-`0x0277` | clock/PLL programming: table lookups into `0x80000` and `0x80200` |
| `0x0277`-`0x029d` | pulses MMIO `0x04` bit 6 around a vsync wait |
| `0x02a0`-`0x02f0` | panel/clock select: `0x44`, `0x48`, `0x70`, chooses `cs:0x167` or `0x0002045c` |
| `0x0327`-`0x0340` | re-derives the Misc Output byte and writes `0x3c2` |
| `0x056b`-`0x0580` | derives a 2-bit selector from MMIO `0x04` bits 12-13 |
| `0x0660`-`0x0680` | sets bit 8 of a dword addressed through a helper's `ECX` |
| `0x1256`-`0x1317` | the option ROM entry point (`0x03` jumps here) |
| `0x1317`-`0x1429` | SiI9024A register sequence through `call 0x745e` |
| `0x1429`-`0x1440` | hooks INT 10h (`0000:0040` <- `cs:0x96a`) and copies `0x108`-style state |
| `0x14e0`-`0x1504` | `int 0x15` with `ax = 0x7f11`, OEM function 0x11 |
| `0x1504`-`0x1544` | reads clock-table index `0x2f`, then walks string/parameter pairs |
| `0x5b2c`-`0x5b3e` | sequencer index access: write `0x3c4`, read `0x3c5` into `AH` |
| `0x5b3e`-`0x5b88` | clock-table lookup, stride-3 records at `0xaf3`, `0xff`-terminated |
| `0x5b88`-`0x5cec` | per-index sequencer/settings writer used by the `0x01d2` walker |
| `0x5cec`-`0x5d58` | window pitch/format: `0x80014`, `0x80018`, `0x8001c`, `0x80020` |
| `0x5e16`-`0x5e78` | panel/CRT clock bits from Misc Output, then `0x98000` bits 13 and 14 |
| `0x5e79`-`0x5eab` | copies `0x80000` bits 12-13 into `0x80200` bits 12-13 |
| `0x5eac`-`0x5ec0` | PCI BIOS 0xB10D: writes `ecx = 0xa0000` into the ROM BAR |
| `0x5f45`-`0x5f80` | walks four dword entries at `0xcf3`/`0xd4f` against `0xeaa`/`0xeab` |
| `0x5fdf`-`0x6010` | two-table firmware query (`cs:0xce3`, `cs:0xce5`) |
| `0x600a`-`0x6029` | PCI config address builder for `0xcf8`/`0xcfc` |
| `0x6029`-`0x6065` | scans device 0..0x1f, function 0..7 for `0x750126f` |
| `0x6065`-`0x606d` | `xor bl,bl` / `xor bh,bh` / `call 0x6029` |
| `0x606d`-`0x60af` | twelve one-instruction thunks: `in`/`out` al, ax, eax, and two bare `ret` |
| `0x60af`-`0x6151` | PCI BIOS function dispatcher (`ax` selects 0xb10c/0xb10d/...) |
| `0x6151`-`0x6172` | far-callable writer of the CRTC `0x89`/`0x8a` pair |
| `0x6172`-`0x61ad` | vsync/status poll on `0x3da` (`test al,8`), `bx` = retry count |
| `0x61ad`-`0x61df` | PLL update helpers for the panel and CRT paths |
| `0x61c0`-`0x6321` | clock and `MISC_CTRL` helpers (`0x61c0` reads clock index `0x16` into `BL`, `0x61cc` clears `MISC_CTRL` bit 20) |
| `0x6321`-`0x6349` | MMIO read, offset in `EBX` |
| `0x6349`-`0x6380` | MMIO write, offset in `EBX` |
| `0x33c4`-`0x3440` | Misc Output bit 0 selects `0x3b4` or `0x3d4`; CRTC index read/write |
| `0x33d9`-`0x340c` | display unblank: sequencer register 1 bit 5 cleared, `0x80000`/`0x80200` bit 2 set, two trailing retrace waits |
| `0x340d`-`0x3440` | display blank: sequencer register 1 bit 5 set, bit 2 cleared, one leading retrace wait |
| `0x3440`-`0x344c` | CRTC index write and read via `0x33c4`, then the same with a fixed `0x3d4` |
| `0x6bd0`-`0x6c30` | VBE `0x4F` handler: `ax = 0x004f` on success, `0x014f` with carry on failure |
| `0x6f40`-`0x6f9c` | 0x40-byte block read/write with byte-sum checksum (EDID-shaped) |
| `0x745e`-`0x74dc` | SiI9024A register write: `al` = device `0x72`, `bl` = register, `cl` = value |
| `0x7c80`-`0x8080` | mode record table, `0x40`-byte records (see section 5.3) - data, not code |
| `0x805b`-`0x815d` | VBE/FP entry: `mov ah,1`, `o32 call 0xc000:0x6151`, `mov al,0x4f` |

Rows name entry points and functional islands, not region boundaries: several
rows span a short data table the code indexes, and a few begin or end inside a
region. The table in section 3 is authoritative for the exact split; this table
answers "what does the code at this offset do".

## 5. Data regions

The 119 data regions cover 31118 bytes.

### 5.1 Font data (`0x3499`-`0x5b2c`)

The span holds a character generator table of 16-byte cells, 607 cells over
`0x3499`-`0x5b2c`, of which 595 are distinct; the longest run of identical
cells is one, and only five cells are all zero. A stock IBM 8x8, 8x14 or 8x16
font gives zero matches for the usual probe glyphs, so the table is custom. The
cell for character `0x01` (`00 00 7e 81 a5 81 bd 99 81 7e 7e db ff ff c3 e7`)
occurs once, at `0x349f`.

The exact cell origin inside `0x349f`-`0x34a9` is UNDETERMINED (section 12):
the zero-last-byte fraction is 0.654 to 0.656 for every candidate base, with no
peak that identifies one. The bytes are data in the region table either way, so
byte exactness does not depend on the answer.

The tail of the span, `0x5a84`-`0x5b2c`, is the VBE/FP OEM dispatch table: `1d 00`
then 6-byte entries `NN b1 <offset> 60 00 c0` for the thunks at `0x606d`,
`0x6065`, `0x606e`, `0x606f`, `0x607a`, `0x6082`, `0x6089`, `0x6092`, `0x609a`,
`0x60a2`, `0x60ad`, `0x60ae`, then zeros up to the first instruction of the
sequencer helper at `0x5b2c`.

### 5.2 MMIO record table (`0x11b`)

Twelve-byte records terminated by an `0xffffffff` offset:

| Offset | OR mask | AND-NOT mask |
| --- | --- | --- |
| `0x64` | `0x00020407` | `0x0007ffff` |
| `0x68` | `0x00022c5f` | `0x0007ffff` |
| `0x4c` | `0x00000004` | `0x00000004` |
| `0x04` | `0x00000000` | `0x00010000` |
| `0x5c` | `0x00020407` | `0x0007ffff` |
| `0x60` | `0x00020407` | `0x0007ffff` |
| `0x70` | `0x00020451` | `0x0007ffff` |
| `0x74` | `0x00010000` | `0x00010000` |
| `0x44` | `0x00000eff` | `0x0000ffff` |
| `0x48` | `0x00000eff` | `0x0000ffff` |
| `0x98004` | `0x00000000` | `0xffffffff` |
| `0x98008` | `0x00000000` | `0xffffffff` |
| `0x9800c` | `0x00000000` | `0xffffffff` |
| `0x98010` | `0x00000000` | `0xffffffff` |
| `0x98014` | `0x00000000` | `0xffffffff` |

The applier at `0x01f4` does `read`, `not ecx` on the third word, `and eax,
ecx`, `or eax, or_mask`, `write`, so the third column is the mask of bits to
**clear** and the second the bits to **set**, in one pass. MMIO `0x64`, `0x68`
and `0x74` are not named in `docs/specs/REGISTER-MAP.md`; `0x04` is
`MISC_CTRL`, `0x4c` is `POWER_MODE_CTRL`, `0x5c` `PANEL_PLL_CTRL`, `0x60`
`CRT_PLL_CTRL`, `0x70` `MXCLK_PLL_CTRL`, `0x44` `MODE0_GATE` and `0x48`
`MODE1_GATE`. The five `0x98004`-`0x98014` records have
an all-ones clear mask and a zero OR mask, i.e. they write zero to each
register.

### 5.3 Mode record table (`0x7c80`-`0x8080`)

The table is `0x40`-byte records aligned on `0x7c80`. Sixteen record bases fall
in the span: `0x7c80`, `0x7cc0`, `0x7d00`, `0x7d40`, `0x7d80`, `0x7dc0`,
`0x7e00`, `0x7e40`, `0x7e80`, `0x7ec0`, `0x7f00`, `0x7f40`, `0x7f80`,
`0x7fc0`, `0x8000`, `0x8040`. Every row up to `0x7ec0`, and again `0x7f00`,
opens with five zero bytes, a two-byte field, `0f`, `ff`, and then the timing
body. The row at `0x7c80`:

```
00 00 00 00 00 00 05 0f ff 50 18 10 00 10 00 03 00 02 66 5f 4f 50 82 55
81 09 3e 00 52 0e 0f 00 00 00 00 e9 8b df 28 1f e3 06 a3 ff 00 08 08 08
08 08 08 08 10 18 18 18 18 18 18 18 0e 00 0f 08
```

and the row at `0x7dc0`, which carries the ascending mask table
`01 02 03 04 05 14 07 38 39 3a 3b 3c 3d 3e 3f`:

```
00 00 00 00 00 10 0e 00 ff 50 18 10 00 10 00 03 00 02 67 5f 4f 50 82 55
81 bf 1f 00 4f 0e 0f 00 00 00 00 9c 8e 8f 28 1f 96 b9 a3 ff 00 01 02 03
04 05 14 07 38 39 3a 3b 3c 3d 3e 3f 0c 00 0f 08
```

Two consumers establish that this is the mode table. `0xc17e8` selects a row
pointer by mode number - `cmp bl,0x8` / `jne` / `mov si,0x7eec`, and
`cmp bl,0x7` / `jne` / `mov si,0x7eac`, i.e. row base plus the interior offset
`0x2c` - then steps `add si,0x10` to the next 16-byte sub-block when
`es:0x49` bit 3 is set. `0xc334a` replays the DAC and sequencer from
`mov si,0x7dce` with `lods al,BYTE PTR ds:[si]` / `out dx,al`.

The span is not a clean table end to end: the region table slices it into
alternating code and data regions (`7dfd`-`7e6b`, `7e99`-`7ea6`, `7f0e`-`7f18`
are marked code). Those slices are an artifact of the partition finding a clean
decode from each slice's first byte; no `call` or `jmp` in the image targets
them, and their bytes have the shape of timing data, so the classification is
carried unchanged rather than guessed at.

The area ends with an 18-byte parameter block at `0x8049`:

```
12 00 36 00 8a 00 08 00 ff ff 0c c0 0a 00 04 00 ff ff
```

whose end `0x805b` is exactly where the VBE/FP entry code begins (`b4 01` =
`mov ah,0x1`). Which byte inside a record is which timing field is
UNDETERMINED (section 12); the stride, the base and the extent are measured.

### 5.4 Other tables

| Offset | Contents |
| --- | --- |
| `0x108` | `0xff`-terminated sequencer/CRTC index list: `00 ff 40 02 01 00 02 00 0b 00 30 01 16 03 2f 01 06 00 ff` |
| `0x160` | panel words: `ff 07 00 70 00 00 00 51 04 02 00 ...`; `0x167` is the `0x00020451` word the panel path loads |
| `0xaf3` | clock table, stride 3: `[index, CRTC register, shift|mask]`, `0xff`-terminated, 140 bytes |
| `0xcf3`-`0xd4f` | dword pairs walked by the `0x5f45` helper |
| `0xce3`, `0xce5` | two words returned by the `0x5fdf` query |
| `0x6caa` | `VBE/` fragment of a longer inline string |
| `0x815d`-`0xc000` | 16035 bytes of `0xcc` fill |

## 6. What the ROM does

`vbios-re/model/` holds a C model of the behaviour the assembly shows. It is a
reading aid, not a driver component: nothing in `src/` includes it and it is not
built by the kernel module. Each function names the ROM offset it comes from
and the register it touches.

### 6.1 Entry point (`0x1256`)

Save state, find the device, hand the BAR to legacy VGA space, unprotect the
sequencer, then run the subsystem initialisers in order:

| Step | Call | Effect |
| --- | --- | --- |
| 1 | `0x6065` then `0x60af` with `ax = 0xb10c`, `di = 4`, `cx = 4`/`6`/`0x1f` | PCI BIOS: write dword `0xb10c` into config space of device 0, register 4, for three register numbers |
| 2 | `0x0660` | set bit 8 of a dword reached through the PCI helper |
| 3 | `0x5eac` | PCI BIOS 0xB10D: `ecx = 0xa0000` into the ROM BAR, i.e. claim legacy VGA |
| 4 | `0x067e` | companion of step 2 |
| 5 | `0x0327` | rewrite Misc Output `0x3c2`, then CRTC `0x96` |
| 6 | `0x1429` | hook INT 10h vector `0000:0040` to `cs:0x96a`, copy state to `0000:0108` |
| 7 | `0x056b` | 2-bit selector from MMIO `0x04` bits 12-13 |
| 8 | `0x1317` | SiI9024A bring-up (section 6.6) |
| 9 | `0x14e0` | `int 0x15`, `ax = 0x7f11` |
| 10 | `0x5ef9`, `0x1504` | panel/clock and mode bring-up |
| 11 | `0x289e` in a loop `si = 8`, `bx = 0xf8` | load the custom font, one `ax = 0x1010` call per glyph |

The sequence ends with `int 0x15`, `ax = 0x7f0f` (VBE/FP OEM), then restores
`es`, `popad`, `pop ds`, `leave`, `retf`.

### 6.2 Clock and PLL (`0x021f`-`0x0277`)

The clock table at `0xaf3` maps an index to a CRTC register and a bit field. The
PLL path reads index 2 and index 6:

* MMIO `0x80000` (`PANEL_DISPLAY_CTRL` in `docs/specs/REGISTER-MAP.md`):
  `and eax, 0xfff3bfff` clears bits 18-19; the value for index 2 is shifted left
  18 and ORed in.
* The same register's low word: the value for index 6 is shifted left 14 and
  ORed in.
* MMIO `0x80200` (`CRT_DISPLAY_CTRL`): `and eax, 0xffffbfff` clears bit 14; the
  index 6 value is shifted left 14 and ORed in.

After the fields are written the code pulses MMIO `0x04` bit 6 (`and ax,0xffbf`
then `or ax,0x40`) with a `0x6172` vsync wait between the two writes, which is
the PLL relock handshake.

### 6.3 Panel and clock select (`0x02a0`)

1. Read MMIO `0x44` (`MODE0_GATE`), keep the low 12 bits.
2. Test bit 0: `0x3263` reads Graphics Controller register 6 through `0x3ce` and
   returns ZF from bit 0 of the high byte (`test ah, 1`).
3. When bit 0 is clear, OR `0x5000` (bit 14) into the value.
4. Write MMIO `0x44`, then mirror the same value into MMIO `0x48`
   (`MODE1_GATE`).
5. Read MMIO `0x70` (`MXCLK_PLL_CTRL`), `and eax, 0xfff80000` - clear bits 0-18.
6. Re-test the same GC6 bit 0: when it is clear, OR `0x0002045c`; when it is
   set, load the 4-byte word at `cs:0x167`, which is `0x00020451`.
7. Write MMIO `0x70`, then `call 0x0277`.

The two constants differ in bit 2 and bit 3: `0x5c` = `0101 1100`, `0x51` =
`0101 0001`. The ROM therefore selects a different MXCLK divider field when it
detects a panel. The exact field meaning is in
`docs/specs/REGISTER-MAP.md` under `MXCLK_PLL_CTRL`; the ROM's choice of two
fixed words, rather than a computed PLL value, is a divergence from the driver
(section 13).

The same GC6 bit 0 gates the `0x5000` OR in step 3, so the two effects always
agree with each other. Which physical condition the bit reports (flat panel
attached, or a strap) is UNDETERMINED; the model calls it `rom_is_panel()` and
keeps the polarity the ROM uses.

### 6.4 Display blank and unblank (`0x340d`, `0x33d9`)

Blank (`0x340d`), the routine the image actually calls:

1. `mov bx,1`, `call 0x61ad` - wait one vsync period. `0x6172` polls `0x3da`
   (or `0x3ba`) for bit 3 three times and re-arms a 0x300-iteration delay when
   the poll spins out, so the wait is bounded rather than a tight spin.
2. `mov al,1`, `call 0x5b2c` - read sequencer register 1 into `AH`.
3. `or ah, 0x20` - set bit 5. `out dx, ax` writes both the index (1) and the
   value, because `0x5b2c` leaves `dx = 0x3c4`.
4. MMIO `0x80000`: `and al, 0xfb` - clear bit 2.
5. MMIO `0x80200`: `and al, 0xfb` - clear bit 2.

Unblank (`0x33d9`) is the mirror image: `and ah, 0xdf` clears sequencer
register 1 bit 5, `or al, 4` sets bit 2 of `0x80000` and `0x80200`, and
`mov bx, 2 / call 0x6172` waits out two vsync periods after the change.

So the ROM treats sequencer register 1 bit 5 as the screen-off bit and bit 2 of
`PANEL_DISPLAY_CTRL`/`CRT_DISPLAY_CTRL` as the second half of the same latch,
driven in opposite directions by the two routines. `src/ddk750_reg.h:567`
names bit 2 `DISPLAY_CTRL_PLANE` and `:561` names bit 8 `DISPLAY_CTRL_TIMING`.

Reachability is asymmetric: `0x340d` is called from `0x042f` and `0x0441`
(both inside the mode-set routine at `0x042c`, once before and once after the
window and clock programming), from `0x0aea`, `0x14ef`, `0x2d33` and `0x698a`.
No direct call or jump anywhere in the image targets `0x33d9`, and the byte
pair `d9 33` does not occur, so no table holds a far pointer to it either.
`0x33d9` is therefore present in the image but not reached by it; the unblank
in the mode path comes from the mode's own sequencer values, which `0x5b88`
and `0x334a` replay and which overwrite register 1 bit 5 themselves. Whether
the SM750 VGA core inverts bit 5 relative to a standard VGA is UNDETERMINED
(section 12).

The driver instead drives the display-enable bits inside
`PANEL_DISPLAY_CTRL`/`CRT_DISPLAY_CTRL` directly and never touches sequencer
register 1 (section 13).

### 6.5 Window, clock bits and panel power (`0x5cec`, `0x5e16`, `0x5e79`)

`0x5cec` first calls `0x3224`, which reads the BIOS video mode byte at
`0000:0449`, looks it up in the 56-record table at `0x639b`, masks the result
with `0x0f` and compares it with 7; when the mode is below 7 the routine
returns without touching anything (`jb 0x5d54`).

Otherwise it takes the 6-byte-stride tables at file offsets `0xc47` and `0xc49`
(one 16-bit value plus four bytes of padding per entry), indexed by bits 16-19
of `EBX` through `0x3476` (`shr ebx, 0x10` / `and bx, 0x0f`), builds
`ecx = (a << 16) | b - 0x10001` with `a` from `0xc49` and `b` from `0xc47`, and
programs four consecutive MMIO registers:

| Register | Value |
| --- | --- |
| `0x80014` | `(ecx << 16) & 0x0fff0000` |
| `0x80018` | `ecx & 0x0fff0000` |
| `0x8001c` | 0 |
| `0x80020` | `ecx & 0x07ff07ff` |

`0x80014`-`0x80020` are `PANEL_WINDOW_WIDTH`, `PANEL_WINDOW_HEIGHT`,
`PANEL_PLANE_TL`, `PANEL_PLANE_BR` in `docs/specs/REGISTER-MAP.md`, so the pair
is written as pitch in the high half and extent in the low half. For table
index 0 the words are `0x0140` at `0xc47` and `0x00c8` at `0xc49`, giving a
width field of `0x13f` (320-1) and a height field of `0x0c7` (200-1); which of
the two tables is horizontal by intent is UNDETERMINED, so the model keeps the
register names and the call order rather than renaming the fields.

`0x5e16` reads the Misc Output byte once (`in al, 0x3cc`, `and al, 0xc0`) and
uses the same two bits three times: bits 6-7 become bits 12-13 of both
`0x80000` and `0x80200` (`shr cl, 2` then `or ah, cl` on each, after clearing
`0xffffcfff`), and then MMIO `0x98000`: bit 14 takes Misc bit 7 (`shr cl, 1` /
`and cl, 0x40`) and bit 13 takes the inverse of Misc bit 5 (`not cx` /
`and cl, 0x20`), both after clearing `0xffffbfff` and `0xffffdfff`
respectively. `0x98000` is not named in `docs/specs/REGISTER-MAP.md`; the ROM
reads it, changes only those two bits and writes it back, which is the shape of
a panel power and backlight enable pair.

`0x5e79` is gated by clock-table index `0x12` bit 0 (`0x6147`): when the bit is
set - or the lookup fails - it calls `0x5e16` instead; otherwise it copies MMIO
`0x80000` bits 12-13 into MMIO `0x80200` bits 12-13, i.e. it gives the CRT path
the same clock-source selection the panel path has.

### 6.6 SiI9024A bring-up (`0x1317`)

`0x70c3` prepares the bus: it clears bits 12-13 of MMIO `0x08`, then ORs
`0x40` into `MODE0_GATE` and `MODE1_GATE` (`0x44`/`0x48`). Then the ROM writes
30 registers through `0x745e` (`al` = device address `0x72`, `bl` = register,
`cl` = value), each as its own I2C transaction:

| Register | Value | Register | Value | Register | Value |
| --- | --- | --- | --- | --- | --- |
| `0x82` | `0x25` | `0x3c` | `0x01` | `0x06` | `0xee` |
| `0x7c` | `0x14` | `0x08` | `0x70` | `0x07` | `0x02` |
| `0xf5` | `0x00` | `0x00` | `0x01` | `0x08` | `0x70` |
| `0xc7` | `0x00` | `0x01` | `0x1d` | `0x1a` | `0x11` |
| `0xbc` | `0x01` | `0x02` | `0x70` | `0x09` | `0x00` |
| `0xbd` | `0x03` | `0x03` | `0x17` | `0x0a` | `0x10` |
| `0xbc` | `0x01` | `0x04` | `0x72` | `0x19` | `0x00` |
| `0xbd` | `0x02` | `0x05` | `0x06` | `0x1a` | `0x10` |
| | | | | `0x60` | `0x00` |
| | | | | `0x1e` | `0x00` |
| | | | | `0x26` | `0x30` |
| | | | | `0x63` | `0x00` |
| | | | | `0x0b` | `0x00` |
| | | | | `0x1a` | `0x40` |

The order is the ROM's order and it matters: `0xc7` = `0x00` leaves the TPI
reset-request state, `0xbc`/`0xbd` select an indexed page twice with different
page numbers, the `0x00`-`0x08` block is the TPI video setup, `0x1a` is written
three times (`0x11`, `0x10`, `0x40`) and `0x08` twice with the same value
`0x70`. No deduplication is legitimate here, which is why
`vbios-re/model/sii9024a.c` keeps all 30 pairs verbatim.

The transport is a bit-banged I2C bus, not the SM750 I2C engine: SDA is driven
by `0xc728b` and SCL by `0xc72d0`, each through an MMIO register, with the
delay loop at `0xc7028`, the start/stop generators at `0xc711c`/`0xc7140`, the
ACK poll at `0xc7400` and the retry counter inside `0xc74dc`. Each of the 30
registers gets its own START/address/register/value/STOP sequence, so a driver
that holds the bus open across a register/value pair is not doing what the ROM
does.

`docs/specs/REGISTER-MAP.md` names `0x3c` (interrupt enable), `0x60` (sync
configuration) and the `0xbc`/`0xbd` index pair; the remaining registers are
written with no name in either the ROM or the driver.

`0x6f40`-`0x6f9c` reads and writes 0x40-byte blocks with a byte-sum checksum,
which is the EDID access shape, but the ROM contains no `EDID` string and no
caller passes a monitor address, so whether it ever reads a real EDID block is
UNDETERMINED (section 12).

Correction 2026-11-19 (T27): the "no caller" half of that sentence is wrong.
`0x6f44` is called from `0x6d91` inside `0x6d7d`, which reads one byte,
multiplies it by `0x80`, and then calls the accessor; the sibling routine
`0x6e9e` does pass monitor addresses (`0xa1`, `0xa3`, `0xa7`, `0xa9`, i.e.
`0x50`/`0x51`/`0x53`/`0x54` shifted left once with the read bit set) before
reading 0x80-byte blocks. Section 12 item 8 records the answer; the transcript
is `docs/evidence/vbios-re/07-undetermined-triage.txt`.

### 6.7 Mode selection (`0x1504`)

`0x1504` reads clock-table index `0x2f`; if the value is 1 it jumps to `0x1543`,
otherwise it sets `es = cs`, loads `cx = cs:0xe1`, and walks string/parameter
pairs with `bp` set to `0x5b` (the OEM string offset) and then `0x36` (the
version string offset). The walk drives `0x1544`, the per-record string applier.

### 6.8 VBE and OEM services (`0x6bd0`, `0x805b`)

`0x6bd0` implements VBE function `0x4F`: success returns `ax = 0x004f` with
carry clear, failure returns `ax = 0x014f` with carry set, and the mode
information buffer is at segment `0xc804`. `0x805b` is the VBE/FP entry the
far-pointer table at `0x5a84` dispatches to: `mov ah,1`, `test bl,bl`,
`cmp bh,1`, then `o32 call 0xc000:0x6151` - the CRT `0x89`/`0x8a` pair writer -
and finally `mov al,0x4f`, `ret`.

## 7. Re-encoding

The reconstruction source is generated, not hand-written: `reencode.py` reads
the region table, disassembles each code region, turns each instruction into a
nasm spelling, verifies that spelling by assembling it alone at its own address,
and only then emits it.

### 7.1 Why 16-bit assembly and not C

The ROM is 16-bit real-mode code. Neither host compiler can emit those bytes:

| Compiler | Invocation | `push %ebp` | `int g(int,int)` argument load |
| --- | --- | --- | --- |
| gcc 15.3.1 | `/usr/bin/gcc -m16 -O2` | `66 55` | `67 66 8b 44 24` |
| clang 21.1.8 | `clang -m16 -O2` | `66 55` | `67 66 8b 44 24` |

Both emit a 32-bit operand-size prefix (`66`) where the ROM has none, and an
address-size prefix (`67`) on every stack access. Neither prefix is optional and
neither can be suppressed, so a C compiler cannot produce a byte-exact 16-bit
image. The transcript is `docs/evidence/vbios-re/04-toolchain.txt`.

The emitter is therefore nasm:

```sh
nasm -f bin -o reencode.bin reencode.asm
```

with `bits 16` and `org 0` in the source, and every branch pinned by its
encoding width (`je short` / `je near`, bare `loop` / `jcxz` which take no size
keyword).

### 7.2 Coverage

| Measure | Value |
| --- | --- |
| Bytes emitted from mnemonics | 17973 |
| Code bytes in the region table | 18034 |
| Coverage | 99.66 percent |
| Instruction slots | 7734 |
| Slots emitted exactly | 6879 |
| Slots reaching the same bytes after a documented canonicalisation | 838 |
| Slots carried as `db` | 17 (61 bytes) |

The metric the plan sets is bytes emitted from mnemonics divided by total code
bytes, floor 85 percent. The build computes it and fails below the floor.

The 838 canonicalised slots are instructions where the vendor assembler chose a
different but equivalent encoding, and nasm's choice is the other one:

* **Direction of a register-to-register ALU operation.** The vendor used
  `8a/03/0b/13/1b/23/2b/33/3b/85/86/87` (register in `reg`, memory or register
  in `r/m`); nasm emits `88/01/09/11/19/21/29/31/39/84/85`. The rewrite swaps
  the two `modrm` fields when `modrm >> 6 == 3`, which leaves the meaning
  identical.
* **Prefix order.** The vendor put `66` before a segment override; nasm puts the
  segment override first. The rewrite reorders to Intel's canonical `67, 66,
  F3/F2/F0, segment` order.

Both rewrites are gated on the assembled bytes being length-identical and
decode-identical to the ROM bytes for that slot, and the whole-image objdump
decode comparison (section 9) is an independent check over every code byte: if a
rewrite changed meaning, the two disassemblies would differ.

### 7.3 The 17 residual `db` slots

Two reasons, and nothing else:

| Offset | Bytes | Instruction | Why data |
| --- | --- | --- | --- |
| `0x1bca` | `89 90 10 00` | `mov word [bx+si+0x10], dx` | vendor disp16 form; nasm emits the disp8 form |
| `0x1c01` | `8b 97 10 00` | `mov dx, word [bx+0x10]` | vendor disp16 form |
| `0x1c5b` | `8b 95 10 00` | `mov dx, word [di+0x10]` | vendor disp16 form |
| `0x209f` | `8b 94 10 00` | `mov dx, word [si+0x10]` | vendor disp16 form |
| `0x2140` | `8b 97 10 00` | `mov dx, word [bx+0x10]` | vendor disp16 form |
| `0x25cc` | `8b 95 10 00` | `mov dx, word [di+0x10]` | vendor disp16 form |
| `0x2056` | `22 af 22 00` | `and ch, byte [bx+0x22]` | vendor disp16 form |
| `0x51f` | `0f 21 05` | `mov ebp, dr0` | nasm encodes `dr0` as `0f 21 c5`; the ROM uses modrm `05` |
| `0x2a38` | `df be 06 00` | `fistp qword [bp+0x6]` | vendor disp16 form |
| `0x2edb` | `db bb 5f 00` | `fstp tbyte [bp+di+0x5f]` | vendor disp16 form |
| `0x3463` | `c0 b9 19 00 e8` | `sar byte [bx+di+0x19], 0xe8` | vendor disp16 form, imm8 shift |
| `0x8ca` | `67 9b` | `addr32 fwait` | an address-size prefix nasm rejects in 16-bit mode |
| `0x2ed7` | `67 df e8` | `addr32 fucomi st, st(0)` | same |
| `0x64e1` | `00 60 00` | `add byte [bx+si+0x0], ah` | vendor redundant disp8 |
| `0x66f5` | `ff c7` | `inc di` | vendor uses the `ff /0` form, nasm the one-byte `47` |
| `0x7e5a` | `3e 00 40 00` | `add byte ds:[bx+si+0x0], al` | vendor redundant disp8 with a segment override |
| `0x7f0e` | `02 60 00` | `add ah, byte [bx+si+0x0]` | vendor redundant disp8 |

All 17 are one instruction in otherwise code-classified regions. The bytes are
carried as `db` with a comment naming the instruction, so the source still
records what the ROM does; the coverage loss is 61 of 18034 code bytes.

Every other `db` run in the source is inside a data region, where `db` is the
correct emission and the bytes are the region's own contents.

## 8. Computed fields

Three header fields are computed from the region table and the rebuilt bytes,
never copied from the capture, and the build fails when a computed value differs
from the captured one:

| Field | Offset | Computation | Captured |
| --- | --- | --- | --- |
| image size in 512-byte blocks | `0x02` | region-table total / 512 | `0x60` |
| PCIR image length | `0x2c` | region-table total / 512, low byte then high byte | `0x0060` |
| checksum byte | `0x34` | `(-sum(all other bytes)) mod 256` over the rebuilt image | `0x6b` |

The checksum is solved after canonicalisation, because the canonicalisation pass
rewrites bytes and the sum must be taken over the final image. The verifier also
asserts `sum(all 49152 bytes) == 0 mod 256` as a separate check, so a wrong
checksum cannot hide behind a wrong size.

## 9. Decode equality

The verifier disassembles every code region of both images with

```sh
objdump -D -b binary -m i8086 -M intel --adjust-vma=0xc0000 <image>
```

and compares instruction by instruction for the 7734 slots. The transcript in
`docs/evidence/vbios-re/03-decode-equality.txt` runs the same command over both
whole images, strips objdump's two-line banner, and diffs: 30283 lines each, no
difference, exit 0. Section 3 explains the one region (`0x805b`-`0x815d`) where
objdump's own text is wrong because of the `66 9a` wrap; the generator handles
that slot separately, and both images produce the same objdump text for it
because both contain the same bytes.

## 10. Reproduction

Two opt-in targets, both recomputing from the captured image:

```sh
make vbios-re      # rebuild the ROM and compare it byte for byte
make vbios-trace   # execute both images and compare their instruction traces
```

Neither is a dependency of `check`, for the same reason `static` is not: the
captured ROM is vendor material and is not in the tree. When the image is
absent both harnesses print `SKIP: captured ROM not present at <path>` and exit
77, which the targets turn into a successful skip (`make` exit 0). `make check`
therefore stays green on a checkout without the image.

### 10.1 Rebuild and byte exactness

`make vbios-re` runs `tools/vbios-re/check.sh` -> `reencode.py`, writing the
rebuilt image and the generated source under `/mega/tmp/sm750/t17/reconstruct/`.
It needs only `python3`, `nasm` and `objdump`. The image path can be overridden
with `VBIOS_ROM` and the output directory with `VBIOS_RE_OUT`.

To reproduce the evidence files:

```sh
python3 tools/vbios-re/reencode.py --out /mega/tmp/sm750/t17/reconstruct
cmp -l /mega/tmp/sm750/vbios-01-00-0.bin /mega/tmp/sm750/t17/reconstruct/reencode.bin
objdump -D -b binary -m i8086 -M intel --adjust-vma=0xc0000 <image>   # both
```

### 10.2 Execution trace

Section 9 compares the two images as text; this compares them as programs. Both
images are executed from one fixed reset state and the resulting instruction
streams are diffed step by step. On a byte-identical pair the result is
necessarily identical, so what the trace adds is an independent check on the
whole pipeline - region model, generated assembly, `nasm`, linked binary - that
fails if any stage ever emits code that assembles but does not run the same
way, and it exercises the entry path the system BIOS takes instead of the
byte order of a file.

```sh
make vbios-trace                      # or: ./tools/vbios-re/trace.sh
VBIOS_ROM=/path/to/image ./tools/vbios-re/trace.sh
VBIOS_TRACE_BOUND=5000 ./tools/vbios-re/trace.sh      # more steps
VBIOS_TRACE_OUT=/mega/tmp/sm750/trace2 ./tools/vbios-re/trace.sh
```

`trace.sh` checks the image, `qemu-system-i386`, `gdb`, `python3` and capstone
in that order and skips (exit 77) with a `SKIP:` line when one is missing. It
then regenerates the rebuilt image with `reencode.py --quiet` into
`$VBIOS_TRACE_OUT/reconstruct/` so the comparison target is what this tree
produces, not a stale scratch file, and runs `tools/vbios-re/trace.py`. That
helper needs `qemu-system-i386`, `gdb`, capstone and unicorn; capstone and
unicorn are installed under `/mega/tmp/sm750/pylib`, which the script prepends
to `PYTHONPATH` (`VBIOS_PYLIB` overrides it). A run takes about a minute, most
of it in the rebuild.

Both engines start from the same state, which is the state a BIOS would hand
the image to at linear `0xC0000`:

| Register | Value |
| --- | --- |
| `CS:IP` | `0xC000:0x1256` (image offset `0x1256`, the `e9 50 12` target) |
| `SS:SP` | `0x0000:0x7C00` |
| `DS`, `ES`, `FS`, `GS` | `0` |
| `EFLAGS` | `0x2` |

Engine `qemu` is the real CPU. The image cannot be loaded with `-option-rom`
(section 1: QEMU's loader requires `55 AA` at the end of a 512-byte block and
this image has none), so it goes through QEMU's generic loader and is stepped
through the gdb stub:

```sh
qemu-system-i386 -M pc -m 8 -S -gdb tcp:127.0.0.1:47127 \
  -device loader,file=<image>,addr=0xc0000,force-raw=on \
  -display none -monitor none -serial none -no-reboot -no-shutdown
gdb -q -batch -x <out>/qemu-captured.gdb
```

The generated command file sets `$cs` and `$eip` (real target registers on this
architecture, so the `set` moves the CPU; the transcript shows gdb arriving at
`0x0000fff0` and the trace starting at `0xc000:0x1256`), then loops:

```gdb
set $n = 0
while $n < 2000
  printf "P %d %04x %04x\n", $n, ($cs), ($eip)
  x/16xb (($cs << 4) + $eip)
  si
  set $n = $n + 1
  if ($cs) != 0xc000
    printf "FAR %04x %04x\n", ($cs), ($eip)
    loop_break
  end
end
```

The port is fixed at 47127 and the run aborts with `FATAL: gdb port 47127 is
already in use; pass --port N` rather than picking another one silently.
`VBIOS_TRACE_PORT` overrides it.

Engine `unicorn` maps the image at `0xC0000` over 1 MiB of RAM and hooks
`UC_HOOK_CODE` for the instruction stream and `UC_HOOK_INSN` for `IN`/`OUT`, so
port accesses are recorded with port, direction, width and value. Both engines
decode the bytes they see with capstone in 16-bit mode, so the traces are the
same format:

```text
000004 c000:125e lin=0c125e bytes=e8044e               call     0xc6065                  branch=0x0c6065
000005 c000:6065 lin=0c6065 bytes=32db                 xor      bl, bl                   branch=-
000021 io   out port=0cf8 size=4 value=0x80000000
000024 io   in port=0cfc size=4 value=0x0
```

Each run writes `<engine>-<captured|rebuilt>.trace` (the header carries the
engine, image path, sha256, bound and stop reason), a matching `.json` summary,
and for the qemu engine the `.gdb` command file, the gdb transcript and the
emulator log, whose first line is the exact `qemu-system-i386` command line.

Stopping is bounded and recorded, never silent:

* `bound` - the step limit was reached (`VBIOS_TRACE_BOUND`, default 2000).
* `far-transfer` - control left `CS=0xC000`, i.e. outside linear
  `0xC0000`-`0xCFFFF`, for example a jump through an uninitialised interrupt
  vector.
* `loop` - a repeated-PC cycle of at most 32 instructions executed 64 times,
  which is a hang, not progress. Both stop rules are self-tested against
  synthetic images (a `jmp far 0x1000:0` and a `jmp $`), see
  `docs/evidence/vbios-re/06-trace-stops.txt`.

A suffix of steps that introduces no new PC is reported separately as `no
progress: the N steps after step K executed no new PC (0x...)`, because that is
a fact about the run and not proof of a loop.

The comparison mode runs the captured image and the rebuilt image through the
same engine from the same state and diffs the whole step list, then the port
events, and prints the first divergence with two lines of context on each side
plus the two differing lines, exiting non-zero. It does not shorten the bound to
make a difference go away: the transcript
`docs/evidence/vbios-re/07-trace-divergence.txt` flips one byte of the image
(`0x125a`: `push ds` -> `push es`) and the tool reports `DIVERGED at step 1` for
both engines and exits 1.

Result on this host, both engines, 2000 steps:

| Engine | Captured image | Rebuilt image | Port writes |
| --- | --- | --- | --- |
| qemu | 2000 steps, `stop=bound`, entered `0xC6065` at step 5 | same | not observable |
| unicorn | 2000 steps, `stop=bound`, entered `0xC6065` at step 5 | same | 99 OUT, 99 IN |

`compare qemu MATCH: 2000 steps identical, 0 port events identical` and
`compare unicorn MATCH: 2000 steps identical, 198 port events identical`, then
`VERDICT: PASS`, exit 0. The 198 events are the PCI configuration accesses of
the scan at section 6.6: `out 0xcf8` with `0x80000000`, `0x80000800`, ... and
`in 0xcfc` returning 0.

What the trace does **not** show:

* There is no SM750 in either machine. `0xcfc` reads what the emulated chipset
  returns, not what this card would return, so the scan for `0x750126f` never
  matches and the mode-set path behind it is never reached. Nothing here is
  evidence about hardware behaviour; it is a CPU-level equivalence check.
* The gdb stub cannot observe I/O, so the qemu engine reports `ports=n/a` and
  port equivalence rests on the unicorn engine. The instruction stream, which
  is the part both engines see, is identical between them for all 2000 steps,
  which is what licenses using the cheaper engine for the side effects.
* Unicorn's `IN` returns 0 and it has no interrupt controller; the traced path
  issues no `INT` and no MMIO access, so neither limitation is exercised here.
  A longer trace would stop being meaningful rather than fail loudly, because
  the ROM is waiting for a device that is not there.

Evidence: `docs/evidence/vbios-re/05-execution-trace.txt` (the harness run, the
two engines, the trace excerpt and the comparison) and
`docs/evidence/vbios-re/06-trace-stops.txt` (skip paths, port collision, both
stop rules, divergence detection).

## 11. Provenance

The reconstruction is **not** committed:

* the generated `reencode.asm` and `reencode.bin` are vendor-derived executable
  material and stay under `/mega/tmp/sm750/t17/reconstruct/`;
* `tools/vbios-re/` and `vbios-re/model/` hold the region table, the generator,
  the verifier and the C reading aid - my own code, no vendor bytes beyond the
  short instruction excerpts this document quotes;
* nothing in `tools/vbios-re/` or `vbios-re/model/` is on the module's build
  path, and neither is listed in `packaging/sm750hdmifb.spec` or reached by
  `build-package.sh`.

The alternative - committing the generated source and the rebuilt binary so the
rebuild is self-contained - was rejected: `build-package.sh` tars
`git ls-files`, so a committed reconstruction would ship in the source package
and the RPM payload, `tests/audit-release.sh` rejects any `*.bin`/`*.rom` in the
payload, and the ROM's own copyright banner matches the phrase that script
grep-fails. `docs/PROVENANCE.md` records the decision and this reason.

## 12. UNDETERMINED

These are measured facts with no answer, and they stay UNDETERMINED rather than
guessed. Triage state added 2026-11-19 (T27): each item now carries the evidence
that supports it and whether the ROM image alone can settle the question. "ROM
alone: yes" means bytes or instructions in `vbios.bin` fix the answer; "no"
means the image bounds the question but cannot answer it (vendor intent, an
attached sink, a datasheet name). The transcript of the checks below is
`docs/evidence/vbios-re/07-undetermined-triage.txt`.

1. **PCIR checksum span.** Byte `0x33` is `0x00` and `sum(0x1c..0x33) = 1`, so
   the structure does not self-validate. The only convention that validates is
   the whole-image sum with the complement at `0x34`. Which span the vendor
   intended `0x34` to cover is unknown.
   - Evidence: section 2.2, and `docs/evidence/vbios-re/02-bitexact.txt` (the
     rebuild reproduces byte `0x34` exactly, so the value is data, not a model
     choice).
   - ROM alone: no. The image says which sum evaluates to zero; it says nothing
     about which span the vendor meant, and no header field or string names it.
2. **Header words `0x0a` = `0x00d9` and `0x0c` = `0x006c`.** Both are below the
   image size and neither is referenced by any decoded instruction.
   - Evidence: section 2.1 header table; section 3.1 classifies the bytes as
     header data and no decoded instruction reads them.
   - ROM alone: partly. That they are unreferenced is decidable by an
     image-wide xref and was decided; what they were meant to hold is not, and
     nothing in the image is a candidate consumer.
3. **VBE mode-list pointer.** `c000:7aac` holds four word pointers
   (`0x7adf`, `0x7ad7`, `0x7acf`, `0x7ac9`) then zeros - not a VBE mode list,
   and no `0xffff` terminator anywhere.
   - Evidence: section 2.3 (bytes `df 7a d7 7a cf 7a c9 7a` then zeros at
     `0x7aac`), re-read 2026-11-19; section 5.4 for what the four pointers
     reach.
   - ROM alone: partly. The stored words and the missing terminator are
     decidable; why the vendor wrote four pointers there is not, and no decoded
     consumer reconstructs a VBE mode list from them.
4. **VBE total-memory field.** `0x91` is the `S` of the ASCII string `SM750`, so
   no memory size can be read there.
   - Evidence: section 2.4 string table (`SM750` starts at `0x91`; byte value
     `0x53`), section 8 for the memory figure the ROM actually derives.
   - ROM alone: yes, for the negative result: VBE 2.0 field `0x91` is occupied
     by a string in this image, so a caller reading it gets `0x53`, not a MiB
     count. Which value the vendor meant to publish is not recoverable from
     that byte, and no other byte is labelled as the VBE memory field.
5. **Font cell origin.** Inside `0x349f`-`0x34a9` no candidate base has a
   distinctive zero-last-byte fraction.
   - Evidence: section 5.1 (cell for `0x01` at `0x349f`, zero-last-byte
     fractions 0.654 to 0.656 for every candidate base).
   - ROM alone: no. The table is a flat run of 16-byte cells with no delimiter
     at the origin; picking a base needs a consumer that sets the font pointer
     (INT 43h or the like), which the decode has not located, so no evidence
     path in this repository settles it.
6. **Mode record field names.** The `0x40` stride from `0x7c80` and the extent
   are measured; which byte is which timing field is not established.
   - Evidence: section 5.3; `vbios-re/model/mode_table.c` (stride from
     `shl bx,0x6` at `0xc344c`, row = base + mode * `0x40`, 16 rows tiling
     `0x7c80`-`0x8080`, consumer `0xc334a` replaying 16 CRTC bytes from
     `0x7dce`), which states explicitly that it carries the accessors and the
     layout, not the field semantics.
   - ROM alone: no. The bytes are fixed but field names need the consumer's
     intent. The T25 harness does not supply it either: every run starts at
     `CS=0xc000 IP=0x1256` and stops at `bound 2000`
     (`docs/evidence/vbios-re/05-execution-trace.txt`), before the replay
     consumer at `0xc334a` executes. `VBIOS_TRACE_BOUND`
     (`tools/vbios-re/trace.sh:21`) is the only in-repo lever to reach it, and
     no run with a raised bound exists yet.
7. **`0x98000` meaning.** Read-modify-write of bits 13 and 14 only, shaped like
   panel power and backlight; the register has no name in
   `docs/specs/REGISTER-MAP.md`.
   - Evidence: section 6.5 (`0x5e16`, `0x5e79`); no name in
     `docs/specs/REGISTER-MAP.md` or `src/ddk750_reg.h`.
   - ROM alone: no. The operations (bits 13 and 14, read-modify-write) are
     decidable; what the bits drive needs the pinout or a datasheet, and the
     image never names a pin.
8. **Whether the 0x40-byte checksummed block accessor at `0x6f40` ever reads a
   real EDID.** The shape matches; the earlier decode found no caller and no
   `EDID` string.
   - ANSWERED 2026-11-19 (T27) for the structural half, and the earlier "no
     caller" statement was wrong: a caller exists. A near call at `0x6d91` (`e8 b0 01`) enters
     `0x6f44`, both inside code regions (`0x6cae`-`0x6d9a` and
     `0x6e86`-`0x7028`). The caller `0x6d7d` reads one byte, multiplies it by
     `0x80` (`mov $0x80,%al` / `mul %bl`, the EDID block size) and calls the
     accessor, which reads `0x40`-byte blocks through `0x735d` (a bit-banged
     byte, GPIO at MMIO `0x10000`/`0x10004`) into `ES:DI`, sums it in `CH` and
     returns VBE status `0x004f` on a zero sum, `0x014f` with carry otherwise.
     The sibling routine `0x6e9e` sends DDC addresses `0xa1`, `0xa3`, `0xa7`,
     `0xa9` (`0x50`, `0x51`, `0x53`, `0x54` shifted left once with the read bit
     set) via `0x748a` and reads `0x80`-byte blocks with the same checksum. The
     path is therefore a real DDC/EDID reader, and the `EDID` keyword count of
     zero (section 2.4) only means the ROM never spells the name.
   - ROM alone: yes for "the accessor is called by an EDID-shaped DDC read
     path". What no ROM can settle is whether a monitor answers on a given
     host; that is a hardware observation, and it is not needed to describe the
     code.

## 13. Divergences from the driver

The ROM and `src/*.c` set some of the same registers differently. Both values
are given so a later reader can decide which one is right.

| Register | ROM | Driver |
| --- | --- | --- |
| `PANEL_PLL_CTRL 0x05c` | never written; the ROM programs the PLL fields in `0x80000`/`0x80200` instead (`0x021f`) | written by `sm750_format_pll_reg` from `src/ddk750_chip.c:385`, called at `src/ddk750_mode.c:214` |
| `MXCLK_PLL_CTRL 0x070` | `0x0002045c`, or `cs:0x167` = `0x00020451` when the panel test passes (`0x02e3`/`0x02e9`) | `sm750_format_pll_reg` output, `src/ddk750_chip.c:81` |
| `MODE0_GATE 0x044` | `(old & 0xfff) | 0x5000` when the panel test passes, mirrored to `MODE1_GATE 0x048` (`0x02a5`-`0x02bd`) | `MODE0_GATE_GPIO` ORed in `src/ddk750_chip.c:191-193`; `MODE1_GATE` used only by `ddk750_set_gate` in `src/ddk750_power.c:79` |
| `POWER_MODE_CTRL 0x04c` | `or 4`, `and-not 4` from the record at `0x11b` | mode/OSC/336CLK fields, `src/ddk750_power.c:37-73` |
| display enable | sequencer register 1 bit 5 **plus** `0x80000`/`0x80200` bit 2 (`0x33d9`, `0x340d`) | `PANEL_DISPLAY_CTRL`/`CRT_DISPLAY_CTRL` enable bits, `src/ddk750_display.c:23-60` |
| `0x80000`/`0x80200` bits 12-13 | copied from `0x80000` into `0x80200` (`0x5e79`) | not touched |
| `0x80014`-`0x80020` | pitch in bits 16-27, extent in the low word (`0x5cec`) | `PANEL_WINDOW_WIDTH`/`HEIGHT`/`PLANE_TL`/`BR` written by the modeset path |
| `0x98000` bits 13-14 | read-modify-write (`0x5e16`) | not touched |
| SiI9024A `0x82`, `0x7c`, `0xf5`, `0xc7`, `0xbc`, `0xbd` | written at `0x1317` with the values in section 6.6 | `src/sii902x.c` drives the TPI through its own sequence |
| CRTC `0x89`/`0x8a` | written as a pair through `0x6151` | CRTC writes go through the driver's own timing path |

The largest divergence is the display-enable mechanism: the ROM uses a
sequencer-register bit that the driver never writes, so a driver that assumed it
was the only writer of the display state would leave the ROM's screen-off bit
set if the ROM had run before it.
