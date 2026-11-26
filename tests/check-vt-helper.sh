#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Static gate for tools/sm750-vt.sh, the operator helper installed as
# /usr/local/sbin/sm750-vt and allowlisted in docs/ROOT-ACTIONS.md section 3.12.
# The helper unbinds fbcon from the SM750 vtconsole, unloads and reloads
# sm750hdmidrm, and re-binds fbcon. While fbcon is unbound the machine has no
# text console on any VT, so the properties this gate pins are the ones that
# keep that window short and always closed again: a resolved (never hardcoded)
# target, a refusal while userspace holds the card, an unload before a load,
# a version read back from sysfs, and a restore on every failure path.
#
# Nothing here runs the helper, writes sysfs, calls modprobe or needs root: the
# gate reads the script text and parses it with sh -n.
#
# Usage: tests/check-vt-helper.sh [script]
#        tests/check-vt-helper.sh --self-test
#        tests/check-vt-helper.sh --single [script]   (no planted controls)
#
# --self-test copies the helper into a scratch directory, applies one mutation
# per planted control and requires this gate to reject every one of them. Each
# control re-enters this script through --single, so the controls do not nest.
#
# Exit 0 when every assertion holds, 1 otherwise.
set -uo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

self_test=0
single=0
if [ "${1:-}" = "--self-test" ]; then
	self_test=1
	shift
elif [ "${1:-}" = "--single" ]; then
	single=1
	shift
fi
helper=${1:-$project_dir/tools/sm750-vt.sh}

fail=0
assertions=0
bad() {
	printf 'FAIL: %s\n' "$*" >&2
	fail=1
}
# ok MESSAGE - one printed section. The count in the pass message is derived
# from these calls, so it cannot drift away from the sections that ran.
ok() {
	assertions=$((assertions + 1))
	printf 'ok: %s\n' "$*"
}

scratch=$(mktemp -d "${TMPDIR}/sm750-vt-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

has() { # has TEXT PATTERN MESSAGE
	case $1 in
	*"$2"*) ;;
	*) bad "$3" ;;
	esac
}

# lineno TEXT - the line of the first literal occurrence, 0 when absent
lineno() {
	printf '%s\n' "$2" | grep -nF -e "$1" | head -n 1 | cut -d: -f1
}

# func NAME - the body of a shell function, indentation stripped and comment
# lines dropped, so a call is checked where it is executed.
func() {
	awk -v want="$2" '
		{ line = $0; sub(/^[ \t]+/, "", line) }
		infn && line == "}" { exit }
		infn && line != "" && line !~ /^#/ { print }
		!infn && $0 ~ ("^" want "\\(\\)[ ]*\\{") { infn = 1 }
	' "$1"
}

# --- a. the file exists, is a POSIX sh script and parses ---------------------
if [ ! -f "$helper" ]; then
	bad "a: $helper does not exist"
	echo "VT helper: 0 assertions held, the script is missing" >&2
	exit 1
fi
has "$(head -n 1 "$helper")" '#!/bin/sh' \
	"a: the shebang must be #!/bin/sh, not a bash script"
if ! sh -n "$helper" 2>"$scratch/sh-n.err"; then
	bad "a: sh -n rejects $helper: $(head -n 1 "$scratch/sh-n.err")"
fi
ok "a. the helper exists, starts with #!/bin/sh and passes sh -n"

body=$(cat "$helper")
# The off sequence, for ordering checks. The restore function is defined above
# it and legitimately repeats a couple of the same calls, so an ordering test
# against the whole file would compare the trap against the success path.
offbody=$(awk '/^# off$/{f=1} f' "$helper")

# --- b. three modes, everything else reaches usage ---------------------------
has "$body" 'show|off|on' \
	"b: the usage and the dispatch must name exactly show, off and on"
has "$body" '*) usage ;;' \
	"b: an unknown mode must fall through to usage, not to a default action"
has "$body" 'exit 2' \
	"b: the usage path must exit 2 so a wrong mode cannot read as a run"
ok "b. modes show, off and on dispatch, anything else exits 2"

# --- c. an unprivileged run cannot write bind -------------------------------
has "$body" '[ "$(id -u)" -eq 0 ]' \
	"c: the helper must check that it is root before writing sysfs"
has "$body" 'must run as root' "c: the root refusal must name the problem"
ok "c. show may run unprivileged, off and on refuse without root"

# --- d. the target is resolved, never hardcoded -----------------------------
has "$body" 'resolve_target' "d: the target must come from resolve_target"
has "$body" 'for vc in "$VTCLASS"/vtcon*' \
	"d: the vtconsole enumeration must glob the class, not name an index"
has "$body" '[ "$count" -gt 1 ]' \
	"d: more than one framebuffer vtconsole must be refused, not picked from"
