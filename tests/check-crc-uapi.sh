#!/usr/bin/env bash
# Copyright (c) 2026 SM750 DRM contributors
# SPDX-License-Identifier: GPL-2.0
#
# T30 gate: DRM core owns crtc-N/crc/{control,data} and routes both to the
# driver's drm_crtc_funcs hooks; it creates no crc/source file. A driver that
# creates its own crc debugfs files shadows core's, so writes through core's
# control file never reach core's state and reads of core's data file fail
# with EIO/EINVAL. The gate therefore requires the three callbacks and forbids
# any CRC debugfs file in src/.
#
# The readback window is a module parameter so a whole visible frame can be
# read: crc_window_bytes must stay writable (mode 0644), the reader must keep
# sampling it at use time and must keep clamping it to the visible scanout
# area, and the release that promises this must be the version every packaging
# site carries. Asserted here so a later edit cannot quietly pin the window
# back to 0444 or drop the clamp.
#
# Usage: tests/check-crc-uapi.sh [source file]
#        tests/check-crc-uapi.sh --single [source file]   (no self-test)

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
	echo "CRC uapi: $1" >&2
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

# The CRC debugfs files and the driver ring that backed them are gone: they
# duplicated DRM core's own crc/control and crc/data. Checked over every src
# file so a shim cannot survive in a second translation unit.
check_no_shim() {
	local file=$1
	local line symbol

	line=$(grep -nE 'debugfs_create_(file|dir)\("(crc|source|control|data)"' \
		"$file" | head -n 1 || true)
	[ -z "$line" ] ||
		fail "$file still creates a CRC debugfs file: $line"

	for symbol in sm750_crc_source_fops sm750_crc_control_fops \
		sm750_crc_data_fops sm750_crc_debugfs_create sm750_crc_push \
		SM750_CRC_ENTRIES SM750_CRC_COUNT_LINE SM750_CRC_LINE_LEN \
		crc_ring crc_opened crc_count_sent; do
		if grep -F "$symbol" "$file" >/dev/null; then
			fail "$file still carries the deleted driver CRC shim symbol $symbol"
		fi
	done
}

check_file() {
	local file=$1
	local funcs body callback

	check_no_shim "$file"

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

	# DRM core calls these three; the driver owns no files of its own.
	grep -F 'static const char *const *sm750_crtc_get_crc_sources' \
		"$file" >/dev/null ||
		fail "$file: sm750_crtc_get_crc_sources not found"
	body=$(fn_body "$file" 'static const char *const *sm750_crtc_get_crc_sources(')
	grep -F '*count = 1;' <<<"$body" >/dev/null ||
		fail "get_crc_sources does not report exactly one source"
	grep -F 'static const char *const sm750_crc_sources[] = { "scanout", NULL };' \
		"$file" >/dev/null ||
		fail "the CRC source list is not a static array holding scanout"

	# Documented requirement: "auto" selects a default source and must be
	# accepted. Both verify and set route through the same name test.
	body=$(fn_body "$file" 'static bool sm750_crc_source_is_scanout(')
	[ -n "$body" ] || fail "$file: sm750_crc_source_is_scanout not found"
	grep -F 'strcmp(source, "scanout")' <<<"$body" >/dev/null ||
		fail "the source name test does not accept scanout"
	grep -F 'strcmp(source, "auto")' <<<"$body" >/dev/null ||
		fail "the source name test does not accept auto"

	body=$(fn_body "$file" 'static int sm750_crtc_verify_crc_source(')
	[ -n "$body" ] || fail "$file: sm750_crtc_verify_crc_source not found"
	grep -F '*values_cnt = 1;' <<<"$body" >/dev/null ||
		fail "verify_crc_source does not report one CRC value per entry"
	grep -F 'sm750_crc_source_is_scanout(source)' <<<"$body" >/dev/null ||
		fail "verify_crc_source does not accept the driver's source names"
	grep -F 'return -EINVAL;' <<<"$body" >/dev/null ||
		fail "verify_crc_source never rejects an unknown source"
	# A NULL source disables CRC generation: it must not be rejected.
	if sed -n '1,/sm750_crc_source_is_scanout(source)/p' <<<"$body" |
		grep -F 'return -EINVAL;' >/dev/null; then
		fail "verify_crc_source rejects a NULL source instead of disabling"
	fi

	body=$(fn_body "$file" 'static int sm750_crtc_set_crc_source(')
	[ -n "$body" ] || fail "$file: sm750_crtc_set_crc_source not found"
	grep -F 'sm750_crc_source_is_scanout(source)' <<<"$body" >/dev/null ||
		fail "set_crc_source does not route auto and scanout through one test"
	grep -F 'sm750_crc_disable(sdev);' <<<"$body" >/dev/null ||
		fail "set_crc_source has no disable path"
	grep -F 'sm750_crc_enable(sdev);' <<<"$body" >/dev/null ||
		fail "set_crc_source has no enable path"
}

