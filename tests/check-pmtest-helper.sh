#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Static gate for tools/sm750-pmtest.sh, the operator helper installed as
# /usr/local/sbin/sm750-pmtest and allowlisted in docs/ROOT-ACTIONS.md section
# 3.14. The helper runs one host-wide suspend cycle through /sys/power/pm_test
# and must always write the test mode back to `none`: a forgotten level is a
# global that turns every later real suspend into a test until reboot, and the
# fingerprint is the line `suspend debug: Waiting for`. The properties this gate
# pins are the ones that keep that window closed and the verdict honest: a root
# check before any write, a level validated against an explicit list, `none`
# written by the EXIT trap, a readback after every write, a journal snapshot
# taken before the freeze, a verdict that needs both completion lines, and no
# use of the absent fb0 as a success criterion.
#
# Nothing here runs the helper, writes sysfs, suspends or needs root: the gate
# reads the script text and parses it with sh -n.
#
# Usage: tests/check-pmtest-helper.sh [script]
#        tests/check-pmtest-helper.sh --self-test
#        tests/check-pmtest-helper.sh --single [script]   (no planted controls)
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
helper=${1:-$project_dir/tools/sm750-pmtest.sh}

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

scratch=$(mktemp -d "${TMPDIR}/sm750-pmtest-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

has() { # has TEXT PATTERN MESSAGE
	case $1 in
	*"$2"*) ;;
	*) bad "$3" ;;
	esac
}

# lineno TEXT - the line of the first literal occurrence, 0 when absent
lineno() {
	printf '%s\n' "$2" | grep -nF -e "$1" | head -n 1 | cut -d: -f1
}

# func NAME - the body of a shell function, indentation stripped and comment
# lines dropped, so a call is checked where it is executed. A function may be
# defined as `name() {` or `name()` with `{` on the next line, so the brace is
# not required on the same line.
func() {
	awk -v want="$2" '
		{ line = $0; sub(/^[ \t]+/, "", line) }
		infn && $0 == "}" { exit }
		infn && line != "" && line !~ /^#/ { print }
		!infn && $0 ~ ("^" want "\\(\\)") { infn = 1 }
	' "$1"
}

# subfn NAME - a function defined inside another one, such as cleanup inside
# run_cmd; the closing brace of that inner function is indented.
subfn() {
	awk -v want="$2" '
		{ line = $0; sub(/^[ \t]+/, "", line) }
		infn && line == "}" { exit }
		infn && line != "" && line !~ /^#/ { print }
		!infn && line ~ ("^" want "\\(\\)") { infn = 1 }
	' "$1"
}

# --- a. the file exists, is a POSIX sh script and parses ---------------------
if [ ! -f "$helper" ]; then
	bad "a: $helper does not exist"
	echo "PM test helper: 0 assertions held, the script is missing" >&2
	exit 1
fi
has "$(head -n 1 "$helper")" '#!/bin/sh' \
	"a: the shebang must be #!/bin/sh, not a bash script"
if ! sh -n "$helper" 2>"$scratch/sh-n.err"; then
	bad "a: sh -n rejects $helper: $(head -n 1 "$scratch/sh-n.err")"
fi
ok "a. the helper exists, starts with #!/bin/sh and passes sh -n"

body=$(cat "$helper")
# The run body, for ordering checks: the reset/status paths legitimately mention
# the same files, so an ordering test against the whole file would compare the
# trap against the success path.
runbody=$(func "$helper" run_cmd)

# --- b. three subcommands, everything else reaches usage ---------------------
has "$body" 'run [level] | status | reset' \
	"b: the usage must name exactly run, status and reset"
has "$body" '*) usage ;;' \
	"b: an unknown subcommand must fall through to usage, not to a default action"
has "$body" 'exit 2' \
	"b: the usage path must exit 2 so a wrong subcommand cannot read as a run"
# Extra or unknown arguments must reach usage: run takes at most one level,
# status and reset take none.
has "$body" '[ "$#" -le 1 ] || usage' \
	"b: run must reject more than one argument with usage"
has "$body" '[ "$#" -eq 0 ] || usage' \
	"b: status and reset must reject any argument with usage"
ok "b. run, status and reset dispatch, anything else exits 2"

