#!/bin/sh
# sm750-pmtest - run one host-wide suspend cycle against the SM750 driver
# through /sys/power/pm_test, and always write the test mode back to `none`.
#
# Runs as root through one NOPASSWD entry (the command line carries no colon):
#   coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-pmtest
# `status` changes nothing and needs no entry: it only reads sysfs and the
# kernel log, and says so when the log is not readable without root.
#
# Why pm_test and not a plain suspend: the host has no S3. ACPI reports S0 S4
# S5 only and /sys/power/mem_sleep is [s2idle], so `mem` and `freeze` are the
# same state and `freeze` is the correct spelling. A real `freeze` would suspend
# the whole machine with no wake source on this console-only host, so the
# driver callbacks are reached through /sys/power/pm_test instead:
#   - `devices` runs every driver's .suspend/.resume but skips
#     dpm_suspend_noirq, so no device leaves D0 and PCI config is not saved;
#   - `platform` additionally saves PCI config and enters D3hot, which is the
#     level that proves the device can leave D0 and come back.
# `core` and `processors` are refused on s2idle with
# "Unsupported test mode for suspend to idle" and -EAGAIN, so they are accepted
# here only because the kernel lists them; they will fail the cycle, not run it.
#
# Guard rails, all hard failures rather than warnings:
#   - refuses to run as anything but root before its first write;
#   - validates the level against the accepted list and exits 2 on anything
#     else;
#   - clears a stale level at the start and names the risk when it finds one;
#   - arms an EXIT trap that ALWAYS writes `none` back, reads it back and prints
#     the readback, so an interrupted run cannot leave the machine in a test
#     mode. A forgotten level is a global: every later real suspend stays a test
#     until reboot, and the fingerprint is the line
#     `suspend debug: Waiting for`.
#   - the verdict needs both completion lines, no failure line and unchanged
#     suspend_stats error counters; anything less is FAIL.
#
# What the driver must log on a healthy cycle, four lines from src/sm750_drm.c:
#   pm: suspend entry, pm: suspend complete, pm: resume entry, pm: resume complete
# every failure path logs `pm: suspend failed: <err>` or `pm: resume failed: <err>`.
#
# `fb0` does not exist on this host (CONFIG_FB_DEVICE is unset), so neither
# /dev/fb* nor /sys/class/graphics is ever used as a success criterion.
#
# Usage: sm750-pmtest run [level] | status | reset
#
# Exit codes:
#   0  the requested action completed; run's verdict is PASS
#   1  environment problem, a refused action, or run's verdict is FAIL
#   2  usage error
set -eu
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

PROG=sm750-pmtest
PMTEST=/sys/power/pm_test
STATE=/sys/power/state
SLEEP=/sys/power/mem_sleep
STATS=/sys/power/suspend_stats
REGS=/usr/local/sbin/sm750-regs
LEVELS='none core processors platform devices freezer'

usage() {
	cat >&2 <<'EOF'
usage: sm750-pmtest run [level] | status | reset

  run [level]  write level to /sys/power/pm_test (default: devices), suspend
               once with `freeze`, then always write `none` back. The level is
               validated first and an EXIT trap restores `none` even when the
               run is interrupted.
  status       print pm_test, the level list, state, mem_sleep, the last four
               pm: lines of this boot and the suspend_stats counters.
  reset        write `none` to /sys/power/pm_test and verify the readback.

levels: none core processors platform devices freezer

This host has no S3: ACPI reports S0 S4 S5 only and /sys/power/mem_sleep is
[s2idle], so `mem` and `freeze` are the same state and `freeze` is the correct
spelling. `core` and `processors` are refused on s2idle with
"Unsupported test mode for suspend to idle" and -EAGAIN. `devices` runs every
driver's .suspend/.resume but skips dpm_suspend_noirq, so no device leaves D0
and PCI config is not saved; `platform` additionally saves PCI config and
enters D3hot, which is the level that proves the device can leave D0.
EOF
	exit 2
}

# read_pm_test - the selected level, or `?` when the file cannot be read.
# /sys/power/pm_test prints the level list with the current one bracketed,
# `[none] core processors platform devices freezer`, so the brackets decide the
# value; the first field is the fallback for a plain single-value file. Every
# write in this helper is followed by this read, never by the value written.
read_pm_test() {
	raw=$(cat "$PMTEST" 2>/dev/null) || raw=
	cur=$(printf '%s\n' "$raw" | sed -n 's/^\[\([^]]*\)\].*$/\1/p')
	[ -n "$cur" ] || cur=$(printf '%s\n' "$raw" | awk 'NF { print $1; exit }')
	printf '%s\n' "${cur:-?}"
}

# require_root - the one privilege gate, called before the first write in every
# writing subcommand.
require_root() {
	[ "$(id -u)" -eq 0 ] || { echo "$PROG: must run as root" >&2; exit 1; }
}

