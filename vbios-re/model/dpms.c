/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Display blank and unblank.
 *
 * Two ROM routines, and they are not symmetric:
 *   0xc340d  blank   - one leading retrace wait, no trailing wait
 *   0xc33d9  unblank - no leading wait, two trailing retraces
 *
 * Both flip the same two bits in opposite directions:
 *   sequencer register 1 bit 5 (the VGA screen-off bit)
 *   bit 2 of the low byte of PANEL_DISPLAY_CTRL and CRT_DISPLAY_CTRL
 *
 * 0xc340d is the reachable one: it is called from the mode-set routine
 * 0xc042c (both before and after the window/clock programming), from
 * 0xc0aea, 0xc14ef, 0xc2d33 and 0xc698a. No direct call or jump in the image
 * targets 0xc33d9, so its role is inferred from the bits it writes, not from a
 * caller.
 *
 * The ROM writes the sequencer pair with one 16-bit `out dx, ax` after
 * 0xc5b2c leaves DX on the index port, AL holding the index and AH the value.
 */

#include "rom.h"

/*
 * 0xc340d. One retrace first (`call 0xc61ad` is 0xc6172 with bx = 1), then
 * `or ah,0x20` sets bit 5 of sequencer register 1, then `and al,0xfb` clears
 * bit 2 of both display-control registers. Only the low byte is touched, so the
 * 32-bit fields above bit 7 survive.
 */
void rom_display_off(void)
{
	uint32_t v;

	rom_wait_vsync(1);

	rom_seq_write(0x01, (uint8_t)(rom_seq_read(0x01) | 0x20u));

	v = rom_mmio_read(ROM_PANEL_DISPLAY_CTRL);
	rom_mmio_write(ROM_PANEL_DISPLAY_CTRL, (v & ~0xffu) | ((v & 0xfbu) & 0xffu));
	v = rom_mmio_read(ROM_CRT_DISPLAY_CTRL);
	rom_mmio_write(ROM_CRT_DISPLAY_CTRL, (v & ~0xffu) | ((v & 0xfbu) & 0xffu));
}

/*
 * 0xc33d9. `and ah,0xdf` clears bit 5 of sequencer register 1 and the pair is
 * written back in one go; then `or al,4` sets bit 2 of both display-control
 * registers. Finally `mov bx,2 / call 0xc6172` waits out two vertical retraces,
 * which is where the ROM lets the panel settle after the pipe is enabled.
 *
 * Because it clears the screen-off bit and enables the plane, this is the
 * unblank direction under the standard VGA meaning of sequencer register 1
 * bit 5. Whether the SM750 VGA core inverts that bit is UNDETERMINED; if it
 * does, the two routines swap roles and nothing else about the model changes.
 */
void rom_display_on(void)
{
	uint32_t v;

	rom_seq_write(0x01, (uint8_t)(rom_seq_read(0x01) & 0xdfu));

	v = rom_mmio_read(ROM_PANEL_DISPLAY_CTRL);
	rom_mmio_write(ROM_PANEL_DISPLAY_CTRL, (v & ~0xffu) | ((v | 0x04u) & 0xffu));
	v = rom_mmio_read(ROM_CRT_DISPLAY_CTRL);
	rom_mmio_write(ROM_CRT_DISPLAY_CTRL, (v & ~0xffu) | ((v | 0x04u) & 0xffu));

	rom_wait_vsync(2);
}
