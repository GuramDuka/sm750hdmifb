#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dist_dir=$project_dir/dist
readonly version=$(sed -n 's/^readonly version=//p' "$project_dir/build-package.sh")
test -n "$version"
package=sm750hdmifb
module=$project_dir/src/sm750hdmidrm.ko
deb=$dist_dir/${package}_${version}_all.deb
source_archive=$dist_dir/${package}-${version}-source.tar.gz
report=$dist_dir/RELEASE-AUDIT.txt

for required in "$module" "$deb" "$source_archive" "$project_dir/LICENSE"; do
	[[ -s $required ]] || {
		echo "Missing release input: $required" >&2
		exit 1
	}
done

# Any release artifact name mentioned by the workflow must carry the version
# this tree builds; the old gate only knew 0.5.0-0.5.5 (defect A16).
stale_artifacts=$(rg -o 'sm750hdmifb[-_][0-9]+\.[0-9]+\.[0-9]+' \
	"$project_dir/.github/workflows/build.yml" |
	grep -vF -- "-$version" | grep -vF -- "_$version" || true)
if [[ -n $stale_artifacts ]]; then
	echo "Manual build workflow contains a stale release version:" >&2
	echo "$stale_artifacts" >&2
	exit 1
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/sm750-release-audit.XXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT
dpkg-deb -e "$deb" "$tmpdir/control"
dpkg-deb -x "$deb" "$tmpdir/deb"
mkdir -p "$tmpdir/src"
tar -xzf "$source_archive" -C "$tmpdir/src"
source_root=$tmpdir/src/${package}-${version}
[[ -d $source_root ]] || {
	echo "Source archive does not contain $package-$version." >&2
	exit 1
}

for forbidden in .audit-source .package-build xorg-sm750shadow xorg-sm750.strace; do
	if find "$tmpdir" -name "*$forbidden*" | grep . >/dev/null; then
		echo "Forbidden development content packaged: $forbidden" >&2
		exit 1
	fi
done

# Untracked developer material must never ship (defect A02), and the
# development-only directories - the screenshots, the session plans and the
# captured transcripts - are deliberately kept out of the build-only archive
# (defects A22, A29). The list is declared once, in
# packaging/source-excludes.sh, which build-package.sh also reads, so the gate
# and the packager cannot drift apart again.
# shellcheck source=../packaging/source-excludes.sh
. "$project_dir/packaging/source-excludes.sh"
for dev_only in "${sm750_dev_only[@]}"; do
	if [[ -e $source_root/$dev_only ]]; then
		echo "Source archive contains development-only content: $dev_only" >&2
		exit 1
	fi
done

# The archive is the tracked tree minus that same list; anything else means the
# packaging script has drifted from the repository again.
if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
	mapfile -t exclude_pathspecs < <(sm750_dev_only_pathspecs)
	(cd "$source_root" && find . -type f -printf '%P\n' | sort) \
		>"$tmpdir/shipped"
	git -C "$project_dir" ls-files -- . "${exclude_pathspecs[@]}" |
		sort >"$tmpdir/tracked"
	if ! diff -u "$tmpdir/tracked" "$tmpdir/shipped" >"$tmpdir/manifest.diff"; then
		cat "$tmpdir/manifest.diff" >&2
		echo "Source archive does not match the tracked tree." >&2
		exit 1
	fi
fi

# The audit now looks at what actually ships, not at the worktree, so an
# untracked note cannot fail a release and a tracked file cannot hide.
release_text=(
	"$source_root"
	"$tmpdir/deb"
)

# Keep this generic: adding a real local username or machine ID to the audit
# would itself disclose the value in the published source tree.
private_pattern='/home/[[:alnum:]_.-]+|/Users/[[:alnum:]_.-]+|[A-Za-z]:\\Users\\|ghp_[[:alnum:]]{20,}|github_pat_[[:alnum:]_]{20,}'
if rg -n -i "$private_pattern" --glob '!audit-release.sh' "${release_text[@]}"; then
	echo "Local path, machine identifier, or credential pattern remains." >&2
	exit 1
fi

if rg -n -i 'without (the )?written consent|all rights reserved|confidential' \
	--glob '!audit-release.sh' "${release_text[@]}"; then
	echo "Restrictive licence marker found in releasable code." >&2
	exit 1
fi

if find "$tmpdir" -type f \( -name '*.o' -o -name '*.ko' -o -name '*.so' \
	-o -name '*.a' -o -name '*.bin' -o -name '*.rom' \) | grep .; then
	echo "Source or Debian package contains an unexpected binary object." >&2
	exit 1
fi

# dpkg --verify is only useful when the payload has a manifest (defect A14).
[[ -s $tmpdir/control/md5sums ]] || {
	echo "Debian package has no md5sums control member." >&2
	exit 1
}
(cd "$tmpdir/deb" && md5sum -c --quiet "$tmpdir/control/md5sums")

mkdir -p "$dist_dir"
{
	echo "SM750HDMIFB RELEASE AUDIT"
	echo "Generated: $(date --iso-8601=seconds)"
	echo
	echo "LICENCE"
	echo "Project licence: GNU GPL version 2 only (GPL-2.0-only)"
	echo "Linux staging DDK files: SPDX GPL-2.0"
	echo "Proprietary objects, firmware and vendor audit sources packaged: no"
	echo
	echo "MODULE"
	modinfo "$module" |
		sed -n '/^filename:/p;/^version:/p;/^license:/p;/^description:/p;/^author:/p;/^alias:/p'
	echo
	echo "UNDEFINED KERNEL SYMBOLS"
	nm -u "$module" | sort
	echo
	echo "DEBIAN PACKAGE CONTENTS"
	dpkg-deb -c "$deb"
	echo
	echo "SOURCE ARCHIVE CONTENTS"
	tar -tzf "$source_archive"
	echo
	echo "CHECKSUMS"
	(cd "$dist_dir" && sha256sum "$(basename "$deb")" \
		"$(basename "$source_archive")")
} >"$report"

echo "Release audit passed: $report"