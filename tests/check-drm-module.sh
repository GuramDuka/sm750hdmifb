#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Gate for the built module: metadata, required symbols, the read-only debugfs
# register dump, and the live vblank ioctl probe. Usage:
#
#   tests/check-drm-module.sh MODULE.ko
#   tests/check-drm-module.sh --self-test [MODULE.ko]
#
# --self-test takes the module as an optional second argument (default
# src/sm750hdmidrm.ko), copies this script, plants one defect per control and
# requires every mutated copy to fail while the unmutated copy passes. It needs
# the built check-vblank helper and a read-write DRM node, and exits 77 with one
# SKIP line when either is missing.
#
# The live probe's expectation is the driver's own active-mode refresh
# (active_mode_refresh_hz), not an assumed 60 Hz: a hardcoded 60 failed a panel
# programmed at 75 Hz (defect A44). SM750_DRM_EXPECTED_HZ still wins when set.
# A frozen vblank_count on an idle pipe is DRM core's vblankoffdelay, not a
# defect, so an idle reading of 0 Hz is never a failure signal here
# (docs/evidence/runtime/34-vblank-idle-freeze.txt).
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}
mkdir -p -- "$TMPDIR"

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
driver_source=$project_dir/src/sm750_drm.c
device=${SM750_DRM_DEVICE:-/dev/dri/card0}

# Expected refresh for the live probe. Preference order: the documented
# override, the mode's own attribute through the card node, then the same
# attribute through the PCI device. Anything that is not a number in 20..250
# falls back to 60 with a note on stderr, so the probe always runs.
sysfs_refresh=/sys/class/drm/$(basename -- "$device")/device/active_mode_refresh_hz
pci_refresh=/sys/bus/pci/devices/0000:01:00.0/active_mode_refresh_hz
expected_refresh=
expected_refresh_source=

plausible_refresh() {
	awk -v hz="$1" 'BEGIN { exit !(hz >= 20 && hz <= 250) }'
}

fallback_refresh() {
	echo "check-drm-module: $1; falling back to 60 Hz." >&2
	expected_refresh=60
	expected_refresh_source='fallback 60 Hz'
}

resolve_expected_refresh() {
	local attr hz
	if [ -n "${SM750_DRM_EXPECTED_HZ:-}" ]; then
		expected_refresh=$SM750_DRM_EXPECTED_HZ
		expected_refresh_source='SM750_DRM_EXPECTED_HZ'
	else
		for attr in "$sysfs_refresh" "$pci_refresh"; do
			[ -r "$attr" ] || continue
			hz=$(tr -d ' \t\r\n' <"$attr" || true)
			[ -n "$hz" ] || continue
			expected_refresh=$hz
			expected_refresh_source=$attr
			break
		done
	fi
	case $expected_refresh in
	'' | *[!0-9.]*)
		fallback_refresh "no numeric refresh from $sysfs_refresh or $pci_refresh"
		;;
	*)
		if ! plausible_refresh "$expected_refresh"; then
			fallback_refresh "refresh '$expected_refresh' Hz from $expected_refresh_source is outside 20..250"
		fi
		;;
	esac
	return 0
}

self_test_scratch=

mutate() {
	python3 - "$1" "$2" "$3" <<'PY'
import io, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = io.open(path, encoding="ascii").read()
if text.count(old) != 1:
	raise SystemExit("mutation anchor appears %d times: %r" %
		(text.count(old), old))
io.open(path, "w", encoding="ascii").write(text.replace(old, new))
PY
}

control() {
	local name=$1 copy=$2 module=$3 pattern=$4 out
	if out=$(bash "$copy" "$module" 2>&1); then
		echo "check-drm-module --self-test: control $name was not rejected" >&2
		return 1
	fi
	if ! grep -qF -- "$pattern" <<<"$out"; then
		echo "check-drm-module --self-test: control $name failed for the wrong reason: $(head -n 1 <<<"$out")" >&2
		return 1
	fi
	echo "negative control $name: rejected: $(grep -m 1 -F -- "$pattern" <<<"$out")"
	return 0
}

