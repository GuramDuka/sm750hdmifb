#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

source_file=${1:-src/sm750_drm.c}
required=(
	640x480 800x600 1024x768 1152x864 1280x720 1280x800
	1280x1024 1366x768 1600x900 1680x1050 1920x1080 1920x810
	2048x864 2048x1024 2048x1080 2048x1152 2464x1080 2560x1080
)

for mode in "${required[@]}"; do
	grep -F "DRM_MODE(\"$mode\"" "$source_file" >/dev/null || {
		echo "Missing required DRM mode: $mode" >&2
		exit 1
	}
done
for mode in 640x480 800x600 1024x768 1152x864 1280x720 1280x800 \
		1280x1024 1366x768 1600x900 1680x1050 1920x810 2048x864; do
	test "$(grep -Fc "DRM_MODE(\"$mode\"" "$source_file")" -eq 5 || {
		echo "Incomplete five-rate mode set: $mode" >&2
		exit 1
	}
done
for entry in '1920x1080 8' '2048x1024 4' '2048x1080 6' \
		'2048x1152 2' '2464x1080 6' '2560x1080 6'; do
	mode=${entry% *}
	expected=${entry#* }
	test "$(grep -Fc "DRM_MODE(\"$mode\"" "$source_file")" -eq "$expected" || {
		echo "Unexpected hardware-limited mode count: $mode" >&2
		exit 1
	}
done
grep -F 'DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED' "$source_file" \
	>/dev/null
grep -F 'DRM_FORMAT_XRGB8888' "$source_file" >/dev/null
grep -F '#define SM750_DRM_MAX_WIDTH 2560' "$source_file" >/dev/null
grep -F '#define SM750_DRM_PHYSICAL_MAX_WIDTH 2048' "$source_file" >/dev/null
grep -F '#define SM750_DRM_MAX_HEIGHT 1152' "$source_file" >/dev/null
grep -F 'static const struct drm_display_mode sm750_standard_modes[]' \
	"$source_file" >/dev/null
for clock in 148352 148500 156240 160848 \
	99860 99959 117180 120672 125849 \
	113394 113507 133021 136975 142842 \
	134440 134574 157748 162408 151149 151300; do
	grep -F "DRM_MODE_TYPE_DRIVER, $clock," "$source_file" >/dev/null || {
		echo "Missing required standards-derived clock: $clock kHz" >&2
		exit 1
	}
done
if grep -F 'DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 167850' \
	"$source_file" >/dev/null ||
	grep -F 'DRM_MODE("2048x1024", DRM_MODE_TYPE_DRIVER, 169335' \
	"$source_file" >/dev/null ||
	grep -E 'DRM_MODE\("2048x1152".*(177411|182633|190562)' \
	"$source_file" >/dev/null; then
	echo "Out-of-spec high-resolution refresh mode is present." >&2
	exit 1
fi
grep -F 'DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC' "$source_file" \
	>/dev/null
grep -F 'drm->mode_config.prefer_shadow = 1;' "$source_file" >/dev/null
for requirement in \
	'module_param(scanout_format, charp, 0444);' \
	'"rgb565-bbdither"' \
	'"rgb565"' \
	'DRM_GEM_SIMPLE_DISPLAY_PIPE_SHADOW_PLANE_FUNCS,' \
	'drm_gem_fb_create_with_dirty' \
	'drm_atomic_for_each_plane_damage(&iter, &damage)' \
	'drm_plane_enable_fb_damage_clips(&sdev->pipe.plane)' \
		'PANEL_DISPLAY_CTRL_FORMAT_16' \
		'sm750_xrgb8888_to_rgb565' \
		'sm750_dither_xrgb8888_to_rgb565' \
		'sm750_shadow_upload(sdev,' \
		'memcpy_toio(sdev->vram + destination, source, size);'; do
	grep -F "$requirement" "$source_file" >/dev/null || {
		echo "Missing RGB565 dither requirement: $requirement" >&2
		exit 1
	}
done
if grep -F 'crtc_state->no_vblank = true;' "$source_file" >/dev/null; then
	echo "DRM source disables vblank event pacing." >&2
	exit 1
fi
grep -F 'if (!edid_only && !sm750_mode_is_catalogued(mode))' \
	"$source_file" >/dev/null
grep -F 'line_width = ALIGN(mode.hdisplay * mode.cpp, SM750_DRM_LINE_ALIGN);' \
	"$source_file" >/dev/null
grep -F 'drm_gem_vram_fill_create_dumb(file, drm, 0,' \
	"$source_file" >/dev/null