# --- c. the level is validated against an explicit list ---------------------
has "$body" 'none|core|processors|platform|devices|freezer' \
	"c: the level must be validated against the explicit accepted list"
has "$body" '*) usage ;;' \
	"c: an unknown level must reach usage, not be written to pm_test"
ok "c. the level is validated against the explicit list before any write"

# --- d. root is required before the first write -----------------------------
has "$(func "$helper" require_root)" '[ "$(id -u)" -eq 0 ]' \
	"d: the helper must check that it is root"
has "$(func "$helper" require_root)" 'must run as root' \
	"d: the root refusal must name the problem"
# In run_cmd the root check must precede the first write to pm_test.
root_line=$(lineno 'require_root' "$runbody")
first_write=$(lineno '> "$PMTEST"' "$runbody")
if [ -z "$root_line" ] || [ -z "$first_write" ]; then
	bad "d: run must call require_root and write pm_test"
elif [ "$root_line" -ge "$first_write" ]; then
	bad "d: the root check at line $root_line must precede the first pm_test write at line $first_write"
fi
ok "d. the root check runs before the first write to pm_test"

# --- e. the EXIT trap always writes none, and every write is read back ------
has "$body" 'trap' "e: an EXIT trap must exist"
has "$body" 'EXIT' "e: the trap must fire on EXIT"
trap_body=$(subfn "$helper" cleanup)
has "$trap_body" 'printf '"'"'none\n'"'"' > "$PMTEST"' \
	"e: the EXIT trap must write none to pm_test"
has "$trap_body" 'read_pm_test' \
	"e: the EXIT trap must read pm_test back"
has "$trap_body" 'readback after cleanup' \
	"e: the EXIT trap must print the readback"
has "$body" 'trap '"'"'cleanup; exit $?'"'"' EXIT' \
	"e: the EXIT trap must run cleanup and keep the status"
# The trap is armed before the level is written, so an interrupt during the
# write is still covered.
trap_line=$(lineno 'trap '"'"'cleanup; exit $?'"'"' EXIT' "$runbody")
arm_write=$(lineno 'printf '"'"'%s\n'"'"' "$level" > "$PMTEST"' "$runbody")
if [ -z "$trap_line" ] || [ -z "$arm_write" ]; then
	bad "e: run must arm the EXIT trap and write the level"
elif [ "$trap_line" -ge "$arm_write" ]; then
	bad "e: the EXIT trap at line $trap_line must be armed before the level write at line $arm_write"
fi
# The readback after the level write is the confirmation, not the value written.
has "$runbody" 'readback: %s' \
	"e: the armed level must be read back and printed"
has "$(func "$helper" read_pm_test)" 'cat "$PMTEST"' \
	"e: the readback must come from the pm_test file itself"
readbody=$(func "$helper" read_pm_test)
has "$readbody" '[^]]' \
	"e: the readback must parse the bracketed level list ([none] core ...), not the whole line"
has "$readbody" "awk 'NF { print \$1; exit }'" \
	"e: the readback must fall back to the first field of a plain single-value file"
ok "e. the EXIT trap always writes none and every write is read back"

# --- e2. the parser finds the bracketed level wherever the kernel puts it ---
# The kernel brackets the current level in the list, and the bracket is at the
# start of the line only when that level is the first entry, so a line-anchored
# match reads the first field for every other level. The real function body is
# extracted and run against fixtures; the parse is not duplicated here.
{
	printf '#!/bin/sh\n'
	printf 'read_pm_test() {\n'
	func "$helper" read_pm_test
	printf '}\n'
	printf 'read_pm_test\n'
} > "$scratch/read_pm_test.sh"

resolve_pm_test() { # TEXT - the level the helper's own parser resolves
	printf '%s\n' "$1" > "$scratch/pm_test.fixture"
	PMTEST=$scratch/pm_test.fixture sh "$scratch/read_pm_test.sh"
}

for want_case in \
	'none core processors platform [devices] freezer|devices' \
	'none core processors platform devices [freezer]|freezer' \
	'[none] core processors platform devices freezer|none'
