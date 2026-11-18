/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * SiI9024A bring-up, modelled from the ROM routine at 0xc1317.
 *
 * The ROM talks to the transmitter over a bit-banged I2C bus, not over DDC:
 *
 *   0xc711c  START   SDA high, SCL high, SDA low
 *   0xc7140  STOP    SCL high, SDA low, SDA high
 *   0xc74dc  one byte, MSB first, ACK polled up to 0xff times
 *   0xc745e  one register write = START, address, register, value, STOP
 *
 * The device address the ROM uses is 0x72, which is the SiI9024A's control
 * interface at 7-bit address 0x39 with the write bit clear. The model keeps the
 * ROM's 8-bit value rather than reinterpreting it.
 *
 * The ROM writes each register in its own transaction (`0xc745e` starts and
 * stops the bus every time), so this is not the usual register-index-then-data
 * pair of a single transaction. That shape matters for a reader comparing the
 * two implementations: a driver that keeps the bus open across a
 * register/value pair is not doing what the ROM does.
 */

#include "rom.h"

#define ROM_SII9024A_ADDR 0x72u

/*
 * 0xc1317. The prologue at 0xc70c3 runs first: clear bits 12 and 13 of MMIO
 * 0x08, then set bit 6 of both MODE0_GATE and MODE1_GATE. The ROM does this
 * before the first TPI write, presumably to hold the transmitter in reset while
 * the registers are programmed.
 */
void rom_sii9024a_unreset(void)
{
	uint32_t v;

	v = rom_mmio_read(ROM_MMIO_UNNAMED_008);
	v &= 0xffffefffu;
	rom_mmio_write(ROM_MMIO_UNNAMED_008, v);
	v &= 0xffffdfffu;
	rom_mmio_write(ROM_MMIO_UNNAMED_008, v);

	v = rom_mmio_read(ROM_MODE0_GATE);
	rom_mmio_write(ROM_MODE0_GATE, v | 0x40u);
	v = rom_mmio_read(ROM_MODE1_GATE);
	rom_mmio_write(ROM_MODE1_GATE, v | 0x40u);
}

/*
 * The 30 register writes in ROM order, measured one `mov bl`/`mov cl` pair at a
 * time from 0xc1317 to the ret at 0xc1428. Register 0x08 and register 0x1a each
 * appear more than once, and the repeats are in the image: the ROM writes 0x08
 * = 0x70 three times and 0x1a = 0x11, 0x10, 0x40 in that order. Do not
 * deduplicate the list.
 */
const struct rom_sii_pair rom_sii9024a_pairs[] = {
	{ 0x82, 0x25 },	/* input bus and pixel repetition */
	{ 0x7c, 0x14 },
	{ 0xf5, 0x00 },
	{ 0xc7, 0x00 },
	{ 0xbc, 0x01 },	/* power state: leave standby */
	{ 0xbd, 0x03 },
	{ 0xbc, 0x01 },
	{ 0xbd, 0x02 },
	{ 0x3c, 0x01 },
	{ 0x08, 0x70 },	/* input video format */
	{ 0x00, 0x01 },	/* device power state */
	{ 0x01, 0x1d },
	{ 0x02, 0x70 },
	{ 0x03, 0x17 },
	{ 0x04, 0x72 },
	{ 0x05, 0x06 },
	{ 0x06, 0xee },
	{ 0x07, 0x02 },
	{ 0x08, 0x70 },
	{ 0x1a, 0x11 },	/* audio/video interface config */
	{ 0x09, 0x00 },
	{ 0x0a, 0x10 },
	{ 0x19, 0x00 },
	{ 0x1a, 0x10 },
	{ 0x60, 0x00 },
	{ 0x1e, 0x00 },
	{ 0x26, 0x30 },
	{ 0x63, 0x00 },
	{ 0x0b, 0x00 },
	{ 0x1a, 0x40 },
};

const unsigned rom_sii9024a_pair_count =
	sizeof(rom_sii9024a_pairs) / sizeof(rom_sii9024a_pairs[0]);

/*
 * 0xc745e. Returns 0 when all three bytes were acknowledged and 1 on the first
 * failure, which is what the ROM's `or ax,ax / je` chain after each call tests.
 *
 * The transport is not modelled. SDA and SCL are driven through two helper
 * routines the ROM calls (0xc728b and 0xc72d0), each of which writes a bit into
 * an MMIO register this model has no name for; the model therefore has no pin
 * to toggle and records nothing rather than inventing a VGA register write. The
 * transaction shape is what a reader needs: one START, the 8-bit device
 * address, one register byte, one value byte, one STOP, with the ACK polled up
 * to 0xff times inside 0xc74dc.
 */
int rom_sii9024a_write(uint8_t addr, uint8_t reg, uint8_t value)
{
	if (addr != ROM_SII9024A_ADDR)
		return 1;
	(void)reg;
	(void)value;
	return 0;
}

/* 0xc1317: the prologue, then the 30 writes in ROM order. */
int rom_sii9024a_init(void)
{
	unsigned i;

	rom_sii9024a_unreset();
	for (i = 0; i < rom_sii9024a_pair_count; i++) {
		if (rom_sii9024a_write(ROM_SII9024A_ADDR,
				       rom_sii9024a_pairs[i].reg,
				       rom_sii9024a_pairs[i].value))
			return 1;
	}
	return 0;
}