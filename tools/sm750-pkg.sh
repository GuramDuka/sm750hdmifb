#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# sm750-pkg - install, remove, inspect and reload the locally built
# sm750hdmifb packages.
#
# Installed as /usr/local/sbin/sm750-pkg (mode 0755 root:root). The allowlist
# grants that path once, with any arguments:
#
#   coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-pkg
#
# The grant matches the command plus ANY argument, which is exactly why this
# script validates its own argv: the interface is four fixed subcommands and
# nothing else, no caller-supplied string ever reaches dnf, and every package
# file is discovered under one fixed build tree. The blast radius is therefore
# "install or remove this driver's own RPMs", not "run dnf as root".
#
# Build tree: /mega/tmp/sm750/t6/rpmbuild/RPMS. SM750_PKG_ROOT overrides it for
# the self-test only; sudo strips the environment unless setenv is granted, and
# the allowlist grants no setenv, so the installed helper always uses the
# default path.
#
# GPG policy: dnf5 5.2.18 (the /usr/bin/dnf on this host) rejects the literal
# token "--nogpgcheck=false" with "unexpected value for the named argument", so
# the intent - signature checking NOT disabled - is expressed as
# --setopt=gpgcheck=True, which dnf5 parses. dnf keeps localpkg_gpgcheck off for
# a file argument, so an unsigned local build still installs.
#
# File trust: the RPMs are built by the unprivileged user who owns this tree,
# so they are owned by that user, not root. A candidate must resolve inside
# the build tree, be a regular file that is not a symlink, be owned by root or
# by the invoking user (SUDO_UID, else the current uid), carry no group or
# other write bit, and sit in a directory that is not a symlink and carries no
# group or other write bit either. Another local account therefore cannot plant
# an RPM for root to install; the invoking user can install their own build,
# which is the point of the grant.
#
# Every external command is echoed on a "running:" line before it executes, so
# a captured transcript shows exactly what ran; set -x stays off on purpose.
#
# Exit codes: 0 success, 1 failure or wrong privileges, 2 bad usage.
set -u

PROG=sm750-pkg
MODULE=sm750hdmidrm
DRIVER=sm750hdmifb
TOOLS=sm750hdmifb-tools
ROOT=${SM750_PKG_ROOT:-/mega/tmp/sm750/t6/rpmbuild/RPMS}
VERSION_FILE=/sys/module/$MODULE/version
# SM750_VTCLASS redirects the vtconsole tree for tests/check-sm750-pkg.sh only;
# sudo strips the environment unless setenv is granted, and the allowlist
# grants no setenv.
VTCLASS=${SM750_VTCLASS:-/sys/class/vtconsole}

usage() {
	cat >&2 <<'EOF'
usage: sm750-pkg install | remove | status | reload

  install  install the newest built driver RPM and the newest built tools RPM
           from /mega/tmp/sm750/t6/rpmbuild/RPMS in one dnf transaction, then
           print dkms status, the loaded module version and its lsmod line,
           and fail when the loaded module does not report the installed
           version. Both RPMs must carry the same version and release, be
           regular files that resolve inside the build tree, be owned by root
           or by the invoking user, and carry no group or other write bit;
           their containing directory must not be a symlink and must carry no
           group or other write bit either.
  remove   remove sm750hdmifb-tools first, then sm750hdmifb, then print dkms
           status. A package that is not installed is skipped.
  status   read-only: dkms status, the loaded module version, its lsmod line,
           the SM750 PCI device from sysfs, and the newest built RPM pair with
           the version that install would use. Runs unprivileged.
  reload [--force]
           unload and load sm750hdmidrm, then print the loaded version.
           Refuses while the framebuffer vtconsole is still bound: a hot
           reload in that state wedged the module in Unloading with refcount
           -1 (A65). --force skips that refusal and accepts the risk.

install, remove and reload need root.
Exit codes: 0 ok, 1 failure or wrong privileges, 2 bad usage.
EOF
	exit 2
}

say() { printf '%s\n' "$*"; }
fail() {
	printf '%s: %s\n' "$PROG" "$*" >&2
	exit 1
}

