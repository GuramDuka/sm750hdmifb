#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# T63 gate: the pm_probe diagnostic attribute (source defect A66). System sleep
# cannot be entered on the reference host because two Tesla P100s return -EIO
# from their .suspend, so sm750_pm_suspend() and sm750_pm_resume() have never
# run there. pm_probe calls those two bodies directly from a root-only sysfs
# write, which makes the callbacks measurable without a system sleep.
#
# The properties pinned here are the ones that keep that safe and honest:
#   - the attribute is write-only (0200), so no unprivileged read exists,
#   - a DRM client holding master refuses the write: a live compositor cannot
#     be driven into the PM callbacks by accident, while the fbcon client
#     (which takes no master) still can,
#   - an unregistered or unplugged device refuses the write,
#   - a dedicated mutex serialises invocations; mode_lock must NOT be used
#     because the callbacks take mode_lock themselves,
#   - exactly the three commands are accepted and anything else is -EINVAL,
#   - every invocation logs the command and the callback result with the
#     `pm probe: ` prefix, and `cycle` skips resume when suspend failed,
#   - the write's return value carries the failure: success returns the byte
#     count, a rejected command returns -EINVAL and a failing callback is
#     returned as-is, so a script under `set -e` stops on it.
#
# Nothing here runs the callbacks, writes sysfs or needs root: it reads the
# source text. Planted controls (--self-test, the default) re-enter this script
# through --single with one mutation each and require rejection.
#
# Usage: tests/check-pm-probe.sh [source file]
#        tests/check-pm-probe.sh --self-test [source file]
#        tests/check-pm-probe.sh --single [source file]   (no planted controls)
set -uo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

single=0
if [ "${1:-}" = "--single" ]; then
	single=1
	shift
elif [ "${1:-}" = "--self-test" ]; then
	shift
fi
source_file=${1:-$project_dir/src/sm750_drm.c}

fail=0
assertions=0
controls=0
bad() {
	printf 'FAIL: %s\n' "$*" >&2
	fail=1
}
# ok MESSAGE - one printed section. The count in the pass line is derived from
# these calls, so it cannot drift away from the sections that ran.
ok() {
	assertions=$((assertions + 1))
	printf 'ok: %s\n' "$*"
}

has() { # has TEXT PATTERN MESSAGE
	case $1 in
	*"$2"*) ;;
	*) bad "$3" ;;
	esac
}

# lineno TEXT PATTERN - the line of the first literal occurrence, empty absent
lineno() {
	printf '%s\n' "$1" | grep -nF -e "$2" | head -n 1 | cut -d: -f1
}

# count_of TEXT PATTERN - literal occurrence count
count_of() {
	printf '%s\n' "$1" | grep -cF -e "$2"
}

if [ ! -f "$source_file" ]; then
	printf 'FAIL: a: %s does not exist\n' "$source_file" >&2
	printf 'PM probe gate checks passed (0 assertions, 0 planted controls)\n'
	exit 1
fi

# --- a. the attribute is declared write-only --------------------------------
body=$(awk '
	index($0, "static ssize_t pm_probe_store(") == 1 { in_fn = 1 }
	in_fn { print }
	in_fn && /^}/ { exit }' "$source_file")
[ -n "$body" ] || bad "a: pm_probe_store() is missing from $source_file"
has "$(cat "$source_file")" 'static DEVICE_ATTR_WO(pm_probe);' \
	"a: pm_probe must be declared with DEVICE_ATTR_WO, so the file is 0200 root-only"
for wrong in DEVICE_ATTR_RO DEVICE_ATTR_RW DEVICE_ATTR_WO_NAMED; do
	if grep -F "$wrong(pm_probe)" "$source_file" >/dev/null; then
		bad "a: pm_probe is also declared as $wrong"
	fi
done
ok "a. pm_probe exists and is declared DEVICE_ATTR_WO"

# --- b. it is published in the existing attribute group ---------------------
has "$(cat "$source_file")" '&dev_attr_pm_probe.attr,' \
	"b: pm_probe is not listed in sm750_attrs[], so it has no sysfs file"
has "$(cat "$source_file")" \
	'devm_device_add_group(&pdev->dev, &sm750_attr_group);' \
	"b: the attribute group is no longer registered on &pdev->dev"
ok "b. pm_probe is in sm750_attrs[] and the group is registered on the PCI device"

# --- c. the store function takes its device state safely -------------------
has "$body" 'dev_get_drvdata(dev)' \
	"c: pm_probe_store() does not take its device state from dev_get_drvdata(dev)"
has "$body" 'if (!sdev)' \
	"c: pm_probe_store() has no NULL guard on the driver data"
