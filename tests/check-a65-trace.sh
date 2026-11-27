#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# A65 gate: default-off teardown marks in src/sm750_drm.c.  Defect A65 is a
# hot `modprobe -r sm750hdmidrm` that wedges in `Unloading` while fbcon is
# bound, with no stack captured.  The marks name the step that was executing,
# so the next reproduction can be read against the remove order.
#
# The properties pinned here are the ones that keep the measurement honest
# and inert:
#   - a65_trace is a bool parameter, mode 0644, zero by default,
#   - a65_mark() prints through pr_err, only when a65_trace is set,
#   - it takes no lock and does not sleep; it runs from teardown,
#   - every mark appears exactly once, and the marks still bracket the calls
#     they measure in the original order,
#   - the remove body did not grow past 80 columns.
#
# Nothing here loads, unloads or writes sysfs: it reads the source text.
# Planted controls (--self-test, the default) re-enter through --single with
# one mutation each and require rejection.
#
# Usage: tests/check-a65-trace.sh [source file]
#        tests/check-a65-trace.sh --self-test [source file]
#        tests/check-a65-trace.sh --single [source file]  (no controls)
set -u
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

lineno() { # lineno TEXT PATTERN - first literal line number, empty absent
	printf '%s\n' "$1" | grep -nF -e "$2" | head -n 1 | cut -d: -f1
}

count_of() { # count_of TEXT PATTERN - literal occurrence count
	printf '%s\n' "$1" | grep -cF -e "$2"
}

if [ ! -f "$source_file" ]; then
	printf 'FAIL: a: %s does not exist\n' "$source_file" >&2
	printf 'A65 teardown marks checks passed (0 assertions, 0 planted controls)\n'
	exit 1
fi

src=$(cat "$source_file")

remove_body=$(awk '
	index($0, "static void sm750_pci_remove(struct pci_dev *pdev)") == 1 {
		in_fn = 1
	}
	in_fn { print }
	in_fn && /^}/ { exit }' "$source_file")
destroy_body=$(awk '
	index($0, "static void sm750_destroy_shadow_workqueue(void *data)") == 1 {
		in_fn = 1
	}
	in_fn { print }
	in_fn && /^}/ { exit }' "$source_file")
mark_body=$(awk '
	index($0, "static void a65_mark(const char *what)") == 1 { in_fn = 1 }
	in_fn { print }
	in_fn && /^}/ { exit }' "$source_file")

[ -n "$remove_body" ] || bad "a: sm750_pci_remove() is missing"
[ -n "$destroy_body" ] || bad "a: sm750_destroy_shadow_workqueue() is missing"

# --- a. the parameter is bool, 0644 and zero by default --------------------
has "$src" 'static bool a65_trace;' \
	"a: a65_trace must be a static bool, zero-initialised and off"
has "$src" 'module_param(a65_trace, bool, 0644);' \
	"a: a65_trace must be declared with mode 0644"
if [ "$(count_of "$src" 'module_param(a65_trace')" -ne 1 ]; then
	bad "a: a65_trace must have exactly one module_param declaration"
fi
if printf '%s\n' "$src" | grep -F 'module_param(a65_trace' |
	grep -vF 'module_param(a65_trace, bool, 0644);' >/dev/null; then
	bad "a: a65_trace must be a bool with mode 0644"
fi
if printf '%s\n' "$src" | grep -F 'module_param(a65_trace' |
	grep -qF '0444'; then
	bad "a: a65_trace must stay writable at runtime, not 0444"
fi
ok "a. a65_trace is a static bool with mode 0644 and defaults to off"

# --- b. the helper prints through pr_err, only behind the guard ------------
if [ -z "$mark_body" ]; then
	bad "b: a65_mark() is missing"
else
	has "$mark_body" 'if (a65_trace)' \
		"b: a65_mark() is not guarded by if (a65_trace)"
	has "$mark_body" 'pr_err("A65: %s\n", what);' \
		"b: a65_mark() does not print through pr_err with the A65: prefix"
	for wrong in pr_debug pr_info pr_warn; do
		if printf '%s\n' "$mark_body" | grep -F "$wrong(" >/dev/null;
		then
			bad "b: a65_mark() must use pr_err, not $wrong"
		fi
	done
	if [ "$(count_of "$mark_body" 'pr_err(')" -ne 1 ]; then
		bad "b: a65_mark() must contain exactly one pr_err call"
	fi
fi
ok "b. a65_mark() prints A65: through pr_err behind the a65_trace guard"

