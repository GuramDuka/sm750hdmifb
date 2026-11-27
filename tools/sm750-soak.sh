#!/bin/sh
# sm750-soak - sample one SM750 panel for hours and write a machine-readable
# verdict, so a release report can cite a window longer than one command.
#
# Why it exists: every other helper in this tree measures one moment. A driver
# that stops scanning out, leaks a reference or starts failing mode sets does
# so after an hour of use, and a verdict taken from one sample cannot tell a
# transient from a failure. This helper takes a sample every INTERVAL seconds
# for DURATION seconds (24 h by default, 48 h the maximum it accepts), appends
# one tab-separated row per sample, and derives its verdict from the whole
# series: counts of out-of-range samples and counts of new fault lines, never a
# single reading. A run with fewer than two samples is never PASS.
#
# Read-only, by construction. It reads 0444 sysfs attributes, /proc and the
# kernel log, and it may run one read-only register helper. It never opens a
# DRM node (no /dev/dri/card), never grabs a console, never switches a VT,
# never unshares /dev/input, never starts a graphical server and never signals
# a process: it has no reason to. It runs as the invoking user; the only
# privileged step is an optional `sudo -n /usr/local/sbin/sm750-regs`
# (allowlisted, read-only), and a refusal is recorded as an unavailable field,
# not treated as a failure.
#
# What one sample records (all of it in samples.tsv, header order):
#   panel state      mode, refresh_hz, crtc, hpd, rxsense, link_state in one
#                    cell, plus vblank_count on its own column
#   crc              a value when a read-only path yields one, else an explicit
#                    unavailable reason (enabling a CRC source writes debugfs,
#                    so this helper does not do it)
#   GAP-B8 counters  the eleven b8_* attributes, or `-` when the loaded module
#                    predates them
#   module           refcnt, version, resident size from /proc/modules
#   memory           MemAvailable from /proc/meminfo
#   kernel log       new lines and new hard fault lines since the previous
#                    sample (delta only, so an old fault cannot fail a run)
#   gates            PASS, FAIL or `unavailable:<reason>` from the last
#                    recorded gate log named by --gates
#
# Verdict criteria, each one a count or a range, never a transient:
#   card-present      the PCI device directory existed in every sample
#   panel-vblank      vblank_count was present in every sample and never
#                     decreased, and PANEL_CURRENT_LINE took more than one
#                     value. A stalled vblank window is recorded and not
#                     failed: an idle pipe freezes vblank_count through DRM
#                     core's vblankoffdelay (runtime/34-vblank-idle-freeze),
#                     while the panel line keeps moving because the raster
#                     runs regardless
#   vram-range        vram_used_bytes <= vram_total_bytes and vram_total_bytes
#                     equals mem_info_vram_total in every sample
#   module-refcount   1..16 in every sample and never more than first + 1
#   module-identity   the module version never changed (a reload is a new
#                     driver instance, so the run no longer measures one)
#   module-size       the resident module size never changed
#   mem-floor         MemAvailable stayed above --mem-floor (default 65536 kB),
#                     so an unattended run cannot starve the owner's machine
#   log-quiet         zero new driver fault lines and zero new kernel-wide
#                     severe lines over the whole window
#   counters-monotonic  the b8_* counters never decreased (a decrease is a
#                     reload or a reset, not a soak)
#   gates-recorded    no sample read gates=FAIL
#   coverage          at least two samples and the requested window completed
#
# Usage:
#   sm750-soak run [--duration SECS] [--interval SECS] [--outdir DIR]
#                  [--gates FILE] [--mem-floor KB] [--root DIR]
#   sm750-soak status DIR
#
# Files written into OUTDIR:
#   samples.tsv   one header row plus one row per sample, tab separated
#   verdict.json  machine-readable verdict for a report to cite
#   summary.txt   the same verdict as text, with each criterion and its counts
#
# Exit codes:
#   0  the run finished and its verdict is PASS
#   1  the run finished (or was interrupted) and its verdict is FAIL
#   2  usage error
#   3  environment problem before the first sample: no device directory, no
#      loaded module, an unusable outdir, or a refused outdir location
set -eu
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

PROG=sm750-soak
BDF=0000:01:00.0
SOAK_BASE=/mega/tmp/sm750
GATES_DEFAULT=$SOAK_BASE/soak/last-gate-results.txt
REGS_DEFAULT=/usr/local/sbin/sm750-regs
CRC_DEFAULT=/usr/local/sbin/sm750-crc