has "$body" 'return -ENODEV;' \
	"c: pm_probe_store() does not return -ENODEV without driver data"
ok "c. the store function reads dev_get_drvdata() and refuses without it"

# --- d. a DRM master refuses the write, before any callback ----------------
master_line=$(lineno "$body" 'READ_ONCE(sdev->drm.master)')
suspend_line=$(lineno "$body" 'sm750_pm_suspend(&pdev->dev)')
resume_line=$(lineno "$body" 'sm750_pm_resume(&pdev->dev)')
if [ -z "$master_line" ]; then
	bad "d: pm_probe_store() does not refuse while a DRM client holds master"
elif [ -z "$suspend_line" ] || [ -z "$resume_line" ]; then
	bad "d: pm_probe_store() does not call both PM callbacks"
elif [ "$master_line" -ge "$suspend_line" ] ||
	[ "$master_line" -ge "$resume_line" ]; then
	bad "d: the master guard at line $master_line must precede the callbacks at $suspend_line and $resume_line"
fi
has "$body" 'a DRM client holds master' \
	"d: the master refusal must name the reason"
ok "d. a DRM client holding master refuses the write before either callback"

# --- e. an unregistered or unplugged device refuses ------------------------
has "$body" '!sdev->drm.dev' \
	"e: pm_probe_store() does not refuse when the DRM device is unregistered"
has "$body" 'drm_dev_enter(&sdev->drm, &idx)' \
	"e: pm_probe_store() does not enter the DRM device before the callbacks"
has "$body" 'drm_dev_exit(idx);' \
	"e: pm_probe_store() does not leave the DRM device after the callbacks"
enter_line=$(lineno "$body" 'drm_dev_enter(&sdev->drm, &idx)')
exit_line=$(lineno "$body" 'drm_dev_exit(idx);')
if [ -z "$enter_line" ] || [ -z "$exit_line" ]; then
	bad "e: pm_probe_store() must both enter and leave the DRM device"
elif [ "$enter_line" -ge "$suspend_line" ] ||
	[ "$exit_line" -le "$suspend_line" ]; then
	bad "e: drm_dev_enter at $enter_line and drm_dev_exit at $exit_line must bracket the callbacks at $suspend_line"
fi
ok "e. an unregistered device is refused and the callbacks run inside drm_dev_enter"

# --- f. a dedicated mutex serialises, mode_lock is not used ----------------
has "$(cat "$source_file")" 'static DEFINE_MUTEX(sm750_pm_probe_lock);' \
	"f: the dedicated pm_probe mutex is missing"
has "$body" 'mutex_lock(&sm750_pm_probe_lock);' \
	"f: pm_probe_store() does not take the dedicated mutex"
has "$body" 'mutex_unlock(&sm750_pm_probe_lock);' \
	"f: pm_probe_store() does not release the dedicated mutex"
if [ "$(count_of "$body" 'mutex_lock(&sm750_pm_probe_lock);')" -ne 1 ] ||
	[ "$(count_of "$body" 'mutex_unlock(&sm750_pm_probe_lock);')" -ne 1 ]; then
	bad "f: the dedicated mutex must be taken and released exactly once"
fi
if [ "$(count_of "$(cat "$source_file")" 'sm750_pm_probe_lock')" -ne 3 ]; then
	bad "f: the dedicated mutex must be taken by pm_probe_store() and nothing else"
fi
if printf '%s\n' "$body" | grep -F 'mode_lock' >/dev/null; then
	bad "f: pm_probe_store() must not use mode_lock, the callbacks already take it"
fi
ok "f. a dedicated mutex serialises and mode_lock is not used"

# --- g. exactly three commands, anything else is -EINVAL -------------------
for cmd in suspend resume cycle; do
	has "$body" "sysfs_streq(buf, \"$cmd\")" \
		"g: the '$cmd' command is not accepted through sysfs_streq()"
done
if [ "$(count_of "$body" 'sysfs_streq(')" -ne 3 ]; then
	bad "g: pm_probe_store() must accept exactly suspend, resume and cycle"
fi
has "$body" 'ret = -EINVAL;' \
	"g: an unknown command does not return -EINVAL"
has "$body" 'accepted: suspend, resume, cycle' \
	"g: the rejection message must name the accepted commands"
ok "g. exactly suspend, resume and cycle are accepted, anything else is -EINVAL"

# --- h. the command and the result are logged with the pm probe: prefix ----
if [ "$(count_of "$body" 'pm probe: command ')" -ne 3 ]; then
	bad "h: every command must be logged once with the 'pm probe: ' prefix"
