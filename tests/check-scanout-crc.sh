#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# T26/T27: driver-side scanout read path.
#
# Exercises the CRTC CRC source "scanout" and the sm750_scanout debugfs dump.
# Structural assertions only: the SM750 scanout is 16-bit RGB565 with a
# black-body dither, so scanout bytes are never a copy of the XRGB source.
# Checked here: CRC entries arrive, they stay constant for a static frame, they
# change when the frame content changes, and the dump's crc32 and nonzero-byte
# count agree with the CRC path and with what was drawn.
#
# T27 draws the frames through KMS (tests/scanout-pattern.c: dumb buffer,
# addfb, setcrtc) because CONFIG_FB_DEVICE is unset on the reference host and
# there is no /dev/fb0 (defect A24). The last frame stays on screen and its fb
# is not removed: rmfb on a scanned-out fb disables the CRTC and stops vblanks,
# so each run leaves one dumb buffer and one active frame behind.
#
# Exit 77 with a single SKIP: line when the check cannot run: no root (the
# debugfs files this check reads are mode 0700), no debugfs, no SM750 card, no
# CRC directory, no libdrm headers, or no DRM master.

set -eu

DEBUGFS=/sys/kernel/debug
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

cleanup() {
	if [ -n "${crc:-}" ] && [ -w "${crc:-}/control" ]; then
		printf 'none' > "$crc/control" 2>/dev/null || true
	fi
	return 0
}

[ "$(id -u)" -eq 0 ] || skip "root is required: $DEBUGFS and its crc files are mode 0700"
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

crc=$card/crtc-0/crc
[ -d "$crc" ] || skip "$card has no crtc-0/crc directory"
[ -e "$crc/control" ] || skip "$crc/control is missing (no CRC source registered)"
[ -r "$crc/source" ] || skip "$crc/source is missing"
[ -r "$card/sm750_scanout" ] || skip "$card/sm750_scanout is missing"

trap cleanup EXIT

sources=$(cat "$crc/source")
case " $sources " in
*" scanout "*)
	pass "crc source list exposes scanout: $sources"
	;;
*)
	fail "crc source list does not expose scanout: $sources"
	;;
esac

# libdrm headers and .pc are not installed system-wide on the reference host.
# The documented rootless tree (docs/ENVIRONMENT.md section 4) is the fallback;
# SM750_LIBDRM_DIR overrides its location.
if ! pkg-config --exists libdrm 2>/dev/null; then
	libdrm_dir=${SM750_LIBDRM_DIR:-/mega/tmp/sm750/t3/libdrm}
	if [ -d "$libdrm_dir/usr/lib64/pkgconfig" ]; then
		PKG_CONFIG_PATH=$libdrm_dir/usr/lib64/pkgconfig
		PKG_CONFIG_SYSROOT_DIR=$libdrm_dir
		LD_LIBRARY_PATH=$libdrm_dir/usr/lib64
		export PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR LD_LIBRARY_PATH
	fi
fi
command -v pkg-config >/dev/null 2>&1 ||
	skip "pkg-config is required to build tests/scanout-pattern.c"
pkg-config --exists libdrm 2>/dev/null ||
	skip "libdrm development files are missing (docs/ENVIRONMENT.md section 4)"

pattern=$here/build/scanout-pattern
mkdir -p "$here/build" || fail "cannot create $here/build"
# The shape of this compile matches tests/check-vblank in the Makefile.
/usr/bin/gcc -O2 -Wall -Wextra -Werror $(pkg-config --cflags libdrm) \
	-o "$pattern" "$here/tests/scanout-pattern.c" \
	$(pkg-config --libs libdrm) 2>"$here/build/scanout-pattern.log" || {
	tail -n 5 "$here/build/scanout-pattern.log" >&2
	fail "cannot build tests/scanout-pattern.c"
}

card_node=
for dev in /dev/dri/card*; do
	[ -e "$dev" ] || continue
	vendor=/sys/class/drm/$(basename "$dev")/device/vendor
	[ -r "$vendor" ] || continue
	[ "$(cat "$vendor")" = "0x126f" ] || continue
	card_node=$dev
	break