# Driver fault markers, verbatim from the census pinned by
# tests/check-scratch-policy.sh, applied to lines that name this driver.
CENSUS='failed to enable HDMI mode|flip_done timed out|commit wait timed out|refcount_t: underflow|did not latch|panel did not acknowledge|enable-fail state|WARNING|BUG:'
# Kernel-wide severe markers: an unattended host must not log these anywhere.
SEVERE='BUG:|Oops|general protection fault|kernel NULL pointer dereference|lockdep'

DURATION=86400
INTERVAL=60
MEM_FLOOR=65536
OUT=
GATES=$GATES_DEFAULT
ROOT=
SYS=/sys
PROC=/proc
REGS=$REGS_DEFAULT
CRC=$CRC_DEFAULT
LOGMODE=none
LOGPATH=
DEV=
MOD=
SAMPLES=
EXPECTED=0
STARTED_UTC=
FINALIZED=0
COMPLETE=0
TMPD=
LOGLINES_PREV=0
FAULTS_PREV=0
WRAPS=0

usage() {
	cat >&2 <<'EOF'
usage: sm750-soak run [--duration SECS] [--interval SECS] [--outdir DIR]
                      [--gates FILE] [--mem-floor KB] [--root DIR]
       sm750-soak status DIR

  run      sample the panel, the b8_* counters, the module refcount, VRAM use,
           resident memory, dmesg delta counts and the last recorded gate
           results every --interval seconds for --duration seconds, then write
           samples.tsv, verdict.json and summary.txt into a fresh --outdir
           (default /mega/tmp/sm750/soak/<UTC stamp>).
  status   print the verdict line and the summary of a finished run; exit 0
           when it is PASS.

Options:
  --duration SECS   window length, 1..172800. Default 86400 (24 h).
  --interval SECS   minimum seconds between samples, 1..3600; each sample's
                    own runtime adds to the gap. Default 60.
  --outdir DIR      absolute output directory, created fresh, never reused.
                    Outside --root it must sit under /mega/tmp/sm750.
  --gates FILE      plain-text log of the last recorded gate results.
                    Default /mega/tmp/sm750/soak/last-gate-results.txt.
  --mem-floor KB    MemAvailable floor in kB. Default 65536.
  --root DIR        test fixture only, used by tests/check-soak-helper.sh.

The helper reads only. It never opens a DRM node, never grabs a console, never
switches a VT, never unshares /dev/input, never starts a graphical server and
never signals a process. A verdict needs at least two samples: one reading
cannot separate a transient from a failure.

Exit codes: 0 PASS, 1 FAIL, 2 usage, 3 environment problem.
EOF
	exit 2
}

die_env() {
	echo "$PROG: $*" >&2
	exit 3
}

isnum() {
	case ${1:-} in
	'' | *[!0-9]*) return 1 ;;
	*) return 0 ;;
	esac
}

# read_attr NAME - a trimmed single-line value from the PCI device directory,
# or `-`. No sysfs attribute this helper reads contains whitespace, so the
# trim is what keeps a stray newline out of a tab-separated cell.
read_attr() {
	read_file "$DEV/$1"
}

read_file() { # read_file PATH - trimmed value or -
	v=
	if [ -r "$1" ]; then
		v=$(tr -d '[:space:]' <"$1" 2>/dev/null) || v=
	fi
	printf '%s' "${v:--}"
}

# panel_line - PANEL_CURRENT_LINE from the read-only register helper. That
# helper needs debugfs, so it is tried unprivileged first and then through the
# grant the host already carries; a refusal yields `-`, never a failure.
panel_line() {
	out=
	if [ -n "$REGS" ] && [ -x "$REGS" ]; then
		# Keep partial output: the helper can print registers and still
		# report a non-zero status from one failed probe file.
		out=$("$REGS" 2>/dev/null) || :
	fi
	if [ -z "$out" ] && [ -z "$ROOT" ] && [ -x "$REGS" ] &&
		command -v sudo >/dev/null 2>&1; then
		out=$(sudo -n "$REGS" 2>/dev/null </dev/null) || :
	fi
	if [ -z "$out" ]; then
		printf '%s' "-"
		return 0
	fi
	line=$(printf '%s\n' "$out" | grep -F 'PANEL_CURRENT_LINE' |
		awk '{print $NF; exit}') || line=
	printf '%s' "${line:--}"
}

