#!/bin/bash
# check-soak-helper.sh - gate for tools/sm750-soak.sh, the long-window soak
# helper.
#
# Two arms. The static arm reads the helper text and asserts the properties a
# soak needs to be safe to leave running unattended on the owner's machine: it
# is POSIX sh and ASCII, it only ever reads, it never grabs a console, never
# switches a VT, never unshares /dev/input, never starts a graphical server and
# never signals a process, it writes only into a fresh directory under
# /mega/tmp/sm750, and it records every field the release report cites. The
# runtime arm runs the helper against a fixture root (no card, no root, no
# DRM node) and requires that a healthy fixture finishes PASS with a zero exit
# status, that a single planted out-of-range field turns the verdict into FAIL
# with a non-zero exit status naming that field, that a fault line already in
# the kernel buffer cannot fail a run, that a fault line logged during a run
# does fail it, and that an interrupted run is never PASS.
#
# Planted controls prove the arms are not vacuous: each of the five forbidden
# constructs is planted into a copy of the helper and the static arm must
# reject the copy with a non-zero exit status and a message on stderr.
#
# Usage:
#   ./tests/check-soak-helper.sh              full gate
#   ./tests/check-soak-helper.sh --single F   static arm on one file, exit 1
#                                             on the first failure set
#
# This gate needs no card and no root. It exits 0 when every assertion holds.
set -uo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(cd "$(dirname "$0")/.." && pwd)
helper=$project_dir/tools/sm750-soak.sh
self=$0
assertions=0
failures=0
controls=0

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	failures=$((failures + 1))
}

ok() { assertions=$((assertions + 1)); }

has() { # has BODY NEEDLE MESSAGE
	assertions=$((assertions + 1))
	case $1 in
	*"$2"*) ;;
	*) fail "$3 (missing: $2)" ;;
	esac
}

# nofind FILE REGEX MESSAGE - fail when a regular expression matches the
# executed text of FILE. Used where a plain substring would hit an unrelated
# occurrence, such as the "[[" inside the "[[:space:]]" character class.
nofind() { # nofind FILE REGEX MESSAGE
	assertions=$((assertions + 1))
	local hit
	hit=$(grep -nE "$2" "$1" 2>/dev/null | head -n 1) || hit=
	if [ -n "$hit" ]; then
		fail "$3 (found: $hit)"
	fi
}

hasnot() { # hasnot BODY NEEDLE MESSAGE
	assertions=$((assertions + 1))
	case $1 in
	*"$2"*) fail "$3 (found: $2)" ;;
	*) ;;
	esac
}

# exec_text FILE - the file with comment lines and the usage-heredoc body
# removed. A forbidden call in a comment or in help text is not a call; a
# forbidden call on an executed line is.
exec_text() {
	awk '
	BEGIN { h = 0 }
	h == 1 { if ($0 == "EOF") h = 0; next }
	/^[[:space:]]*#/ { next }
	/<<.EOF.$/ { h = 1 }
	{ print }
	' "$1"
}

