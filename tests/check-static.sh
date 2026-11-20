#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Opt-in static-analysis gate. NOT part of `make check`: that target's recipe
# command count is asserted by tests/check-drm-module.sh and documented in
# docs/AUDIT.md, so this gate is a separate `make static` target.
#
# Each analyser is run, its findings are normalised to fingerprints that carry
# no line numbers (a line shift must not look like a new defect), and the
# fingerprint multiset is compared against tests/static/baseline/<tool>.txt.
# Any fingerprint beyond the recorded baseline fails the gate.
#
#   ./tests/check-static.sh                 run and compare against baseline
#   ./tests/check-static.sh --update        rewrite the baseline from this run
#   ./tests/check-static.sh --logs DIR      keep raw analyser output in DIR
#
# When none of the analysers is installed the gate exits 0 with a skip notice,
# so a machine without the toolchain can still build, package and run
# `make check`.
#
# Triage of the recorded findings: docs/STATIC-ANALYSIS.md.
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
baseline_dir=$project_dir/tests/static/baseline
CC=${CC:-/usr/bin/gcc}
# Tool messages are localised: the fingerprints must not change with the host
# locale, and the parser below matches English severity words. LANGUAGE
# overrides LC_ALL for GNU gettext, so it has to be cleared as well, otherwise
# make's own "entering directory" lines come out in the host language and the
# logs are no longer ASCII.
export LC_ALL=C
# The kernel Makefile does `unexport LC_ALL`, so the sub-make would fall back to
# the host LANG; set LANG/LC_MESSAGES as well to keep the captured logs ASCII.
export LANG=C LC_MESSAGES=C
unset LANGUAGE
# Coccinelle's Python bridge locates libpython by running
# `pkg-config --libs python-3.14`. That probe answers with the empty string
# when libpython lives in a system directory, but a caller's pkg-config
# resolver settings change the answer: with PKG_CONFIG_SYSROOT_DIR set
# (docs/ENVIRONMENT.md section 4 exports it for the rootless libdrm build) the
# answer becomes "-L<mega>/t3/libdrm/usr/lib64", spatch cannot parse it and
# every .cocci invocation exits 255 before analysing a single file. The gate
# analyses C and uses pkg-config nowhere else, so the probe runs with the
# resolver variables cleared. Proved in docs/evidence/builds/28-static-determinism.log.
unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_PATH PKG_CONFIG_LIBDIR
KDIR=${KDIR:-/lib/modules/$(uname -r)/build}
update=0
logdir=
while [ $# -gt 0 ]; do
	case $1 in
	--update) update=1 ;;
	--logs) logdir=${2:?--logs needs a directory}; shift ;;
	-h|--help) sed -n '3,20p' "$0"; exit 0 ;;
	*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done
own_logdir=0
if [ -z "$logdir" ]; then
	logdir=$(mktemp -d "${TMPDIR}/sm750-static.XXXXXX")
	own_logdir=1
fi
# Drop our own directory only on a pass: a failing run's raw logs are the
# evidence for the finding, so they survive and the path is printed below.
# A --logs directory belongs to the caller and is never removed.
if [ "$own_logdir" -eq 1 ]; then
	trap 'rc=$?; if [ "$rc" -eq 0 ]; then rm -rf -- "$logdir"; fi' EXIT
fi
mkdir -p "$logdir"
logdir=$(CDPATH= cd -- "$logdir" && pwd)

have() { command -v "$1" >/dev/null 2>&1; }

# Kernel trees to analyse: the configured one plus anything in STATIC_KERNELS
# (space separated). The first entry also drives the cppcheck and pahole runs.
kdirs=("$KDIR")
if [ -n "${STATIC_KERNELS:-}" ]; then
	read -r -a extra <<<"${STATIC_KERNELS}"
	kdirs+=("${extra[@]}")
fi

tree_key() { basename "$(readlink -f "$1")"; }

