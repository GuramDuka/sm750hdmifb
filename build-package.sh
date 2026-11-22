#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

readonly project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
readonly package=sm750hdmifb
readonly module=sm750hdmidrm
readonly version=0.6.4
readonly arch=all
readonly build_root="${project_dir}/build/package/${package}_${version}_${arch}"
readonly dist_dir="${project_dir}/dist"
readonly deb="${dist_dir}/${package}_${version}_${arch}.deb"
readonly source_archive="${dist_dir}/${package}-${version}-source.tar.gz"
readonly tools_package="${package}-tools"
readonly tools_arch=$(dpkg --print-architecture)
readonly tools_build_root="${project_dir}/build/package/${tools_package}_${version}_${tools_arch}"
readonly tools_deb="${dist_dir}/${tools_package}_${version}_${tools_arch}.deb"

usage() {
	cat <<'EOF'
Usage: build-package.sh [--help]

Builds the release artifacts into dist/ as the invoking user:

  sm750hdmifb_<version>_all.deb             module payload, Architecture: all
  sm750hdmifb-tools_<version>_<arch>.deb    sm750-smi, arch of the build host
  sm750hdmifb-<version>-source.tar.gz       tracked tree minus development files
  SHA256SUMS                                covers every artifact above

sm750hdmifb-tools compiles tools/sm750-smi.c and so needs the libdrm
development files (pkg-config module "libdrm": Debian/Ubuntu libdrm-dev,
Fedora libdrm-devel). When pkg-config cannot find libdrm the tools package is
skipped with a message on stderr, a tools deb left by an earlier run is
removed, and the module deb, the source archive and SHA256SUMS are still
produced - a release is never half built. A rootless libdrm tree works through
PKG_CONFIG_PATH (docs/ENVIRONMENT.md section 3).
EOF
}

case "${1:-}" in
'') ;;
-h | --help)
	usage
	exit 0
	;;
*)
	printf 'build-package.sh: unknown argument: %s\n' "$1" >&2
	usage >&2
	exit 2
	;;
esac

rm -rf "${build_root}"
install -d "${build_root}/DEBIAN" \
	"${build_root}/usr/src/${package}-${version}/src" \
	"${build_root}/usr/share/doc/${package}" \
	"${build_root}/usr/lib/${package}" \
	"${build_root}/etc/modprobe.d" \
	"${build_root}/etc/modules-load.d" \
	"${build_root}/usr/share/X11/xorg.conf.d" \
	"${dist_dir}"

install -m 0644 "${project_dir}/Makefile" "${project_dir}/README.md" \
	"${project_dir}/LICENSE" "${project_dir}/dkms.conf" \
	"${build_root}/usr/src/${package}-${version}/"
install -m 0644 "${project_dir}/src/Makefile" "${project_dir}/src/Kconfig" \
	"${project_dir}/src"/ddk750*.c "${project_dir}/src"/ddk750*.h \
	"${project_dir}/src/sii902x.c" "${project_dir}/src/sii902x.h" \
	"${project_dir}/src/sm750_dither.c" \
	"${project_dir}/src/sm750_dither.h" \
	"${project_dir}/src/sm750_drm.c" \
	"${project_dir}/src/sm750_drm_mode.c" \
	"${project_dir}/src/sm750_drm_mode.h" \
	"${build_root}/usr/src/${package}-${version}/src/"
install -m 0644 "${project_dir}/packaging/sm750hdmidrm.conf" \
	"${build_root}/etc/modprobe.d/sm750hdmidrm.conf"
install -m 0644 "${project_dir}/packaging/sm750hdmidrm.modules-load" \
	"${build_root}/etc/modules-load.d/sm750hdmidrm.conf"
install -m 0644 "${project_dir}/packaging/20-sm750hdmidrm.conf" \
	"${build_root}/usr/share/X11/xorg.conf.d/20-sm750hdmidrm.conf"