grep -F '.dumb_create = sm750_dumb_create,' "$source_file" >/dev/null
grep -F '!IS_ALIGNED(plane_state->fb->pitches[0],' "$source_file" >/dev/null
grep -F 'sm750_sii902x_read_edid(&sdev->pdev->dev' "$source_file" >/dev/null
grep -F 'drm_connector_update_edid_property(connector, edid);' \
	"$source_file" >/dev/null
grep -F 'count = drm_add_edid_modes(connector, edid);' \
	"$source_file" >/dev/null
for requirement in \
	'if (sdev->connected_edid_valid && sdev->monitor_disconnected &&' \
	'memcmp(sdev->connected_edid, edid, SM750_DRM_EDID_SIZE)' \
	'sm750_remember_disconnected_mode(sdev, connector);' \
	'sm750_select_reconnected_monitor_mode(connector);' \
	'sm750_catalog_supports_edid_mode(sdev, mode)' \
	'sdev->hotplug_preferred_valid = true;' \
	'"hotplug preferred mode %ux%u@%u is unavailable\n"'; do
	grep -F "$requirement" "$source_file" >/dev/null || {
		echo "Missing EDID hotplug policy: $requirement" >&2
		exit 1
	}
done
for parameter in edid_only softscale_wide sharpen double_shadow \
		disable_hardware_cursor enable_dma disable_dma async_updates; do
	grep -F "module_param($parameter, bool, 0444);" "$source_file" \
		>/dev/null || {
		echo "Missing runtime policy parameter: $parameter" >&2
		exit 1
	}
done
grep -F 'module_param(preferred_width, uint, 0444);' "$source_file" >/dev/null
grep -F 'module_param(preferred_height, uint, 0444);' "$source_file" >/dev/null
grep -F 'module_param(preferred_refresh, uint, 0444);' "$source_file" >/dev/null
for requirement in \
	'drm_vblank_init(drm, 1);' \
	'sdev->pipe.crtc.funcs = &sm750_crtc_funcs;' \
	'PANEL_CURRENT_LINE' \
	'drm_crtc_vblank_get(&pipe->crtc)' \
	'drm_crtc_handle_vblank(&sdev->pipe.crtc);' \
	'drm_crtc_arm_vblank_event(&pipe->crtc, event);' \
	'drm_crtc_vblank_on(&pipe->crtc);' \
	'.enable_vblank = sm750_pipe_enable_vblank,' \
	'.disable_vblank = sm750_pipe_disable_vblank,' \
	'.enable_vblank = sm750_crtc_enable_vblank,' \
	'.disable_vblank = sm750_crtc_disable_vblank,' \
	'hrtimer_try_to_cancel(&sdev->vblank_timer);' \
	'hrtimer_cancel(&sdev->vblank_timer);'; do
	grep -F "$requirement" "$source_file" >/dev/null || {
		echo "Missing DRM vblank requirement: $requirement" >&2
		exit 1
	}
done
# A1 supersedes A27: a failed hardware enable must not be dressed up as a live
# pipe. A27 required the fail label to re-enable vblank and consume the commit
# event so the commit would not wedge; that only made userspace see a
# successful commit for a panel that never came up. The fail path now leaves
# the event for the core to time out, keeps vblank and CRC off, and sets
# enable_failed so the next commit retries. The property and its planted control
# live in runtime_guard_properties() (A1) so one checker owns both.
if ! grep -F '#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)' \
	"$source_file" >/dev/null ||
	! grep -F '#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 0, 0)' \
	"$source_file" >/dev/null; then
	echo "DRM source lacks versioned pipe/CRTC vblank hooks." >&2
	exit 1
fi
if grep -F 'DRM_CRTC_VBLANK_TIMER_FUNCS' "$source_file" >/dev/null; then
	echo "DRM source still selects the core timer with the restart race." >&2
	exit 1
fi
grep -F 'devm_request_irq(&sdev->pdev->dev, sdev->pdev->irq,' \
	"$source_file" >/dev/null
grep -F 'IRQF_SHARED' "$source_file" >/dev/null
if grep -F '#define SM750_DRM_MAX_WIDTH 1920' "$source_file" >/dev/null; then
	echo "Initial build was accidentally capped at 1920 pixels." >&2
	exit 1
fi
for excluded in 2432x1080 2496x1080 2540x1080 \
		SM750_DRM_SECONDARY_SCANOUT; do
	if grep -F "$excluded" "$source_file" >/dev/null; then
		echo "Excluded experimental path remains: $excluded" >&2
		exit 1
	fi
