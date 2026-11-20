#!/usr/bin/env bash
# Copyright (c) 2026 SM750 DRM contributors
# SPDX-License-Identifier: GPL-2.0
#
# T37 gate: the driver never leaves the panel dead-black when no client
# produces a frame. The test card is a bounded fallback, not a display path:
# it must not paint into a softscaled (2048-pitch) window, must not exceed the
# VRAM left after the scanout offset, and must be overwritten the moment a real
# client commit arrives. The gate therefore requires:
#   - the test_pattern / test_pattern_period_ms parameters with their defaults
#     and their documented values,
#   - a painter that pads every row to the scanout pitch and carries the
#     colour bars, grayscale staircase, grid, sweep, crosshair, circle and
#     border, in both bpp encodings,
#   - the paint call inside sm750_pipe_enable() after sm750_program_mode(),
#     after the blank-frame diagnostic and before drm_crtc_vblank_on(),
#   - rotation as a delayed work that is cancelled on disable, on the first
#     client update and on remove, advances its phase, and logs nothing per
#     tick.
#
# Usage: tests/check-test-pattern.sh [source file]
#        tests/check-test-pattern.sh --single [source file]   (no self-test)

set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

mode=full
if [ "${1:-}" = "--single" ]; then
	mode=single
	shift
fi
source_file=${1:-$project_dir/src/sm750_drm.c}

fail() {
	echo "Test pattern: $1" >&2
	exit 1
}

# Print a top-level function body (definition line to the closing brace).
fn_body() {
	local file=$1
	local head=$2

	awk -v head="$head" '
		index($0, head) == 1 { in_fn = 1 }
		in_fn { print }
		in_fn && /^}/ { exit }' "$file"
}

# Line number of the first match of $2 inside text $1, empty when absent.
first_line() {
	local text=$1
	local pattern=$2

	{ grep -n -F "$pattern" <<<"$text" || true; } | head -n 1 | cut -d: -f1
}

count_in() {
	local text=$1
	local pattern=$2

	{ grep -c -F "$pattern" <<<"$text" || true; }
}

require() {
	local text=$1
	local pattern=$2
	local why=$3

	grep -F -- "$pattern" <<<"$text" >/dev/null || fail "$why"
}

# The parameters: writable, with an auto default and the documented help.
check_param() {
	local file=$1

	grep -F 'static char *test_pattern = "auto";' "$file" >/dev/null ||
		fail "$file: test_pattern does not default to auto"
	grep -F 'module_param(test_pattern, charp, 0644);' "$file" >/dev/null ||
		fail "$file: test_pattern is not a writable module parameter"
	grep -F 'static unsigned int test_pattern_period_ms = 5000;' "$file" >/dev/null ||
		fail "$file: test_pattern_period_ms does not default to 5000"
	grep -F 'module_param(test_pattern_period_ms, uint, 0644);' "$file" >/dev/null ||
		fail "$file: test_pattern_period_ms is not a writable module parameter"
	grep -F 'off, auto (default), or always' "$file" >/dev/null ||
		fail "the test_pattern help does not document the three modes"
	grep -F 'default 5000' "$file" >/dev/null ||
		fail "the test_pattern_period_ms help does not document the default"
}

# The painter: bounded, pitch-padded, and complete.
check_painter() {
	local file=$1
	local body put

	body=$(fn_body "$file" 'static void sm750_paint_test_pattern(')
	[ -n "$body" ] || fail "$file: sm750_paint_test_pattern not found"
	require "$body" 'sdev->softscale_active' \
		"the painter does not skip a softscaled window"
	require "$body" 'if (!line || !pitch)' \
		"the painter does not skip without a line buffer or pitch"
	require "$body" 'SM750_TEST_MIN_WIDTH' \
		"the painter has no minimum width"
	require "$body" 'SM750_TEST_MIN_HEIGHT' \
		"the painter has no minimum height"
	require "$body" 'sdev->vram_size - sdev->scanout_offset' \
		"the painter does not bound the frame to the VRAM left"
	require "$body" 'SM750_TEST_LINE_BYTES' \
		"the painter does not bound the pitch to its line buffer"
	require "$body" 'memcpy_toio(sdev->vram + sdev->scanout_offset' \
		"the painter does not write through the scanout offset"
	require "$body" '(u64)y * pitch, line, pitch);' \
		"the painter does not copy a full pitch-padded row"
	require "$body" 'memset((u8 *)line + width * cpp,' \
		"the painter does not pad the row to the pitch"
	require "$body" 'sdev->shadow_source_snapshot_valid = false;' \
		"the painter leaves the shadow snapshot valid"
	require "$body" 'sdev->rgb565_scanout_snapshot_valid = false;' \
		"the painter leaves the RGB565 snapshot valid"

	require "$body" 'SM750_TEST_BAR_COUNT - 1' \
		"the painter has no colour bars"
	require "$body" 'SM750_TEST_GRAY_STEPS' \
		"the painter has no grayscale staircase"
	require "$body" 'x % grid_x' \
		"the painter has no vertical grid lines"
	require "$body" 'y % grid_y' \
		"the painter has no horizontal grid lines"
	require "$body" 'SM750_TEST_SWEEP_WIDTH' \
		"the painter has no rotation sweep"
	require "$body" 'sm750_test_pattern_circle(radius, half)' \
		"the painter has no circle"
	require "$body" 'dy <= 1 && dx <= radius' \
		"the painter has no horizontal crosshair"
	require "$body" 'dx <= 1 && dy <= cy' \
		"the painter has no vertical crosshair"
	require "$body" 'x == width - 3' \
		"the painter has no inset frame border"
	require "$body" 'sdev->test_pattern_phase' \
		"the painter does not rotate the palette"

	put=$(fn_body "$file" 'static void sm750_test_pattern_put(')
	[ -n "$put" ] || fail "$file: sm750_test_pattern_put not found"
	require "$put" '((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)' \
		"the RGB565 encoding is wrong or missing"
	require "$put" '((u32 *)line)[x] = rgb;' \
		"the 32 bpp encoding is missing"
}