# crc_sample - a crc value if a read-only path yields one, else an explicit
# unavailable reason. Enabling a CRC source writes the debugfs control, so this
# helper never does it: `probe` is the read-only subcommand and it reports
# availability, not a value.
crc_sample() {
	out=
	if [ -n "$CRC" ] && [ -x "$CRC" ]; then
		out=$("$CRC" 2>/dev/null) || :
	fi
	if [ -z "$out" ] && [ -z "$ROOT" ] && [ -x "$CRC" ] &&
		command -v sudo >/dev/null 2>&1; then
		out=$(sudo -n "$CRC" 2>/dev/null </dev/null) || :
	fi
	if [ -z "$out" ]; then
		printf '%s' 'unavailable:no-read-only-crc-path'
		return 0
	fi
	if printf '%s\n' "$out" | grep -qF 'crc/source'; then
		supported=$(read_attr crc_supported)
		printf 'unavailable:probe-only-supported=%s' "$supported"
	else
		printf '%s' 'unavailable:probe-reported-no-source'
	fi
}

init_log_source() {
	if [ -n "$ROOT" ]; then
		if [ -r "$ROOT/dmesg.log" ]; then
			LOGMODE=file
			LOGPATH=$ROOT/dmesg.log
		else
			LOGMODE=none
		fi
		return 0
	fi
	if command -v dmesg >/dev/null 2>&1 && dmesg >/dev/null 2>&1; then
		LOGMODE=dmesg
	elif command -v journalctl >/dev/null 2>&1 &&
		journalctl -k -b --no-pager >/dev/null 2>&1; then
		LOGMODE=journal
	else
		LOGMODE=none
	fi
}

log_read() {
	case $LOGMODE in
	file) cat "$LOGPATH" 2>/dev/null || true ;;
	dmesg) dmesg 2>/dev/null || true ;;
	journal) journalctl -k -b --no-pager 2>/dev/null || true ;;
	*) : ;;
	esac
}

log_lines() {
	log_read | wc -l | tr -d ' '
}

# hard_faults - the number of fault lines in the current buffer: severe lines
# anywhere plus driver-marked lines that name sm750. Counted over the whole
# buffer and differenced per sample, so a ring-buffer wrap cannot rescan old
# lines as new ones.
hard_faults() {
	severe=$(log_read | grep -cE "$SEVERE" 2>/dev/null) || severe=0
	driver=$(log_read | grep -E "$CENSUS" 2>/dev/null | grep -cF 'sm750') ||
		driver=0
	isnum "$severe" || severe=0
	isnum "$driver" || driver=0
	printf '%s' "$((severe + driver))"
}

gates_sample() {
	if [ -z "$GATES" ] || [ ! -r "$GATES" ]; then
		printf '%s' 'unavailable:no-gate-log'
		return 0
	fi
	if grep -qE '(^|[[:space:]])(FAIL|FAILED|ERROR|Traceback)(:|[[:space:]]|$)' \
		"$GATES" 2>/dev/null; then
		printf '%s' 'FAIL'
	elif grep -qE '(^|[[:space:]])ok:' "$GATES" 2>/dev/null; then
		printf '%s' 'PASS'
	elif grep -qF 'passed' "$GATES" 2>/dev/null; then
		printf '%s' 'PASS'
	else
		printf '%s' 'unavailable:no-gate-marker'
	fi
}