# A comment may name vtcon1 as an example; executed text may not. The filter
# drops comment-only lines so the guard stays precise instead of banning a word.
if grep -nE 'vtcon[0-9]+' "$helper" | grep -vE ':[[:space:]]*#' >"$scratch/vtcon.hit"; then
	bad "d: a hardcoded vtconsole index is used as the target: $(head -n 1 "$scratch/vtcon.hit")"
fi
ok "d. the vtconsole is resolved by globbing the class, and an index is never used"

# --- e. bind 0 detaches and bind 1 restores, both read back -----------------
has "$body" 'write_bind "$TARGET" 0' "e: the detach must write 0 to the bind file"
has "$body" 'write_bind "$TARGET" 1' "e: the restore must write 1 to the bind file"
has "$body" 'printf '"'"'%s\n'"'"' "$2" >"$1/bind"' \
	"e: the single writer must be the bind file itself"
has "$body" '[ "$(cat "$1/bind" 2>/dev/null || echo '"'"'?'"'"')" = "$2" ]' \
	"e: every bind write must be read back before it counts"
ok "e. bind 0 detaches and bind 1 restores, each read back from sysfs"

# --- f. both resources are restored on every failing path -------------------has "$body" 'restore_all' "f: a restore function must exist"
has "$body" "trap 'rc=\$?; if [ \"\$rc\" -ne 0 ]; then restore_all; fi; exit \$rc' EXIT" \
	"f: exactly one EXIT trap must restore the state and re-raise the status"
has "$(func "$helper" restore_all)" 'write_bind "$TARGET" 1' \
	"f: the restore function must write bind 1"
has "$(func "$helper" restore_all)" 'return 0' \
	"f: the trap function must end with an explicit return so it cannot mask the status"
has "$body" 'unbound=1' "f: the restore must be armed by the detach"
has "$body" 'FINISHED=1' \
	"f: a completed run must disarm the restore so it never undoes its own success"
ok "f. one EXIT trap restores the state after any non-zero exit and keeps the status"

# --- g. unload before load, and only when nobody holds the card -------------
has "$body" 'holders' "g: userspace holders must be enumerated"
has "$body" '/proc/[0-9]*' "g: the holder scan must walk the fd table"
has "$body" 'if [ -n "$h" ]; then' \
	"g: the unload must be gated on the holder list, not merely report it"
has "$body" 'userspace processes hold the card' \
	"g: a held card must be refused with a message that names the reason"
unload=$(lineno '"$MODPROBE" -r sm750hdmidrm' "$offbody")
load=$(lineno '"$MODPROBE" sm750hdmidrm' "$offbody")
if [ -z "$unload" ] || [ -z "$load" ]; then
	bad "g: both the unload (modprobe -r) and the load (modprobe) must be present"
elif [ "$unload" -ge "$load" ]; then
	bad "g: the unload at line $unload must precede the load at line $load"
fi
ok "g. the holder refusal runs first and the unload precedes the load"

# --- h. the loaded version is read back, not assumed ------------------------
# The read-back is the post-load guard, not the read used to print the state
# before the change, so the ordered literal is the "missing after the load"
# test that follows the load rather than the first mention of the file.
ver=$(lineno 'is missing after the load' "$offbody")
if [ -z "$ver" ]; then
	bad "h: the helper must read /sys/module/sm750hdmidrm/version back after the load"
elif [ -n "$load" ] && [ "$ver" -le "$load" ]; then
	bad "h: the version read-back at line $ver must follow the load at line $load"
fi
has "$body" 'is missing after the load' \
	"h: a load without a version attribute must fail, not pass"
ok "h. the version is read back from sysfs after the load"

# --- i. the console-only recovery mode exists ------------------------------
has "$body" 'module unloaded' "i: off must report the unload"
has "$(func "$helper" restore_all)" 'FAILED to re-bind' \
	"i: a failed restore must say so and point at the on mode"
ok "i. off reports the unload and a failed restore points the operator at on"

# --- k. the PCI unbind step that releases the framebuffer reference (A51) ---
# Detaching the vtconsole alone left the module refcount at 1 and modprobe -r
# failed on the first live run, so the sequence now removes the device as well.
has "$offbody" 'write_dev unbind' "k: the device must be unbound, not only the console"
has "$offbody" 'write_dev bind' "k: the device must be bound again after the load"
has "$body" 'refcnt before any change' \
	"k: the module refcount must be printed before anything is touched"
has "$body" 'refcnt after the unbind' \
	"k: the module refcount must be printed again right after the unbind"
has "$body" 'if [ "$rc_after" != 0 ]; then' \
	"k: a refcount that did not drop to zero must fail the run with that number"