install -m 0755 "${project_dir}/packaging/write-xorg-config.sh" \
	"${build_root}/usr/lib/${package}/write-xorg-config"
install -m 0644 "${project_dir}/packaging/copyright" \
	"${build_root}/usr/share/doc/${package}/copyright"
install -m 0644 "${project_dir}/docs/RELEASE-NOTES.md" \
	"${project_dir}/docs/TESTING.md" \
	"${build_root}/usr/share/doc/${package}/"
install -m 0755 "${project_dir}/packaging/drm-postinst" \
	"${build_root}/DEBIAN/postinst"
install -m 0755 "${project_dir}/packaging/drm-prerm" \
	"${build_root}/DEBIAN/prerm"
install -m 0755 "${project_dir}/packaging/drm-postrm" \
	"${build_root}/DEBIAN/postrm"
# Maintainer scripts carry @VERSION@ instead of a literal version so a release
# bump cannot leave them pointing at the previous one (defect A09).
sed -i "s/@VERSION@/${version}/g" "${build_root}/DEBIAN/postinst" \
	"${build_root}/DEBIAN/prerm"

cat >"${build_root}/DEBIAN/control" <<EOF
Package: ${package}
Version: ${version}
Section: kernel
Priority: optional
Architecture: ${arch}
Maintainer: kodemunkie <kodemunkie@users.noreply.github.com>
Depends: dkms, make, gcc
Recommends: initramfs-tools | dracut
Provides: sm750hdmi-dkms
Conflicts: sm750hdmi-dkms, sm750hdmidrm-xrgb8888-dkms, sm750hdmidrm-rgb565-dither-dkms
Replaces: sm750hdmi-dkms, sm750hdmidrm-xrgb8888-dkms, sm750hdmidrm-rgb565-dither-dkms
Description: Experimental DRM/KMS driver for SM750G10 HDMI cards
 Out-of-tree DRM driver for SE-DP750A-HDMI boards using an SM750G10 and
 external SiI9024A HDMI transmitter. Includes EDID, atomic modesetting,
 RGB565 dither, wide softscaling, coalesced shadow updates, hardware cursor
 and interrupt-completed DMA shadow uploads.
EOF

printf '/etc/modprobe.d/%s.conf\n/etc/modules-load.d/%s.conf\n' \
	"${module}" "${module}" >"${build_root}/DEBIAN/conffiles"
# dpkg --verify needs a manifest; dpkg-deb does not generate one (defect A14).
(
	cd "${build_root}"
	find . -path ./DEBIAN -prune -o -type f -printf '%P\0' |
		sort -z | xargs -0 md5sum
) >"${build_root}/DEBIAN/md5sums"
dpkg-deb --root-owner-group --build "${build_root}" "${deb}"

# sm750-smi is a second, arch-dependent package: rpm cannot attach an arch
# subpackage to a noarch parent (docs/PACKAGING-RPM.md section 10), and the
# same split is kept here so both formats carry the same two names.
tools_built=0
if pkg-config --exists libdrm 2>/dev/null; then
	rm -rf "${tools_build_root}"
	install -d "${tools_build_root}/DEBIAN" "${tools_build_root}/usr/bin"
	read -r -a drm_cflags <<<"$(pkg-config --cflags libdrm)"
	read -r -a drm_libs <<<"$(pkg-config --libs libdrm)"
	"${CC:-cc}" -O2 -Wall -Wextra -Werror "${drm_cflags[@]}" \
		-o "${tools_build_root}/usr/bin/sm750-smi" \
		"${project_dir}/tools/sm750-smi.c" "${drm_libs[@]}"
	cat >"${tools_build_root}/DEBIAN/control" <<EOF
