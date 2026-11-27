#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Static gate for tools/sm750-headless.sh, the operator helper installed as
# /usr/local/sbin/sm750-headless and allowlisted in docs/ROOT-ACTIONS.md
# section 3.11. The helper takes DRM master on the SM750 and hands the card to
# a real compositor, so its blast radius is the card plus the owner's session
# on seat0. This gate pins the properties that keep that radius small: a fixed
# program list with no passthrough argument, a clamed run time, a seat backend
# that never switches a VT, a verdict that cannot pass on a frame count alone,
# an x11 arm that refuses to start without SM750_CONSOLE_ACK=1, and a teardown
# that activates only the VT the run started on.
#
# Nothing here runs the helper. No compositor is started, no card node is
# opened, no ioctl is issued, no root is needed: the gate reads the script
# text and parses it with sh -n.
#
# Usage: tests/check-headless-helper.sh [script]
#        tests/check-headless-helper.sh --self-test
#        tests/check-headless-helper.sh --single [script]   (no planted controls)
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
helper=${1:-$project_dir/tools/sm750-headless.sh}

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

scratch=$(mktemp -d "${TMPDIR}/sm750-headless-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

# arm FILE NAME - the case arm of the compositor switch, indentation stripped
# and comment lines dropped, so an argument is checked where it is executed and
# not where a comment happens to mention it.
arm() {
	awk -v want="$2" '
		{ line = $0; sub(/^[ \t]+/, "", line) }
		inarm && line == ";;" { exit }
		inarm && line != "" && line !~ /^#/ { print }
		!inarm && line == want ")" { inarm = 1 }
	' "$1"
}

has() { # has TEXT PATTERN MESSAGE
	case $1 in
	*"$2"*) ;;
	*) bad "$3" ;;
	esac
}

# func_body FILE NAME - the body of a shell function with indentation and
# comment lines dropped, so a call is checked where it runs and not where the
# definition or a comment happens to name it.
func_body() {
	awk -v want="$2() {" '
		{ line = $0; sub(/^[ \t]+/, "", line) }
		!inb && line == want { inb = 1; next }
		inb && line == "}" { exit }
		inb && line != "" && line !~ /^#/ { print }
	' "$1"
}

# --- a. the file exists, is a POSIX sh script and parses ---------------------
if [ ! -f "$helper" ]; then
	bad "a: $helper does not exist"
	echo "Headless helper: 0 assertions held, the script is missing" >&2
	exit 1
fi
has "$(head -n 1 "$helper")" '#!/bin/sh' \
	"a: the shebang must be #!/bin/sh, not a bash script"
if ! sh -n "$helper" 2>"$scratch/sh-n.err"; then
	bad "a: sh -n rejects $helper: $(head -n 1 "$scratch/sh-n.err")"
fi
ok "a. the helper exists, starts with #!/bin/sh and passes sh -n"

# --- b. six modes, everything else reaches usage ---------------------------
has "$(cat "$helper")" 'probe|diagnose|weston|cage|kmscube|x11)' \
	"b: the mode dispatch must accept exactly probe, diagnose, weston, cage, kmscube and x11"
has "$(cat "$helper")" '*) usage ;;' \
	"b: an unknown mode must fall through to usage, not to a default action"
has "$(cat "$helper")" 'exit 2' \
	"b: the usage path must exit 2 so a wrong mode cannot read as a run"
ok "b. modes probe, diagnose, weston, cage, kmscube and x11 dispatch, anything else exits 2"

# --- c. the card is the SM750 and the driver is bound ------------------------
body=$(cat "$helper")
has "$body" '0000:01:00.0' "c: the PCI BDF 0000:01:00.0 must be fixed in the script"
has "$body" 'sm750hdmidrm' "c: the expected driver name sm750hdmidrm must be checked"
has "$body" '[ "$driver" = sm750hdmidrm ]' \
	"c: the bound driver must be compared against sm750hdmidrm"
ok "c. the card is pinned to 0000:01:00.0 and verified bound to sm750hdmidrm"

# --- d. libseat noop, and no invented backend -------------------------------
has "$body" 'export LIBSEAT_BACKEND=noop' \
	"d: LIBSEAT_BACKEND=noop must be exported; logind and seatd are not usable here"
if grep -nE '^[[:space:]]*export[[:space:]]+[A-Z_]*BUILTIN' "$helper" >/dev/null ||
	grep -nE '^[[:space:]]*export[[:space:]]+LIBSEAT_BACKEND=builtin' "$helper" >/dev/null; then
	bad "d: LIBSEAT_BACKEND=builtin is not a libseat backend; only logind, seatd and noop exist"
fi
ok "d. LIBSEAT_BACKEND=noop is exported and no invented backend is set"

# --- e. the three program invocations --------------------------------------
weston_arm=$(arm "$helper" weston)
cage_arm=$(arm "$helper" cage)
kmscube_arm=$(arm "$helper" kmscube)
has "$weston_arm" '--backend=drm' "e: weston must be started with --backend=drm"
has "$weston_arm" '--drm-device=card0' "e: weston must be given --drm-device=card0"
has "$weston_arm" '--shell=kiosk-shell.so' "e: weston must run the kiosk shell"
has "$cage_arm" ' -d ' "e: cage must be started with -d"
if printf '%s\n' "$cage_arm" | grep -qE '(^|[[:space:]])-s([[:space:]]|$)'; then
	bad "e: cage must not be given -s; -s allows VT switching and seat0 belongs to the owner"