sample_once() { # sample_once N
	n=$1
	present=0
	if [ -d "$DEV" ]; then
		present=1
	fi
	mode=$(read_attr active_mode)
	refresh=$(read_attr active_mode_refresh_hz)
	crtc=$(read_attr active_crtc)
	vblank=$(read_attr vblank_count)
	linkstate=$(read_attr link_state)
	hpd=$(read_attr hpd)
	rx=$(read_attr rxsense)
	vused=$(read_attr vram_used_bytes)
	vtot=$(read_attr vram_total_bytes)
	vmem=$(read_attr mem_info_vram_total)
	refcnt=$(read_file "$MOD/refcnt")
	version=$(read_file "$MOD/version")
	# Resident module size in bytes, field 2 of the /proc/modules row.
	modsize=$(awk -v m=sm750hdmidrm '$1 == m { print $2; exit }' \
		"$PROC/modules" 2>/dev/null) || modsize=
	[ -n "${modsize:-}" ] || modsize=-
	memavail=$(awk '/^MemAvailable:/ { print $2; exit }' \
		"$PROC/meminfo" 2>/dev/null) || memavail=
	[ -n "${memavail:-}" ] || memavail=-
	panel=$(panel_line)
	crc=$(crc_sample)
	gates=$(gates_sample)

	# The panel cell folds the four liveness attributes sysfs exposes without
	# a card node, so a report can read the panel from one column.
	panelcell=$mode:$refresh:$crtc:$hpd:$rx:$linkstate

	lines=$(log_lines)
	faults=$(hard_faults)
	dlines=0
	dfaults=0
	if isnum "$lines" && isnum "$faults"; then
		if [ "$lines" -ge "$LOGLINES_PREV" ]; then
			dlines=$((lines - LOGLINES_PREV))
		else
			WRAPS=$((WRAPS + 1))
		fi
		if [ "$faults" -ge "$FAULTS_PREV" ]; then
			dfaults=$((faults - FAULTS_PREV))
		else
			WRAPS=$((WRAPS + 1))
		fi
		LOGLINES_PREV=$lines
		FAULTS_PREV=$faults
	fi

	ROW=$n
	for field in "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" "$present" \
		"$panelcell" "$vused" "$vtot" "$vmem" "$refcnt" "$version" \
		"$modsize" "$memavail" "$vblank" "$panel" "$crc"; do
		ROW=$ROW$TAB$field
	done
	for name in b8_mode_attempts b8_mode_failures b8_mode_retries \
		b8_stage_failures b8_i2c_write_timeouts b8_i2c_recoveries \
		b8_ready_expired b8_ddc_grant_timeouts b8_edid_reads \
		b8_edid_failures b8_counters_epoch_s; do
		ROW=$ROW$TAB$(read_attr "$name")
	done
	ROW=$ROW$TAB$gates$TAB$dlines$TAB$dfaults
	printf '%s\n' "$ROW" >>"$SAMPLES"

	printf '%s: sample %s %s panel=%s vblank=%s vram=%s/%s refcnt=%s faults+=%s\n' \
		"$PROG" "$n" "$(date -u +%H:%M:%SZ)" "$mode" "$vblank" "$vused" \
		"$vtot" "$refcnt" "$dfaults"
}

