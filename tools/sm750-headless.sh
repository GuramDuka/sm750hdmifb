#!/bin/sh
# sm750-headless - exercise the SM750 output path with a real compositor,
# without touching seat0, any VT, or any other DRM card.
#
# Runs as root through one NOPASSWD entry. Why root is required: taking DRM
# master is DRM_ROOT_ONLY in the kernel, and every compositor has to be master
# of the card it drives. The card is still not handed to logind: the compositor
# is started with LIBSEAT_BACKEND=noop, which opens the device directly and
# never performs a VT switch, so the session on seat0 is not disturbed.
#
# Guard rails, all hard failures rather than warnings:
#   - refuses to run as anything but root;
#   - the card is fixed to the SM750 (PCI 0000:01:00.0) and verified to be
#     bound to sm750hdmidrm; no other /dev/dri node is opened;
#   - the only programs it can start are the ones named below, with a fixed
#     argument list; there is no passthrough argument, so this entry cannot be
#     turned into a root shell;
#   - a fixed run time with a hard kill, and master is always dropped again;
#   - the card's compositors run inside a private mount namespace with a tmpfs
#     over /dev/input, so weston's DRM backend and cage's wlroots backend
#     physically cannot open or grab the owner's keyboard or mouse. There is no
#     compositor option that does this: weston's --no-input exists only for its
#     x11 backend and cage has no input option at all. See DEFECTS.md A49 for
#     the 2026-11-26 incident this guard closes;
#   - the x11 arm starts a root Xorg, because opening a virtual console needs
#     root on this host and the logind seat belongs to the owner. It generates
#     its own server config with AutoAddDevices off and no InputDevice
#     section, so the server never opens /dev/input at all, and runs with
#     -sharevts -novtswitch so no VT is taken or switched.
#
# Exit codes:
#   0  the requested run completed and every expectation held
#   1  environment problem (not root, wrong driver, missing program)
#   2  usage error
#   3  the compositor started but a measured expectation failed
#   4  nothing could take master on the card
set -eu

PROG=sm750-headless
BDF=0000:01:00.0
CARD=/dev/dri/by-path/pci-0000:01:00.0-card
# wlroots splits WLR_DRM_DEVICES on ':' before opening the paths, so the
# by-path symlink cannot be used there (cage would try to open
# "/dev/dri/by-path/pci-0000", "01" and "00.0-card" and find no GPU).
# The by-path link is still the right handle for everything else: it names
# the card by PCI address instead of by the order the driver probed in.
CARD_NODE=$(readlink -f "$CARD" 2>/dev/null || true)
UNSHARE=/usr/bin/unshare
MOUNT=/usr/bin/mount
DRIVER_ATTR=/sys/bus/pci/devices/$BDF/driver
DEV_ATTRS=/sys/bus/pci/devices/$BDF
CONNECTOR=/sys/class/drm/card0-HDMI-A-1
BASE=${SM750_HEADLESS_DIR:-/mega/tmp/sm750/headless}

usage() {
	echo "usage: $PROG [probe | diagnose | weston [SECONDS] | cage [SECONDS] | kmscube [SECONDS] | x11 [SECONDS]]" >&2
	exit 2
}

[ "$(id -u)" -eq 0 ] || { echo "$PROG: must run as root" >&2; exit 1; }

