/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Clock and PLL handling.
 *
 * Models three ROM routines:
 *   0xc5b3e  clock-table lookup + CRTC bit-field extraction
 *   0xc0220  PLL field programming into PANEL_DISPLAY_CTRL / CRT_DISPLAY_CTRL
 *   0xc0277  reset pulse around the PLL field update
 *   0xc5e78  copy the clock-select bits from PANEL to CRT
 */

#include "rom.h"

/*
 * The table lives at file offset 0xaf3 and is 0xff-terminated; the ROM walks
 * it three bytes at a time from 0xc5b3e. Third byte = (shift << 4) | mask.
 */
const struct rom_clock_entry rom_clock_table[] = {
	{ 0x00, 0x96, 0x08 }, { 0x01, 0x95, 0x62 }, { 0x02, 0x95, 0x42 },
	{ 0x06, 0x95, 0x11 }, { 0x08, 0x97, 0x08 }, { 0x0b, 0x8b, 0x71 },
	{ 0x10, 0x8f, 0x05 }, { 0x11, 0x8f, 0x53 }, { 0x12, 0x93, 0x01 },
	{ 0x13, 0x93, 0x11 }, { 0x14, 0x93, 0x31 }, { 0x15, 0x93, 0x21 },
	{ 0x16, 0x8e, 0x08 }, { 0x18, 0x91, 0x05 }, { 0x19, 0x91, 0x53 },
	{ 0x1a, 0x93, 0x41 }, { 0x1b, 0x93, 0x51 }, { 0x1c, 0x93, 0x71 },
	{ 0x1d, 0x93, 0x61 }, { 0x28, 0x8c, 0x42 }, { 0x29, 0x8d, 0x21 },
	{ 0x2a, 0x8b, 0x43 }, { 0x2b, 0x8c, 0x02 }, { 0x2f, 0x8d, 0x41 },
	{ 0x30, 0x8d, 0x31 }, { 0x31, 0x8d, 0x11 }, { 0x32, 0x8d, 0x01 },
	{ 0x33, 0x92, 0x61 }, { 0x40, 0x92, 0x04 }, { 0x41, 0x92, 0x01 },
	{ 0x42, 0x92, 0x11 }, { 0x43, 0x92, 0x21 }, { 0x44, 0x92, 0x31 },
	{ 0x50, 0x94, 0x01 }, { 0x52, 0x8c, 0x71 }, { 0x53, 0x92, 0x71 },
	{ 0x62, 0x95, 0x21 }, { 0x67, 0x8c, 0x61 }, { 0x6a, 0x94, 0x11 },
	{ 0x6b, 0x94, 0x21 }, { 0x6c, 0x94, 0x31 }, { 0x6d, 0x94, 0x61 },
	{ 0x6f, 0x94, 0x71 },
};

const unsigned rom_clock_table_len =
	sizeof(rom_clock_table) / sizeof(rom_clock_table[0]);

/*
 * 0xc5b3e. Extract the field the table entry describes from the CRTC register
 * it names. The ROM shifts AH (the register content) right by the high nibble
 * and masks with the low nibble; it returns the value in AL and clears carry.
 * A missing index jumps to 0xc5b83, which sets carry and returns AL = 0xff.
 */
int rom_clock_lookup(uint8_t index)
{
	unsigned i;

	for (i = 0; i < rom_clock_table_len; i++) {
		const struct rom_clock_entry *e = &rom_clock_table[i];
		uint16_t reg;
		unsigned shift;
		unsigned mask;

		if (e->index != index)
			continue;
		reg = rom_crtc_read(e->crtc_reg);
		shift = (unsigned)(e->field >> 4);
		mask = (unsigned)(e->field & 0x0f);
		return (int)((((unsigned)reg >> 8) >> shift) &
			     ((1u << mask) - 1u));
	}
	return -1;
}

/*
 * 0xc0220. Clock index 2 supplies a field placed at bit 18 of
 * PANEL_DISPLAY_CTRL (32-bit `shl ecx,0x12` after the 0xfff3bfff mask). Clock
 * index 6 supplies a 16-bit field placed at bit 14 of the LOW WORD of
 * PANEL_DISPLAY_CTRL (`mov cl,al / shl cx,0xe / pop ax / or ax,cx`), so the
 * upper half of the read value is preserved. The same index-6 field is then
 * placed at bit 14 of the low word of CRT_DISPLAY_CTRL after the 0xffffbfff
 * mask. Because `shl cx,0xe` is a 16-bit shift, only the low two bits of the
 * looked-up value survive.
 */
