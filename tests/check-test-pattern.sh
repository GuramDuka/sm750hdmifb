#!/usr/bin/env bash
# Copyright (c) 2026 SM750 DRM contributors
# SPDX-License-Identifier: GPL-2.0
#
# T37/T38 gate: the driver never leaves the panel dead-black when no client
# produces a frame. The test card is a bounded fallback, not a display path:
# it must not paint into a softscaled (2048-pitch) window, must not exceed the
# VRAM left after the scanout offset, and must be overwritten the moment a real
# client commit arrives. The gate therefore requires:
#   - the test_pattern / test_pattern_period_ms / test_pattern_anim_ms
#     parameters with their defaults, their widths and their documented values,
#   - a guard set shared by the full painter and the animation tick, through
#     sm750_test_pattern_ctx_init(),
#   - a background pixel function that carries the colour bars, grayscale
#     staircase, grid, sweep, crosshair, circle and border, in both bpp
#     encodings,
#   - a rectangle writer that pads full rows to the scanout pitch and writes a
#     partial row from its own column offset, so a tick costs a bounding box
#     rather than a frame,
#   - a disc that moves, reflects off the inner border and changes colour only
#     on a bounce,
#   - the paint call inside sm750_pipe_enable() after sm750_program_mode(),
#     after the blank-frame diagnostic and before drm_crtc_vblank_on(),
#   - animation as a delayed work that is cancelled on disable, on the first
#     client update and on remove, advances its phase on its own period, and
#     logs nothing per tick,
#   - a scanout CRC source owning the window: arming it cancels the card, the
#     paint decision and the tick both refuse to paint while it is armed, and
#     nothing paints over a userspace master's legitimately black frame
#     (docs/evidence/runtime/24-test-card-crc-conflict-rca.txt, R1 and R2).
# There is no one-shot upload skip: the RCA proved that flag swallowed the
# client's first frame instead of the enabling commit's own upload.
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

# The parameters: writable, with the documented defaults and help.
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
	grep -F 'static unsigned int test_pattern_anim_ms = 40;' "$file" >/dev/null ||
		fail "$file: test_pattern_anim_ms does not default to 40"
	grep -F 'module_param(test_pattern_anim_ms, uint, 0644);' "$file" >/dev/null ||
		fail "$file: test_pattern_anim_ms is not a writable module parameter"
	grep -F 'off, auto (default), or always' "$file" >/dev/null ||
		fail "the test_pattern help does not document the three modes"
	grep -F 'default 5000' "$file" >/dev/null ||
		fail "the test_pattern_period_ms help does not document the default"
	grep -F 'default 40, clamped to 10-1000' "$file" >/dev/null ||
		fail "the test_pattern_anim_ms help does not document the default and clamp"
}

# The shared guard set: both drawing paths refuse the same frames.
check_guards() {
	local file=$1
	local body

	body=$(fn_body "$file" 'static bool sm750_test_pattern_ctx_init(')
	[ -n "$body" ] || fail "$file: sm750_test_pattern_ctx_init not found"
	require "$body" 'sdev->softscale_active' \
		"the painter does not skip a softscaled window"
	require "$body" 'if (!sdev->test_pattern_line || !sdev->test_pattern_half || !pitch)' \
		"the painter does not skip without its buffers or pitch"
	require "$body" 'SM750_TEST_MIN_WIDTH' \
		"the painter has no minimum width"
	require "$body" 'SM750_TEST_MIN_HEIGHT' \
		"the painter has no minimum height"
	require "$body" 'sdev->vram_size - sdev->scanout_offset' \
		"the painter does not bound the frame to the VRAM left"
	require "$body" 'SM750_TEST_LINE_BYTES' \
		"the painter does not bound the pitch to its line buffer"
	require "$body" 'sdev->test_pattern_phase' \
		"the painter does not rotate the palette"
}

# The card content: pure geometry, identical in both bpp encodings.
check_pixel() {
	local file=$1
	local body put

	body=$(fn_body "$file" 'static u32 sm750_test_pattern_pixel(')
	[ -n "$body" ] || fail "$file: sm750_test_pattern_pixel not found"
	require "$body" 'SM750_TEST_BAR_COUNT - 1' \
		"the painter has no colour bars"
	require "$body" 'SM750_TEST_GRAY_STEPS' \
		"the painter has no grayscale staircase"
	require "$body" 'x % ctx->grid_x' \
		"the painter has no vertical grid lines"
	require "$body" 'y % ctx->grid_y' \
		"the painter has no horizontal grid lines"
	require "$body" 'SM750_TEST_SWEEP_WIDTH' \
		"the painter has no rotation sweep"
	require "$body" 'dy <= 1 && dx <= ctx->radius' \
		"the painter has no horizontal crosshair"
	require "$body" 'dx <= 1 && dy <= ctx->cy' \
		"the painter has no vertical crosshair"
	require "$body" 'ctx->half[dy]' \
		"the painter has no circle outline"
	require "$body" 'x == ctx->width - 3' \
		"the painter has no inset frame border"

	put=$(fn_body "$file" 'static void sm750_test_pattern_put(')
	[ -n "$put" ] || fail "$file: sm750_test_pattern_put not found"
	require "$put" '((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)' \
		"the RGB565 encoding is wrong or missing"
	require "$put" '((u32 *)line)[x] = rgb;' \
		"the 32 bpp encoding is missing"
}

