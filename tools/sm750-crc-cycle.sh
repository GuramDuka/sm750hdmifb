#!/bin/sh
# sm750-crc-cycle - reload the locally built sm750hdmidrm module and run the
# scanout CRC acceptance check as root, printing everything a transcript needs.
#
# Runs as root through a single NOPASSWD entry. Read-only with respect to the
# module source: it never builds the module, it only loads what is already
# built. It does build tests/scanout-pattern.c (a userspace helper) and gives
# the build directory back to its owner afterwards.
#
# Exit codes:
#   0  cycle completed and tests/check-scanout-crc.sh passed
#   1  environment problem (not root, no module object, insmod failed)
#   2  CRC debugfs interface missing after load
#   3  interface present, check did not pass (its own output says why)
#   4  check skipped (environment, see its SKIP line)
set -eu

PROG=sm750-crc-cycle
MOD=sm750hdmidrm
REPO=/home/coder/sm750hdmifb
KO=$REPO/src/sm750hdmidrm.ko
BDF=pci-0000:01:00.0
OWNER=coder
RELOAD=1
DIAG=0
DUMP=0
STREAM_SECONDS=20

usage() {
	echo "usage: $PROG [--no-reload] [--ko PATH] [--diag] [--stream-seconds N]" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
	--no-reload) RELOAD=0 ;;
	--ko) shift; KO=${1:-} ;;
	--diag) DIAG=1 ;;
	--dump) DUMP=1 ;;
	--stream-seconds) shift; STREAM_SECONDS=${1:-20} ;;
	-h|--help) usage ;;
	*) usage ;;
	esac
	shift
done

# Accepted for compatibility with the first version, which read crc/data
# itself. The check script owns the sampling now, so this value is unused.
: "$STREAM_SECONDS"

say() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root"

say "# $PROG $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "# kernel $(uname -r)"

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
	# modprobe -r also drops the auto-loaded dependencies, and insmod resolves
	# none of them, so the helper libraries are loaded back explicitly.
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

dri=/sys/kernel/debug/dri/$idx
crc=$dri/crtc-0/crc
i=0
while [ ! -d "$crc" ]; do
	i=$((i + 1))
	[ "$i" -le 40 ] || break
	sleep 0.25
done
if [ -d "$crc" ]; then
	say "  CRC interface ready ($(ls "$crc" | tr '\n' ' '))"
else
	say "  CRC interface absent: $crc"
	if [ "$DUMP" -eq 1 ] || [ "$DIAG" -eq 1 ]; then
		ls -lai "$dri/crtc-0" 2>&1 | sed 's/^/  /'
		exit 2
	fi
	fail "CRC debugfs interface missing: $crc"
fi

say "--- crc files"
for f in source control; do
	if [ -e "$crc/$f" ]; then
		say "  $f: $(head -c 120 "$crc/$f" 2>&1 | tr '\n' ' ')"
	else
		say "  $f: absent"
	fi
done
say "--- scanout readback header (before)"
head -n 8 "$dri/sm750_scanout" | sed 's/^/  /'

# A fresh load has no mode on CRTC-0 until the kernel console client programs
# one, and the CRC source needs recorded scanout geometry. Wait for it instead
# of racing the client.
i=0
while ! head -n 8 "$dri/sm750_scanout" 2>/dev/null | grep -q 'pitch [0-9]'; do
	i=$((i + 1))
	[ "$i" -le 80 ] || break
	sleep 0.25
done
if head -n 8 "$dri/sm750_scanout" | grep -q 'pitch [0-9]'; then
	say "--- scanout geometry recorded after $((i / 4)) s"
else
	say "--- WARNING: no scanout geometry after 20 s; the check will most likely skip"
fi

if [ "$DUMP" -eq 1 ]; then
	say "--- crtc-0 debugfs listing"
	ls -lai "$dri/crtc-0" 2>&1 | sed 's/^/  /'
	say "--- crc file contents"
	for f in source control; do
		[ -e "$crc/$f" ] || continue
		say "  $f: $(head -c 200 "$crc/$f" 2>&1 | tr '\n' ' ')"
	done
	say "  data (5s): $(timeout 5 head -n 3 "$crc/data" 2>&1 | tr '\n' ' ')"
fi

if [ "$DIAG" -eq 1 ]; then
	say "--- debugfs listing"
	ls -lai "$crc" 2>&1 | sed 's/^/  /'
	say "  dir inode: $(stat -c '%i %a %U %G' "$dri/crtc-0" 2>&1)"
	say "--- open/read trace of crc/data (5s)"
	timeout 5 strace -f -e trace=openat,read -s 48 /bin/cat "$crc/data" 2>&1 |
		grep -E 'crc/data|EIO|ENODEV|EBUSY' | sed 's/^/  /' || true
	say "--- debugfs mounts"
	grep -w debugfs /proc/self/mountinfo | sed 's/^/  /' || true
fi

say "--- tests/check-scanout-crc.sh (runs as root)"
chk_out=$(mktemp /tmp/sm750-crc-cycle.XXXXXX)
chk_rc=0
"$REPO/tests/check-scanout-crc.sh" >"$chk_out" 2>&1 || chk_rc=$?
sed 's/^/  /' "$chk_out"
rm -f "$chk_out"
# The check compiles a userspace helper into build/, do not leave it root-owned.
chown -R "$OWNER:$OWNER" "$REPO/build" 2>/dev/null || true

say "--- scanout readback header (after)"
head -n 8 "$dri/sm750_scanout" | sed 's/^/  /'
say "--- dmesg"
dmesg -T 2>/dev/null | grep -iE 'sm750|sii902|crc' | tail -n 15 | sed 's/^/  /' || true

case $chk_rc in
0)
	say "RESULT: scanout CRC check passed"
	exit 0
	;;
77)
	say "RESULT: scanout CRC check skipped (see its SKIP line)"
	exit 4
	;;
*)
	say "RESULT: scanout CRC check failed with exit $chk_rc"
	exit 3
	;;
esac