check_static() { # check_static FILE
	local file=$1 body code
	[ -r "$file" ] || {
		fail "cannot read $file"
		return 0
	}
	body=$(cat "$file")
	code=$(exec_text "$file")

	# a. POSIX sh, ASCII, scratch discipline.
	has "$body" '#!/bin/sh' "a: the helper must declare /bin/sh, not bash"
	hasnot "$body" '#!/bin/bash' "a: the helper must not be a bash script"
	has "$body" 'set -eu' "a: the helper must run with set -eu"
	has "$body" 'export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}' \
		"a: the helper must pin TMPDIR to the approved scratch root"
	has "$code" 'mktemp -d "${TMPDIR}/sm750-soak.XXXXXX"' \
		"a: the scratch directory must be a mktemp template under ${TMPDIR}"
	hasnot "$code" 'local ' "a: local is not POSIX; the helper must not use it"
	hasnot "$code" 'pipefail' "a: pipefail is a bashism; the helper must be POSIX"
	nofind "$file" '(^|[[:space:];&|(])\[\[($|[[:space:]])' \
		"a: [[ is a bashism; the helper must be POSIX sh"
	nofind "$file" '^[[:space:]]*function[[:space:]]' \
		"a: shell functions must be declared as name(), not with function"
	bad=$(
		LC_ALL=C grep -n '[^ -~	]' "$file" 2>/dev/null | head -n 1
	) || bad=
	if [ -n "$bad" ]; then
		fail "a: the helper must be ASCII only, found $bad"
	else
		ok
	fi

	# b. Read-only: sysfs attributes, /proc and the kernel log, never a card
	# node, never a write to the kernel.
	hasnot "$code" '/dev/dri/' "b: the helper must not open a DRM node"
	hasnot "$code" 'ioctl' "b: the helper must not issue an ioctl"
	hasnot "$code" 'modprobe' "b: the helper must not load or unload a module"
	hasnot "$code" '>/sys/' "b: the helper must not write a sysfs attribute"
	has "$body" '[ -r "$1" ]' \
		"b: a sysfs attribute must be read only after a readable check"
	has "$body" 'sudo -n' "b: a privileged read must use the allowlisted sudo -n"
	has "$code" 'dmesg' "b: the helper must count new kernel log lines"
	has "$body" '/^MemAvailable:/' "b: the helper must read MemAvailable"
	has "$body" '/proc/modules' "b: the helper must read the resident module size"

	# c. The five forbidden constructs, on executed lines only.
	hasnot "$code" 'chvt' "c: no chvt"
	hasnot "$code" 'VT_ACTIVATE' "c: no VT_ACTIVATE"
	hasnot "$code" 'unshare' "c: no unshare"
	hasnot "$code" '/dev/input' "c: no access to /dev/input"
	hasnot "$code" 'weston' "c: no compositor launch"
	hasnot "$code" 'cage' "c: no compositor launch"
	hasnot "$code" 'Xorg' "c: no X server launch"
	hasnot "$code" 'startx' "c: no X server launch"
	hasnot "$code" 'kill' "c: no signal to a process"
	hasnot "$code" 'pkill' "c: no signal to a process"
	hasnot "$code" 'killall' "c: no signal to a process"

	# d. Every field a sample must carry.
	local needle
	for needle in '#sample' 'present' 'panel_cell' 'vram_used' 'vram_total' \
		'mem_info_vram_total' 'refcnt' 'version' 'module_size' 'mem_avail' \
		'vblank' 'panel_line' 'crc' 'b8_mode_attempts' 'b8_mode_failures' \
		'b8_mode_retries' 'b8_stage_failures' 'b8_i2c_write_timeouts' \
		'b8_i2c_recoveries' 'b8_ready_expired' 'b8_ddc_grant_timeouts' \
		'b8_edid_reads' 'b8_edid_failures' 'b8_epoch_s' 'gates' \
		'dmesg_lines' 'dmesg_faults'; do
		has "$body" "$needle" "d: a sample must record $needle"
	done
	has "$body" 'link_state' "d: the panel cell must carry the link state"
	has "$body" 'PANEL_CURRENT_LINE' "d: the panel current line must be recorded"
	has "$body" 'unavailable:' "d: an unavailable field must carry a reason"

	# e. The verdict and its criteria.
	has "$body" '"verdict"' "e: verdict.json must carry a verdict"
	has "$body" '"criteria"' "e: verdict.json must carry the criteria"
	has "$body" '"complete"' "e: verdict.json must record whether the window ran"
	has "$body" '"samples"' "e: verdict.json must record the sample count"
	for needle in card-present panel-vblank vram-range module-refcount \
		module-identity module-size mem-floor log-quiet \
		counters-monotonic gates-recorded coverage; do
		has "$body" "$needle" "e: the verdict must carry the $needle criterion"
	done
	has "$body" 'n >= 2' \
		"e: coverage must demand at least two samples; one reading is not a verdict"
	has "$body" 'complete + 0 == 1' \
		"e: coverage must demand a completed window, so a cut run cannot pass"
	has "$body" 'exit 3' "e: an environment problem must exit 3"
	has "$body" 'exit 2' "e: a usage error must exit 2"
	has "$body" 'exit 130' "e: an interrupted run must exit 130"
	has "$body" 'exit 143' "e: a terminated run must exit 143"
	has "$body" 'exit 129' "e: a hung-up run must exit 129"

	# f. Output discipline.
	has "$body" 'die_env "--outdir must be under $SOAK_BASE' \
		"f: an outdir outside the scratch root must be refused"
	has "$body" '[ ! -e "$OUT" ]' \
		"f: an existing outdir must be refused, never reused"
	has "$body" '--root' \
		"f: the fixture root option must exist so the gate needs no card"
	has "$body" 'fixture' \
		"f: the fixture root must be documented as a test-only option"
	return 0
}

