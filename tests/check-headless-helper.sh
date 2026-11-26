#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Static gate for tools/sm750-headless.sh, the operator helper installed as
# /usr/local/sbin/sm750-headless and allowlisted in docs/ROOT-ACTIONS.md
# section 3.11. The helper takes DRM master on the SM750 and hands the card to
# a real compositor, so its blast radius is the card plus the owner's session
# on seat0. This gate pins the properties that keep that radius small: a fixed
# program list with no passthrough argument, a clamed run time, a seat backend
# that never switches a VT, and a verdict that cannot pass on a frame count
# alone.
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

# --- b. five modes, everything else reaches usage ---------------------------
has "$(cat "$helper")" 'probe|diagnose|weston|cage|kmscube)' \
	"b: the mode dispatch must accept exactly probe, diagnose, weston, cage and kmscube"
has "$(cat "$helper")" '*) usage ;;' \
	"b: an unknown mode must fall through to usage, not to a default action"
has "$(cat "$helper")" 'exit 2' \
	"b: the usage path must exit 2 so a wrong mode cannot read as a run"
ok "b. modes probe, diagnose, weston, cage and kmscube dispatch, anything else exits 2"

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

# The pristine copy must still pass, otherwise the controls prove nothing.
cp "$helper" "$scratch/pristine.sh"
if ! bash "$0" --single "$scratch/pristine.sh" >/dev/null 2>"$scratch/pristine.err"; then
	bad "j: the unmutated copy was rejected: $(head -n 1 "$scratch/pristine.err")"
fi
printf 'negative control pristine: accepted\n'

[ "$fail" -eq 0 ] || exit 1
controls=12
if [ "$self_test" -eq 1 ]; then
	printf 'Headless helper checks passed (%s assertions, %s planted controls, self-test)\n' "$assertions" "$controls"
else
	printf 'Headless helper checks passed (%s assertions, %s planted controls)\n' "$assertions" "$controls"
fi
