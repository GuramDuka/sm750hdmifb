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
# requires every mutated copy to fail while the unmutated copy passes. The
# mutated copies run against fixture card trees (lit and idle) and a stand-in
# probe, so a self-test does not need a lit panel; the unmutated copy also runs
# once against the real device. It needs the built check-vblank helper (the
# stand-in replaces it only for the controls) and a read-write DRM node, and
# exits 77 with one SKIP line when either is missing.
#
# The live probe needs an enabled CRTC: DRM answers DRM_IOCTL_WAIT_VBLANK with
# EINVAL when every pipe is off, which measures the device state and not the
# driver. When the driver's active_crtc attribute (or, for an older module
# without it, the bound connectors' enabled attribute) proves that no pipe is
# on, the gate prints one SKIP line naming the measurement instead of letting
# that EINVAL fail the run. Like the other two preconditions, that SKIP leaves
# the gate at exit 0 and is not a pass.
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
# falls back to 60 with a note on stderr, so a bogus attribute never invents an
# expectation. sysfs_crtc is the same card node's own "no pipe" marker.
sysfs_card=/sys/class/drm/$(basename -- "$device")
sysfs_refresh=$sysfs_card/device/active_mode_refresh_hz
sysfs_crtc=$sysfs_card/device/active_crtc
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

# Evidence that no CRTC is enabled on $device, empty when a pipe is on or the
# state cannot be measured. DRM returns EINVAL from DRM_IOCTL_WAIT_VBLANK when
# every pipe is off: that measures the device state, not the driver (A44). The
# driver's active_crtc is authoritative when it reads; a module older than that
# attribute is judged by the bound connectors' enabled attribute.
no_enabled_crtc() {
	local index= connectors= path name value
	if [ -r "$sysfs_crtc" ]; then
		index=$(tr -d ' \t\r\n' <"$sysfs_crtc" || true)
	fi
	case $index in
	-*) ;;
	'') ;;
	*[!0-9]*) ;;
	*) return 1 ;;
	esac
	for path in "$sysfs_card"-*/enabled; do
		[ -r "$path" ] || continue
		name=$(basename -- "${path%/enabled}")
		value=$(tr -d ' \t\r\n' <"$path" || true)
		[ -n "$value" ] || continue
		connectors="${connectors:+$connectors, }connector $name enabled=$value"
	done
	case $index in
	-*)
		printf 'active_crtc=%s%s\n' "$index" "${connectors:+, $connectors}"
		return 0
		;;
	esac
	[ -n "$connectors" ] || return 1
	case $connectors in
	*'enabled=enabled'*) return 1 ;;
	esac
	printf '%s\n' "$connectors"
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
	local link card lit idle live idle_skip old_idle old_lit

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
	link=$self_test_scratch/tests/check-vblank
	copy=$self_test_scratch/tests/check-drm-module.sh
	# A path that cannot exist, so both attribute sources are unreadable.
	unreadable=/nonexistent/active_mode_refresh_hz

	# A vblank probe cannot run without an enabled pipe (DRM answers EINVAL,
	# A44), so the controls must not depend on a lit panel: they run against a
	# fixture card tree and a stand-in for tests/check-vblank. The stand-in
	# keeps the helper's contract (two arguments, the 20..250 Hz range, a
	# measured rate of $derived, the 5% tolerance) on a lit card, and answers
	# EINVAL on an idle one. The unmutated copy runs against the fixture tree
	# and, separately, against the real device.
	card=$(basename -- "$device")
	lit=$self_test_scratch/sysfs/lit/$card
	idle=$self_test_scratch/sysfs/idle/$card
	mkdir -p -- "$lit/device" "$lit-HDMI-A-1" "$idle/device" "$idle-HDMI-A-1"
	printf '0\n' >"$lit/device/active_crtc"
	printf '%s\n' "$derived" >"$lit/device/active_mode_refresh_hz"
	printf 'enabled\n' >"$lit-HDMI-A-1/enabled"
	printf '%s\n' -1 >"$idle/device/active_crtc"
	printf 'disabled\n' >"$idle-HDMI-A-1/enabled"
	stub_lit=$self_test_scratch/stub-lit
	stub_idle=$self_test_scratch/stub-idle
	cat >"$stub_lit" <<EOF