void rom_pll_program(void)
{
	int sel2 = rom_clock_lookup(0x02);
	int sel6 = rom_clock_lookup(0x06);
	uint32_t panel = rom_mmio_read(ROM_PANEL_DISPLAY_CTRL);
	uint32_t crt;

	/* The ROM does not test carry, so a missing index contributes 0xff. */
	if (sel2 < 0)
		sel2 = 0xff;
	if (sel6 < 0)
		sel6 = 0xff;

	panel &= 0xfff3bfffu;
	panel |= (uint32_t)(sel2 & 0xff) << 18;
	panel |= (uint32_t)(uint16_t)((sel6 & 0xff) << 14);
	rom_mmio_write(ROM_PANEL_DISPLAY_CTRL, panel);

	crt = rom_mmio_read(ROM_CRT_DISPLAY_CTRL);
	crt &= 0xffffbfffu;
	crt |= (uint32_t)(uint16_t)((sel6 & 0xff) << 14);
	rom_mmio_write(ROM_CRT_DISPLAY_CTRL, crt);
}

/*
 * 0xc0277. Clear bit 6 of MISC_CTRL, wait two vertical retraces, set it again.
 * The ROM uses this as the reset pulse around a PLL field update.
 */
void rom_pll_pulse(void)
{
	uint32_t v = rom_mmio_read(ROM_MISC_CTRL);

	rom_mmio_write(ROM_MISC_CTRL, v & ~0x40u);
	rom_wait_vsync(2);
	v = rom_mmio_read(ROM_MISC_CTRL);
	rom_mmio_write(ROM_MISC_CTRL, v | 0x40u);
}

/*
 * 0xc5e79. Copy bits 12-13 from PANEL_DISPLAY_CTRL into CRT_DISPLAY_CTRL; the
 * ROM keeps the two panel clocks in step after a clock change.
 *
 * The routine is gated by 0xc6147, which looks clock-table index 0x12 up in the
 * CRTC and tests bit 0 of the extracted field: when the bit is set the ROM calls
 * 0xc5e16 (misc-output driven path) instead of the copy, and when the table has
 * no index 0x12 the lookup returns 0xff, bit 0 is set, and the same branch is
 * taken.
 */
void rom_copy_clock_select(void)
{
	int idx = rom_clock_lookup(0x12);
	uint32_t panel;
	uint32_t crt;

	if (idx < 0 || (idx & 0x1)) {
		rom_panel_clock_and_power();
		return;
	}
	panel = rom_mmio_read(ROM_PANEL_DISPLAY_CTRL) & 0x3000u;
	crt = rom_mmio_read(ROM_CRT_DISPLAY_CTRL) & 0xffffcfffu;
	rom_mmio_write(ROM_CRT_DISPLAY_CTRL, crt | panel);
}

/*
 * 0xc02a0. Panel clock select.
 *
 * `mov ebx,0x44 / call 0xc6321 / and ax,0xfff` keeps the low 12 bits of the
 * low word of MODE0_GATE; the upper 16 bits of the 32-bit value are untouched
 * because the mask is 16-bit. `call 0xc3263` sets ZF from the flat-panel bit,
 * and `jne` skips the `or ax,0x5000`, so 0x5000 is ORed in for the non-panel
 * case. The result is written back to MODE0_GATE and then to MODE1_GATE, whose
 * previous value is read and discarded.
 *
 * MXCLK_PLL_CTRL keeps only its top 15 bits. `call 0xc3263` then selects:
 * `je` (no panel) ORs the built-in 0x2045c into the masked value, while the
 * panel case REPLACES the whole 32-bit value with the board dword at file
 * offset 0x167, which holds 51 04 02 00 = 0x00020451.
 */
void rom_panel_clock_select(void)
{
	uint32_t gate0 = rom_mmio_read(ROM_MODE0_GATE);
	uint32_t pll;
	int panel = rom_is_panel();

	gate0 = (gate0 & 0xffff0000u) | (gate0 & 0x0fffu);
	if (!panel)
		gate0 |= 0x5000u;
	rom_mmio_write(ROM_MODE0_GATE, gate0);
	(void)rom_mmio_read(ROM_MODE1_GATE);
	rom_mmio_write(ROM_MODE1_GATE, gate0);

	if (panel) {
		pll = 0x00020451u;
	} else {
		pll = rom_mmio_read(ROM_MXCLK_PLL_CTRL) & 0xfff80000u;
		pll |= 0x0002045cu;
	}
	rom_mmio_write(ROM_MXCLK_PLL_CTRL, pll);
	rom_pll_pulse();
}
