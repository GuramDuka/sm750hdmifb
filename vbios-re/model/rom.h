/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * C semantic model of the captured SM750 option ROM.
 *
 * This is a reading aid, not driver code. Nothing in src/ includes it, the
 * kernel module does not link it, and it is not part of the packaged sources.
 * Every function names the ROM file offset it models; the corresponding
 * absolute address is ROM_BASE + offset.
 *
 * Register names follow docs/specs/REGISTER-MAP.md, which carries the
 * datasheet citation for each MMIO address. Where that document has no name
 * for an address, the raw offset is used and the function says so.
 */

#ifndef VBIOS_RE_MODEL_ROM_H
#define VBIOS_RE_MODEL_ROM_H

#include <stdint.h>

/* The image loads at 0xC0000 and its entry point is file offset 0x1256. */
#define ROM_BASE 0xC0000u

/* MMIO registers the ROM touches, named as in docs/specs/REGISTER-MAP.md. */
#define ROM_MISC_CTRL 0x000004u		/* MISC_CTRL, src/ddk750_reg.h:46 */
#define ROM_MODE0_GATE 0x000044u	/* MODE0_GATE, src/ddk750_reg.h:333 */
#define ROM_MODE1_GATE 0x000048u	/* MODE1_GATE, src/ddk750_reg.h:356 */
#define ROM_POWER_MODE_CTRL 0x00004Cu	/* POWER_MODE_CTRL, src/ddk750_reg.h:379 */
#define ROM_PANEL_PLL_CTRL 0x00005Cu	/* PANEL_PLL_CTRL, src/ddk750_reg.h:400 */
#define ROM_MXCLK_PLL_CTRL 0x000070u	/* MXCLK_PLL_CTRL, src/ddk750_reg.h:428 */
#define ROM_PANEL_DISPLAY_CTRL 0x080000u /* PANEL_DISPLAY_CTRL, src/ddk750_reg.h:537 */
#define ROM_PANEL_WINDOW_WIDTH 0x080014u /* src/ddk750_reg.h:593 */
#define ROM_PANEL_WINDOW_HEIGHT 0x080018u /* src/ddk750_reg.h:598 */
#define ROM_PANEL_PLANE_TL 0x08001Cu	/* src/ddk750_reg.h:603 */
#define ROM_PANEL_PLANE_BR 0x080020u	/* src/ddk750_reg.h:608 */
#define ROM_CRT_DISPLAY_CTRL 0x080200u	/* CRT_DISPLAY_CTRL, src/ddk750_reg.h:999 */

/*
 * MMIO offsets the ROM touches that docs/specs/REGISTER-MAP.md does not name.
 * They are written as raw offsets and the model does not invent meanings.
 */
#define ROM_MMIO_UNNAMED_008 0x000008u
#define ROM_MMIO_UNNAMED_060 0x000060u
#define ROM_MMIO_UNNAMED_064 0x000064u
#define ROM_MMIO_UNNAMED_068 0x000068u
#define ROM_MMIO_UNNAMED_074 0x000074u
#define ROM_MMIO_UNNAMED_98000 0x098000u
#define ROM_MMIO_UNNAMED_98004 0x098004u
#define ROM_MMIO_UNNAMED_98008 0x098008u
#define ROM_MMIO_UNNAMED_9800C 0x09800Cu
#define ROM_MMIO_UNNAMED_98010 0x098010u
#define ROM_MMIO_UNNAMED_98014 0x098014u

/* Trace of the accesses the model performs, in ROM order. */
#define ROM_TRACE_MAX 512

struct rom_trace_entry {
	uint32_t off;	/* MMIO offset, or the I/O port for a port access */
	uint32_t value;
	unsigned char is_write;
	unsigned char is_port;
};

extern struct rom_trace_entry rom_trace[ROM_TRACE_MAX];
extern unsigned rom_trace_len;

void rom_ops_reset(void);

/* Port I/O, modelled as the ROM issues it (offsets 0xc606d-0xc60ae thunks). */
uint8_t rom_in8(uint16_t port);
void rom_out8(uint16_t port, uint8_t value);
uint16_t rom_in16(uint16_t port);
void rom_out16(uint16_t port, uint16_t value);