# journal_lines - the number of kernel-log lines of this boot. The run collects
# only the lines added after this number, so a previous cycle cannot satisfy it.
journal_lines() {
	journalctl -k -b --no-pager 2>/dev/null | wc -l | tr -d ' '
}

# stats_errors - the suspend_stats counters that report a failure, read from the
# directory this kernel publishes (`fail`, `failed_*`, `last_failed_*`).
# `success` is deliberately absent: a working cycle increments it.
stats_errors() {
	for name in fail failed_freeze failed_prepare failed_suspend \
		failed_suspend_late failed_suspend_noirq failed_resume \
		failed_resume_early failed_resume_noirq last_failed_dev \
		last_failed_errno last_failed_step; do
		[ -e "$STATS/$name" ] || continue
		printf '%s=%s\n' "$name" "$(cat "$STATS/$name" 2>/dev/null || echo '?')"
	done
}

# panel_line - PANEL_CURRENT_LINE from the allowlisted register dump, or empty
# when the helper or the register line is absent.
panel_line() {
	"$REGS" 2>/dev/null | grep -F 'PANEL_CURRENT_LINE' |
		awk '{print $NF}' | head -n 1
}

reset_cmd() {
	require_root
	printf 'none\n' > "$PMTEST"
	got=$(read_pm_test)
	printf '%s: pm_test is %s\n' "$PROG" "$got"
	[ "$got" = none ] || {
		echo "$PROG: failed to reset pm_test (readback '$got')" >&2
		exit 1
	}
}

