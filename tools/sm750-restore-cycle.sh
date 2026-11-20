#!/bin/sh
# sm750-restore-cycle - stress the fbdev reconsole restore path as root.
#
# When the last userspace DRM client closes /dev/dri/cardN, DRM's lastclose
# restores the fbdev console mode: the driver disables and re-enables the pipe
# in one commit. That is the path that returned -ETIMEDOUT from the display
# transition wait before A32 (docs/evidence/runtime/20-fbdev-restore-timeout-rca.txt).
# This harness repeats it and looks for the fault census below, which is the
# same nine markers the hardware proof greps for. They go
# through pr_err_ratelimited/drm_err, so no dynamic debug is needed - dynamic
# debug is root-only on this host and off by default.
#
# Each attempt: tests/scanout-pattern puts a white frame on the CRTC, holds the
# master for the requested hold time and exits; closing the node triggers the
# restore. When modetest is available one mode change is appended, because a
# mode change exercises the same disable-then-enable pair.
#
# The harness never calls drmModeRmFB, never kills the console client and never
# removes the module between attempts: rmfb on a scanned-out buffer disables the
# CRTC, and a module reload would replace the state under test. It leaves the
# panel showing whatever the console client restores.
#
# Exit codes:
#   0  every attempt completed and none logged a restore failure
#   1  environment problem (not root, no module object, insmod failed, no card,
#      no debugfs, the drawing helper could not become DRM master)
#   2  scanout readback is unavailable, so the attempts cannot be confirmed
#   3  a failure line appeared (printed with its iteration number)
#
# Usage: sudo sm750-restore-cycle [--no-reload] [--ko PATH] [--iterations N]
#                                [--mode WxH] [--hold SECONDS]
set -eu

PROG=sm750-restore-cycle
MOD=sm750hdmidrm
OWNER=coder
# Resolve the checkout through the owner's passwd entry instead of embedding
# this host's home directory: this script ships in the source archive and
# tests/audit-release.sh rejects a literal local path in anything that ships.
owner_home=$(getent passwd "$OWNER" | cut -d: -f6 || true)
REPO=${SM750_REPO:-${owner_home:-}/sm750hdmifb}
KO=$REPO/src/sm750hdmidrm.ko
BDF=pci-0000:01:00.0
RELOAD=1
ITERATIONS=20
MODE=1024x768
HOLD=2

usage() {
	echo "usage: $PROG [--no-reload] [--ko PATH] [--iterations N] [--mode WxH] [--hold SECONDS]" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
	--no-reload) RELOAD=0 ;;
	--ko) shift; KO=${1:-} ;;
	--iterations) shift; ITERATIONS=${1:-} ;;
	--mode) shift; MODE=${1:-} ;;
	--hold) shift; HOLD=${1:-} ;;
	-h|--help) usage ;;
	*) usage ;;
	esac
	shift
done

case "$ITERATIONS" in
''|*[!0-9]*) usage ;;
esac
case "$HOLD" in
''|*[!0-9]*) usage ;;
esac
[ "$ITERATIONS" -ge 1 ] || usage

say() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root"

say "# $PROG $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "# kernel $(uname -r)  attempts $ITERATIONS  mode $MODE  hold ${HOLD}s"

if [ "$RELOAD" -eq 1 ]; then
	[ -f "$KO" ] || fail "module object not found: $KO"
	ko_vermagic=$(modinfo -F vermagic "$KO" 2>/dev/null | awk '{print $1}')
	say "--- module object"
	ls -l "$KO" | sed 's/^/  /'
	say "  srcversion $(modinfo -F srcversion "$KO" 2>/dev/null || echo unknown)"
	say "  vermagic ${ko_vermagic:-unknown} (running $(uname -r))"
	# Refuse before unloading anything: an object built for another kernel
	# would fail insmod and leave the card without a driver.
	if [ -n "$ko_vermagic" ] && [ "$ko_vermagic" != "$(uname -r)" ]; then
		fail "object is built for $ko_vermagic, not for $(uname -r); rebuild before running the cycle"
	fi
	say "--- reload"
	modprobe -r "$MOD" 2>/dev/null || true
	modprobe drm_vram_helper
	if ! insmod "$KO"; then
		modprobe "$MOD" 2>/dev/null || true
		fail "insmod failed; packaged module restored where possible"
	fi
	say "  loaded"
fi

say "--- running module"
say "  srcversion $(cat "/sys/module/$MOD/srcversion" 2>/dev/null || echo unknown)"
say "  version $(cat "/sys/module/$MOD/version" 2>/dev/null || echo unknown)"

