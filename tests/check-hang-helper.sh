#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Gate for tools/sm750-hang.sh, the read-only capture installed as
# /usr/local/sbin/sm750-hang and allowlisted in docs/ROOT-ACTIONS.md 3.15.
#
# Defect A65: a hot `modprobe -r` with the fbcon vtconsole bound wedged the
# module in Unloading (refcount -1) and left `modprobe -r` in `D` state, and no
# stack could be captured, so the blocked function is still unknown. The helper
# exists for the next reproduction, and this gate pins what makes its capture
# usable: a root check before the first write, an OUTDIR that is never
# overwritten, the six files, the D-state filter that excludes an ordinary
# sleeping task, the `=== pid` header for every D-state pid, and a verdict that
# says whether any stack text was captured.
#
# The helper is simulated in a throwaway tree: pf, journalctl, dmesg and lsmod
# are stubs on PATH, /proc, /sys and /dev/dri are redirected with SM750_HANG_*
# environment variables (test-only seams; sudo strips the environment), and `id`
# reports uid 0. Nothing reads the real /proc, /sys or module state.
#
# Usage: tests/check-hang-helper.sh [script]
#        tests/check-hang-helper.sh --single [script]   (no planted controls)
#
# Each planted control deletes one property from a scratch copy and requires
# this gate to reject it; every control re-enters through --single.
#
# Exit 0 when every assertion holds, 1 otherwise.
set -uo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

single=0
if [ "${1:-}" = "--single" ]; then
	single=1
	shift
fi
helper=${1:-$project_dir/tools/sm750-hang.sh}

fail=0
assertions=0
bad() {
	printf 'FAIL: %s\n' "$*" >&2
	fail=1
}
ok() {
	assertions=$((assertions + 1))
	printf 'ok: %s\n' "$*"
}
expect_exit() { # expect_exit LABEL GOT WANT
	[ "$2" -eq "$3" ] || bad "$1: exit $2, expected $3"
}

scratch=$(mktemp -d "${TMPDIR}/sm750-hang-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

has() { # has FILE NEEDLE MESSAGE
	grep -qF -- "$2" "$1" || bad "$3: $1 lacks '$2'"
}
hasnt() { # hasnt FILE NEEDLE MESSAGE
	grep -qF -- "$2" "$1" && bad "$3: $1 unexpectedly has '$2'"
	return 0
}
contains() { # contains LABEL TEXT NEEDLE
	case $2 in
	*"$3"*) ;;
	*) bad "$1: output does not contain '$3'" ;;
	esac
}
func_body() { # func_body FILE NAME
	awk -v fn="$2() {" '$0 == fn { f = 1 } f { print } f && $0 == "}" { exit }' "$1"
}

# --- fixture ----------------------------------------------------------------
fx=$scratch/fx
bin=$scratch/bin
binroot=$scratch/bin-root
mkdir -p "$fx/proc/100" "$fx/proc/sys/kernel" \
	"$fx/sys/module/sm750hdmidrm" "$fx/sys/bus/pci/devices/0000:01:00.0" \
	"$fx/sys/bus/pci/drivers/sm750hdmidrm" \
	"$fx/sys/class/vtconsole/vtcon0" "$fx/dev/dri" "$bin" "$binroot"

printf 'sm750hdmidrm 200704 -1 - Unloading 0xffffffffc0a3d000 (OE-)\n' \
	>"$fx/proc/modules"
printf '0 sm750drmfb\n' >"$fx/proc/fb"
: >"$fx/proc/lockdep"
printf '120\n' >"$fx/proc/sys/kernel/hung_task_timeout_secs"
printf '524288\n' >"$fx/proc/sys/kernel/hung_task_check_count"
printf '[<0>] __schedule+0x2f4/0x8b0\n[<0>] schedule+0x5e/0xf0\n' \
	>"$fx/proc/100/stack"
printf '__schedule\n' >"$fx/proc/100/wchan"
printf '%s\n' '-1' >"$fx/sys/module/sm750hdmidrm/refcnt"
printf 'FF25FF3C9D1E0B77A0C4E2\n' >"$fx/sys/module/sm750hdmidrm/srcversion"
ln -s "$fx/sys/bus/pci/drivers/sm750hdmidrm" \
	"$fx/sys/bus/pci/devices/0000:01:00.0/driver"
