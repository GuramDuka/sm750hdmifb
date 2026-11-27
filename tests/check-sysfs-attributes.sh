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
# GAP-B8 counters (docs/evidence/gap-b8/02-counter-design.txt section 8): the
# eleven b8_* attributes are held to the same show-function shape, and each one
# must have an increment site on the path it claims to count. A counter whose
# attribute exists but whose increment is absent, or sits off the retry path,
# is decoration: it reads zero forever and no soak can tell it from an idle
# build. That is what the b8 control below plants.
#
# Usage: tests/check-sysfs-attributes.sh [source file [sii902x source file]]
#        tests/check-sysfs-attributes.sh --single [source [sii902x]]  (no self-test)

set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

mode=full
if [ "${1:-}" = "--single" ]; then
	mode=single
	shift
fi
source_file=${1:-$project_dir/src/sm750_drm.c}
sii_source=${2:-$(dirname -- "$source_file")/sii902x.c}

fail() {
	echo "sysfs attributes: $1" >&2
	exit 1
}

[ -f "$source_file" ] || fail "missing source file $source_file"
[ -f "$sii_source" ] || fail "missing source file $sii_source"

attributes="mem_info_vram_total vram_total_bytes vram_used_bytes active_mode \
active_mode_refresh_hz active_mode_pixel_clock_khz hpd rxsense link_state \
active_crtc vblank_count crc_supported"

# GAP-B8 counters, one read-only attribute each, on the same marked group.
counter_attributes="b8_mode_attempts b8_mode_failures b8_mode_retries \
b8_stage_failures b8_i2c_write_timeouts b8_i2c_recoveries b8_ready_expired \
b8_ddc_grant_timeouts b8_edid_reads b8_edid_failures b8_counters_epoch_s"

all_attributes="$attributes $counter_attributes"