mode=${1:-probe}
case $mode in
probe|diagnose|weston|cage|kmscube|x11) ;;
*) usage ;;
esac
seconds=${2:-20}
case $seconds in
''|*[!0-9]*) usage ;;
esac
[ "$seconds" -ge 1 ] && [ "$seconds" -le 600 ] || usage
[ $# -le 2 ] || usage

# The card must exist and be the driver's card, not merely a readable node.
[ -e "$CARD" ] || { echo "$PROG: $CARD is missing" >&2; exit 1; }
[ -n "$CARD_NODE" ] && [ -e "$CARD_NODE" ] || { echo "$PROG: $CARD does not resolve to a device node" >&2; exit 1; }
driver=$(basename "$(readlink -f "$DRIVER_ATTR")")
[ "$driver" = sm750hdmidrm ] || {
	echo "$PROG: $BDF is bound to '$driver', not sm750hdmidrm" >&2
	exit 1
}

stamp=$(date -u +%Y%m%dT%H%M%SZ)
out=$BASE/$stamp-$mode
mkdir -p "$out"
runtime=$out/runtime
mkdir -p "$runtime"
chmod 700 "$runtime"

# Input isolation. weston 14.0.2 documents --no-input under "Options for x11:"
# only; its DRM backend options are --seat, --drm-device, --additional-devices,
# --use-pixman, --current-mode and --continue-without-input, and
# --continue-without-input only means "start even with zero input devices", so
# the DRM backend still opens every /dev/input/event* it finds. cage 0.2.x has
# no input option at all. The only lever left is the device nodes themselves:
# start the compositor in a private mount namespace and put an empty tmpfs over
# /dev/input before the exec. The namespace dies with the compositor, so the
# host /dev/input is never modified.
case $mode in
weston|cage)
	[ -x "$UNSHARE" ] || {
		echo "$PROG: $UNSHARE is missing; refusing to start a compositor without input isolation" >&2
		exit 1
	}
	[ -x "$MOUNT" ] || {
		echo "$PROG: $MOUNT is missing; refusing to start a compositor without input isolation" >&2
		exit 1
	}
	isolation="input devices are isolated in a private mount namespace (empty /dev/input)"
	printf '%s: %s\n' "$PROG" "$isolation"
	{
		printf '%s\n' "$isolation"
		printf '%-10s %s --mount --propagation private\n' namespace "$UNSHARE"
		printf '%-10s %s -t tmpfs -o size=1M,mode=0755 tmpfs /dev/input\n' mount "$MOUNT"
		printf '%-10s %s\n' mode "$mode"
		printf '%-10s %s\n' seconds "$seconds"
	} >"$out/00-plan.txt"
	;;
x11)
	# A root Xorg needs no mount-namespace trick: with AutoAddDevices off and
	# no InputDevice section it never opens /dev/input, which is the same
	# guarantee by a different mechanism (see the A49 bullet above).
	# The config is generated per run rather than shipped as a second file, so
	# the helper stays one installable unit. It also has to live next to the
	# server's cwd: -config refuses an absolute path once the server runs with
	# elevated privileges ("With elevated privileges -config must specify a
	# relative path without any ".." elements").
	cat >"$out/sm750-x11.conf" <<EOF
# Generated by $PROG for the run in $out. Not installed anywhere.
Section "ServerFlags"
	Option "AutoAddDevices" "false"
	Option "AutoAddGPU" "false"
	Option "DontVTSwitch" "true"
	Option "DontZap" "true"
EndSection

Section "Device"
	Identifier "SM750 HDMI"
	Driver "modesetting"
	Option "kmsdev" "$CARD_NODE"
	Option "AccelMethod" "none"
	Option "ShadowFB" "true"
	# Card selection is not done here: the modesetting driver ignores
	# PrimaryGPU in a Device section and logs
	# "(WW) modeset(0): Option "PrimaryGPU" is not used". The shipped
	# OutputClass fragment 20-sm750hdmidrm.conf selects card0 as PrimaryGPU.
EndSection

Section "Screen"
	Identifier "SM750 screen"
	Device "SM750 HDMI"
EndSection

Section "ServerLayout"
	Identifier "SM750 layout"
	Screen "SM750 screen"
EndSection
EOF
	{
		printf '%s\n' "no input devices are configured (AutoAddDevices off, no InputDevice section)"
		printf '%-10s %s :1 -config sm750-x11.conf -sharevts -novtswitch -noreset -ac -nolisten tcp\n' xorg /usr/libexec/Xorg
		printf '%-10s %s\n' config "$out/sm750-x11.conf"
		printf '%-10s %s\n' mode "$mode"
		printf '%-10s %s\n' seconds "$seconds"
		printf '%s\n' "a Plasma session on :1 must start with these variables unset, or kwin_x11 dies at once:"
		printf '%-10s %s\n' unset "KWIN_DRM_DEVICES KWIN_RENDER_NODES __GLX_VENDOR_LIBRARY_NAME KWIN_DISABLE_VULKAN KWIN_COMPOSE"
		printf '%s\n' "a leaked KWIN_DRM_DEVICES or __GLX_VENDOR_LIBRARY_NAME=nvidia cost four crashes before kwin stayed up"
	} >"$out/00-plan.txt"
	;;
