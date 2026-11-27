#!/usr/bin/env bash
# Copyright (c) 2026 SM750 DRM contributors
# SPDX-License-Identifier: GPL-2.0
#
# T52 gate: the twelve monitoring attributes tools/sm750-smi reads from
# /sys/class/drm/cardN/device/. The tool prints "n/a (driver attribute not
# present in this version)" for each one it cannot find, so a renamed or
# unregistered attribute silently degrades the tool instead of failing it.
# The gate therefore requires, in src/sm750_drm.c:
#   - one DEVICE_ATTR_RO() and one attribute-array entry per documented name,
#   - the group registered on &pdev->dev (the /sys/class/drm/cardN/device node)
#     before drm_dev_register(), and nowhere else,
#   - every show function to use dev_get_drvdata() with a NULL guard and
#     sysfs_emit(), to take no lock other than the driver's mode lock, and to
#     sleep nowhere,
#   - the link-status read to pass clear_events = false: a sysfs read must never
#     clear the SiI9024A's latched interrupt bits,
#   - vblank_count to read DRM core's counter rather than keep a second one.
#
# Usage: tests/check-sysfs-attributes.sh [source file]
#        tests/check-sysfs-attributes.sh --single [source file]  (no self-test)

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
	echo "sysfs attributes: $1" >&2
	exit 1
}

[ -f "$source_file" ] || fail "missing source file $source_file"

attributes="mem_info_vram_total vram_total_bytes vram_used_bytes active_mode \
active_mode_refresh_hz active_mode_pixel_clock_khz hpd rxsense link_state \
active_crtc vblank_count crc_supported"

begin_marker='BEGIN sysfs monitoring attributes'
end_marker='END sysfs monitoring attributes'

# Print the body of the top-level function whose definition line starts with
# "static ssize_t <name>_show(struct device *dev".
show_body() {
	local file=$1 name=$2

	awk -v head="static ssize_t ${name}_show(struct device *dev" '
		index($0, head) == 1 { in_fn = 1 }
		in_fn { print }
		in_fn && /^}/ { exit }' "$file"
}

# Print the block between the two marker comments.
marked_region() {
	awk -v begin="$begin_marker" -v end="$end_marker" '
		index($0, begin) { in_block = 1; next }
		index($0, end) { in_block = 0; next }
		in_block { print }' "$1"
}

check_names() {
	local file=$1 name

	for name in $attributes; do
		grep -F "DEVICE_ATTR_RO(${name});" "$file" >/dev/null ||
			fail "$file does not declare DEVICE_ATTR_RO(${name}); sm750-smi cannot find it"
		grep -F "&dev_attr_${name}.attr," "$file" >/dev/null ||
			fail "$file does not publish dev_attr_${name} in the attribute array"
	done
}

check_group() {
	local file=$1 region add_line register_line count

	region=$(marked_region "$file")
	[ -n "$region" ] ||
		fail "$file has no sysfs monitoring attribute block (markers missing)"

	grep -F 'static const struct attribute_group sm750_attr_group = {' \
		"$file" >/dev/null ||
		fail "$file does not define sm750_attr_group"

	# Twelve monitoring attributes plus the write-only pm_probe diagnostic
	# (defect A66), which is deliberately not one of the names above: it is
	# not read by sm750-smi and must never be read-only.
	count=$(grep -F '&dev_attr_' <<<"$region" | wc -l)
	[ "$count" -eq 13 ] ||
		fail "sm750_attr_group lists $count attributes, expected 12 monitoring attributes plus pm_probe"
	extra=$(grep -oE '&dev_attr_[a-z0-9_]+\.attr,' <<<"$region" |
		sed 's/^&dev_attr_//; s/\.attr,$//' |
		while IFS= read -r name; do
			case " $attributes " in
			*" $name "*) ;;
			*) printf '%s\n' "$name" ;;
			esac
		done)
	[ "$extra" = pm_probe ] ||
		fail "sm750_attr_group carries unexpected non-monitoring attributes: $extra"

	count=$(grep -c 'device_add_group(' "$file" || true)
	[ "$count" -eq 1 ] ||
		fail "$file calls device_add_group() $count times; expected exactly one"

	add_line=$({ grep -n -F \
		'devm_device_add_group(&pdev->dev, &sm750_attr_group);' "$file" ||
		true; } | head -n 1 | cut -d: -f1)
	[ -n "$add_line" ] ||
		fail "sm750_attr_group is not registered on &pdev->dev; /sys/class/drm/cardN/device would carry no attributes"

	register_line=$({ grep -n -F 'ret = drm_dev_register(&sdev->drm, 0);' \
		"$file" || true; } | head -n 1 | cut -d: -f1)
	[ -n "$register_line" ] || fail "$file no longer registers the DRM device"

	[ "$add_line" -lt "$register_line" ] ||
		fail "sm750_attr_group is registered at line $add_line, after drm_dev_register at line $register_line; a udev reader could miss the attributes"
}

