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
%global dkms_version  0.6.2
%global module_name   sm750hdmidrm

Name:           sm750hdmifb
Version:        0.6.2
Release:        3%{?dist}
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
# modules_root and dkms_root are overridable so tests/check-rpm-dkms.sh can
# exercise every branch without writing to /lib/modules or /var/lib/dkms. rpm
# never sets either variable, so the installed defaults are always
# /lib/modules and /var/lib/dkms.
modules_root=${SM750_RPM_MODULES_ROOT:-/lib/modules}
dkms_root=${SM750_RPM_DKMS_ROOT:-/var/lib/dkms}

# Stale-registration purge, before the build loop on purpose. Releases before
# 0.6.0 registered other versions of %{dkms_name} and left them registered.
# Both dkms.conf files declare DEST_MODULE_LOCATION="/updates/dkms", which
# override_dest_module_location() in /usr/sbin/dkms rewrites to /extra on
# Fedora, so every registered version of this module name shares the one
# destination path /lib/modules/<kernel>/extra/%{module_name}.ko.xz.
# "dkms autoinstall" (what dkms.service runs on boot) installs only the newest
# registered version and skips kernels where the module already looks
# installed, so a stale version that stays registered takes the destination
# path back on the next kernel update. Rationale and host evidence:
# docs/PACKAGING-RPM.md section 4.
#
# The ordering is load-bearing. "dkms install" of the new version first
# uninstalls the older registered version for the same kernel, and when that
# registration is broken - its /var/lib/dkms/<name>/<version>/source symlink
# dangles because rpm erased the older package's files - dkms exits with
# "Error! Could not locate dkms.conf file." and installs nothing, so the
# destination path keeps the old module. Purging first leaves install with no
# stale registration to uninstall. Observed on this host with 0.6.1 left
# broken while 0.6.2 installed; transcript:
# docs/evidence/runtime/27-posttrans-install-failure.txt.
#
# Bounded by construction: only a status line whose module name is exactly
# %{dkms_name} is considered ("<name>/" is matched, so a module named
# "%{dkms_name}-something" is never touched), %{dkms_version} itself is never
# removed, each distinct version is removed at most once, and a version that is
# not a plain release token (empty, ".", "..", containing "/" or any byte
# outside [0-9A-Za-z._-]) is skipped before it can reach a path. A failed
# removal is a warning, never a non-zero exit: an exiting scriptlet aborts the
# transaction.
#
# A failed removal escalates once: when the registration tree is demonstrably
# broken - the version directory exists and its source/dkms.conf is not a
# readable file - the tree itself is removed, which is what dkms instructs
# ("If this module version is no longer needed, you can remove the stale
# directory"). A tree whose dkms.conf is readable is never deleted here; dkms
# remove owns that case.
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
	# anything with a path separator is not a version, and neither is "." or
	# ".." (each would resolve the tree path elsewhere) nor a token carrying a
	# byte outside the release-string class.
	case "$stale_version" in
		*/*|.|..) continue ;;
	esac
	case "$stale_version" in
		*[!0-9A-Za-z._-]*) continue ;;
	esac
	case "$seen_versions" in
		*" $stale_version "*) continue ;;
	esac
	seen_versions="$seen_versions$stale_version "
	echo "removing stale DKMS registration: %{dkms_name}/$stale_version" >&2
	if dkms remove -m %{dkms_name} -v "$stale_version" --all; then
		continue
	fi
	echo "warning: dkms remove %{dkms_name}/$stale_version failed; remove it by hand" >&2
	stale_tree=$dkms_root/%{dkms_name}/$stale_version
	if [ -d "$stale_tree" ] && [ ! -r "$stale_tree/source/dkms.conf" ]; then
		echo "warning: removing broken DKMS registration tree: $stale_tree" >&2
		rm -rf -- "$stale_tree"
	fi
done

# Second shape of the same leftover (defect A40), and the loop above cannot see
# it. do_install() in dkms 3.4.4 (/usr/sbin/dkms:1768) builds the active-version
# link path "$dkms_tree/$module/kernel-$kernelver-$arch", derives the version
# from the link target alone (:1783-1784, "old_active_version=${old_active_version%%/*}")
# without checking that the version is still registered or still on disk, and
# at :1866-1868 runs "do_uninstall" for it, dying with die 6
# ("Failed to uninstall ...") when that fails. A dangling active link is not a
# dkms registration, so "dkms status" never lists it: the version loop above
# iterates registrations and skips it, and the link alone is then enough to
# abort "dkms install" for that kernel. Clearing the link is safe because dkms
# recreates it on the next successful install and installs nothing through it.
# Bounded by construction: only symlinks under "$dkms_root/%{dkms_name}" whose
# name starts with "kernel-" are considered, and a link that resolves is never
# touched. dkms always points these links at a version directory
# ("<version>/<kernel>/<arch>"), so -d with a trailing slash is the resolution
# test; a regular file or directory that merely shares the name is skipped.
for dkms_link in "$dkms_root/%{dkms_name}"/kernel-*; do
	[ -L "$dkms_link" ] || continue
	if [ ! -d "$dkms_link/" ]; then
		echo "removing dangling DKMS kernel link: $dkms_link" >&2
		rm -f -- "$dkms_link"
	fi
done

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
	echo "warning: no kernel received the module; check the warnings above and run: dkms install -m %{dkms_name} -v %{dkms_version} -k <kernel>" >&2
fi
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
* Sat Nov 21 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.2-3
- The stale purge in %posttrans now also clears a dangling DKMS active-version
  link. 0.6.2-2 moved the purge ahead of the build loop, but a host whose
  /var/lib/dkms/sm750hdmifb/kernel-<kernel>-<arch> link still points at a
  version rpm erased an earlier time kept failing: do_install() in dkms 3.4.4
  reads the version out of that link target without checking that it is still
  registered, uninstalls it before installing the new version, and dies 6 when
  that fails, so no kernel received the module while "dkms status" listed only
  the new version. A dangling link is not a registration, so the
  version-driven purge could not see it; the second loop removes it before the
  build loop, leaves a link that resolves and any other path alone.
* Sat Nov 21 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.2-2
- The stale-registration purge in %posttrans now runs before the DKMS build
  loop: a registration left broken by an earlier package (version directory
  present, source/dkms.conf gone) makes "dkms install" abort while uninstalling
  the older version, so 0.6.2 was never installed and /lib/modules kept the
  0.6.1 module; a removal that fails now also deletes a demonstrably broken
  registration tree, which is what dkms itself instructs. The CLEAN directive is
  dropped from dkms.conf: dkms 3.4.4 only prints "Deprecated feature: CLEAN"
  for it and never runs it. The console helper prints the zero-frame hint only
  when the read crc32 is the zero-frame value.
* Sat Nov 21 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.2-1
- Release 0.6.2: a test-card fallback paints an EBU colour bar pattern, a
  grayscale staircase, a grid, a crosshair and a border into the scanout window
  when the pipe is enabled with an unowned, entirely blank frame, so a panel
  with no client is never dead-black; the card rotates its palette every five
  seconds and carries a bouncing disc whose tick repaints only the two bounding
  boxes it touches (about 35 KiB at 1080p in 32 bpp, not the 8 MiB frame), which
  keeps a static panel from burning in; parameters test_pattern,
  test_pattern_period_ms and test_pattern_anim_ms, the last two writable at
  runtime; an armed scanout CRC source cancels the card and owns the window for
  its whole lifetime, so the CRC stream can no longer be torn by a repaint, and
  a frame from a userspace DRM master is never overwritten; new gate
  tests/check-test-pattern.sh; new helper tools/sm750-console.sh reports the
  VT mode, the fbcon bind state and the scanout content.
* Fri Nov 20 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.1-1
- Release 0.6.1: the display-control transition waits compare through a mask
  and re-poke the register on every poll, and the mode wait budget is derived
  from the vertical period instead of a fixed iteration count, so a modeset no
  longer reports "failed to enable HDMI mode" on this panel; the display-off
  result is no longer discarded and an enable failure dumps PANEL_DISPLAY_CTRL,
  PANEL_PLL_CTRL, SYSTEM_CTRL and PANEL_CURRENT_LINE; a blank console
  framebuffer now names the KD_GRAPHICS precondition once; new gates
  tests/check-restore-path.sh and tests/check-console-blank.sh.
* Wed Nov 18 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.0-1
- Release 0.6.0: driver reports its version through drm_driver major/minor/
  patchlevel so modetest no longer prints 0.1.0; read-only debugfs "regs"
  register dump; RPM/DKMS packaging path with the rootless gate.
* Wed Nov 18 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.5.9-1
- Initial DKMS source RPM: mirrors the 0.5.9 Debian payload, registers in %post,
  builds and installs in %posttrans, unregisters in %preun.
