#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# sm750-hang - read-only forensic capture for a wedged sm750hdmidrm.
#
# Defect A65: on 2026-11-26 a hot `modprobe -r sm750hdmidrm` with the fbcon
# vtconsole bound wedged the module in `Unloading` (refcount -1) and left
# `modprobe -r` in `D` state for the rest of the boot. kernel.dmesg_restrict=1,
# the hung-task detector never fired and no allowlisted helper could read
# /proc/<pid>/stack, so the blocked function was never identified. This helper
# exists BEFORE the next reproduction, so that a stack is finally available.
#
# It reads only: /proc, /sys, /dev/dri, lsmod, ps, journalctl and dmesg. It
# never writes sysfs, never calls modprobe and never tries to unwedge anything.
# A module already wedged in Unloading cannot be recovered from userspace: only
# a reboot does that.
#
# Installed as /usr/local/sbin/sm750-hang (mode 0755 root:root), allowlisted in
# docs/ROOT-ACTIONS.md section 3.15:
#
#   coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-hang
#
# Exit codes: 0 capture written, 1 failed capture or wrong privileges, 2 usage.
#
# The SM750_HANG_* overrides redirect the fixed /proc, /sys and /dev/dri
# prefixes and exist for tests/check-hang-helper.sh only: sudo strips the
# environment unless setenv is granted, and no grant here carries setenv, so
# the installed helper always reads the real paths.
set -u

PROG=sm750-hang
PROC=${SM750_HANG_PROC:-/proc}
SYS=${SM750_HANG_SYS:-/sys}
DEV_DRI=${SM750_HANG_DEV_DRI:-/dev/dri}
DEFAULT_ROOT=/mega/tmp/sm750/hang

usage() {
	cat >&2 <<'EOF'
usage: sm750-hang capture [OUTDIR]
       sm750-hang status

  capture [OUTDIR]
           write a read-only forensic snapshot of the SM750 module state into
           OUTDIR (default /mega/tmp/sm750/hang/<UTC stamp>) and refuse to
           overwrite an existing directory. Six files: 00-summary.txt,
           01-tasks.txt, 02-stacks.txt, 03-driver.txt, 04-kernel.txt and
           05-locks.txt. 02-stacks.txt is the file that identifies what a
           wedged remove path is blocked on.
  status   print the same summary, task and driver facts to stdout without
           writing anything.

Both need root. Neither can recover a wedged module; only a reboot does that.
Exit codes: 0 capture written, 1 failed capture or wrong privileges, 2 usage.
EOF
	exit 2
}

need_root() {
	if [ "$(id -u)" -ne 0 ]; then
		printf '%s: must run as root\n' "$PROG" >&2
		exit 1
	fi
}

# show LABEL FILE - one labelled read. A missing or unreadable file records
# cat's error text instead of aborting the capture.
show() {
	printf '%s: ' "$1"
	cat "$2" 2>&1
}

# dstate_lines - one "pid stat comm" line per D-state task.
dstate_lines() {
	ps -eo pid,ppid,stat,wchan:40,etimes,comm,args 2>/dev/null |
		awk 'NR > 1 && $3 ~ /^D/ { printf "%s %s %s\n", $1, $3, $6 }'
}

# summary_facts - the 00-summary.txt body, also printed by status.
summary_facts() {
	printf 'date: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	printf 'kernel: %s\n' "$(uname -r)"
	printf 'modules: '
	awk '$1 == "sm750hdmidrm"' "$PROC/modules" 2>&1
	printf 'lsmod:\n'
	lsmod 2>/dev/null | grep -E 'sm750hdmidrm|drm' ||
		printf '(no matching lsmod line)\n'
	printf 'D-state tasks:\n'
	dstate_lines
}

# tasks_facts - the 01-tasks.txt body: D-state tasks plus every module-tool
# process, so a modprobe blocked in D is kept even if its state column is read
# differently by a future util-linux.
tasks_facts() {
	ps -eo pid,ppid,stat,wchan:40,etimes,comm,args 2>/dev/null |
		awk 'NR == 1 || $3 ~ /^D/ || $0 ~ /modprobe|insmod|rmmod|dkms/'
}

# dstate_pids TASKS - "pid comm" for each D-state row of a tasks file.
dstate_pids() {
	awk 'NR > 1 && $3 ~ /^D/ { print $1, $6 }' "$1"
}

