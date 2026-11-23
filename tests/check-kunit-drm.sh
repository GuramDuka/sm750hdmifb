#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# T55: DRM KUnit sweep. Fedora does not ship tools/testing/selftests/drm; the
# equivalent coverage lives in the DRM KUnit test modules of the
# kernel-modules-internal package (CONFIG_DRM_KUNIT_TEST=m,
# CONFIG_KUNIT_AUTORUN_ENABLED=y, CONFIG_KUNIT_DEFAULT_TIMEOUT=300). The gate
# discovers them under
#   /lib/modules/$(uname -r)/internal/drivers/gpu/drm/tests/
# so a new kernel with more tests is swept without editing this file, and it
# asserts a floor so a silently empty directory fails instead of passing.
#
# How a suite is run: modprobe <basename>, which loads the suite and its
# support modules through modules.dep; CONFIG_KUNIT_AUTORUN_ENABLED=y makes
# KUnit run it at init. Nothing else is needed - no kunit.py, no debugfs. The
# KTAP results go to the kernel log, so the gate reads them through
# $DMESG_CMD (default: dmesg). Measured real output for one suite (drm_rect,
# 2026-11-22) is:
#
#   [ time] KTAP version 1
#   [ time] 1..1
#   [ time]     KTAP version 1
#   [ time]     # Subtest: drm_rect          <- suite name drops the _test suffix
#   [ time]     # module: drm_rect_test      <- stable per-suite marker
#   [ time]     1..9
#   [ time]     ok 1 drm_test_rect_clip_scaled_div_by_zero
#   [ time]     # Totals: pass:43 fail:0 skip:0 total:43
#   [ time] ok 1 drm_rect
#
# The gate parses "# module:", "ok N name", "not ok N name" (leading
# whitespace before "not ok" is normal for nested subtests, and the " - "
# dash is optional) and "# Totals: pass:N fail:N skip:N". A delta can hold
# MORE THAN ONE "# Totals:" line (drm_bridge_test prints four top-level
# entries in one load), so all of them must report fail:0 and the reported
# counts are the aggregate. Every suite is unloaded in an EXIT trap on every
# path, so no test module is left resident.
#
# Root: modprobe of an internal test module needs root, and the gate never
# escalates on its own. Two ways to run it:
#   - as root:            sudo ./tests/check-kunit-drm.sh
#   - unprivileged with an allowlisted modprobe prefix (this host grants
#     "/usr/bin/modprobe <name>" and "/usr/bin/modprobe -r <name>" for each
#     suite, and "/usr/bin/modprobe -r kunit"; docs/ROOT-ACTIONS.md 3.9/3.10):
#       MODPROBE_CMD='sudo -n /usr/bin/modprobe' DMESG_CMD='sudo -n dmesg' \
#         ./tests/check-kunit-drm.sh
# With neither, one SKIP line and exit 77.
#
# KUnit must also be enabled at runtime. This host's kernel has
# "# CONFIG_KUNIT_DEFAULT_ENABLED is not set", so kunit loads with
# enable=false and every suite prints only "KTAP version 1 / 1..1 /
# kunit: disabled" with no subtest. The gate treats that as an unavailable
# runner (SKIP, exit 77) and names the prerequisite instead of passing: the
# owner adds "options kunit enable=1" to /etc/modprobe.d/ (or kunit.enable=1
# on the kernel command line); see docs/ROOT-ACTIONS.md section 3.10.
#
# Usage:
#   tests/check-kunit-drm.sh              the sweep (needs root)
#   tests/check-kunit-drm.sh --self-test  planted controls against synthetic
#                                         kernel logs; no root, no module load
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
selftest_scratch=
kernel=$(uname -r)
testdir=/lib/modules/${kernel}/internal/drivers/gpu/drm/tests
dmesg_cmd=${DMESG_CMD:-dmesg}
modprobe_cmd=${MODPROBE_CMD:-modprobe}
floor=8
wait_s=${KUNIT_WAIT:-330}

skip() {
	echo "SKIP: kunit-drm: $*" >&2
	exit 77
}

fail() {
	echo "kunit-drm: $*" >&2
	exit 1
}