# The stream must not die when the scanout window is unreadable, the enable
# path must refuse instead of arming a stream that cannot produce entries, and
# the reason for a missing window must be reported once per enable cycle.
check_stream() {
	local file=$1
	local body structure schedule_line

	body=$(fn_body "$file" 'static void sm750_crc_work_fn(')
	[ -n "$body" ] || fail "$file: sm750_crc_work_fn not found"
	# Enabled, the tick publishes to DRM core; core owns the ring.
	grep -F 'drm_crtc_add_crc_entry(crtc, true, frame, &crc)' <<<"$body" >/dev/null ||
		fail "the CRC tick does not publish a frame-counted entry through drm_crtc_add_crc_entry"
	if grep -F 'sm750_crc_push' <<<"$body" >/dev/null; then
		fail "the CRC tick still fills a driver ring instead of DRM core"
	fi
	# The region check decides what a tick does, not whether it continues.
	grep -F 'sm750_crc_region(sdev, &offset, &length, &missing)' <<<"$body" >/dev/null ||
		fail "the CRC tick does not check the scanout region"
	grep -F 'sm750_crc_region_warn(sdev, missing)' <<<"$body" >/dev/null ||
		fail "the CRC tick drops an unreadable window without reporting why"

	# The re-arm is the last statement, behind a top-level crc_enabled guard
	# only: one failed region read must not end the stream.
	structure=$(awk '
		index($0, "drm_vblank_work_schedule(&sdev->crc_work") {
			sched = NR
			exit
		}
		/^\tif \(READ_ONCE\(sdev->crc_enabled\)\) \{$/ { top_guard = NR }
		/^[[:space:]]*if \(READ_ONCE\(sdev->crc_enabled\)\) \{$/ { last_guard = NR }
		/^[[:space:]]*return;$/ { returned = NR }
		END {
			if (!sched)
				print "no-rearm"
			else if (returned && returned < sched)
				print "early-return"
			else if (!last_guard)
				print "no-guard"
			else if (last_guard != top_guard)
				print "guard-nested"
			else
				print "ok", last_guard, sched
		}' <<<"$body")
	case $structure in
	"ok "*) ;;
	no-rearm) fail "the CRC tick never re-arms the vblank work" ;;
	early-return)
		fail "the CRC tick can return before it re-arms: one region failure ends the stream"
		;;
	no-guard) fail "the CRC tick re-arms without a crc_enabled guard" ;;
	guard-nested)
		fail "the re-arm guard is nested inside the region check, so one failed read ends the stream"
		;;
	*) fail "unexpected CRC tick structure: $structure" ;;
	esac
	set -- $structure
	schedule_line=$3
	if sed -n "${2},${schedule_line}p" <<<"$body" |
		grep -F 'sm750_crc_region' >/dev/null; then
		fail "the re-arm sits inside the region check"
	fi

	# enable: validate first, then arm, then fail loudly with -ENODEV.
	body=$(fn_body "$file" 'static int sm750_crc_enable(')
	[ -n "$body" ] || fail "$file: sm750_crc_enable not found"
	grep -F 'sm750_crc_region(sdev, &offset, &length, &missing)' <<<"$body" >/dev/null ||
		fail "sm750_crc_enable arms the stream without checking the scanout region"
	grep -F 'ret = -ENODEV;' <<<"$body" >/dev/null ||
		fail "sm750_crc_enable does not fail with -ENODEV on missing geometry"
	validate_line=$(first_line "$body" 'sm750_crc_region(sdev')
	enabled_line=$(first_line "$body" 'sdev->crc_enabled = true;')
	[ -n "$enabled_line" ] || fail "sm750_crc_enable never sets crc_enabled"
	test "$validate_line" -lt "$enabled_line" ||
		fail "sm750_crc_enable validates the region only after enabling the source"

	# One warning per enable cycle: a latch, set in the warn helper and
	# cleared wherever the cycle ends.
	grep -F 'bool crc_warned;' "$file" >/dev/null ||
		fail "no warn-once latch for the CRC stream"
	body=$(fn_body "$file" 'static void sm750_crc_region_warn(')
	[ -n "$body" ] || fail "$file: sm750_crc_region_warn not found"
	grep -F 'READ_ONCE(sdev->crc_warned)' <<<"$body" >/dev/null ||
		fail "sm750_crc_region_warn has no latch: it would warn every vblank"
	grep -F 'WRITE_ONCE(sdev->crc_warned, true)' <<<"$body" >/dev/null ||
		fail "sm750_crc_region_warn never sets the latch"
	body=$(fn_body "$file" 'static void sm750_crc_stop(')
	[ -n "$body" ] || fail "$file: sm750_crc_stop not found"
	grep -F 'sdev->crc_warned = false;' <<<"$body" >/dev/null ||
		fail "disabling the source does not clear the warn-once latch"

	# Modeset: the stream is parked on disable and re-armed on enable, and
	# the re-arm has to run after drm_crtc_vblank_on() rebuilt the counter.
	body=$(fn_body "$file" 'static void sm750_pipe_enable(')
	[ -n "$body" ] || fail "$file: sm750_pipe_enable not found"
	grep -F 'sm750_crc_resume(sdev);' <<<"$body" >/dev/null ||
		fail "sm750_pipe_enable never re-arms the CRC stream after a modeset"
	on_line=$(first_line "$body" 'drm_crtc_vblank_on(&pipe->crtc);')
	resume_line=$(first_line "$body" 'sm750_crc_resume(sdev);')
	[ -n "$on_line" ] || fail "sm750_pipe_enable never calls drm_crtc_vblank_on()"
	test "$resume_line" -gt "$on_line" ||
		fail "sm750_pipe_enable re-arms the CRC stream before drm_crtc_vblank_on()"
	body=$(fn_body "$file" 'static void sm750_pipe_disable(')
	[ -n "$body" ] || fail "$file: sm750_pipe_disable not found"
	grep -F 'sm750_crc_suspend(sdev);' <<<"$body" >/dev/null ||
		fail "sm750_pipe_disable stops the CRC source instead of parking it"
}