esac


snapshot() {
	label=$1
	{
		echo "# $label $(date -u +%Y-%m-%dT%H:%M:%SZ)"
		for f in vram_total_bytes vram_used_bytes active_mode \
			active_mode_refresh_hz active_mode_pixel_clock_khz hpd rxsense \
			link_state active_crtc vblank_count crc_supported; do
			p=$DEV_ATTRS/$f
			if [ -r "$p" ]; then
				printf '%-32s %s\n' "$f" "$(cat "$p")"
			else
				printf '%-32s %s\n' "$f" '<absent>'
			fi
		done
		printf '%-32s %s\n' connector-status "$(cat "$CONNECTOR/status" 2>/dev/null || echo '<absent>')"
		printf '%-32s %s\n' connector-enabled "$(cat "$CONNECTOR/enabled" 2>/dev/null || echo '<absent>')"
		if [ -r "$CONNECTOR/modes" ]; then
			printf '%-32s %s\n' connector-modes "$(head -1 "$CONNECTOR/modes")"
		fi
	} >"$out/$label.txt"
	cp "$out/$label.txt" "$out/$label.before.txt" 2>/dev/null || true
}

snapshot 01-before

vblank_before=$(cat "$DEV_ATTRS/vblank_count" 2>/dev/null || echo 0)

# Master probe: the ioctl is DRM_ROOT_ONLY, so this only works as root.
probe_master() {
	python3 - "$CARD" <<'PY' 2>&1
import fcntl, os, sys
DRM_IOCTL_SET_MASTER = 0x641E
DRM_IOCTL_DROP_MASTER = 0x641F
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CLOEXEC)
try:
    fcntl.ioctl(fd, DRM_IOCTL_SET_MASTER, 0)
except OSError as e:
    print("master: FAILED (%s)" % e.strerror)
    os.close(fd)
    sys.exit(1)
print("master: acquired")
fcntl.ioctl(fd, DRM_IOCTL_DROP_MASTER, 0)
print("master: dropped")
os.close(fd)
PY
}

if [ "$mode" != diagnose ]; then
	if ! probe_master >"$out/02-master.txt" 2>&1; then
		cat "$out/02-master.txt" >&2
		echo "$PROG: another process holds DRM master on the SM750; refusing to fight for it" >&2
		exit 4
	fi
	cat "$out/02-master.txt"
fi

[ "$mode" = probe ] && {
	snapshot 03-after
	echo "$PROG: probe complete, log in $out"
	exit 0
}

case $mode in
weston) prog=/usr/bin/weston ;;
cage) prog=/usr/bin/cage ;;
kmscube) prog=/usr/bin/kmscube ;;
# Xorg.wrap and the /usr/bin/Xorg wrapper are skipped: both exist to be
# setuid, and nothing on this host is setuid, so the real server binary is
# exec'd directly by the root helper.
x11) prog=/usr/libexec/Xorg ;;
*) prog= ;;
esac
if [ "$mode" = diagnose ]; then
	# Enumerate userspace holders of the card over the whole fd table
	# (running as root, this sees every process).  The kernel fbdev
	# client never appears there: an empty table together with the
	# EBUSY from SET_MASTER means a kernel-internal client master.
	ino=$(stat -c %i "$CARD")
	{
		echo "# fd-table holders of the card inode $ino"
		for p in /proc/[0-9]*; do
			for f in "$p"/fd/*; do
				t=$(readlink "$f" 2>/dev/null) || continue
				case $t in *card0*)
					echo "holder pid=${p#/proc/} fd=${f##*/} -> $t comm=$(cat "$p/comm" 2>/dev/null) cmd=$(tr '\0' ' ' <"$p/cmdline" 2>/dev/null | cut -c1-90)"
					;;
				esac
			done
		done
		echo "# module refcount: $(awk '/^sm750hdmidrm /{print $3}' /proc/modules 2>/dev/null || echo '?')"
		echo "# fbcon bind: $(cat /sys/class/vtconsole/vtcon1/bind 2>/dev/null || echo '?')"
	} >"$out/04-holders.txt" 2>&1
	cat "$out/04-holders.txt"
	snapshot 05-after
	echo "$PROG: diagnose complete, log in $out"
	exit 0