# Print the failing subtest names of one delta of kernel log ($1 = file),
# ignoring the ones named in $2 (an extended regex of allowed subtests).
# Real failing lines are indented and carry no dash: "[ time]     not ok 3 name".
failing_subtests() {
	grep -E '(^\[[^]]*\] *)? *not ok [0-9]+( -)? ' "$1" 2>/dev/null |
		sed -E 's/^\[[^]]*\] *//; s/^ *not ok [0-9]+( -)? //' |
		grep -Ev "${2:-^$}" || true
}

# Parse one suite's delta log. $1 = file, $2 = module base name. Exits
# non-zero with a named reason when the results are absent, when a subtest
# failed, or when any totals line reports a failure.
parse_delta() {
	local log=$1 name=$2 bad totals_line failing ntotals plan okc suite
	local agg_p agg_f agg_s
	suite=${name%_test}
	if ! grep -Fq "# module: $name" "$log"; then
		echo "kunit-drm: no '# module: $name' marker in the kernel log; KUnit did not run the suite" >&2
		return 1
	fi
	bad=$(failing_subtests "$log" "${KUNIT_ALLOW_SUBTESTS:-}")
	if [ -n "$bad" ]; then
		printf '%s\n' "$bad" | while IFS= read -r sub; do
			echo "kunit-drm: FAIL $name: $sub" >&2
		done
		return 1
	fi
	totals_line=$(grep -E '# Totals: pass:[0-9]+ fail:[0-9]+ skip:[0-9]+' "$log" || true)
	if [ -z "$totals_line" ]; then
		# Some suites print no "# Totals:" line at all (measured:
		# drm_atomic_test, whose only subtest is named like a test). Fall
		# back to the top-level KTAP plan and result count, which is the
		# authoritative verdict of the run.
		plan=$(sed -nE 's/^\[[^]]*\] [0-9]+\.\.([0-9]+)$/\1/p' "$log" | head -n 1)
		okc=$(grep -cE '^\[[^]]*\] ok [0-9]+ ' "$log" || true)
		if [ -z "$plan" ] || [ "${okc:-0}" -lt "$plan" ]; then
			echo "kunit-drm: no '# Totals:' line for $name and only ${okc:-0} of ${plan:-?} top-level KTAP results; the run did not finish (timeout $wait_s s?)" >&2
			return 1
		fi
		echo "kunit-drm: $name ok (no '# Totals:' line in this suite's output; top-level KTAP ok:$okc/$plan, no failures)"
		return 0
	fi
	failing=$(grep -E '# Totals: pass:[0-9]+ fail:[1-9][0-9]* skip:[0-9]+' <<<"$totals_line" | head -n 1)
	if [ -n "$failing" ]; then
		echo "kunit-drm: FAIL $name: totals line reports failures: $failing" >&2
		return 1
	fi
	# One delta can hold several "# Totals:" lines (a module with multiple
	# top-level subtests, measured: drm_bridge_test 3, drm_connector_test 10);
	# report the aggregate, not the last line.
	ntotals=$(grep -c '# Totals:' <<<"$totals_line")
	read -r agg_p agg_f agg_s < <(sed -E \
		's/.*# Totals: pass:([0-9]+) fail:([0-9]+) skip:([0-9]+).*/\1 \2 \3/' \
		<<<"$totals_line" | awk '{p += $1; f += $2; s += $3} END {print p + 0, f + 0, s + 0}')
	if [ "$ntotals" -gt 1 ]; then
		echo "kunit-drm: $name ok (aggregate of $ntotals totals lines: pass:$agg_p fail:$agg_f skip:$agg_s)"
	else
		echo "kunit-drm: $name ok ($totals_line)"
	fi
}