status_cmd() {
	printf 'pm_test:      %s\n' "$(read_pm_test)"
	printf 'levels:       %s\n' "$LEVELS"
	printf 'state:        %s\n' "$(cat "$STATE" 2>/dev/null || echo '?')"
	printf 'mem_sleep:    %s\n' "$(cat "$SLEEP" 2>/dev/null || echo '?')"
	printf 'pm lines (last 4, this boot):\n'
	if lines=$(journalctl -k -b --no-pager 2>/dev/null |
		grep -F 'sm750' | grep -F 'pm: ' | tail -n 4) && [ -n "$lines" ]; then
		printf '%s\n' "$lines" | sed 's/^/  /'
	else
		printf '  none readable; the kernel log needs root (kernel.dmesg_restrict=1)\n'
	fi
	printf 'suspend_stats:\n'
	if [ -d "$STATS" ]; then
		for entry in "$STATS"/*; do
			printf '  %s: %s\n' "$(basename "$entry")" \
				"$(cat "$entry" 2>/dev/null || echo '?')"
		done
	elif [ -r "$STATS" ]; then
		sed 's/^/  /' "$STATS"
	else
		printf '  %s is not readable\n' "$STATS"
	fi
}

run_cmd() {
	require_root
	level=$1

	[ -w "$PMTEST" ] || {
		echo "$PROG: $PMTEST is not writable" >&2
		exit 1
	}
	[ -w "$STATE" ] || {
		echo "$PROG: $STATE is not writable" >&2
		exit 1
	}
	[ -d "$STATS" ] || [ -r "$STATS" ] || {
		echo "$PROG: $STATS is not readable, so no verdict is possible" >&2
		exit 1
	}
	command -v journalctl >/dev/null 2>&1 || {
		echo "$PROG: journalctl is missing; it is the only readable kernel log (kernel.dmesg_restrict=1)" >&2
		exit 1
	}

	# A level already set is a global that would make every later real suspend
	# a test; clear it and say why it matters.
	prev=$(read_pm_test)
	if [ "$prev" != none ]; then
		echo "$PROG: WARNING: pm_test was already '$prev', not 'none'." >&2
		echo "$PROG: WARNING: a forgotten level turns every later real suspend into a test until reboot;" >&2
		echo "$PROG: WARNING: the fingerprint is the line 'suspend debug: Waiting for'." >&2
	fi
	printf 'none\n' > "$PMTEST"

	SCRATCH=$(mktemp -d "${TMPDIR}/sm750-pmtest.XXXXXX")
	CLEANED=0
	cleanup() {
		rc=$?
		[ "$CLEANED" -eq 0 ] || return 0
		CLEANED=1
		printf 'none\n' > "$PMTEST" 2>/dev/null || true
		after=$(read_pm_test)
		printf '%s: pm_test readback after cleanup: %s\n' "$PROG" "$after" >&2
		if [ -n "${SCRATCH:-}" ]; then
			rm -rf "$SCRATCH"
		fi
		return "$rc"
	}
	trap 'cleanup; exit $?' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	trap 'exit 129' HUP

	printf '%s: pm_test=%s, suspending once with freeze; the panel may blank briefly\n' \
		"$PROG" "$level"
	printf '%s\n' "$level" > "$PMTEST"
	got=$(read_pm_test)
	printf '%s: pm_test armed at %s (readback: %s)\n' "$PROG" "$level" "$got"
	[ "$got" = "$level" ] || {
		echo "$PROG: pm_test did not read back $level (got '$got')" >&2
		exit 1
	}

	journal_before=$(journal_lines)
	case $journal_before in
	''|*[!0-9]*) echo "$PROG: could not snapshot the kernel log" >&2; exit 1 ;;
	esac
	stats_before=$(stats_errors)

	freeze_rc=0
	echo freeze > "$STATE" 2>"$SCRATCH/freeze.err" || freeze_rc=$?
	if [ "$freeze_rc" -ne 0 ]; then
		printf '%s: writing freeze to %s returned %s: %s\n' "$PROG" "$STATE" \
			"$freeze_rc" "$(cat "$SCRATCH/freeze.err" 2>/dev/null || echo '')" >&2
	fi

	added=$SCRATCH/added.log
	journalctl -k -b --no-pager 2>/dev/null |
		sed -n "$((journal_before + 1)),\$p" > "$added"
	driver=$SCRATCH/driver.log
	grep -F 'sm750' "$added" | grep -F 'pm: ' > "$driver" || true

	suspend_complete=$(grep -cF 'pm: suspend complete' "$driver" || true)
	resume_complete=$(grep -cF 'pm: resume complete' "$driver" || true)
	failed=$(grep -cE 'pm: (suspend|resume) failed' "$driver" || true)
	stats_after=$(stats_errors)
	stats_same=1
	[ "$stats_before" = "$stats_after" ] || stats_same=0

	panel_before=
	panel_after=
	if [ -x "$REGS" ]; then
		panel_before=$(panel_line)
		sleep 0.2 2>/dev/null || sleep 1
		panel_after=$(panel_line)
	fi

	ok_all=1
	[ "$suspend_complete" -ge 1 ] || ok_all=0
	[ "$resume_complete" -ge 1 ] || ok_all=0
	[ "$failed" -eq 0 ] || ok_all=0
	[ "$stats_same" -eq 1 ] || ok_all=0
	if [ "$ok_all" -eq 1 ]; then
		verdict=PASS
	else
		verdict=FAIL
	fi

	printf 'journal lines added since the snapshot: %s\n' "$(wc -l < "$added" | tr -d ' ')"
	printf 'driver pm: lines in that window:\n'
	if [ -s "$driver" ]; then
		sed 's/^/  /' "$driver"
	else
		printf '  none\n'
	fi
	printf 'pm: suspend complete count: %s\n' "$suspend_complete"
	printf 'pm: resume complete count: %s\n' "$resume_complete"
	printf 'pm: failure lines: %s\n' "$failed"
	if [ -x "$REGS" ]; then
		if [ "$panel_before" != "$panel_after" ]; then
			printf 'PANEL_CURRENT_LINE: %s -> %s (advances)\n' "$panel_before" "$panel_after"
		else
			printf 'PANEL_CURRENT_LINE: %s -> %s (did not change)\n' "$panel_before" "$panel_after"
		fi
	else
		printf 'PANEL_CURRENT_LINE: not sampled, %s is not installed\n' "$REGS"
	fi
	printf 'suspend_stats error counters before: %s\n' "$(printf '%s' "$stats_before" | tr '\n' ' ')"
	printf 'suspend_stats error counters after:  %s\n' "$(printf '%s' "$stats_after" | tr '\n' ' ')"

	if [ "$verdict" = PASS ]; then
		printf 'verdict: PASS\n'
		exit 0
	fi

	reason=
	[ "$suspend_complete" -ge 1 ] || reason="no 'pm: suspend complete' line"
	[ "$resume_complete" -ge 1 ] || reason="${reason:+$reason; }no 'pm: resume complete' line"
	[ "$failed" -eq 0 ] || reason="${reason:+$reason; }$failed 'pm: ... failed' line(s)"
	[ "$stats_same" -eq 1 ] || reason="${reason:+$reason; }suspend_stats error counters changed"
	printf 'verdict: FAIL: %s\n' "$reason"
	printf 'journal lines added since the snapshot:\n'
	sed 's/^/  /' "$added"
	printf 'suspend_stats error counters before:\n%s\n' "$stats_before"
	printf 'suspend_stats error counters after:\n%s\n' "$stats_after"
	exit 1
}

[ "$#" -ge 1 ] || usage
cmd=$1
shift
case $cmd in
run)
	[ "$#" -le 1 ] || usage
	level=${1:-devices}
	case $level in
	none|core|processors|platform|devices|freezer) ;;
	*) usage ;;
	esac
	run_cmd "$level"
	;;
status)
	[ "$#" -eq 0 ] || usage
	status_cmd
	exit 0
	;;
reset)
	[ "$#" -eq 0 ] || usage
	reset_cmd
	exit 0
	;;
*)
	usage
	;;
esac