analysers=()
have sparse && analysers+=(sparse)
have smatch && analysers+=(smatch)
have cppcheck && have bear && analysers+=(cppcheck)
have spatch && analysers+=(coccinelle)
have pahole && analysers+=(pahole)
if [ ${#analysers[@]} -eq 0 ]; then
	echo "analysers not installed, skipping"
	echo "  install sparse, smatch, cppcheck, bear, coccinelle, pahole to enable"
	exit 0
fi
echo "static gate: ${analysers[*]}"
echo "  kernel trees: ${kdirs[*]}"
if [ "$own_logdir" -eq 1 ]; then
	echo "  raw logs:     $logdir (removed on pass)"
else
	echo "  raw logs:     $logdir"
fi

fail=0
# Fresh fingerprint files: the log directory may be reused between runs, and
# appending to a stale file would double-count every finding.
for tool in sparse smatch cppcheck coccinelle; do
	: >"$logdir/$tool.fingerprints"
done

note_missing() {
	echo "  skip: $1 not installed"
}

# --- sparse -----------------------------------------------------------------
if have sparse; then
	for kdir in "${kdirs[@]}"; do
		key=$(tree_key "$kdir")
		log=$logdir/sparse-${key}.log
		# Force a real compilation: kbuild only runs the checker on files
		# it rebuilds, so a warm tree would report no findings at all.
		make -C "$kdir" M="$project_dir/src" clean >/dev/null 2>&1 || true
		set +e
		make -C "$project_dir" KDIR="$kdir" CC="$CC" C=2 \
			CHECK="$project_dir/tests/static/sparse-check" all \
			>"$log" 2>&1
		rc=$?
		set -e
		# Only driver-file lines are findings: the kernel headers carry their
		# own warnings under any non-default warning set.
		matches=$(sed -n 's/^\([a-zA-Z0-9_]*\.c\):[0-9]*:[0-9]*: \(warning: .*\)$/\1 \2/p' \
			"$log" | sort || true)
		count=$(printf '%s' "$matches" | grep -c . || true)
		echo "sparse[$key]: exit $rc, $count warning(s)"
		printf '%s\n' "$matches" | grep . |
			sed "s|^|$key sparse |" >>"$logdir/sparse.fingerprints" || true
		[ "$rc" -eq 0 ] || { echo "  sparse build failed, see $log" >&2; fail=1; }
	done
else
	note_missing sparse
fi

# --- smatch -----------------------------------------------------------------
if have smatch; then
	for kdir in "${kdirs[@]}"; do
		key=$(tree_key "$kdir")
		log=$logdir/smatch-${key}.log
		make -C "$kdir" M="$project_dir/src" clean >/dev/null 2>&1 || true
		set +e
		make -C "$project_dir" KDIR="$kdir" CC="$CC" C=2 \
			CHECK="$project_dir/tests/static/smatch-check" all \
			>"$log" 2>&1
		rc=$?
		set -e
		# smatch prefixes driver findings with the source basename and prints
		# function context; header noise appears as an absolute path.
		matches=$(sed -n \
			's/^\([a-zA-Z0-9_]*\.c\):[0-9]* \(.*\)$/smatch \1 \2/p' \
			"$log" | grep -E ' (warn|error|info): ' | sort || true)
		count=$(printf '%s' "$matches" | grep -c . || true)
		echo "smatch[$key]: exit $rc, $count finding(s)"
		printf '%s\n' "$matches" | grep . |
			sed "s|^|$key |" >>"$logdir/smatch.fingerprints" || true
		[ "$rc" -eq 0 ] || { echo "  smatch build failed, see $log" >&2; fail=1; }
	done
else
	note_missing smatch
fi

# --- cppcheck ---------------------------------------------------------------
if have cppcheck && have bear; then
	work=$logdir/cppcheck-tree
	rm -rf "$work"
	mkdir -p "$work"
	cp -a "$project_dir/src" "$work/src"
	cp "$project_dir/Makefile" "$work/Makefile"
	# The copy carries the current build artefacts; clean them so bear records
	# a real compilation instead of an up-to-date no-op.
	make -C "$work" KDIR="${kdirs[0]}" CC="$CC" clean >/dev/null 2>&1 || true
	bear --output "$work/compile_commands.json" -- \
		make -C "$work" KDIR="${kdirs[0]}" CC="$CC" all \
		>"$logdir/cppcheck-bear.log" 2>&1 || {
		echo "  bear could not record the build, see $logdir/cppcheck-bear.log" >&2
		fail=1
	}
	python3 "$project_dir/tests/static/mk-cppdb.py" \
		"$work/compile_commands.json" "$work/cppcheck-db.json" \
		>>"$logdir/cppcheck-bear.log"
	log=$logdir/cppcheck.log
	set +e
	cppcheck --project="$work/cppcheck-db.json" \
		--enable=warning,performance,portability \
		--inline-suppr --std=c11 --platform=unix64 \
		--template='{file}:{line}:{column}: {severity}: {id}: {message}' \
		--suppress=missingIncludeSystem \
		--suppress=unusedFunction \
		--suppress=unknownMacro \
		-q >"$log" 2>&1
	rc=$?
	set -e
	# Normalise away the scratch path and the line number; keep file, severity
	# and checker id, which is what identifies the finding.
	matches=$(sed -n \
		's|.*/src/\([a-zA-Z0-9_]*\.c\):[0-9]*:[0-9]*: \([a-z]*\): \([A-Za-z0-9]*\):.*|cppcheck \1 \2 \3|p' \
		"$log" | sort || true)
	count=$(printf '%s' "$matches" | grep -c . || true)
	echo "cppcheck: exit $rc, $count finding(s)"
	printf '%s\n' "$matches" | grep . >>"$logdir/cppcheck.fingerprints" || true
	[ "$rc" -eq 0 ] || { echo "  cppcheck failed, see $log" >&2; fail=1; }
else
	note_missing "cppcheck+bear"
fi

# --- coccinelle -------------------------------------------------------------
if have spatch; then
	log=$logdir/coccinelle.log
	: >"$log"
	rc=0
	for patch in "$project_dir"/tests/static/cocci/*.cocci; do
		[ -e "$patch" ] || continue
		echo "# $(basename "$patch")" >>"$log"
		set +e
		spatch --sp-file "$patch" --no-includes --include-headers \
			-I "$project_dir/src" "$project_dir"/src/*.c >>"$log" 2>&1
		sub=$?
		set -e
		if [ "$sub" -ne 0 ]; then
			echo "  spatch exit $sub on $(basename "$patch")" >&2
			rc=$sub
		fi
	done
	# Kernel-tree patches, when the tree ships scripts/coccinelle. These are
	# report-only: several need -D report to emit anything.
	kdir=${kdirs[0]}
	if [ -d "$kdir/scripts/coccinelle" ]; then
		for patch in null/deref_null.cocci api/err_cast.cocci \
			misc/array_size.cocci locks/double_lock.cocci \
			null/kmerr.cocci api/kfree_mismatch.cocci \
			misc/minmax.cocci misc/struct_size.cocci null/badzero.cocci; do
			[ -e "$kdir/scripts/coccinelle/$patch" ] || continue
			echo "# kernel $patch" >>"$log"
			set +e
			spatch -D report --sp-file "$kdir/scripts/coccinelle/$patch" \
				--no-includes --include-headers \
				"$project_dir"/src/*.c >>"$log" 2>&1
			sub=$?
			set -e
			if [ "$sub" -ne 0 ]; then
				echo "  spatch exit $sub on kernel $patch" >&2
				rc=$sub
			fi
		done
	fi
	matches=$(sed -n \
		's|^\([a-z-]*\): .*/src/\([a-zA-Z0-9_]*\.c\):[0-9]*$|coccinelle \1 \2|p' \
		"$log" | sort || true)
	count=$(printf '%s' "$matches" | grep -c . || true)
	echo "coccinelle: exit $rc, $count finding(s)"
	printf '%s\n' "$matches" | grep . >>"$logdir/coccinelle.fingerprints" || true
	[ "$rc" -eq 0 ] || {
		if [ "$rc" -eq 255 ]; then
			echo "  spatch fatal exit (255: internal error or patch parse error, not a finding), see $log" >&2
		else
			echo "  spatch failed, see $log" >&2
		fi
		fail=1
	}
else
	note_missing spatch
fi

# --- pahole -----------------------------------------------------------------
# Informational only: struct padding is an alignment property of the target
# ABI, not a defect, and BTF is unavailable for out-of-tree modules built
# without a vmlinux for the target tree.
if have pahole; then
	work=$logdir/pahole-tree
	rm -rf "$work"
	mkdir -p "$work"
	cp -a "$project_dir/src" "$work/src"
	cp "$project_dir/Makefile" "$work/Makefile"
	make -C "$work" KDIR="${kdirs[0]}" CC="$CC" clean >/dev/null 2>&1 || true
	log=$logdir/pahole.log
	set +e
	make -C "$work" KDIR="${kdirs[0]}" CC="$CC" KCFLAGS=-g all \
		>"$log" 2>&1
	rc=$?
	set -e
	{
		echo "## pahole --version"
		pahole --version
		echo "## BTF status of sm750hdmidrm.ko"
		if readelf -S "$work/src/sm750hdmidrm.ko" | grep -q '\.BTF'; then
			echo "BTF: present"
		else
			echo "BTF: absent (no vmlinux BTF for the target tree;"
			echo "     see docs/STATIC-ANALYSIS.md, out of scope)"
		fi
		echo "## driver struct layouts"
		for type in sm750_drm_device sm750_scanout_mode mode_parameter \
			sm750_dither sm750_dither_scale_map \
			sm750_dither_scale_sample sm750_source_run pll_value \
			initchip_param; do
			pahole -C "$type" "$work/src/sm750_drm.o" 2>/dev/null ||
				echo "pahole: struct $type not in sm750_drm.o"
		done
	} >>"$log" 2>&1
	echo "pahole: exit $rc (informational, struct layout in $log)"
	[ "$rc" -eq 0 ] || { echo "  pahole build failed, see $log" >&2; fail=1; }
else
	note_missing pahole
fi

# --- baseline comparison ----------------------------------------------------
mkdir -p "$baseline_dir"
for tool in sparse smatch cppcheck coccinelle; do
	[ -e "$logdir/$tool.fingerprints" ] || continue
	# Collapse repeats to "count fingerprint": a second copy of an already
	# recorded finding is a new finding, while a line shift is not.
	counts=$logdir/$tool.counts
	sort "$logdir/$tool.fingerprints" | uniq -c |
		sed 's/^ *\([0-9][0-9]*\) /\1 /' | sort >"$counts"
	baseline=$baseline_dir/$tool.txt
	if [ "$update" -eq 1 ]; then
		cp "$counts" "$baseline"
		echo "baseline updated: ${baseline#$project_dir/}"
		continue
	fi
	if [ ! -e "$baseline" ]; then
		echo "no baseline for $tool: run ./tests/check-static.sh --update" >&2
		fail=1
		continue
	fi
	if ! new=$(comm -13 "$baseline" "$counts" | grep . || true); then
		new=
	fi
	if [ -n "$new" ]; then
		echo "NEW $tool findings beyond the recorded baseline:" >&2
		printf '%s\n' "$new" | sed 's/^/  /' >&2
		fail=1
	fi
done

if [ "$fail" -ne 0 ]; then
	echo "static gate: FAIL (raw logs in $logdir)"
	if [ "$own_logdir" -eq 1 ]; then
		echo "static analysis logs kept at: $logdir"
	fi
	exit 1
fi
if [ "$own_logdir" -eq 1 ]; then
	echo "static gate: PASS"
else
	echo "static gate: PASS (raw logs in $logdir)"
fi
