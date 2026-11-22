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
# TAP results go to the kernel log, so the gate reads them through $DMESG_CMD
# (default: dmesg) and parses "# Subtest:", "ok N - name", "not ok N - name"
# and "# Totals: pass:N fail:N skip:N". Every suite is unloaded in an EXIT
# trap on every path, so no test module is left resident.
#
# Root: modprobe of an internal test module needs root, and the gate never
# escalates on its own. Two ways to run it:
#   - as root:            sudo ./tests/check-kunit-drm.sh
#   - unprivileged with an allowlisted modprobe prefix (this host grants
#     "/usr/bin/modprobe <name>" and "/usr/bin/modprobe -r <name>" for each
#     suite, docs/ROOT-ACTIONS.md section 3.9):
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
failing_subtests() {
	grep -E '^\[[^]]*\] *not ok [0-9]+ - |^not ok [0-9]+ - ' "$1" 2>/dev/null |
		sed -E 's/^\[[^]]*\] *//; s/^not ok [0-9]+ - //' |
		grep -Ev "${2:-^$}" || true
}

# Parse one suite's delta log. $1 = file, $2 = suite name. Exits non-zero with
# a named reason when the results are absent, when a subtest failed, or when
# the totals line reports a failure.
parse_delta() {
	local log=$1 name=$2 bad totals
	if ! grep -Fq "# Subtest: $name" "$log"; then
		echo "kunit-drm: no '# Subtest: $name' marker in the kernel log; KUnit did not run the suite" >&2
		return 1
	fi
	bad=$(failing_subtests "$log" "${KUNIT_ALLOW_SUBTESTS:-}")
	if [ -n "$bad" ]; then
		printf '%s\n' "$bad" | while IFS= read -r sub; do
			echo "kunit-drm: FAIL $name: $sub" >&2
		done
		return 1
	fi
	if ! totals=$(grep -E '# Totals: pass:[0-9]+ fail:[0-9]+ skip:[0-9]+' "$log" |
		tail -n 1); then
		echo "kunit-drm: no '# Totals:' line for $name; the run did not finish (timeout $wait_s s?)" >&2
		return 1
	fi
	if ! grep -Eq '# Totals: pass:[0-9]+ fail:0 skip:[0-9]+' <<<"$totals"; then
		echo "kunit-drm: FAIL $name: totals line reports failures: $totals" >&2
		return 1
	fi
	echo "kunit-drm: $name ok ($totals)"
}