build_fixture() { # build_fixture DIR
	local dir=$1 dev mod
	dev=$dir/sys/bus/pci/devices/0000:01:00.0
	mod=$dir/sys/module/sm750hdmidrm
	mkdir -p "$dev" "$mod" "$dir/proc"
	printf '1024x768\n' >"$dev/active_mode"
	printf '75.00\n' >"$dev/active_mode_refresh_hz"
	printf '0\n' >"$dev/active_crtc"
	printf '1\n' >"$dev/hpd"
	printf '1\n' >"$dev/rxsense"
	printf 'connected\n' >"$dev/link_state"
	printf '5505\n' >"$dev/vblank_count"
	printf '3147008\n' >"$dev/vram_used_bytes"
	printf '16777216\n' >"$dev/vram_total_bytes"
	printf '16777216\n' >"$dev/mem_info_vram_total"
	printf '1\n' >"$dev/crc_supported"
	printf '0\n' >"$dev/b8_mode_attempts"
	printf '0\n' >"$dev/b8_mode_failures"
	printf '0\n' >"$dev/b8_mode_retries"
	printf '0\n' >"$dev/b8_stage_failures"
	printf '0\n' >"$dev/b8_i2c_write_timeouts"
	printf '0\n' >"$dev/b8_i2c_recoveries"
	printf '0\n' >"$dev/b8_ready_expired"
	printf '0\n' >"$dev/b8_ddc_grant_timeouts"
	printf '3\n' >"$dev/b8_edid_reads"
	printf '0\n' >"$dev/b8_edid_failures"
	printf '1795000000\n' >"$dev/b8_counters_epoch_s"
	printf '1\n' >"$mod/refcnt"
	printf '0.6.10\n' >"$mod/version"
	printf 'sm750hdmidrm 208896 1 - Live 0x0000000000000000\n' >"$dir/proc/modules"
	{
		printf 'MemTotal:       32000000 kB\n'
		printf 'MemAvailable:    2000000 kB\n'
	} >"$dir/proc/meminfo"
	printf 'kernel: fixture boot\n' >"$dir/dmesg.log"
	# A moving panel line: the raster runs whether or not vblank is counted,
	# so this is what keeps the liveness check honest on an idle pipe.
	cat >"$dir/sm750-regs" <<'REGS'
#!/bin/sh
printf '0x080034 PANEL_CURRENT_LINE 0x%08x\n' "$(date +%N | cut -c1-8)"
REGS
	cat >"$dir/sm750-crc" <<'CRC'
#!/bin/sh
echo '--- crc/source (supported sources)'
CRC
	chmod 0755 "$dir/sm750-regs" "$dir/sm750-crc"
	return 0
}

run_fixture() { # run_fixture ROOT OUTDIR [extra args...]
	local root=$1 out=$2
	shift 2
	"$helper" run --root "$root" --outdir "$out" --duration 2 --interval 1 "$@"
	return $?
}

verdict_of() { # verdict_of OUTDIR - the verdict string
	sed -n 's/.*"verdict": "\([A-Z]*\)".*/\1/p' "$1/verdict.json" 2>/dev/null |
		head -n 1
}

failed_of() { # failed_of OUTDIR - the failed criterion names, one per line
	sed -n 's/.*"failed_criteria": \[\(.*\)\].*/\1/p' "$1/verdict.json" 2>/dev/null |
		tr -d '"' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true
}

expect_fail() { # expect_fail NAME OUTDIR RC CRITERION
	local name=$1 out=$2 rc=$3 crit=$4 v failed
	controls=$((controls + 1))
	v=$(verdict_of "$out")
	failed=$(failed_of "$out")
	if [ "$rc" -eq 0 ]; then
		fail "$name: a planted out-of-range sample must exit non-zero, saw 0"
		return 0
	fi
	if [ "$v" != FAIL ]; then
		fail "$name: a planted out-of-range sample must be FAIL, saw '${v:-none}'"
		return 0
	fi
	case $failed in
	*"$crit"*) ok ;;
	*) fail "$name: the verdict must name $crit, saw '$(printf '%s' "$failed" | tr '\n' ' ')'" ;;
	esac
}