fi
has "$body" '"pm probe: suspend returned %d\n"' \
	"h: the suspend result is not logged"
has "$body" '"pm probe: resume returned %d\n"' \
	"h: the resume result is not logged"
has "$body" '"pm probe: cycle suspend failed: %d, resume skipped\n"' \
	"h: a failed cycle suspend is not logged as resume skipped"
has "$body" '"pm probe: cycle suspend ok, resume failed: %d\n"' \
	"h: a failed cycle resume is not logged"
has "$body" '"pm probe: cycle suspend ok, resume ok\n"' \
	"h: a successful cycle is not logged"
ok "h. every command and result is logged with the 'pm probe: ' prefix"

# --- i. cycle skips resume when suspend failed ------------------------------
cycle=$(printf '%s\n' "$body" | awk '
	index($0, "sysfs_streq(buf, \"cycle\")") { in_cycle = 1 }
	in_cycle { print }
	in_cycle && /^\t} else \{$/ { exit }')
cycle_suspend=$(lineno "$cycle" 'sm750_pm_suspend(&pdev->dev)')
cycle_guard=$(lineno "$cycle" 'if (ret) {')
cycle_skip=$(lineno "$cycle" 'resume skipped')
cycle_else=$(printf '%s\n' "$cycle" | grep -n $'^\t\t} else {$' |
	head -n 1 | cut -d: -f1)
cycle_resume=$(lineno "$cycle" 'sm750_pm_resume(&pdev->dev)')
if [ -z "$cycle_suspend" ] || [ -z "$cycle_guard" ] ||
	[ -z "$cycle_skip" ] || [ -z "$cycle_else" ] || [ -z "$cycle_resume" ]; then
	bad "i: the cycle path must suspend, log a failed suspend, and resume only on success"
elif [ "$cycle_suspend" -ge "$cycle_guard" ] ||
	[ "$cycle_guard" -ge "$cycle_skip" ] ||
	[ "$cycle_skip" -ge "$cycle_else" ] ||
	[ "$cycle_else" -ge "$cycle_resume" ]; then
	bad "i: the cycle path must resume inside the success branch, after the failure branch"
fi
ok "i. cycle resumes only after a successful suspend"

# --- j. a callback failure reaches the caller ------------------------------
tail_body=$(printf '%s\n' "$body" | awk '
	index($0, "drm_dev_exit(idx);") { seen = 1; next }
	seen { print }')
if [ -z "$tail_body" ]; then
	bad "j: pm_probe_store() has no code after drm_dev_exit()"
fi
has "$tail_body" 'return count;' \
	"j: a successful invocation must return the byte count"
has "$tail_body" 'return ret;' \
	"j: a non-zero callback return must be propagated to the caller"
if printf '%s\n' "$tail_body" | grep -Fq '? ret : count'; then
	bad "j: a callback failure must not be swallowed into a successful write"
fi
ok "j. success returns the byte count and a callback failure reaches the caller"

# --- k. the root-only helper that drives the attribute ----------------------
# The attribute is 0200, so an unprivileged shell cannot use it and the sudo
# allowlist names exact paths only. Without a helper the measurement route is
# unreachable on this host, which is how A66 stayed unmeasured. This section
# pins the delivery path - presence, mode, root refusal, the commands and the
# honesty statement - and its failure modes are file-level, so no planted
# control is derived from it.
helper=$project_dir/tools/sm750-pm-probe.sh
if [ ! -f "$helper" ]; then
	bad "k: tools/sm750-pm-probe.sh is missing, so the attribute cannot be used through sudo"
else
	[ -x "$helper" ] || bad "k: tools/sm750-pm-probe.sh is not executable"
	has "$(cat "$helper")" 'ATTR=$SYS/bus/pci/devices/0000:01:00.0/pm_probe' \
		"k: the helper must write the pm_probe attribute of the SM750 PCI device"
	has "$(cat "$helper")" '[ "$(id -u)" = 0 ] ||' \
		"k: the helper must refuse to run unprivileged"
	has "$(cat "$helper")" 'status)' \
		"k: the helper does not implement the status command"
	has "$(cat "$helper")" 'suspend | resume | cycle)' \
		"k: the helper does not implement suspend, resume and cycle"
	if printf '%s\n' "$(cat "$helper")" | grep -Fq 'systemctl suspend'; then
		bad "k: the helper must not trigger a real system sleep"
	fi
	has "$(cat "$helper")" 'this is not a system sleep' \
		"k: the helper must state that a pass is not a system sleep"
	# The verdict is a string match against the driver's own result lines, so a
	# drift in either file turns a healthy callback into a red verdict with no
	# compile error anywhere. That happened: cycle logs one combined line, and
	# the helper only knew the single-command form, so it reported FAIL on a
	# cycle that had in fact succeeded. Both sides are pinned here.
	has "$(cat "$helper")" 'pm probe: suspend returned 0' \
		"k: the helper does not match the driver's suspend result line"
	has "$(cat "$helper")" 'pm probe: resume returned 0' \
		"k: the helper does not match the driver's resume result line"
	has "$(cat "$helper")" 'pm probe: cycle suspend ok, resume ok' \
		"k: the helper does not match the driver's cycle result line"
	has "$(cat "$helper")" 'cycle suspend failed:' \
		"k: the helper does not recognise a failed cycle suspend"
	has "$(cat "$helper")" 'resume failed:' \
		"k: the helper does not recognise a failed cycle resume"
	if ! bash -n "$helper" 2>/dev/null; then
		bad "k: tools/sm750-pm-probe.sh does not parse"
	fi
fi
ok "k. the helper drives the attribute through the allowlist and says what a pass means"


[ "$fail" -eq 0 ] || exit 1

if [ "$single" -eq 1 ]; then
	printf 'PM probe assertions passed (%s)\n' "$source_file"
	exit 0
fi

# --- planted controls -------------------------------------------------------
# Each mutation removes exactly one guarantee asserted above; the gate must
# reject every one of them, otherwise the gate is decorative.
scratch=$(mktemp -d "${TMPDIR}/sm750-pm-probe-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

plant_master_guard_removed() { # a compositor can be driven into the PM path
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\tif (READ_ONCE(sdev->drm.master)) {\n'
       '\t\tdrm_info(&sdev->drm,\n'
       '\t\t\t "pm probe: refused: a DRM client holds master\\n");\n'
       '\t\treturn -EBUSY;\n'
       '\t}\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_attribute_read_write() { # an unprivileged read appears
	sed -i 's/^static DEVICE_ATTR_WO(pm_probe);$/static DEVICE_ATTR_RW(pm_probe);/' "$1"
}
plant_mode_lock_instead_of_mutex() { # a lock the callbacks already take
	sed -i \
		-e 's/mutex_lock(&sm750_pm_probe_lock);/mutex_lock(\&sdev->mode_lock);/' \
		-e 's/mutex_unlock(&sm750_pm_probe_lock);/mutex_unlock(\&sdev->mode_lock);/' \
		"$1"
}
plant_cycle_resumes_anyway() { # resume runs after a failed suspend
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\t\tif (ret) {\n'
       '\t\t\tdrm_info(&sdev->drm,\n'
       '\t\t\t\t "pm probe: cycle suspend failed: %d, resume skipped\\n",\n'
       '\t\t\t\t ret);\n'
       '\t\t} else {\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_result_not_logged() { # a callback result leaves no trace
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\tdrm_info(&sdev->drm, "pm probe: suspend returned %d\\n", ret);\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_result_swallowed() { # a callback failure still reads as a completed write
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\tif (ret)\n'
       '\t\treturn ret;\n'
       '\treturn count;\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, '\treturn ret == -EINVAL ? ret : count;\n'))
MUT
}

control() {
	local name=$1
	local planted=$scratch/sm750_drm.c
	local err=$scratch/stderr

	controls=$((controls + 1))
	cp "$source_file" "$planted"
	shift
	"$@" "$planted"
	if bash "$0" --single "$planted" >/dev/null 2>"$err"; then
		bad "planted control $name was not rejected"
	elif [ ! -s "$err" ]; then
		bad "planted control $name was rejected without a message"
	else
		printf 'negative control %s: rejected: %s\n' "$name" "$(head -n 1 "$err")"
	fi
}

control master-guard-removed plant_master_guard_removed
control attribute-read-write plant_attribute_read_write
control mode-lock-instead-of-mutex plant_mode_lock_instead_of_mutex
control cycle-resumes-anyway plant_cycle_resumes_anyway
control result-not-logged plant_result_not_logged
control result-swallowed plant_result_swallowed

# The pristine copy must still pass, otherwise the controls prove nothing.
cp "$source_file" "$scratch/pristine.c"
if ! bash "$0" --single "$scratch/pristine.c" >/dev/null 2>"$scratch/pristine.err"; then
	bad "the unmutated copy was rejected: $(head -n 1 "$scratch/pristine.err")"
fi
printf 'negative control pristine: accepted\n'

[ "$fail" -eq 0 ] || exit 1
printf 'PM probe gate checks passed (%s assertions, %s planted controls)\n' "$assertions" "$controls"