self_test() {
	local module=${2:-$project_dir/src/sm750hdmidrm.ko}
	local copy out derived wrong_hz controls=0 fail=0

	if [ ! -s "$module" ]; then
		echo "check-drm-module --self-test: no built module at $module; run make check or pass MODULE.ko. This is not a pass." >&2
		return 2
	fi
	if [ ! -x "$project_dir/tests/check-vblank" ]; then
		echo "SKIP: --self-test needs the built tests/check-vblank; run make check first. This is not a pass."
		return 77
	fi
	if [ ! -r "$device" ] || [ ! -w "$device" ]; then
		echo "SKIP: --self-test cannot open $device read-write as uid $(id -u); the live controls need the probe to run. This is not a pass."
		return 77
	fi

	expected_refresh=
	expected_refresh_source=
	resolve_expected_refresh
	derived=$expected_refresh
	# Control (a) must disagree with the refresh the probe measures.
	wrong_hz=60
	if [ "$derived" = 60 ] || [ "$derived" = 60.00 ]; then
		wrong_hz=30
	fi

	self_test_scratch=$(mktemp -d "${TMPDIR}/sm750-drm-module.XXXXXX")
	trap 'rm -rf -- "$self_test_scratch"' EXIT
	mkdir -p -- "$self_test_scratch/tests"
	ln -s "$project_dir/src" "$self_test_scratch/src"
	ln -s "$project_dir/build-package.sh" "$self_test_scratch/build-package.sh"
	ln -s "$project_dir/tests/check-vblank" "$self_test_scratch/tests/check-vblank"
	copy=$self_test_scratch/tests/check-drm-module.sh
	# A path that cannot exist, so both attribute sources are unreadable.
	unreadable=/nonexistent/active_mode_refresh_hz

	# (a) the derived refresh replaced by a hardcoded value.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	mutate "$copy" $'\n\t\t\texpected_refresh=$hz\n' \
		$'\n\t\t\texpected_refresh='"$wrong_hz"$'\n' || return 1
	control hardcoded-refresh "$copy" "$module" \
		'vblank rate is outside the 5% tolerance' || fail=1
	controls=$((controls + 1))

	# (b) the 20..250 range check removed, so a bogus 999 reaches the probe.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	mutate "$copy" $'\n\t\t\texpected_refresh=$hz\n' \
		$'\n\t\t\texpected_refresh=999\n' || return 1
	mutate "$copy" $'\n\t\tif ! plausible_refresh "$expected_refresh"; then\n' \
		$'\n\t\tif false; then\n' || return 1
	control no-range-check "$copy" "$module" 'invalid expected refresh: 999' ||
		fail=1
	controls=$((controls + 1))

	# (c) the PCI sysfs fallback removed and the no-attribute path yielding 0.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	mutate "$copy" $'\nsysfs_refresh=/sys/class/drm/$(basename -- "$device")/device/active_mode_refresh_hz\n' \
		$'\nsysfs_refresh='$unreadable$'\n' || return 1
	mutate "$copy" $'\n\t\tfor attr in "$sysfs_refresh" "$pci_refresh"; do\n' \
		$'\n\t\tfor attr in "$sysfs_refresh"; do\n' || return 1
	mutate "$copy" \
		$'\n\t\tfallback_refresh "no numeric refresh from $sysfs_refresh or $pci_refresh"\n' \
		$'\n\t\texpected_refresh=0\n' || return 1
	control no-attribute-fallback "$copy" "$module" \
		'invalid expected refresh: 0' || fail=1
	controls=$((controls + 1))

	# (d) no attribute readable at all: the substitution must be announced, so
	# a silent 60 Hz can never stand in for a derived refresh.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	mutate "$copy" $'\nsysfs_refresh=/sys/class/drm/$(basename -- "$device")/device/active_mode_refresh_hz\n' \
		$'\nsysfs_refresh='$unreadable$'\n' || return 1
	mutate "$copy" $'\n\t\tfor attr in "$sysfs_refresh" "$pci_refresh"; do\n' \
		$'\n\t\tfor attr in "$sysfs_refresh"; do\n' || return 1
	if out=$(bash "$copy" "$module" 2>&1); then :; fi
	if grep -qF -- 'falling back to 60 Hz' <<<"$out"; then
		echo "negative control missing-attribute-note: announced: $(grep -m 1 -F -- 'falling back to 60 Hz' <<<"$out")"
	else
		echo "check-drm-module --self-test: control missing-attribute-note did not announce the 60 Hz substitution" >&2
		fail=1
	fi

	# The unmutated copy must pass, and must name the refresh it used.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	if out=$(bash "$copy" "$module" 2>&1); then
		if grep -qF -- "at $derived Hz (expected refresh from" <<<"$out"
		then
			echo "negative control pristine: accepted"
		else
			echo "check-drm-module --self-test: pristine copy did not name $derived Hz" >&2
			fail=1
		fi
	else
		echo "check-drm-module --self-test: pristine copy failed: $(head -n 1 <<<"$out")" >&2
		fail=1
	fi

	[ "$fail" -eq 0 ] || return 1
	echo "DRM module self-test passed ($controls planted controls rejected, pristine copy accepted at $derived Hz)"
	return 0
}

if [ "${1:-}" = --self-test ]; then
	rc=0
	self_test "$@" || rc=$?
	case $rc in
	0) exit 0 ;;
	77) exit 77 ;;
	*) exit 1 ;;
	esac
fi

module=${1:?usage: check-drm-module.sh MODULE.ko}