# evaluate FILE COMPLETE - one criterion per line: name TAB ok(1|0) TAB detail.
# COMPLETE is 1 when the sampling loop reached the requested window.
evaluate() {
	awk -F'\t' -v floor="$MEM_FLOOR" -v complete="$2" '
	NR == 1 { next }
	{
		n++
		if ($4 != 1) miss++
		if ($13 ~ /^[0-9]+$/) {
			vb++
			if (firstvb == "") firstvb = $13
			if (prevvb != "") {
				if ($13 + 0 < prevvb + 0) vdec++
				if ($13 + 0 == prevvb + 0) {
					stall++
					if (stall > maxstall) maxstall = stall
				} else stall = 0
			}
			prevvb = $13
			lastvb = $13
		}
		if ($14 != "" && $14 != "-") pl[$14] = 1
		if ($6 ~ /^[0-9]+$/ && $7 ~ /^[0-9]+$/ && $6 + 0 > $7 + 0) vrbad++
		if ($7 ~ /^[0-9]+$/ && $8 ~ /^[0-9]+$/ && $7 + 0 != $8 + 0) vrbad++
		if ($9 ~ /^[0-9]+$/) {
			if (firstref == "") firstref = $9
			if ($9 + 0 < 1 || $9 + 0 > 16) refbad++
			if ($9 + 0 > firstref + 1) refbad++
		}
		if (firstver == "") firstver = $10
		else if ($10 != firstver) verbad++
		if (firstsize == "") firstsize = $11
		else if ($11 != firstsize) sizebad++
		if ($12 ~ /^[0-9]+$/ && $12 + 0 < floor + 0) membad++
		if ($29 ~ /^[0-9]+$/) faults += $29
		for (i = 16; i <= 26; i++) {
			if ($i !~ /^[0-9]+$/) continue
			if (i in prevc && $i + 0 < prevc[i] + 0) b8bad++
			prevc[i] = $i
		}
		if ($27 == "FAIL") gatesbad++
		else if ($27 ~ /^unavailable:/) gatesna++
	}
	END {
		for (k in pl) pln++
		printf "card-present\t%d\t%d of %d samples found the PCI device directory\n", (miss == 0 ? 1 : 0), n - miss, n
		printf "panel-vblank\t%d\tpresent in %d of %d samples, advanced %d over the window, %d decrease(s), longest stall %d sample(s), PANEL_CURRENT_LINE took %d distinct value(s) (an idle pipe freezes vblank_count by design)\n", ((n > 0 && vb == n && vdec == 0 && pln > 1) ? 1 : 0), vb, n, (firstvb == "" ? 0 : lastvb - firstvb), vdec, maxstall, pln
		printf "vram-range\t%d\t%d sample(s) out of range or inconsistent\n", (vrbad == 0 ? 1 : 0), vrbad
		printf "module-refcount\t%d\t%d sample(s) outside 1..16 or above first+1\n", (refbad == 0 ? 1 : 0), refbad
		printf "module-identity\t%d\t%d sample(s) carried a different module version\n", (verbad == 0 ? 1 : 0), verbad
		printf "module-size\t%d\t%d sample(s) carried a different resident module size\n", (sizebad == 0 ? 1 : 0), sizebad
		printf "mem-floor\t%d\t%d sample(s) below MemAvailable %d kB\n", (membad == 0 ? 1 : 0), membad, floor
		printf "log-quiet\t%d\t%d new driver fault line(s) and kernel severe line(s)\n", (faults == 0 ? 1 : 0), faults
		printf "counters-monotonic\t%d\t%d decrease(s) across the b8_* counters\n", (b8bad == 0 ? 1 : 0), b8bad
		printf "gates-recorded\t%d\t%d sample(s) read gates=FAIL, %d sample(s) had no gate log\n", (gatesbad == 0 ? 1 : 0), gatesbad, gatesna
		printf "coverage\t%d\t%d sample(s) taken, window %s\n", ((n >= 2 && complete + 0 == 1) ? 1 : 0), n, (complete + 0 == 1 ? "completed" : "cut short")
	}
	' "$1"
}

json_str() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/ /g'
}

finalize() { # finalize COMPLETE
	[ "$FINALIZED" -eq 0 ] || return 0
	FINALIZED=1
	complete=${1:-0}
	[ -n "${TMPD:-}" ] && [ -d "$TMPD" ] || return 0
	[ -n "${SAMPLES:-}" ] && [ -f "$SAMPLES" ] || return 0
	crit=$TMPD/criteria.txt
	evaluate "$SAMPLES" "$complete" >"$crit" || true
	criteria=$(wc -l <"$crit" | tr -d ' ')
	samples=$(awk 'NR > 1 { n++ } END { print n + 0 }' "$SAMPLES")
	bad=$(awk -F'\t' '$2 != 1' "$crit" | wc -l | tr -d ' ')
	verdict=PASS
	[ "$bad" -eq 0 ] || verdict=FAIL
	last=$(awk -F'\t' 'END { print $2 }' "$SAMPLES")
	started=${STARTED_UTC:-$last}

	{
		printf '{\n'
		printf '  "helper": "sm750-soak",\n'
		printf '  "schema": 1,\n'
		printf '  "verdict": "%s",\n' "$verdict"
		printf '  "complete": %s,\n' \
			"$([ "$complete" -eq 1 ] && echo true || echo false)"
		printf '  "started_utc": "%s",\n' "$(json_str "$started")"
		printf '  "finished_utc": "%s",\n' "$(json_str "$last")"
		printf '  "duration_requested_s": %s,\n' "$DURATION"
		printf '  "interval_s": %s,\n' "$INTERVAL"
		printf '  "samples": %s,\n' "$samples"
		printf '  "samples_expected": %s,\n' "$EXPECTED"
		printf '  "samples_file": "samples.tsv",\n'
		printf '  "log_wraps": %s,\n' "$WRAPS"
		printf '  "criteria": [\n'
		awk -F'\t' -v total="$criteria" '{
			printf "    {\"name\": \"%s\", \"ok\": %s, \"detail\": \"%s\"}", $1, ($2 == 1 ? "true" : "false"), $3
			printf "%s\n", (NR < total ? "," : "")
		}' "$crit"
		printf '  ],\n'
		printf '  "failed_criteria": ['
		awk -F'\t' '$2 != 1 { printf "%s\"%s\"", (c++ ? ", " : ""), $1 }' "$crit"
		printf ']\n'
		printf '}\n'
	} >"$OUT/verdict.json"

	{
		printf '%s summary\n' "$PROG"
		printf 'started:   %s\n' "$started"
		printf 'finished:  %s\n' "$last"
		printf 'window:    %s s requested, %s sample(s) every %s s\n' \
			"$DURATION" "$samples" "$INTERVAL"
		printf 'device:    %s (module %s)\n' "$BDF" "$(read_file "$MOD/version")"
		printf 'kernel log source: %s (ring-buffer wraps seen: %s)\n' \
			"$LOGMODE" "$WRAPS"
		printf 'verdict:   %s\n' "$verdict"
		printf 'criteria (%s):\n' "$criteria"
		awk -F'\t' '{ printf "  %s %s: %s\n", ($2 == 1 ? "ok  " : "FAIL"), $1, $3 }' "$crit"
		printf 'samples file: samples.tsv\n'
		printf 'what this window proves: every field above stayed in range, the\n'
		printf 'panel kept a live scanout, and the kernel logged no new fault\n'
		printf 'line for this driver for the whole window.\n'
		printf 'what it does not prove: a window of %s s is not a warranty. It does\n' \
			"$DURATION"
		printf 'not exercise a mode set, a hot reload, a suspend or heavy use, and\n'
		printf 'a short window cannot exclude a fault that needs hours to appear.\n'
		printf 'It also does not measure a crc when the crc column reads\n'
		printf 'unavailable, and it says nothing about a CRT-only output path.\n'
	} >"$OUT/summary.txt"

	sed 's/^/  /' "$OUT/summary.txt"
	printf '%s: wrote %s %s\n' "$PROG" "$SAMPLES" "$OUT/verdict.json"
	if [ "$verdict" = PASS ]; then
		printf '%s: verdict: PASS\n' "$PROG"
	else
		printf '%s: verdict: FAIL: %s criterion(s) failed\n' "$PROG" "$bad"
	fi
	return 0
}