done
# GAP-B8: the pipe-enable error path names the sm750_program_mode() call that
# failed. A stage with no name renders as "unknown"; a call site without its
# stage assignment makes the report name the previous stage. Both drift modes
# are checked here.
grep -F 'failed to enable HDMI mode: %d at stage %s' "$source_file" >/dev/null || {
	echo "GAP-B8: the pipe-enable error does not name the failing mode stage." >&2
	exit 1
}
stage_enum=$(awk '
	/^enum sm750_mode_stage \{/ { in_enum = 1 }
	in_enum { print }
	in_enum && /^\};/ { exit }
' "$source_file")
if [[ -z $stage_enum ]]; then
	echo "GAP-B8: enum sm750_mode_stage is missing." >&2
	exit 1
fi
stage_count=0
while read -r stage; do
	[[ -n $stage ]] || continue
	stage_count=$((stage_count + 1))
	grep -F "[$stage] = \"" "$source_file" >/dev/null || {
		echo "GAP-B8: stage $stage has no name in sm750_mode_stage_names." >&2
		exit 1
	}
	grep -F "sdev->mode_stage = $stage;" "$source_file" >/dev/null || {
		echo "GAP-B8: stage $stage is never assigned on the modeset path." >&2
		exit 1
	}
done < <(sed -n 's/^[[:space:]]*\(SM750_MODE_STAGE_[A-Z_]*\),.*/\1/p' <<<"$stage_enum")
# Five fallible calls plus the NONE state: anything less is a lost stage.
test "$stage_count" -ge 6 || {
	echo "GAP-B8: expected at least 6 mode stages, found $stage_count." >&2
	exit 1
}
# T30: DRM core owns crtc-N/crc/{control,data} and routes them to the three
# crtc hooks; the driver hosts no crc debugfs file of its own. The gate checks
# the callbacks, the deleted shim, the tick's re-arm and the value count, and
# re-runs itself against planted defects.
./tests/check-crc-uapi.sh "$source_file"
# T31: a blank console buffer (foreground VT in KD_GRAPHICS) is named once
# instead of being mistaken for a display-path regression. Source-level, with
# its own planted-defect controls.
./tests/check-console-blank.sh "$source_file"
# T37: the test-card fallback (test_pattern/test_pattern_period_ms, the
# pitch-padded painter, the single sample in sm750_pipe_enable and the
# cancelled rotation). Source-level, with its own planted-defect controls.
./tests/check-test-pattern.sh "$source_file"
# T32: the reconsole restore path (masked transition compare, mode-derived
# budget, kept display-off result, terminal fail path). Source-level, with its
# own planted-defect controls.
./tests/check-restore-path.sh
# T35: AGENTS.md:26 scratch rule. Every mktemp caller exports
# TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp} before its first call and interpolates
# it, and the restore harness greps the same nine-marker census as the hardware
# proof. With its own planted-defect controls.
./tests/check-scratch-policy.sh
# A42: the SiI9024A readiness gate watches HPD (0x3d bit 2) with a 500 ms
# budget and accepts a powered receiver, a timed-out TPI write is retried after
# a bus clear without failing the enable, the EDID read is skipped while the
# transmitter is powered down, the DDC grant wait polls every 200 ms inside a
# 2000 ms budget with one retry, and every mode set clears the software bus
# first. Source-level, with its own nine planted-defect controls.
./tests/check-sii902x-recovery.sh
# T52: the twelve monitoring attributes sm750-smi reads from
# /sys/class/drm/cardN/device/ (names, group on the PCI device before
# drm_dev_register, sysfs_emit and no sleep in a show function, clear_events
# false on the link-status read). Source-level, with its own five
# planted-defect controls.
./tests/check-sysfs-attributes.sh "$source_file"
# T56: the headless compositor helper tools/sm750-headless.sh (fixed mode and
# program list, the card pinned to 0000:01:00.0 bound to sm750hdmidrm,
# LIBSEAT_BACKEND=noop so no VT is touched, cage without -s, kmscube with -c
# and without -n, a clamped run time, a verdict that needs a survivor and a
# vblank delta, TERM then KILL cleanup, and input isolation: weston and cage
# both exec inside a private mount namespace whose /dev/input is an empty
# tmpfs, so neither can take the owner's keyboard or mouse - A49). Source-level;
# it never runs the helper and needs no root.
./tests/check-headless-helper.sh
# T57: the render node. kwin 6.7.5 skips a DRM device whose node set has no
# render node, so the driver advertises DRIVER_RENDER on the same
# driver_features line as DRIVER_MODESET (a render-only device would lose
# modesetting); the node carries dumb and PRIME primitives only, because SM750
# has no 3D engine. Source-level with three planted controls; the live half
# skips while the running module predates the change.
./tests/check-render-node.sh
# T60: the VT hot-reload helper tools/sm750-vt.sh and its recovery mode. The
# target vtconsole is resolved by globbing /sys/class/vtconsole (never a
# hardcoded index) and confirmed by the PCI driver of 0000:01:00.0, the unload
# is refused while userspace holds the card, modprobe -r precedes modprobe, the
# loaded version is read back from sysfs, bind 0 detaches and bind 1 restores
# with a read-back, and one EXIT trap re-binds fbcon on every non-zero exit
# while preserving the status. Source-level only; it never writes sysfs, calls
# modprobe or needs root.
./tests/check-vt-helper.sh
# T61: the deferred PM cycle helper tools/sm750-pmtest.sh, installed as
# /usr/local/sbin/sm750-pmtest and allowlisted in docs/ROOT-ACTIONS.md 3.14.
# The host has no S3, so the driver callbacks are reached through
# /sys/power/pm_test, and a forgotten level turns every later real suspend into
# a test until reboot. The gate pins the root check before the first write, the
# level validated against the explicit list, `none` written by the EXIT trap,
# the readback after every write, the journal snapshot taken before the freeze,
# the verdict that needs both completion lines, and the absence of fb0 as a
# success criterion. Source-level; it never writes sysfs, suspends or needs root.
./tests/check-pmtest-helper.sh
# T62: the A65 forensic pair. tools/sm750-hang.sh is the read-only capture
# installed as /usr/local/sbin/sm750-hang (ROOT-ACTIONS.md 3.15): a root check
# before the first write, no OUTDIR overwrite, six files, a D-state-only task
# filter, a `=== pid` header per blocked pid, and a verdict that distinguishes
# a captured stack from one /proc could not report; it never writes sysfs,
# never calls modprobe and needs no root. tools/sm750-pkg.sh gains the reload
# refusal while the framebuffer vtconsole is bound (the state that wedged the
# module in Unloading on 2026-11-26) and the --force override. Source-level,
# with three planted controls each; neither adds a `make check` recipe
# command, so the documented count of 17 is unchanged.
./tests/check-hang-helper.sh
./tests/check-sm750-pkg.sh
# T63: the pm_probe diagnostic attribute in src/sm750_drm.c. It drives the
# suspend and resume callback bodies directly, because a devices-level sleep is
# unreachable on the reference host: two neighbouring Tesla P100s refuse the
# pm_test cycle before the SM750 is reached (docs/DEFECTS.md A66). The gate pins
# the three commands, the root-only 0200 mode, the master, registration and
# drm_dev_enter guards before any callback, the mutex and the dev_enter bracket,
# the logged callback result, the no-resume-after-failed-suspend rule, and the
# return value: a success returns the byte count while a callback failure is
# propagated, so `echo cycle > pm_probe` fails visibly and a script under
# `set -e` stops. Source-level, with six planted controls; it is invoked from
# here, so the documented count of 18 `make check` recipe commands is unchanged.
./tests/check-pm-probe.sh
# T63: the default-off A65 teardown marks in src/sm750_drm.c. Defect A65 is a
# hot remove that wedges in Unloading with fbcon bound and leaves no stack, so
# a65_trace=1 prints `A65: <step>` through pr_err from the remove callback and
# from the shadow-workqueue teardown. The gate pins the bool 0644 declaration,
# the pr_err/guard pair, the no-lock/no-sleep body, the exact mark set per
# function and the original bracket order. Source-level, with four planted
# controls; it is invoked from here, so the documented count of 18 `make check`
# recipe commands is unchanged.
./tests/check-a65-trace.sh
# T6 of the strict-production plan: tools/sm750-soak.sh, the owner-installable
# soak helper (ROOT-ACTIONS.md 3.18). It samples the panel state, the GAP-B8
# counters, the module refcount, VRAM use, resident memory, kernel-log delta
# counts and the last recorded gate results every --interval seconds for
# --duration seconds (24 h by default), and derives its verdict from the whole
# series: a count of out-of-range samples and a count of new fault lines, never
# one reading. The gate pins POSIX sh and ASCII, a TMPDIR-pinned mktemp
# scratch directory, the absence of chvt, VT_ACTIVATE, unshare, /dev/input,
# every compositor and every signal to a process on executed lines, the 29
# recorded sample columns, the eleven verdict criteria, the exit codes, and the
# refusal to write outside /mega/tmp/sm750 or into an existing directory; then
# it runs the helper against a fixture root with no card and no root: a healthy
# fixture must reach PASS with exit 0 and at least two samples, a fault already
# in the kernel buffer must not fail a run, a fault logged during a run must
# fail it, each planted out-of-range field must turn the verdict into FAIL with
# a non-zero exit status naming that criterion, and an interrupted run must
# never be PASS. Seven planted controls prove the static arm rejects each
# forbidden construct. It is invoked from here, so the documented count of 18
# `make check` recipe commands is unchanged.
./tests/check-soak-helper.sh
# Runtime guard properties found by the 2026-11-26 production-readiness
# review (docs/evidence/review/02-production-readiness-runtime.txt): D1 (the
# direct scanout path must not read past the plane object or VRAM), D2 (the
# commit path must not read the writable test_pattern string), D3 (the SiI9022A
# pin parameters are validated as ints before the u8 conversion), D4 (a minimum
# VRAM floor precedes the DMA test carve) and R2 (the DMA timeout re-reads the
# completion counter). Each property is pinned by a planted control that removes
# it, so the gate cannot pass by accident.
guard_fn() {
	local file=$1
	local head=$2
	local def_only=${3:-0}

	# def_only=1 skips a line that is a declaration rather than a definition.
	# A static function that is called before it is defined needs a prototype,
	# and the prototype carries the same prefix as the definition: without the
	# semicolon test the extractor would return the prototype and the property
	# under test would be checked against the wrong lines.
	awk -v head="$head" -v def_only="$def_only" '
		!in_fn && index($0, head) == 1 &&
		    (def_only == 0 || $0 !~ /;[[:space:]]*$/) { in_fn = 1 }
		in_fn { print }
		in_fn && /^}/ { exit }' "$file"
}

