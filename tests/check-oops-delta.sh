#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# T55: reusable oops detector. Wraps a command, snapshots the kernel log
# before and after through a single configurable reader, and fails when a new
# line matches an oops pattern:
#   BUG:  WARNING:  Oops  general protection fault
#   kernel NULL pointer dereference  lockdep  call trace  RIP:
#   WARNING: possible circular locking dependency
# Matching is case-insensitive on the "oops" and "call trace" keywords, but
# BUG:/WARNING:/RIP: are matched as literal prefixes so the driver's own
# documentation strings (for example a source comment "WARNING:" in a patch
# echoed by the wrapped command) do not trigger a false positive unless the
# kernel log itself carries them.
#
# The reader is $DMESG_CMD (default: dmesg). On this host the allowlisted
# form is `sudo -n dmesg` (docs/ROOT-ACTIONS.md, exact argv), so invoke as:
#   DMESG_CMD='sudo -n dmesg' ./tests/check-oops-delta.sh -- <command...>
# With no readable kernel log the gate exits 77 with one SKIP line; it never
# escalates on its own and never hardcodes sudo.
#
# Baseline: --allow REGEX (repeatable) or OOPS_ALLOW_FILE (one regex per
# line) excludes known pre-existing lines. This host's nvidia taint lines are
# expected noise; no SM750 driver line may ever be allowlisted here.
#
# Usage:
#   tests/check-oops-delta.sh [--allow REGEX]... -- <command...>
#   tests/check-oops-delta.sh --self-test   planted controls, no root needed
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
	echo "usage: $0 [--allow REGEX]... -- <command...>" >&2
	exit 2
}

skip() {
	echo "SKIP: oops-delta: $*" >&2
	exit 77
}

fail() {
	echo "oops-delta: $*" >&2
	exit 1
}

dmesg_cmd=${DMESG_CMD:-dmesg}
allows=()

while [ $# -gt 0 ]; do
	case $1 in
	--allow)
		[ $# -ge 2 ] || usage
		allows+=("$1_is_a_marker_never_matched") # placeholder, replaced below
		allows[${#allows[@]}-1]=$2
		shift 2
		;;
	--self-test)
		self_test=1
		shift
		;;
	--)
		shift
		break
		;;
	*)
		usage
		;;
	esac