# The call site: after programming the mode, one sample, before vblank_on.
check_call() {
	local file=$1
	local body paint_line program_line blank_line vblank_line

	body=$(fn_body "$file" 'static void sm750_pipe_enable(')
	[ -n "$body" ] || fail "$file: sm750_pipe_enable not found"
	require "$body" 'painted a test card: no client has produced a frame (test_pattern=%s)\n' \
		"the paint message is not the documented line"
	require "$body" 'test_pattern_fresh = true;' \
		"the paint does not mark the enabling commit"
	require "$body" 'schedule_delayed_work(&sdev->test_pattern_work,' \
		"the paint does not start the rotation"

	[ "$(count_in "$body" 'sm750_shadow_frame_is_blank(')" -eq 1 ] ||
		fail "the blank frame is sampled more than once per enable"

	paint_line=$(first_line "$body" 'sm750_paint_test_pattern(sdev,')
	program_line=$(first_line "$body" 'sm750_program_mode(sdev,')
	blank_line=$(first_line "$body" 'console framebuffer is blank')
	vblank_line=$(first_line "$body" 'drm_crtc_vblank_on(')
	[ -n "$paint_line" ] || fail "sm750_pipe_enable never paints the test card"
	[ -n "$program_line" ] || fail "sm750_pipe_enable no longer programs the mode"
	[ -n "$blank_line" ] || fail "the blank-console diagnostic is gone"
	[ -n "$vblank_line" ] || fail "sm750_pipe_enable no longer turns vblank on"
	test "$paint_line" -gt "$program_line" ||
		fail "the test card is painted before sm750_program_mode()"
	test "$paint_line" -gt "$blank_line" ||
		fail "the test card is painted before the blank-frame diagnostic"
	test "$paint_line" -lt "$vblank_line" ||
		fail "the test card is painted after drm_crtc_vblank_on()"
}

# The rotation: a delayed work cancelled everywhere it must be.
check_rotation() {
	local file=$1
	local work period disable update remove cancel_line damage_line

	grep -F 'struct delayed_work test_pattern_work;' "$file" >/dev/null ||
		fail "$file: the rotation has no delayed work"
	grep -F 'INIT_DELAYED_WORK(&sdev->test_pattern_work, sm750_test_pattern_work);' \
		"$file" >/dev/null ||
		fail "the rotation work is never initialised"

	work=$(fn_body "$file" 'static void sm750_test_pattern_work(')
	[ -n "$work" ] || fail "$file: sm750_test_pattern_work not found"
	require "$work" 'sdev->test_pattern_active && sdev->scanout_pitch' \
		"a tick does not re-check the live state"
	require "$work" 'sdev->test_pattern_phase++;' \
		"a tick does not advance the palette phase"
	require "$work" 'mutex_lock(&sdev->mode_lock);' \
		"a tick does not serialise against the mode lock"
	require "$work" 'if (painted && period)' \
		"a tick re-arms without a live card or a period"
	if grep -qF 'drm_info(' <<<"$work"; then
		fail "a rotation tick logs with drm_info"
	fi

	period=$(fn_body "$file" 'static unsigned int sm750_test_pattern_period(')
	[ -n "$period" ] || fail "$file: sm750_test_pattern_period not found"
	require "$period" 'SM750_TEST_PERIOD_MIN_MS' \
		"the period is not clamped at the bottom"
	require "$period" 'SM750_TEST_PERIOD_MAX_MS' \
		"the period is not clamped at the top"
	require "$period" 'drm_info_once' \
		"a clamped period is not reported once"

	disable=$(fn_body "$file" 'static void sm750_pipe_disable(')
	[ -n "$disable" ] || fail "$file: sm750_pipe_disable not found"
	require "$disable" 'sm750_test_pattern_cancel(sdev);' \
		"sm750_pipe_disable leaves the rotation running"

	update=$(fn_body "$file" 'static void sm750_pipe_update(')
	[ -n "$update" ] || fail "$file: sm750_pipe_update not found"
	require "$update" 'sm750_test_pattern_cancel(sdev);' \
		"a client commit does not stop the rotation"
	require "$update" 'if (sdev->test_pattern_fresh)' \
		"the enabling commit's own update overwrites the fresh card"
	cancel_line=$(first_line "$update" 'sm750_test_pattern_cancel(sdev);')
	damage_line=$(first_line "$update" 'sm750_async_queue_damage(sdev,')
	[ -n "$damage_line" ] || fail "sm750_pipe_update no longer queues damage"
	test "$cancel_line" -lt "$damage_line" ||
		fail "the rotation is stopped only after the upload is queued"

	remove=$(fn_body "$file" 'static void sm750_pci_remove(')
	[ -n "$remove" ] || fail "$file: sm750_pci_remove not found"
	require "$remove" 'sm750_test_pattern_cancel(sdev);' \
		"the remove path leaves the rotation running"
}