do
	want_text=${want_case%|*}
	want_level=${want_case##*|}
	got_level=$(resolve_pm_test "$want_text")
	[ "$got_level" = "$want_level" ] ||
		bad "e2: '$want_text' resolved to '$got_level', not '$want_level': the bracket may sit anywhere in the list"
done
ok "e2. read_pm_test resolves the bracketed level wherever it sits in the list"

# --- e3. a bracket-free file keeps the single-value fallback ----------------
# The first-field fallback exists only for a file with no brackets at all; an
# unreadable file must still yield ?, never an empty level.
if [ "$(resolve_pm_test 'none')" != none ]; then
	bad "e3: a bracket-free 'none' must resolve to none, got '$(resolve_pm_test 'none')'"
fi
if [ "$(PMTEST=$scratch/no-such-pm_test sh "$scratch/read_pm_test.sh")" != '?' ]; then
	bad "e3: an unreadable pm_test must resolve to ?, got '$(PMTEST=$scratch/no-such-pm_test sh "$scratch/read_pm_test.sh")'"
fi
ok "e3. a bracket-free single value resolves and an unreadable file yields ?"

# --- e4. the armed line is printed after its readback is taken --------------
# The armed line reports a measured value, so the readback assignment must come
# first; printing it before the read is the false-success shape this pins out.
readback_line=$(lineno 'got=$(read_pm_test)' "$runbody")
armed_line=$(lineno 'pm_test armed at %s (readback: %s)' "$runbody")
if [ -z "$readback_line" ] || [ -z "$armed_line" ]; then
	bad "e4: run must read the level back and print it"
elif [ "$readback_line" -ge "$armed_line" ]; then
	bad "e4: the readback at line $readback_line must precede the armed line at line $armed_line"
fi
ok "e4. the armed line is printed only after the level has been read back"

# --- e5. the two empty journal cases are named apart ------------------------
# status once printed the permission hint both when journalctl failed and when
# a readable journal held no driver `pm: ` line, sending the operator after a
# permission problem that did not exist. The decision is extracted into
# pm_log_block and exercised against a stub journalctl, never the real log.
{
	printf '#!/bin/sh\n'
	printf 'journalctl() {\n'
	printf '\tcat "${STUB_LOG:-/dev/null}" 2>/dev/null\n'
	printf '\treturn "${STUB_RC:-0}"\n'
	printf '}\n'
	printf 'pm_log_block() {\n'
	func "$helper" pm_log_block
	printf '}\n'
	printf 'pm_log_block\n'
} > "$scratch/pm_log_block.sh"

readable=$scratch/pm_log_readable.txt
printf '%s\n' \
	'clocksource: acpi_pm: timekeeping: ...' \
	'sm750hdmidrm 0000:01:00.0: probe ok' > "$readable"

no_lines=$(STUB_LOG=$readable STUB_RC=0 sh "$scratch/pm_log_block.sh")
case $no_lines in
*'no sm750 pm: line'*) ;;
*) bad "e5: a readable log with no driver pm: line must say so, got '$no_lines'" ;;
esac
case $no_lines in
*'needs root'*) bad "e5: a readable log must not claim the kernel log needs root" ;;
esac
ok "e5. a readable log with no driver pm: line names that, not permissions"

unreadable=$(STUB_RC=1 sh "$scratch/pm_log_block.sh")
case $unreadable in
*'needs root'*) ;;
*) bad "e6: a failing journalctl must keep the permission hint, got '$unreadable'" ;;
esac
case $unreadable in
*'no sm750 pm: line'*) bad "e6: a failing journalctl must not claim the log was read" ;;
esac
empty=$(STUB_RC=0 sh "$scratch/pm_log_block.sh")
case $empty in
*'needs root'*) ;;
*) bad "e6: an empty journal must keep the permission hint, got '$empty'" ;;
esac
ok "e6. a failing or empty journalctl keeps the permission hint"

hit=$scratch/pm_log_hit.txt
printf '%s\n' 'sm750hdmidrm 0000:01:00.0: pm: suspend entry' > "$hit"
hit_out=$(STUB_LOG=$hit STUB_RC=0 sh "$scratch/pm_log_block.sh")
[ "$hit_out" = '  sm750hdmidrm 0000:01:00.0: pm: suspend entry' ] ||
	bad "e7: a driver pm: line must print indented and unchanged, got '$hit_out'"
ok "e7. a driver pm: line still prints indented, byte-compatible with status"