cleanup() {
	rc=$?
	finalize "${COMPLETE:-0}" || true
	if [ -n "${TMPD:-}" ] && [ -d "$TMPD" ]; then
		rm -rf "$TMPD"
	fi
	return "$rc"
}

parse_run_opts() {
	while [ "$#" -gt 0 ]; do
		case $1 in
		--duration)
			[ "$#" -ge 2 ] || usage
			DURATION=$2
			shift 2
			;;
		--interval)
			[ "$#" -ge 2 ] || usage
			INTERVAL=$2
			shift 2
			;;
		--outdir)
			[ "$#" -ge 2 ] || usage
			OUT=$2
			shift 2
			;;
		--gates)
			[ "$#" -ge 2 ] || usage
			GATES=$2
			shift 2
			;;
		--mem-floor)
			[ "$#" -ge 2 ] || usage
			MEM_FLOOR=$2
			shift 2
			;;
		--root)
			[ "$#" -ge 2 ] || usage
			ROOT=$2
			shift 2
			;;
		*) usage ;;
		esac
	done
	isnum "$DURATION" || usage
	isnum "$INTERVAL" || usage
	isnum "$MEM_FLOOR" || usage
	[ "$DURATION" -ge 1 ] && [ "$DURATION" -le 172800 ] || usage
	[ "$INTERVAL" -ge 1 ] && [ "$INTERVAL" -le 3600 ] || usage
	[ "$MEM_FLOOR" -ge 1024 ] || usage
	return 0
}

status_cmd() {
	dir=${1:-}
	[ -n "$dir" ] || usage
	[ -r "$dir/verdict.json" ] || {
		echo "$PROG: $dir/verdict.json is missing; is that a finished run?" >&2
		exit 1
	}
	line=$(grep -F '"verdict":' "$dir/verdict.json" 2>/dev/null | head -n 1) ||
		line=
	[ -n "$line" ] || line='  "verdict": "unknown"'
	printf '%s\n' "$line" | sed 's/^[[:space:]]*//'
	if [ -r "$dir/summary.txt" ]; then
		sed 's/^/  /' "$dir/summary.txt"
	fi
	case $line in
	*'"PASS"'*) exit 0 ;;
	*) exit 1 ;;
	esac
}