has "$body" 'if ! dev_bound; then' \
	"k: off must refuse when the device is not bound to its driver"

detach=$(lineno 'write_bind "$TARGET" 0' "$offbody")
pci_unbind=$(lineno 'write_dev unbind' "$offbody")
pci_unload=$(lineno '"$MODPROBE" -r sm750hdmidrm' "$offbody")
pci_load=$(lineno '"$MODPROBE" sm750hdmidrm' "$offbody")
pci_rebind=$(lineno 'write_dev bind' "$offbody")
pci_console=$(lineno 'write_bind "$TARGET" 1' "$offbody")
for pair in "detach:$detach:unbind:$pci_unbind" "unbind:$pci_unbind:unload:$pci_unload" \
	"unload:$pci_unload:load:$pci_load" "load:$pci_load:rebind:$pci_rebind" \
	"rebind:$pci_rebind:console:$pci_console"; do
	first_name=${pair%%:*}
	rest=${pair#*:}
	first=${rest%%:*}
	rest=${rest#*:}
	second_name=${rest%%:*}
	second=${rest#*:}
	if [ -z "$first" ] || [ -z "$second" ]; then
		bad "k: one of $first_name and $second_name is missing from the off sequence"
	elif [ "$first" -ge "$second" ]; then
		bad "k: $first_name at line $first must precede $second_name at line $second"
	fi
done
ok "k. the order is fbcon detach, PCI unbind, unload, load, PCI rebind, fbcon rebind"

# The trap must put the module back first (the device has nothing to bind to
# otherwise), then the device, then the console.
trap_body=$(func "$helper" restore_all)
t_mod=$(lineno '"$MODPROBE" sm750hdmidrm' "$trap_body")
t_dev=$(lineno 'write_dev bind' "$trap_body")
t_con=$(lineno 'write_bind "$TARGET" 1' "$trap_body")
if [ -z "$t_mod" ] || [ -z "$t_dev" ] || [ -z "$t_con" ]; then
	bad "k: the restore must reload the module, re-bind the device and re-bind the console"
elif [ "$t_mod" -ge "$t_dev" ] || [ "$t_dev" -ge "$t_con" ]; then
	bad "k: the restore order must be module ($t_mod), device ($t_dev), console ($t_con)"
fi
has "$trap_body" 'mod_down' "k: the restore must reload a module this run unloaded"
has "$trap_body" 'dev_unbound' "k: the restore must re-bind a device this run unbound"
ok "k. the trap restores module, then device, then console, and never on success"

# --- l. the holder scan is pinned to node identity, not to a node name -------
# The scan globbed `*card0*`, but the DRM node name is not stable: after a
# reload the SM750 card is card4 and the render node renderD132, so the scan
# reported zero holders while the module refcount was 1 and the refusal printed
# an empty holder list - a false statement that hid the real holder.
has "$body" '/dev/dri/by-path/pci-0000:01:00.0-card' \
	"l: the card must be addressed through its stable by-path link"
has "$body" '/dev/dri/by-path/pci-0000:01:00.0-render' \
	"l: the render node must be addressed through its by-path link too"
has "$(func "$helper" node_inode)" 'stat -L -c' \
	"l: a node must be resolved to its dev:inode pair, not compared by name"
has "$(func "$helper" holders)" 'node_inode' \
	"l: the fd scan must compare node identity, not a node name"
has "$(func "$helper" holders)" 'basename "$t"' \
	"l: the matched node path must be printed so the operator sees which node"
has "$body" 'holder scan pinned to the card identity, not to a node name' \
	"l: the scan must carry the reason it is identity-based"
# A comment may name card0 as the unstable example; executed text may not glob
# a node name. Same comment filter as the vtconsole guard in section d.
if grep -nE '\*card[0-9]+\*' "$helper" | grep -vE ':[[:space:]]*#' >"$scratch/cardglob.hit"; then
	bad "l: the fd scan must not glob a DRM node name: $(head -n 1 "$scratch/cardglob.hit")"
fi
ok "l. the holder scan matches by dev:inode and prints the node it matched"

[ "$fail" -eq 0 ] || exit 1

if [ "$single" -eq 1 ]; then
	printf 'VT helper assertions passed (%s)\n' "$helper"
	exit 0
fi

printf 'ok: j. helper structure checked\n'
assertions=$((assertions + 1))

# --- planted controls -------------------------------------------------------
# Each mutation removes exactly one of the guarantees asserted above; the gate
# must reject every one with a message naming the missing guarantee.
plant_never_restore() { # fbcon left detached after a failed unload
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = "trap 'rc=$?; if [ \"$rc\" -ne 0 ]; then restore_all; fi; exit $rc' EXIT"
new = "trap 'rc=$?; exit $rc' EXIT"
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_hardcoded_vtcon() { # the target pinned to one index
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'resolve_target || exit 1\n'
new = 'TARGET=/sys/class/vtconsole/vtcon1\nresolve_target || exit 1\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_modprobe_order_reversed() { # load before unload
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
unload = 'if ! "$MODPROBE" -r sm750hdmidrm; then'
load = 'if ! "$MODPROBE" sm750hdmidrm; then'
assert s.count(unload) == 1, s.count(unload)
assert s.count(load) == 1, s.count(load)
s = s.replace(unload, '@@UNLOAD@@').replace(load, unload)
open(p, 'w').write(s.replace('@@UNLOAD@@', load))
MUT
}
plant_version_readback_removed() { # the load accepted without a version
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('if [ ! -r "$MODDIR/version" ]; then\n'
       '\techo "$PROG: $MODDIR/version is missing after the load; the module did not come back" >&2\n'
       '\texit 3\n'
       'fi\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_holder_check_dropped() { # the unload attempted while a process holds the card
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'if [ -n "$h" ]; then\n'
new = 'if [ -n "" ]; then\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_pci_unbind_dropped() { # the A51 step removed, so the refcount never drops
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''write_dev unbind || {
\techo "$PROG: could not unbind $BDF; $DRIVER_ATTR still resolves to $(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo '?')" >&2
\texit 3
}
'''
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_pci_rebind_dropped() { # the device left unbound after the load
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''if [ "$(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo none)" != "$DRVDIR" ]; then
\techo "$PROG: the driver core did not re-probe $BDF; binding it explicitly"
\twrite_dev bind || {
\t\techo "$PROG: could not bind $BDF to $(basename "$DRVDIR"); the device has no driver" >&2
\t\texit 3
\t}
fi
'''
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ':\n'))
MUT
}
plant_refcount_not_reported() { # the operator never sees the number that matters
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'echo "$PROG: device unbound, refcnt after the unbind: $rc_after"\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_trap_restores_fbcon_only() { # the device stays unbound after a failure
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''\tif [ "$dev_unbound" -eq 1 ] && [ -n "$DRVDIR" ]; then
\t\tif write_dev bind; then
\t\t\tdev_unbound=0
\t\t\techo "$PROG: $BDF re-bound to $(basename "$DRVDIR")" >&2
\t\telse
\t\t\techo "$PROG: FAILED to re-bind $BDF; write it to $DRVDIR/bind by hand" >&2
\t\tfi
\tfi
'''
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_holder_scan_name_glob() { # the fd scan back on an unstable node name
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''\t\t\tid=$(node_inode "$t")
\t\t\t[ -n "$id" ] || continue
\t\t\t[ "$id" = "$card" ] || [ "$id" = "$rend" ] || continue
'''
new = '''\t\t\tcase $t in
\t\t\t*card0*) ;;
\t\t\t*) continue ;;
\t\t\tesac
'''
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}

control() {
	local name=$1
	local planted=$scratch/sm750-vt.sh
	local err=$scratch/stderr

	cp "$helper" "$planted"
	shift
	"$@" "$planted"
	if bash "$0" --single "$planted" >/dev/null 2>"$err"; then
		bad "j: planted control $name was not rejected"
	elif [ ! -s "$err" ]; then
		bad "j: planted control $name was rejected without a message"
	else
		printf 'negative control %s: rejected: %s\n' "$name" "$(head -n 1 "$err")"
	fi
}

control never-restore plant_never_restore
control hardcoded-vtcon plant_hardcoded_vtcon
control modprobe-order-reversed plant_modprobe_order_reversed
control version-readback-removed plant_version_readback_removed
control holder-check-dropped plant_holder_check_dropped
control pci-unbind-dropped plant_pci_unbind_dropped
control pci-rebind-dropped plant_pci_rebind_dropped
control refcount-not-reported plant_refcount_not_reported
control trap-restores-fbcon-only plant_trap_restores_fbcon_only
control holder-scan-name-glob plant_holder_scan_name_glob

# The pristine copy must still pass, otherwise the controls prove nothing.
cp "$helper" "$scratch/pristine.sh"
if ! bash "$0" --single "$scratch/pristine.sh" >/dev/null 2>"$scratch/pristine.err"; then
	bad "j: the unmutated copy was rejected: $(head -n 1 "$scratch/pristine.err")"
fi
printf 'negative control pristine: accepted\n'

[ "$fail" -eq 0 ] || exit 1
controls=10
if [ "$self_test" -eq 1 ]; then
	printf 'VT helper checks passed (%s assertions, %s planted controls, self-test)\n' "$assertions" "$controls"
else
	printf 'VT helper checks passed (%s assertions, %s planted controls)\n' "$assertions" "$controls"
fi