Package: ${tools_package}
Version: ${version}
Section: utils
Priority: optional
Architecture: ${tools_arch}
Maintainer: kodemunkie <kodemunkie@users.noreply.github.com>
Depends: libdrm2
Description: Monitoring and control utility for SM750G10 HDMI cards
 Reports and controls an SM750G10 HDMI card through sysfs, debugfs and the
 DRM connector state: card identity, memory configuration, output mode, pixel
 clock, panel power, I2C health and the SiI9024A receiver state. Carries the
 loop and machine-readable output used by monitoring and the strict exit
 status used by scripts. The driver comes from sm750hdmifb.
EOF
	(
		cd "${tools_build_root}"
		find . -path ./DEBIAN -prune -o -type f -printf '%P\0' |
			sort -z | xargs -0 md5sum
	) >"${tools_build_root}/DEBIAN/md5sums"
	dpkg-deb --root-owner-group --build "${tools_build_root}" "${tools_deb}"
	tools_built=1
else
	printf 'build-package.sh: skipping %s: pkg-config cannot find libdrm\n' \
		"${tools_package}" >&2
	printf '  install the libdrm development files: Debian/Ubuntu libdrm-dev, Fedora libdrm-devel\n' >&2
	printf '  or point PKG_CONFIG_PATH at a libdrm tree (docs/ENVIRONMENT.md section 3)\n' >&2
	rm -f "${tools_deb}"
fi

# Ship exactly the tracked tree minus the development-only material. Packing
# the working tree leaked untracked planning notes into the release and made
# the audit scan them (defect A02); the screenshots, the session plans and the
# captured transcripts stay in git because the source archive only has to
# build the module (defects A22, A29). The list is declared once, in
# packaging/source-excludes.sh, and tests/audit-release.sh reads the same file,
# so adding a development-only directory is a one-line change that both the
# packager and the gate follow. Building from an unpacked tarball has no .git,
# so fall back to the explicit path list with the same excludes.
# shellcheck source=packaging/source-excludes.sh
. "${project_dir}/packaging/source-excludes.sh"
mapfile -t exclude_pathspecs < <(sm750_dev_only_pathspecs)
if git -C "${project_dir}" rev-parse --git-dir >/dev/null 2>&1; then
	tracked_list=$(mktemp "${TMPDIR}/sm750-tracked.XXXXXX")
	trap 'rm -f -- "$tracked_list"' EXIT
	git -C "${project_dir}" ls-files -z -- . "${exclude_pathspecs[@]}" \
		>"$tracked_list"
	tar -C "${project_dir}" -czf "${source_archive}" \
		--transform="s|^|${package}-${version}/|" --null \
		-T "$tracked_list"
else
	tar_excludes=()
	for dev_only in "${sm750_dev_only[@]}"; do
		tar_excludes+=("--exclude=${dev_only}/*")
	done
	tar -C "${project_dir}" -czf "${source_archive}" \
		--transform="s|^|${package}-${version}/|" \
		--exclude-vcs --exclude='./build' --exclude='./dist' \
		--exclude='src/*.o' --exclude='src/*.ko' --exclude='src/*.cmd' \
		--exclude='src/.*.cmd' --exclude='src/*.mod' \
		--exclude='src/*.mod.c' --exclude='src/Module.symvers' \
		--exclude='src/modules.order' \
		--exclude='tests/check-vblank' \
		--exclude='tests/test-bbdither-rgb565' \
		--exclude='tests/test-scale-optimizations' \
		"${tar_excludes[@]}" \
		.gitignore LICENSE Makefile README.md build-package.sh dkms.conf \
		src docs tests tools packaging
fi

checksums=("$(basename "${deb}")" "$(basename "${source_archive}")")
if [ "${tools_built}" -eq 1 ]; then
	checksums+=("$(basename "${tools_deb}")")
fi
(cd "${dist_dir}" && printf '%s\n' "${checksums[@]}" | xargs sha256sum >SHA256SUMS)
printf '%s\n' "${deb}" "${source_archive}"
if [ "${tools_built}" -eq 1 ]; then
	printf '%s\n' "${tools_deb}"
fi
printf '%s\n' "${dist_dir}/SHA256SUMS"