plant() { # plant FILE MARKER - apply one text mutation
	python3 - "$1" "$2" <<'PY'
import sys
path, mode = sys.argv[1], sys.argv[2]
text = open(path).read()
planted = {
    "chvt": '\n\tchvt 2\n',
    "vt-activate": '\n\tsh -c "printf %%s VT_ACTIVATE"\n',
    "unshare": '\n\tunshare --mount true\n',
    "dev-input": '\n\tcat /dev/input/event0 >/dev/null\n',
    "compositor": '\n\tweston --backend=headless >/dev/null\n',
    "signal": '\n\tkill -TERM 12345\n',
    "coverage": None,
}
if mode == "coverage":
    new = text.replace("n >= 2", "n >= 1")
    if new == text:
        sys.stderr.write("plant coverage: marker not found\n")
        sys.exit(1)
    open(path, "w").write(new)
    sys.exit(0)
if mode not in planted or planted[mode] is None:
    sys.stderr.write("plant: unknown mode %s\n" % mode)
    sys.exit(1)
marker = "sample_once() {"
if marker not in text:
    sys.stderr.write("plant: anchor not found\n")
    sys.exit(1)
head, tail = text.split(marker, 1)
open(path, "w").write(head + marker + planted[mode] + tail)
PY
}

control() { # control MARKER - the static arm must reject a planted helper
	local mode=$1 copy rc out
	controls=$((controls + 1))
	copy=$scratch/planted-$mode.sh
	cp "$helper" "$copy"
	if ! plant "$copy" "$mode"; then
		fail "$mode: could not plant the mutation"
		return 0
	fi
	out=$(bash "$self" --single "$copy" 2>&1)
	rc=$?
	if [ "$rc" -eq 0 ]; then
		fail "$mode: the static arm accepted a helper with $mode planted"
		return 0
	fi
	case $out in
	*FAIL:*) ok ;;
	*) fail "$mode: the rejection must print a FAIL line, saw '${out%%$'\n'*}'" ;;
	esac
}

if [ "${1:-}" = "--single" ]; then
	[ "$#" -eq 2 ] || {
		echo "usage: $0 --single FILE" >&2
		exit 2
	}
	check_static "$2"
	if [ "$failures" -ne 0 ]; then
		exit 1
	fi
	printf 'soak helper static checks passed (%s assertions)\n' "$assertions"
	exit 0
fi

scratch=$(mktemp -d "${TMPDIR}/sm750-soak-check.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

# ---------------------------------------------------------------------------
# Static arm.
# ---------------------------------------------------------------------------
check_static "$helper"
printf 'static arm: %s assertions, %s failure(s)\n' "$assertions" "$failures"

# ---------------------------------------------------------------------------
# Runtime arm: a healthy fixture must PASS, and each planted fault must FAIL.
# ---------------------------------------------------------------------------
root=$scratch/root
build_fixture "$root"

msg=$(run_fixture "$root" "$scratch/ok" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok || fail "healthy fixture: the run must exit 0, saw $rc: $msg"
[ "$(verdict_of "$scratch/ok")" = PASS ] && ok ||
	fail "healthy fixture: the verdict must be PASS, saw '$(verdict_of "$scratch/ok")'"
samples=$(awk 'NR > 1 { n++ } END { print n + 0 }' "$scratch/ok/samples.tsv" 2>/dev/null)
[ "${samples:-0}" -ge 2 ] && ok ||
	fail "healthy fixture: at least two samples are required, saw ${samples:-0}"
cols=$(awk -F'\t' 'NR == 1 { print NF }' "$scratch/ok/samples.tsv" 2>/dev/null)
rows=$(awk -F'\t' -v c="$cols" 'NF != c { bad++ } END { print bad + 0 }' \
	"$scratch/ok/samples.tsv" 2>/dev/null)
[ "${cols:-0}" -eq 29 ] && ok ||
	fail "healthy fixture: samples.tsv must carry 29 columns, saw ${cols:-0}"
[ "${rows:-1}" -eq 0 ] && ok ||
	fail "healthy fixture: $rows sample row(s) do not carry $cols columns"
crc=$(awk -F'\t' 'NR == 2 { print $15 }' "$scratch/ok/samples.tsv" 2>/dev/null)
case ${crc:-} in
unavailable:*) ok ;;
*) fail "healthy fixture: a crc cell must carry a value or an unavailable reason, saw '${crc:-}'" ;;
esac

# The status subcommand must read a finished run back and agree with it.
if "$helper" status "$scratch/ok" >/dev/null 2>&1; then ok; else
	fail "status: a PASS run must be readable back with a zero exit status"
