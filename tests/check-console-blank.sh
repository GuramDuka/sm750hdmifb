#!/usr/bin/env bash
# Copyright (c) 2026 SM750 DRM contributors
# SPDX-License-Identifier: GPL-2.0
#
# T31 gate: the driver names the blank-console precondition instead of letting
# an all-zero panel be read as a display-path regression. fbcon only paints the
# fbdev client's buffer while the foreground VT is in KD_TEXT (drivers/tty/vt/
# vt.c do_con_write drops console output when vc_mode is KD_GRAPHICS), so a
# module load on a graphical VT leaves that buffer blank and the panel scans
# zeros with nothing else wrong. The gate therefore requires:
#   - sm750_shadow_frame_is_blank() sampling the source on a coarse grid and
#     bailing out on an unusable map or geometry,
#   - the exact diagnostic text, emitted inside sm750_pipe_enable() after
#     sm750_program_mode() and behind a once-per-load latch,
#   - a diagnostic that cannot change behaviour (no return, no goto).
#
# Usage: tests/check-console-blank.sh [source file]
#        tests/check-console-blank.sh --single [source file]   (no self-test)

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
	echo "Console blank: $1" >&2
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

# The sampler: bounded, allocation-free, and honest about unknown input.
check_helper() {
	local file=$1
	local body

	body=$(fn_body "$file" 'static bool sm750_shadow_frame_is_blank(')
	[ -n "$body" ] ||
		fail "$file: sm750_shadow_frame_is_blank not found"
	grep -F 'const struct drm_shadow_plane_state *shadow' <<<"$body" >/dev/null ||
		fail "the blank-frame helper does not take the shadow plane state"
	grep -F 'iosys_map_is_null(&shadow->data[0])' <<<"$body" >/dev/null ||
		fail "the blank-frame helper samples an unmapped buffer"
	grep -F 'iosys_map_memcpy_from(&pixel, &shadow->data[0],' <<<"$body" >/dev/null ||
		fail "the blank-frame helper does not read the shadow buffer"
	grep -F 'y += 16' <<<"$body" >/dev/null ||
		fail "the blank-frame helper does not sample on a coarse row stride"
	grep -F 'x += 16' <<<"$body" >/dev/null ||
		fail "the blank-frame helper does not sample on a coarse column stride"
	grep -F 'if (pixel)' <<<"$body" >/dev/null ||
		fail "the blank-frame helper does not stop at the first painted pixel"
	grep -F 'return true;' <<<"$body" >/dev/null ||
		fail "the blank-frame helper cannot report a blank frame"
	# A kmalloc here would run in the commit tail; the helper must stay static.
	if grep -qE '\b(kmalloc|kzalloc|vmalloc|kvmalloc)\b' <<<"$body"; then
		fail "the blank-frame helper allocates"
	fi
	grep -F 'u32 shadow_source_pitch;' "$file" >/dev/null ||
		fail "$file: the shadow source pitch is not recorded"
}

# The emit point: after the mode is programmed, once, and inert.
check_emit() {
	local file=$1
	local body block msg_line program_line

	body=$(fn_body "$file" 'static void sm750_pipe_enable(')
	[ -n "$body" ] || fail "$file: sm750_pipe_enable not found"
	grep -F 'console framebuffer is blank' <<<"$body" >/dev/null ||
		fail "sm750_pipe_enable never names the blank console buffer"
	msg_line=$(first_line "$body" 'console framebuffer is blank')
	program_line=$(first_line "$body" 'sm750_program_mode(sdev,')
	[ -n "$program_line" ] ||
		fail "sm750_pipe_enable no longer programs the mode"
	test "$msg_line" -gt "$program_line" ||
		fail "the blank-console diagnostic is emitted before sm750_program_mode()"

	# The diagnostic must be one drm_info() with the full explanation: a
	# terse line would read as a defect report rather than a precondition.
	grep -F 'is the foreground VT in KD_TEXT?' <<<"$body" >/dev/null ||
		fail "the diagnostic does not name the KD_TEXT precondition"
	grep -F 'static bool blank_frame_reported;' <<<"$body" >/dev/null ||
		fail "the diagnostic has no once-per-module-load latch"
	grep -F '!blank_frame_reported' <<<"$body" >/dev/null ||
		fail "the latch never guards the diagnostic"
	grep -F 'blank_frame_reported = true;' <<<"$body" >/dev/null ||
		fail "the latch is never set"

	# Behaviour: the block may only log. Any control flow here would let a
	# blank frame skip an upload or fail a commit.
	block=$(awk '
		/if \(sdev->shadow_scanout && plane_state->fb &&/ { in_block = 1 }
		in_block { print }
		in_block && /^\t\t\}$/ { exit }' <<<"$body")
	[ -n "$block" ] || fail "the blank-console guard is gone"
	if grep -qE '\b(return|goto)\b' <<<"$block"; then
		fail "the blank-console guard changes behaviour (return/goto)"
	fi
	if grep -qE '^\s*(drm_atomic_set|sm750_shadow_rect|sm750_shadow_upload|sm750_shadow_commit|sm750_present|sm750_program_mode)' \
		<<<"$block"; then
		fail "the blank-console guard calls into the upload path"
	fi

	# Nothing to sample outside the shadow path, and no leftover state.
	body=$(fn_body "$file" 'static void sm750_pipe_disable(')
	[ -n "$body" ] || fail "$file: sm750_pipe_disable not found"
	grep -F 'sdev->shadow_source_pitch = 0;' <<<"$body" >/dev/null ||
		fail "sm750_pipe_disable keeps a stale shadow source pitch"
}

check_helper "$source_file"
check_emit "$source_file"
echo "Console blank-frame diagnostics check passed: $source_file"

if [ "$mode" = single ]; then
	exit 0
fi

scratch=$(mktemp -d "${TMPDIR}/sm750-console-blank.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

# The defect this gate exists for: a blank panel with no explanation at all.
plant_no_message() {
	sed -i '/console framebuffer is blank/d' "$1"
}
# A diagnostic that runs before the mode is programmed describes nothing.
plant_emit_early() {
	local block

	block=$(awk '
		index($0, "static void sm750_pipe_enable(") == 1 { in_fn = 1 }
		in_fn && index($0, "\t\tif (sdev->shadow_scanout && plane_state->fb &&") == 1 { hold = 1 }
		hold {
			print
			if (index($0, "\t\t}") == 1)
				hold = 0
		}
		in_fn && hold == 0 && block_done { exit }
		in_fn && hold == 1 { block_done = 1 }' "$1")
	# Re-insert the same guard above the call that programs the mode.
	BLOCK=$block awk '
		index($0, "\tret = sm750_program_mode(sdev,") == 1 && !done {
			printf "%s", ENVIRON["BLOCK"]
			done = 1
		}
		{ print }' "$1" >"$1.early"
	mv "$1.early" "$1"
}
# Sampling an unmapped buffer would fault in the commit tail.
plant_no_bail() {
	sed -i '/iosys_map_is_null(&shadow->data\[0\])/d' "$1"
}
# Without the latch the line prints on every modeset.
plant_no_latch() {
	sed -i 's/!blank_frame_reported &&//' "$1"
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

control no_message plant_no_message
control emit_before_program_mode plant_emit_early
control no_map_bail plant_no_bail
control no_warn_once_latch plant_no_latch

echo "Console blank-frame diagnostics checks passed"