runtime_guard_properties() {
	local file=$1
	local checked=0
	local failed=0
	local pipe_check pipe_enable should_paint probe dma_wait
	local check_line conv_line min_line carve_line done_line err_line
	local enable_body disable_body update_body fail_block read_edid arm_event
	local hw_init get_line lock_line arm_line unlock_line init_line mask_line
	local region_body scanout_body mode_line pitch_line
	local pm_suspend pm_resume pm_fail_count

	pipe_check=$(guard_fn "$file" 'static int sm750_pipe_check(')
	checked=$((checked + 1))
	if [[ -z $pipe_check ]] ||
	   ! grep -qF 'plane_state->fb->width < mode->hdisplay' <<<"$pipe_check" ||
	   ! grep -qF 'plane_state->fb->height < mode->vdisplay' <<<"$pipe_check"; then
		echo "D1: sm750_pipe_check does not reject a plane framebuffer smaller than the adjusted mode." >&2
		failed=1
	fi

	pipe_enable=$(guard_fn "$file" 'static void sm750_pipe_enable(')
	checked=$((checked + 1))
	if [[ -z $pipe_enable ]] ||
	   ! grep -qF '(u64)offset + frame_size > sdev->vram_size' <<<"$pipe_enable"; then
		echo "D1: the direct scanout branch does not reject offset + frame_size beyond VRAM with 64-bit arithmetic." >&2
		failed=1
	fi

	should_paint=$(guard_fn "$file" 'static bool sm750_test_pattern_should_paint(')
	checked=$((checked + 1))
	if [[ -z $should_paint ]] ||
	   ! grep -qF 'sdev->test_pattern_mode' <<<"$should_paint" ||
	   grep -qF 'strcmp(test_pattern' <<<"$should_paint" ||
	   grep -qF 'strcmp(test_pattern' <<<"$pipe_enable"; then
		echo "D2: the commit path still reads the test_pattern string instead of the probe-time enum." >&2
		failed=1
	fi

	probe=$(guard_fn "$file" 'static int sm750_pci_probe(')
	checked=$((checked + 1))
	check_line=$(grep -nF 'sii9024_scl < 0 || sii9024_scl > 31' <<<"$probe" |
		head -n 1 | cut -d: -f1)
	conv_line=$(grep -nF 'sm750_sii902x_prepare(' <<<"$probe" |
		head -n 1 | cut -d: -f1)
	if [[ -z $probe ]] ||
	   ! grep -qF 'sii9024_sda < 0 || sii9024_sda > 31' <<<"$probe" ||
	   ! grep -qF 'sii9024_scl == sii9024_sda' <<<"$probe" ||
	   [[ -z $check_line || -z $conv_line || $check_line -ge $conv_line ]]; then
		echo "D3: sii9024_scl/sii9024_sda are not validated as 0..31 ints before the u8 conversion, or may be equal." >&2
		failed=1
	fi

	checked=$((checked + 1))
	probe=$(guard_fn "$file" 'static int sm750_pci_probe(')
	min_line=$(grep -nF 'sdev->vram_size < SM750_DRM_MIN_VRAM' <<<"$probe" |
		head -n 1 | cut -d: -f1)
	dma_line=$(grep -nF 'sm750_dma_init(sdev)' <<<"$probe" |
		head -n 1 | cut -d: -f1)
	min_vram=$(grep -A4 -F '#define SM750_DRM_MIN_VRAM' "$file")
	if [[ -z $probe || -z $min_line || -z $dma_line ||
	      $min_line -ge $dma_line ]] ||
	   ! grep -qF 'SM750_DRM_DMA_TEST_SIZE' <<<"$min_vram" ||
	   ! grep -qF 'SM750_DRM_DMA_GUARD_WORDS' <<<"$min_vram"; then
		echo "D4: the minimum-VRAM check does not precede the DMA test carve." >&2
		failed=1
	fi

	dma_wait=$(guard_fn "$file" 'static int sm750_dma_wait_active(')
	checked=$((checked + 1))
	done_line=$(grep -nF 'completion_done(&sdev->dma_completion)' <<<"$dma_wait" |
		head -n 1 | cut -d: -f1)
	err_line=$(grep -nF '"DMA1 shadow upload timed out' <<<"$dma_wait" |
		head -n 1 | cut -d: -f1)
	if [[ -z $dma_wait || -z $done_line || -z $err_line ||
	      $done_line -ge $err_line ]]; then
		echo "R2: the DMA timeout path declares a timeout without re-reading the completion counter." >&2
		failed=1
	fi

	enable_body=$(guard_fn "$file" 'static void sm750_pipe_enable(')
	disable_body=$(guard_fn "$file" 'static void sm750_pipe_disable(')
	update_body=$(guard_fn "$file" 'static void sm750_pipe_update(')
	fail_block=$(awk '
		/^static void sm750_pipe_enable\(/ { in_function = 1 }
		in_function && /^fail:/ { in_fail = 1 }
		in_function && in_fail { print }
		in_function && in_fail && /^}/ { exit }
	' "$file")
	checked=$((checked + 1))
	if [[ -z $enable_body || -z $disable_body || -z $update_body ||
	      -z $fail_block ]] ||
	   ! grep -qF 'sdev->enable_failed = true;' <<<"$fail_block" ||
	   ! grep -qF 'sdev->enable_failed = false;' <<<"$enable_body" ||
	   ! grep -qF 'sdev->enable_failed = false;' <<<"$disable_body" ||
	   ! grep -qF 'sdev->enable_failed && !pipe->crtc.state->mode_changed' \
		<<<"$update_body" ||
	   ! grep -qF '!sdev->enable_failed && !pipe->crtc.state->mode_changed' \
		<<<"$update_body" ||
	   grep -qF 'drm_crtc_vblank_on' <<<"$fail_block" ||
	   grep -qF 'sm750_crc_resume' <<<"$fail_block" ||
	   grep -qF 'sm750_arm_vblank_event' <<<"$fail_block" ||
	   grep -qF 'commit finished, event consumed' <<<"$fail_block"; then
		echo "A1: the enable fail path still fakes a live pipe or does not mark it down for the next commit." >&2
		failed=1
	fi

	read_edid=$(guard_fn "$file" 'static struct edid *sm750_connector_read_edid(')
	checked=$((checked + 1))
	if [[ -z $read_edid ]] ||
	   ! grep -qF 'sm750_sii902x_read_edid(&sdev->pdev->dev, (u8 *)edid, 256)' <<<"$read_edid" ||
	   grep -qF 'msleep(' <<<"$read_edid" ||
	   grep -qF 'usleep_range(' <<<"$read_edid"; then
		echo "E1: the EDID read taken by get_modes still sleeps or retries under connection_mutex." >&2
		failed=1
	fi

	arm_event=$(guard_fn "$file" 'static void sm750_arm_vblank_event(')
	checked=$((checked + 1))
	get_line=$(grep -nF 'drm_crtc_vblank_get(&pipe->crtc)' <<<"$arm_event" |
		head -n 1 | cut -d: -f1)
	lock_line=$(grep -nF 'spin_lock_irqsave(&pipe->crtc.dev->event_lock' \
		<<<"$arm_event" | head -n 1 | cut -d: -f1)
	arm_line=$(grep -nF 'drm_crtc_arm_vblank_event(&pipe->crtc, event)' \
		<<<"$arm_event" | head -n 1 | cut -d: -f1)
	unlock_line=$(grep -nF 'spin_unlock_irqrestore(&pipe->crtc.dev->event_lock' \
		<<<"$arm_event" | head -n 1 | cut -d: -f1)
	if [[ -z $arm_event || -z $get_line || -z $lock_line ||
	      -z $arm_line || -z $unlock_line ]] ||
	   (( get_line >= lock_line )) ||
	   (( arm_line <= lock_line )) ||
	   (( arm_line >= unlock_line )); then
		echo "C1: drm_crtc_vblank_get() is not taken outside event_lock with only the arm inside it." >&2
		failed=1
	fi

	hw_init=$(guard_fn "$file" 'static int sm750_hw_init(')
	checked=$((checked + 1))
	init_line=$(grep -nF 'ddk750_init_hw(&init);' <<<"$hw_init" |
		head -n 1 | cut -d: -f1)
	mask_line=$(grep -nF 'poke32(INT_MASK, peek32(INT_MASK) | INT_MASK_DMA1);' \
		<<<"$hw_init" | head -n 1 | cut -d: -f1)
	if [[ -z $hw_init || -z $init_line || -z $mask_line ]] ||
	   ! grep -qF 'sdev->dma_irq_enabled' <<<"$hw_init" ||
	   (( mask_line <= init_line )); then
		echo "P2: sm750_hw_init() does not re-arm the DMA1 INT_MASK bit after the chip reset." >&2
		failed=1
	fi

	region_body=$(guard_fn "$file" 'static const char *sm750_crc_region_missing(')
	checked=$((checked + 1))
	mode_line=$(grep -nF 'if (!sdev->pipe.crtc.mode.hdisplay || !sdev->pipe.crtc.mode.vdisplay)' \
		<<<"$region_body" | head -n 1 | cut -d: -f1)
	pitch_line=$(grep -nF 'if (!sdev->scanout_pitch)' <<<"$region_body" |
		head -n 1 | cut -d: -f1)
	if [[ -z $region_body || -z $mode_line || -z $pitch_line ]] ||
	   ! grep -qF 'return "active mode";' <<<"$region_body" ||
	   (( mode_line >= pitch_line )); then
		echo "R3: sm750_crc_region_missing() does not reject a zero mode as a missing region." >&2
		failed=1
	fi

	checked=$((checked + 1))
	if [[ -z $disable_body || -z $update_body ]] ||
	   ! grep -qF 'sdev->scanout_pitch = 0;' <<<"$disable_body" ||
	   ! grep -qF 'sdev->scanout_frame_size = 0;' <<<"$disable_body" ||
	   ! grep -qF 'if (!sdev->scanout_pitch || !sdev->scanout_frame_size)' \
		<<<"$update_body"; then
		echo "R4: sm750_pipe_disable() leaves the previous scanout geometry behind or an upload ignores a cleared pitch." >&2
		failed=1
	fi

	scanout_body=$(guard_fn "$file" 'static int sm750_scanout_show(')
	checked=$((checked + 1))
	if [[ -z $scanout_body ]] ||
	   ! grep -qF 'if (!sdev->pipe.crtc.mode.hdisplay || !sdev->pipe.crtc.mode.vdisplay)' \
		<<<"$scanout_body" ||
	   ! grep -qF 'scanout readback, no active mode' <<<"$scanout_body"; then
		echo "R5: the scanout debugfs header does not name a zero mode honestly." >&2
		failed=1
	fi

	pm_suspend=$(guard_fn "$file" 'static int sm750_pm_suspend(' 1)
	checked=$((checked + 1))
	if [[ -z $pm_suspend ]] ||
	   ! grep -qF 'pm: suspend entry' <<<"$pm_suspend" ||
	   ! grep -qF 'pm: suspend complete' <<<"$pm_suspend"; then
		echo "S1: sm750_pm_suspend() does not log both edges of a suspend cycle." >&2
		failed=1
	fi

	pm_resume=$(guard_fn "$file" 'static int sm750_pm_resume(' 1)
	checked=$((checked + 1))
	if [[ -z $pm_resume ]] ||
	   ! grep -qF 'pm: resume entry' <<<"$pm_resume" ||
	   ! grep -qF 'pm: resume complete' <<<"$pm_resume"; then
		echo "S2: sm750_pm_resume() does not log both edges of a resume cycle." >&2
		failed=1
	fi

	checked=$((checked + 1))
	pm_fail_count=$(grep -cE '"pm: (suspend|resume) failed: %d\\n"' "$file" || true)
	if [[ $pm_fail_count -ne 4 ]]; then
		echo "S3: a PM callback returns an error code without logging it on every early-return path." >&2
		failed=1
	fi

	echo "$checked"
	return "$failed"
}

# Planted controls: each removes the property, not the sentence that explains
# it, and each must be rejected by runtime_guard_properties().
plant_plane_covers_mode() {
	sed -i '/plane_state->fb->width < mode->hdisplay/d;
		/plane_state->fb->height < mode->vdisplay/d' "$1"
}
plant_direct_vram_bound() {
	sed -i 's/(u64)offset + frame_size > sdev->vram_size/(u64)offset + frame_size > U32_MAX/' "$1"
}
plant_test_pattern_string() {
	awk '
		index($0, "static bool sm750_test_pattern_should_paint(") == 1 { in_fn = 1 }
		in_fn && !done && index($0, "READ_ONCE(sdev->crc_enabled)") {
			print "\tif (!strcmp(test_pattern, \"always\"))";
			print "\t\treturn true;";
			done = 1
		}
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
plant_pin_range() {
	sed -i '/sii9024_scl < 0 || sii9024_scl > 31/d;
		/sii9024_sda < 0 || sii9024_sda > 31/d' "$1"
}
plant_vram_floor() {
	sed -i '/sdev->vram_size < SM750_DRM_MIN_VRAM/,+4d' "$1"
}
plant_completion_recheck() {
	sed -i '/if (irq_completion && completion_done(&sdev->dma_completion))/,+3d' "$1"
}
plant_enable_fail_reports_live_pipe() {
	sed -i '/^[[:space:]]*sdev->enable_failed = true;$/d' "$1"
}
plant_edid_sleep() {
	awk '
		index($0, "ret = sm750_sii902x_read_edid(&sdev->pdev->dev, (u8 *)edid, 256);") {
			print;
			print "\tmsleep(3000);";
			next
		}
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
plant_event_get_under_lock() {
	awk '
		index($0, "if (drm_crtc_vblank_get(&pipe->crtc)) {") {
			print "\tspin_lock_irqsave(&pipe->crtc.dev->event_lock, flags);";
		}
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
plant_int_mask_rearm() {
	sed -i '/poke32(INT_MASK, peek32(INT_MASK) | INT_MASK_DMA1);/d' "$1"
}
plant_crc_zero_mode() {
	awk '
		/^static const char \*sm750_crc_region_missing\(/ { in_fn = 1 }
		in_fn && index($0, "sdev->pipe.crtc.mode.hdisplay") { next }
		in_fn && index($0, "return \"active mode\";") { next }
		in_fn && /^}/ { in_fn = 0 }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
plant_disable_geometry() {
	awk '
		/^static void sm750_pipe_disable\(/ { in_fn = 1 }
		in_fn && index($0, "sdev->scanout_pitch = 0;") { next }
		in_fn && index($0, "sdev->scanout_frame_size = 0;") { next }
		in_fn && /^}/ { in_fn = 0 }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
plant_header_zero_mode() {
	awk '
		/^static int sm750_scanout_show\(/ { in_fn = 1 }
		in_fn && index($0, "sdev->pipe.crtc.mode.hdisplay || !sdev->pipe.crtc.mode.vdisplay)") { next }
		in_fn && /^}/ { in_fn = 0 }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}

plant_pm_no_suspend_entry() {
	awk '
		/^static int sm750_pm_suspend\(struct device \*dev\)$/ { in_fn = 1 }
		in_fn && index($0, "pm: suspend entry") { next }
		in_fn && /^}/ { in_fn = 0 }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
plant_pm_no_resume_complete() {
	awk '
		/^static int sm750_pm_resume\(struct device \*dev\)$/ { in_fn = 1 }
		in_fn && index($0, "pm: resume complete") { next }
		in_fn && /^}/ { in_fn = 0 }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
plant_pm_silent_failure() {
	awk '
		/^static int sm750_pm_resume\(struct device \*dev\)$/ { in_fn = 1 }
		in_fn && !done && index($0, "pm: resume failed") { done = 1; next }
		in_fn && /^}/ { in_fn = 0 }
		{ print }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}

control_scratch=${TMPDIR:-/mega/tmp/sm750/tmp}/drm-policy-control.$$
mkdir -p "$control_scratch"
trap 'rm -rf "$control_scratch"' EXIT

control_count=0
control() {
	local name=$1
	local planted=$control_scratch/sm750_drm.c
	local err=$control_scratch/stderr

	control_count=$((control_count + 1))
	cp "$source_file" "$planted"
	shift
	"$@" "$planted"
	if runtime_guard_properties "$planted" >/dev/null 2>"$err"; then
		echo "Runtime guard: negative control $name was not rejected." >&2
		exit 1
	fi
	echo "negative control $name: rejected (exit 1): $(head -n 1 "$err")"
}

guard_count=$(runtime_guard_properties "$source_file")
control plane_covers_mode plant_plane_covers_mode
control direct_vram_bound plant_direct_vram_bound
control test_pattern_string plant_test_pattern_string
control pin_range plant_pin_range
control vram_floor plant_vram_floor
control completion_recheck plant_completion_recheck
control enable_fail_reports_live_pipe plant_enable_fail_reports_live_pipe
control edid_sleep plant_edid_sleep
control event_get_under_lock plant_event_get_under_lock
control int_mask_rearm plant_int_mask_rearm
control crc_zero_mode plant_crc_zero_mode
control disable_geometry plant_disable_geometry
control header_zero_mode plant_header_zero_mode
control pm_no_suspend_entry plant_pm_no_suspend_entry
control pm_no_resume_complete plant_pm_no_resume_complete
control pm_silent_failure plant_pm_silent_failure

echo "DRM mode policy checks passed ($guard_count runtime-guard assertions, $control_count planted controls)"