# The rectangle writer: full rows padded to the pitch, partial rows from their
# own offset, and the snapshot invalidation that keeps a later upload complete.
check_rect() {
	local file=$1
	local body

	body=$(fn_body "$file" 'static void sm750_test_pattern_rect(')
	[ -n "$body" ] || fail "$file: sm750_test_pattern_rect not found"
	require "$body" 'memcpy_toio(sdev->vram + sdev->scanout_offset' \
		"the writer does not write through the scanout offset"
	require "$body" '(u64)y * pitch, line, pitch);' \
		"the writer does not copy a full pitch-padded row"
	require "$body" 'memset((u8 *)line + ctx->width * cpp,' \
		"the writer does not pad the row to the pitch"
	require "$body" '(u64)(x1 - x0) * cpp' \
		"the writer does not write a partial row from its own offset"
	require "$body" 'sdev->shadow_source_snapshot_valid = false;' \
		"the painter leaves the shadow snapshot valid"
	require "$body" 'sdev->rgb565_scanout_snapshot_valid = false;' \
		"the painter leaves the RGB565 snapshot valid"

	body=$(fn_body "$file" 'static void sm750_paint_test_pattern(')
	[ -n "$body" ] || fail "$file: sm750_paint_test_pattern not found"
	require "$body" 'sm750_test_pattern_ctx_init(sdev, width, height, &ctx)' \
		"the painter does not use the shared guard set"
	require "$body" 'sm750_test_pattern_rect(sdev, &ctx, 0, 0, width, height);' \
		"the painter does not draw the whole card through the rectangle writer"
}

# The disc: state, movement, reflection and a colour that changes on a bounce.
check_disc() {
	local file=$1
	local reset move tick pixel

	grep -F 'int test_pattern_disc_x;' "$file" >/dev/null ||
		fail "$file: the disc has no horizontal position"
	grep -F 'int test_pattern_disc_dx;' "$file" >/dev/null ||
		fail "$file: the disc has no horizontal velocity"
	grep -F 'u32 test_pattern_disc_colour;' "$file" >/dev/null ||
		fail "$file: the disc has no colour index"

	reset=$(fn_body "$file" 'static void sm750_test_pattern_disc_reset(')
	[ -n "$reset" ] || fail "$file: sm750_test_pattern_disc_reset not found"
	require "$reset" 'SM750_TEST_DISC_SPEED_X' \
		"the disc starts without a horizontal speed"
	require "$reset" 'SM750_TEST_DISC_SPEED_Y' \
		"the disc starts without a vertical speed"
	require "$reset" 'test_pattern_disc_colour = 0;' \
		"the disc does not start at the first colour"

	move=$(fn_body "$file" 'static void sm750_test_pattern_disc_move(')
	[ -n "$move" ] || fail "$file: sm750_test_pattern_disc_move not found"
	require "$move" '= -sdev->test_pattern_disc_dx;' \
		"the disc never reflects off a vertical edge"
	require "$move" '= -sdev->test_pattern_disc_dy;' \
		"the disc never reflects off a horizontal edge"
	require "$move" 'int min_x = 3 + reach;' \
		"the disc is not kept inside the inner border"
	require "$move" 'test_pattern_disc_colour++;' \
		"the disc colour never changes"

	tick=$(fn_body "$file" 'static void sm750_test_pattern_disc_tick(')
	[ -n "$tick" ] || fail "$file: sm750_test_pattern_disc_tick not found"
	[ "$(count_in "$tick" 'sm750_test_pattern_rect(sdev,')" -ge 2 ] ||
		fail "a tick does not erase the old bounding box and draw the new one"
	if grep -qF 'drm_info(' <<<"$tick"; then
		fail "an animation tick logs with drm_info"
	fi

	pixel=$(fn_body "$file" 'static u32 sm750_test_pattern_disc_pixel(')
	[ -n "$pixel" ] || fail "$file: sm750_test_pattern_disc_pixel not found"
	require "$pixel" 'ctx->disc_radius * ctx->disc_radius' \
		"the disc has no radius test"
	require "$pixel" 'inner * inner' \
		"the disc has no 2 px outline"
}