printf '(M) frame buffer device\n' >"$fx/sys/class/vtconsole/vtcon0/name"
printf '0\n' >"$fx/sys/class/vtconsole/vtcon0/bind"
: >"$fx/dev/dri/card0"

cat >"$bin/ps" <<'EOF'
#!/bin/sh
cat "$SM750_HANG_TEST_PS"
EOF
cat >"$bin/journalctl" <<'EOF'
#!/bin/sh
printf 'stub-journal %s\n' "$*"
EOF
cat >"$bin/dmesg" <<'EOF'
#!/bin/sh
printf 'stub-dmesg %s\n' "$*"
EOF
cat >"$bin/lsmod" <<'EOF'
#!/bin/sh
printf 'Module                  Size  Used by\n'
printf 'sm750hdmidrm          200704  -1\n'
EOF
cat >"$binroot/id" <<'EOF'
#!/bin/sh
case "${1:-}" in
-u) printf '0\n' ;;
*) exec /usr/bin/id "$@" ;;
esac
EOF
chmod 0755 "$bin/ps" "$bin/journalctl" "$bin/dmesg" "$bin/lsmod" \
	"$binroot/id"

psd=$scratch/ps-d.txt
cat >"$psd" <<'EOF'
    PID    PPID STAT WCHAN                                    ELAPSED COMMAND         COMMAND
 100       1 D    __schedule                                    2245 modprobe        modprobe -r sm750hdmidrm
 200       1 S    do_wait                                       1000 zzznond         /bin/zzznond
EOF
psnod=$scratch/ps-nod.txt
cat >"$psnod" <<'EOF'
    PID    PPID STAT WCHAN                                    ELAPSED COMMAND         COMMAND
 200       1 S    do_wait                                       1000 zzznond         /bin/zzznond
EOF

# hang PS ARGS... - run the helper as uid 0 against the fixture.
hang() {
	_ps=$1
	shift
	PATH="$binroot:$bin:$PATH" SM750_HANG_PROC="$fx/proc" \
		SM750_HANG_SYS="$fx/sys" SM750_HANG_DEV_DRI="$fx/dev/dri" \
		SM750_HANG_TEST_PS="$_ps" sh "$helper" "$@"
}

# --- a. the script itself ---------------------------------------------------
[ -f "$helper" ] || bad "a: $helper is missing"
[ "$(head -n 1 "$helper")" = '#!/bin/sh' ] || bad "a: helper is not POSIX sh"
sh -n "$helper" || bad "a: sh -n rejected the helper"
grep -qF 'must run as root' "$helper" || bad "a: no root refusal text"
grep -qF '/mega/tmp/sm750/hang' "$helper" ||
	bad "a: no default capture root"
grep -qF 'lockdep_stats' "$helper" &&
	bad "a: helper reads the lockdep dump that the spec forbids"
grep -qF 'available_filter_functions' "$helper" &&
	bad "a: helper reads the tracing dump that the spec forbids"
ok "a script shape, POSIX syntax, root text, default root, no lockdep/tracing dump"

# --- b. root check before the first write -----------------------------------
# No uid-0 stub here: the real id must report the caller, and the OUTDIR must
# still be absent afterwards, i.e. the refusal happens before mkdir.
if [ "$(id -u)" -eq 0 ]; then
	printf 'SKIP: b root check (this gate is running as root)\n'
else
	_noroot=$scratch/no-root-dir
	out=$(PATH=/usr/bin:/bin sh "$helper" capture "$_noroot" 2>&1)
	st=$?
	expect_exit "b: capture as uid $(id -u)" "$st" 1
	contains "b: refusal" "$out" "sm750-hang: must run as root"
	[ -e "$_noroot" ] && bad "b: the refused capture created $_noroot"
	ok "b refused before the first write (uid $(id -u), exit 1, no directory)"
fi

# --- c. argv ----------------------------------------------------------------
out=$(hang "$psd" 2>&1)
expect_exit "c: no subcommand" $? 2
contains "c: usage" "$out" "usage: sm750-hang capture"
out=$(hang "$psd" bogus 2>&1)
expect_exit "c: unknown subcommand" $? 2
out=$(hang "$psd" capture "$scratch/one" "$scratch/two" 2>&1)
expect_exit "c: capture with two paths" $? 2
[ -e "$scratch/one" ] && bad "c: refused argv created $scratch/one"
ok "c missing, unknown and extra arguments refused with exit 2 and no write"

