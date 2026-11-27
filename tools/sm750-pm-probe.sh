#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# sm750-pm-probe - drive the driver's suspend and resume callback bodies from a
# running system through the root-only pm_probe attribute.
#
# Defect A66: on 2026-11-27 an armed `pm_test=devices` cycle stopped at the two
# neighbouring Tesla P100s (0000:83:00.0 and 0000:84:00.0) before the SM750 was
# ever reached, so the driver's own sleep path has never been executed. This
# helper exercises it while that environmental blocker stands.
#
# It is NOT a system sleep and must never be reported as one: the callback
# bodies run, but there is no PCI config space save and restore, the device
# never enters D3hot and no power state changes. See docs/PARAMETERS.md.
#
# Installed as /usr/local/sbin/sm750-pm-probe (mode 0755 root:root),
# allowlisted in docs/ROOT-ACTIONS.md section 3.17:
#
#   coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-pm-probe
#
# Exit codes: 0 the probe ran and the callbacks reported success, 1 the probe
# was refused or a callback returned an error, 2 usage or wrong privileges.
#
# The SM750_PM_PROBE_* overrides redirect the fixed sysfs and /proc prefixes and
# the log reader and exist for tests/check-pm-probe.sh only: sudo strips the
# environment unless setenv is granted, and the grant above carries no setenv,
# so the installed helper always uses the real paths.
set -u

PROG=sm750-pm-probe
SYS=${SM750_PM_PROBE_SYS:-/sys}
PROC=${SM750_PM_PROBE_PROC:-/proc}
ATTR=$SYS/bus/pci/devices/0000:01:00.0/pm_probe
MODULE_DIR=$SYS/module/sm750hdmidrm
LOG_READER=${SM750_PM_PROBE_LOG:-journalctl}
REGISTERS=${SM750_PM_PROBE_REGS:-/usr/local/sbin/sm750-regs}

usage() {
	cat >&2 <<'EOF'
usage: sm750-pm-probe status
       sm750-pm-probe suspend
       sm750-pm-probe resume
       sm750-pm-probe cycle

  status   read the loaded version, the module reference count, the attribute
           mode and the whole last probe from the kernel log. Writes nothing.
  suspend  call the driver's suspend callback body once.
  resume   call the driver's resume callback body once.
  cycle    call suspend, then resume only if suspend succeeded.

  Every command prints the kernel's own `pm probe: ` lines, the raster
  position before and after, and the module reference count. A non-zero
  callback return is reported as FAIL and exits 1.

  This is not a system sleep: no PCI config space is saved or restored, the
  device never enters D3hot and no power state changes. A pass here says the
  callback bodies run and return 0, nothing more.
EOF
}

die() {
	printf '%s: %s\n' "$PROG" "$1" >&2
	exit "${2:-1}"
}

[ "$(id -u)" = 0 ] || die "must run as root (use the allowlisted /usr/local/sbin/$PROG)" 2

[ -e "$ATTR" ] || die "no $ATTR: the loaded module has no pm_probe attribute (module older than 0.6.9?)"

module_version() {
	cat "$MODULE_DIR/version" 2>/dev/null || printf '?'
}

module_refcnt() {
	cat "$MODULE_DIR/refcnt" 2>/dev/null || printf '?'
}

attr_mode() {
	stat -c '%a %U:%G' "$ATTR" 2>/dev/null || printf '?'
}

raster() {
	# The panel raster position advances while the pipe scans out. It is the
	# cheapest proof that the display path kept running across the probe.
	if [ -r "$REGISTERS" ] || [ -x "$REGISTERS" ]; then
		"$REGISTERS" 2>/dev/null | awk '/PANEL_CURRENT_LINE/ { print $NF; exit }'
	else
		printf '?'
	fi
}

probe_lines() {
	# Only the driver's own lines: a plain `pm probe` grep would also match
	# unrelated kernel text on some kernels.
	"$LOG_READER" -k -b --no-pager 2>/dev/null | grep -F 'pm probe: ' || true
}

print_state() {
	printf 'version:    %s\n' "$(module_version)"
	printf 'refcnt:     %s\n' "$(module_refcnt)"
	printf 'attribute:  %s (%s)\n' "$ATTR" "$(attr_mode)"
	printf 'raster:     %s\n' "$(raster)"
}

command=${1:-}
case "$command" in
status)
	[ "$#" -eq 1 ] || { usage; exit 2; }
	print_state
	lines=$(probe_lines)
	if [ -n "$lines" ]; then
		echo 'last probes in this boot:'
		printf '  %s\n' "$lines"
	else
		echo 'no pm probe has run in this boot'
	fi
	;;
suspend | resume | cycle)
	[ "$#" -eq 1 ] || { usage; exit 2; }
	before=$(raster)
	printf 'driver:     %s\n' "$(module_version)"
	printf 'refcnt:     %s\n' "$(module_refcnt)"
	printf 'raster:     %s\n' "$before"
	printf 'writing %s to %s\n' "$command" "$ATTR"
	# The attribute returns the byte count on success and the callback's own
	# error otherwise, so a failed callback fails this write as well. The status
	# is captured from the write itself: `if ! cmd` would report 0 here.
	rc=0
	printf '%s' "$command" >"$ATTR" 2>/dev/null || rc=$?
	if [ "$rc" -ne 0 ]; then
		echo "write failed (rc=$rc); the kernel log carries the reason:"
		probe_lines | tail -n 6 | sed 's/^/  /'
		exit 1
	fi
	after=$(raster)
	printf 'raster:     %s\n' "$after"
	lines=$(probe_lines)
	echo 'kernel log:'
	if [ -n "$lines" ]; then
		probe_lines | tail -n 6 | sed 's/^/  /'
	else
		echo '  (the reader returned no line; journalctl needs root)'
	fi
	case "$command:$lines" in
	suspend:*'pm probe: suspend returned 0'*) ok=1 ;;
	resume:*'pm probe: resume returned 0'*) ok=1 ;;
	cycle:*'pm probe: cycle suspend ok, resume ok'*) ok=1 ;;
	*) ok=0 ;;
	esac
	if [ "$ok" != 1 ]; then
		case "$lines" in
		*'cycle suspend failed:'* | *'resume failed:'* | *'returned '*)
			echo 'verdict:    FAIL: a callback returned a non-zero code'
			;;
		*)
			echo 'verdict:    FAIL: no "pm probe:" result line for this command'
			;;
		esac
		exit 1
	fi
	echo 'verdict:    pass (callback bodies ran and returned 0; this is not a system sleep)'
	;;
*)
	usage
	exit 2
	;;
esac