fi
has "$kmscube_arm" ' -c ' "e: kmscube must be given -c, the frame count"
if printf '%s\n' "$kmscube_arm" | grep -qE '(^|[[:space:]])-n([[:space:]]|$)'; then
	bad "e: kmscube must not be given -n; -n is a connector id, not the frame count"
fi
ok "e. weston gets its drm backend, device and shell; cage runs without -s; kmscube uses -c and not -n"

# --- f. the run time is numeric and bounded --------------------------------
has "$body" '*[!0-9]*' "f: SECONDS must be validated as numeric"
has "$body" '"$seconds" -ge 1' "f: SECONDS must have a lower bound of 1"
has "$body" '"$seconds" -le 600' "f: SECONDS must have an upper bound of 600"
ok "f. SECONDS is numeric and clamped to 1..600"

# --- g. the verdict needs a survivor and a vblank delta --------------------
has "$body" 'survived=0' \
	"g: the verdict must record that the compositor did not survive"
if ! printf '%s\n' "$body" | grep -qF '[ "$survived" -ne 1 ]'; then
	bad "g: the verdict must fail when the compositor did not survive the full run"
fi
has "$body" 'frames=$((vblank_after - vblank_before))' \
	"g: the verdict must compute the vblank delta from the two snapshots"
if ! printf '%s\n' "$body" | grep -qF '[ "$frames" -le 0 ]'; then
	bad "g: the verdict must fail when no vertical blank was counted"
fi
# Three verdict paths set status=3: the shared zero-vblank failure, the
# kmscube non-zero-exit failure, and the weston/cage non-survivor failure.
# Recounted honestly at three (it was two before the kmscube split); a new
# failure path must be added here deliberately, not silently.
if [ "$(grep -cF 'status=3' "$helper")" -ne 3 ]; then
	bad "g: the verdict must have exactly three failure exit paths (status=3), found $(grep -cF 'status=3' "$helper")"
fi
has "$body" 'a frame count alone never proves a compositor rendered' \
	"g: the verdict must state that a frame count alone proves nothing"
ok "g. the verdict fails on a dead compositor and on a zero vblank delta"

# --- g2. kmscube has its own exit model -----------------------------------
# kmscube takes a fixed frame count (-c 300) and exits by design when it has
# drawn them, so a clean early exit is a pass and only a non-zero rc is a
# failure. The frame-count guard must come first, otherwise a kmscube that
# crashed before drawing anything could pass on rc=0 alone.
has "$body" '[ "$mode" = kmscube ]' \
	"g2: the verdict must branch on the kmscube exit model"
if printf '%s\n' "$body" | grep -qF 'elif true; then'; then
	bad "g2: the kmscube exit branch must not pass unconditionally; a crashed kmscube (rc 255) would pass"
fi
has "$body" 'elif [ "$rc" -eq 0 ]; then' \
	"g2: a clean kmscube exit (rc 0) must not be reported as failure"
has "$body" 'RESULT: PASS kmscube rendered its frame count and exited rc=0' \
	"g2: the kmscube clean-exit PASS string must be present and distinct"
has "$body" 'RESULT: FAIL kmscube exited with rc=$rc before ${seconds}s (see 03-compositor.log)' \
	"g2: the kmscube non-zero-exit FAIL string must name the rc and the log"
has "$body" 'RESULT: PASS kmscube was still rendering after ${seconds}s and VBlank advanced' \
	"g2: the kmscube still-running PASS string must be present and distinct"
has "$body" '[ "$survived" -ne 1 ]' \
	"g2: the weston/cage non-survivor failure must survive the kmscube branch"
frames_line=$(grep -nF '[ "$frames" -le 0 ]' "$helper" | head -n 1 | cut -d: -f1)
kmscube_line=$(grep -nF 'elif [ "$mode" = kmscube ]; then' "$helper" | head -n 1 | cut -d: -f1)
if [ -z "$frames_line" ] || [ -z "$kmscube_line" ]; then
	bad "g2: the zero-vblank guard and the kmscube branch must both exist"
elif [ "$frames_line" -ge "$kmscube_line" ]; then
	bad "g2: the zero-vblank guard at :$frames_line must precede the kmscube branch at :$kmscube_line"
fi
ok "g2. kmscube passes on a clean early exit, fails on a non-zero rc, and cannot pass on zero frames"

# --- h. cleanup is TERM, then KILL, on an EXIT trap -----------------------
has "$body" 'trap cleanup EXIT' "h: cleanup must be installed as an EXIT trap"
term_line=$(grep -nF 'kill -TERM' "$helper" | head -n 1 | cut -d: -f1)
kill_line=$(grep -nF 'kill -KILL' "$helper" | head -n 1 | cut -d: -f1)
if [ -z "$term_line" ] || [ -z "$kill_line" ]; then
	bad "h: cleanup must send TERM and then KILL"
elif [ "$term_line" -ge "$kill_line" ]; then
	bad "h: cleanup must send TERM before KILL"
fi
ok "h. cleanup sends TERM then KILL from an EXIT trap"

