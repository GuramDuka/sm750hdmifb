#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# T57 gate: the render node.
#
# kwin 6.7.5 refuses a DRM device that has no render node; the string
# "Skipping device %s without a render node" is in /usr/lib64/libkwin.so.
# The driver therefore sets DRIVER_RENDER (include/drm/drm_drv.h:78,
# "Driver supports dedicated render nodes") on the same driver_features line
# as DRIVER_MODESET. SM750 has no 3D engine: the node exposes dumb-buffer and
# PRIME/dma-buf primitives and the core ioctls marked DRM_RENDER_ALLOW
# (include/drm/drm_ioctl.h:121), and it is not a claim of GL capability.
#
# A render-only device would lose modesetting, so the gate rejects any line
# that sets DRIVER_RENDER without DRIVER_MODESET. It also pins the two
# driver_features lines and the version define, and it re-runs itself against
# three planted controls so it cannot pass by accident.
#
# The live half is opportunistic: the running module on this host predates
# this change, so when no sm750hdmidrm render node exists the live half prints
# a SKIP line and the gate still exits 0. It becomes a real check the moment a
# module built from this tree is loaded.
#
# Usage: tests/check-render-node.sh [--self-test] [repo dir]
#        tests/check-render-node.sh <tree>   static checks only, for the
#                                            planted controls
set -eu
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_rel=src/sm750_drm.c
builder_rel=build-package.sh

self_test=0
root=
for arg in "$@"; do
	case $arg in
	--self-test) self_test=1 ;;
	-*) echo "usage: $0 [--self-test] [repo dir]" >&2; exit 2 ;;
	*) root=$arg ;;
	esac
done
[ -n "$root" ] || root=$project_dir

assertions=0

pass() {
	assertions=$((assertions + 1))
	printf 'ok: %s\n' "$1"
}

fail() {
	printf 'render node: %s\n' "$1" >&2
	exit 1
}

# --- static: both driver_features lines carry DRIVER_RENDER ----------------
# Two drm_driver instances exist (TTM/VRAM and shmem shadow). Both must
# advertise the node, otherwise the registered device depends on which one
# bound.
check_features() {
	tree=$1
	source=$tree/$source_rel

	[ -f "$source" ] || fail "missing $source_rel under $tree"

	lines=$(grep -n '\.driver_features = ' "$source" | cut -d: -f1 || true)
	[ -n "$lines" ] || fail "$source_rel has no driver_features line"

	count=$(printf '%s\n' "$lines" | wc -l)
	count=$((count))
	[ "$count" -eq 2 ] ||
		fail "$source_rel has $count driver_features lines, expected 2"

	for n in $lines; do
		text=$(sed -n "${n}p" "$source")
		case $text in
		*DRIVER_RENDER*)
			pass "$source_rel:$n advertises DRIVER_RENDER" ;;
		*)
			fail "$source_rel:$n is a driver_features line without DRIVER_RENDER: the device it describes registers no render node"
			;;
		esac
	done
}