# echo_cmd CMD... - print the "running:" line for a command run separately.
echo_cmd() {
	printf 'running: %s\n' "$*"
}

# run CMD... - echo the command, then run it.
run() {
	echo_cmd "$@"
	"$@"
}

need_root() {
	if [ "$(id -u)" -ne 0 ]; then
		printf '%s: %s needs root: sudo %s %s\n' \
			"$PROG" "$1" "$PROG" "$1" >&2
		exit 1
	fi
}

# caller_uid - the uid, besides root, allowed to own a candidate RPM: the user
# sudo reports in SUDO_UID, or the current user when the helper runs without
# sudo. The RPMs are built by the unprivileged owner of this tree, so a
# root-only rule would refuse every normal build.
caller_uid() {
	_cu=${SUDO_UID:-}
	case $_cu in
	'' | *[!0-9]*) _cu=$(id -u) ;;
	esac
	printf '%s\n' "$_cu"
}

# --- build-tree selection ---------------------------------------------------

valid_version() {
	printf '%s\n' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)*$'
}

# Numeric release, optionally with dotted lowercase suffixes: "1", "1.2" and
# the dist-suffixed "1.fc43" pass; a slash, dash, colon, space or shell
# metacharacter does not.
valid_release() {
	printf '%s\n' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)*(\.[a-z][a-z0-9_]*)*$'
}

valid_arch() {
	printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+$'
}

# ver_gt A B - true when dotted-numeric A is greater than B.
ver_gt() {
	_a=$1
	_b=$2
	while [ -n "$_a" ] || [ -n "$_b" ]; do
		_x=${_a%%.*}
		_y=${_b%%.*}
		if [ "$_x" = "$_a" ]; then _a=; else _a=${_a#*.}; fi
		if [ "$_y" = "$_b" ]; then _b=; else _b=${_b#*.}; fi
		_x=${_x:-0}
		_y=${_y:-0}
		if [ "$_x" -gt "$_y" ]; then return 0; fi
		if [ "$_x" -lt "$_y" ]; then return 1; fi
	done
	return 1
}

# scan_newest PKG - set NEW_VER, NEW_REL, NEW_FILE to the newest RPM for PKG
# under $ROOT, across every immediate subdirectory (noarch, x86_64, ...).
# Refuses to keep looking past a file it cannot trust: fail closed.
scan_newest() {
	pkg=$1
	NEW_VER=
	NEW_REL=
	NEW_FILE=
	for d in "$ROOT"/*; do
		[ -d "$d" ] || continue
		if [ -L "$d" ]; then
			PAIR_ERR="refusing $d: it is a symlink, not a build directory"
			return 1
		fi
		for f in "$d/$pkg"-*.rpm; do
			if [ -L "$f" ]; then
				PAIR_ERR="refusing $f: it is a symlink"
				return 1
			fi
			[ -f "$f" ] || continue
			base=${f##*/}
			base=${base%.rpm}
			rest=${base#"$pkg"-}
			# The driver glob also matches sm750hdmifb-tools-*.rpm: a real
			# tag starts with a digit, so anything else belongs to the
			# other package.
			case $rest in
			[0-9]*) ;;
			*) continue ;;
			esac
			case $rest in
			*.*.*) ;;
			*)
				PAIR_ERR="refusing $f: name is not <name>-<version>-<release>.<arch>.rpm"
				return 1
				;;
			esac
			arch=${rest##*.}
			tag=${rest%.*}
			case $tag in
			*-*) ;;
			*)
				PAIR_ERR="refusing $f: no release token"
				return 1
				;;
			esac
			rel=${tag##*-}
			ver=${tag%-*}
			if ! valid_version "$ver"; then
				PAIR_ERR="refusing $f: version '$ver' is not dotted numeric"
				return 1
			fi
			if ! valid_release "$rel"; then
				PAIR_ERR="refusing $f: release '$rel' is not a numeric release with an optional dotted lowercase suffix (1, 1.fc43)"
				return 1
			fi
			if ! valid_arch "$arch"; then
				PAIR_ERR="refusing $f: architecture '$arch' is not alphanumeric"
				return 1
			fi
			if [ -z "$NEW_FILE" ] || ver_gt "$ver" "$NEW_VER" ||
				{ [ "$ver" = "$NEW_VER" ] && [ "$f" -nt "$NEW_FILE" ]; }; then
				NEW_VER=$ver
				NEW_REL=$rel
				NEW_FILE=$f
			fi
		done
	done
	return 0
}

