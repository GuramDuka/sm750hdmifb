#!/bin/sh
# sm750-vt - reload the sm750hdmidrm module without a reboot, by temporarily
# detaching fbcon from the console device that holds the module open.
#
# Runs as root through two NOPASSWD entries, one per state-changing mode:
#   coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-vt off
#   coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-vt on
# `show` changes nothing and needs no entry: it only reads sysfs and /proc.
#
# Why the sequence is needed: a loaded DRM module that registered an in-kernel
# fbdev client is held open by fbcon, so `modprobe -r` reports
# "Module sm750hdmidrm is in use." even with an empty holders list. Detaching
# the framebuffer vtconsole alone does NOT release that reference (A51, the
# first live attempt on 2026-11-26): the reference is the registered
# framebuffer, and it goes away only when the driver's remove path runs. The
# order is therefore: write 0 to the framebuffer vtconsole's bind (no console
# output into a framebuffer about to be torn down), write the BDF to
# /sys/bus/pci/drivers/sm750hdmidrm/unbind so the driver core calls remove and
# unregisters the DRM device with its fbdev client, `modprobe -r`, `modprobe`,
# then wait for the device to be re-probed and bind 1 puts fbcon back.
#
# Guard rails, all hard failures rather than warnings:
#   - refuses to run as anything but root (sysfs bind is root-only);
#   - the vtconsole is RESOLVED, never hardcoded, and the helper refuses rather
#     than guesses when more than one framebuffer vtconsole exists;
#   - refuses unless the device is bound to sm750hdmidrm and that driver exposes
#     writable bind and unbind attributes, so the PCI step cannot fail silently;
#   - refuses to unload while a userspace process holds the DRM card, naming the
#     processes instead of printing a modprobe error; the holder scan is pinned
#     to the card identity, not to a node name (see holders());
#   - prints the module refcount before and after the unbind, so a reference
#     that did not go away is reported as such instead of as a modprobe error;
#   - on every non-zero exit the trap reloads the module if it is down, re-binds
#     the PCI device, then re-binds fbcon, so an interrupted `off` leaves
#     neither a console-less nor a driver-less host; a finished run sets a guard
#     so restore code never runs twice;
#   - every printed success is a value read back from sysfs afterwards.
#
# While fbcon is unbound there is NO text console on any VT. Run `off` from a
# remote session, never from the SM750 monitor itself.
#
# `on` re-binds fbcon and nothing else: it is the recovery path when the console
# is missing but the device is fine. It does NOT re-bind the PCI device, so if
# the device was left unbound the operator must also write the BDF to
# /sys/bus/pci/drivers/sm750hdmidrm/bind.
#
# Usage: sm750-vt show | off | on
#
# Exit codes:
#   0  the requested action completed and every expectation held
#   1  environment problem, ambiguous target, or console restore problem
#   2  usage error
#   3  a measured expectation failed (a sysfs value did not read back)
set -eu

PROG=sm750-vt
BDF=0000:01:00.0
# The by-path links are the stable handles for the two DRM nodes: the cardN and
# renderDN names they point at are re-issued on every probe, so they are read
# and never assumed.
CARD=/dev/dri/by-path/pci-0000:01:00.0-card
RENDER=/dev/dri/by-path/pci-0000:01:00.0-render
VTCLASS=/sys/class/vtconsole
DRIVER_ATTR=/sys/bus/pci/devices/$BDF/driver
# Fixed by driver name, not resolved through the device, so it stays valid
# across the unload in the middle of the reload (the module creates the
# directory and creates it again on load).
DRVDIR=/sys/bus/pci/drivers/sm750hdmidrm
MODDIR=/sys/module/sm750hdmidrm
TTYACTIVE=/sys/class/tty/tty0/active
MODPROBE=/usr/bin/modprobe

usage() {
	echo "usage: $PROG show|off|on" >&2
	exit 2
}

# write_bind FILE VALUE - the only writer of a bind attribute, so every write
# goes through the same readback.
write_bind() {
	printf '%s\n' "$2" >"$1/bind" 2>/dev/null || return 1
	[ "$(cat "$1/bind" 2>/dev/null || echo '?')" = "$2" ]
}

# refcnt - the module refcount, or '-' when the module is not loaded. This is
# the number the whole sequence exists to drive to zero, so it is printed before
# and after the unbind instead of being inferred from a modprobe error.
refcnt() {
	cat "$MODDIR/refcnt" 2>/dev/null || printf '%s\n' '-'
}