# stack_report TASKS - the 02-stacks.txt body: header, /proc/<pid>/stack and
# /proc/<pid>/wchan per D-state pid. A kernel thread's stack may be unreadable;
# that error text is recorded, never fatal.
stack_report() {
	dstate_pids "$1" | while read -r _pid _comm; do
		printf '=== pid %s %s\n' "$_pid" "$_comm"
		printf 'stack:\n'
		cat "$PROC/$_pid/stack" 2>&1
		printf 'wchan: '
		cat "$PROC/$_pid/wchan" 2>&1
		printf '\n'
	done
}

# driver_facts - the 03-driver.txt body, also printed by status.
driver_facts() {
	show refcnt "$SYS/module/sm750hdmidrm/refcnt"
	show srcversion "$SYS/module/sm750hdmidrm/srcversion"
	printf 'driver: %s\n' \
		"$(readlink -f "$SYS/bus/pci/devices/0000:01:00.0/driver" 2>&1)"
	for _vc in "$SYS/class/vtconsole"/vtcon*; do
		[ -e "$_vc" ] || continue
		show "vtconsole ${_vc##*/} name" "$_vc/name"
		show "vtconsole ${_vc##*/} bind" "$_vc/bind"
	done
	show fb "$PROC/fb"
	printf 'dev-dri:\n'
	ls -l "$DEV_DRI/" 2>&1
}

kernel_facts() {
	printf '== journalctl -k -b (last 400 lines)\n'
	journalctl -k -b --no-pager 2>&1 | tail -n 400
	printf '== dmesg (last 200 lines)\n'
	dmesg 2>&1 | tail -n 200
}

# locks_facts - the 05-locks.txt body. The large lockdep and tracing dumps are
# deliberately NOT read: neither names the blocked function, and both are
# enormous. Only the existence of /proc/lockdep and the two hung-task sysctls
# are recorded.
locks_facts() {
	if [ -e "$PROC/lockdep" ]; then
		printf '%s: present\n' "$PROC/lockdep"
	else
		printf '%s: absent\n' "$PROC/lockdep"
	fi
	show hung_task_timeout_secs "$PROC/sys/kernel/hung_task_timeout_secs"
	show hung_task_check_count "$PROC/sys/kernel/hung_task_check_count"
}

failed() {
	printf '%s: failed to write %s\n' "$PROG" "$1" >&2
	exit 1
}

cmd_capture() {
	[ $# -le 1 ] || usage
	_out=${1:-}
	if [ -z "$_out" ]; then
		_out=$DEFAULT_ROOT/$(date -u '+%Y%m%dT%H%M%SZ')
	fi
	if [ -e "$_out" ]; then
		printf '%s: refusing to overwrite existing %s\n' "$PROG" "$_out" >&2
		exit 1
	fi
	mkdir -p "$_out" || {
		printf '%s: cannot create %s\n' "$PROG" "$_out" >&2
		exit 1
	}

	summary_facts >"$_out/00-summary.txt" || failed "$_out/00-summary.txt"
	tasks_facts >"$_out/01-tasks.txt" || failed "$_out/01-tasks.txt"
	stack_report "$_out/01-tasks.txt" >"$_out/02-stacks.txt" ||
		failed "$_out/02-stacks.txt"
	driver_facts >"$_out/03-driver.txt" || failed "$_out/03-driver.txt"
	kernel_facts >"$_out/04-kernel.txt" || failed "$_out/04-kernel.txt"
	locks_facts >"$_out/05-locks.txt" || failed "$_out/05-locks.txt"

	for _f in "$_out"/00-summary.txt "$_out"/01-tasks.txt \
		"$_out"/02-stacks.txt "$_out"/03-driver.txt \
		"$_out"/04-kernel.txt "$_out"/05-locks.txt; do
		printf '%s: %s lines\n' "$_f" "$(wc -l <"$_f")"
	done
	if [ -s "$_out/02-stacks.txt" ]; then
		printf '%s: stacks captured, read 02-stacks.txt first\n' "$PROG"
	else
		printf '%s: no stack captured - the task was not in an uninterruptible wait, or /proc/<pid>/stack is not readable\n' \
			"$PROG"
	fi
}

cmd_status() {
	summary_facts
	printf '\n'
	tasks_facts
	printf '\n'
	driver_facts
}

[ $# -ge 1 ] || usage
action=$1
shift
case $action in
capture | status) ;;
*) usage ;;
esac
need_root
case $action in
capture) cmd_capture "$@" ;;
status)
	[ $# -eq 0 ] || usage
	cmd_status
	;;
esac