# --- d. an existing OUTDIR is never overwritten ------------------------------
mkdir -p "$scratch/existing"
: >"$scratch/existing/keep"
out=$(hang "$psd" capture "$scratch/existing" 2>&1)
expect_exit "d: existing OUTDIR" $? 1
contains "d: refusal" "$out" \
	"sm750-hang: refusing to overwrite existing $scratch/existing"
[ -f "$scratch/existing/keep" ] || bad "d: the marker file was removed"
[ -e "$scratch/existing/00-summary.txt" ] &&
	bad "d: a refused capture still wrote into the directory"
ok "d existing OUTDIR refused with exit 1 and left untouched"

# --- e. six files, the D filter, the header and the facts -------------------
cap=$scratch/cap
out=$(hang "$psd" capture "$cap" 2>&1)
st=$?
expect_exit "e: capture" "$st" 0
for _f in 00-summary.txt 01-tasks.txt 02-stacks.txt 03-driver.txt \
	04-kernel.txt 05-locks.txt; do
	[ -f "$cap/$_f" ] || bad "e: missing $cap/$_f"
done
contains "e: file list" "$out" "$cap/02-stacks.txt: "
contains "e: line counts" "$out" " lines"
contains "e: verdict" "$out" \
	"sm750-hang: stacks captured, read 02-stacks.txt first"
# 00: module line, lsmod and one line per D-state task.
has "$cap/00-summary.txt" "sm750hdmidrm 200704 -1 - Unloading" "e: module line"
has "$cap/00-summary.txt" "100 D modprobe" "e: D task line"
has "$cap/00-summary.txt" "kernel: " "e: kernel release"
# 01: the D-state filter keeps the blocked modprobe and drops the sleeping task.
has "$cap/01-tasks.txt" "100" "e: blocked pid"
has "$cap/01-tasks.txt" "modprobe" "e: blocked comm"
hasnt "$cap/01-tasks.txt" "zzznond" "e: D filter must drop an S-state task"
# 02: one header per D pid, then the stack and the wchan.
has "$cap/02-stacks.txt" "=== pid 100 modprobe" "e: stack header"
has "$cap/02-stacks.txt" "__schedule" "e: stack text"
has "$cap/02-stacks.txt" "wchan: " "e: wchan"
hasnt "$cap/02-stacks.txt" "=== pid 200" "e: no header for the S-state task"
# 03: the driver facts.
has "$cap/03-driver.txt" "refcnt: -1" "e: refcnt"
has "$cap/03-driver.txt" "srcversion: FF25FF3C9D1E0B77A0C4E2" "e: srcversion"
has "$cap/03-driver.txt" "driver: " "e: driver link"
has "$cap/03-driver.txt" "sm750hdmidrm" "e: driver target"
has "$cap/03-driver.txt" "vtconsole vtcon0 name: (M) frame buffer device" \
	"e: vtconsole name"
has "$cap/03-driver.txt" "vtconsole vtcon0 bind: 0" "e: vtconsole bind"
has "$cap/03-driver.txt" "fb: 0 sm750drmfb" "e: /proc/fb"
has "$cap/03-driver.txt" "dev-dri:" "e: /dev/dri header"
has "$cap/03-driver.txt" "card0" "e: /dev/dri entry"
# 04: both kernel logs, through the stubs.
has "$cap/04-kernel.txt" "stub-journal -k -b --no-pager" "e: journal"
has "$cap/04-kernel.txt" "stub-dmesg " "e: dmesg"
# 05: the two hung-task sysctls and /proc/lockdep presence.
has "$cap/05-locks.txt" "lockdep: present" "e: lockdep"
has "$cap/05-locks.txt" "hung_task_timeout_secs: 120" "e: hung timeout"
has "$cap/05-locks.txt" "hung_task_check_count: 524288" "e: hung check count"
ok "e six files, D-only filter, '=== pid' header, driver and kernel facts"

