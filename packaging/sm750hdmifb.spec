# SPDX-License-Identifier: GPL-2.0-only
#
# DKMS source RPM for the SM750G10 / SiI9024A HDMI DRM-KMS driver.
#
# The package is a noarch source carrier: dkms builds the out-of-tree module
# against each installed kernel, so nothing is compiled at RPM build time. The
# shipped file set mirrors the Debian builder (build-package.sh) exactly; the
# one deliberate difference is the maintainer-script layer, documented at the
# %posttrans section below.
#
# Reproduction (never uses rpmdev-setuptree and never writes to $HOME):
#   docs/PACKAGING-RPM.md
# Verification (rootless, exits non-zero on regression):
#   tests/check-rpm-dkms.sh

%global dkms_name     sm750hdmifb
%global dkms_version  0.6.0
%global module_name   sm750hdmidrm

Name:           sm750hdmifb
Version:        0.6.0
Release:        1%{?dist}
Summary:        DKMS source for the SM750G10 SiI9024A HDMI DRM-KMS driver
License:        GPL-2.0-only
URL:            https://github.com/KodeMunkie/sm750hdmifb
Source0:        %{name}-%{version}-source.tar.gz
BuildArch:      noarch

# BuildRequires: no compilation happens here. gcc and make are declared because
# a DKMS payload is only meaningful when the local toolchain can build it, and
# so a missing toolchain fails early rather than on the first kernel update.
BuildRequires:  rpm-build
BuildRequires:  dkms
BuildRequires:  make
BuildRequires:  gcc

# Runtime: the source tree is inert without dkms.
Requires:       dkms

# Scriptlet-scoped requirements. %posttrans runs in the same transaction as
# %post, so a tool required by %post is unpacked before %posttrans too; kmod is
# required for the depmod -a call that follows dkms install.
Requires(post): dkms
Requires(post): kmod
Requires(preun): dkms

# Upgrade parity with the Debian package (Conflicts/Replaces in
# build-package.sh:71-72): the predecessor package families must not stay
# installed next to this one.
Provides:       sm750hdmi-dkms = %{version}-%{release}
Obsoletes:      sm750hdmi-dkms < %{version}
Provides:       sm750hdmidrm-xrgb8888-dkms = %{version}-%{release}
Obsoletes:      sm750hdmidrm-xrgb8888-dkms < %{version}
Provides:       sm750hdmidrm-rgb565-dither-dkms = %{version}-%{release}
Obsoletes:      sm750hdmidrm-rgb565-dither-dkms < %{version}

%description
Out-of-tree DRM/KMS driver for SE-DP750A-HDMI boards using an SM750G10 and an
external SiI9024A HDMI transmitter. Includes EDID, atomic modesetting, RGB565
dither, wide softscaling, coalesced shadow updates, hardware cursor and
interrupt-completed DMA shadow uploads.

This package contains the DKMS source tree and the modprobe, modules-load and
Xorg configuration assets; the kernel module is built on the target host.

%prep
%setup -q -n %{name}-%{version}

%build
# Nothing to compile: DKMS builds src/ against each installed kernel tree.

%install
srcroot=%{_builddir}/%{name}-%{version}
install -d "%{buildroot}%{_usrsrc}/%{name}-%{version}/src"
install -d "%{buildroot}%{_sysconfdir}/modprobe.d"
install -d "%{buildroot}%{_sysconfdir}/modules-load.d"
install -d "%{buildroot}%{_datadir}/X11/xorg.conf.d"
install -d "%{buildroot}%{_prefix}/lib/%{name}"

# /usr/src/%{name}-%{version}: the DKMS source tree, identical to the Debian
# payload (build-package.sh:25-36).
install -m 0644 "$srcroot/Makefile" "$srcroot/README.md" "$srcroot/LICENSE" \
	"$srcroot/dkms.conf" "%{buildroot}%{_usrsrc}/%{name}-%{version}/"
