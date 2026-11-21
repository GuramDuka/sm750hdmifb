#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# sm750-console - inspect and move the SM750 panel between the text console
# and the graphical session.
#
# The panel is dark while the foreground VT is KD_GRAPHICS: the kernel console
# drops output before fbcon (drivers/tty/vt/vt.c, do_con_write) and a Wayland
# session on another card paints nothing on card0. Switching the foreground VT
# to a text VT puts the VT back into KD_TEXT, fbcon binds and the console
# reaches the panel. This script is that one-command route, plus the status an
# operator needs afterwards.
#
# Exit codes:
#   0  the requested action ran and the status was printed
#   1  environment problem (not root, no /dev/tty0, chvt failed, no SM750 card)
#   2  bad usage
set -u

PROG=sm750-console
DEBUGFS=/sys/kernel/debug

usage() {
	echo "usage: $PROG show | text [N] | graphics" >&2
	exit 2
}

say() { printf '%s\n' "$*"; }
fail() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

[ $# -ge 1 ] || usage
action=$1
shift
case "$action" in
show|text|graphics) ;;
*) usage ;;
esac

[ "$(id -u)" -eq 0 ] || fail "root is required: debugfs is mode 0700 and chvt needs CAP_SYS_TTY_CONFIG"
[ -e /dev/tty0 ] || fail "/dev/tty0 is missing"

# 0x4B3B is KDGETMODE on the tty file descriptor: 0 KD_TEXT, 1 KD_GRAPHICS,
# 4 KD_KDWANTED.
vt_mode=$(python3 -c '
import fcntl, struct, sys
f = open("/dev/tty0", "rb")
sys.stdout.write(str(struct.unpack("i", fcntl.ioctl(f.fileno(), 0x4B3B,
                                                     struct.pack("i", 0)))[0]))
' 2>/dev/null) || fail "cannot read the VT mode of /dev/tty0 with KDGETMODE"

mode_name() {
	case "$1" in
	0) echo KD_TEXT ;;
	1) echo KD_GRAPHICS ;;
	4) echo KD_KDWANTED ;;
	*) echo "unknown($1)" ;;
	esac
}

show_status() {
	active=$(cat /sys/class/tty/tty0/active 2>/dev/null) || active=
	say "active tty:   ${active:-unknown}"
	say "tty0 mode:    $(mode_name "$vt_mode") ($vt_mode)"

	for vc in /sys/class/vtconsole/vtcon*; do
		[ -r "$vc/name" ] || continue
		name=$(cat "$vc/name" 2>/dev/null) || name=
		bind=$(cat "$vc/bind" 2>/dev/null) || bind=
		say "vtconsole:    $(basename "$vc") bind=$bind name=$name"
	done

	card=
	for d in "$DEBUGFS"/dri/*; do
		[ -r "$d/name" ] || continue
		if grep -q "sm750hdmidrm" "$d/name" 2>/dev/null; then
			card=$d
			break
		fi
	done
	[ -n "$card" ] || fail "no SM750 DRM device (card absent or driver not loaded)"

	if [ -x /usr/local/sbin/sm750-regs ]; then
		regs=$(/usr/local/sbin/sm750-regs 2>/dev/null) || regs=
	else
		regs=$(cat "$card/regs" 2>/dev/null) || regs=
	fi
	if [ -n "$regs" ]; then
		addr=$(printf '%s\n' "$regs" |
			awk '$2 == "PANEL_FB_ADDRESS" { print $3; exit }')
		say "PANEL_FB_ADDRESS: ${addr:-unknown}"
	else
		say "PANEL_FB_ADDRESS: unavailable (no sm750-regs and no $card/regs)"
	fi

	if [ -r "$card/sm750_scanout" ]; then
		dump_field() {
			head -n 8 "$card/sm750_scanout" |
				awk -v key="$1" '$1 == key { print $2; exit }'
		}
		say "scanout offset:   $(dump_field offset)"
		say "scanout nonzero:  $(dump_field nonzero)"
		crc=$(dump_field crc32)
		say "scanout crc32:    $crc"
		if [ "$crc" = "0xe20eea22" ]; then
			say "(crc32 0xe20eea22 is 262144 zero bytes: nothing has painted the window)"
		else
			say "(crc32 0xe20eea22 is 262144 zero bytes; this frame is not it)"
		fi
	else
		say "scanout:          unavailable ($card/sm750_scanout is not readable)"
	fi
}

switch_vt() {
	/usr/bin/chvt "$1" || fail "chvt $1 failed"
	sleep 1
	vt_mode=$(python3 -c '
import fcntl, struct, sys
f = open("/dev/tty0", "rb")
sys.stdout.write(str(struct.unpack("i", fcntl.ioctl(f.fileno(), 0x4B3B,
                                                     struct.pack("i", 0)))[0]))
' 2>/dev/null) || fail "cannot read the VT mode of /dev/tty0 with KDGETMODE"
}

case "$action" in
show)
	[ $# -eq 0 ] || usage
	show_status
	;;
text)
	[ $# -le 1 ] || usage
	n=${1:-2}
	case "$n" in
	''|*[!0-9]*) usage ;;
	esac
	switch_vt "$n"
	show_status
	;;
graphics)
	[ $# -eq 0 ] || usage
	switch_vt 1
	show_status
	;;
esac