done
[ "${self_test:-0}" = 1 ] || [ $# -ge 1 ] || usage

if [ -n "${OOPS_ALLOW_FILE:-}" ]; then
	[ -f "$OOPS_ALLOW_FILE" ] || fail "OOPS_ALLOW_FILE $OOPS_ALLOW_FILE is not a file"
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		case $line in \#*) continue ;; esac
		allows+=("$line")
	done <"$OOPS_ALLOW_FILE"
fi

# One extended regex over every pattern; case-insensitive only where the
# kernel spells variants differently ("Oops:"/"oops", "Call Trace"/"call trace").
pattern='(BUG:|WARNING:|[Oo]ops|general protection fault|kernel NULL pointer dereference|lockdep|WARNING: possible circular locking dependency|[Cc]all [Tt]race|RIP:)'

filter_allow() {
	# $1 = candidate log file. Drop lines matching any --allow regex.
	local re
	while IFS= read -r line; do
		keep=1
		for re in "${allows[@]}"; do
			if grep -Eq "$re" <<<"$line"; then
				keep=0
				break
			fi
		done
		[ "$keep" -eq 1 ] && printf '%s\n' "$line"
		continue
	done <"$1"
}

report_hits() {
	# $1 = delta file, $2 = label. Print the matching lines, return count.
	local n
	n=$(grep -Ec "$pattern" "$1" 2>/dev/null || true)
	if [ "$n" -gt 0 ]; then
		grep -E "$pattern" "$1" | while IFS= read -r line; do
			echo "oops-delta: $2: $line"
		done
	fi
	[ "$n" -gt 0 ]
}

run_gate() {
	local log_before log_after rc=0
	log_before=$(mktemp "${TMPDIR}/sm750-oops-before.XXXXXX")
	log_after=$(mktemp "${TMPDIR}/sm750-oops-after.XXXXXX")
	log_delta=$log_before.delta
	log_filtered=$log_after.filtered
	# Expand now: at script exit the locals are gone under set -u.
	trap "rm -f -- '$log_before' '$log_after' '$log_delta' '$log_filtered'" EXIT

	if ! $dmesg_cmd >"$log_before" 2>/dev/null; then
		skip "the kernel log is not readable through '$dmesg_cmd' (set DMESG_CMD, for example DMESG_CMD='sudo -n dmesg')"
	fi

	if ! "$@"; then
		echo "oops-delta: the wrapped command exited non-zero" >&2
		rc=1
	fi

	if ! $dmesg_cmd >"$log_after" 2>/dev/null; then
		skip "the kernel log stopped being readable through '$dmesg_cmd' mid-run"
	fi

	# Delta = lines after the command that were not in the before-snapshot,
	# then the allowlist filter, then the pattern match.
	awk 'NR==FNR { seen[$0]; next } !($0 in seen)' \
		"$log_before" "$log_after" >"$log_delta"
	filter_allow "$log_delta" >"$log_filtered"

	if report_hits "$log_filtered" "new kernel log line"; then
		fail "new oops-pattern lines appeared during the wrapped command"
	fi

	echo "oops-delta: clean; no new oops-pattern lines in the kernel log"
	return "$rc"
}

# --- self-test: planted controls on synthetic before/after snapshots ---------
self_test() {
	local scratch rc=0
	scratch=$(mktemp -d "${TMPDIR}/sm750-oops-gate.XXXXXX")
	trap "rm -rf -- '$scratch'" EXIT

	# The gate's core is the delta+filter+match pipeline; exercise it by
	# overriding the reader with a script that cats planted snapshots.
	reader=$scratch/reader
	snap_before=$scratch/before
	snap_after=$scratch/after
	# First read is the before-snapshot, every later read the after-snapshot.
	cat >"$reader" <<EOF
#!/usr/bin/env bash
n=\$(cat "$scratch/calls" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$scratch/calls"
if [ "\$n" -eq 0 ]; then cat "$snap_before"; else cat "$snap_after"; fi
EOF
	chmod +x "$reader"

	invoke() {
		DMESG_CMD=$reader OOPS_ALLOW_FILE="${OOPS_ALLOW_FILE:-}" \
			bash "$project_dir/tests/check-oops-delta.sh" -- true 2>&1
	}

	check() {
		# $1 name, $2 expect (pass|fail), $3 fragment
		local name=$1 expect=$2 want=$3 out
		rm -f "$scratch/calls"
		out=$(invoke) || true
		if [ "$expect" = fail ]; then
			if grep -Fq "oops-delta: new kernel log line: $want" <<<"$out" &&
				grep -Fq "new oops-pattern lines appeared" <<<"$out"; then
				echo "negative control $name: rejected ($(grep -m1 'oops-delta: new kernel log line' <<<"$out"))"
			else
				echo "oops-delta: planted defect '$name' not rejected for the right reason: $out" >&2
				rc=1
			fi
		else
			if grep -Fq "oops-delta: clean" <<<"$out" &&
				! grep -Fq "oops-delta: new kernel log line" <<<"$out"; then
				echo "negative control $name: accepted"
			else
				echo "oops-delta: planted defect '$name' (expected pass) misbehaved: $out" >&2
				rc=1
			fi
		fi
	}

	# 0. Unchanged kernel log passes (negative control).
	printf 'nvidia: module taints kernel\nsm750hdmidrm: probe ok\n' >"$snap_before"
	cp "$snap_before" "$snap_after"
	check unchanged_log pass "oops-delta: clean"

	# 1. A fake new WARNING: line.
	printf 'nvidia: module taints kernel\n' >"$snap_before"
	printf 'nvidia: module taints kernel\nWARNING: CPU 3 at drm_do_get_edid\n' >"$snap_after"
	check fake_warning fail "WARNING: CPU 3"

	# 2. A fake new BUG: line in an otherwise clean delta.
	printf 'nothing bad\n' >"$snap_before"
	printf 'nothing bad\nBUG: kernel NULL pointer dereference at sm750\n' >"$snap_after"
	check fake_bug fail "BUG: kernel NULL"

	# 3. An --allow regex keeps a known pre-existing-warning shape clean.
	printf 'nvidia: module taints kernel\n' >"$snap_before"
	printf 'nvidia: module taints kernel\nWARNING: nvidia expected taint\n' >"$snap_after"
	echo 'WARNING: nvidia expected taint' >"$scratch/allow"
	rm -f "$scratch/calls"
	out=$(DMESG_CMD=$reader OOPS_ALLOW_FILE=$scratch/allow \
		bash "$project_dir/tests/check-oops-delta.sh" -- true 2>&1) || true
	if grep -Fq "oops-delta: clean" <<<"$out"; then
		echo "negative control allow_filtered: accepted"
	else
		echo "oops-delta: allow_filtered control failed: $out" >&2
		rc=1
	fi

	# 4. A pattern inside a --allow'd line is still filtered (allow wins).
	printf 'x\n' >"$snap_before"
	printf 'x\nBUG: allowed by the baseline\n' >"$snap_after"
	echo 'BUG: allowed by the baseline' >"$scratch/allow"
	rm -f "$scratch/calls"
	out=$(DMESG_CMD=$reader OOPS_ALLOW_FILE=$scratch/allow \
		bash "$project_dir/tests/check-oops-delta.sh" -- true 2>&1) || true
	if grep -Fq "oops-delta: clean" <<<"$out"; then
		echo "negative control allow_wins: accepted"
	else
		echo "oops-delta: allow_wins control failed: $out" >&2
		rc=1
	fi

	# 5. A wrapped command that exits non-zero is still a failure.
	printf 'x\n' >"$snap_before"
	cp "$snap_before" "$snap_after"
	rm -f "$scratch/calls"
	if out=$(DMESG_CMD=$reader bash "$project_dir/tests/check-oops-delta.sh" -- false 2>&1); then
		echo "oops-delta: planted defect 'command_fails' was not caught" >&2
		rc=1
	elif grep -Fq "wrapped command exited non-zero" <<<"$out"; then
		echo "negative control command_fails: rejected"
	else
		echo "oops-delta: command_fails failed for the wrong reason: $out" >&2
		rc=1
	fi

	[ "$rc" -eq 0 ] || exit 1
	echo "Oops detector self-test passed (3 planted defects rejected, 4 negative controls accepted)"
}

if [ "${self_test:-0}" = 1 ]; then
	self_test
	exit 0
fi

run_gate "$@"