fi

# A fault line that was already in the buffer before the window began cannot
# fail the run: the helper counts deltas, not totals.
cp -a "$root" "$scratch/root-dirty"
printf 'kernel: WARNING: pre-existing fixture noise\n' >>"$scratch/root-dirty/dmesg.log"
run_fixture "$scratch/root-dirty" "$scratch/dirty" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok ||
	fail "baseline: a fault already in the buffer must not fail a run, saw exit $rc"
[ "$(verdict_of "$scratch/dirty")" = PASS ] && ok ||
	fail "baseline: the verdict must stay PASS when no new fault line appeared"

# A driver fault line logged during the window must fail it.
cp -a "$root" "$scratch/root-live"
"$helper" run --root "$scratch/root-live" --outdir "$scratch/live" \
	--duration 3 --interval 1 >/dev/null 2>&1 &
live_pid=$!
sleep 1
printf 'kernel: sm750hdmidrm 0000:01:00.0: flip_done timed out\n' \
	>>"$scratch/root-live/dmesg.log"
wait "$live_pid"
rc=$?
[ "$rc" -ne 0 ] && ok ||
	fail "delta: a driver fault logged during the window must fail the run"
[ "$(verdict_of "$scratch/live")" = FAIL ] && ok ||
	fail "delta: the verdict must be FAIL after a new driver fault line"

# Each planted out-of-range field: FAIL, non-zero exit, and the criterion named.
cp -a "$root" "$scratch/root-vram"
printf '99999999999\n' >"$scratch/root-vram/sys/bus/pci/devices/0000:01:00.0/vram_used_bytes"
run_fixture "$scratch/root-vram" "$scratch/vram" >/dev/null 2>&1
expect_fail "vram" "$scratch/vram" "$?" vram-range

cp -a "$root" "$scratch/root-ref"
printf '17\n' >"$scratch/root-ref/sys/module/sm750hdmidrm/refcnt"
run_fixture "$scratch/root-ref" "$scratch/ref" >/dev/null 2>&1
expect_fail "refcount" "$scratch/ref" "$?" module-refcount

cp -a "$root" "$scratch/root-mem"
printf 'MemAvailable:       1024 kB\n' >"$scratch/root-mem/proc/meminfo"
run_fixture "$scratch/root-mem" "$scratch/mem" >/dev/null 2>&1
expect_fail "mem-floor" "$scratch/mem" "$?" mem-floor

cp -a "$root" "$scratch/root-b8"
printf '0\n' >"$scratch/root-b8/sys/bus/pci/devices/0000:01:00.0/b8_edid_reads"
printf '5\n' >"$scratch/root-b8/sys/bus/pci/devices/0000:01:00.0/b8_mode_attempts"
"$helper" run --root "$scratch/root-b8" --outdir "$scratch/b8" \
	--duration 3 --interval 1 >/dev/null 2>&1 &
b8_pid=$!
sleep 1
printf '0\n' >"$scratch/root-b8/sys/bus/pci/devices/0000:01:00.0/b8_mode_attempts"
wait "$b8_pid"
expect_fail "counters" "$scratch/b8" "$?" counters-monotonic

# An interrupted run is never PASS, and it exits with the signal's status.
"$helper" run --root "$root" --outdir "$scratch/cut" \
	--duration 30 --interval 1 >/dev/null 2>&1 &
cut_pid=$!
sleep 2
kill -TERM "$cut_pid" 2>/dev/null
wait "$cut_pid"
rc=$?
[ "$rc" -ne 0 ] && ok || fail "interrupt: a cut run must not exit 0"
[ "$(verdict_of "$scratch/cut")" = FAIL ] && ok ||
	fail "interrupt: a cut run must be FAIL, never PASS"
case $(failed_of "$scratch/cut") in
*coverage*) ok ;;
*) fail "interrupt: the verdict must fail on coverage" ;;
esac

# ---------------------------------------------------------------------------
# Planted controls: the static arm must reject each forbidden construct.
# ---------------------------------------------------------------------------
control chvt
control vt-activate
control unshare
control dev-input
control compositor
control signal
control coverage

printf 'soak helper checks passed (%s assertions, %s planted controls)\n' \
	"$assertions" "$controls"
if [ "$failures" -ne 0 ]; then
	exit 1
fi
exit 0