test -s "$module"
test "$(modinfo -F name "$module")" = sm750hdmidrm
test "$(modinfo -F license "$module")" = "GPL v2"
expected_version=$(sed -n 's/^readonly version=//p' "$project_dir/build-package.sh")
test -n "$expected_version"
test "$(modinfo -F version "$module")" = "$expected_version"
grep -F "#define SM750_DRM_VERSION \"$expected_version\"" "$driver_source" >/dev/null
grep -F 'MODULE_VERSION(SM750_DRM_VERSION)' "$driver_source" >/dev/null
modinfo -F alias "$module" | grep 'v0000126Fd00000750' >/dev/null
modinfo -F description "$module" | grep 'DRM' >/dev/null
modinfo -F parm "$module" | grep '^preferred_width:' >/dev/null
modinfo -F parm "$module" | grep '^preferred_height:' >/dev/null
modinfo -F parm "$module" | grep '^preferred_refresh:' >/dev/null
modinfo -F parm "$module" | grep '^scanout_format:' >/dev/null
modinfo -F parm "$module" | grep '^dither_green_gain:' >/dev/null
for parameter in edid_only softscale_wide sharpen double_shadow \
		disable_hardware_cursor enable_dma disable_dma async_updates; do
	modinfo -F parm "$module" | grep "^${parameter}:" >/dev/null
done
readelf -h "$module" | grep 'ELF64' >/dev/null
if strings "$module" | grep -x 'sm750fb' >/dev/null; then
	echo "DRM module contains the stock module name as an identity." >&2
	exit 1
fi
undefined=$(nm -u "$module")
for symbol in drm_crtc_arm_vblank_event drm_crtc_vblank_get \
		drm_crtc_vblank_off drm_crtc_vblank_on \
		drm_vblank_init; do
	grep -E "[[:space:]]${symbol}$" <<<"$undefined" >/dev/null || {
		echo "DRM module lacks required vblank symbol: $symbol" >&2
		exit 1
	}
done
for symbol in drm_gem_shmem_dumb_create \
		drm_gem_simple_kms_begin_shadow_fb_access \
		drm_gem_simple_kms_end_shadow_fb_access; do
	grep -E "[[:space:]]${symbol}$" <<<"$undefined" >/dev/null || {
		echo "DRM module lacks required RGB565 shadow symbol: $symbol" >&2
		exit 1
	}
done
grep -E '[[:space:]]drm_crtc_handle_vblank$' <<<"$undefined" \
	>/dev/null || {
	echo "DRM module lacks private timer handler." >&2
	exit 1
}
if grep -E '[[:space:]]drm_crtc_vblank_(helper_.*_timer|start_timer|cancel_timer)$' \
		<<<"$undefined" >/dev/null; then
	echo "DRM module uses the core timer with the callback restart race." >&2
	exit 1
fi
for symbol in devm_request_threaded_irq wait_for_completion_timeout; do
	grep -E "[[:space:]]${symbol}$" <<<"$undefined" >/dev/null || {
		echo "DRM module lacks asynchronous DMA symbol: $symbol" >&2
		exit 1
	}
done
# Register-dump facility: a read-only debugfs file, registered from both
# drivers, whose handler must never write to the device.
grep -F 'debugfs_create_file("regs", 0444' "$driver_source" >/dev/null
grep -F 'DEFINE_SHOW_ATTRIBUTE(sm750_regs)' "$driver_source" >/dev/null
grep -F '.debugfs_init = sm750_vram_debugfs_init' "$driver_source" >/dev/null
grep -F '.debugfs_init = sm750_debugfs_init' "$driver_source" >/dev/null
show_body=$(sed -n '/^static int sm750_regs_show/,/^DEFINE_SHOW_ATTRIBUTE(sm750_regs)/p' \
	"$driver_source")
grep -F 'sm750_regs_show' <<<"$show_body" >/dev/null
if grep -E 'writel|poke32|iowrite' <<<"$show_body" >/dev/null; then
	echo "Register dump handler writes to the device; it must stay read-only." >&2
	exit 1
fi
# Live device probe. The vblank ioctl path is the only test that touches the
# DRM device; report a skip with the exact reason when the node is denied
# instead of claiming the path was exercised.
if [[ ! -x $project_dir/tests/check-vblank ]]; then
	echo "SKIP: tests/check-vblank is not built; run make check first. This is not a pass."
elif [[ ! -r $device || ! -w $device ]]; then
	echo "SKIP: cannot open $device read-write as uid $(id -u); grant the video group or run tests/check-vblank $device ${SM750_DRM_EXPECTED_HZ:-<active mode refresh>} as root. This is not a pass."
else
	resolve_expected_refresh
	"$project_dir/tests/check-vblank" "$device" "$expected_refresh"
	echo "DRM vblank ioctl checks passed: $device at $expected_refresh Hz (expected refresh from $expected_refresh_source)"
fi
echo "DRM module metadata checks passed: $module"
