/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * The BIOS mode table and the two ROM routines that consume it.
 *
 * Layout facts measured from the image:
 *
 *   entry size      0x40 bytes        (`shl bx,0x6` in 0xc344c)
 *   row address     BIOS mode pointer + mode * 0x40   (0xc344c)
 *   rows            16, tiling 0x7c80-0x8080
 *   tail            18-byte parameter block at 0x8049-0x805b, immediately
 *                   before the code at 0x805b
 *
 * The record body holds a 5-byte zero prefix, a 2-byte field, the byte 0x0f,
 * then 0xff, then a timing body, an ascending byte mask
 * (01 02 03 04 05 14 07 38 39 3a 3b 3c 3d 3e 3f), and a trailing
 * NN 00 0f 0Y 00 00 00 00 00 10 0e 00 group. Which byte is which VBE timing
 * field is UNDETERMINED, so this model carries the accessors and the layout,
 * not the record contents. The bytes themselves stay in the ROM.
 */

#include "rom.h"

/*
 * 0xc344c. The BIOS data area dword at 0040:0068 points at the BIOS mode table
 * descriptor; the ROM loads DS with 0x0040, takes the far pointer at DS:0x68,
 * follows it once to reach the flat table address, and adds mode * 0x40.
 * Reproduced as offset arithmetic on the table base.
 */
uint32_t rom_mode_row(uint32_t table_base, unsigned mode)
{
	return table_base + (uint32_t)mode * ROM_MODE_RECORD_SIZE;
}

/*
 * 0xc17e8. Two attribute rows are fixed by mode number. Bit 3 of the BIOS byte
 * at ES:0049 selects the second 16-byte sub-block of the row; otherwise the ROM
 * copies 16 bytes from the row into the save area reached through
 * ES:0068 -> [ES:0068] -> +4, and only when that far pointer is non-null.
 */
uint32_t rom_mode_attr_row(unsigned mode, int second_block)
{
	uint32_t row = (mode == 8) ? ROM_MODE_ATTR_8 : ROM_MODE_ATTR_7;

	if (second_block)
		row += 0x10u;
	return row;
}

/*
 * 0xc334a, the VGA state replay. It is a fixed sequence of block writes rather
 * than a byte-at-a-time replay:
 *
 *   AL = 1, DL = 0xc4, CX = 4, call 0xc32c3   sequencer regs 1..4 from stream
 *   AL = stream[4] (via lodsb), DL = 0xc2     Misc Output from stream
 *   DL = 0xd4, AX = 0x2011                    CRTC reg 0x11 = 0x20
 *   AL = 0, CX = 0x19, call 0xc32c3           CRTC regs 0x00..0x18 from stream
 *   DL = 0xc4, AX = 0x0300                    sequencer reg 3 = 0x00
 *
 * 0xc32c3 is the block writer: `mov ah,[si] / inc si / out dx,ax / inc al /
 * loop`, i.e. it walks the index in AL upward from the caller's value while
 * streaming bytes from DS:SI into the port in DX. DX holds the low byte of the
 * VGA register pair (0xc4 = 0x3c4, 0xd4 = 0x3d4), set by an earlier `mov dl`.
 *
 * The stream pointer is the literal 0x7dce the ROM loads into SI, so the model
 * takes it as an argument rather than embedding the bytes.
 */
void rom_mode_vga_replay(const uint8_t *stream, unsigned bytes)
{
	unsigned i;

	if (bytes < 5 + 0x19)
		return;
	rom_out8(0x3c4, 0x01);
	for (i = 0; i < 4; i++)
		rom_out8(0x3c5, stream[i]);
	rom_out8(0x3c2, stream[4]);
	rom_crtc_write(0x11, 0x20);
	rom_out8(0x3d4, 0x00);
	for (i = 0; i < 0x19; i++)
		rom_out8(0x3d5, stream[5 + i]);
	rom_out8(0x3c4, 0x03);
	rom_out8(0x3c5, 0x00);
}

/*
 * 0xc3382, the register-access selector. A stride-5 table at file offset
 * 0x639b holds { u8 key, u32 value } records; key 0xff at 0x64b3 terminates it,
 * giving 56 records. The ROM scans for the key in BL and returns the dword in
 * EBX, with carry set when the key is absent. Callers shift EBX before masking
 * (0xc346b takes bits 13-15, 0xc3476 takes bits 16-19), so the values are
 * pointers or packed panel descriptors rather than register data.
 *
 * The record values are image data, not behaviour, so this model carries the
 * key set only and reports membership. A caller that needs a value reads it
 * from the image; nothing in src/ depends on these records.
 */
static const uint8_t rom_reg_table_keys[] = {
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x0d, 0x0e, 0x10,
	0x11, 0x12, 0x13, 0x28, 0x29, 0x2b, 0x30, 0x32, 0x34, 0x35,
	0x37, 0x39, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47,
	0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4e, 0x50, 0x52, 0x54, 0x55,
	0x57, 0x59, 0x5a, 0x5c, 0x5e, 0x60, 0x62, 0x64, 0x65, 0x67,
	0x69, 0x6a, 0x6b, 0x70, 0x72, 0x74,
};

int rom_reg_table_lookup(uint8_t key)
{
	unsigned i;

	for (i = 0; i < sizeof(rom_reg_table_keys); i++) {
		if (rom_reg_table_keys[i] == key)
			return 0;
	}
	return -1;
}