# poll_refcnt_zero MAX SECONDS_EACH - wait, with a hard bound, for the module
# refcount to read 0. The wait is bounded because a holder can appear at any
# moment: giving up and saying so is the only safe answer, and it is never
# inferred later from a modprobe error. Never loops without a counter and never
# calls modprobe.
poll_refcnt_zero() {
	max=$1
	each=${2:-0.1}
	i=0
	while [ "$i" -lt "$max" ]; do
		if [ "$(refcnt)" = 0 ]; then
			echo "$PROG: refcount reached 0 after $i waits"
			return 0
		fi
		i=$((i + 1))
		sleep "$each" 2>/dev/null || sleep 1
	done
	echo "$PROG: the module refcount did not reach 0 within $max waits" >&2
	return 1
}

# refcnt_diagnostics - on stderr, everything needed to understand a refusal to
# unload: the number, who might hold it, the console bindings, and the device's
# current driver. The refcount is read first so the labels agree.
refcnt_diagnostics() {
	n=$(refcnt)
	echo "$PROG: module refcount: $n" >&2
	echo "$PROG: holders directory: $(ls -A "$MODDIR/holders" 2>/dev/null | tr '\n' ' ')" >&2
	h=$(holders || true)
	if [ -z "$h" ]; then
		echo "$PROG: userspace holders: none" >&2
	else
		echo "$PROG: userspace holders:" >&2
		printf '%s\n' "$h" | sed 's/^/  /' >&2
	fi
	for vc in "$VTCLASS"/vtcon*; do
		[ -d "$vc" ] || continue
		echo "$PROG: $(basename "$vc") name=$(cat "$vc/name" 2>/dev/null || echo '?') bind=$(cat "$vc/bind" 2>/dev/null || echo '?')" >&2
	done
	echo "$PROG: device binding: $(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo none)" >&2
	if [ "$n" = -1 ]; then
		echo "$PROG: sm750hdmidrm is stuck in Unloading (refcount -1); only a reboot clears this state" >&2
	fi
}

# dev_bound - true when the device's driver link resolves to our driver dir.
dev_bound() {
	[ "$(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo none)" = "$DRVDIR" ]
}

# write_dev unbind|bind - write the BDF to the driver attribute and verify the
# result through the device tree, because neither attribute has a value that
# can be read back: an unbind is confirmed by the driver link disappearing, a
# bind by it resolving to the same driver directory again.
write_dev() {
	case ${1:-} in
	unbind)
		printf '%s\n' "$BDF" >"$DRVDIR/unbind" 2>/dev/null || return 1
		[ ! -e "$DRIVER_ATTR" ]
		;;
	bind)
		printf '%s\n' "$BDF" >"$DRVDIR/bind" 2>/dev/null || return 1
		dev_bound
		;;
	*)
		return 1
		;;
	esac
}

# fb_vtcons - print one line per vtconsole whose name says it is a framebuffer
# console. The kernel registers one such vtconsole per registered fb_info, so a
# count above one means the owner cannot be attributed from sysfs alone.
fb_vtcons() {
	for vc in "$VTCLASS"/vtcon*; do
		[ -d "$vc" ] || continue
		nm=$(cat "$vc/name" 2>/dev/null || echo '?')
		case $nm in
		*"frame buffer device"*) printf '%s\n' "$vc" ;;
		esac
	done
}

# resolve_target - set TARGET and BASIS. Prints the reason on stdout so show can
# quote it; refusals go to stderr and return 1. DRVDIR is a global constant and
# is NOT touched here.
resolve_target() {
	TARGET=
	BASIS=
	cands=$(fb_vtcons | tr '\n' ' ')
	set -- $(fb_vtcons)
	count=$#
	if [ "$count" -eq 0 ]; then
		echo "$PROG: no framebuffer vtconsole under $VTCLASS; nothing can hold the module" >&2
		return 1
	fi
	if [ "$count" -gt 1 ]; then
		echo "$PROG: $count framebuffer vtconsoles exist ($cands)." >&2
		echo "$PROG: kernel $(uname -r) exposes no vtconsole owner link and CONFIG_FB_DEVICE is unset, so the SM750 one cannot be identified from sysfs; refusing to guess." >&2
		return 1
	fi
	TARGET=$1
	if dev_bound; then
		driver=$(basename "$DRVDIR")
		if [ "$driver" != sm750hdmidrm ]; then
			echo "$PROG: $BDF is bound to '$driver', not sm750hdmidrm" >&2
			return 1
		fi
		BASIS="sole framebuffer vtconsole on the host, with the sole sm750hdmidrm card ($BDF); not by a hardcoded index or a node name"
	else
		BASIS="sole framebuffer vtconsole on the host; $BDF is currently unbound from any driver"
	fi
	return 0
}

