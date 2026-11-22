#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
builder=$project_dir/build-package.sh
dkms_config=$project_dir/dkms.conf
# GitHub Actions is disabled, so the recipe lives outside .github/workflows/.
ci_recipe=$project_dir/docs/ci/build.yml

version=$(sed -n 's/^readonly version=//p' "$builder")
test -n "$version"
grep -F "PACKAGE_VERSION=\"$version\"" "$dkms_config" >/dev/null

# The module, the maintainer scripts and the package must carry one version.
module_version=$(sed -n \
	's/^#define SM750_DRM_VERSION "\([^"]*\)"/\1/p' \
	"$project_dir/src/sm750_drm.c")
test "$module_version" = "$version"

# modetest prints "version <major>.<minor>.<patchlevel>", so the numbers the
# two drm_driver instances report must track the release version as well
# (defect: they were pinned at 0.1 and every build claimed to be 0.1.0).
driver_macro() {
	sed -n "s/^#define $1 \([0-9]\+\)\$/\1/p" "$project_dir/src/sm750_drm.c"
}
reported="$(driver_macro DRIVER_MAJOR).$(driver_macro DRIVER_MINOR).$(driver_macro DRIVER_PATCHLEVEL)"
test "$reported" = "$version" || {
	echo "src/sm750_drm.c reports driver version '$reported', expected '$version'" >&2
	exit 1
}
test "$(grep -Fc '.major = DRIVER_MAJOR,' "$project_dir/src/sm750_drm.c")" -eq 2 &&
	test "$(grep -Fc '.minor = DRIVER_MINOR,' "$project_dir/src/sm750_drm.c")" -eq 2 &&
	test "$(grep -Fc '.patchlevel = DRIVER_PATCHLEVEL,' "$project_dir/src/sm750_drm.c")" -eq 2 || {
	echo "both drm_driver instances must use DRIVER_MAJOR/DRIVER_MINOR/DRIVER_PATCHLEVEL" >&2
	exit 1
}

# The RPM spec declares the version twice and neither declaration was checked
# before this gate existed, so a bump could ship a spec that still says 0.5.9.
spec=$project_dir/packaging/sm750hdmifb.spec
spec_dkms_version=$(sed -n \
	's/^%global dkms_version[[:space:]]*\([^[:space:]]*\)$/\1/p' "$spec")
test -n "$spec_dkms_version"
test "$spec_dkms_version" = "$version" || {
	echo "RPM spec %global dkms_version is '$spec_dkms_version', expected '$version'" >&2
	exit 1
}
spec_version=$(sed -n 's/^Version:[[:space:]]*\([^[:space:]]*\)$/\1/p' "$spec")
test -n "$spec_version"
test "$spec_version" = "$version" || {
	echo "RPM spec Version is '$spec_version', expected '$version'" >&2
	exit 1
}
# The tools spec is a second package in the same release and must not drift.
tools_spec=$project_dir/packaging/sm750hdmifb-tools.spec
tools_spec_version=$(sed -n \
	's/^Version:[[:space:]]*\([^[:space:]]*\)$/\1/p' "$tools_spec")
test -n "$tools_spec_version"
test "$tools_spec_version" = "$version" || {
	echo "Tools RPM spec Version is '$tools_spec_version', expected '$version'" >&2
	exit 1
}
grep -F 's/@VERSION@/${version}/g' "$builder" >/dev/null
for script in packaging/drm-postinst packaging/drm-prerm; do
	grep -F 'version=@VERSION@' "$project_dir/$script" >/dev/null
	if grep -qE '^version=[0-9]+\.[0-9]+\.[0-9]+$' "$project_dir/$script"; then
		echo "Maintainer script hardcodes a version: $script" >&2
		exit 1
	fi
done

artifact_count=0
while IFS= read -r artifact; do
	case "$artifact" in
		sm750hdmifb-"$version"|sm750hdmifb_"$version"_all.deb|\
			sm750hdmifb-tools-"$version"|\
			sm750hdmifb-tools_"$version"_*.deb) ;;
		*)
			echo "CI recipe references stale release artifact: $artifact" >&2
			exit 1
			;;
	esac
	artifact_count=$((artifact_count + 1))
done < <(rg -o 'sm750hdmifb(-tools)?(-[0-9]+\.[0-9]+\.[0-9]+|_[0-9]+\.[0-9]+\.[0-9]+_[a-z0-9]+\.deb)' "$ci_recipe")

test "$artifact_count" -gt 0
echo "Release version consistency checks passed: $version"