fi
[ -n "$prog" ] || { echo "$PROG: internal error, no program for mode $mode" >&2; exit 1; }
[ -x "$prog" ] || { echo "$PROG: $prog is not installed" >&2; exit 1; }

export XDG_RUNTIME_DIR=$runtime
export LIBGL_ALWAYS_SOFTWARE=1
# libseat 0.9.3 offers exactly three backends: logind, seatd and noop.
# There is no "builtin" backend and no seat for coder, so use noop: it
# opens the device directly and never touches seat0 or any VT.
export LIBSEAT_BACKEND=noop
export WLR_RENDERER=pixman
export WLR_DRM_DEVICES=$CARD_NODE
# wlroots variable only: cage is wlroots-based and honours it, weston does not
# read it at all (its DRM backend opens libinput directly). It is kept for cage
# as a second, cheap guard, but the private mount namespace below is the one
# that actually binds both compositors.
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_BACKENDS=drm
export KWIN_COMPOSE=Q

pid=
cleanup() {
	if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
		kill -TERM "$pid" 2>/dev/null || true
		sleep 2
		kill -KILL "$pid" 2>/dev/null || true
	fi
}
trap cleanup EXIT INT TERM

# isolate CMD... - exec CMD in a private mount namespace whose /dev/input is an
# empty tmpfs. The intermediate sh is replaced by CMD, so the pid stays the
# compositor's and the EXIT trap above still reaches it. --propagation private
# is required: /dev on this host is a shared mount, so a mount made in a
# namespace that kept shared propagation would propagate back to the host.
isolate() {
	exec "$UNSHARE" --mount --propagation private /bin/sh -c '
		"$1" -t tmpfs -o size=1M,mode=0755 tmpfs /dev/input || {
			echo "sm750-headless: cannot seal /dev/input in the private namespace" >&2
			exit 1
		}
		shift
		exec "$@"
	' sm750-headless "$MOUNT" "$@"
}

(
	case $mode in
	weston)
		isolate "$prog" --backend=drm --drm-device=card0 --renderer=pixman \
			--shell=kiosk-shell.so --continue-without-input --idle-time=0 \
			--log="$out/weston.log"
		;;
	cage)
		# -d only: -s would allow VT switching, and seat0 is the owner's.
		isolate "$prog" -d -- /usr/bin/weston-terminal
		;;
	kmscube)
		# -c is the frame count; -n is a connector id, so it is left out
		# and kmscube picks the first connected connector itself.
		exec "$prog" -A -D "$CARD" -c 300
		;;
	x11)
		# Display :1, a fixed argument list, no passthrough. -ac is required
		# because the server writes no auth file, so an unprivileged session
		# user could not connect otherwise; it is bounded by -nolisten tcp and
		# by the run lifetime. -sharevts -novtswitch means no VT is allocated
		# and the owner's tty1 session is neither switched away nor reused.
		cd "$out" || exit 1
		exec "$prog" :1 -config sm750-x11.conf -sharevts -novtswitch \
			-noreset -ac -nolisten tcp -logfile xorg.log
		;;
	esac
) >"$out/03-compositor.log" 2>&1 &
pid=$!

sleep 3
if [ "$mode" = weston ]; then
	# A kiosk shell with nothing to show is indistinguishable from a black
	# screen; give it one client from the same package set.
	# weston publishes wayland-0 under the private runtime dir; the
	# client must be told which socket to connect to.
	WAYLAND_DISPLAY=wayland-0 WESTON_TERMINAL=1 /usr/bin/weston-terminal \
		>"$out/04-client.log" 2>&1 &
	client=$!
	printf '%s\n' "$client" >"$out/04-client.pid"