# --- i. no local path, no non-ASCII byte ----------------------------------
if LC_ALL=C grep -nP '[^\x00-\x7F]' "$helper" >"$scratch/nonascii.txt"; then
	bad "i: non-ASCII byte in $helper at line $(head -n 1 "$scratch/nonascii.txt" | cut -d: -f1)"
fi
if grep -nP '/home/[[:alnum:]_.-]' "$helper" >"$scratch/homepath.txt"; then
	bad "i: absolute local path in $helper at line $(head -n 1 "$scratch/homepath.txt" | cut -d: -f1)"
fi
ok "i. no absolute local path and no non-ASCII byte in the helper"

# --- k. both compositors run with an empty /dev/input ---------------------
# A49: at 2026-11-26T06:32:48 weston's DRM backend opened the owner's keyboard
# and mouse because --no-input exists only for its x11 backend and cage has no
# input option at all, so no argument can stop the grab. The guard is a private
# mount namespace with a tmpfs over /dev/input. A compositor arm that reaches
# exec without passing through isolate() is unprotected, so both arms are
# checked, not one.
has "$body" '--mount --propagation private' \
	"k: the compositor must run in a private mount namespace (unshare --mount --propagation private)"
has "$body" '-t tmpfs -o size=1M,mode=0755 tmpfs /dev/input' \
	"k: an empty tmpfs must be mounted over /dev/input before the compositor starts"
has "$body" 'input devices are isolated in a private mount namespace (empty /dev/input)' \
	"k: the run must announce that input devices are isolated"
has "$body" '00-plan.txt' \
	"k: the isolation must be recorded in 00-plan.txt"
has "$weston_arm" 'isolate ' \
	"k: weston must be started through the input isolation, not exec'd directly"
has "$cage_arm" 'isolate ' \
	"k: cage must be started through the input isolation, not exec'd directly"
if printf '%s\n' "$kmscube_arm" | grep -qF 'isolate '; then
	bad "k: kmscube must keep its plain exec; it takes no input and is not isolated"
fi
# The namespace must be entered and the tmpfs mounted before either compositor
# execs. mount/isolate are the only two lines that can satisfy this, so the
# order is checked on their line numbers rather than on their text alone.
mount_line=$(grep -nF -e '-t tmpfs -o size=1M,mode=0755 tmpfs /dev/input' "$helper" | head -n 1 | cut -d: -f1)
weston_call=$(grep -nF 'isolate "$prog" --backend=drm' "$helper" | head -n 1 | cut -d: -f1)
cage_call=$(grep -nF 'isolate "$prog" -d -- /usr/bin/weston-terminal' "$helper" | head -n 1 | cut -d: -f1)
if [ -z "$mount_line" ] || [ -z "$weston_call" ] || [ -z "$cage_call" ]; then
	bad "k: the /dev/input mount and both compositor launches must all be present"
elif [ "$mount_line" -ge "$weston_call" ] || [ "$mount_line" -ge "$cage_call" ]; then
	bad "k: the /dev/input mount at :$mount_line must precede the weston call at :$weston_call and the cage call at :$cage_call"
fi
# WLR_LIBINPUT_NO_DEVICES is a wlroots variable. It is kept because cage is
# wlroots-based, but the comment must say so, otherwise its presence reads as
# the guard and the namespace gets removed as redundant.
has "$body" 'export WLR_LIBINPUT_NO_DEVICES=1' \
	"k: WLR_LIBINPUT_NO_DEVICES=1 must stay exported for cage"
if ! grep -qF 'wlroots' "$helper"; then
	bad "k: WLR_LIBINPUT_NO_DEVICES must be documented as a wlroots-only variable"
fi
ok "k. weston and cage both run in a private mount namespace with an empty /dev/input, mounted before the exec"

# --- l. the x11 arm: a root server that never touches the owner's input ----
# Xorg cannot open a VT without privilege here ((EE) xf86OpenConsole: Cannot
# open virtual console 1 (Permission denied) as coder), so the arm runs as
# root. That makes input isolation a configuration question, not a namespace
# one: AutoAddDevices off and no InputDevice section are the whole guarantee,
# and both are asserted so a later "helpful" addition cannot quietly reinstate
# the A49 keyboard grab with root privileges behind it.
has "$body" 'Section "ServerFlags"' \
	"l: the x11 arm must emit its own ServerFlags section"
has "$body" 'Option "AutoAddDevices" "false"' \
	"l: AutoAddDevices must be off so Xorg never opens /dev/input as root"
has "$body" 'Option "AutoAddGPU" "false"' \
	"l: AutoAddGPU must be off so the NVIDIA cards are not added to this server"
has "$body" 'Option "DontVTSwitch" "true"' \
	"l: DontVTSwitch must be on; the owner's tty1 session must not be switched away"
has "$body" 'Option "DontZap" "true"' \
	"l: DontZap must be on; a root Ctrl-Alt-Backspace would take the server down"
has "$body" 'Option "kmsdev"' \
	"l: the device must be pinned with kmsdev, not left to auto-detection"
has "$body" 'Option "AccelMethod" "none"' \
	"l: the x11 arm must request the software path; there is no Mesa driver for this GPU"
