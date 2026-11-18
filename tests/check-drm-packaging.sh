#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
builder=$project_dir/build-package.sh
dkms_config=$project_dir/dkms.conf

bash -n "$builder" "$project_dir/packaging/write-xorg-config.sh"
sh -n "$project_dir/packaging/drm-postinst" \
	"$project_dir/packaging/drm-prerm" \
	"$project_dir/packaging/drm-postrm"
grep -F 'PACKAGE_VERSION="0.6.0"' "$dkms_config" >/dev/null
grep -F 'BUILT_MODULE_NAME[0]="sm750hdmidrm"' "$dkms_config" >/dev/null
grep -F 'BUILD_EXCLUSIVE_KERNEL="^(6\\.(1[7-9]|[2-9][0-9])\\.|[7-9]\\.|[1-9][0-9]\\.)"' \
	"$dkms_config" >/dev/null
grep -F '6.1[7-9].*|6.[2-9][0-9].*|[7-9].*|[1-9][0-9].*) ;;' \
	"$project_dir/packaging/drm-postinst" >/dev/null
grep -F 'Removing stale DKMS registration:' \
	"$project_dir/packaging/drm-postinst" >/dev/null
grep -F '[ "$1" = remove ] || [ "$1" = deconfigure ] || [ "$1" = upgrade ]' \
	"$project_dir/packaging/drm-prerm" >/dev/null
grep -F -- "-name 'linux-headers-6.17.*-generic'" \
	"$project_dir/.github/workflows/build.yml" >/dev/null
grep -F 'readonly package=sm750hdmifb' "$builder" >/dev/null
grep -F 'readonly deb="${dist_dir}/${package}_${version}_${arch}.deb"' \
	"$builder" >/dev/null
grep -F 'Maintainer: kodemunkie <kodemunkie@users.noreply.github.com>' \
	"$builder" >/dev/null
# A14: the payload needs a dpkg manifest.
grep -F 'DEBIAN/md5sums' "$builder" >/dev/null
# A02/A22/A29: the archive is the tracked tree without the development-only
# directories, and that list is declared once, in packaging/source-excludes.sh,
# which both the packager and the release audit read.
excludes=$project_dir/packaging/source-excludes.sh
bash -n "$excludes"
grep -F 'docs/plan' "$excludes" >/dev/null
grep -F 'docs/evidence' "$excludes" >/dev/null
grep -F 'docs/images' "$excludes" >/dev/null
grep -F 'sm750_dev_only_pathspecs' "$builder" >/dev/null
grep -F 'sm750_dev_only_pathspecs' "$project_dir/tests/audit-release.sh" >/dev/null
grep -F 'packaging/source-excludes.sh' "$builder" >/dev/null
grep -F 'packaging/source-excludes.sh' "$project_dir/tests/audit-release.sh" >/dev/null
# No consumer may hard-code its own copy of the list again.
if grep -F ":(exclude)docs/" "$builder" >/dev/null ||
	grep -F ":(exclude)docs/" "$project_dir/tests/audit-release.sh" >/dev/null; then
	echo "A development-only path is hard-coded outside source-excludes.sh" >&2
	exit 1
fi
# A08: initramfs refresh must not depend on a Debian-only tool.
grep -F 'command -v update-initramfs' "$project_dir/packaging/drm-postinst" \
	>/dev/null
grep -F 'command -v dracut' "$project_dir/packaging/drm-postinst" >/dev/null
# Every update-initramfs call must sit directly under its command -v guard.
for script in drm-postinst drm-postrm; do
	awk '
		/^[[:space:]]*update-initramfs/ {
			if (prev !~ /command -v update-initramfs/) {
				print "unguarded update-initramfs at line " NR > "/dev/stderr"
				bad = 1
			}
		}
		{ prev = $0 }
		END { exit bad }
	' "$project_dir/packaging/$script"
done
grep -F 'Recommends: initramfs-tools | dracut' "$builder" >/dev/null
grep -F 'SM750_DRM_SCANOUT_DEFAULT' "$project_dir/src/Makefile" >/dev/null
grep -F 'SM750_DRM_DEFAULT_SCANOUT_FORMAT "rgb565-bbdither"' \
	"$project_dir/src/sm750_drm.c" >/dev/null
grep -F 'SM750_DRM_DEFAULT_SCANOUT_FORMAT "xrgb8888"' \
	"$project_dir/src/sm750_drm.c" >/dev/null
grep -F 'SM750_DRM_DEFAULT_SCANOUT_FORMAT "rgb565"' \
	"$project_dir/src/sm750_drm.c" >/dev/null
! grep -F 'sm750hdmifb.o' "$project_dir/src/Makefile" >/dev/null
! grep -F 'sm750fb' "$project_dir/dkms.conf" >/dev/null

echo "Unified DRM package checks passed"