# --- f. the empty-stack branch says so --------------------------------------
cap2=$scratch/cap-nostack
out=$(hang "$psnod" capture "$cap2" 2>&1)
expect_exit "f: capture without a D task" $? 0
[ "$(wc -l <"$cap2/02-stacks.txt")" -eq 0 ] ||
	bad "f: 02-stacks.txt should be empty without a D-state task"
contains "f: verdict" "$out" \
	"sm750-hang: no stack captured - the task was not in an uninterruptible wait, or /proc/<pid>/stack is not readable"
ok "f empty 02-stacks.txt prints the no-stack verdict and still exits 0"

# --- g. status writes nothing and prints the same facts ---------------------
body=$(func_body "$helper" cmd_status)
[ -n "$body" ] || bad "g: cmd_status not found"
case $body in
*'>'*) bad "g: cmd_status contains a redirection and could write" ;;
*) ;;
esac
out=$(hang "$psd" status 2>&1)
st=$?
expect_exit "g: status" "$st" 0
contains "g: module fact" "$out" "sm750hdmidrm 200704 -1 - Unloading"
contains "g: D task fact" "$out" "100 D modprobe"
contains "g: driver fact" "$out" "refcnt: -1"
contains "g: status header" "$out" "D-state tasks:"
out=$(hang "$psd" status "$scratch/statusdir" 2>&1)
expect_exit "g: status takes no path" $? 2
ok "g status is write-free (no redirection) and prints module, tasks and driver"

if [ "$fail" -ne 0 ]; then
	printf 'hang helper checks failed\n' >&2
	exit 1
fi
if [ "$single" -eq 1 ]; then
	printf 'Hang helper checks passed (%s assertions, --single)\n' "$assertions"
	exit 0
fi

# --- planted controls -------------------------------------------------------
# Each control removes one PROPERTY from a scratch copy and keeps the sentence
# that explains it, then requires this gate to reject the copy.
controls=0
control() {
	_name=$1
	_mutator=$2
	_planted=$scratch/planted-$_name.sh
	cp "$helper" "$_planted"
	chmod 0755 "$_planted"
	if ! "$_mutator" "$_planted"; then
		printf 'FAIL: negative control %s: mutator did not apply\n' \
			"$_name" >&2
		fail=1
		return 1
	fi
	_err=$scratch/planted-$_name.err
	if bash "$0" --single "$_planted" >/dev/null 2>"$_err"; then
		printf 'FAIL: negative control %s was accepted\n' "$_name" >&2
		fail=1
		return 1
	fi
	[ -s "$_err" ] || {
		printf 'FAIL: negative control %s failed without a reason\n' \
			"$_name" >&2
		fail=1
		return 1
	}
	controls=$((controls + 1))
	printf 'negative control %s: rejected: %s\n' \
		"$_name" "$(head -n 1 "$_err")"
}

# (a) the per-pid stack loop is gone, so 02-stacks.txt stays empty.
mut_stack_loop_removed() {
	python3 - "$1" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
start_marker = '\tdstate_pids "$1" | while read -r _pid _comm; do\n'
start = text.index(start_marker)
end = text.index("\tdone\n", start) + len("\tdone\n")
open(path, "w").write(text[:start] + "\t:\n" + text[end:])
PY
}

# (b) the D-state filter is widened to every task in both readers.
mut_filter_widened() {
	python3 - "$1" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
assert text.count("$3 ~ /^D/") == 3, "D filter count"
open(path, "w").write(text.replace("$3 ~ /^D/", "$3 ~ /./"))
PY
}

# (c) the verdict always claims a stack was captured.
mut_verdict_always_success() {
	python3 - "$1" <<'PY'
import sys

path = sys.argv[1]
text = open(path).read()
old = 'if [ -s "$_out/02-stacks.txt" ]; then'
assert text.count(old) == 1, "verdict branch count"
open(path, "w").write(text.replace(old, "if true; then", 1))
PY
}

control stack-loop-removed mut_stack_loop_removed
control dstate-filter-widened mut_filter_widened
control verdict-always-success mut_verdict_always_success

if [ "$fail" -ne 0 ]; then
	printf 'hang helper checks failed\n' >&2
	exit 1
fi
printf 'Hang helper checks passed (%s assertions, %s planted controls)\n' \
	"$assertions" "$controls"