# The generated Device section must not carry PrimaryGPU: the modesetting
# driver ignores it there and logs
# "(WW) modeset(0): Option "PrimaryGPU" is not used" (Xorg 21.1.26, run
# 20261126T125401Z-x11). Card selection is done by the shipped OutputClass
# fragment, so the whole option is dead weight that also emits a warning.
# The section is extracted with comments stripped, so the explanatory comment
# above it cannot satisfy or trip this check.
device_section=$(awk '
	{ line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line) }
	!indev && line == "Section \"Device\"" { indev = 1; next }
	indev && line == "EndSection" { exit }
	indev && line != "" && line !~ /^#/ { print }
' "$helper")
if [ -z "$device_section" ]; then
	bad "l: the x11 arm must emit a Device section; none was found"
fi
if printf '%s\n' "$device_section" | grep -qF 'PrimaryGPU'; then
	bad "l: PrimaryGPU must not appear in the x11 Device section; modesetting ignores it there and warns, card selection is done by the OutputClass fragment"
fi
# The load-bearing options in that section must survive: dropping one to
# silence the warning would trade a warning for a broken render path.
has "$device_section" 'Driver "modesetting"' \
	"l: the Device section must keep Driver modesetting"
has "$device_section" 'Option "kmsdev"' \
	"l: the Device section must keep kmsdev pinned to the card node"
has "$device_section" 'Option "AccelMethod" "none"' \
	"l: the Device section must keep the software path (AccelMethod none)"
has "$device_section" 'Option "ShadowFB" "true"' \
	"l: the Device section must keep ShadowFB; the card has no working Mesa driver"
has "$body" '20-sm750hdmidrm.conf' \
	"l: the helper must name the OutputClass fragment that actually selects card0"
if grep -nE 'Section[[:space:]]+"InputDevice"' "$helper" >/dev/null; then
	bad "l: an InputDevice section would open a real input device as root; the x11 arm must declare none"
fi
if grep -nF 'AutoAddDevices" "true' "$helper" >/dev/null; then
	bad "l: AutoAddDevices true would add every present input device to a root X server"
fi
has "$body" '/usr/libexec/Xorg' \
	"l: the arm must exec /usr/libexec/Xorg directly, never a setuid wrapper"
has "$body" 'cd "$out" || exit 1' \
	"l: the arm must cd into the run directory, because -config rejects absolute paths"
if grep -nE '\-config[[:space:]]+/' "$helper" >/dev/null; then
	bad "l: -config must be a relative path; Xorg refuses an absolute one under elevated privileges"
fi
if grep -nE '\-config[[:space:]]+\.\.' "$helper" >/dev/null; then
	bad "l: -config must not contain .. elements; Xorg refuses it under elevated privileges"
fi
has "$body" '-config sm750-x11.conf' \
	"l: the arm must pass the generated config by bare filename"
has "$body" '-sharevts -novtswitch' \
	"l: the server must not claim or switch a VT (-sharevts -novtswitch)"
has "$body" '-nolisten tcp' \
	"l: the server must not open a TCP listener"
has "$body" 'no input devices are configured' \
	"l: the run must record that no input device was configured"
has "$body" '/tmp/.X11-unix/X1' \
	"l: the arm must report whether DISPLAY=:1 came up for the session user"
has "$body" 'KWIN_DRM_DEVICES' \
	"l: the run must name the variables a Plasma session on :1 has to start without"
has "$body" 'run-plasma-x11.sh' \
	"l: the run must leave a session script the user can execute; six variable names are too many to remember"
# The launcher clears the desktop-wide selection from /etc/environment; assert
# the launcher lines themselves, not bare variable names, which the plan file
# above already mentions.
has "$body" 'unset KWIN_DRM_DEVICES KWIN_RENDER_NODES' \
	"l: the generated session script must clear KWIN_DRM_DEVICES for the SM750"
has "$body" 'unset __GLX_VENDOR_LIBRARY_NAME GBM_BACKEND' \
	"l: the generated session script must clear the forced NVIDIA GLX and GBM selection"
has "$body" '__GLX_VENDOR_LIBRARY_NAME' \
	"l: a leaked GLX vendor library selection must be named; it made kwin_x11 crash four times"
ok "l. the x11 arm runs a root server on :1 with no input device, no VT switch and no TCP listener"

# --- m. a finished session puts the text console back ----------------------
# Measured on the SM750 on 2026-11-26: when the last client removes its
# framebuffer the DRM core disables the CRTC (drm_framebuffer.c
# atomic_remove_fb), the kernel's only restore (drm_lastclose ->
# drm_client_dev_restore) never ran, and a foreground VT left in KD_GRAPHICS
# stops the console from repainting at all (drivers/tty/vt/vt.c
# do_con_write). A chvt to a text VT brought both back within 2 s, so the
# teardown must do it. The properties pinned here: the VT and its mode are
# recorded before the client starts, probe and diagnose never touch a VT, and
# cleanup switches to a text VT without ever failing the run.
cleanup_body=$(func_body "$helper" cleanup)
has "$body" '/sys/class/tty/tty0/active' \
	"m: the helper must record the active VT from /sys/class/tty/tty0/active"
has "$body" 'fcntl.ioctl(f.fileno(), 0x4B3B' \
	"m: the VT mode must be read with KDGETMODE (0x4B3B), not assumed"
has "$cleanup_body" 'vt_restore' \
	"m: cleanup must put the console back; a teardown that only kills leaves the panel dark"
has "$body" 'restored text console on' \
	"m: the teardown must say which VT it restored"
has "$body" 'the panel was left with no client' \
	"m: the restored line must say why the console had to be restored"
