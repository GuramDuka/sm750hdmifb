#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# A65 gate: default-off teardown marks in src/sm750_drm.c, and the teardown
# contract they measure.  Defect A65 is a hot `modprobe -r sm750hdmidrm` that
# wedges in `Unloading` while fbcon is bound, with no stack captured.  The
# marks name the step that was executing, so the next reproduction can be read
# against the remove order.
#
# The properties pinned here are the ones that keep the measurement honest
# and inert:
#   - a65_trace is a bool parameter, mode 0644, zero by default,
#   - a65_mark() prints through pr_err, only when a65_trace is set,
#   - it takes no lock and does not sleep; it runs from teardown,
#   - every mark appears exactly once, and the marks still bracket the calls
#     they measure,
#   - the instrumented lines did not grow past 80 columns,
# and the ones that make the stall structurally impossible
# (docs/evidence/a65/01-teardown-analysis.txt, section 4):
#   - producers stop, the pipeline shuts down while the console framebuffer is
#     still alive, the shadow queue dies inside .remove and not from a devres
#     action after it returned,
#   - the vtconsole detaches explicitly, outside clientlist_mutex,
#   - nothing fbcon reaches takes mode_lock blocking (candidate C1).
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

lt() { # lt LEFT RIGHT MESSAGE - LEFT must be a present, smaller line number
	if [ -z "$1" ] || [ -z "$2" ]; then
		bad "$3 (a step is missing)"
	elif [ "$1" -ge "$2" ]; then
		bad "$3"
	fi
}

if [ ! -f "$source_file" ]; then
	printf 'FAIL: a: %s does not exist\n' "$source_file" >&2
	printf 'A65 teardown marks checks passed (0 assertions, 0 planted controls)\n'
	exit 1
fi

src=$(cat "$source_file")

body_of() { # body_of SIGNATURE - function text, empty when absent
	awk -v sig="$2" '
		index($0, sig) == 1 { in_fn = 1 }
		in_fn { print }
		in_fn && /^}/ { exit }' "$1"
}
remove_body=$(body_of "$source_file" \
	"static void sm750_pci_remove(struct pci_dev *pdev)")
destroy_body=$(body_of "$source_file" \
	"static void sm750_destroy_shadow_workqueue(void *data)")
mark_body=$(body_of "$source_file" "static void a65_mark(const char *what)")
worker_body=$(body_of "$source_file" \
	"static void sm750_async_shadow_work(struct work_struct *work)")
defer_body=$(body_of "$source_file" \
	"static void sm750_mode_defer_worker(struct work_struct *work)")
detach_body=$(body_of "$source_file" \
	"static void sm750_detach_vtconsole(struct sm750_drm_device *sdev)")
pipe_enable_body=$(body_of "$source_file" \
	"static void sm750_pipe_enable(struct drm_simple_display_pipe *pipe")
pipe_disable_body=$(body_of "$source_file" \
	"static void sm750_pipe_disable(struct drm_simple_display_pipe *pipe)")

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