# The call site: after programming the mode, one sample, before vblank_on.
check_call() {
	local file=$1
	local body paint_line program_line blank_line vblank_line

	body=$(fn_body "$file" 'static void sm750_pipe_enable(')
	[ -n "$body" ] || fail "$file: sm750_pipe_enable not found"
	require "$body" 'painted a test card: no client has produced a frame (test_pattern=%s)\n' \
		"the paint message is not the documented line"
	require "$body" 'sm750_test_pattern_should_paint(sdev, blank)' \
		"the paint decision is not passed the device and the blank state"
	require "$body" 'sm750_test_pattern_disc_reset(sdev,' \
		"the paint does not start the disc"
	require "$body" 'schedule_delayed_work(&sdev->test_pattern_work,' \
		"the paint does not start the animation"

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

# The animation: a delayed work cancelled everywhere it must be, re-armed only
# while the card is live, rotating the palette on its own period.
check_rotation() {
	local file=$1
	local work period anim disable update remove cancel_line damage_line

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
	require "$work" 'sm750_test_pattern_disc_tick(sdev, &ctx);' \
		"an animation tick does not move the disc"
	require "$work" 'sdev->test_pattern_ticks' \
		"the palette rotation is not counted in ticks"
	require "$work" 'if (painted && delay)' \
		"a tick re-arms without a live card or a delay"
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

	anim=$(fn_body "$file" 'static unsigned int sm750_test_pattern_anim(')
	[ -n "$anim" ] || fail "$file: sm750_test_pattern_anim not found"
	require "$anim" 'SM750_TEST_ANIM_MIN_MS' \
		"the animation period is not clamped at the bottom"
	require "$anim" 'SM750_TEST_ANIM_MAX_MS' \
		"the animation period is not clamped at the top"
	require "$anim" 'drm_info_once' \
		"a clamped animation period is not reported once"

	disable=$(fn_body "$file" 'static void sm750_pipe_disable(')
	[ -n "$disable" ] || fail "$file: sm750_pipe_disable not found"
	require "$disable" 'sm750_test_pattern_cancel(sdev);' \
		"sm750_pipe_disable leaves the rotation running"

	update=$(fn_body "$file" 'static void sm750_pipe_update(')
	[ -n "$update" ] || fail "$file: sm750_pipe_update not found"
	require "$update" 'sm750_test_pattern_cancel(sdev);' \
		"a client commit does not stop the rotation"
	cancel_line=$(first_line "$update" 'sm750_test_pattern_cancel(sdev);')
	damage_line=$(first_line "$update" 'sm750_async_queue_damage(sdev,')
	skip_line=$(first_line "$update" 'goto event;')
	[ -n "$damage_line" ] || fail "sm750_pipe_update no longer queues damage"
	test "$cancel_line" -lt "$damage_line" ||
		fail "the rotation is stopped only after the upload is queued"
	# A skip before the cancel is the `test_pattern_fresh` defect the RCA
	# proved: it drops a real client's first frame and keeps the card alive.
	if [ -n "$skip_line" ] && [ "$skip_line" -lt "$cancel_line" ]; then
		fail "sm750_pipe_update can skip an upload before stopping the card"
	fi

	remove=$(fn_body "$file" 'static void sm750_pci_remove(')
	[ -n "$remove" ] || fail "$file: sm750_pci_remove not found"
	require "$remove" 'sm750_test_pattern_cancel(sdev);' \
		"the remove path leaves the rotation running"
}

# R1: a CRC source owns the scanout window; R2: an all-black frame from a
# userspace master is a picture, not an unpainted buffer.
check_crc_ownership() {
	local file=$1
	local should crc work update whole

	should=$(fn_body "$file" \
		'static bool sm750_test_pattern_should_paint(struct sm750_drm_device *sdev,')
	[ -n "$should" ] || fail "$file: sm750_test_pattern_should_paint not found"
	require "$should" 'if (READ_ONCE(sdev->crc_enabled))' \
		"the paint decision ignores an armed CRC source"
	require "$should" 'return !READ_ONCE(sdev->drm.master) && blank;' \
		"an unowned blank frame is not distinguished from a master's black frame"
	[ "$(first_line "$should" 'READ_ONCE(sdev->crc_enabled)')" -lt \
	  "$(first_line "$should" 'strcmp(test_pattern, "always")')" ] ||
		fail "test_pattern=always overrides an armed CRC source"

	crc=$(fn_body "$file" 'static int sm750_crc_enable(')
	[ -n "$crc" ] || fail "$file: sm750_crc_enable not found"
	require "$crc" 'sm750_test_pattern_cancel(sdev);' \
		"arming a CRC source leaves a paint in flight"
	[ "$(first_line "$crc" 'sm750_test_pattern_cancel(sdev);')" -lt \
	  "$(first_line "$crc" 'ret = sm750_crc_arm(sdev);')" ] ||
		fail "the card is stopped only after the CRC source is armed"

	work=$(fn_body "$file" 'static void sm750_test_pattern_work(')
	[ -n "$work" ] || fail "$file: sm750_test_pattern_work not found"
	require "$work" '!READ_ONCE(sdev->crc_enabled)' \
		"a tick that lost the race can still paint under an armed CRC source"
	[ "$(first_line "$work" '!READ_ONCE(sdev->crc_enabled)')" -lt \
	  "$(first_line "$work" 'sm750_test_pattern_rect(sdev,')" ] ||
		fail "the tick checks the CRC source only after painting"

	whole=$(cat "$file")
	if grep -qF 'test_pattern_fresh' <<<"$whole"; then
		fail "a one-shot upload skip is back: it drops the client's first frame"
	fi
}

check_param "$source_file"
check_guards "$source_file"
check_pixel "$source_file"
check_rect "$source_file"
check_disc "$source_file"
check_call "$source_file"
check_rotation "$source_file"
check_crc_ownership "$source_file"
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
		index($0, "static bool sm750_test_pattern_ctx_init(") == 1 { in_fn = 1 }
		in_fn && index($0, "if (sdev->softscale_active)") { skip = 1; next }
		skip { skip = 0; next }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (d) Rows copied by width instead of pitch: the card shears on any padding.
plant_memcpy_no_pitch() {
	sed -i 's/(u64)y \* pitch, line, pitch);/(u64)y * pitch, line, ctx->width * cpp);/' "$1"
}
# (e) The rotation survives a pipe disable.
plant_no_cancel_disable() {
	plant_delete_in_fn "$1" 'static void sm750_pipe_disable(' \
		'sm750_test_pattern_cancel(sdev);'
}
# (f) A client commit no longer stops the animation.
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
# (j) The animation defaults off: the panel goes back to a 5 s jump.
plant_anim_default_zero() {
	sed -i 's/static unsigned int test_pattern_anim_ms = 40;/static unsigned int test_pattern_anim_ms = 0;/' "$1"
}
# (k) The disc never reflects: it walks off the card and never returns.
plant_no_reflect() {
	sed -i 's/= -sdev->test_pattern_disc_dx;/= sdev->test_pattern_disc_dx;/;
		s/= -sdev->test_pattern_disc_dy;/= sdev->test_pattern_disc_dy;/' "$1"
}
# (l) A per-frame log inside the animation tick.
plant_disc_tick_log() {
	awk '
		index($0, "static void sm750_test_pattern_disc_tick(") == 1 { in_fn = 1 }
		in_fn && index($0, "\terase.disc = false;") { print; print "\tdrm_info(&sdev->drm, \"frame\\n\");"; next }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (m) A full-frame repaint on every animation tick: 4 MiB per frame at 25 fps.
plant_full_frame_tick() {
	sed -i 's/sm750_test_pattern_disc_tick(sdev, &ctx);/sm750_test_pattern_rect(sdev, \&ctx, 0, 0, ctx.width, ctx.height);/' "$1"
}

# (n) The paint decision ignores an armed CRC source: the reader and the
# painter race over the same window again.
plant_crc_ignored() {
	awk '
		index($0, "if (READ_ONCE(sdev->crc_enabled))") { skip = 1; next }
		skip { skip = 0; next }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (o) Arming the CRC source does not stop the card.
plant_crc_no_cancel() {
	plant_delete_in_fn "$1" 'static int sm750_crc_enable(' \
		'sm750_test_pattern_cancel(sdev);'
}
# (p) A tick waiting on mode_lock paints after the CRC source armed.
plant_tick_ignores_crc() {
	sed -i 's/\t    !READ_ONCE(sdev->crc_enabled)) {/\t    1) {/' "$1"
}
# (q) A one-shot skip in front of the cancel: the RCA's test_pattern_fresh.
plant_one_shot_skip() {
	awk '
		index($0, "\tif (sdev->test_pattern_active)") == 1 { in_blk = 1 }
		in_blk && !done {
			print
			print "\t\tsdev->test_pattern_active = false;"
			print "\t\tgoto event;"
			done = 1
			next
		}
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (r) The paint condition drops the master test: a black desktop is painted over.
plant_no_master_test() {
	sed -i 's/return !READ_ONCE(sdev->drm.master) && blank;/return blank;/' "$1"
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
control anim_default_zero plant_anim_default_zero
control velocity_never_inverted plant_no_reflect
control disc_frame_logging plant_disc_tick_log
control full_frame_tick plant_full_frame_tick
control crc_source_ignored plant_crc_ignored
control crc_arm_keeps_card plant_crc_no_cancel
control tick_ignores_crc plant_tick_ignores_crc
control one_shot_upload_skip plant_one_shot_skip
control black_master_frame plant_no_master_test

echo "Test-pattern fallback checks passed"
