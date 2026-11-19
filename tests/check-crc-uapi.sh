#!/usr/bin/env bash
# Copyright (c) 2026 SM750 DRM contributors
# SPDX-License-Identifier: GPL-2.0
#
# T26 gate: the driver must publish the DRM CRC uapi itself. DRM only creates
# crtc-N/crc/ when the CRTC funcs carry the three CRC callbacks at
# drm_dev_register() time, and this driver swaps the funcs after
# drm_simple_display_pipe_init(), so the files are hosted by the driver.
#
# Usage: tests/check-crc-uapi.sh [source file]
#        tests/check-crc-uapi.sh --single [source file]   (no self-test)

set -euo pipefail

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

mode=full
if [ "${1:-}" = "--single" ]; then
	mode=single
	shift
fi
source_file=${1:-$project_dir/src/sm750_drm.c}

fail() {
	echo "CRC uapi: $1" >&2
	exit 1
}

check_file() {
	local file=$1
	local funcs hook callback name

	funcs=$(awk '/^static const struct drm_crtc_funcs sm750_crtc_funcs = \{/ {
			in_funcs = 1
		}
		in_funcs { print }
		in_funcs && /^\};/ { exit }' "$file")
	[ -n "$funcs" ] || fail "$file: sm750_crtc_funcs not found"

	for callback in get_crc_sources verify_crc_source set_crc_source; do
		grep -F ".$callback = " <<<"$funcs" >/dev/null ||
			fail "sm750_crtc_funcs lacks .$callback"
	done

	# The files are created by one helper so that both the debugfs hook and
	# the CRTC late_register callback can reach it.
	grep -F 'debugfs_create_dir("crc", crtc->debugfs_entry)' "$file" >/dev/null ||
		fail "no crc debugfs directory is created"
	for name in source control data; do
		grep -F "debugfs_create_file(\"$name\"" "$file" >/dev/null ||
			fail "no crc/$name debugfs file is created"
	done

	hook=$(awk '/^static void sm750_regs_debugfs_add\(/ {
			in_hook = 1
		}
		in_hook { print }
		in_hook && /^}/ { exit }' "$file")
	[ -n "$hook" ] || fail "$file: sm750_regs_debugfs_add not found"
	grep -F 'sm750_crc_debugfs_create(minor->dev);' <<<"$hook" >/dev/null ||
		fail "sm750_regs_debugfs_add does not host the crc files"

	# crc/data: the count line first, then entry lines. Checked in the
	# order userspace reads them.
	data=$(awk '/^static ssize_t sm750_crc_data_read\(/ {
			in_data = 1
		}
		in_data { print }
		in_data && /^}/ { exit }' "$file")
	[ -n "$data" ] || fail "$file: sm750_crc_data_read not found"

	# No 0x prefix anywhere: IGT parses "%u %x".
	if grep -F '0x' <<<"$data" >/dev/null; then
		fail "crc/data carries a 0x prefix"
	fi

	# Decimal frame counter first, then one hex CRC, one entry per read.
	grep -F '"%u %08x\n"' <<<"$data" >/dev/null ||
		fail "the crc/data entry format is missing or malformed"

	# First read after open is the value count, once per open.
	grep -F '#define SM750_CRC_COUNT_LINE "1\n"' "$file" >/dev/null ||
		fail "no CRC count-line constant"
	grep -F 'SM750_CRC_COUNT_LINE' <<<"$data" >/dev/null ||
		fail "crc/data never emits the count line"
	grep -F 'crc_count_sent' <<<"$data" >/dev/null ||
		fail "crc/data does not gate the count line per open"

	grep -F '#define SM750_CRC_ENTRIES 128' "$file" >/dev/null ||
		fail "the CRC ring is not 128 entries deep"
}

check_file "$source_file"
echo "CRC uapi check passed: $source_file"

if [ "$mode" = single ]; then
	exit 0
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/sm750-crc-uapi.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

plant_no_set_crc() { sed -i '/\.set_crc_source = sm750_crtc_set_crc_source,/d' "$1"; }
plant_no_control() { sed -i 's/debugfs_create_file("control"/debugfs_create_file("ctl"/' "$1"; }
plant_no_count_line() { sed -i '/crc_count_sent/d' "$1"; }
plant_frame_second() { sed -i 's/"%u %08x\\n"/"%08x %u\\n"/' "$1"; }
plant_hex_prefix() { sed -i 's/"%u %08x\\n"/"%u 0x%08x\\n"/' "$1"; }
plant_small_ring() { sed -i 's/#define SM750_CRC_ENTRIES 128/#define SM750_CRC_ENTRIES 64/' "$1"; }

# Every planted defect must be caught, otherwise the gate is decorative.
control() {
	local name=$1
	local planted=$scratch/sm750_drm.c
	local err=$scratch/stderr

	cp "$source_file" "$planted"
	shift
	"$@" "$planted"
	if "$0" --single "$planted" >/dev/null 2>"$err"; then
		fail "negative control $name was not rejected"
	fi
	echo "negative control $name: rejected (exit 1): $(head -n 1 "$err")"
}

control set_crc_source plant_no_set_crc
control control_file plant_no_control
control count_line plant_no_count_line
control frame_field plant_frame_second
control hex_prefix plant_hex_prefix
control ring_depth plant_small_ring

echo "CRC uapi gate and negative controls passed"