# --- self-test: planted controls on synthetic logs ---------------------------
# No root, no module load: the parser and the floor are the subjects. All
# fixtures use the measured real KTAP shape (suite name without _test,
# "# module:" marker, indented subtests without dashes).
self_test() {
	local scratch rc=0 out
	scratch=$(mktemp -d "${TMPDIR}/sm750-kunit-gate.XXXXXX")
	selftest_scratch=$scratch
	trap 'rm -rf -- "${selftest_scratch:-}"' EXIT

	expect_reject() {
		local name=$1 want=$2 log=$3 mod=${4:-drm_rect_test}
		if out=$(parse_delta "$log" "$mod" 2>&1); then
			echo "kunit-drm: planted defect '$name' was not caught" >&2
			rc=1
		elif ! grep -Fq "$want" <<<"$out"; then
			echo "kunit-drm: planted defect '$name' failed for the wrong reason: $out" >&2
			rc=1
		else
			echo "negative control $name: rejected ($(head -n 1 <<<"$out"))"
		fi
	}

	# 1. A failing subtest in an otherwise well-formed log. The failing line
	#    is indented and carries no dash, matching the real kernel output.
	cat >"$scratch/fail.log" <<'EOF'
[  1.0] KTAP version 1
[  1.0] 1..1
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_rect
[  1.0]     # module: drm_rect_test
[  1.0]     1..3
[  1.0]     ok 1 drm_test_rect_intersect
[  1.0]     not ok 2 drm_test_rect_clip_scaled_div_by_zero
[  1.0]     ok 3 drm_test_rect_calc_hscale
[  1.0]     # Totals: pass:2 fail:1 skip:0 total:3
[  1.0] ok 1 drm_rect
EOF
	expect_reject failing_subtest 'FAIL drm_rect_test: drm_test_rect_clip_scaled_div_by_zero' \
		"$scratch/fail.log"

	# 2. A suite that was never run: no marker, so a silent no-op cannot pass.
	cat >"$scratch/absent.log" <<'EOF'
[  1.0] usbcore: registered new interface driver uvcvideo
EOF
	expect_reject missing_suite "no '# module: drm_rect_test' marker" "$scratch/absent.log"

	# 3. A run that never finished: markers but no Totals line.
	cat >"$scratch/truncated.log" <<'EOF'
[  1.0] KTAP version 1
[  1.0] 1..1
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_rect
[  1.0]     # module: drm_rect_test
[  1.0]     1..3
[  1.0]     ok 1 drm_test_rect_intersect
EOF
	expect_reject missing_totals "no '# Totals:' line" "$scratch/truncated.log"

	# 4. Totals that contradict the visible results.
	cat >"$scratch/totals.log" <<'EOF'
[  1.0]     # module: drm_rect_test
[  1.0]     1..2
[  1.0]     ok 1 drm_test_rect_intersect
[  1.0]     ok 2 drm_test_rect_calc_hscale
[  1.0]     # Totals: pass:1 fail:1 skip:0 total:2
EOF
	expect_reject totals_mismatch 'totals line reports failures' "$scratch/totals.log"

	# 5. Planted control: the "# module:" line names a DIFFERENT module, so a
	#    wrong-module log must not pass as drm_rect_test.
	cat >"$scratch/wrongmodule.log" <<'EOF'
[  1.0] KTAP version 1
[  1.0] 1..1
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_mm
[  1.0]     # module: drm_mm_test
[  1.0]     1..6
[  1.0]     ok 1 drm_test_mm_init
[  1.0]     # Totals: pass:6 fail:0 skip:0 total:6
[  1.0] ok 1 drm_mm
EOF
	expect_reject wrong_module "no '# module: drm_rect_test' marker" "$scratch/wrongmodule.log"

	# 6. Planted control: two "# Totals:" lines in one delta (a module with
	#    several top-level subtests), the second with fail:1 - must reject.
	cat >"$scratch/twototals.log" <<'EOF'
[  1.0] KTAP version 1
[  1.0] 1..4
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_bridge
[  1.0]     # module: drm_bridge_test
[  1.0]     1..2
[  1.0]     ok 1 drm_test_bridge_get_modes
[  1.0]     # Totals: pass:4 fail:0 skip:0 total:4
[  1.0]     ok 2 drm_test_bridge_get_modes_edid
[  1.0]     # Totals: pass:3 fail:1 skip:0 total:4
EOF
	expect_reject second_totals_fails 'totals line reports failures' "$scratch/twototals.log" \
		drm_bridge_test

	# 6b. Negative control: measured real output of a suite that prints NO
	#     "# Totals:" line at all (drm_atomic_test). A single top-level
	#     "ok 1 <suite>" is the complete run and must be accepted.
	cat >"$scratch/nototals.log" <<'EOF'
[  1.0] KTAP version 1
[  1.0] 1..1
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_test_atomic_get_connector_for_encoder
[  1.0]     # module: drm_atomic_test
[  1.0]     1..1
[  1.0]     ok 1 drm_test_drm_atomic_get_connector_for_encoder
[  1.0] ok 1 drm_test_atomic_get_connector_for_encoder
EOF
	if out=$(parse_delta "$scratch/nototals.log" drm_atomic_test 2>&1); then
		echo "negative control no_totals_line: accepted ($out)"
	else
		echo "kunit-drm: negative control 'no_totals_line' was rejected: $out" >&2
		rc=1
	fi

	# 7. Negative control: a clean real-shape run must pass.
	cat >"$scratch/clean.log" <<'EOF'
[  1.0] KTAP version 1
[  1.0] 1..1
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_rect
[  1.0]     # module: drm_rect_test
[  1.0]     1..2
[  1.0]     ok 1 drm_test_rect_intersect
[  1.0]     ok 2 drm_test_rect_calc_hscale
[  1.0]     # Totals: pass:2 fail:0 skip:0 total:2
[  1.0] ok 1 drm_rect
EOF
	if out=$(parse_delta "$scratch/clean.log" drm_rect_test 2>&1); then
		echo "negative control clean_run: accepted ($out)"
	else
		echo "kunit-drm: planted defect 'clean_run' was rejected: $out" >&2
		rc=1
	fi

	# 8. Negative control: a skipped subtest is not a failure.
	cat >"$scratch/skip.log" <<'EOF'
[  1.0]     # module: drm_rect_test
[  1.0]     1..2
[  1.0]     ok 1 drm_test_rect_intersect
[  1.0]     ok 2 drm_test_rect_calc_hscale # SKIP no hardware
[  1.0]     # Totals: pass:2 fail:0 skip:1 total:2
EOF
	if out=$(parse_delta "$scratch/skip.log" drm_rect_test 2>&1); then
		echo "negative control skipped_subtest: accepted ($out)"
	else
		echo "kunit-drm: planted defect 'skipped_subtest' was rejected: $out" >&2
		rc=1
	fi

	# 9. Negative control: two "# Totals:" lines, both fail:0 - accepted, and
	#    the counts are aggregated across both.
	cat >"$scratch/twoclean.log" <<'EOF'
[  1.0]     # module: drm_bridge_test
[  1.0]     1..2
[  1.0]     ok 1 drm_test_bridge_get_modes
[  1.0]     # Totals: pass:4 fail:0 skip:0 total:4
[  1.0]     ok 2 drm_test_bridge_get_modes_edid
[  1.0]     # Totals: pass:3 fail:0 skip:1 total:4
EOF
	if out=$(parse_delta "$scratch/twoclean.log" drm_bridge_test 2>&1) &&
		grep -Fq 'aggregate of 2 totals lines: pass:7 fail:0 skip:1' <<<"$out"; then
		echo "negative control two_totals_clean: accepted ($out)"
	else
		echo "kunit-drm: negative control 'two_totals_clean' failed: ${out:-no output}" >&2
		rc=1
	fi

	# 10. Control exit_status_green: the EXIT-trap status leak, pinned
	#     structurally. A function installed as an EXIT trap must end in a
	#     command that succeeds; measured regression: unload_all ended in
	#     "grep -q ... && echo", which returned 1 once kunit had been
	#     successfully unloaded, so the trap status became the script's rc
	#     and a fully green run exited 1 without printing the closing line.
	#     Assert the real unload_all ends in "return 0", and run a
	#     same-shaped harness under "set -euo pipefail" to prove the trap
	#     does not swallow the epilogue.
	if ! awk '/^unload_all\(\) \{/,/^\}/' "$0" | tail -n 2 | grep -q 'return 0'; then
		echo "kunit-drm: control exit_status_green failed: unload_all does not end in 'return 0'" >&2
		rc=1
	fi
	bash -c '
		set -euo pipefail
		loaded=()
		kunit_before=0
		unload_all() {
			if [ "${kunit_before:-1}" -eq 0 ]; then
				if grep -q "^kunit " /proc/modules; then :; fi
			fi
			return 0
		}
		trap unload_all EXIT
		failures=0
		[ "$failures" -eq 0 ] || exit 1
		echo "KUnit DRM sweep passed: 21 suites, 0 failures"
	' >/dev/null || {
		echo "kunit-drm: control exit_status_green failed: EXIT-trap shape still leaks a non-zero status" >&2
		rc=1
	}
	if [ "$rc" -eq 0 ]; then
		echo "control exit_status_green: accepted (green run reaches the closing line, rc 0)"
	fi

	[ "$rc" -eq 0 ] || exit 1
	echo "KUnit sweep self-test passed (6 planted defects rejected, 4 negative controls accepted, exit_status_green pinned)"
}