# --- c. no lock and no sleep inside the helper -----------------------------
if [ -z "$mark_body" ]; then
	bad "c: a65_mark() is missing"
else
	for forbidden in mutex_lock spin_lock msleep usleep_range schedule \
		wait_for_completion; do
		if printf '%s\n' "$mark_body" | grep -F "$forbidden" >/dev/null;
		then
			bad "c: a65_mark() must not call $forbidden during teardown"
		fi
	done
	if printf '%s\n' "$mark_body" | grep -F 'pr_err' |
		grep -qF 'mutex_lock'; then
		bad "c: a65_mark() must not lock"
	fi
fi
ok "c. a65_mark() takes no lock and does not sleep"

# --- d. every mark appears exactly once -----------------------------------
if [ -z "$remove_body" ]; then
	bad "d: sm750_pci_remove() is missing"
else
	i=0
	for mark in "remove enter" "before poll_fini" "after poll_fini" \
		"before unplug" "after unplug" \
		"before test_pattern_cancel" "after test_pattern_cancel" \
		"before atomic_shutdown" "after atomic_shutdown" \
		"before vblank_stop" "after vblank_stop" \
		"after sii902x_shutdown" "remove exit"; do
		i=$((i + 1))
		if [ "$(count_of "$remove_body" "a65_mark(\"$mark\");")" -ne 1 ];
		then
			bad "d: mark '$mark' must appear exactly once in sm750_pci_remove()"
		fi
	done
	if [ "$(count_of "$remove_body" 'a65_mark(')" -ne "$i" ]; then
		bad "d: sm750_pci_remove() must make exactly $i a65_mark calls, not $(count_of "$remove_body" 'a65_mark(')"
	fi
fi
if [ -z "$destroy_body" ]; then
	bad "d: sm750_destroy_shadow_workqueue() is missing"
else
	for mark in "before async_quiesce" "after async_quiesce" \
		"after destroy_workqueue"; do
		if [ "$(count_of "$destroy_body" "a65_mark(\"$mark\");")" -ne 1 ];
		then
			bad "d: mark '$mark' must appear exactly once in sm750_destroy_shadow_workqueue()"
		fi
	done
	if [ "$(count_of "$destroy_body" 'a65_mark(')" -ne 3 ]; then
		bad "d: sm750_destroy_shadow_workqueue() must make exactly 3 a65_mark calls"
	fi
fi
ok "d. every expected mark appears exactly once in its function"

# --- e. the marks still bracket the calls they measure --------------------
bracket() { # bracket TEXT BEFORE CALL AFTER
	if [ -z "$1" ]; then
		bad "e: the function for '$2' is missing"
		return
	fi
	pre=$(lineno "$1" "a65_mark(\"$2\");")
	call=$(lineno "$1" "$3")
	post=$(lineno "$1" "a65_mark(\"$4\");")
	if [ -z "$pre" ] || [ -z "$call" ] || [ -z "$post" ]; then
		bad "e: '$2', '$3' and '$4' must all be present"
	elif [ "$pre" -ge "$call" ] || [ "$call" -ge "$post" ]; then
		bad "e: '$2' at $pre, '$3' at $call and '$4' at $post are not in order"
	fi
}
bracket "$remove_body" "before poll_fini" \
	'drm_kms_helper_poll_fini(&sdev->drm);' "after poll_fini"
bracket "$remove_body" "before unplug" \
	'drm_dev_unplug(&sdev->drm);' "after unplug"
bracket "$remove_body" "before test_pattern_cancel" \
	'sm750_test_pattern_cancel(sdev);' "after test_pattern_cancel"
bracket "$remove_body" "before atomic_shutdown" \
	'drm_atomic_helper_shutdown(&sdev->drm);' "after atomic_shutdown"
bracket "$remove_body" "before vblank_stop" \
	'sm750_vblank_timer_stop(sdev, true);' "after vblank_stop"
bracket "$destroy_body" "before async_quiesce" \
	'sm750_async_quiesce(sdev);' "after async_quiesce"

# The unplug pair must also keep its place before the atomic shutdown pair.
unplug_pre=$(lineno "$remove_body" 'a65_mark("before unplug");')
unplug_post=$(lineno "$remove_body" 'a65_mark("after unplug");')
atomic_pre=$(lineno "$remove_body" 'a65_mark("before atomic_shutdown");')
if [ -z "$unplug_pre" ] || [ -z "$unplug_post" ] || [ -z "$atomic_pre" ];
then
	bad "e: the unplug and atomic_shutdown marks are missing"
elif [ "$unplug_pre" -ge "$unplug_post" ] ||
	[ "$unplug_post" -ge "$atomic_pre" ]; then
	bad "e: before unplug < after unplug < before atomic_shutdown must hold"
fi

enter=$(lineno "$remove_body" 'a65_mark("remove enter");')
exitl=$(lineno "$remove_body" 'a65_mark("remove exit");')
if [ -z "$enter" ] || [ -z "$exitl" ]; then
	bad "e: remove enter and remove exit must both be present"
elif [ "$enter" -ge "$(lineno "$remove_body" 'a65_mark("before poll_fini");')" ] ||
	[ "$exitl" -le "$(lineno "$remove_body" 'a65_mark("after sii902x_shutdown");')" ];
then
	bad "e: remove enter must be the first mark and remove exit the last"
fi

unlock=$(lineno "$remove_body" 'mutex_unlock(&sdev->mode_lock);')
after_sii=$(lineno "$remove_body" 'a65_mark("after sii902x_shutdown");')
if [ -z "$unlock" ] || [ -z "$after_sii" ] || [ "$unlock" -ge "$after_sii" ];
then
	bad "e: after sii902x_shutdown must follow mutex_unlock(&sdev->mode_lock)"
fi
ok "e. the marks bracket their calls and keep the original remove order"

# --- f. the instrumented lines stay within 80 columns ---------------------
long=$(printf '%s\n%s\n%s\n' "$remove_body" "$destroy_body" "$mark_body" |
	awk 'length($0) > 79 { print; found = 1 } END { exit !found }')
if [ -n "$long" ]; then
	bad "f: an instrumented line exceeds 79 columns: $long"
fi
ok "f. the instrumented lines stay within 80 columns"

[ "$fail" -eq 0 ] || exit 1

if [ "$single" -eq 1 ]; then
	printf 'A65 teardown mark assertions passed (%s)\n' "$source_file"
	exit 0
fi

# --- planted controls -------------------------------------------------------
# Each mutation removes exactly one guarantee asserted above; the gate must
# reject every one of them, otherwise the gate is decorative.
scratch=$(mktemp -d "${TMPDIR}/sm750-a65-trace-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

plant_mode_0444() { # the parameter can no longer be enabled at runtime
	sed -i \
		's/module_param(a65_trace, bool, 0644);/module_param(a65_trace, bool, 0444);/' \
		"$1"
}
plant_pr_debug() { # the line disappears at the default loglevel
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\tpr_err("A65: %s\\n", what);\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, '\t\tpr_debug("A65: %s\\n", what);\n'))
MUT
}
plant_guard_removed() { # the marks print on every teardown
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\tif (a65_trace)\n\t\tpr_err("A65: %s\\n", what);\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, '\tpr_err("A65: %s\\n", what);\n'))
MUT
}
plant_unplug_swapped() { # the marks name the wrong side of drm_dev_unplug
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\ta65_mark("before unplug");\n'
       '\tdrm_dev_unplug(&sdev->drm);\n'
       '\ta65_mark("after unplug");\n')