# A whole 1920x1080 XRGB8888 frame is 8294400 bytes, so the window has to be
# growable at runtime; a 0444 parameter makes the default the hard ceiling.
# The reader must sample the live value and keep its min() against the visible
# frame, which is what stops a nonsensical write from reading past it.
check_window() {
	local file=$1
	local body line

	grep -F 'module_param(crc_window_bytes, uint, 0644);' "$file" >/dev/null ||
		fail "$file: crc_window_bytes is not writable (expected mode 0644)"
	! grep -F 'module_param(crc_window_bytes, uint, 0444);' "$file" >/dev/null ||
		fail "$file: crc_window_bytes is still read-only (mode 0444)"
	grep -F 'static unsigned int crc_window_bytes = 262144;' "$file" >/dev/null ||
		fail "$file: the crc_window_bytes default is no longer 262144"

	body=$(fn_body "$file" 'static bool sm750_crc_region(')
	[ -n "$body" ] || fail "$file: sm750_crc_region not found"
	grep -F 'READ_ONCE(crc_window_bytes)' <<<"$body" >/dev/null ||
		fail "sm750_crc_region does not sample the live crc_window_bytes value"
	# Writing a huge value is safe only because of this clamp; without it the
	# dump would walk past the visible frame into whatever follows in VRAM.
	grep -F 'window = round_down(min(window, visible), 4);' <<<"$body" >/dev/null ||
		fail "sm750_crc_region no longer clamps the window to the visible frame"
	line=$(first_line "$body" 'visible = min_t(u64, sdev->scanout_frame_size,')
	[ -n "$line" ] || fail "sm750_crc_region does not bound visible by the frame size"
}