if [ "${1:-}" = "--self-test" ]; then
	self_test
	exit 0
fi

# --- the sweep --------------------------------------------------------------
# Privilege model: the gate never escalates on its own. Either it runs as
# root, or the owner passes an allowlisted modprobe prefix in MODPROBE_CMD
# (this host: MODPROBE_CMD='sudo -n /usr/bin/modprobe' with the exact
# per-suite lines in docs/ROOT-ACTIONS.md section 3.9). Without either:
# one SKIP line, exit 77.
mp() { $modprobe_cmd "$@"; }

if [ "$(id -u)" -eq 0 ]; then
	: # root: plain modprobe works
elif [ "$modprobe_cmd" = modprobe ]; then
	skip "loading the DRM KUnit test modules needs root, this shell is uid $(id -u); run as root (sudo $0) or pass the allowlisted loader, MODPROBE_CMD='sudo -n /usr/bin/modprobe' with the per-suite allowlist of docs/ROOT-ACTIONS.md section 3.9"
fi

[ -d "$testdir" ] ||
	skip "directory $testdir does not exist; the kernel-modules-internal package for kernel $kernel is not installed"
command -v "${modprobe_cmd%% *}" >/dev/null 2>&1 || skip "the modprobe runner '$modprobe_cmd' is not in PATH"
$dmesg_cmd >/dev/null 2>&1 ||
	skip "the kernel log is not readable through '$dmesg_cmd' (set DMESG_CMD, for example DMESG_CMD='sudo -n dmesg')"