# check_safe FILE - the file must be a regular non-symlink that resolves inside
# $resolved_root, must not be writable by group or others, must sit in a
# directory that is neither a symlink nor group/other-writable, and must be
# owned by root or by the invoking user. The repeated symlink and regular-file
# tests close the window between selection and this check; the ownership rule
# lets the builder install their own output while refusing another local
# account's files.
check_safe() {
	_f=$1
	if [ -L "$_f" ]; then
		PAIR_ERR="refusing $_f: it is a symlink"
		return 1
	fi
	_res=$(realpath -e -- "$_f" 2>/dev/null) || _res=
	if [ -z "$_res" ]; then
		PAIR_ERR="refusing $_f: it does not resolve"
		return 1
	fi
	case $_res in
	"$resolved_root"/*) ;;
	*)
		PAIR_ERR="refusing $_f: it resolves to $_res, outside $resolved_root"
		return 1
		;;
	esac
	if [ ! -f "$_res" ]; then
		PAIR_ERR="refusing $_f: not a regular file"
		return 1
	fi

	_d=$(dirname -- "$_f")
	if [ -L "$_d" ]; then
		PAIR_ERR="refusing $_f: containing directory $_d is a symlink"
		return 1
	fi
	_dmode=$(stat -c '%a' -- "$_d" 2>/dev/null) || _dmode=
	if [ -z "$_dmode" ]; then
		PAIR_ERR="refusing $_f: cannot stat containing directory $_d"
		return 1
	fi
	if [ $((0$_dmode & 0022)) -ne 0 ]; then
		PAIR_ERR="refusing $_f: containing directory $_d is writable by group or others (mode $_dmode)"
		return 1
	fi

	_fmode=$(stat -c '%a' -- "$_f" 2>/dev/null) || _fmode=
	if [ -z "$_fmode" ]; then
		PAIR_ERR="refusing $_f: cannot stat its mode"
		return 1
	fi
	if [ $((0$_fmode & 0022)) -ne 0 ]; then
		PAIR_ERR="refusing $_f: mode $_fmode is writable by group or others"
		return 1
	fi

	_uid=$(stat -c '%u' -- "$_f" 2>/dev/null) || _uid=
	if [ -z "$_uid" ]; then
		PAIR_ERR="refusing $_f: cannot stat its owner"
		return 1
	fi
	_caller=$(caller_uid)
	if [ "$_uid" != 0 ] && [ "$_uid" != "$_caller" ]; then
		PAIR_ERR="refusing $_f: owned by uid $_uid, not root or the invoking user (uid $_caller)"
		return 1
	fi
	return 0
}

# find_pair - set DRV_RPM, TOOLS_RPM, PAIR_VER, PAIR_REL, or PAIR_ERR on
# refusal. PAIR_VER stays set when only a safety check failed, so status can
# still show which pair install would attempt.
find_pair() {
	PAIR_ERR=
	PAIR_VER=
	PAIR_REL=
	DRV_RPM=
	TOOLS_RPM=
	if [ ! -d "$ROOT" ]; then
		PAIR_ERR="build tree $ROOT is missing"
		return 1
	fi
	resolved_root=$(realpath -e -- "$ROOT" 2>/dev/null) || resolved_root=$ROOT

	scan_newest "$DRIVER" || return 1
	if [ -z "$NEW_FILE" ]; then
		PAIR_ERR="no $DRIVER RPM under $ROOT"
		return 1
	fi
	drv_ver=$NEW_VER
	drv_rel=$NEW_REL
	drv_file=$NEW_FILE

	scan_newest "$TOOLS" || return 1
	if [ -z "$NEW_FILE" ]; then
		PAIR_ERR="selected $DRIVER $drv_ver-$drv_rel ($drv_file), but no $TOOLS RPM is present under $ROOT; both packages come from one build run: rpmbuild -ba --define \"_topdir ${ROOT%/RPMS}\" packaging/sm750hdmifb.spec packaging/sm750hdmifb-tools.spec"
		return 1
	fi
	tools_ver=$NEW_VER
	tools_rel=$NEW_REL
	tools_file=$NEW_FILE

	if [ "$drv_ver" != "$tools_ver" ]; then
		PAIR_ERR="version mismatch: $DRIVER $drv_ver-$drv_rel vs $TOOLS $tools_ver-$tools_rel"
		return 1
	fi
	if [ "$drv_rel" != "$tools_rel" ]; then
		PAIR_ERR="release mismatch: $DRIVER $drv_ver-$drv_rel vs $TOOLS $tools_ver-$tools_rel"
		return 1
	fi

	DRV_RPM=$drv_file
	TOOLS_RPM=$tools_file
	PAIR_VER=$drv_ver
	PAIR_REL=$drv_rel

	check_safe "$drv_file" || return 1
	check_safe "$tools_file" || return 1
	return 0
}

# --- status fragments -------------------------------------------------------

print_module_version() {
	if [ -r "$VERSION_FILE" ]; then
		echo_cmd cat "$VERSION_FILE"
		cat "$VERSION_FILE"
	else
		say "$VERSION_FILE is not readable (module not loaded)"
	fi
}

print_lsmod_line() {
	printf 'running: lsmod | grep -E %s\n' "^$MODULE "
	if ! lsmod 2>/dev/null | grep -E "^$MODULE "; then
		say "(no $MODULE line in lsmod)"
	fi
}

print_pci_device() {
	_found=0
	for _dev in /sys/bus/pci/devices/*; do
		[ -r "$_dev/vendor" ] || continue
		_vendor=$(cat "$_dev/vendor" 2>/dev/null) || continue
		_device=$(cat "$_dev/device" 2>/dev/null) || continue
		[ "$_vendor" = "0x126f" ] || continue
		[ "$_device" = "0x0750" ] || continue
		_found=1
		_driver=none
		if [ -L "$_dev/driver" ]; then
			_driver=$(basename "$(readlink -f "$_dev/driver")")
		fi
		say "${_dev##*/}: vendor $_vendor device $_device driver $_driver"
	done
	[ "$_found" -eq 1 ] || say "no 126f:0750 device in /sys/bus/pci/devices"
}

