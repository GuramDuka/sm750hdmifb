#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Scratch-policy gate: AGENTS.md:26 says scratch files go under
# /mega/tmp/sm750/ only. TMPDIR is unset on this host, so a bare mktemp falls
# back to /tmp and leaks there - nine tests/check-static.sh runs had left
# /tmp/sm750-static.* directories of 15 MB each. This gate keeps the fix in
# place: every script that calls mktemp exports the repository resolver before
# its first call, and every template interpolates ${TMPDIR} instead of naming
# /tmp.
#
# It also pins the restore stress harness to the fault census of
# docs/evidence/runtime/22-restore-fix-hardware-proof.txt: the harness used to
# look for three markers while the proof greps nine, so the two could drift.
#
# The gate re-runs itself against planted defects, so it cannot pass by
# accident. Usage: tests/check-scratch-policy.sh [repo dir]
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "${1:-$(dirname -- "$0")/..}" && pwd)
resolver='export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}'
census='failed to enable HDMI mode|flip_done timed out|commit wait timed out|refcount_t: underflow|did not latch|panel did not acknowledge|enable-fail state|WARNING|BUG:'
proof=docs/evidence/runtime/22-restore-fix-hardware-proof.txt
harness=tools/sm750-restore-cycle.sh

# Scripts that call mktemp for scratch, relative to the tree root.
scripts=(
	build-package.sh
	tests/audit-release.sh
	tests/check-drm-xorg-config.sh
	tests/check-rpm-dkms.sh
	tests/check-static.sh
	tests/check-crc-uapi.sh
	tests/check-console-blank.sh
	tests/check-restore-path.sh
	tools/benchmark-staging.sh
	tools/sm750-crc-cycle.sh
)
# packaging/write-xorg-config.sh also calls mktemp, but its template is
# "${output}.XXXXXX" on purpose: the temporary file must sit on the same
# filesystem as the file it is renamed onto, so TMPDIR would break the atomic
# write. It is not scratch and is exempt from the rule.
exempt=packaging/write-xorg-config.sh

fail=0
complain() {
	echo "scratch policy: $*" >&2
	fail=1
}

check_tree() {
	local root=$1 script first_mktemp first_export bad got
	for script in "${scripts[@]}"; do
		if [ ! -f "$root/$script" ]; then
			complain "$script is missing"
			continue
		fi
		first_mktemp=$(grep -n 'mktemp' "$root/$script" |
			head -n 1 | cut -d: -f1 || true)
		if [ -z "$first_mktemp" ]; then
			complain "$script no longer calls mktemp; drop it from the list"
			continue
		fi
		first_export=$(grep -nF "$resolver" "$root/$script" |
			head -n 1 | cut -d: -f1 || true)
		if [ -z "$first_export" ]; then
			complain "$script does not export $resolver"
			continue
		fi
		if [ "$first_export" -gt "$first_mktemp" ]; then
			complain "$script exports TMPDIR at :$first_export, after its first mktemp at :$first_mktemp"
		fi
		# A template that names /tmp bypasses the resolver entirely.
		bad=$(grep -n 'mktemp' "$root/$script" | grep -F '/tmp' || true)
		if [ -n "$bad" ]; then
			complain "$script still names /tmp in a mktemp template: $bad"
		fi
		# And every template must actually interpolate TMPDIR.
		bad=$(grep -n 'mktemp' "$root/$script" | grep -vF '${TMPDIR}' || true)
		if [ -n "$bad" ]; then
			complain "$script mktemp template does not use \${TMPDIR}: $bad"
		fi
	done
	if [ -f "$root/$exempt" ] && grep -qF '${TMPDIR}' "$root/$exempt"; then
		complain "$exempt now interpolates TMPDIR; the exemption is stale"
	fi

	# Harness census: the marker alternation must be the proof's, verbatim.
	got=$(grep -o "grep -E 'failed to enable HDMI mode[^']*'" \
		"$root/$harness" | head -n 1 | sed "s/^grep -E '//; s/'\$//" || true)
	if [ -z "$got" ]; then
		complain "$harness has no nine-marker census grep"
	elif [ "$got" != "$census" ]; then
		complain "$harness census differs from the fault census"
	fi
	if [ -f "$root/$proof" ]; then
		got=$(grep -oE "failed to enable HDMI mode\|flip_done timed out[^']*BUG:" \
			"$root/$proof" | head -n 1 || true)
		if [ "$got" != "$census" ]; then
			complain "the hardware proof census changed; update the harness and this gate together"
		fi
	fi
}

check_tree "$project_dir"
[ "$fail" -eq 0 ] || exit 1

# --- planted defects: the gate must reject each of them ----------------------
# Only the files the gate reads are copied, so the check stays fast.
[ "${1:-}" = "" ] || exit 0
scratch=$(mktemp -d "${TMPDIR}/sm750-scratch-gate.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

plant() {
	# $1 name, $2 file, $3 expected message fragment, rest: sed arguments
	local name=$1 file=$2 want=$3 tree out path
	shift 3
	tree=$scratch/$name
	for path in "${scripts[@]}" "$exempt" "$harness" "$proof"; do
		install -D "$project_dir/$path" "$tree/$path"
	done
	sed -i "$@" "$tree/$file"
	if out=$(bash "$0" "$tree" 2>&1); then
		complain "planted defect '$name' was not caught"
	elif ! grep -qF "$want" <<<"$out"; then
		complain "planted defect '$name' failed for the wrong reason: $out"
	fi
}

# 1. The original leak: an absolute /tmp template.
plant tmp-template tests/check-crc-uapi.sh 'still names /tmp' \
	's|mktemp -d "${TMPDIR}/|mktemp -d /tmp/|'
# 2. The resolver deleted, so mktemp falls back to /tmp on this host.
plant no-resolver tests/check-console-blank.sh 'does not export' \
	'/^export TMPDIR=\${TMPDIR:-\/mega\/tmp\/sm750\/tmp}$/d'
# 3. The resolver present but below the first mktemp: too late to help.
plant late-resolver tests/audit-release.sh 'after its first mktemp' \
	-e '/^export TMPDIR=/d' \
	-e '/mktemp /a export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}'
# 4. The harness census shrunk back to the three fix markers.
plant census-drift tools/sm750-restore-cycle.sh 'census differs' \
	's/|flip_done timed out.*BUG:/|WARNING|BUG:/'
# 5. A template that interpolates something else entirely.
plant foreign-template tests/check-rpm-dkms.sh 'does not use' \
	's|"\${TMPDIR}/sm750-rpm-tracked|"${HOME}/sm750-rpm-tracked|'

[ "$fail" -eq 0 ] || exit 1
echo "Scratch policy checks passed (10 scripts, resolver before first mktemp, census pinned)"