mapfile -t found < <(cd "$testdir" && ls -1 ./*.ko.xz 2>/dev/null | sed 's|^\./||; s|\.ko\.xz$||' | sort)
[ "${#found[@]}" -ge "$floor" ] ||
	fail "discovered ${#found[@]} KUnit modules under $testdir, below the floor of $floor; the internal package is empty or incomplete"
echo "kunit-drm: ${#found[@]} modules discovered under $testdir"

# drm_kunit_helpers and drm_kunit_edid are support code, not suites: modprobe
# pulls them in as dependencies and they have no test of their own.
suites=()
for m in "${found[@]}"; do
	case $m in
	drm_kunit_helpers | drm_kunit_edid) continue ;;
	esac
	suites+=("$m")
done
[ "${#suites[@]}" -ge "$floor" ] ||
	fail "only ${#suites[@]} runnable suites among ${#found[@]} modules, below the floor of $floor"

loaded=()
kunit_before=$(grep -c '^kunit ' /proc/modules || true)
unload_all() {
	local i
	for ((i = ${#loaded[@]} - 1; i >= 0; i--)); do
		mp -r "${loaded[$i]}" 2>/dev/null || true
	done
	loaded=()
	# modprobe -r of the last suite normally drops kunit too. If this run
	# pulled kunit in and it is still resident, try once and then say so:
	# "/usr/bin/modprobe -r kunit" is allowlisted on this host
	# (docs/ROOT-ACTIONS.md section 3.10); an unprivileged run elsewhere
	# cannot unload it.
	if [ "${kunit_before:-1}" -eq 0 ]; then
		if grep -q '^kunit ' /proc/modules; then
			mp -r kunit 2>/dev/null || true
			# Plain if, not "grep && echo": under "set -e" a compound
			# list ending the function returns 1 when grep fails, and
			# as the EXIT trap that status became the script's rc even
			# on a fully green run.
			if grep -q '^kunit ' /proc/modules; then
				echo "kunit-drm: NOTE the kunit base module is still resident; unloading it needs '/usr/bin/modprobe -r kunit' (docs/ROOT-ACTIONS.md section 3.10)" >&2
			fi
		fi
	fi
	return 0
}
trap unload_all EXIT

scratch=$(mktemp -d "${TMPDIR}/sm750-kunit-run.XXXXXX")
trap 'unload_all; rm -rf -- "$scratch"' EXIT

failures=0
ran=0
disabled=0
# Cursor into the kernel log: the full line printed just before this run's
# first message. A tail-by-count cursor breaks once the ring buffer wraps
# (measured: the drm_hdmi_state_helper_test delta holds ~600 lines with
# WARNING tracebacks, and dmesg then holds fewer lines than the old
# "before" count, so "tail -n +N" yielded nothing and the marker was never
# found). Matching the exact anchor line is wrap-safe.
# Cursor into the kernel log, by monotonic timestamp rather than by line
# count: a count cursor breaks once the ring buffer wraps (measured: the
# drm_hdmi_state_helper_test delta holds ~600 lines of WARNING tracebacks, so
# dmesg held fewer lines than the old "before" count and "tail -n +N" yielded
# nothing at all, which is why that suite was reported as not run). $1 = the
# timestamp to start at (inclusive); lines without a timestamp are kept.
kernel_ts() {
	$dmesg_cmd 2>/dev/null | tail -n 1 |
		sed -nE 's/^\[ *([0-9]+\.[0-9]+)\].*/\1/p'
}
delta_since() {
	local since=$1
	if [ -z "$since" ]; then
		$dmesg_cmd 2>/dev/null
		return
	fi
	$dmesg_cmd 2>/dev/null | awk -v since="$since" '
		{ ts = "" }
		match($0, /^\[ *[0-9]+\.[0-9]+\]/) {
			ts = substr($0, 2, RLENGTH - 2) + 0
			gsub(/^ +| +$/, "", ts)
			if (ts + 0 >= since + 0) print
			next
		}
		{ print }'
}
# Seed the cursor before the first suite: an empty cursor would make the
# whole kernel log the first delta and drag in leftovers from earlier runs
# (measured: drm_atomic_commit_test then aggregated 69 totals lines from
# three accumulated runs instead of its own one).
cursor=$(kernel_ts)
for name in "${suites[@]}"; do
	mp "$name" || { echo "kunit-drm: modprobe $name failed" >&2; failures=$((failures + 1)); continue; }
	loaded+=("$name")
	deadline=$((SECONDS + wait_s))
	# Wait until the delta is settled: it carries "# Totals:", or the module's
	# single top-level "ok N <suite>" result (drm_atomic_test prints no
	# Totals line), or the "kunit: disabled" short-circuit. Measured settle
	# time is under 250 ms; $wait_s is only the safety ceiling. The delta is
	# captured into a variable first: piping into "grep -q" under pipefail
	# would fail the pipeline on SIGPIPE once grep exits early, which is what
	# made every large-delta suite burn the whole ceiling.
	while :; do
		delta=$(delta_since "$cursor")
		if grep -Eq "# module: $name|kunit: disabled" <<<"$delta" &&
			{ grep -Eq '# Totals:|kunit: disabled' <<<"$delta" ||
				grep -Eq '^\[[^]]*\] ok [0-9]+ ' <<<"$delta"; }; then
			break
		fi
		[ "$SECONDS" -lt "$deadline" ] || break
		sleep 1
	done
	printf '%s\n' "$delta" >"$scratch/$name.log"
	cursor=$(kernel_ts)
	if grep -Fq 'kunit: disabled' "$scratch/$name.log" &&
		! grep -Fq "# module: $name" "$scratch/$name.log"; then
		disabled=$((disabled + 1))
		continue
	fi
	ran=$((ran + 1))
	if ! parse_delta "$scratch/$name.log" "$name"; then
		failures=$((failures + 1))
	fi
done

unload_all
if [ "$disabled" -gt 0 ] && [ "$ran" -eq 0 ]; then
	skip "$disabled of ${#suites[@]} suites only printed 'kunit: disabled': KUnit is disabled at runtime on kernel $kernel (# CONFIG_KUNIT_DEFAULT_ENABLED is not set in /boot/config-$kernel, so kunit loads with enable=0). No subtest ran, so this is not a pass. Enable it with 'options kunit enable=1' in /etc/modprobe.d/ or 'kunit.enable=1' on the kernel command line (docs/ROOT-ACTIONS.md section 3.10), then rerun"
fi
[ "$failures" -eq 0 ] ||
	fail "$failures of ${#suites[@]} DRM KUnit suites failed"
echo "KUnit DRM sweep passed: ${#suites[@]} suites, 0 failures"
