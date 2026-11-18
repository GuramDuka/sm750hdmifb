/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Panel, gate and window programming.
 *
 * Models:
 *   0xc01f4  apply the 12-byte MMIO records at file offset 0x11b
 *   0xc0327  Misc Output init, then the MMIO table
 *   0xc5cec  window width/height/plane programming
 *   0xc5e16  panel and CRT clock bits from Misc Output, then MMIO 0x98000
 */

#include "rom.h"

/*
 * The record table at file offset 0x11b is a run of 12-byte records
 * { u32 mmio_offset, u32 or_mask, u32 and_not_mask } terminated by an offset of
 * 0xffffffff. 0xc01f4 applies `value = (read & ~and_not) | or` to each record in
 * table order: it loads the third word, inverts it (`not ecx`) and ANDs, so the
 * third word is the mask of bits to clear, not a keep mask.
 */
struct rom_mmio_record {
	uint32_t off;
	uint32_t or_mask;
	uint32_t and_not;
};

static const struct rom_mmio_record rom_mmio_records[] = {
	{ ROM_MMIO_UNNAMED_064, 0x00020407u, 0x0007ffffu },
	{ ROM_MMIO_UNNAMED_068, 0x00022c5fu, 0x0007ffffu },
	{ ROM_POWER_MODE_CTRL, 0x00000004u, 0x00000004u },
	{ ROM_MISC_CTRL, 0x00000000u, 0x00010000u },
	{ ROM_PANEL_PLL_CTRL, 0x00020407u, 0x0007ffffu },
	{ ROM_MMIO_UNNAMED_060, 0x00020407u, 0x0007ffffu },
	{ ROM_MXCLK_PLL_CTRL, 0x00020451u, 0x0007ffffu },
	{ ROM_MMIO_UNNAMED_074, 0x00010000u, 0x00010000u },
	{ ROM_MODE0_GATE, 0x00000effu, 0x0000ffffu },
	{ ROM_MODE1_GATE, 0x00000effu, 0x0000ffffu },
	{ ROM_MMIO_UNNAMED_98004, 0x00000000u, 0xffffffffu },
	{ ROM_MMIO_UNNAMED_98008, 0x00000000u, 0xffffffffu },
	{ ROM_MMIO_UNNAMED_9800C, 0x00000000u, 0xffffffffu },
	{ ROM_MMIO_UNNAMED_98010, 0x00000000u, 0xffffffffu },
	{ ROM_MMIO_UNNAMED_98014, 0x00000000u, 0xffffffffu },
};

/* 0xc01f4: read-modify-write each record in table order. */
void rom_apply_mmio_table(void)
{
	unsigned i;

	for (i = 0; i < sizeof(rom_mmio_records) / sizeof(rom_mmio_records[0]);
	     i++) {
		const struct rom_mmio_record *r = &rom_mmio_records[i];
		uint32_t value = rom_mmio_read(r->off);

		value &= ~r->and_not;
		value |= r->or_mask;
		rom_mmio_write(r->off, value);
	}
}

/*
 * 0xc0327. Read Misc Output 0x3cc; a non-zero value makes the ROM force
 * AL = 0x6f with bits 2-3 cleared (0xf3) before writing 0x3c2, i.e. it keeps a
 * real VGA's clock-select bits and forces the rest. Then the MMIO table is
 * applied, 0xc01d3 runs (the 0xff-terminated byte list at file offset 0x108),
 * and CRTC register 0x96 is read back.
 */
void rom_misc_output_init(void)
{
	uint8_t misc = rom_in8(0x3cc);
	uint8_t value = 0x6f;

	if (misc)
		value &= 0xf3;
	rom_out8(0x3c2, value);
	rom_apply_mmio_table();
	(void)rom_crtc_read(0x96);
}