check_show_functions() {
	local file=$1 name body locks unlocks

	for name in $attributes; do
		body=$(show_body "$file" "$name")
		[ -n "$body" ] || fail "no ${name}_show() in $file"

		grep -F 'dev_get_drvdata(dev)' <<<"$body" >/dev/null ||
			fail "${name}_show() does not take its device state from dev_get_drvdata(dev)"
		grep -F 'if (!sdev)' <<<"$body" >/dev/null ||
			fail "${name}_show() has no NULL guard on the driver data"
		grep -F 'sysfs_emit(' <<<"$body" >/dev/null ||
			fail "${name}_show() does not emit through sysfs_emit()"

		if grep -Eq '(msleep|ssleep|usleep_range|usleep|mdelay|udelay)\(' \
			<<<"$body"; then
			fail "${name}_show() sleeps; a sysfs read must not block on a delay"
		fi

		locks=$(grep -c 'mutex_lock(' <<<"$body" || true)
		unlocks=$(grep -c 'mutex_unlock(' <<<"$body" || true)
		[ "$locks" -eq "$unlocks" ] ||
			fail "${name}_show() takes $locks mode locks but releases $unlocks"

		if grep 'mutex_lock(' <<<"$body" |
			grep -v -F 'mutex_lock(&sdev->mode_lock);' >/dev/null; then
			fail "${name}_show() takes a lock other than the driver mode lock"
		fi

		if grep -Eq '(spin_lock|spin_lock_irq|read_lock|down_read|rtnl_lock)' \
			<<<"$body"; then
			fail "${name}_show() takes a spin or rtnl lock"
		fi
	done
}

check_link_status() {
	local file=$1 region body

	region=$(marked_region "$file")

	grep -F 'sm750_sii902x_get_link_status(hpd, rxsense, &event, false)' \
		<<<"$region" >/dev/null ||
		fail "the sysfs link-status read does not pass clear_events = false; a monitoring read would clear latched interrupt bits"
	if grep -F 'sm750_sii902x_get_link_status(hpd, rxsense, &event, true)' \
		<<<"$region" >/dev/null; then
		fail "the sysfs link-status read passes clear_events = true"
	fi

	body=$(show_body "$file" link_state)
	grep -F '"connected\n"' <<<"$body" >/dev/null ||
		fail "link_state_show() has no connected state"
	grep -F '"receiver-only\n"' <<<"$body" >/dev/null ||
		fail "link_state_show() has no receiver-only state"
	grep -F '"hpd-only\n"' <<<"$body" >/dev/null ||
		fail "link_state_show() has no hpd-only state"
	grep -F '"disconnected\n"' <<<"$body" >/dev/null ||
		fail "link_state_show() has no disconnected state"
}

check_counters() {
	local file=$1 body

	body=$(show_body "$file" vblank_count)
	grep -F 'drm_crtc_vblank_count(&sdev->pipe.crtc)' <<<"$body" >/dev/null ||
		fail "vblank_count_show() does not read DRM core's vblank counter"
	if grep -Eq 'vblank_count\s*(\+\+|\+=)' <<<"$file"; then
		fail "$file keeps a second vblank counter"
	fi

	body=$(show_body "$file" active_crtc)
	grep -F 'int index = -1;' <<<"$body" >/dev/null ||
		fail "active_crtc_show() does not default to -1 when no pipe is enabled"

	body=$(show_body "$file" crc_supported)
	grep -F 'SM750_CRC_SUPPORTED' <<<"$body" >/dev/null ||
		fail "crc_supported_show() does not report the build-time CRC support"
	grep -B6 -F '#define SM750_CRC_SUPPORTED 1' "$file" |
		grep -F 'KERNEL_VERSION(7, 0, 0)' >/dev/null ||
		fail "SM750_CRC_SUPPORTED is 1 without the kernel range that registers .get_crc_sources"
	grep -F '#define SM750_CRC_SUPPORTED 0' "$file" >/dev/null ||
		fail "SM750_CRC_SUPPORTED has no 0 fallback for kernels without the CRC callbacks"
}

check_names "$source_file"
check_group "$source_file"
check_show_functions "$source_file"
check_link_status "$source_file"
check_counters "$source_file"
echo "Sysfs attribute checks passed: $source_file"

if [ "$mode" = single ]; then
	exit 0
fi

scratch=$(mktemp -d "${TMPDIR}/sm750-sysfs-attr.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

# (a) An attribute renamed: the tool falls back to n/a for it.
plant_renamed_attribute() {
	sed -i \
		-e 's/^static DEVICE_ATTR_RO(active_mode);$/static DEVICE_ATTR_RO(active_mode_old);/' \
		-e 's/^\t&dev_attr_active_mode\.attr,$/\t\&dev_attr_active_mode_old.attr,/' \
		"$1"
}
# (b) A monitoring read that clears the latched link-event bits.
plant_clear_events() {
	sed -i 's/sm750_sii902x_get_link_status(hpd, rxsense, \&event, false)/sm750_sii902x_get_link_status(hpd, rxsense, \&event, true)/' "$1"
}
# (c) A show function that sleeps.
plant_msleep_in_show() {
	awk '
		index($0, "static ssize_t vram_total_bytes_show(") == 1 { in_fn = 1 }
		in_fn && index($0, "return sysfs_emit(") && !done {
			print "\tmsleep(1);"
			done = 1
		}
		{ print }
		in_fn && /^}/ { in_fn = 0 }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (d) The group on the DRM class device: invisible under cardN/device/.
plant_group_on_drm_device() {
	sed -i 's/devm_device_add_group(&pdev->dev, &sm750_attr_group)/devm_device_add_group(\&sdev->drm.dev, \&sm750_attr_group)/' "$1"
}
# (e) A show function that takes a spin lock.
plant_spin_lock_in_show() {
	awk '
		index($0, "static ssize_t vram_total_bytes_show(") == 1 { in_fn = 1 }
		in_fn && index($0, "return sysfs_emit(") && !done {
			print "\tspin_lock(&sdev->vblank_lock);"
			done = 1
		}
		{ print }
		in_fn && /^}/ { in_fn = 0 }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
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

control renamed_attribute plant_renamed_attribute
control clear_events_true plant_clear_events
control msleep_in_show plant_msleep_in_show
control group_on_drm_device plant_group_on_drm_device
control spin_lock_in_show plant_spin_lock_in_show

echo "Sysfs attribute checks passed (12 attributes, 5 planted controls)"
