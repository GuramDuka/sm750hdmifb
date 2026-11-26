# SPDX-License-Identifier: GPL-2.0-only
#
# sm750-smi as its own arch-dependent package.
#
# Why this is a second spec file instead of a %package tools in
# packaging/sm750hdmifb.spec: rpm 6.0.2 refuses an arch-dependent subpackage of
# a noarch package ("error: line N: Only noarch subpackages are supported:
# BuildArch: x86_64"), and a subpackage that omits BuildArch inherits noarch
# from its parent (measured: main noarch plus tools subpackage yields two
# noarch packages). sm750-smi is a compiled ELF that links libdrm, so shipping
# it from a noarch package would put an x86_64 binary on every architecture.
# The module payload therefore stays in the noarch spec and this spec builds
# the arch package from the same source archive.
#
# Reproduction (never uses rpmdev-setuptree and never writes to $HOME):
#   docs/PACKAGING-RPM.md section 10
# Verification (rootless, exits non-zero on regression):
#   tests/check-rpm-dkms.sh

Name:           sm750hdmifb-tools
Version:        0.6.8
Release:        1%{?dist}
Summary:        Monitoring and control utility for SM750G10 HDMI cards
License:        GPL-2.0-only
URL:            https://github.com/KodeMunkie/sm750hdmifb
# Same source archive as the module package; the file name keeps the module
# package prefix so one tarball feeds both specs.
Source0:        sm750hdmifb-%{version}-source.tar.gz

BuildRequires:  gcc
BuildRequires:  libdrm-devel

# One 50 KB single-file utility. The distribution default would add
# -debuginfo and -debugsource subpackages and turn the deliverable into four
# artifacts; the project ships the same two package names in both formats, so
# keep the debug subpackages off deliberately.
%global debug_package %{nil}

# libdrm is linked, not loaded with dlopen; the soname dependency is generated
# automatically, this line only guarantees a readable name in the metadata.
Requires:       libdrm

%description
sm750-smi reports and controls a Silicon Motion SM750G10 HDMI card through
sysfs, debugfs and the DRM connector state: card identity, memory
configuration, output mode, pixel clock, panel power state, I2C bus health and
the SiI9024A HDMI receiver state.

It also carries the loop and the machine-readable output used by monitoring,
and the strict exit status used by scripts. The driver comes from the
sm750hdmifb package; this package installs only the utility.

%prep
%setup -q -n sm750hdmifb-%{version}

%build
pkg-config --exists libdrm || {
	echo "sm750hdmifb-tools: pkg-config cannot find libdrm; install libdrm-devel" >&2
	exit 1
}
%{__cc} %{optflags} -Wall -Wextra -Werror \
	$(pkg-config --cflags libdrm) \
	-o tools/sm750-smi tools/sm750-smi.c \
	$(pkg-config --libs libdrm)

%install
install -d "%{buildroot}%{_bindir}"
install -m 0755 tools/sm750-smi "%{buildroot}%{_bindir}/sm750-smi"

%files
%{_bindir}/sm750-smi

%changelog
* Thu Nov 26 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.8-1
- Rebuild against the 0.6.8 module release; the tools payload is unchanged
  from 0.6.7-1 and both halves of the release move together.
* Wed Nov 25 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.7-1
- Rebuild against the 0.6.7 module release; the tools payload is unchanged
  from 0.6.6-1 and both halves of the release move together.
* Wed Nov 25 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.6-1
- Rebuild against the 0.6.6 module release; the tools payload is unchanged
  from 0.6.5-1 and both halves of the release move together.
* Wed Nov 25 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.5-1
- Rebuild against the 0.6.5 module release; the tools payload is unchanged
  from 0.6.4-2 and both halves of the release move together.
* Sun Nov 22 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.4-2
- Banner rows of sm750-smi pad to exactly 79 columns; the Driver Version and
  PCI Bus Id rows printed 80 against the 79-column border.
* Sun Nov 22 2026 kodemunkie <kodemunkie@users.noreply.github.com> - 0.6.3-1
- Split sm750-smi out of the noarch module package into an arch package;
  rpm cannot place an arch-dependent subpackage under a noarch parent.