# --- f. the journal snapshot is taken before the freeze write ---------------
has "$runbody" 'journal_before=' "f: the journal length must be snapshotted"
has "$body" 'journalctl -k -b --no-pager' \
	"f: the kernel log must be read through journalctl"
snap_line=$(lineno 'journal_before=' "$runbody")
freeze_line=$(lineno 'echo freeze > "$STATE"' "$runbody")
if [ -z "$snap_line" ] || [ -z "$freeze_line" ]; then
	bad "f: run must snapshot the journal and write freeze to state"
elif [ "$snap_line" -ge "$freeze_line" ]; then
	bad "f: the journal snapshot at line $snap_line must precede the freeze at line $freeze_line"
fi
# Only lines added after the snapshot are collected.
has "$runbody" 'journal_before + 1' \
	"f: only journal lines added since the snapshot may be collected"
ok "f. the journal snapshot is taken before the freeze and only the delta is read"

# --- g. the verdict needs both completion lines and no failure --------------
has "$runbody" 'pm: suspend complete' \
	"g: the verdict must look for 'pm: suspend complete'"
has "$runbody" 'pm: resume complete' \
	"g: the verdict must look for 'pm: resume complete'"
has "$runbody" 'pm: (suspend|resume) failed' \
	"g: the verdict must look for a failure line"
has "$runbody" '[ "$suspend_complete" -ge 1 ] || ok_all=0' \
	"g: a missing suspend-complete line must fail the verdict"
has "$runbody" '[ "$resume_complete" -ge 1 ] || ok_all=0' \
	"g: a missing resume-complete line must fail the verdict"
has "$runbody" '[ "$failed" -eq 0 ] || ok_all=0' \
	"g: a failure line must fail the verdict"
has "$runbody" 'stats_same' \
	"g: a suspend_stats error-counter change must fail the verdict"
statsbody=$(func "$helper" stats_errors)
has "$statsbody" 'failed_suspend_noirq' \
	"g: the error counters must be read from the suspend_stats directory entries"
has "$statsbody" '-e "$STATS/$name"' \
	"g: each suspend_stats counter must be read from its own file"
has "$statsbody" 'last_failed_step' \
	"g: the last_failed_* counters must be compared too"
has "$(func "$helper" status_cmd)" '-d "$STATS"' \
	"g: status must print the suspend_stats directory, not sed a directory"
ok "g. the verdict requires both completion lines, no failure and unchanged stats"

# --- h. fb0 is never a success criterion ------------------------------------
# A comment may explain why fb0 is absent; executed text may not name it.
if grep -nE '/dev/fb|/sys/class/graphics|fb0' "$helper" |
	grep -vE ':[[:space:]]*#' >"$scratch/fb.hit"; then
	bad "h: fb0 or /dev/fb is used as a success criterion: $(head -n 1 "$scratch/fb.hit")"
fi
ok "h. fb0, /dev/fb* and /sys/class/graphics are never used"

# --- i. the no-S3 explanation is in the usage text -------------------------
usagebody=$(func "$helper" usage)
has "$usagebody" 'no S3' "i: the usage must explain that the host has no S3"
has "$usagebody" 's2idle' "i: the usage must name the s2idle state"
has "$usagebody" 'freeze' "i: the usage must name freeze as the correct spelling"
has "$usagebody" 'D3hot' "i: the usage must name platform as the D3-capable level"
has "$usagebody" 'devices' "i: the usage must name the default level"
has "$body" 'Waiting for' \
	"i: the usage or the warning must name the forgotten-level fingerprint"
ok "i. the usage explains the absent S3, s2idle, freeze, D3hot and the fingerprint"

[ "$fail" -eq 0 ] || exit 1

if [ "$single" -eq 1 ]; then
	printf 'PM test helper assertions passed (%s)\n' "$helper"
	exit 0
fi

printf 'ok: j. helper structure checked\n'
assertions=$((assertions + 1))