has "$body" 'left it alone, it is not ours to switch' \
	"m: a foreground VT that moved must be reported and left alone"
has "$body" '/sys/class/tty/$start_vt/active' \
	"m: the recorded VT must be re-checked against /sys/class/tty/ttyN/active before it is switched"
has "$body" 'is unavailable; the console may stay dark' \
	"m: a missing chvt must warn and continue, not fail the run"
record_line=$(grep -nxF 'vt_record' "$helper" | head -n 1 | cut -d: -f1)
probe_exit=$(grep -nF 'probe complete, log in' "$helper" | head -n 1 | cut -d: -f1)
diag_exit=$(grep -nF 'diagnose complete, log in' "$helper" | head -n 1 | cut -d: -f1)
launch_line=$(grep -nxF 'pid=$!' "$helper" | head -n 1 | cut -d: -f1)
if [ -z "$record_line" ] || [ -z "$probe_exit" ] || [ -z "$diag_exit" ] || [ -z "$launch_line" ]; then
	bad "m: the VT record call, both read-only mode exits and the compositor launch must all exist"
else
	if [ "$record_line" -le "$probe_exit" ] || [ "$record_line" -le "$diag_exit" ]; then
		bad "m: probe and diagnose must never record or restore a VT; vt_record at :$record_line comes before the probe exit at :$probe_exit or the diagnose exit at :$diag_exit"
	fi
	if [ "$record_line" -ge "$launch_line" ]; then
		bad "m: the VT must be recorded before the client is launched; vt_record at :$record_line, launch at :$launch_line"
	fi
fi
ok "m. the VT is recorded before the client starts and cleanup restores a text console, leaving foreign VTs alone"

# --- n. diagnose sees every node of the device, not just card0 -------------
# DRIVER_RENDER publishes /dev/dri/renderD<N> (crw-rw-rw-); a process holding
# it keeps dev->open_count above zero, which is the leading explanation for
# the skipped last-close restore. The old scan matched fd targets against the
# literal string card0 and was blind to that node, and it ignored the fd
# tables this account cannot read - 673 of 906 at the 2026-11-26 measurement.
has "$body" '/sys/class/drm/card*/device/drm/*' \
	"n: diagnose must enumerate the device's nodes from its sysfs drm directory"
has "$body" '/sys/class/drm/renderD*/device/drm/*' \
	"n: diagnose must enumerate render nodes; a holder of one suppresses the last-close restore"
has "$body" '[ "$dev_of" = "$d" ]' \
	"n: nodes must be matched by device number, not by the literal card0"
if grep -qF '*card0*)' "$helper"; then
	bad "n: diagnose must not match fd targets by the literal string card0; renderD128 holders are invisible that way"
fi
has "$body" 'inode=%s' \
	"n: each node must be reported with its inode"
has "$body" 'fd tables: $fd_seen processes, $fd_dark unreadable' \
	"n: unreadable fd tables must be counted and reported, not silently skipped"
has "$body" 'holder node=' \
	"n: each holder line must name the node it holds"
has "$body" '# fd-table holders of the card inode' \
	"n: the existing card0 line must stay"
ok "n. diagnose matches every node of the device by device number, prints inode and holders, and counts unreadable fd tables"

# --- o. the console is the owner's: an ack, the start VT, and a way back -----
# Measured 2026-11-27: three runs of `sm750-headless x11 150` each took DRM
# master on the card behind the owner's console and reprogrammed its mode, and
# the teardown chvt'd to tty2, moving his foreground VT off tty1 while his
# keyboard still went to a VT where nothing ran; he had to cut power. The
# properties pinned here: only an explicitly acknowledged x11 run may start,
# teardown activates only the VT the run started on, and every path that cannot
# do so prints the command to do it by hand.
x11_arm=$(arm "$helper" x11)
has "$x11_arm" '[ "${SM750_CONSOLE_ACK:-}" != 1 ]' \
	"o: the x11 arm must refuse unless SM750_CONSOLE_ACK=1 is set"
has "$x11_arm" 'exit 2' \
	"o: the refusal must exit 2 instead of starting the server"
for m in weston cage kmscube; do
	if printf '%s\n' "$(arm "$helper" "$m")" | grep -qF 'SM750_CONSOLE_ACK'; then
		bad "o: only the x11 arm takes the console; the $m arm must not require SM750_CONSOLE_ACK"
	fi
done
ok "o1. the x11 arm refuses without SM750_CONSOLE_ACK=1 and no other arm gained a requirement"

has "$x11_arm" 'behind the console' \
	"o: the refusal must name the hazard: the arm takes the card behind the console"
has "$x11_arm" 'reprograms its mode' \
	"o: the refusal must say the arm reprograms the card's mode"
has "$x11_arm" 'nobody is using the machine' \
	"o: the refusal must say to run it only when nobody is using the machine"
ok "o2. the refusal names the console hazard, the mode change and the idle-machine condition"

ack_line=$(grep -nF '[ "${SM750_CONSOLE_ACK:-}" != 1 ]' "$helper" | head -n 1 | cut -d: -f1)
xorg_spawn=$(grep -nF 'exec "$prog" :1 -config' "$helper" | head -n 1 | cut -d: -f1)
master_line=$(grep -nF 'probe_master >' "$helper" | head -n 1 | cut -d: -f1)
if [ -z "$ack_line" ] || [ -z "$xorg_spawn" ] || [ -z "$master_line" ]; then
	bad "o: the ack test, the Xorg spawn and the master probe must all exist"