install -m 0644 "$srcroot/src/Makefile" "$srcroot/src/Kconfig" \
	"$srcroot/src/ddk750.h" \
	"$srcroot/src/ddk750_chip.c" "$srcroot/src/ddk750_chip.h" \
	"$srcroot/src/ddk750_display.c" "$srcroot/src/ddk750_display.h" \
	"$srcroot/src/ddk750_hwi2c.c" "$srcroot/src/ddk750_hwi2c.h" \
	"$srcroot/src/ddk750_mode.c" "$srcroot/src/ddk750_mode.h" \
	"$srcroot/src/ddk750_power.c" "$srcroot/src/ddk750_power.h" \
	"$srcroot/src/ddk750_reg.h" \
	"$srcroot/src/ddk750_swi2c.c" "$srcroot/src/ddk750_swi2c.h" \
	"$srcroot/src/sii902x.c" "$srcroot/src/sii902x.h" \
	"$srcroot/src/sm750_dither.c" "$srcroot/src/sm750_dither.h" \
	"$srcroot/src/sm750_drm.c" \
	"$srcroot/src/sm750_drm_mode.c" "$srcroot/src/sm750_drm_mode.h" \
	"%{buildroot}%{_usrsrc}/%{name}-%{version}/src/"

# Configuration assets. The two files carried in DEBIAN/conffiles are %config;
# the Xorg snippet is not a conffile on the Debian side either, so it is a
# plain file here as well.
install -m 0644 "$srcroot/packaging/%{module_name}.conf" \
	"%{buildroot}%{_sysconfdir}/modprobe.d/%{module_name}.conf"
install -m 0644 "$srcroot/packaging/%{module_name}.modules-load" \
	"%{buildroot}%{_sysconfdir}/modules-load.d/%{module_name}.conf"
install -m 0644 "$srcroot/packaging/20-%{module_name}.conf" \
	"%{buildroot}%{_datadir}/X11/xorg.conf.d/20-%{module_name}.conf"
install -m 0755 "$srcroot/packaging/write-xorg-config.sh" \
	"%{buildroot}%{_prefix}/lib/%{name}/write-xorg-config"

%post
# --rpm_safe_upgrade semantics: register with DKMS only on first install
# ($1 == 1). On an upgrade ($1 == 2) /usr/src/%{name}-%{version} is already
# registered, and a second "dkms add" on a populated tree is an error that
# would abort the transaction. The same guard keeps "rpm -U --replacepkgs"
# from re-adding.
#
# A warning, never a non-zero exit: an exiting scriptlet aborts the RPM
# transaction, which for a driver package is worse than an unregistered tree
# (the %posttrans build then warns and the admin can run dkms add by hand).
if [ "$1" -eq 1 ]; then
	dkms add -m %{dkms_name} -v %{dkms_version} >/dev/null || \
		echo "warning: dkms add %{dkms_name}/%{dkms_version} failed; run it manually" >&2
fi
exit 0

%posttrans
# Build and install only after the whole transaction: kernel-devel packages
# installed in the same transaction are unpacked by %posttrans but not by
# %post, and building before headers exist would fail the install.
#
# Divergence from packaging/drm-postinst (Debian), recorded deliberately:
#   - packaging/drm-postinst:66-73 calls update-initramfs; this driver is not
#     needed to mount the root filesystem, so dkms install plus depmod -a is
#     the Fedora path and no initramfs is regenerated here.
#   - packaging/drm-postinst:86-89 exits 1 when no supported kernel has usable
#     headers; here that case prints warnings and exits 0 (see the final block).
#
# modules_root is overridable so tests/check-rpm-dkms.sh can exercise the
# missing-headers branch without writing to /lib/modules. rpm never sets the
# variable, so the installed default is always /lib/modules.
modules_root=${SM750_RPM_MODULES_ROOT:-/lib/modules}
built_count=0
for kernel_dir in "$modules_root"/*; do
	[ -d "$kernel_dir" ] || continue
	kernel_version=${kernel_dir##*/}
	# Same supported floor as BUILD_EXCLUSIVE_KERNEL in dkms.conf. The pattern
	# is byte-identical to packaging/drm-postinst:73-76; tests/check-rpm-dkms.sh
	# fails if the three ever diverge.
	case "$kernel_version" in
		6.1[7-9].*|6.[2-9][0-9].*|[7-9].*|[1-9][0-9].*) ;;
		*) continue ;;
	esac
	if [ ! -f "$kernel_dir/build/Makefile" ]; then
		echo "warning: skipping $kernel_version: matching kernel headers are absent" >&2
		continue
	fi
	dkms build -m %{dkms_name} -v %{dkms_version} -k "$kernel_version" || {
		echo "warning: dkms build failed for $kernel_version; run it manually" >&2
		continue
	}
	dkms install -m %{dkms_name} -v %{dkms_version} -k "$kernel_version" --force || {
		echo "warning: dkms install failed for $kernel_version; run it manually" >&2
		continue
	}
	depmod -a "$kernel_version" || \
		echo "warning: depmod -a $kernel_version failed" >&2
	built_count=$((built_count + 1))
