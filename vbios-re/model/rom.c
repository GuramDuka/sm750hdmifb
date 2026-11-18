/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Register-file simulation and the low-level helpers the ROM uses.
 *
 * The model is not a device emulator: it holds one 32-bit word per MMIO offset
 * and one byte per I/O port, so a function can be read as a sequence of
 * read-modify-write operations with the resulting values visible in rom_trace.
 */

#include "rom.h"

#include <string.h>

#define ROM_MMIO_SLOTS 32
#define ROM_PORT_SLOTS 256

struct mmio_slot {
	uint32_t off;
	uint32_t value;
	int used;
};

static struct mmio_slot mmio[ROM_MMIO_SLOTS];
static uint8_t ports[ROM_PORT_SLOTS];

struct rom_trace_entry rom_trace[ROM_TRACE_MAX];
unsigned rom_trace_len;

static void trace(uint32_t off, uint32_t value, int is_write, int is_port)
{
	if (rom_trace_len < ROM_TRACE_MAX) {
		rom_trace[rom_trace_len].off = off;
		rom_trace[rom_trace_len].value = value;
		rom_trace[rom_trace_len].is_write = is_write ? 1 : 0;
		rom_trace[rom_trace_len].is_port = is_port ? 1 : 0;
		rom_trace_len++;
	}
}

void rom_ops_reset(void)
{
	memset(mmio, 0, sizeof(mmio));
	memset(ports, 0, sizeof(ports));
	memset(rom_trace, 0, sizeof(rom_trace));
	rom_trace_len = 0;
}

static struct mmio_slot *slot_for(uint32_t off, int create)
{
	unsigned i;
	struct mmio_slot *free_slot = 0;

	for (i = 0; i < ROM_MMIO_SLOTS; i++) {
		if (mmio[i].used && mmio[i].off == off)
			return &mmio[i];
		if (!mmio[i].used && !free_slot)
			free_slot = &mmio[i];
	}
	if (!create || !free_slot)
		return 0;
	free_slot->used = 1;
	free_slot->off = off;
	return free_slot;
}

uint32_t rom_mmio_read(uint32_t off)
{
	struct mmio_slot *s = slot_for(off, 1);
	uint32_t value = s ? s->value : 0;

	trace(off, value, 0, 0);
	return value;
}

void rom_mmio_write(uint32_t off, uint32_t value)
{
	struct mmio_slot *s = slot_for(off, 1);

	if (s)
		s->value = value;
	trace(off, value, 1, 0);
}

uint8_t rom_in8(uint16_t port)
{
	trace(port, ports[port & 0xff], 0, 1);
	return ports[port & 0xff];
}

void rom_out8(uint16_t port, uint8_t value)
{
	ports[port & 0xff] = value;
	trace(port, value, 1, 1);
}

uint16_t rom_in16(uint16_t port)
{
	uint16_t value = (uint16_t)(ports[port & 0xff] |
				    (ports[(port + 1) & 0xff] << 8));

	trace(port, value, 0, 1);
	return value;
}

void rom_out16(uint16_t port, uint16_t value)
{
	ports[port & 0xff] = (uint8_t)value;
	ports[(port + 1) & 0xff] = (uint8_t)(value >> 8);
	trace(port, value, 1, 1);
}

/*
 * 0xc5b2c. The ROM leaves DX pointing at the index port, so a caller that
 * writes both halves with one `out dx, ax` writes index and value together.
 * The model keeps the two operations separate and records both.
 */
void rom_seq_write(uint8_t index, uint8_t value)
{
	rom_out8(0x3c4, index);
	rom_out8(0x3c5, value);
}

uint8_t rom_seq_read(uint8_t index)
{
	rom_out8(0x3c4, index);
	return rom_in8(0x3c5);
}

/*
 * 0xc3440 / 0xc3446. Both write the index with `out dx, al` and then read a
 * 16-bit word back from the index port: the low byte is the index echo, the
 * high byte is the register content. Callers use AH only (0xc5b3e does
 * `shr ah,cl`), so the model returns that word.
 */
uint16_t rom_crtc_read(uint8_t index)
{
	uint16_t base = rom_crtc_base();

	rom_out8(base, index);
	return rom_in16(base);
}

/*
 * Writing goes the other way round: `out dx, ax` with AL = index and AH = the
 * value, which is what 0xc6151 does and what the sequencer path does after
 * 0xc5b2c leaves DX on the index port.
 */
void rom_crtc_write(uint8_t index, uint8_t value)
{
	uint16_t base = rom_crtc_base();

	rom_out16(base, (uint16_t)((value << 8) | index));
}

/* 0xc33c4: Misc Output bit 0 selects the 0x3b4 or the 0x3d4 base. */
uint16_t rom_crtc_base(void)
{
	uint8_t misc = rom_in8(0x3cc);

	return (misc & 0x01) ? 0x3d4 : 0x3b4;
}

/* 0xc3263: GC register 6 index write, then bit 0 of the read-back high byte. */
int rom_is_panel(void)
{
	uint16_t gc;

	rom_out8(0x3ce, 0x06);
	gc = rom_in16(0x3cf);
	return (gc & 0x0100) ? 1 : 0;
}

/* 0xc6172: poll bit 3 of the CRTC status port for each of `count` edges. */
void rom_wait_vsync(uint16_t count)
{
	uint16_t base = rom_crtc_base();
	uint16_t status = base + 6;
	uint16_t i;

	for (i = 0; i < count; i++) {
		unsigned guard = 0x10000u;

		while ((rom_in8(status) & 0x08) && guard--)
			;
		guard = 0x10000u;
		while (!(rom_in8(status) & 0x08) && guard--)
			;
	}
}