# --- static: never DRIVER_RENDER without DRIVER_MODESET --------------------
# A render-only device keeps /dev/dri/renderD* but loses card0, its connectors
# and its modesetting. Comment lines are not code and are skipped.
check_modeset_kept() {
	tree=$1
	source=$tree/$source_rel

	offenders=$(awk '
		/^[[:space:]]*(\*|\/\*|\/\/)/ { next }
		/DRIVER_RENDER/ && !/DRIVER_MODESET/ { printf "%d:%s\n", NR, $0 }
	' "$source" || true)
	[ -z "$offenders" ] ||
		fail "$source_rel sets DRIVER_RENDER without DRIVER_MODESET: $offenders"
	pass "$source_rel never sets DRIVER_RENDER without DRIVER_MODESET"
}

# --- static: the version define matches build-package.sh ------------------
# check-release-version.sh checks the same pair, but a bump that edits only
# one of them is the mistake this gate is most likely to meet.
check_version() {
	tree=$1
	source=$tree/$source_rel
	builder=$tree/$builder_rel

	[ -f "$builder" ] || fail "missing $builder_rel under $tree"

	module_version=$(sed -n 's/^#define SM750_DRM_VERSION "\([^"]*\)"$/\1/p' \
		"$source")
	[ -n "$module_version" ] ||
		fail "$source_rel has no SM750_DRM_VERSION define"
	package_version=$(sed -n 's/^readonly version=//p' "$builder")
	[ -n "$package_version" ] ||
		fail "$builder_rel has no 'readonly version=' line"
	[ "$module_version" = "$package_version" ] ||
		fail "$source_rel says SM750_DRM_VERSION \"$module_version\" but $builder_rel packages $package_version; the two disagree"
	pass "SM750_DRM_VERSION \"$module_version\" matches $builder_rel"
}

check_tree() {
	check_features "$1"
	check_modeset_kept "$1"
	check_version "$1"
}

# --- live: the node the loaded module registered, if any ------------------
check_live() {
	seen=0

	for node in /sys/class/drm/renderD*; do
		[ -e "$node" ] || continue
		driver=$(readlink -f "$node/device/driver" 2>/dev/null || true)
		[ -n "$driver" ] || continue
		[ "$(basename "$driver")" = sm750hdmidrm ] || continue
		seen=1
		name=$(basename "$node")
		dev=/dev/dri/$name
		[ -c "$dev" ] ||
			fail "$node exists but $dev is not a character device"
		[ -w "$dev" ] ||
			fail "$dev is not writable by user $(id -un); the render node is useless to an unprivileged compositor"
		pass "$dev exists and is writable by user $(id -un)"
	done

	if [ "$seen" -eq 0 ]; then
		printf 'SKIP: %s\n' "the running module does not advertise a render node yet: install 0.6.5"
	fi
}

check_tree "$root"

# An explicit tree is the internal invocation used by the planted controls.
if [ "$root" != "$project_dir" ]; then
	exit 0
fi

check_live

if [ "$self_test" -eq 0 ]; then
	printf 'Render node checks passed (%d assertions, 0 planted controls)\n' \
		"$assertions"
	exit 0
fi

# --- planted controls: each must be rejected, for the right reason --------
scratch=$(mktemp -d "${TMPDIR}/sm750-render-node.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

plant() {
	name=$1 want=$2
	tree=$scratch/$name
	mkdir -p "$tree/src"
	install -m 0644 "$project_dir/$source_rel" "$tree/$source_rel"
	install -m 0755 "$project_dir/$builder_rel" "$tree/$builder_rel"
	shift 2
	"$@" "$tree"
	if out=$("$0" "$tree" 2>&1); then
		fail "planted control '$name' was not rejected"
	fi
	case $out in
	*"$want"*) pass "planted control '$name' rejected: $want" ;;
	*) fail "planted control '$name' failed for the wrong reason: $out" ;;
	esac
}

# (a) DRIVER_RENDER dropped from the TTM/VRAM driver line, which is the first
# of the two: kwin would see a card without a render node again.
drop_render() {
	python3 - "$1/$source_rel" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='ascii').read()
old = "\t.driver_features = DRIVER_GEM | DRIVER_MODESET | DRIVER_ATOMIC | DRIVER_RENDER,\n"
new = "\t.driver_features = DRIVER_GEM | DRIVER_MODESET | DRIVER_ATOMIC,\n"
assert s.count(old) == 2, s.count(old)
i = s.index(old)
s = s[:i] + new + s[i + len(old):]
open(p, 'w', encoding='ascii', newline='').write(s)
PY
}

# (b) A synthetic DRIVER_RENDER on a line without DRIVER_MODESET: a
# render-only device, which loses card0 and every connector.
add_render_only() {
	python3 - "$1/$source_rel" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='ascii').read()
anchor = "#define SM750_DRM_MAX_WIDTH 2560\n"
assert s.count(anchor) == 1, s.count(anchor)
planted = "static unsigned long sm750_planted_render = DRIVER_RENDER;\n"
s = s.replace(anchor, planted + anchor, 1)
open(p, 'w', encoding='ascii', newline='').write(s)
PY
}

# (c) The package version moved and the module define did not.
drift_version() {
	python3 - "$1/$builder_rel" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='ascii').read()
pattern = r'^readonly version=(\S+)$'
found = re.findall(pattern, s, re.M)
assert len(found) == 1, found
s = re.sub(pattern, 'readonly version=9.9.9', s, count=1, flags=re.M)
open(p, 'w', encoding='ascii', newline='').write(s)
PY
}

plant render_dropped 'without DRIVER_RENDER' drop_render
plant render_only 'without DRIVER_MODESET' add_render_only
plant version_drift 'the two disagree' drift_version

printf 'Render node checks passed (%d assertions, 3 planted controls)\n' \
	"$assertions"