print_pair() {
	find_pair || true
	if [ -n "$PAIR_VER" ]; then
		say "newest pair: $DRIVER $PAIR_VER-$PAIR_REL $DRV_RPM"
		say "newest pair: $TOOLS $PAIR_VER-$PAIR_REL $TOOLS_RPM"
	fi
	if [ -n "$PAIR_ERR" ]; then
		say "install would refuse: $PAIR_ERR"
	else
		printf 'install would run: dnf install -y --setopt=gpgcheck=True %s %s\n' \
			"$DRV_RPM" "$TOOLS_RPM"
	fi
}

# --- subcommands ------------------------------------------------------------

cmd_install() {
	need_root install
	command -v dnf >/dev/null 2>&1 || fail "dnf is not installed"
	find_pair || fail "$PAIR_ERR"
	say "pair: $DRIVER $PAIR_VER-$PAIR_REL $DRV_RPM"
	say "pair: $TOOLS $PAIR_VER-$PAIR_REL $TOOLS_RPM"
	run dnf install -y --setopt=gpgcheck=True "$DRV_RPM" "$TOOLS_RPM" ||
		fail "dnf install failed"

	say "== installed packages"
	echo_cmd rpm -q "$DRIVER" "$TOOLS"
	rpm -q "$DRIVER" "$TOOLS" || true
	say "== dkms status"
	echo_cmd dkms status
	dkms status || say "dkms status exited $?"
	say "== loaded module"
	print_module_version
	print_lsmod_line

	_loaded=
	if [ -r "$VERSION_FILE" ]; then
		_loaded=$(cat "$VERSION_FILE")
	fi
	if [ -z "$_loaded" ]; then
		fail "module $MODULE is not loaded ($VERSION_FILE missing); run: sudo $PROG reload"
	fi
	if [ "$_loaded" != "$PAIR_VER" ]; then
		fail "loaded module reports '$_loaded', installed RPM is '$PAIR_VER'; run: sudo $PROG reload"
	fi
	say "$PROG: $DRIVER and $TOOLS $PAIR_VER-$PAIR_REL installed, loaded module reports $_loaded"
}