# Each counter and the token its increment (or, for the epoch, its store) must
# carry. The split is on ';' because the tokens contain spaces and '&'.
counter_wiring="b8_mode_attempts;atomic64_inc(&sdev->b8_mode_attempts)
b8_mode_failures;atomic64_inc(&sdev->b8_mode_failures)
b8_mode_retries;atomic64_inc(&sdev->b8_mode_retries)
b8_stage_failures;atomic64_inc(&sdev->b8_stage_failures[
b8_i2c_write_timeouts;sii902x_b8_count_inc(SM750_SII902X_B8_I2C_WRITE_TIMEOUTS)
b8_i2c_recoveries;sii902x_b8_count_inc(SM750_SII902X_B8_I2C_RECOVERIES)
b8_ready_expired;sii902x_b8_count_inc(SM750_SII902X_B8_READY_EXPIRED)
b8_ddc_grant_timeouts;sii902x_b8_count_inc(SM750_SII902X_B8_DDC_GRANT_TIMEOUTS)
b8_edid_reads;sii902x_b8_count_inc(SM750_SII902X_B8_EDID_READS)
b8_edid_failures;sii902x_b8_count_inc(SM750_SII902X_B8_EDID_FAILURES)
b8_counters_epoch_s;ktime_get_boottime_seconds()"

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

# Print the body of the top-level function whose definition line starts with
# the given prefix.
fn_body() {
	local file=$1 head=$2

	awk -v head="$head" '
		index($0, head) == 1 { in_fn = 1 }
		in_fn { print }
		in_fn && /^}/ { exit }' "$file"
}

# Print the fail branch of sm750_pipe_enable(), from the label to the closing
# brace of the function.
fail_block() {
	awk '
		/^static void sm750_pipe_enable\(/ { in_fn = 1 }
		in_fn && /^fail:/ { in_fail = 1 }
		in_fail { print }
		in_fail && /^}/ { exit }' "$1"
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

	for name in $all_attributes; do
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

	# Twelve monitoring attributes, the eleven GAP-B8 counters and the
	# write-only pm_probe diagnostic (defect A66), which is deliberately not
	# one of the names above: it is not read by sm750-smi and must never be
	# read-only.
	count=$(grep -F '&dev_attr_' <<<"$region" | wc -l)
	[ "$count" -eq 24 ] ||
		fail "sm750_attr_group lists $count attributes, expected 12 monitoring attributes plus 11 GAP-B8 counters plus pm_probe"
	extra=$(grep -oE '&dev_attr_[a-z0-9_]+\.attr,' <<<"$region" |
		sed 's/^&dev_attr_//; s/\.attr,$//' |
		while IFS= read -r name; do
			case " $all_attributes " in
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

	for name in $all_attributes; do
		body=$(show_body "$file" "$name")
		[ -n "$body" ] || fail "no ${name}_show() in $file"

		grep -F 'dev_get_drvdata(dev)' <<<"$body" >/dev/null ||
			fail "${name}_show() does not take its device state from dev_get_drvdata(dev)"
		grep -F 'if (!sdev)' <<<"$body" >/dev/null ||
			fail "${name}_show() has no NULL guard on the driver data"
		# sysfs_emit_at() is the same bounds-checked emitter, for the one
		# multi-line attribute (b8_stage_failures).
		grep -Eq 'sysfs_emit(_at)?\(' <<<"$body" >/dev/null ||
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

# The GAP-B8 counters must be on the path they claim to count, in both files:
# a b8_* attribute with no increment is a constant zero, and the one counter
# that witnesses a silently recovered timeout must count inside the attempt
# loop, after the write already failed.
check_counter_paths() {
	local file=$1 wiring name token body for_line guard_line inc_line close_line
	local enable failpart update probe prog_line attempts_line fail_line
	local stage_line retry_line call_line guard_line2 epoch_line

	for wiring in $counter_wiring; do
		name=${wiring%%;*}
		token=${wiring#*;}
		grep -F -- "$token" "$file" "$sii_source" >/dev/null ||
			fail "counter $name has no increment site ($token): the attribute would read zero on every build"
	done

	for name in $counter_attributes; do
		body=$(show_body "$file" "$name")
		if grep -Eq 'atomic64_inc|sii902x_b8_count_inc' <<<"$body"; then
			fail "${name}_show() increments a counter; a sysfs read must never change what it reports"
		fi
	done

	body=$(show_body "$file" b8_stage_failures)
	grep -F 'sm750_mode_stage_names[' <<<"$body" >/dev/null ||
		fail "b8_stage_failures_show() does not print the stage names in enum order"

	enable=$(fn_body "$file" 'static void sm750_pipe_enable(')
	[ -n "$enable" ] || fail "$file has no sm750_pipe_enable()"
	attempts_line=$(grep -nF 'atomic64_inc(&sdev->b8_mode_attempts);' <<<"$enable" |
		head -n 1 | cut -d: -f1)
	prog_line=$(grep -nF 'sm750_program_mode(sdev, &crtc_state->adjusted_mode,' \
		<<<"$enable" | head -n 1 | cut -d: -f1)
	[ -n "$attempts_line" ] && [ -n "$prog_line" ] &&
		[ "$attempts_line" -lt "$prog_line" ] ||
		fail "b8_mode_attempts is not incremented at the top of sm750_pipe_enable(), before the mode is programmed"

	failpart=$(fail_block "$file")
	[ -n "$failpart" ] || fail "$file has no fail branch in sm750_pipe_enable()"
	fail_line=$(grep -nF 'atomic64_inc(&sdev->b8_mode_failures);' <<<"$failpart" |
		head -n 1 | cut -d: -f1)
	stage_line=$(grep -nF 'atomic64_inc(&sdev->b8_stage_failures[' <<<"$failpart" |
		head -n 1 | cut -d: -f1)
	[ -n "$fail_line" ] && [ -n "$stage_line" ] ||
		fail "the enable fail branch does not count b8_mode_failures and b8_stage_failures"
	grep -F 'ARRAY_SIZE(sdev->b8_stage_failures)' <<<"$failpart" >/dev/null ||
		fail "the b8_stage_failures index is not bounded by the array size"

	update=$(fn_body "$file" 'static void sm750_pipe_update(')
	[ -n "$update" ] || fail "$file has no sm750_pipe_update()"
	guard_line2=$(grep -nF 'if (sdev->enable_failed && !pipe->crtc.state->mode_changed)' \
		<<<"$update" | head -n 1 | cut -d: -f1)
	retry_line=$(grep -nF 'atomic64_inc(&sdev->b8_mode_retries);' <<<"$update" |
		head -n 1 | cut -d: -f1)
	call_line=$(grep -nF 'sm750_pipe_enable(pipe, pipe->crtc.state, state);' \
		<<<"$update" | head -n 1 | cut -d: -f1)
	[ -n "$guard_line2" ] && [ -n "$retry_line" ] && [ -n "$call_line" ] &&
		[ "$guard_line2" -lt "$retry_line" ] && [ "$retry_line" -lt "$call_line" ] ||
		fail "b8_mode_retries is not incremented inside the enable-failed retry, before the recursive enable"

	probe=$(fn_body "$file" 'static int sm750_pci_probe(')
	[ -n "$probe" ] || fail "$file has no sm750_pci_probe()"
	epoch_line=$(grep -cF 'atomic64_set(&sdev->b8_counters_epoch_s, ktime_get_boottime_seconds());' \
		<<<"$probe" || true)
	[ "$epoch_line" -eq 1 ] ||
		fail "the counters epoch is not set exactly once in sm750_pci_probe(); a reload must be detectable"

	body=$(fn_body "$sii_source" 'static int sii902x_write_block_retrying(')
	[ -n "$body" ] ||
		fail "$sii_source has no sii902x_write_block_retrying(); GAP-B8 counts that retry path"
	for_line=$(grep -nF 'for (attempt = 0; attempt < SII902X_WRITE_ATTEMPTS; attempt++)' \
		<<<"$body" | head -n 1 | cut -d: -f1)
	guard_line=$(grep -nF 'if (ret != -ETIMEDOUT)' <<<"$body" |
		head -n 1 | cut -d: -f1)
	inc_line=$(grep -nF 'sii902x_b8_count_inc(SM750_SII902X_B8_I2C_WRITE_TIMEOUTS);' \
		<<<"$body" | head -n 1 | cut -d: -f1)
	close_line=$(awk '/^\t\}$/ { print NR; exit }' <<<"$body")
	[ -n "$for_line" ] && [ -n "$guard_line" ] && [ -n "$inc_line" ] &&
		[ -n "$close_line" ] ||
		fail "sii902x_write_block_retrying() no longer has the attempt loop the timeout counter counts"
	[ "$inc_line" -gt "$guard_line" ] ||
		fail "the b8_i2c_write_timeouts increment runs before the -ETIMEDOUT test, so a successful write counts as a timeout"
	[ "$inc_line" -lt "$close_line" ] ||
		fail "the b8_i2c_write_timeouts increment is outside the attempt loop: a retried transient would not be counted"
}

check_names "$source_file"
check_group "$source_file"
check_show_functions "$source_file"
check_link_status "$source_file"
check_counters "$source_file"
check_counter_paths "$source_file"
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

# (f) A counter read that bypasses sysfs_emit(), so the kernel's buffer size
# is no longer enforced for it.
plant_counter_bypass() {
	awk '
		index($0, "static ssize_t b8_mode_failures_show(") == 1 { in_fn = 1 }
		in_fn && /sysfs_emit\(/ {
			sub(/sysfs_emit\(buf, /, "scnprintf(buf, PAGE_SIZE, ")
		}
		{ print }
		in_fn && /^}/ { in_fn = 0 }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (g) A counter read that sleeps.
plant_counter_show_sleeps() {
	awk '
		index($0, "static ssize_t b8_ready_expired_show(") == 1 { in_fn = 1 }
		in_fn && index($0, "return sysfs_emit(") && !done {
			print "\tusleep_range(1000, 2000);"
			done = 1
		}
		{ print }
		in_fn && /^}/ { in_fn = 0 }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (h) A counter read that takes a spin lock.
plant_counter_spin_lock() {
	awk '
		index($0, "static ssize_t b8_i2c_recoveries_show(") == 1 { in_fn = 1 }
		in_fn && index($0, "return sysfs_emit(") && !done {
			print "\tspin_lock(&sdev->vblank_lock);"
			done = 1
		}
		{ print }
		in_fn && /^}/ { in_fn = 0 }' "$1" >"$1.tmp"
	mv "$1.tmp" "$1"
}
# (i) The timeout increment moved off the retry path: it now counts once per
# call instead of once per timed-out attempt, so a retried transient vanishes.
plant_moved_increment() {
	awk '
		index($0, "static int sii902x_write_block_retrying(") == 1 { in_fn = 1 }
		in_fn && index($0, "sii902x_b8_count_inc(SM750_SII902X_B8_I2C_WRITE_TIMEOUTS);") {
			saved = $0
			next
		}
		{ print }
		in_fn && /^\t\}$/ && saved != "" {
			print "\t" saved
			saved = ""
		}
		in_fn && /^}/ { in_fn = 0 }' "$2" >"$2.tmp"
	mv "$2.tmp" "$2"
}

# Every planted defect must be caught, for the stated reason, otherwise the
# gate is decorative.
control() {
	local name=$1
	local expect=$2
	local planted=$scratch/sm750_drm.c
	local planted_sii=$scratch/sii902x.c
	local err=$scratch/stderr

	cp "$source_file" "$planted"
	cp "$sii_source" "$planted_sii"
	shift 2
	"$@" "$planted" "$planted_sii"
	if "$0" --single "$planted" "$planted_sii" >/dev/null 2>"$err"; then
		fail "negative control $name was not rejected"
	fi
	grep -F -- "$expect" "$err" >/dev/null ||
		fail "negative control $name was rejected for the wrong reason: $(head -n 1 "$err")"
	echo "negative control $name: rejected (exit 1): $(head -n 1 "$err")"
}

control renamed_attribute "does not declare DEVICE_ATTR_RO(active_mode)" plant_renamed_attribute
control clear_events_true "does not pass clear_events = false" plant_clear_events
control msleep_in_show "vram_total_bytes_show() sleeps" plant_msleep_in_show
control group_on_drm_device "is not registered on &pdev->dev" plant_group_on_drm_device
control spin_lock_in_show "takes a spin or rtnl lock" plant_spin_lock_in_show
control counter_bypasses_sysfs_emit "b8_mode_failures_show() does not emit through sysfs_emit()" plant_counter_bypass
control counter_show_sleeps "b8_ready_expired_show() sleeps" plant_counter_show_sleeps
control counter_show_spin_lock "b8_i2c_recoveries_show() takes a spin or rtnl lock" plant_counter_spin_lock
control increment_off_retry_path "outside the attempt loop" plant_moved_increment

echo "Sysfs attribute checks passed (12 monitoring attributes, 11 GAP-B8 counters, 9 planted controls)"
