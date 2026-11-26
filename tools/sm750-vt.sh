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
# "Module sm750hdmidrm is in use." even with an empty holders list. Writing 0 to
# the framebuffer vtconsole's bind releases that client; the module then unloads,
# loads again from /lib/modules, and bind 1 puts fbcon back.
#
# Guard rails, all hard failures rather than warnings:
#   - refuses to run as anything but root (sysfs bind is root-only);
#   - the vtconsole is RESOLVED, never hardcoded, and the helper refuses rather
#     than guesses when more than one framebuffer vtconsole exists;
#   - refuses to unload while a userspace process holds the DRM card, naming the
#     processes instead of printing a modprobe error;
#   - fbcon is re-bound on every non-zero exit once it was unbound, including a
#     failed unload, so an interrupted `off` cannot leave a console-less host;
#   - every printed success is a value read back from sysfs afterwards.
#
# While fbcon is unbound there is NO text console on any VT. Run `off` from a
# remote session, never from the SM750 monitor itself.
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
CARD=/dev/dri/by-path/pci-0000:01:00.0-card
VTCLASS=/sys/class/vtconsole
DRIVER_ATTR=/sys/bus/pci/devices/$BDF/driver
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
# quote it; refusals go to stderr and return 1.
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
	driver=$(basename "$(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo none)")
	if [ "$driver" != sm750hdmidrm ]; then
		echo "$PROG: $BDF is bound to '$driver', not sm750hdmidrm" >&2
		return 1
	fi
	BASIS="sole framebuffer vtconsole on the host, with the sole sm750hdmidrm card (card0, $BDF); not by a hardcoded index"
	return 0
}

# card_inode - the dev:inode pair that identifies the card node even after a
# reload re-creates it under a different name.
card_inode() {
	stat -L -c '%d:%i' "$CARD" 2>/dev/null || true
}

# holders - print "pid:comm" per process whose fd table resolves to the card.
# Unreadable /proc entries are skipped silently: this runs as root, where the
# only such entries are kernel threads that cannot hold a card fd.
holders() {
	ino=$(card_inode)
	[ -n "$ino" ] || return 0
	for p in /proc/[0-9]*; do
		for f in "$p"/fd/*; do
			t=$(readlink "$f" 2>/dev/null) || continue
			case $t in
			*card0*)
				printf '%s:%s\n' "${p#/proc/}" "$(cat "$p/comm" 2>/dev/null || echo '?')"
				break
				;;
			esac
		done
	done
}

module_line() {
	if [ -r "$MODDIR/version" ]; then
		printf 'module:       version=%s srcversion=%s refcnt=%s\n' \
			"$(cat "$MODDIR/version" 2>/dev/null || echo '?')" \
			"$(cat "$MODDIR/srcversion" 2>/dev/null || echo '?')" \
			"$(cat "$MODDIR/refcnt" 2>/dev/null || echo '?')"
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
	else
		printf 'target:       unresolvable (see the message above)\n'
	fi
	module_line
	printf 'active tty:   %s\n' "$(cat "$TTYACTIVE" 2>/dev/null || echo '?')"
	printf 'card:         %s -> %s inode %s\n' "$CARD" \
		"$(readlink -f "$CARD" 2>/dev/null || echo '?')" "$(card_inode)"
	h=$(holders || true)
	if [ -z "$h" ]; then
		printf 'holders:      0 userspace processes hold the card\n'
	else
		printf 'holders:      %s\n' "$(printf '%s' "$h" | wc -l | tr -d ' ')"
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

unbound=0
# restore_console - put fbcon back if this run detached it and is failing. It
# ends with an explicit return so it cannot overwrite the exit status the EXIT
# trap is about to re-raise (the A49 gate lesson: a trap whose last command can
# fail silently replaces the real status).
restore_console() {
	[ "$unbound" -eq 1 ] || return 0
	if write_bind "$TARGET" 1; then
		unbound=0
		echo "$PROG: fbcon re-bound to $TARGET (bind=1)" >&2
	else
		echo "$PROG: FAILED to re-bind fbcon to $TARGET; run '$PROG on' and check $TARGET/bind" >&2
	fi
	return 0
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then restore_console; fi; exit $rc' EXIT

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

echo "$PROG: target $TARGET (basis: $BASIS)"
echo "$PROG: detaching fbcon; there will be no text console until the reload ends"
write_bind "$TARGET" 0 || {
	echo "$PROG: could not write 0 to $TARGET/bind" >&2
	exit 3
}
unbound=1
echo "$PROG: fbcon detached, bind=$(cat "$TARGET/bind")"

if ! "$MODPROBE" -r sm750hdmidrm; then
	restore_console
	unbound=0
	echo "$PROG: modprobe -r sm750hdmidrm failed; the console was restored and nothing changed" >&2
	exit 1
fi
echo "$PROG: module unloaded"

if ! "$MODPROBE" sm750hdmidrm; then
	echo "$PROG: modprobe sm750hdmidrm failed; the console is still detached" >&2
	exit 1
fi

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

write_bind "$TARGET" 1 || {
	echo "$PROG: module reloaded but fbcon could not be re-bound to $TARGET" >&2
	exit 3
}
unbound=0

printf 'reloaded:     version=%s srcversion=%s refcnt=%s\n' \
	"$(cat "$MODDIR/version")" \
	"$(cat "$MODDIR/srcversion" 2>/dev/null || echo '?')" \
	"$(cat "$MODDIR/refcnt" 2>/dev/null || echo '?')"
printf 'fbcon:        re-bound to %s, bind=%s\n' "$TARGET" "$(cat "$TARGET/bind")"
printf 'card:         %s -> driver %s\n' "$BDF" \
	"$(basename "$(readlink -f "$DRIVER_ATTR" 2>/dev/null || echo '?')")"
exit 0