# --- self-test: planted controls on synthetic logs ---------------------------
# No root, no module load: the parser and the floor are the subjects.
self_test() {
	local scratch rc=0 out
	scratch=$(mktemp -d "${TMPDIR}/sm750-kunit-gate.XXXXXX")
	selftest_scratch=$scratch
	trap 'rm -rf -- "${selftest_scratch:-}"' EXIT

	expect_reject() {
		local name=$1 want=$2 log=$3
		if out=$(parse_delta "$log" drm_rect_test 2>&1); then
			echo "kunit-drm: planted defect '$name' was not caught" >&2
			rc=1
		elif ! grep -Fq "$want" <<<"$out"; then
			echo "kunit-drm: planted defect '$name' failed for the wrong reason: $out" >&2
			rc=1
		else
			echo "negative control $name: rejected ($(head -n 1 <<<"$out"))"
		fi
	}

	# 1. A failing subtest in an otherwise well-formed log.
	cat >"$scratch/fail.log" <<'EOF'
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_rect_test
[  1.0]     1..3
[  1.0]     ok 1 - drm_test_rect_intersect
[  1.0]     not ok 2 - drm_test_rect_clip_scaled_div_by_zero
[  1.0]     ok 3 - drm_test_rect_calc_hscale
[  1.0]     # Totals: pass:2 fail:1 skip:0 total:3
[  1.0] ok 1 - drm_rect_test
EOF
	expect_reject failing_subtest 'FAIL drm_rect_test: drm_test_rect_clip_scaled_div_by_zero' \
		"$scratch/fail.log"

	# 2. A suite that was never run: no marker, so a silent no-op cannot pass.
	cat >"$scratch/absent.log" <<'EOF'
[  1.0] usbcore: registered new interface driver uvcvideo
EOF
	expect_reject missing_suite "no '# Subtest: drm_rect_test' marker" "$scratch/absent.log"

	# 3. A run that never finished: markers but no Totals line.
	cat >"$scratch/truncated.log" <<'EOF'
[  1.0]     # Subtest: drm_rect_test
[  1.0]     1..3
[  1.0]     ok 1 - drm_test_rect_intersect
EOF
	expect_reject missing_totals "no '# Totals:' line" "$scratch/truncated.log"

	# 4. Totals that contradict the visible results.
	cat >"$scratch/totals.log" <<'EOF'
[  1.0]     # Subtest: drm_rect_test
[  1.0]     1..2
[  1.0]     ok 1 - drm_test_rect_intersect
[  1.0]     ok 2 - drm_test_rect_calc_hscale
[  1.0]     # Totals: pass:1 fail:1 skip:0 total:2
EOF
	expect_reject totals_mismatch 'totals line reports failures' "$scratch/totals.log"

	# 5. Negative control: a clean run must pass.
	cat >"$scratch/clean.log" <<'EOF'
[  1.0]     KTAP version 1
[  1.0]     # Subtest: drm_rect_test
[  1.0]     1..2
[  1.0]     ok 1 - drm_test_rect_intersect
[  1.0]     ok 2 - drm_test_rect_calc_hscale
[  1.0]     # Totals: pass:2 fail:0 skip:0 total:2
[  1.0] ok 1 - drm_rect_test
EOF
	if out=$(parse_delta "$scratch/clean.log" drm_rect_test 2>&1); then
		echo "negative control clean_run: accepted ($out)"
	else
		echo "kunit-drm: planted defect 'clean_run' was rejected: $out" >&2
		rc=1
	fi

	# 6. A skipped subtest is not a failure.
	cat >"$scratch/skip.log" <<'EOF'
[  1.0]     # Subtest: drm_rect_test
[  1.0]     1..2
[  1.0]     ok 1 - drm_test_rect_intersect
[  1.0]     ok 2 - drm_test_rect_calc_hscale # SKIP no hardware
[  1.0]     # Totals: pass:2 fail:0 skip:1 total:2
EOF
	if out=$(parse_delta "$scratch/skip.log" drm_rect_test 2>&1); then
		echo "negative control skipped_subtest: accepted ($out)"
	else
		echo "kunit-drm: planted defect 'skipped_subtest' was rejected: $out" >&2
		rc=1
	fi

	[ "$rc" -eq 0 ] || exit 1
	echo "KUnit sweep self-test passed (4 planted defects rejected, 2 negative controls accepted)"
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
	# "/usr/bin/modprobe -r kunit" is not in the allowlist, so an
	# unprivileged run cannot unload it (docs/ROOT-ACTIONS.md section 3.10).
	if [ "${kunit_before:-1}" -eq 0 ] && grep -q '^kunit ' /proc/modules; then
		mp -r kunit 2>/dev/null || true
		grep -q '^kunit ' /proc/modules &&
			echo "kunit-drm: NOTE the kunit base module is still resident; unloading it needs '/usr/bin/modprobe -r kunit', which is not allowlisted (docs/ROOT-ACTIONS.md section 3.10)" >&2
	fi
}
trap unload_all EXIT

scratch=$(mktemp -d "${TMPDIR}/sm750-kunit-run.XXXXXX")
trap 'unload_all; rm -rf -- "$scratch"' EXIT

failures=0
ran=0
disabled=0
for name in "${suites[@]}"; do
	before=$($dmesg_cmd 2>/dev/null | wc -l)
	mp "$name" || { echo "kunit-drm: modprobe $name failed" >&2; failures=$((failures + 1)); continue; }
	loaded+=("$name")
	deadline=$((SECONDS + wait_s))
	while ! $dmesg_cmd 2>/dev/null | tail -n +"$((before + 1))" | grep -Eq "# Subtest: $name|kunit: disabled"; do
		[ "$SECONDS" -lt "$deadline" ] || break
		sleep 1
	done
	$dmesg_cmd 2>/dev/null | tail -n +"$((before + 1))" >"$scratch/$name.log" || true
	if grep -Fq 'kunit: disabled' "$scratch/$name.log" &&
		! grep -Fq "# Subtest: $name" "$scratch/$name.log"; then
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