# --- planted controls -------------------------------------------------------
# Each mutation removes exactly one of the guarantees asserted above; the gate
# must reject every one with a message naming the missing guarantee.
plant_trap_removed() { # an interrupted run leaves pm_test armed
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = "trap 'cleanup; exit $?' EXIT\n"
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_level_validation_removed() { # any string is written to pm_test
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = "\tnone|core|processors|platform|devices|freezer) ;;\n"
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, "\t*) ;;\n"))
MUT
}
plant_readback_removed() { # the armed level is trusted, not read back
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\tgot=$(read_pm_test)\n'
       "\tprintf '%s: pm_test armed at %s (readback: %s)\\n' \"$PROG\" \"$level\" \"$got\"\n"
       '\t[ "$got" = "$level" ] || {\n'
       '\t\techo "$PROG: pm_test did not read back $level (got \'$got\')" >&2\n'
       '\t\texit 1\n'
       '\t}\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_verdict_without_completion() { # PASS without both completion lines
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\t[ "$suspend_complete" -ge 1 ] || ok_all=0\n'
       '\t[ "$resume_complete" -ge 1 ] || ok_all=0\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}
plant_stats_file_only() { # suspend_stats is a directory, so grep on it reads nothing
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\tfor name in fail failed_freeze failed_prepare failed_suspend \\\n'
       '\t\tfailed_suspend_late failed_suspend_noirq failed_resume \\\n'
       '\t\tfailed_resume_early failed_resume_noirq last_failed_dev \\\n'
       '\t\tlast_failed_errno last_failed_step; do\n'
       '\t\t[ -e "$STATS/$name" ] || continue\n'
       '\t\tprintf \'%s=%s\\n\' "$name" "$(cat "$STATS/$name" 2>/dev/null || echo \'?\')"\n'
       '\tdone\n')
assert s.count(old) == 1, s.count(old)
new = "\tgrep -E '^(fail|failed_|last_failed)' \"$STATS\" 2>/dev/null || true\n"
open(p, 'w').write(s.replace(old, new))
MUT
}
plant_journal_snapshot_removed() { # the whole log is read, not the delta
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\tjournal_before=$(journal_lines)\n'
       '\tcase $journal_before in\n'
       "\t''|*[!0-9]*) echo \"$PROG: could not snapshot the kernel log\" >&2; exit 1 ;;\n"
       '\tesac\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, ''))
MUT
}

plant_pmtest_readback_line_anchored() { # the bracket only matches at line start
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\tcur=$(printf \'%s\\n\' "$raw" | sed -n \'s/.*\\[\\([^]]*\\)\\].*$/\\1/p\')\n')
assert s.count(old) == 1, s.count(old)
open(p, 'w').write(s.replace(old, old.replace('s/.*\\[', 's/^\\[')))
MUT
}
plant_pmtest_armed_before_readback() { # the armed line is printed before the read
	python3 - "$1" <<'MUT'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('\tgot=$(read_pm_test)\n'
       "\tprintf '%s: pm_test armed at %s (readback: %s)\\n' \"$PROG\" \"$level\" \"$got\"\n")
assert s.count(old) == 1, s.count(old)
new = ("\tprintf '%s: pm_test armed at %s (readback: %s)\\n' \"$PROG\" \"$level\" \"$got\"\n"
       '\tgot=$(read_pm_test)\n')
open(p, 'w').write(s.replace(old, new))
MUT
}

control() {
	local name=$1
	local planted=$scratch/sm750-pmtest.sh
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

control trap-removed plant_trap_removed
control level-validation-removed plant_level_validation_removed
control readback-removed plant_readback_removed
control readback-line-anchored plant_pmtest_readback_line_anchored
control armed-before-readback plant_pmtest_armed_before_readback
control verdict-without-completion plant_verdict_without_completion
control journal-snapshot-removed plant_journal_snapshot_removed
control stats-file-only plant_stats_file_only

# The pristine copy must still pass, otherwise the controls prove nothing.
cp "$helper" "$scratch/pristine.sh"
if ! bash "$0" --single "$scratch/pristine.sh" >/dev/null 2>"$scratch/pristine.err"; then
	bad "j: the unmutated copy was rejected: $(head -n 1 "$scratch/pristine.err")"
fi
printf 'negative control pristine: accepted\n'

[ "$fail" -eq 0 ] || exit 1
controls=8
if [ "$self_test" -eq 1 ]; then
	printf 'PM test helper checks passed (%s assertions, %s planted controls, self-test)\n' "$assertions" "$controls"
else
	printf 'PM test helper checks passed (%s assertions, %s planted controls)\n' "$assertions" "$controls"
fi