check_param "$source_file"
check_painter "$source_file"
check_call "$source_file"
check_rotation "$source_file"
echo "Test-pattern fallback checks passed: $source_file"

if [ "$mode" = single ]; then
	exit 0
fi

scratch=$(mktemp -d "${TMPDIR}/sm750-test-pattern.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

# Delete every line matching $3 inside the top-level function starting at $2.
plant_delete_in_fn() {
	local file=$1 head=$2 pattern=$3

	awk -v head="$head" -v pattern="$pattern" '
		index($0, head) == 1 { in_fn = 1 }
		in_fn && index($0, pattern) { next }
		{ print }
		in_fn && /^}/ { in_fn = 0 }' "$file" >"$file.tmp"
	mv "$file.tmp" "$file"
}

# (a) The default says off while the help still promises auto.
plant_default_off() {
	sed -i 's/static char \*test_pattern = "auto";/static char *test_pattern = "off";/' "$1"
}
# (b) A card painted before the mode is programmed.
plant_paint_early() {
	awk '
		index($0, "\tret = sm750_program_mode(sdev,") == 1 && !done {
			print "\t\tsm750_paint_test_pattern(sdev, 1, 1);"
			done = 1
		}
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (c) No softscale guard: the card would fight the softscaler.
plant_no_softscale_guard() {
	awk '
		index($0, "static void sm750_paint_test_pattern(") == 1 { in_fn = 1 }
		in_fn && index($0, "if (sdev->softscale_active)") { skip = 1; next }
		skip { skip = 0; next }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (d) Rows copied by width instead of pitch: the card shears on any padding.
plant_memcpy_no_pitch() {
	sed -i 's/(u64)y \* pitch, line, pitch);/(u64)y * pitch, line, width * cpp);/' "$1"
}
# (e) The rotation survives a pipe disable.
plant_no_cancel_disable() {
	plant_delete_in_fn "$1" 'static void sm750_pipe_disable(' \
		'sm750_test_pattern_cancel(sdev);'
}
# (f) A client commit no longer stops the rotation.
plant_no_cancel_update() {
	awk '
		index($0, "if (sdev->test_pattern_active)") { skip = 1; next }
		skip { skip = 0; next }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (g) A tick that never advances: the same palette, forever.
plant_no_phase() {
	plant_delete_in_fn "$1" 'static void sm750_test_pattern_work(' \
		'sdev->test_pattern_phase++;'
}
# (h) A per-tick log line: a diagnostic path that floods the ring buffer.
plant_tick_log() {
	awk '
		index($0, "bool painted = false;") > 0 && !done {
			print
			print "\tdrm_info(&sdev->drm, \"tick\\n\");"
			done = 1
			next
		}
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (i) The period defaults to zero while the help still promises 5000.
plant_period_zero() {
	sed -i 's/static unsigned int test_pattern_period_ms = 5000;/static unsigned int test_pattern_period_ms = 0;/' "$1"
}

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

control default_off plant_default_off
control paint_before_program_mode plant_paint_early
control no_softscale_guard plant_no_softscale_guard
control memcpy_without_pitch plant_memcpy_no_pitch
control no_cancel_on_disable plant_no_cancel_disable
control no_cancel_on_update plant_no_cancel_update
control phase_never_advances plant_no_phase
control per_tick_logging plant_tick_log
control period_default_zero plant_period_zero

echo "Test-pattern fallback checks passed"