/*
 * 0xc5e16, one routine from 0xc5e16 to the ret at 0xc5e78.
 *
 * Misc Output bits 6-7 are read once (`and al,0xc0`) and reused three times:
 *   PANEL_DISPLAY_CTRL bits 12-13 = misc bits 6-7  (`shr cl,2 / or ah,cl`)
 *   CRT_DISPLAY_CTRL   bits 12-13 = misc bits 6-7  (same sequence)
 *   MMIO 0x98000 bit 14 = misc bit 7, bit 13 = NOT misc bit 6
 * The last two come from `pop cx / shr cl,1 / and cl,0x40` and
 * `pop cx / not cx / and cl,0x20`; because CL only ever held bits 6-7 of the
 * Misc Output byte, the inverted bit 5 of the shifted value is the complement
 * of misc bit 6, and the masked bit 6 is misc bit 7. The two MMIO bits are
 * therefore a pair that always moves in opposite directions - a power and an
 * enable, but docs/specs/REGISTER-MAP.md has no name for MMIO 0x98000, so the
 * model keeps the raw offset.
 */
void rom_panel_clock_and_power(void)
{
	uint8_t misc = (uint8_t)(rom_in8(0x3cc) & 0xc0u);
	uint16_t cl = (uint16_t)((uint16_t)misc >> 2);
	uint32_t panel;
	uint32_t crt;
	uint32_t pwr;

	panel = rom_mmio_read(ROM_PANEL_DISPLAY_CTRL) & 0xffffcfffu;
	panel = (panel & 0xffff0000u) |
		((panel & 0x0000ffffu) | (uint32_t)(cl << 8));
	rom_mmio_write(ROM_PANEL_DISPLAY_CTRL, panel);

	crt = rom_mmio_read(ROM_CRT_DISPLAY_CTRL) & 0xffffcfffu;
	crt = (crt & 0xffff0000u) |
	      ((crt & 0x0000ffffu) | (uint32_t)(cl << 8));
	rom_mmio_write(ROM_CRT_DISPLAY_CTRL, crt);

	pwr = rom_mmio_read(ROM_MMIO_UNNAMED_98000) & 0xffffbfffu;
	cl = (uint16_t)((uint16_t)misc >> 1);
	pwr = (pwr & 0xffff0000u) |
	      ((pwr & 0x0000ffffu) | (uint32_t)((cl & 0x40u) << 8));
	pwr &= 0xffffdfffu;
	cl = (uint16_t)~misc;
	pwr = (pwr & 0xffff0000u) |
	      ((pwr & 0x0000ffffu) | (uint32_t)((cl & 0x20u) << 8));
	rom_mmio_write(ROM_MMIO_UNNAMED_98000, pwr);
}

/*
 * 0xc5cec. Two helpers read the tables at file offsets 0xc47 and 0xc49, both
 * indexed by bits 16-19 of EBX (`call 0xc3476` = `shr ebx,0x10 / and bx,0xf`)
 * with a 6-byte stride, so the table holds one 16-bit value plus three bytes of
 * padding per entry. 0xc6205 returns the 0xc49 word and 0xc621a the 0xc47 word.
 *
 *   ecx = (a << 16) | b;  ecx -= 0x10001;      a from 0xc49, b from 0xc47
 *   PANEL_WINDOW_WIDTH  (0x80014) = ((ecx << 16) & 0x0fff0000) = (b-1) << 16
 *   PANEL_WINDOW_HEIGHT (0x80018) = (ecx & 0x0fff0000)          = (a-1) << 16
 *   PANEL_PLANE_TL      (0x8001c) = 0
 *   PANEL_PLANE_BR      (0x80020) = ecx & 0x07ff07ff
 *
 * For table index 0 the words are a = 0x0c8 (from 0xc49) and b = 0x140 (from
 * 0xc47), so the width field ends up 0x13f (320-1) and the height field 0x0c7
 * (200-1): the ROM's `b` is the horizontal extent. Which of the two ROM tables
 * is horizontal by intent is UNDETERMINED; the model keeps the call order and
 * the register names from src/ddk750_reg.h rather than renaming the fields.
 */
void rom_program_window(uint16_t a, uint16_t b)
{
	uint32_t ecx = ((uint32_t)a << 16) | (uint32_t)b;

	ecx -= 0x10001u;
	rom_mmio_write(ROM_PANEL_WINDOW_WIDTH, (ecx << 16) & 0x0fff0000u);
	rom_mmio_write(ROM_PANEL_WINDOW_HEIGHT, ecx & 0x0fff0000u);
	rom_mmio_write(ROM_PANEL_PLANE_TL, 0);
	rom_mmio_write(ROM_PANEL_PLANE_BR, ecx & 0x07ff07ffu);
}