new = ('\ta65_mark("after unplug");\n'
       '\tdrm_dev_unplug(&sdev->drm);\n'
       '\ta65_mark("before unplug");\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}

control() {
	name=$1
	planted=$scratch/sm750_drm.c
	err=$scratch/stderr

	controls=$((controls + 1))
	cp "$source_file" "$planted"
	shift
	"$@" "$planted"
	if sh "$0" --single "$planted" >/dev/null 2>"$err"; then
		bad "planted control $name was not rejected"
	elif [ ! -s "$err" ]; then
		bad "planted control $name was rejected without a message"
	else
		printf 'negative control %s: rejected: %s\n' \
			"$name" "$(head -n 1 "$err")"
	fi
}

control mode-0444 plant_mode_0444
control pr-debug plant_pr_debug
control guard-removed plant_guard_removed
control unplug-swapped plant_unplug_swapped

# The pristine copy must still pass, otherwise the controls prove nothing.
cp "$source_file" "$scratch/pristine.c"
if ! sh "$0" --single "$scratch/pristine.c" >/dev/null \
	2>"$scratch/pristine.err"; then
	bad "the unmutated copy was rejected: $(head -n 1 "$scratch/pristine.err")"
fi
printf 'negative control pristine: accepted\n'

[ "$fail" -eq 0 ] || exit 1
printf 'A65 teardown marks gate checks passed (%s assertions, %s planted controls)\n' \
	"$assertions" "$controls"