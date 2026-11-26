#!/usr/bin/env bash
# Copyright (c) 2026 SM750 DRM contributors
# SPDX-License-Identifier: GPL-2.0
#
# T32 gate: the fbdev reconsole restore path.
#
# docs/evidence/runtime/20-fbdev-restore-timeout-rca.txt shows the failure as a
# chain, not a single call: a whole-register compare in the display transition
# wait never converges while the hardware rewrites the register, the resulting
# -ETIMEDOUT is discarded by the disable hook, and the enable hook's transition
# loop polls a fixed 10 ms budget that a vertical-sync handshake can exceed.
# The gate therefore requires:
#   - src/ddk750_display.c compares and re-pokes through a transition mask
#     inside the poll loop, and names want/mask/last on timeout,
#   - src/ddk750_mode.c derives its transition budget from the mode instead of a
#     fixed iteration cap, with the same masked compare and re-poke,
#   - sm750_pipe_disable() keeps the display-off result and warns with the
#     PANEL_DISPLAY_CTRL readback,
#   - the sm750_pipe_enable() fail path marks the pipe down instead of
#     re-enabling vblank, resuming CRC or arming the commit event, and prints
#     the four diagnostic registers.
#
# The gate is source level and does not assert formatting: it looks for a mask
# expression, a write inside the poll loop, an ordering and a set of register
# names. It rejects its own planted defects, so a regression cannot pass it.
#
# Usage: tests/check-restore-path.sh [source dir]
#        tests/check-restore-path.sh --single [source dir]   (no self-test)

set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

mode=full
if [ "${1:-}" = "--single" ]; then
	mode=single
	shift
fi
src_dir=${1:-${SM750_SRC_DIR:-$project_dir/src}}

display_c=$src_dir/ddk750_display.c
mode_c=$src_dir/ddk750_mode.c
drm_c=$src_dir/sm750_drm.c

fail() {
	echo "Restore path: $1" >&2
	exit 1
}

for f in "$display_c" "$mode_c" "$drm_c"; do
	[ -f "$f" ] || fail "missing source file $f"
done

# Print a top-level function body (definition line to the closing brace).
fn_body() {
	local file=$1
	local head=$2

	awk -v head="$head" '
		index($0, head) == 1 { in_fn = 1 }
		in_fn { print }
		in_fn && /^}/ { exit }' "$file"
}

# Print the first poll loop in the given text: from the loop head to its brace.
loop_block() {
	local head=$1
	local text=$2

	awk -v head="$head" '
		index($0, head) { in_loop = 1 }
		in_loop { print }
		in_loop && /^[[:space:]]+}$/ { exit }' <<<"$text"
}

# Line number of the first match of $2 inside text $1, empty when absent.
first_line() {
	local text=$1
	local pattern=$2

	{ grep -n -F "$pattern" <<<"$text" || true; } | head -n 1 | cut -d: -f1
}

# 1. The display transition wait is masked and re-pokes inside the loop.
wait_body=$(fn_body "$display_c" 'static int wait_display')
[[ -n $wait_body ]] || fail "ddk750_display.c has no wait_display helper"
grep -Eq 'unsigned long mask' <<<"$wait_body" ||
	fail "the display wait helper takes no transition mask"
grep -Eq '&[[:space:]]*mask\)[[:space:]]*==' <<<"$wait_body" ||
	fail "the display wait does not compare through the transition mask"
grep -Fq '~reserved' <<<"$wait_body" &&
	fail "the display wait still compares against an exact register value"
wait_loop=$(loop_block 'for (elapsed = 0' "$wait_body")
[[ -n $wait_loop ]] || fail "the display wait has no bounded poll loop"
grep -Fq 'poke32(reg,' <<<"$wait_loop" ||
	fail "the display wait pokes once, not on every poll iteration"
grep -Eq 'want.*mask.*last' <<<"$wait_body" ||
	fail "a timed-out display transition does not log want/mask/last"
grep -Eq '(pr_err|dev_err|drm_err)' <<<"$wait_body" ||
	fail "a timed-out display transition is silent"

# 2. The mode transition wait is masked, re-pokes and budgets by the mode.
prog_body=$(fn_body "$mode_c" 'static int program_mode_registers(')
[[ -n $prog_body ]] || fail "ddk750_mode.c has no program_mode_registers()"
grep -Eq 'cnt[[:space:]]*>[[:space:]]*[0-9]+' <<<"$prog_body" &&
	fail "the mode transition loop still uses a fixed iteration cap"
grep -Fq 'vertical_frequency' <<<"$prog_body" ||
	fail "the mode transition budget ignores the mode's vertical frequency"
grep -Fq '20000' <<<"$prog_body" ||
	fail "the mode transition budget has no 20 ms floor"
grep -Eq '&[[:space:]]*mask\)' <<<"$prog_body" ||
	fail "the mode transition compare is not masked"
prog_loop=$(loop_block 'for (elapsed_us = 0' "$prog_body")
[[ -n $prog_loop ]] || fail "the mode transition has no bounded poll loop"
grep -Fq 'poke32(PANEL_DISPLAY_CTRL' <<<"$prog_loop" ||
	fail "the mode transition does not re-poke inside the poll loop"
grep -Fq 'return -ETIMEDOUT;' <<<"$prog_body" ||
	fail "a mode transition timeout no longer reports -ETIMEDOUT"