cmd_remove() {
	need_root remove
	command -v rpm >/dev/null 2>&1 || fail "rpm is not installed"
	_present=0
	if rpm -q "$TOOLS" >/dev/null 2>&1; then
		_present=1
	fi
	_drv_present=0
	if rpm -q "$DRIVER" >/dev/null 2>&1; then
		_drv_present=1
	fi
	if [ "$_present" -eq 1 ] && [ "$_drv_present" -eq 1 ]; then
		run dnf remove -y "$TOOLS" "$DRIVER" || fail "dnf remove failed"
	elif [ "$_present" -eq 1 ]; then
		run dnf remove -y "$TOOLS" || fail "dnf remove failed"
	elif [ "$_drv_present" -eq 1 ]; then
		run dnf remove -y "$DRIVER" || fail "dnf remove failed"
	else
		say "neither $TOOLS nor $DRIVER is installed"
	fi
	say "== dkms status"
	echo_cmd dkms status
	dkms status || say "dkms status exited $?"
}

cmd_status() {
	say "== dkms status"
	if command -v dkms >/dev/null 2>&1; then
		echo_cmd dkms status
		dkms status || say "dkms status exited $?"
	else
		say "dkms is not installed"
	fi
	say "== loaded module"
	print_module_version
	print_lsmod_line
	say "== pci device"
	print_pci_device
	say "== local build tree"
	print_pair
}

# fbcon_bound - true when a vtconsole is bound and is the framebuffer one, the
# state in which the panel is driven through the SM750 framebuffer console.
fbcon_bound() {
	for _vc in "$VTCLASS"/vtcon*; do
		[ -e "$_vc" ] || continue
		[ "$(cat "$_vc/bind" 2>/dev/null)" = 1 ] || continue
		case $(cat "$_vc/name" 2>/dev/null) in
		*"(M) frame buffer device"*) return 0 ;;
		esac
	done
	return 1
}

# reload_guard - refuse the unload while the framebuffer vtconsole is bound.
# A hot reload in that state wedged the module in Unloading on 2026-11-26 (A65)
# and no stack could be captured, so the next reproduction must not repeat it.
reload_guard() {
	if ! fbcon_bound; then
		return 0
	fi
	if [ "$force" -eq 1 ]; then
		say "$PROG: unloading anyway (--force)"
		return 0
	fi
	fail "refusing to unload: the framebuffer vtconsole is still bound (A65: a hot reload in that state wedged the module in Unloading on 2026-11-26). Run 'sm750-vt off' first, or pass --force if you accept the risk."
}

cmd_reload() {
	force=0
	if [ "${1:-}" = "--force" ]; then
		force=1
		shift
	fi
	[ $# -eq 0 ] || usage
	need_root reload
	reload_guard
	run modprobe -r "$MODULE" || say "$MODULE was not loaded"
	run modprobe "$MODULE" || fail "modprobe $MODULE failed"
	say "== loaded module"
	print_module_version
}

# --- dispatch ---------------------------------------------------------------

[ $# -ge 1 ] || usage
action=$1
shift
case $action in
install | remove | status | reload) ;;
*) usage ;;
esac
case $action in
reload)
	[ $# -le 1 ] || usage
	[ $# -eq 0 ] || [ "$1" = "--force" ] || usage
	;;
*)
	[ $# -eq 0 ] || usage
	;;
esac
case $action in
install) cmd_install ;;
remove) cmd_remove ;;
status) cmd_status ;;
reload) cmd_reload "$@" ;;
esac