done
if [ "$built_count" -eq 0 ]; then
	echo "warning: no supported installed kernel has usable headers; the module was not built" >&2
	echo "warning: install kernel-devel for a supported kernel, then run: dkms install -m %{dkms_name} -v %{dkms_version} -k <kernel>" >&2
fi
# Stale-registration purge. Releases before 0.6.0 registered other versions of
# %{dkms_name} and left them registered. Both dkms.conf files declare
# DEST_MODULE_LOCATION="/updates/dkms", which override_dest_module_location()
# in /usr/sbin/dkms rewrites to /extra on Fedora, so every registered version
# of this module name shares the one destination path
# /lib/modules/<kernel>/extra/%{module_name}.ko.xz. "dkms autoinstall" (what
# dkms.service runs on boot) installs only the newest registered version and
# skips kernels where the module already looks installed, so a stale version
# that stays registered takes the destination path back on the next kernel
# update. Rationale and host evidence: docs/PACKAGING-RPM.md section 4.
#
# Bounded by construction: only a status line whose module name is exactly
# %{dkms_name} is considered ("<name>/" is matched, so a module named
# "%{dkms_name}-something" is never touched), %{dkms_version} itself is never
# removed, and each distinct version is removed at most once. A failed removal
# is a warning, never a non-zero exit: an exiting scriptlet aborts the
# transaction.
#
# This runs after the build loop on purpose: %{dkms_version} must own the
# shared destination path before any other version is unregistered. A stale
# version whose kernel symlinks still point at itself is uninstalled by
# "dkms remove --all", which is intended - the pre-0.6.0 driver must not be the
# object that loads.
#
# Deliberately left alone: /usr/src/sm750hdmifb-0.5.9 predates packaging and no
# RPM owns it, so %files cannot remove it. It is a documented manual step.
seen_versions=' '
dkms status 2>/dev/null | while IFS= read -r status_line; do
	# "<name>/<version>, <kernel>, <arch>: <state>" or "<name>/<version>: <state>".
	# Parsed with cut, not with parameter expansion: rpm collapses a doubled
	# percent sign in a scriptlet, so a shell expansion written with the
	# longest-suffix form would reach the host as the shortest-suffix form and
	# silently mis-parse the version.
	stale_entry=$(printf '%s\n' "$status_line" | cut -d, -f1)
	stale_name=$(printf '%s\n' "$stale_entry" | cut -d/ -f1)
	stale_version=$(printf '%s\n' "$stale_entry" | cut -d/ -f2 | cut -d: -f1)
	# Not this package's module name: leave it alone.
	[ "$stale_name" = "%{dkms_name}" ] || continue
	[ -n "$stale_version" ] || continue
	# This is the version being installed: never remove it.
	if [ "$stale_version" = "%{dkms_version}" ]; then
		continue
	fi
	# "name/version" without a registered source tree parses as "name/";
	# anything with a path separator is not a version.
	case "$stale_version" in
		*/*) continue ;;
	esac
	case "$seen_versions" in
		*" $stale_version "*) continue ;;
	esac
	seen_versions="$seen_versions$stale_version "
	echo "removing stale DKMS registration: %{dkms_name}/$stale_version" >&2
	dkms remove -m %{dkms_name} -v "$stale_version" --all || \
		echo "warning: dkms remove %{dkms_name}/$stale_version failed; remove it by hand" >&2
done
exit 0

# No %postun scriptlet is defined on purpose. dkms remove must run while
# /usr/src/sm750hdmifb-%{version} is still present (%preun), and no initramfs
# rebuild is required after an erase.
%preun
# --rpm_safe_upgrade semantics: unregister only when the last installed version
# is erased ($1 == 0). On an upgrade ($1 == 1) the new version still needs the
# DKMS registration, so removing it here would uninstall the module mid-upgrade.
#
# %preun, not %postun: dkms needs /usr/src/%{name}-%{version} to still exist
# when it removes the registration.
if [ "$1" -eq 0 ]; then
	dkms remove -m %{dkms_name} -v %{dkms_version} --all || \
		echo "warning: dkms remove %{dkms_name}/%{dkms_version} failed; run it manually" >&2
fi
exit 0

%files
# Ship/no-ship decision for every asset build-package.sh installs
# (build-package.sh:25-55). Full table: docs/PACKAGING-RPM.md.
#   ship     Makefile, dkms.conf, src/Makefile, src/Kconfig, src/*.c, src/*.h
#   ship     /etc/modprobe.d/sm750hdmidrm.conf
#   ship     /etc/modules-load.d/sm750hdmidrm.conf (source name *.modules-load)
#   ship     /usr/share/X11/xorg.conf.d/20-sm750hdmidrm.conf
#   ship     /usr/lib/sm750hdmifb/write-xorg-config (0755, same as the .deb)
#   ship     README.md, LICENSE, docs/RELEASE-NOTES.md, docs/TESTING.md,
#            packaging/copyright (all via %doc, into /usr/share/doc/sm750hdmifb)
#   no-ship  DEBIAN/control, DEBIAN/conffiles, DEBIAN/md5sums - RPM metadata and
#            its payload digest replace them
#   no-ship  DEBIAN/postinst, DEBIAN/prerm, DEBIAN/postrm (packaging/drm-*):
#            dpkg maintainer scripts whose arguments and tools do not exist
#            under rpm; replaced by the %post/%posttrans/%preun above
#   no-ship  build-package.sh, tests/, tools/, docs/ (except the two
#            documents listed above) - repository tooling, not runtime assets
%dir %{_usrsrc}/%{name}-%{version}
%{_usrsrc}/%{name}-%{version}/Makefile
%{_usrsrc}/%{name}-%{version}/README.md
%{_usrsrc}/%{name}-%{version}/LICENSE
%{_usrsrc}/%{name}-%{version}/dkms.conf
%dir %{_usrsrc}/%{name}-%{version}/src
%{_usrsrc}/%{name}-%{version}/src/Makefile
%{_usrsrc}/%{name}-%{version}/src/Kconfig
%{_usrsrc}/%{name}-%{version}/src/ddk750.h
%{_usrsrc}/%{name}-%{version}/src/ddk750_chip.c
%{_usrsrc}/%{name}-%{version}/src/ddk750_chip.h
%{_usrsrc}/%{name}-%{version}/src/ddk750_display.c
%{_usrsrc}/%{name}-%{version}/src/ddk750_display.h
%{_usrsrc}/%{name}-%{version}/src/ddk750_hwi2c.c
%{_usrsrc}/%{name}-%{version}/src/ddk750_hwi2c.h
%{_usrsrc}/%{name}-%{version}/src/ddk750_mode.c
%{_usrsrc}/%{name}-%{version}/src/ddk750_mode.h
%{_usrsrc}/%{name}-%{version}/src/ddk750_power.c
%{_usrsrc}/%{name}-%{version}/src/ddk750_power.h
%{_usrsrc}/%{name}-%{version}/src/ddk750_reg.h
%{_usrsrc}/%{name}-%{version}/src/ddk750_swi2c.c
%{_usrsrc}/%{name}-%{version}/src/ddk750_swi2c.h
%{_usrsrc}/%{name}-%{version}/src/sii902x.c
%{_usrsrc}/%{name}-%{version}/src/sii902x.h
%{_usrsrc}/%{name}-%{version}/src/sm750_dither.c
%{_usrsrc}/%{name}-%{version}/src/sm750_dither.h
%{_usrsrc}/%{name}-%{version}/src/sm750_drm.c
%{_usrsrc}/%{name}-%{version}/src/sm750_drm_mode.c
%{_usrsrc}/%{name}-%{version}/src/sm750_drm_mode.h
%config(noreplace) %{_sysconfdir}/modprobe.d/%{module_name}.conf
%config(noreplace) %{_sysconfdir}/modules-load.d/%{module_name}.conf
%{_datadir}/X11/xorg.conf.d/20-%{module_name}.conf
%dir %{_prefix}/lib/%{name}
%{_prefix}/lib/%{name}/write-xorg-config
%doc README.md LICENSE docs/RELEASE-NOTES.md docs/TESTING.md packaging/copyright

%changelog
* Wed Nov 18 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.0-1
- Release 0.6.0: driver reports its version through drm_driver major/minor/
  patchlevel so modetest no longer prints 0.1.0; read-only debugfs "regs"
  register dump; RPM/DKMS packaging path with the rootless gate.
* Wed Nov 18 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.5.9-1
- Initial DKMS source RPM: mirrors the 0.5.9 Debian payload, registers in %post,
  builds and installs in %posttrans, unregisters in %preun.