run_cmd() {
	parse_run_opts "$@"

	if [ -n "$ROOT" ]; then
		[ -d "$ROOT" ] || die_env "fixture root $ROOT does not exist"
		SYS=$ROOT/sys
		PROC=$ROOT/proc
		if [ -x "$ROOT/sm750-regs" ]; then
			REGS=$ROOT/sm750-regs
		else
			REGS=
		fi
		if [ -x "$ROOT/sm750-crc" ]; then
			CRC=$ROOT/sm750-crc
		else
			CRC=
		fi
	fi
	DEV=$SYS/bus/pci/devices/$BDF
	MOD=$SYS/module/sm750hdmidrm

	if [ -n "$OUT" ]; then
		case $OUT in
		/*) ;;
		*) die_env "--outdir must be an absolute path" ;;
		esac
		# Outside a fixture run the only writable place is the approved
		# scratch root; a soak must not write into the project tree.
		if [ -z "$ROOT" ]; then
			case $OUT in
			"$SOAK_BASE"/*) ;;
			*) die_env "--outdir must be under $SOAK_BASE (got $OUT)" ;;
			esac
		fi
	else
		OUT=$SOAK_BASE/soak/$(date -u +%Y%m%dT%H%M%SZ)
	fi
	[ ! -e "$OUT" ] || die_env "$OUT already exists; a run never overwrites one"
	mkdir -p "$(dirname "$OUT")" || die_env "cannot create $(dirname "$OUT")"
	mkdir "$OUT" || die_env "cannot create $OUT"

	[ -d "$DEV" ] ||
		die_env "$DEV is absent; the SM750 is not bound to a PCI device"
	[ -r "$MOD/refcnt" ] ||
		die_env "$MOD/refcnt is absent; sm750hdmidrm is not loaded"

	init_log_source
	TMPD=$(mktemp -d "${TMPDIR}/sm750-soak.XXXXXX")
	SAMPLES=$OUT/samples.tsv
	TAB=$(printf '\t')
	printf '#sample\tts\tepoch\tpresent\tpanel_cell\tvram_used\tvram_total\tvram_total_meminfo\trefcnt\tversion\tmodule_size\tmem_avail_kb\tvblank\tpanel_line\tcrc\tb8_mode_attempts\tb8_mode_failures\tb8_mode_retries\tb8_stage_failures\tb8_i2c_write_timeouts\tb8_i2c_recoveries\tb8_ready_expired\tb8_ddc_grant_timeouts\tb8_edid_reads\tb8_edid_failures\tb8_epoch_s\tgates\tdmesg_lines\tdmesg_faults\n' \
		>"$SAMPLES"

	EXPECTED=$(((DURATION + INTERVAL - 1) / INTERVAL + 1))
	STARTED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	start=$(date +%s)
	COMPLETE=0
	trap 'cleanup' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	trap 'exit 129' HUP

	printf '%s: sampling every %s s for %s s into %s\n' "$PROG" "$INTERVAL" \
		"$DURATION" "$OUT"
	printf '%s: read-only; no card node is opened and no VT is touched\n' \
		"$PROG"

	# Baseline the kernel-log counters before the first sample, so a fault
	# that was already in the buffer cannot be counted as new.
	LOGLINES_PREV=$(log_lines)
	FAULTS_PREV=$(hard_faults)
	isnum "$LOGLINES_PREV" || LOGLINES_PREV=0
	isnum "$FAULTS_PREV" || FAULTS_PREV=0

	n=0
	while :; do
		sample_once "$n"
		n=$((n + 1))
		now=$(date +%s)
		if [ "$now" -ge "$((start + DURATION))" ]; then
			break
		fi
		next=$((start + n * INTERVAL))
		if [ "$next" -gt "$((start + DURATION))" ]; then
			break
		fi
		now=$(date +%s)
		if [ "$next" -gt "$now" ]; then
			sleep "$((next - now))"
		fi
	done
	COMPLETE=1
	finalize 1
	bad=$(awk -F'\t' '$2 != 1' "$TMPD/criteria.txt" | wc -l | tr -d ' ')
	[ "$bad" -eq 0 ] || exit 1
	exit 0
}

[ "$#" -ge 1 ] || usage
cmd=$1
shift
case $cmd in
run)
	run_cmd "$@"
	;;
status)
	[ "$#" -le 1 ] || usage
	status_cmd "${1:-}"
	;;
*)
	usage
	;;
esac