# --- i. no mark runs with a spinlock held ---------------------------------
# pr_err() may sleep and each mark prints a whole line, so a mark placed
# inside a spin_lock() section can stall the very teardown it traces.  This
# is checked before the census below so a planted relocation is reported for
# its real reason instead of as a missing mark.
spin_held=$(printf '%s\n' "$src" | awk '
	/spin_lock_init/ { next }
	/spin_lock/ && !/spin_unlock/ { depth++; next }
	/spin_unlock/ { if (depth > 0) depth--; next }
	depth > 0 && /a65_mark\(/ { print NR ": " $0 }
')
if [ -n "$spin_held" ]; then
	bad "i: an A65 mark runs with a spinlock held: $spin_held"
fi
ok "i. no mark runs with a spinlock held"

# --- d. every mark appears exactly once -----------------------------------
if [ -z "$remove_body" ]; then
	bad "d: sm750_pci_remove() is missing"
else
	i=0
	for mark in "remove enter" "before poll_fini" "after poll_fini" \
		"before test_pattern_cancel" "after test_pattern_cancel" \
		"before vblank_stop" "after vblank_stop" \
		"before atomic_shutdown" "after atomic_shutdown" \
		"before unplug" "after unplug" "before sii902x_shutdown" \
		"mode_lock acquired" "after sii902x_shutdown" "remove exit"; do
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
# Candidate C2b: the shadow worker must prove it ran, before it takes a lock.
if [ -z "$worker_body" ]; then
	bad "d: sm750_async_shadow_work() is missing"
else
	if [ "$(count_of "$worker_body" 'a65_mark("shadow worker enter");')" -ne 1 ];
	then
		bad "d: mark 'shadow worker enter' must appear exactly once in sm750_async_shadow_work()"
	fi
	if [ "$(count_of "$worker_body" 'a65_mark(')" -ne 1 ]; then
		bad "d: sm750_async_shadow_work() must make exactly 1 a65_mark call"
	fi
	if [ -n "$(lineno "$worker_body" 'a65_mark("shadow worker enter");')" ] &&
		[ "$(lineno "$worker_body" 'a65_mark("shadow worker enter");')" -ge \
		"$(lineno "$worker_body" 'mutex_lock(&sdev->async_lock);')" ]; then
		bad "d: 'shadow worker enter' must print before the worker takes async_lock"
	fi
fi
if [ "$(count_of "$src" 'a65_mark("')" -ne 19 ]; then
	bad "d: the driver must make exactly 19 a65_mark calls, not $(count_of "$src" 'a65_mark("')"
fi
if ! printf '%s\n' "$src" | grep -F 'MODULE_PARM_DESC(a65_trace,' -A1 |
	grep -qF '19 marks'; then
	bad "d: MODULE_PARM_DESC(a65_trace) must state the mark count (19 marks)"
fi
ok "d. every expected mark appears exactly once, and the count is documented"

# --- e. the marks bracket their calls, in the contract order --------------
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
bracket "$remove_body" "before sii902x_shutdown" \
	'sm750_sii902x_shutdown();' "after sii902x_shutdown"
bracket "$destroy_body" "before async_quiesce" \
	'sm750_async_quiesce(sdev);' "after async_quiesce"

# The teardown contract (docs/evidence/a65/01-teardown-analysis.txt, section
# 4): stop the producers, shut the pipeline down while the console buffer is
# still mapped, destroy the shadow queue inside .remove, detach the vtconsole
# with no driver mutex held, unplug, and power the panel down last.  Before
# this gate existed the reverse held: drm_dev_unplug() ran second, so the
# fbdev buffer was freed at :5571 while the queue and the panel shutdown were
# still to come.
tp=$(lineno "$remove_body" 'a65_mark("before test_pattern_cancel");')
stop=$(lineno "$remove_body" 'a65_mark("after vblank_stop");')
atomic_pre=$(lineno "$remove_body" 'a65_mark("before atomic_shutdown");')
atomic_post=$(lineno "$remove_body" 'a65_mark("after atomic_shutdown");')
queue=$(lineno "$remove_body" 'sm750_destroy_shadow_workqueue(sdev);')
detach=$(lineno "$remove_body" 'sm750_detach_vtconsole(sdev);')
unplug_pre=$(lineno "$remove_body" 'a65_mark("before unplug");')
unplug_post=$(lineno "$remove_body" 'a65_mark("after unplug");')
before_sii=$(lineno "$remove_body" 'a65_mark("before sii902x_shutdown");')
acquired=$(lineno "$remove_body" 'a65_mark("mode_lock acquired");')
lock=$(lineno "$remove_body" 'mutex_lock(&sdev->mode_lock);')
unlock=$(lineno "$remove_body" 'mutex_unlock(&sdev->mode_lock);')
after_sii=$(lineno "$remove_body" 'a65_mark("after sii902x_shutdown");')

lt "$tp" "$stop" \
	"e: test_pattern_cancel must run before the vblank timer stops"
lt "$stop" "$atomic_pre" \
	"e: every producer must stop before drm_atomic_helper_shutdown"
lt "$atomic_post" "$queue" \
	"e: the shadow queue must be destroyed after drm_atomic_helper_shutdown"
lt "$queue" "$detach" \
	"e: the shadow queue must die before the vtconsole detaches"
lt "$detach" "$unplug_pre" \
	"e: the vtconsole must detach before drm_dev_unplug"
lt "$unplug_post" "$before_sii" \
	"e: drm_dev_unplug must precede the sii902x power-down"
lt "$lock" "$acquired" \
	"e: 'mode_lock acquired' must follow mutex_lock(&sdev->mode_lock)"
lt "$acquired" "$unlock" \
	"e: 'mode_lock acquired' must precede mutex_unlock(&sdev->mode_lock)"
lt "$unlock" "$after_sii" \
	"e: after sii902x_shutdown must follow mutex_unlock(&sdev->mode_lock)"

enter=$(lineno "$remove_body" 'a65_mark("remove enter");')
exitl=$(lineno "$remove_body" 'a65_mark("remove exit");')
if [ -z "$enter" ] || [ -z "$exitl" ]; then
	bad "e: remove enter and remove exit must both be present"
elif [ "$enter" -ge "$(lineno "$remove_body" 'a65_mark("before poll_fini");')" ] ||
	[ "$exitl" -le "$after_sii" ]; then
	bad "e: remove enter must be the first mark and remove exit the last"
fi
ok "e. the marks bracket their calls and follow the teardown contract"

# --- f. the instrumented lines stay within 80 columns ---------------------
long=$(printf '%s\n%s\n%s\n%s\n' "$remove_body" "$destroy_body" "$mark_body" \
	"$detach_body" |
	awk 'length($0) > 79 { print; found = 1 } END { exit !found }')
if [ -n "$long" ]; then
	bad "f: an instrumented line exceeds 79 columns: $long"
fi
ok "f. the instrumented lines stay within 80 columns"

# --- g. the contract, not just the mark order -----------------------------
# A devres action would destroy the queue after .remove returned, exactly
# when the fbdev buffer the worker reads is already freed (candidate C2b).
if printf '%s\n' "$src" | grep -F 'sm750_destroy_shadow_workqueue, sdev);' \
	>/dev/null; then
	bad "g: sm750_destroy_shadow_workqueue must not be a devres action: the queue has to die inside .remove"
fi
has "$remove_body" 'sm750_destroy_shadow_workqueue(sdev);' \
	"g: sm750_pci_remove() must destroy the shadow queue itself"
has "$remove_body" 'sm750_detach_vtconsole(sdev);' \
	"g: sm750_pci_remove() must detach the vtconsole explicitly"
has "$remove_body" 'disable_work_sync(&sdev->mode_defer_work);' \
	"g: sm750_pci_remove() must drain the deferred register write"
for lockname in mode_lock shadow_lock cursor_lock; do
	has "$remove_body" "WARN_ON(mutex_is_locked(&sdev->$lockname));" \
		"g: the unplug site must warn when $lockname is still held"
	lockline=$(lineno "$remove_body" "WARN_ON(mutex_is_locked(&sdev->$lockname));")
	if [ -n "$lockline" ] && [ -n "$unplug_post" ] &&
		[ "$lockline" -le "$unplug_post" ]; then
		bad "g: the $lockname warning must come after drm_dev_unplug(), when no new user can enter"
	fi
done
# The detach unlinks the client under clientlist_mutex and runs the console
# teardown outside it, so console_lock is never taken while it is held.
if [ -z "$detach_body" ]; then
	bad "g: sm750_detach_vtconsole() is missing"
else
	has "$detach_body" 'mutex_lock(&dev->clientlist_mutex);' \
		"g: the detach must take clientlist_mutex"
	has "$detach_body" 'list_del(&client->list);' \
		"g: the detach must unlink the fbdev client from dev->clientlist"
	has "$detach_body" 'client->funcs->unregister(client);' \
		"g: the detach must run the client unregister callback"
	lt "$(lineno "$detach_body" 'mutex_unlock(&dev->clientlist_mutex);')" \
		"$(lineno "$detach_body" 'client->funcs->unregister(client);')" \
		"g: the console teardown must run outside clientlist_mutex"
fi
ok "g. the remove body follows the teardown contract, not just the mark order"

# --- h. no fbcon-reachable commit tail waits on mode_lock (candidate C1) --
# fbcon drives pipe_enable()/pipe_disable() from commit_tail() under
# console_sem, so either one blocking on mode_lock can close the cycle
# console_sem -> mode_lock -> console_sem.  The test pattern worker and the
# shadow paths take mode_lock legitimately and are not part of this loop.
for fn in enable disable; do
	case $fn in
	enable) body=$pipe_enable_body ;;
	disable) body=$pipe_disable_body ;;
	esac
	if [ -z "$body" ]; then
		bad "h: sm750_pipe_$fn() is missing"
		continue
	fi
	if printf '%s\n' "$body" | grep -F 'mutex_lock(&sdev->mode_lock);' \
		>/dev/null; then
		bad "h: sm750_pipe_$fn() must not take mode_lock blocking: fbcon reaches it under console_sem (candidate C1)"
	fi
	has "$body" 'mutex_trylock(&sdev->mode_lock)' \
		"h: sm750_pipe_$fn() must take mode_lock with mutex_trylock()"
	has "$body" 'sm750_mode_defer(sdev, ' \
		"h: sm750_pipe_$fn() must defer the register write when mode_lock is busy"
done
if [ -z "$defer_body" ]; then
	bad "h: sm750_mode_defer_worker() is missing"
else
	has "$defer_body" 'mutex_lock(&sdev->mode_lock);' \
		"h: the deferred programmer must take mode_lock, from system_wq"
	has "$defer_body" 'sm750_program_mode(sdev, ' \
		"h: the deferred programmer must apply the mode"
	has "$defer_body" 'sm750_sii902x_disable_link();' \
		"h: the deferred programmer must apply the panel-off"
fi
ok "h. no fbcon-reachable path takes mode_lock blocking (candidate C1)"

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
plant_pipe_enable_blocking() { # the fbcon-reachable tail waits on mode_lock again
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\tif (!mutex_trylock(&sdev->mode_lock)) {\n'
assert s.count(old) == 1, s.count(old)
new = '\tmutex_lock(&sdev->mode_lock);\n\tif (0) {\n'
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_devres_destroy() { # the queue is destroyed after .remove returns again
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\tif (!sdev->shadow_workqueue)\n\t\t\treturn -ENOMEM;\n'
assert s.count(old) == 1, s.count(old)
new = (old +
       '\t\tret = devm_add_action_or_reset(&pdev->dev,\n'
       '\t\t\t\tsm750_destroy_shadow_workqueue, sdev);\n'
       '\t\tif (ret)\n'
       '\t\t\treturn ret;\n')
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_detach_dropped() { # the console only detaches from inside drm_dev_unplug
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\tsm750_detach_vtconsole(sdev);\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_queue_after_unplug() { # the queue outlives the freed console buffer
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\tsm750_destroy_shadow_workqueue(sdev);\n'
mark = '\ta65_mark("after atomic_shutdown");\n'
anchor = '\ta65_mark("after unplug");\n'
assert s.count(mark) == 1, s.count(mark)
assert s.count(anchor) == 1, s.count(anchor)
i = s.index(mark) + len(mark)
j = s.index(old, i)
s = s[:j] + s[j + len(old):]
k = s.index(anchor) + len(anchor)
s = s[:k] + old + s[k:]
open(p, 'w').write(s)
MUT
}
plant_mark_in_spinlock() { # a mark sleeps while the vblank spinlock is held
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\thrtimer_try_to_cancel(&sdev->vblank_timer);\n'
assert s.count(old) == 1, s.count(old)
new = '\ta65_mark("shadow worker enter");\n' + old
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
control pipe-enable-blocking plant_pipe_enable_blocking
control devres-destroy plant_devres_destroy
control detach-dropped plant_detach_dropped
control queue-after-unplug plant_queue_after_unplug
control mark-in-spinlock plant_mark_in_spinlock

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