fi

if [ "$mode" = x11 ]; then
	# The session client has to be started by the desktop user, not by this
	# root helper, so the run announces the moment the display is usable.
	up=0
	tries=0
	while [ "$tries" -lt 20 ]; do
		if [ -S /tmp/.X11-unix/X1 ]; then
			up=1
			break
		fi
	tries=$((tries + 1))
		sleep 1
	done
	if [ "$up" -eq 1 ]; then
		printf '%s\n' "DISPLAY=:1" >"$out/04-display.txt"
		# The session must start with the desktop-wide GL/DRM variables of
		# /etc/environment cleared: that file points KWIN_DRM_DEVICES at the
		# NVIDIA card and forces __GLX_VENDOR_LIBRARY_NAME=nvidia, which makes
		# kwin_x11 crash four times before it gives up. The script is written
		# here so the user can run one file instead of remembering six names.
		cat >"$out/run-plasma-x11.sh" <<'PLASMA'
#!/bin/sh
# Start Plasma on the X server this run left listening on display :1.
# /etc/environment on this host selects the NVIDIA card for KWin and for GLX;
# on the SM750 that combination crashes kwin_x11 until it gives up, so the
# desktop-wide variables are cleared for this session only.
set -u
unset KWIN_DRM_DEVICES KWIN_RENDER_NODES KWIN_DISABLE_VULKAN KWIN_COMPOSE
unset __GLX_VENDOR_LIBRARY_NAME GBM_BACKEND VK_DRIVER_FILES VK_ICD_FILENAMES
export DISPLAY=:1
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true
exec /usr/bin/startplasma-x11
PLASMA
		chmod 0755 "$out/run-plasma-x11.sh"
		printf '%s: DISPLAY=:1 is up after %ss; start the session with %s\n' \
			"$PROG" "$tries" "$out/run-plasma-x11.sh"
	else
		printf '%s\n' "no socket" >"$out/04-display.txt"
		printf '%s: Xorg created no /tmp/.X11-unix/X1 within 20s (see %s)\n' "$PROG" "$out/03-compositor.log" >&2
	fi
fi

sleep "$seconds"

status=0
survived=1
rc=0
if kill -0 "$pid" 2>/dev/null; then
	echo "$PROG: $mode still running after ${seconds}s" >"$out/05-verdict.txt"
else
	survived=0
	wait "$pid" || rc=$?
	echo "$PROG: $mode exited with rc=$rc before ${seconds}s" >"$out/05-verdict.txt"
fi

vblank_after=$(cat "$DEV_ATTRS/vblank_count" 2>/dev/null || echo 0)
frames=$((vblank_after - vblank_before))
{
	echo "vblank_count before: $vblank_before"
	echo "vblank_count after:  $vblank_after"
	echo "vblank delta:        $frames"
	echo "# the raster scans out whether or not a user client owns the card,"
	echo "# so a frame count alone never proves a compositor rendered"
	if [ "$frames" -le 0 ]; then
		echo "RESULT: FAIL no vertical blank was counted while the compositor ran"
		status=3
	elif [ "$mode" = kmscube ]; then
		# kmscube gets a fixed frame count via -c, so a clean early exit is its pass condition.
		if [ "$survived" -eq 1 ]; then
			echo "RESULT: PASS kmscube was still rendering after ${seconds}s and VBlank advanced"
		elif [ "$rc" -eq 0 ]; then
			echo "RESULT: PASS kmscube rendered its frame count and exited rc=0"
		else
			echo "RESULT: FAIL kmscube exited with rc=$rc before ${seconds}s (see 03-compositor.log)"
			status=3
		fi
	elif [ "$survived" -ne 1 ]; then
		echo "RESULT: FAIL $mode did not survive ${seconds}s (see 03-compositor.log)"
		status=3
	else
		echo "RESULT: PASS $mode held the card for ${seconds}s and VBlank advanced"
	fi
} >>"$out/05-verdict.txt"

snapshot 06-after
cleanup
pid=
trap - EXIT

cat "$out/05-verdict.txt"
echo "$PROG: log in $out"
exit "$status"