/*
 * MMIO access with the offset in EBX, as the helpers at 0xc6321 (read) and
 * 0xc6349 (write) do it. The ROM always works on a 32-bit value.
 */
uint32_t rom_mmio_read(uint32_t off);
void rom_mmio_write(uint32_t off, uint32_t value);

/*
 * Sequencer and CRTC helpers.
 *
 * 0xc5b2c: write AL to port 0x3c4, read port 0x3c5 into AH, leave DX = 0x3c4.
 * 0xc3440: write AL to the CRTC index port, read the data port into AX.
 * 0xc3446: same with the index port fixed at 0x3d4.
 * 0xc33c4: DX = 0x3b4 or 0x3d4 from bit 0 of Misc Output 0x3cc.
 */
void rom_seq_write(uint8_t index, uint8_t value);
uint8_t rom_seq_read(uint8_t index);
uint16_t rom_crtc_read(uint8_t index);
void rom_crtc_write(uint8_t index, uint8_t value);
uint16_t rom_crtc_base(void);

/* 0xc3263: GC register 6, bit 0 of AH - the flat-panel test. */
int rom_is_panel(void);

/* 0xc6172: wait for `count` vertical retraces; 0xc61ad waits one. */
void rom_wait_vsync(uint16_t count);

/* Clock table at file offset 0xaf3 (43 stride-3 entries, 0xff-terminated). */
struct rom_clock_entry {
	uint8_t index;
	uint8_t crtc_reg;
	uint8_t field;	/* high nibble: shift, low nibble: width mask */
};

extern const struct rom_clock_entry rom_clock_table[];
extern const unsigned rom_clock_table_len;

/*
 * 0xc5b3e: look `index` up, read the CRTC register it names, extract the bit
 * field, and return the field value. Returns -1 when the index is absent.
 */
int rom_clock_lookup(uint8_t index);

/* clock.c */
void rom_pll_program(void);		/* 0xc0220 */
void rom_pll_pulse(void);		/* 0xc0277 */
void rom_copy_clock_select(void);	/* 0xc5e78 */
void rom_panel_clock_select(void);	/* 0xc02a0 */

/* panel.c */
void rom_apply_mmio_table(void);	/* 0xc01f4 */
void rom_misc_output_init(void);	/* 0xc0327 */
void rom_panel_clock_and_power(void);	/* 0xc5e16 */
void rom_program_window(uint16_t a, uint16_t b); /* 0xc5cec */

/* dpms.c */
void rom_display_off(void);		/* 0xc33d9 */
void rom_display_on(void);		/* 0xc340d */

/* mode_table.c - the 0x40-byte BIOS mode records and their consumers. */
#define ROM_MODE_RECORD_SIZE 0x40u
#define ROM_MODE_ATTR_7 0x7EACu		/* fixed row for mode 7 (0xc17e8) */
#define ROM_MODE_ATTR_8 0x7EECu		/* fixed row for mode 8 (0xc17e8) */
#define ROM_MODE_STREAM 0x7DCEu		/* VGA replay stream (0xc334a) */

uint32_t rom_mode_row(uint32_t table_base, unsigned mode);	/* 0xc344c */
uint32_t rom_mode_attr_row(unsigned mode, int second_block);	/* 0xc17e8 */
void rom_mode_vga_replay(const uint8_t *stream, unsigned bytes); /* 0xc334a */
int rom_reg_table_lookup(uint8_t key);			/* 0xc3382 */

/* sii9024a.c - the HDMI transmitter bring-up at 0xc1317. */
#define ROM_SII9024A_ADDR 0x72u

struct rom_sii_pair {
	uint8_t reg;
	uint8_t value;
};

extern const struct rom_sii_pair rom_sii9024a_pairs[];
extern const unsigned rom_sii9024a_pair_count;

void rom_sii9024a_unreset(void);				/* 0xc70c3 */
int rom_sii9024a_write(uint8_t addr, uint8_t reg, uint8_t value); /* 0xc745e */
int rom_sii9024a_init(void);					/* 0xc1317 */

#endif /* VBIOS_RE_MODEL_ROM_H */