#!/bin/sh
# tests/check-vblank stand-in for a card lit at $derived Hz.
case \$2 in
'' | *[!0-9.]*) echo "invalid expected refresh: \$2" >&2; exit 2 ;;
esac
awk -v hz="\$2" 'BEGIN { exit !(hz >= 20 && hz <= 250) }' || {
	echo "invalid expected refresh: \$2" >&2
	exit 2
}
echo "Measured $derived DRM vblanks/s over 120 events (expected \$2)"
awk -v hz="\$2" 'BEGIN { exit !(hz >= $derived * 0.95 && hz <= $derived * 1.05) }' || {
	echo "vblank rate is outside the 5% tolerance" >&2
	exit 1
}
EOF
	cat >"$stub_idle" <<'EOF'
#!/bin/sh
# tests/check-vblank stand-in for a card whose every CRTC is off: DRM answers
# DRM_IOCTL_WAIT_VBLANK with EINVAL (A44).
echo "DRM_IOCTL_WAIT_VBLANK: Invalid argument" >&2
exit 1
EOF

	# point_at COPY CARD_NODE: the copy resolves its card node in the fixture
	# tree instead of /sys/class/drm.
	point_at() {
		mutate "$1" \
			$'\nsysfs_card=/sys/class/drm/$(basename -- "$device")\n' \
			$'\nsysfs_card='"$2"$'\n'
	}
	install -m 755 "$stub_lit" "$link"

	# (a) the derived refresh replaced by a hardcoded value.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$lit" || return 1
	mutate "$copy" $'\n\t\t\texpected_refresh=$hz\n' \
		$'\n\t\t\texpected_refresh='"$wrong_hz"$'\n' || return 1
	control hardcoded-refresh "$copy" "$module" \
		'vblank rate is outside the 5% tolerance' || fail=1
	controls=$((controls + 1))

	# (b) the 20..250 range check removed, so a bogus 999 reaches the probe.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$lit" || return 1
	mutate "$copy" $'\n\t\t\texpected_refresh=$hz\n' \
		$'\n\t\t\texpected_refresh=999\n' || return 1
	mutate "$copy" $'\n\t\tif ! plausible_refresh "$expected_refresh"; then\n' \
		$'\n\t\tif false; then\n' || return 1
	control no-range-check "$copy" "$module" 'invalid expected refresh: 999' ||
		fail=1
	controls=$((controls + 1))

	# (c) the PCI sysfs fallback removed and the no-attribute path yielding 0.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$lit" || return 1
	mutate "$copy" $'\nsysfs_refresh=$sysfs_card/device/active_mode_refresh_hz\n' \
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
	point_at "$copy" "$lit" || return 1
	mutate "$copy" $'\nsysfs_refresh=$sysfs_card/device/active_mode_refresh_hz\n' \
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

	# (e) the no-pipe precondition removed: an idle card reaches the probe, and
	# the EINVAL DRM answers must not silently decide the run.
	install -m 755 "$stub_idle" "$link"
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$idle" || return 1
	mutate "$copy" $'\nelif evidence=$(no_enabled_crtc); then\n' \
		$'\nelif false; then\n' || return 1
	control no-pipe-precondition "$copy" "$module" \
		'DRM_IOCTL_WAIT_VBLANK: Invalid argument' || fail=1
	controls=$((controls + 1))

	# The intact copy on the same idle fixture must skip with the measurement
	# and never reach the probe: that is the precondition (e) removes.
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$idle" || return 1
	idle_skip="SKIP: the SM750 has no enabled CRTC (active_crtc=-1, connector $card-HDMI-A-1 enabled=disabled)"
	if out=$(bash "$copy" "$module" 2>&1); then
		if grep -qF -- "$idle_skip" <<<"$out"; then
			echo "no-pipe precondition: skipped with the measured evidence"
		else
			echo "check-drm-module --self-test: idle copy did not name the measured evidence: $(head -n 1 <<<"$out")" >&2
			fail=1
		fi
	else
		echo "check-drm-module --self-test: idle copy failed: $(head -n 1 <<<"$out")" >&2
		fail=1
	fi

	# An older module has no active_crtc, so the bound connector decides: a
	# missing attribute must not read as "pipe on" (a false skip would hide a
	# real probe) and an enabled connector must not read as "pipe off".
	old_idle=$self_test_scratch/sysfs/old-idle/$card
	old_lit=$self_test_scratch/sysfs/old-lit/$card
	mkdir -p -- "$old_idle/device" "$old_idle-HDMI-A-1" \
		"$old_lit/device" "$old_lit-HDMI-A-1"
	printf 'disabled\n' >"$old_idle-HDMI-A-1/enabled"
	printf 'enabled\n' >"$old_lit-HDMI-A-1/enabled"
	printf '%s\n' "$derived" >"$old_lit/device/active_mode_refresh_hz"
	install -m 755 "$stub_idle" "$link"
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$old_idle" || return 1
	if out=$(bash "$copy" "$module" 2>&1) &&
		grep -qF -- "SKIP: the SM750 has no enabled CRTC (connector $card-HDMI-A-1 enabled=disabled)" <<<"$out"; then
		echo "no-pipe precondition: an absent active_crtc falls back to the connector"
	else
		echo "check-drm-module --self-test: connector-only idle card did not skip with the connector evidence: $(head -n 1 <<<"$out")" >&2
		fail=1
	fi
	install -m 755 "$stub_lit" "$link"
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$old_lit" || return 1
	if out=$(bash "$copy" "$module" 2>&1) &&
		grep -qF -- "at $derived Hz (expected refresh from" <<<"$out"; then
		echo "no-pipe precondition: an enabled connector still reaches the probe"
	else
		echo "check-drm-module --self-test: connector-enabled card did not reach the probe: $(head -n 1 <<<"$out")" >&2
		fail=1
	fi

	# The unmutated copy must pass on a lit card and name the refresh it used.
	install -m 755 "$stub_lit" "$link"
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	point_at "$copy" "$lit" || return 1
	if out=$(bash "$copy" "$module" 2>&1); then
		if grep -qF -- "at $derived Hz (expected refresh from" <<<"$out"; then
			echo "negative control pristine: accepted at $derived Hz (fixture card)"
			live="probe at $derived Hz"
		else
			echo "check-drm-module --self-test: pristine copy did not name $derived Hz" >&2
			fail=1
		fi
	else
		echo "check-drm-module --self-test: pristine copy failed: $(head -n 1 <<<"$out")" >&2
		fail=1
	fi

	# And once against the real device: the probe when a pipe is on, the skip
	# when it is off. Anything else means the two paths disagree.
	rm -f -- "$link"
	ln -s "$project_dir/tests/check-vblank" "$link"
	cp "$project_dir/tests/check-drm-module.sh" "$copy"
	if out=$(bash "$copy" "$module" 2>&1); then
		if grep -qF -- "at $derived Hz (expected refresh from" <<<"$out"; then
			live="probe at $derived Hz"
		elif grep -qF -- 'SKIP: the SM750 has no enabled CRTC (active_crtc=' <<<"$out"; then
			live='skipped, no enabled CRTC'
		else
			echo "check-drm-module --self-test: live copy neither probed nor skipped: $(head -n 1 <<<"$out")" >&2
			fail=1
		fi
	else
		echo "check-drm-module --self-test: live copy failed: $(head -n 1 <<<"$out")" >&2
		fail=1
	fi

	[ "$fail" -eq 0 ] || return 1
	echo "DRM module self-test passed ($controls planted controls rejected, pristine copy accepted at $derived Hz; live device: ${live:-unknown})"
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
# DRM device; report a skip with the exact reason when the node is denied or no
# pipe is enabled instead of claiming the path was exercised.
if [[ ! -x $project_dir/tests/check-vblank ]]; then
	echo "SKIP: tests/check-vblank is not built; run make check first. This is not a pass."
elif [[ ! -r $device || ! -w $device ]]; then
	echo "SKIP: cannot open $device read-write as uid $(id -u); grant the video group or run tests/check-vblank $device ${SM750_DRM_EXPECTED_HZ:-<active mode refresh>} as root. This is not a pass."
elif evidence=$(no_enabled_crtc); then
	echo "SKIP: the SM750 has no enabled CRTC ($evidence); a vblank ioctl probe needs an enabled pipe. This is not a pass."
else
	resolve_expected_refresh
	"$project_dir/tests/check-vblank" "$device" "$expected_refresh"
	echo "DRM vblank ioctl checks passed: $device at $expected_refresh Hz (expected refresh from $expected_refresh_source)"
fi
echo "DRM module metadata checks passed: $module"