elif [ "$ack_line" -ge "$xorg_spawn" ]; then
	bad "o: the ack test at :$ack_line must precede the Xorg spawn at :$xorg_spawn"
elif [ "$ack_line" -ge "$master_line" ]; then
	bad "o: the ack test at :$ack_line must precede the first DRM master work at :$master_line"
fi
ok "o3. the ack test runs before the Xorg spawn and before the first DRM master work"

has "$x11_arm" 'start-vt' \
	"o: the x11 run must record the start VT in 00-plan.txt"
has "$x11_arm" 'active_vt' \
	"o: the recorded start VT must be read from the active VT, not guessed"
ok "o4. the x11 run records in 00-plan.txt the start VT it will restore"

restore_body=$(func_body "$helper" vt_restore)
has "$restore_body" '"$CHVT" "${start_vt#tty}"' \
	"o: teardown must chvt to the recorded start VT"
if printf '%s\n' "$restore_body" | grep -qE '"\$CHVT"[[:space:]]+[0-9]'; then
	bad "o: teardown must not chvt to a fixed VT number"
fi
if printf '%s\n' "$restore_body" | grep -qF 'candidates'; then
	bad "o: teardown must not pick a spare VT from a candidate list"
fi
has "$restore_body" 'the start VT was not recorded' \
	"o: an unrecorded start VT must be reported instead of guessed"
has "$restore_body" 'restored text console on $start_vt' \
	"o: the teardown line must name the VT it restored"
has "$restore_body" 'chvt ${start_vt#tty} failed' \
	"o: a failed chvt must be reported with the VT it tried"
recovery_calls=$(printf '%s\n' "$restore_body" | grep -cF 'vt_recovery' || true)
if [ "${recovery_calls:-0}" -lt 2 ]; then
	bad "o: the recovery command must be printed on the unrecorded start VT and on a failed chvt, found ${recovery_calls:-0} calls"
fi
recovery_body=$(func_body "$helper" vt_recovery)
has "$recovery_body" '$CHVT ${start_vt#tty}' \
	"o: the recovery hint must print the chvt command for the recorded VT"
has "$recovery_body" 'Ctrl-Alt-F' \
	"o: the recovery hint must also name the key sequence for the operator"
ok "o5. teardown activates only the recorded start VT and prints the manual recovery command when it cannot"

# --- p. progress lines and the input handover ------------------------------
# The owner's 2026-11-27 symptom was precise: after a run that moved the VT his
# DVI picture stayed on screen (the compositor's last frame) while his mouse and
# keyboard stopped working, because input followed the VT. Two properties are
# pinned here: a long wait prints one greppable line per 10 s so a live run is
# not read as a hang, and the helper records which processes hold
# /dev/input/event* before and after a run so that handover is visible. The
# record is observation only: nothing under /dev/input may be opened or grabbed.
wait_body=$(func_body "$helper" wait_window)
progress_body=$(func_body "$helper" progress)
has "$wait_body" 'progress "$elapsed"' \
	"p: the progress line must be printed from inside the wait loop"
has "$wait_body" 'step=10' \
	"p: the progress interval must be 10 s, not one line per loop iteration or per second"
has "$wait_body" 'sleep "$step"' \
	"p: the wait must sleep the interval it prints, so no burst can happen"
has "$progress_body" 't=%ss mode=%s pid=%s' \
	"p: the progress line must carry elapsed seconds, the mode and the client pid"
has "$progress_body" 'alive' \
	"p: the progress line must say whether the client pid is alive"
wait_call=$(grep -nxF 'wait_window' "$helper" | head -n 1 | cut -d: -f1)
if [ -z "$wait_call" ] || [ -z "$probe_exit" ] || [ -z "$diag_exit" ]; then
	bad "p: the wait call and both read-only mode exits must exist"
elif [ "$wait_call" -le "$probe_exit" ] || [ "$wait_call" -le "$diag_exit" ]; then
	bad "p: probe and diagnose must gain no wait window; wait_window at :$wait_call must follow the probe exit at :$probe_exit and the diagnose exit at :$diag_exit"
fi
if grep -nF 'sleep "$seconds"' "$helper" >/dev/null; then
	bad "p: the silent unbounded sleep must be gone; that silent wait is the hang the progress line exists to expose"
fi
ok "p1. the wait prints one greppable line per 10 s interval, and probe and diagnose have no wait window"

scan_body=$(func_body "$helper" input_scan)
has "$scan_body" '/proc/[0-9]*' \
	"p: the input scan must walk /proc/*/fd"
has "$scan_body" '/dev/input/event*' \
	"p: the input scan must match the owner's /dev/input/event* nodes"
has "$scan_body" 'uid=' \
	"p: each input holder must be printed with its uid"
has "$scan_body" 'skipped' \
	"p: unreadable fd tables must be counted and reported, never fatal"
if printf '%s\n' "$scan_body" | grep -qE '>[[:space:]]*/dev/input|</dev/input|EVIOCGRAB'; then
	bad "p: the input scan is observation only; it must never open or grab anything under /dev/input"