# node_inode PATH - the dev:inode pair of a node, empty when it cannot be
# read. This is the only identity a DRM node has: the cardN and renderDN names
# are re-issued on every probe (card0 before the reload, card4 after it on this
# host on 2026-11-26), so a name can never be compared, only resolved.
node_inode() {
	stat -L -c '%d:%i' "$1" 2>/dev/null || true
}

# card_inode - the dev:inode pair that identifies the card node even after a
# reload re-creates it under a different name.
card_inode() {
	node_inode "$CARD"
}

# render_inode - the same for the render node. Its absence is tolerated: an
# older module without DRIVER_RENDER has no render node, and the card alone is
# then the whole set of nodes to scan for.
render_inode() {
	[ -e "$RENDER" ] || return 0
	node_inode "$RENDER"
}

# holders - print "pid:comm node" per process whose fd table resolves to the
# SM750 card or render node.
#
# Why identity and not a name: this is a
# holder scan pinned to the card identity, not to a node name; the name is
# read from the fd link only to print it, never to decide, because card0 is
# not stable across a driver reload (the holder-scan failure mode - a
# `*card0*` glob reported zero holders while the module refcount was 1, which
# hid the real holder behind an empty list).
#
# Unreadable /proc entries are skipped silently: this runs as root, where the
# only such entries are kernel threads that cannot hold a DRM fd.
holders() {
	card=$(card_inode)
	rend=$(render_inode)
	[ -n "$card$rend" ] || return 0
	for p in /proc/[0-9]*; do
		for f in "$p"/fd/*; do
			t=$(readlink "$f" 2>/dev/null) || continue
			case $t in
			/dev/*) ;;
			*) continue ;;
			esac
			id=$(node_inode "$t")
			[ -n "$id" ] || continue
			[ "$id" = "$card" ] || [ "$id" = "$rend" ] || continue
			printf '%s:%s %s\n' "${p#/proc/}" "$(cat "$p/comm" 2>/dev/null || echo '?')" "$(basename "$t")"
			break
		done
	done
}

module_line() {
	if [ -r "$MODDIR/version" ]; then
		printf 'module:       version=%s srcversion=%s refcnt=%s\n' \
			"$(cat "$MODDIR/version" 2>/dev/null || echo '?')" \
			"$(cat "$MODDIR/srcversion" 2>/dev/null || echo '?')" \
			"$(refcnt)"
	else
		printf 'module:       sm750hdmidrm is not loaded\n'
	fi
}

show_state() {
	printf 'vtconsole:    %s\n' "$VTCLASS"
	for vc in "$VTCLASS"/vtcon*; do
		[ -d "$vc" ] || continue
		printf '  %-12s bind=%s name=%s\n' "$(basename "$vc")" \
			"$(cat "$vc/bind" 2>/dev/null || echo '?')" \
			"$(cat "$vc/name" 2>/dev/null || echo '?')"
	done
	if resolve_target; then
		printf 'target:       %s\n' "$TARGET"
		printf 'basis:        %s\n' "$BASIS"
		printf '  bind now:   %s\n' "$(cat "$TARGET/bind" 2>/dev/null || echo '?')"
		printf 'driver dir:   %s\n' "$DRVDIR"
	else
		printf 'target:       unresolvable (see the message above)\n'
	fi
	module_line
	if [ "$(refcnt)" = -1 ]; then
		printf 'state:        Unloading (wedged; only a reboot clears this)\n'
	else
		printf 'state:        live\n'
	fi
	printf 'active tty:   %s\n' "$(cat "$TTYACTIVE" 2>/dev/null || echo '?')"
	printf 'card:         %s -> %s inode %s\n' "$CARD" \
		"$(readlink -f "$CARD" 2>/dev/null || echo '?')" "$(card_inode)"
	printf 'render:       %s -> %s inode %s\n' "$RENDER" \
		"$(readlink -f "$RENDER" 2>/dev/null || echo '?')" \
		"$(render_inode || printf 'none')"
	h=$(holders || true)
	if [ -z "$h" ]; then
		printf 'holders:      0 userspace processes hold the card\n'
	else
		printf 'holders:      %s\n' "$(printf '%s\n' "$h" | wc -l | tr -d ' ')"
		printf '%s\n' "$h" | sed 's/^/  /'
	fi
	return 0
}

[ "$#" -eq 1 ] || usage
mode=$1
case $mode in
show|off|on) ;;
*) usage ;;
esac

[ "$(id -u)" -eq 0 ] || {
	[ "$mode" = show ] || { echo "$PROG: must run as root" >&2; exit 1; }
}

if [ "$mode" = show ]; then
	show_state
	exit 0
fi

[ -e "$CARD" ] || { echo "$PROG: $CARD is missing" >&2; exit 1; }
[ -x "$MODPROBE" ] || { echo "$PROG: $MODPROBE is missing" >&2; exit 1; }
resolve_target || exit 1

unbound=0     # fbcon detached by this run
dev_unbound=0 # PCI device unbound by this run
mod_down=0    # module unloaded by this run and not yet loaded again
FINISHED=0    # set once off has completed; the trap then restores nothing

# restore_all - undo whatever this run changed, in the order that keeps the
# machine usable: the module back first (otherwise the device has no driver to
# bind to), then the PCI device, then the console. It ends with an explicit
# return so it cannot overwrite the exit status the EXIT trap is about to
# re-raise (the A49 gate lesson: a trap whose last command can fail silently
# replaces the real status).
restore_all() {
	[ "$FINISHED" -eq 0 ] || return 0
	if [ "$mod_down" -eq 1 ]; then
		if "$MODPROBE" sm750hdmidrm; then
			mod_down=0
			echo "$PROG: module reloaded by the restore path" >&2
		else
			echo "$PROG: FAILED to reload sm750hdmidrm; the card has no driver, load it by hand" >&2
		fi
	fi
	if [ "$dev_unbound" -eq 1 ] && [ -n "$DRVDIR" ]; then
		if write_dev bind; then
			dev_unbound=0
			echo "$PROG: $BDF re-bound to $(basename "$DRVDIR")" >&2
		else
			echo "$PROG: FAILED to re-bind $BDF; write it to $DRVDIR/bind by hand" >&2
		fi
	fi
	[ "$unbound" -eq 1 ] || return 0
	if write_bind "$TARGET" 1; then
		unbound=0
		echo "$PROG: fbcon re-bound to $TARGET (bind=1)" >&2
	else
		echo "$PROG: FAILED to re-bind fbcon to $TARGET; run '$PROG on' and check $TARGET/bind" >&2
	fi
	return 0
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then restore_all; fi; exit $rc' EXIT

if [ "$mode" = on ]; then
	bind=$(cat "$TARGET/bind" 2>/dev/null || echo '?')
	if [ "$bind" = 1 ]; then
		echo "$PROG: fbcon is already bound to $TARGET (bind=1), nothing to do"
		exit 0
	fi
	write_bind "$TARGET" 1 || {
		echo "$PROG: could not write 1 to $TARGET/bind" >&2
		exit 3
	}
	echo "$PROG: fbcon re-bound to $TARGET, bind=$(cat "$TARGET/bind")"
	module_line
	exit 0
fi

# off
# The A65 wedge: a modprobe -r on a module whose framebuffer reference is still
# held can leave it in state Unloading with refcount -1 forever. Nothing this
# helper can do clears that, and detaching the console first only makes the
# panel darker, so refuse before changing anything.
if [ "$(refcnt)" = -1 ]; then
	echo "$PROG: sm750hdmidrm is already stuck in Unloading (refcount -1); only a reboot clears this state, and detaching the console now would only make the panel darker" >&2
	echo "$PROG: record this line: $(grep -m 1 '^sm750hdmidrm ' /proc/modules 2>/dev/null || echo 'no /proc/modules line')" >&2
	echo "$PROG: set a65_trace=1 to mark the stop point on the next attempt" >&2
	exit 1
fi

bind=$(cat "$TARGET/bind" 2>/dev/null || echo '?')
if [ "$bind" != 1 ]; then
	echo "$PROG: fbcon is already unbound from $TARGET (bind=$bind); run '$PROG on' to restore it" >&2
	exit 1
fi

h=$(holders || true)
if [ -n "$h" ]; then
	echo "$PROG: userspace processes hold the card, so the module cannot be unloaded:" >&2
	printf '%s\n' "$h" | sed 's/^/  /' >&2
	exit 1
fi

# The reload needs the driver directory present with writable bind and unbind
# attributes; without them the framebuffer reference cannot be released and the
# unload would fail exactly as it did before A51.
if [ ! -d "$DRVDIR" ]; then
	echo "$PROG: $DRVDIR does not exist, so sm750hdmidrm is not loaded and there is nothing to reload" >&2
	exit 1
fi
if [ ! -e "$DRVDIR/unbind" ] || [ ! -e "$DRVDIR/bind" ]; then
	echo "$PROG: $DRVDIR lacks an unbind or bind attribute; the device cannot be freed for a reload" >&2
	exit 1
fi
if ! dev_bound; then
	echo "$PROG: $DRIVER_ATTR does not resolve to $DRVDIR; run '$PROG show' and bind $BDF to $DRVDIR/bind first" >&2
	exit 1
fi

echo "$PROG: target $TARGET (basis: $BASIS)"
echo "$PROG: driver dir $DRVDIR"
echo "$PROG: refcnt before any change: $(refcnt)"

echo "$PROG: detaching fbcon; there will be no text console until the reload ends"
write_bind "$TARGET" 0 || {
	echo "$PROG: could not write 0 to $TARGET/bind" >&2
	exit 3
}
unbound=1
echo "$PROG: fbcon detached, bind=$(cat "$TARGET/bind")"

# Detaching the vtconsole releases the console binding but not the reference
# the registered framebuffer holds on the module (A51). Removing the device
# runs the driver's remove path, which unregisters the DRM device and its
# fbdev client; only then does the refcount drop.
from_version=$(cat "$MODDIR/version" 2>/dev/null || echo '?')
echo "$PROG: unbinding $BDF from $(basename "$DRVDIR") to release the framebuffer"
write_dev unbind || {
	echo "$PROG: could not unbind $BDF; $DRIVER_ATTR still resolves to $(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo '?')" >&2
	exit 3
}
dev_unbound=1
rc_after=$(refcnt)
echo "$PROG: device unbound, refcnt after the unbind: $rc_after"

# A52: the refcount can be held by a userspace fd and can also clear by itself
# a moment after the remove path runs, so wait a bounded time for it instead of
# reading once. A refusal here restores everything through the EXIT trap.
if ! poll_refcnt_zero 20 0.1; then
	echo "$PROG: the module refcount is still $(refcnt) after unbinding the device, so something other than the framebuffer holds it; modprobe -r cannot succeed" >&2
	refcnt_diagnostics
	exit 1
fi

# A holder can appear between the poll and the unload, and modprobe -r on a
# still-held module is the one call that can wedge it in Unloading forever, so
# re-read immediately before it and refuse the same way.
rc=$(refcnt)
if [ "$rc" != 0 ]; then
	echo "$PROG: the module refcount is $rc immediately before modprobe -r, so a holder appeared after the wait; modprobe -r cannot succeed" >&2
	refcnt_diagnostics
	exit 1
fi

if ! "$MODPROBE" -r sm750hdmidrm; then
	rc=$(refcnt)
	if [ "$rc" = -1 ]; then
		echo "$PROG: modprobe -r left the module in Unloading; this is the A65 state and only a reboot clears it" >&2
	else
		echo "$PROG: modprobe -r sm750hdmidrm failed even though the refcount read 0" >&2
		refcnt_diagnostics
	fi
	exit 1
fi
mod_down=1
echo "$PROG: module unloaded"

if ! "$MODPROBE" sm750hdmidrm; then
	echo "$PROG: modprobe sm750hdmidrm failed; the device stays unbound and the console stays detached, the restore path is running" >&2
	exit 1
fi
mod_down=0

# The driver registers its fbdev client from drm_client_setup after
# drm_dev_register, so the version file can appear a moment after modprobe
# returns.
i=0
while [ "$i" -lt 20 ]; do
	[ -r "$MODDIR/version" ] && break
	sleep 0.1 2>/dev/null || sleep 1
	i=$((i + 1))
done
if [ ! -r "$MODDIR/version" ]; then
	echo "$PROG: $MODDIR/version is missing after the load; the module did not come back" >&2
	exit 3
fi
to_version=$(cat "$MODDIR/version")

# Probe: the driver core normally binds a matching device itself. If it did
# not, bind it explicitly and confirm through the device tree rather than
# trusting the write.
if [ "$(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo none)" != "$DRVDIR" ]; then
	echo "$PROG: the driver core did not re-probe $BDF; binding it explicitly"
	write_dev bind || {
		echo "$PROG: could not bind $BDF to $(basename "$DRVDIR"); the device has no driver" >&2
		exit 3
	}
fi
dev_unbound=0
echo "$PROG: device re-bound, $DRIVER_ATTR -> $(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo '?')"

write_bind "$TARGET" 1 || {
	echo "$PROG: module reloaded but fbcon could not be re-bound to $TARGET" >&2
	exit 3
}
unbound=0
FINISHED=1

printf 'fbcon:        detached then re-bound to %s, bind=%s\n' "$TARGET" "$(cat "$TARGET/bind")"
printf 'device:       %s unbound then re-bound to %s\n' "$BDF" "$(basename "$(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo '?')")"
printf 'reloaded:     %s -> %s (srcversion=%s refcnt=%s)\n' "$from_version" "$to_version" \
	"$(cat "$MODDIR/srcversion" 2>/dev/null || echo '?')" "$(refcnt)"
exit 0