# The writable window is a property of the release that carries it, so every
# packaging site must name the same, bumped version in the same tree.
check_release() {
	local file=$1
	local builder=$project_dir/build-package.sh
	local dkms_config=$project_dir/dkms.conf
	local spec=$project_dir/packaging/sm750hdmifb.spec
	local tools_spec=$project_dir/packaging/sm750hdmifb-tools.spec
	local ci_recipe=$project_dir/docs/ci/build.yml
	local version module_version reported spec_version tools_version spec_dkms
	local major minor patch

	version=$(sed -n 's/^readonly version=//p' "$builder")
	[ -n "$version" ] || fail "$builder: no readonly version="
	# The read-only window belonged to 0.6.5; claiming it again means the bump
	# was forgotten and the release notes would describe the wrong behaviour.
	test "$version" != "0.6.5" ||
		fail "build-package.sh still says 0.6.5; the writable window needs a release of its own"

	module_version=$(sed -n \
		's/^#define SM750_DRM_VERSION "\([^"]*\)"/\1/p' "$file")
	test "$module_version" = "$version" ||
		fail "$file: SM750_DRM_VERSION '$module_version' does not match build-package.sh '$version'"

	major=$(sed -n 's/^#define DRIVER_MAJOR \([0-9]\+\)$/\1/p' "$file")
	minor=$(sed -n 's/^#define DRIVER_MINOR \([0-9]\+\)$/\1/p' "$file")
	patch=$(sed -n 's/^#define DRIVER_PATCHLEVEL \([0-9]\+\)$/\1/p' "$file")
	reported="$major.$minor.$patch"
	test "$reported" = "$version" ||
		fail "$file: DRIVER_* report '$reported', build-package.sh says '$version'"

	grep -F "PACKAGE_VERSION=\"$version\"" "$dkms_config" >/dev/null ||
		fail "$dkms_config: PACKAGE_VERSION does not match '$version'"

	spec_dkms=$(sed -n \
		's/^%global dkms_version[[:space:]]*\([^[:space:]]*\)$/\1/p' "$spec")
	test "$spec_dkms" = "$version" ||
		fail "$spec: %global dkms_version '$spec_dkms' does not match '$version'"
	spec_version=$(sed -n 's/^Version:[[:space:]]*\([^[:space:]]*\)$/\1/p' "$spec")
	test "$spec_version" = "$version" ||
		fail "$spec: Version '$spec_version' does not match '$version'"
	tools_version=$(sed -n 's/^Version:[[:space:]]*\([^[:space:]]*\)$/\1/p' "$tools_spec")
	test "$tools_version" = "$version" ||
		fail "$tools_spec: Version '$tools_version' does not match '$version'"

	# CI artifact names are how the release is collected, so they carry the
	# same version; a stale name uploads nothing.
	grep -F "sm750hdmifb-$version-source.tar.gz" "$ci_recipe" >/dev/null ||
		fail "$ci_recipe: no source-up archive named for '$version'"
	grep -F "sm750hdmifb_${version}_all.deb" "$ci_recipe" >/dev/null ||
		fail "$ci_recipe: no module .deb named for '$version'"
}

plant_window_readonly() {
	sed -i 's/module_param(crc_window_bytes, uint, 0644);/module_param(crc_window_bytes, uint, 0444);/' "$1"
}
# A dropped clamp turns a large write into a read past the visible frame.
plant_clamp_dropped() {
	sed -i 's/window = round_down(min(window, visible), 4);/window = round_down(window, 4);/' "$1"
}
plant_version_drift() {
	sed -i 's/^#define SM750_DRM_VERSION ".*"$/#define SM750_DRM_VERSION "0.6.5"/' "$1"
}

check_window "$source_file"
check_release "$source_file"
check_file "$source_file"
check_stream "$source_file"
if [ "$mode" = full ]; then
	for other in "$project_dir"/src/*.c; do
		[ "$other" = "$source_file" ] && continue
		check_no_shim "$other"
	done
fi
echo "CRC uapi check passed: $source_file"

if [ "$mode" = single ]; then
	exit 0
fi

scratch=$(mktemp -d "${TMPDIR}/sm750-crc-uapi.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

plant_no_set_crc() { sed -i '/\.set_crc_source = sm750_crtc_set_crc_source,/d' "$1"; }
# The T30 defect: a driver-owned crc debugfs file shadows core's own.
plant_debugfs_shim() {
	printf '\nstatic void plant_crc_shim(void)\n{\n\tdebugfs_create_file("control", 0644, NULL, NULL, NULL);\n}\n' >>"$1"
}
# The defect this gate exists for: a return placed in front of the re-arm.
plant_early_return() {
	sed -i 's/sm750_crc_region_warn(sdev, missing);/sm750_crc_region_warn(sdev, missing);\n\t\t\treturn;/' "$1"
}
plant_enable_no_validate() { sed -i 's/ret = -ENODEV;/ret = 0;/' "$1"; }
plant_no_frame_counter() {
	sed -i 's/drm_crtc_add_crc_entry(crtc, true, frame, \&crc)/drm_crtc_add_crc_entry(crtc, false, frame, \&crc)/' "$1"
}
plant_no_auto() { sed -i 's/ || !strcmp(source, "auto")//' "$1"; }
plant_two_values() { sed -i 's/\*values_cnt = 1;/*values_cnt = 2;/' "$1"; }

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
control debugfs_shim plant_debugfs_shim
control early_return plant_early_return
control enable_without_region plant_enable_no_validate
control no_frame_counter plant_no_frame_counter
control no_auto_source plant_no_auto
control two_values plant_two_values
control window_readonly plant_window_readonly
control clamp_dropped plant_clamp_dropped
control version_drift plant_version_drift

echo "CRC uapi gate and negative controls passed"