fi
scan_call=$(grep -nF 'input_scan "$in_before"' "$helper" | head -n 1 | cut -d: -f1)
if [ -z "$scan_call" ] || [ -z "$launch_line" ]; then
	bad "p: the pre-run input scan and the client launch must both exist"
elif [ "$scan_call" -ge "$launch_line" ]; then
	bad "p: the input holders must be recorded before the client starts; scan at :$scan_call, launch at :$launch_line"
fi
ok "p2. the input-holder scan reads /proc/*/fd for /dev/input/event*, prints pids with uids and counts unreadable fd tables"

delta_body=$(func_body "$helper" input_delta)
has "$delta_body" 'holders before' \
	"p: the teardown must print the before/after input-holder delta"
has "$delta_body" ' %s after' \
	"p: the delta line must carry the after count as well as the before count"
has "$delta_body" 'belong to another VT' \
	"p: the delta warning must say the owner's input devices may now belong to another VT"
has "$delta_body" 'Ctrl-Alt-F' \
	"p: the way back must be named: Ctrl-Alt-F<N> on the keyboard"
if ! printf '%s\n' "$(func_body "$helper" cleanup)" | grep -qF 'input_delta'; then
	bad "p: cleanup must print the input delta at teardown"
fi
ok "p3. teardown prints the before/after input-holder delta and the Ctrl-Alt-F way back"

has "$x11_arm" 'follow the VT' \
	"p: the refusal must say the owner's mouse and keyboard follow the VT"
has "$x11_arm" 'looks alive but stops responding' \
	"p: the refusal must say the machine looks alive but stops responding"
ok "p4. the refusal states the consequence in the owner's terms: input follows the VT and the screen keeps the last frame"

[ "$fail" -eq 0 ] || exit 1

if [ "$single" -eq 1 ]; then
	printf 'Headless helper assertions passed (%s)\n' "$helper"
	exit 0
fi

# --- j. planted controls ---------------------------------------------------
# Each control mutates one property the assertions above pin, and the gate must
# reject the mutated copy. A gate that cannot fail is decoration.
home_prefix=$(printf '/%s' home)

plant_no_libseat() { # the seat backend export deleted: libseat picks logind
	sed -i '/^export LIBSEAT_BACKEND=noop$/d' "$1"
}
plant_builtin_backend() { # an invented backend name: libseat refuses to start
	sed -i 's/^export LIBSEAT_BACKEND=noop$/export LIBSEAT_BACKEND=builtin/' "$1"
}
plant_cage_vt_switch() { # -s lets cage switch the VT out from under the owner
	sed -i 's|-d -- /usr/bin/weston-terminal|-d -s -- /usr/bin/weston-terminal|' "$1"
}
plant_kmscube_connector() { # -n is a connector id, so the frame count is lost
	sed -i 's| -c 300| -n 300|' "$1"
}
plant_no_survived_check() { # a dead compositor would no longer be recorded
	sed -i '/^[[:space:]]*survived=0$/d' "$1"
}
plant_no_vblank_check() { # a zero vblank delta would no longer fail
	# The delta guard leads the chain as "if", not "elif": the branches after
	# it are per-mode, so it cannot be an arm of the survivor test.
	sed -i 's/if \[ "\$frames" -le 0 \]; then/if false; then/' "$1"
}
plant_kmscube_exit_is_failure() { # a clean kmscube completion reported as failure
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\telif [ "$rc" -eq 0 ]; then\n'
new = '\t\telif false; then\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_kmscube_rc_ignored() { # a crashed kmscube (rc 255) would pass on exit alone
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\telif [ "$rc" -eq 0 ]; then\n'
new = '\t\telif true; then\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_local_path() { # a local absolute path in a committed script
	printf 'scratch=%s/coder/x\n' "$home_prefix" >>"$1"
}
plant_seconds_zero() { # the lower clamp opened to zero
	sed -i 's/"\$seconds" -ge 1/"$seconds" -ge 0/' "$1"
}
plant_input_isolation_dropped() { # both compositors exec without the namespace
	# A weston that reads /dev/input directly grabs the owner's keyboard, which
	# is the A49 incident: the compositor must not be reachable without isolate.
	sed -i 's|isolate "\$prog"|exec "$prog"|g' "$1"
}
plant_isolation_one_mode_only() { # cage left unprotected while weston is sealed
	sed -i 's|isolate "\$prog" -d -- /usr/bin/weston-terminal|exec "$prog" -d -- /usr/bin/weston-terminal|' "$1"
}
plant_x11_sharevts_dropped() { # the root server would take a VT away from the owner
	sed -i 's| -sharevts -novtswitch||' "$1"
}
plant_x11_input_device() { # a root X server that opens a real input device
	printf 'Section "InputDevice"\n\tIdentifier "keyboard"\n\tDriver "libinput"\nEndSection\n' >>"$1"
}
plant_x11_abspath_config() { # -config with an absolute path: refused by Xorg
	sed -i 's|-config sm750-x11.conf|-config /tmp/sm750-x11.conf|' "$1"
}
plant_x11_session_script_unset_dropped() { # the generated session script starts with the hostile environment
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
keep = [l for l in open(p)
        if not (l.startswith('unset ')
                and ('KWIN_DRM_DEVICES' in l or '__GLX_VENDOR_LIBRARY_NAME' in l))]
out = open(p, 'w')
out.writelines(keep)
out.close()
MUT
}