# Resolve the debugfs index from the PCI path instead of assuming card0.
card_node="/dev/dri/by-path/$BDF-card"
[ -e "$card_node" ] || fail "no DRM node at $card_node"
card=$(readlink -f "$card_node")
idx=${card##*card}
say "--- card node"
say "  $card_node -> $card (debugfs dri/$idx)"

readback=/sys/kernel/debug/dri/$idx/sm750_scanout
[ -r "$readback" ] || fail "scanout readback is not readable: $readback"
i=0
while ! head -n 8 "$readback" 2>/dev/null | grep -q 'pitch [0-9]'; do
	i=$((i + 1))
	[ "$i" -le 80 ] || break
	sleep 0.25
done
head -n 8 "$readback" | grep -q 'pitch [0-9]' ||
	fail "no scanout geometry after 20 s; give the console client a mode first"
say "--- scanout readback header (before)"
head -n 8 "$readback" | sed 's/^/  /'

# Build the drawer the same way tests/check-scanout-crc.sh does, including the
# documented rootless libdrm tree (docs/ENVIRONMENT.md section 4).
if ! pkg-config --exists libdrm 2>/dev/null; then
	libdrm_dir=${SM750_LIBDRM_DIR:-/mega/tmp/sm750/t3/libdrm}
	if [ -d "$libdrm_dir/usr/lib64/pkgconfig" ]; then
		PKG_CONFIG_PATH=$libdrm_dir/usr/lib64/pkgconfig
		PKG_CONFIG_SYSROOT_DIR=$libdrm_dir
		LD_LIBRARY_PATH=$libdrm_dir/usr/lib64
		export PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR LD_LIBRARY_PATH
	fi
fi
pattern=$REPO/build/scanout-pattern
mkdir -p "$REPO/build" || fail "cannot create $REPO/build"
/usr/bin/gcc -O2 -Wall -Wextra -Werror $(pkg-config --cflags libdrm) \
	-o "$pattern" "$REPO/tests/scanout-pattern.c" \
	$(pkg-config --libs libdrm) 2>"$REPO/build/scanout-pattern.log" || {
	tail -n 5 "$REPO/build/scanout-pattern.log" >&2
	chown -R "$OWNER:$OWNER" "$REPO/build" 2>/dev/null || true
	fail "cannot build tests/scanout-pattern.c"
}
chown -R "$OWNER:$OWNER" "$REPO/build" 2>/dev/null || true

# Connector@CRTC for the extra mode change. Discovered, not assumed, so the
# harness does not go stale if the allocation changes; absent modetest is not
# an error - the restore trigger is the drawer exiting.
ids=
if command -v modetest >/dev/null 2>&1; then
	ids=$(modetest -M "$MOD" 2>/dev/null | awk '
		/^Connectors:/ { sec = "c"; next }
		/^CRTCs:/ { sec = "r"; next }
		/^Planes:/ { sec = "p"; next }
		sec == "c" && /^[0-9]+/ && !conn { conn = $1 }
		sec == "r" && /^[0-9]+/ && !crtc { crtc = $1 }
		END { if (conn && crtc) print conn "@" crtc }')
fi
if [ -n "$ids" ]; then
	say "--- mode change: modetest -M $MOD -s $ids:$MODE"
else
	say "--- mode change: skipped (modetest missing or no connector@CRTC)"
fi

hits=0
i=0
while [ "$i" -lt "$ITERATIONS" ]; do
	i=$((i + 1))
	before=$(dmesg 2>/dev/null | wc -l)
	if ! "$pattern" "$card" white "$HOLD" >"$REPO/build/restore-attempt.log" 2>&1; then
		rc=$?
		# 3 is the helper's own environment verdict (no DRM master).
		if [ "$rc" -eq 3 ]; then
			fail "attempt $i: could not become DRM master (another client owns the card)"
		fi
		say "attempt $i: drawer failed: $(tail -n 1 "$REPO/build/restore-attempt.log")"
		hits=$((hits + 1))
		continue
	fi
	if [ -n "$ids" ]; then
		modetest -M "$MOD" -s "$ids:$MODE" >/dev/null 2>&1 || true
	fi
	after=$(dmesg 2>/dev/null | wc -l)
	new=$(dmesg 2>/dev/null | tail -n +$((before + 1)))
	# Same nine-marker census as docs/evidence/runtime/22-restore-fix-hardware-proof.txt
	# (its line 129 grep); keep the two identical so the harness and the proof
	# cannot drift.
	bad=$(printf '%s\n' "$new" | \
		grep -E 'failed to enable HDMI mode|flip_done timed out|commit wait timed out|refcount_t: underflow|did not latch|panel did not acknowledge|enable-fail state|WARNING|BUG:' || true)
	if [ -n "$bad" ]; then
		hits=$((hits + 1))
		say "attempt $i: restore failure"
		printf '%s\n' "$bad" | sed 's/^/  /'
	else
		say "attempt $i: ok"
	fi
done

say "--- scanout readback header (after)"
head -n 8 "$readback" | sed 's/^/  /'
say "--- dmesg"
dmesg -T 2>/dev/null | grep -iE 'sm750|sii902' | tail -n 15 | sed 's/^/  /' || true

if [ "$hits" -ne 0 ]; then
	say "RESULT: $hits of $i attempts logged a restore failure"
	exit 3
fi

say "RESULT: $i attempts, no restore failure logged"
exit 0
