#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# T31: the console really reaches the panel when the foreground VT is in
# KD_TEXT. The driver's sm750_scanout debugfs dump reads the visible scanout
# window back out of VRAM, so it says whether the panel is being handed content
# or zeros. With the VT in KD_GRAPHICS the kernel console drops output before
# fbcon (drivers/tty/vt/vt.c do_con_write), the fbdev client's buffer stays
# blank and an all-zero window is expected; that is a precondition, not a
# defect. This check therefore only tells the two states apart: it skips under
# KD_GRAPHICS and, on a text VT, asserts that writing to /dev/tty0 leaves
# content in the window, that the content is not the blank sentinel, and that
# the dump's offset is the address the panel register points at.
#
# The blank sentinel is crc32 of 262144 zero bytes: 0xe20eea22.
#
# Exit 77 with a single SKIP: line when the check cannot run: no root (the
# debugfs files are mode 0700), no debugfs, no SM750 card, no readable
# sm750_scanout, no /dev/tty0, or a foreground VT in KD_GRAPHICS.
#
# Nothing is written to docs/evidence/ and the console is left as found.

set -eu

DEBUGFS=/sys/kernel/debug
BLANK_CRC=0xe20eea22
here=$(cd "$(dirname "$0")/.." && pwd)

skip() {
	echo "SKIP: $1"
	exit 77
}

fail() {
	echo "FAIL: $1"
	exit 1
}

pass() {
	echo "PASS: $1"
}

[ "$(id -u)" -eq 0 ] || skip "root is required: $DEBUGFS and its sm750_scanout are mode 0700"
[ -d "$DEBUGFS/dri" ] || skip "debugfs is not mounted at $DEBUGFS"

card=
for d in "$DEBUGFS"/dri/*; do
	[ -r "$d/name" ] || continue
	if grep -q "sm750hdmidrm" "$d/name" 2>/dev/null; then
		card=$d
		break
	fi
done
[ -n "$card" ] || skip "no SM750 DRM device (card absent or driver not loaded)"
[ -r "$card/sm750_scanout" ] || skip "$card/sm750_scanout is missing"
[ -r /dev/tty0 ] || skip "/dev/tty0 is missing"
command -v python3 >/dev/null 2>&1 ||
	skip "python3 is required to read the VT mode with KDGETMODE"

# KDGETMODE (0x4B3B) on the foreground VT: 0 is KD_TEXT, 1 is KD_GRAPHICS.
vt_mode=$(python3 -c '
import fcntl, struct, sys
f = open("/dev/tty0", "rb")
sys.stdout.write(str(struct.unpack("i", fcntl.ioctl(f.fileno(), 0x4B3B,
                                                     struct.pack("i", 0)))[0]))
' 2>/dev/null) || skip "cannot read the VT mode of /dev/tty0 with KDGETMODE"

if [ "$vt_mode" = "1" ]; then
	echo "SKIP: foreground VT is KD_GRAPHICS; the kernel console discards output before fbcon, so an all-zero scanout window is expected - run this on a text VT"
	exit 77
fi
[ "$vt_mode" = "0" ] || skip "unexpected KDGETMODE value $vt_mode on /dev/tty0"

dump_field() {
	head -n 8 "$card/sm750_scanout" | awk -v key="$1" '$1 == key { print $2; exit }'
}

# PANEL_FB_ADDRESS is the address the panel scans; the helper prints the same
# regs file the debugfs node does, so a host without the helper (non-root
# install) still has a path.
if [ -x /usr/local/sbin/sm750-regs ]; then
	regs=$(/usr/local/sbin/sm750-regs 2>/dev/null) || regs=
else
	regs=$(cat "$card/regs" 2>/dev/null) || regs=
fi
[ -n "$regs" ] || skip "neither sm750-regs nor $card/regs is readable"
panel_addr=$(printf '%s\n' "$regs" |
	awk '$2 == "PANEL_FB_ADDRESS" { print $3; exit }')
[ -n "$panel_addr" ] || skip "the register dump has no PANEL_FB_ADDRESS row"
panel_dec=$((panel_addr))

# 40 lines on the foreground VT is enough for fbcon to scroll and repaint; the
# driver uploads it before the dump reads the window back.
i=1
while [ "$i" -le 40 ]; do
	printf 'console scanout check %s\n' "$i" > /dev/tty0
	i=$((i + 1))
done
sleep 1

offset=$(dump_field offset)
nonzero=$(dump_field nonzero)
crc=$(dump_field crc32)
[ -n "$offset" ] && [ -n "$nonzero" ] && [ -n "$crc" ] ||
	fail "$card/sm750_scanout did not report offset, nonzero and crc32"

test "$nonzero" -gt 0 ||
	fail "the scanout window is all-zero on a text VT (nonzero $nonzero, crc32 $crc)"
pass "the scanout window carries content: $nonzero nonzero bytes"

test "$crc" != "$BLANK_CRC" ||
	fail "the scanout crc32 is the all-zero sentinel $crc"
pass "the scanout crc32 differs from the all-zero sentinel: $crc"

test "$offset" -eq "$panel_dec" ||
	fail "the dump reads offset $offset but PANEL_FB_ADDRESS is $panel_addr ($panel_dec)"
pass "the dump's offset matches PANEL_FB_ADDRESS: $offset"

echo "Console scanout content checks passed"