plant_x11_env_note_dropped() { # the leak that cost four kwin crashes goes unmentioned
	# Both the sentence and the unset list must go, otherwise the variable
	# names are still in the file and the assertion would rightly still hold.
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
keep = [l for l in open(p)
        if 'KWIN_DRM_DEVICES' not in l
        and '__GLX_VENDOR_LIBRARY_NAME' not in l]
out = open(p, 'w')
out.writelines(keep)
out.close()
MUT
}

plant_x11_primarygpu_reintroduced() { # a Device-section PrimaryGPU the modesetting driver ignores and warns about
	# Inserted right after Driver "modesetting", so it lands inside the Device
	# section and changes nothing else: the rejection can only be the
	# PrimaryGPU assertion.
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '\tDriver "modesetting"\n'
assert s.count(anchor) == 1, s.count(anchor)
inject = anchor + '\tOption "PrimaryGPU" "true"\n'
open(p, 'w').write(s.replace(anchor, inject, 1))
MUT
}

plant_no_console_restore() { # teardown kills the client and leaves the VT dark
	# The call is removed, not the function: the helper still contains the
	# restore code, but nothing runs it, so a finished session leaves the
	# panel dark exactly as measured on 2026-11-26.
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\tvt_restore\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}

plant_diagnose_card0_only() { # holder scan back to the literal card0 node
	# Name matching instead of device matching: a world-writable renderD128
	# holder, the leading candidate for the skipped restore, becomes
	# invisible again, which is the blindness this scan exists to remove.
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\t\tif [ "$dev_of" = "$d" ]; then\n'
new = '\t\t\tif [ "/dev/dri/${n##*/}" = "/dev/dri/card0" ]; then\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, new))
MUT
}

plant_vt_restore_hardcoded_tty2() { # teardown chvt's a fixed tty2, moving the owner's console
	# The property, not its comment: the switch target itself becomes a
	# constant, which is exactly what moved the owner's VT on 2026-11-27.
	sed -i 's|"\$CHVT" "\${start_vt#tty}"|"$CHVT" 2|' "$1"
}

plant_vt_restore_moved_after_release() { # teardown restores a discovered VT, not the start VT
	# Still a target, still a chvt, but no longer the VT the run began on:
	# the restore follows whatever the foreground is when it runs.
	sed -i 's|"\$CHVT" "\${start_vt#tty}"|"$CHVT" "${now_vt#tty}"|' "$1"
}

plant_console_ack_removed() { # the acknowledgement deleted: a stray run takes the console
	# The condition becomes ':', so the refusal block is dead and the server
	# starts on an unacknowledged run exactly as it did three times before.
	sed -i 's|\[ "\${SM750_CONSOLE_ACK:-}" != 1 \]|:|' "$1"
}

plant_progress_line_removed() { # the wait goes silent again: a hang reads like a run
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\tprogress "$elapsed"\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}

plant_progress_burst() { # the interval collapses to one line per second
	sed -i 's/step=10/step=1/' "$1"
}

plant_input_delta_removed() { # the teardown stops reporting the input handover
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t\tinput_delta || true\n'
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}

control() {
	local name=$1
	local planted=$scratch/sm750-headless.sh
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

control no-libseat-export plant_no_libseat
control builtin-backend plant_builtin_backend
control cage-vt-switch plant_cage_vt_switch
control kmscube-connector plant_kmscube_connector
control survived-check-dropped plant_no_survived_check
control vblank-check-dropped plant_no_vblank_check
control kmscube-exit-is-failure plant_kmscube_exit_is_failure
control kmscube-rc-ignored plant_kmscube_rc_ignored
control local-path plant_local_path
control seconds-zero-clamp plant_seconds_zero
control input-isolation-dropped plant_input_isolation_dropped
control isolation-one-mode-only plant_isolation_one_mode_only
control x11-sharevts-dropped plant_x11_sharevts_dropped
control x11-input-device plant_x11_input_device
control x11-abspath-config plant_x11_abspath_config
control x11-primarygpu-reintroduced plant_x11_primarygpu_reintroduced
control x11-env-note-dropped plant_x11_env_note_dropped
control x11-session-script-unset-dropped plant_x11_session_script_unset_dropped
control console-restore-dropped plant_no_console_restore
control diagnose-card0-only plant_diagnose_card0_only
control vt-restore-hardcoded-tty2 plant_vt_restore_hardcoded_tty2
control vt-restore-moved-after-release plant_vt_restore_moved_after_release
control console-ack-removed plant_console_ack_removed
control progress-line-removed plant_progress_line_removed
control progress-burst plant_progress_burst
control input-delta-removed plant_input_delta_removed

# The pristine copy must still pass, otherwise the controls prove nothing.
cp "$helper" "$scratch/pristine.sh"
if ! bash "$0" --single "$scratch/pristine.sh" >/dev/null 2>"$scratch/pristine.err"; then
	bad "j: the unmutated copy was rejected: $(head -n 1 "$scratch/pristine.err")"
fi
printf 'negative control pristine: accepted\n'

[ "$fail" -eq 0 ] || exit 1
controls=26
if [ "$self_test" -eq 1 ]; then
	printf 'Headless helper checks passed (%s assertions, %s planted controls, self-test)\n' "$assertions" "$controls"
else
	printf 'Headless helper checks passed (%s assertions, %s planted controls)\n' "$assertions" "$controls"
fi