# 3. sm750_pipe_disable() keeps the display-off result and its readback.
disable_body=$(fn_body "$drm_c" 'static void sm750_pipe_disable(')
[[ -n $disable_body ]] || fail "sm750_pipe_disable() is missing"
grep -Eq '^[[:space:]]*ret = ddk750_set_display_control\(SM750_DRM_CONTROLLER, false\);' \
	<<<"$disable_body" ||
	fail "the display-off result is discarded"
grep -Eq '^[[:space:]]*ddk750_set_display_control\(SM750_DRM_CONTROLLER, false\);' \
	<<<"$disable_body" &&
	fail "an unchecked display-off call remains in sm750_pipe_disable()"
grep -Fq 'panel did not acknowledge display-off' <<<"$disable_body" ||
	fail "a failed display-off is not reported"
grep -Fq 'peek32(PANEL_DISPLAY_CTRL)' <<<"$disable_body" ||
	fail "a failed display-off reports no register readback"
grep -Eq 'drm_warn|drm_err' <<<"$disable_body" ||
	fail "a failed display-off is not logged at warning severity"

# 4. The enable fail path stays terminal and prints the diagnostic state.
fail_block=$(awk '
	/^fail:/ { in_fail = 1 }
	in_fail { print }
	in_fail && /^\}/ { exit }' "$drm_c")
[[ -n $fail_block ]] || fail "sm750_pipe_enable() has no fail: label"
grep -Fq 'failed to enable HDMI mode: %d at stage %s' <<<"$fail_block" ||
	fail "the fail path no longer names the mode stage"
grep -Fq 'sdev->enable_failed = true;' <<<"$fail_block" ||
	fail "the fail path does not mark the pipe as down for the next commit"
for forbidden in \
	'drm_crtc_vblank_on(' \
	'sm750_crc_resume(' \
	'sm750_arm_vblank_event(' \
	'commit finished, event consumed'; do
	if grep -Fq "$forbidden" <<<"$fail_block"; then
		fail "the fail path still fakes a live pipe: $forbidden"
	fi
done
for reg in PANEL_DISPLAY_CTRL PANEL_PLL_CTRL SYSTEM_CTRL PANEL_CURRENT_LINE; do
	grep -Fq "$reg=" <<<"$fail_block" ||
		fail "the fail path does not print $reg"
done
grep -Eq 'enable-fail state:.*PANEL_DISPLAY_CTRL=.*PANEL_PLL_CTRL=.*SYSTEM_CTRL=.*PANEL_CURRENT_LINE=' \
	<<<"$fail_block" ||
	fail "the fail-path register state is not one diagnostic line"

[ "$mode" = full ] || exit 0

# Every planted defect must be caught, otherwise the gate is decorative.
scratch=$(mktemp -d "${TMPDIR}/sm750-restore-gate.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

# The defect this gate exists for: the pre-A32 whole-register compare.
plant_exact_compare() {
	sed -i 's/(last & mask) == (value & mask)/(last \& ~mask) == (value \& ~mask)/' \
		"$1/ddk750_display.c"
}
# A1: a failed enable must not re-enable vblank on the way out.
plant_enable_fail_up() {
	awk '
		/^fail:/ {
			print
			print "\tdrm_crtc_vblank_on(&pipe->crtc);"
			next
		}
		{ print }' "$1/sm750_drm.c" >"$1/sm750_drm.c.new"
	mv "$1/sm750_drm.c.new" "$1/sm750_drm.c"
}
# The defect A32 closed: the display-off result was thrown away.
plant_discard_result() {
	awk '
		index($0, "static void sm750_pipe_disable(") == 1 { in_fn = 1 }
		in_fn && /^\tret = ddk750_set_display_control\(SM750_DRM_CONTROLLER, false\);$/ {
			print "\tddk750_set_display_control(SM750_DRM_CONTROLLER, false);"
			next
		}
		in_fn && /^\tif \(ret\)$/ { skip = 1; next }
		in_fn && skip && /panel did not acknowledge display-off/ { next }
		in_fn && skip && /peek32\(PANEL_DISPLAY_CTRL\)\);/ { skip = 0; next }
		in_fn && skip { next }
		{ print }' "$1/sm750_drm.c" >"$1/sm750_drm.c.new"
	mv "$1/sm750_drm.c.new" "$1/sm750_drm.c"
}
# Without the register state the recurrence hypothesis stays open.
plant_no_state_line() {
	sed -i '/enable-fail state:/d' "$1/sm750_drm.c"
}

control() {
	local name=$1
	local planted=$scratch/src
	local err=$scratch/stderr

	rm -rf "$planted"
	mkdir -p "$planted"
	cp "$display_c" "$mode_c" "$drm_c" "$planted/"
	shift
	"$@" "$planted"
	if "$0" --single "$planted" >/dev/null 2>"$err"; then
		fail "negative control $name was not rejected"
	fi
	echo "negative control $name: rejected (exit 1): $(head -n 1 "$err")"
}

control exact_register_compare plant_exact_compare
control enable_fail_fakes_live_pipe plant_enable_fail_up
control display_off_result_discarded plant_discard_result
control no_fail_state_registers plant_no_state_line

echo "Restore path checks passed"