done
[ -n "$card_node" ] || skip "no /dev/dri/card* backed by the SM750 (PCI vendor 0x126f)"

# draw <black|white>: one SETCRTC with a solid frame. Exit 3 means the process
# could not become DRM master, which is an environment condition.
draw() {
	out=$("$pattern" "$card_node" "$1" 2>&1) && rc=0 || rc=$?
	case $rc in
	0) echo "$out" ;;
	3) skip "cannot become DRM master on $card_node: $out" ;;
	*) fail "cannot draw a $1 frame on $card_node: $out" ;;
	esac
}

# A sample is a fresh open of crc/data, so it only contains new frames. The
# read blocks until entries arrive, hence the timeout plus head.
sample() {
	timeout 20 cat "$crc/data" 2>/dev/null | head -n "$1"
}

dump_field() {
	head -n 8 "$card/sm750_scanout" | awk -v key="$1" '$1 == key { print $2; exit }'
}

# Returns "count uniq crc" for a sample on stdin.
summarize() {
	awk -v n=0 '
		{ n++; last = $NF; seen[$NF] = 1 }
		END {
			u = 0
			for (k in seen)
				u++
			print n, u + 0, last
		}'
}

# Enable the source. Failure here means the CRTC cannot start vblanks, which is
# the "no DRM master / display off" case.
if ! printf 'scanout' > "$crc/control" 2>/dev/null; then
	skip "cannot enable the scanout CRC source (CRTC-0 not active: no DRM master or display off)"
fi

draw black
sleep 1
sample 4 >/dev/null

stats=$(sample 12 | summarize)
set -- $stats
[ $# -eq 3 ] || fail "CRC data yielded no entries in 20 s"
count=$1
uniq=$2
black_crc=$3
[ "$count" -eq 12 ] || fail "CRC data yielded $count of 12 lines in 20 s"
[ "$uniq" -eq 1 ] || fail "CRC is not stable for a static frame: $uniq distinct values in 12 frames"
pass "CRC entries arrive and are stable over 12 static frames (crc $black_crc)"

dump_length=$(dump_field length)
dump_nonzero=$(dump_field nonzero)
dump_crc=$(dump_field crc32)
[ -n "$dump_length" ] && [ "$dump_length" -gt 0 ] ||
	fail "sm750_scanout reported no bounded window"
case $dump_crc in
0x*) ;;
*) fail "sm750_scanout has no crc32 summary" ;;
esac
[ "${dump_crc#0x}" = "$black_crc" ] ||
	fail "dump crc32 $dump_crc does not match the CRC path $black_crc"
pass "dump and CRC path agree for a black frame (offset $(dump_field offset), length $dump_length, crc $black_crc)"

draw white
sleep 1
sample 4 >/dev/null

stats=$(sample 12 | summarize)
set -- $stats
[ $# -eq 3 ] || fail "CRC data yielded no entries after the frame change"
count=$1
uniq=$2
white_crc=$3
[ "$count" -eq 12 ] || fail "CRC data yielded $count of 12 lines after the frame change"
[ "$uniq" -eq 1 ] || fail "CRC is not stable for a static white frame: $uniq distinct values in 12 frames"
[ "$white_crc" != "$black_crc" ] ||
	fail "CRC did not change between a black and a white frame ($white_crc)"
pass "CRC changes with frame content (black $black_crc, white $white_crc)"

white_nonzero=$(dump_field nonzero)
dump_crc=$(dump_field crc32)
[ "${dump_crc#0x}" = "$white_crc" ] ||
	fail "dump crc32 $dump_crc does not match the CRC path $white_crc"
[ "$white_nonzero" -ge "$dump_nonzero" ] ||
	fail "nonzero scanout bytes decreased from black ($dump_nonzero) to white ($white_nonzero)"
[ "$white_nonzero" -eq "$dump_length" ] ||
	fail "white frame has $white_nonzero of $dump_length nonzero scanout bytes"
pass "nonzero scanout bytes are monotonic (black $dump_nonzero, white $white_nonzero of $dump_length)"

pass "scanout CRC source and sm750_scanout dump agree ($card, drawn through $card_node)"
