<!-- SPDX-License-Identifier: GPL-2.0-only -->
# RPM packaging (`packaging/sm750hdmifb.spec`)

How to build, install, verify and roll back the `sm750hdmifb` RPM. The Debian
path remains `build-package.sh`; both ship the same file set, with one
deliberate scriptlet divergence (section 7).

## 1. Purpose

`packaging/sm750hdmifb.spec` produces a **noarch DKMS source carrier**:

| Macro / field | Value |
| --- | --- |
| `%global dkms_name` | `sm750hdmifb` |
| `%global dkms_version` | `0.6.0` |
| `%global module_name` | `sm750hdmidrm` |
| `Name` / `Version` / `Release` | `sm750hdmifb` / `0.6.0` / `1%{?dist}` |
| `BuildArch` | `noarch` |

Nothing is compiled at RPM build time: `%build` is empty. The package ships
the DKMS source tree under `/usr/src/sm750hdmifb-0.6.0`, the modprobe /
modules-load / Xorg assets and the Xorg helper script. DKMS compiles `src/`
against each installed kernel, so one noarch RPM serves every architecture.
The `BUILD_EXCLUSIVE_KERNEL` floor in `dkms.conf` (6.17 and newer, same
semantics as `packaging/drm-postinst:73-76`) is unchanged.

## 2. Prerequisites

Build host: `rpm-build` (rpm 6.0.2 / Fedora 43 tested), `git` (the source
archive is the tracked tree), plus `dkms`, `make`, `gcc` as declared
`BuildRequires` so a missing toolchain fails at build time rather than on the
first kernel update.

Target host, enforced by the spec: `Requires: dkms`;
`Requires(post): dkms, kmod` (`%post` registers the tree, `%posttrans` calls
`depmod -a`); `Requires(preun): dkms` (`%preun` unregisters). A `kernel-devel`
tree for the running kernel is a host property, not an RPM dependency
(section 8).

## 3. Build recipe (clean checkout, no `$HOME` writes)

`rpmdev-setuptree` is deliberately **not** used. `~/.rpmmacros` on this host
points `%_topdir` at `$HOME/rpmbuild`, so every run passes an explicit
`--define`:

```sh
work=/mega/tmp/sm750/t6
topdir=$work/rpmbuild
rm -rf -- "$topdir"
mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}

# Source0 is the tracked tree minus the screenshots, exactly as
# build-package.sh:95-102; never tar the working tree.
tracked=$(mktemp)
git ls-files -z -- . ':(exclude)docs/images/*' >"$tracked"
tar -C . -czf "$topdir/SOURCES/sm750hdmifb-0.6.0-source.tar.gz" \
    --transform='s|^|sm750hdmifb-0.6.0/|' --null -T "$tracked"

rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
```

Artifacts (73 tracked files in the tarball, 36 files in the RPM):

```
/mega/tmp/sm750/t6/rpmbuild/SRPMS/sm750hdmifb-0.6.0-1.fc43.src.rpm
/mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm
```

`rpmbuild -ba` exits `0`; the transcript is
`docs/evidence/packaging/01-rpmbuild.log`. The `rm -rf "$topdir"` makes the
result independent of earlier runs.

## 4. Install, upgrade, erase

Root only by definition: the payload owns `/usr/src`, `/etc` and
`/var/lib/dkms`.

```sh
sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm
sudo dkms status -m sm750hdmifb -v 0.6.0     # expected: ..., <kernel>: installed
sudo modprobe sm750hdmidrm                   # requires a free DRM minor
sudo dnf remove -y sm750hdmifb               # erase; %preun unregisters
sudo dkms status -m sm750hdmifb -v 0.6.0     # expected: no such module
```

None of these have run on this host: the account is unprivileged (`uid 1005`).
They are `GAP-B7` in `docs/evidence/EVIDENCE-GAPS.md`.

### Upgrade path (`$1 == 1` / `--rpm_safe_upgrade`)

| Stage | Scriptlet | Guard | Action |
| --- | --- | --- | --- |
| first install | `%post` | `[ "$1" -eq 1 ]` | `dkms add` |
| upgrade | `%post` | `$1 == 2`, skipped | tree already registered |
| install / upgrade | `%posttrans` | - | `dkms build`, `dkms install --force`, `depmod -a` per supported kernel |
| erase | `%preun` | `[ "$1" -eq 0 ]` | `dkms remove --all` |
| upgrade | `%preun` | `$1 == 1`, skipped | the new version needs the registration |
| - | `%postun` | not defined | no initramfs to regenerate |

`dkms add` runs only on first install because re-adding a populated
`/usr/src/sm750hdmifb-0.6.0` is an error and an exiting scriptlet aborts the
transaction. `%preun` (not `%postun`) removes the registration because DKMS
needs the source tree while unregistering.

### Kernel-update rebuild

`dkms.conf` sets `AUTOINSTALL=yes`, so DKMS kernel hooks build and install the
module for a newly installed kernel; the RPM is not re-run. Confirm with
`dkms status -m sm750hdmifb -v 0.6.0`. The floor regex that `%posttrans` uses
is byte-identical to `BUILD_EXCLUSIVE_KERNEL` and
`packaging/drm-postinst:73-76`; the test fails if any of the three drifts.

## 5. Verification

```sh
cd /path/to/sm750hdmifb
./tests/check-rpm-dkms.sh          # exit 0 = pass, non-zero = regression
```

Rootless; writes only under `/mega/tmp/sm750/t6` (override `SM750_RPM_WORK`),
never `$HOME`, archives output in `docs/evidence/packaging/` (override
`SM750_RPM_EVIDENCE`). Expected on Fedora 43 with kernel 7.3.4-100:

```
OK: source payload matches git ls-files (73 files)
OK: rpmbuild -ba exit 0: sm750hdmifb-0.6.0-1.fc43.src.rpm, sm750hdmifb-0.6.0-1.fc43.noarch.rpm
OK: dependencies: BuildRequires 4, runtime dkms, post dkms+kmod, preun dkms
OK: scriptlets: add in %post, build+install+depmod in %posttrans, remove in %preun, no %postun
OK: %files: 36 files, 4 owned directories, 2 %config(noreplace) entries
OK: missing headers: warning on stderr, exit 0; build/install/depmod sequence verified
OK: dkms sandbox: sm750hdmifb/0.6.0, 7.3.4-100.fc43.x86_64, x86_64: built
OK: built object: /mega/tmp/sm750/t6/dkms/sm750hdmifb/0.6.0/7.3.4-100.fc43.x86_64/x86_64/module/sm750hdmidrm.ko (320960 bytes, host tree untouched)
SKIP: dnf install sm750hdmifb-0.6.0-1.fc43.noarch.rpm: needs root (writes /usr/src, /etc, /var/lib/dkms)
SKIP: dkms status showing 'installed' in the host tree: needs root, follows the skipped dnf install
SKIP: dkms install (even with --installtree): 'Error! You must be root to use this command.'
SKIP: modinfo of the installed module: needs root, follows the skipped dnf install
SKIP: dnf remove sm750hdmifb: needs root and the skipped dnf install
SKIP: dkms status after erase (registration gone): needs root, follows the skipped dnf remove
SKIP: closing commands recorded in docs/evidence/EVIDENCE-GAPS.md GAP-B7
RPM/DKMS checks passed: sm750hdmifb 0.6.0, sandbox built, root-only steps skipped
```

Exit codes: `0` every assertion held; `1` first failed assertion (reason on
stderr) or a usage/environment error (running as root, missing spec,
unexpected `$HOME/rpmbuild`). `SKIP` lines are printed, never silent.

Rootless checks: payload equality with `git ls-files`, full `rpmbuild -ba`
from a fresh `_topdir`, `rpm -qpR` / `rpm -qp --scripts` / `rpm -qp --qf` /
`rpm -qlp` metadata assertions, an offline `%posttrans` run with
`dkms`/`depmod` shims over two fake module roots, and a real DKMS `add` +
`build` producing `sm750hdmidrm.ko` with a matching vermagic. `dkms install`
is the one step that cannot be sandboxed: it refuses a non-root caller even
with `--dkmstree`, `--sourcetree` and `--installtree` all on scratch, so the
refusal is captured in `05-dkms-sandbox.log` and reported as `SKIP`, while the
host module tree is asserted absent.

Companion files: `packaging/sm750hdmifb.spec`, `tests/check-rpm-dkms.sh`,
`docs/evidence/packaging/01`-`07`, `docs/evidence/EVIDENCE-GAPS.md` `GAP-B7`,
and `build-package.sh` (the Debian path this spec mirrors).

## 6. File inventory

`rpm -qlp`: 36 files, 4 owned directories - the same set the `.deb` installs.

```
0644 /etc/modprobe.d/sm750hdmidrm.conf            (config(noreplace))
0644 /etc/modules-load.d/sm750hdmidrm.conf        (config(noreplace))
dir  /usr/lib/sm750hdmifb
0755 /usr/lib/sm750hdmifb/write-xorg-config
0644 /usr/share/X11/xorg.conf.d/20-sm750hdmidrm.conf
dir  /usr/share/doc/sm750hdmifb
0644 /usr/share/doc/sm750hdmifb/{LICENSE,README.md,RELEASE-NOTES.md,TESTING.md,copyright}
dir  /usr/src/sm750hdmifb-0.6.0
0644 /usr/src/sm750hdmifb-0.6.0/{LICENSE,Makefile,README.md,dkms.conf}
dir  /usr/src/sm750hdmifb-0.6.0/src
0644 /usr/src/sm750hdmifb-0.6.0/src/{Kconfig,Makefile,ddk750.h,ddk750_chip.c,ddk750_chip.h,
     ddk750_display.c,ddk750_display.h,ddk750_hwi2c.c,ddk750_hwi2c.h,ddk750_mode.c,
     ddk750_mode.h,ddk750_power.c,ddk750_power.h,ddk750_reg.h,ddk750_swi2c.c,
     ddk750_swi2c.h,sii902x.c,sii902x.h,sm750_dither.c,sm750_dither.h,sm750_drm.c,
     sm750_drm_mode.c,sm750_drm_mode.h}
```

Deliberately **not** shipped: `DEBIAN/` (control, md5sums, postinst, prerm,
postrm - RPM metadata and the scriptlets in section 7 replace them),
`build-package.sh`, `tests/`, `tools/`, `.github/`, and every `docs/` file
except the four installed under `/usr/share/doc/sm750hdmifb`. The two Debian
conffiles map to `%config(noreplace)`; the Xorg snippet is a plain file in
both packages.

## 7. Divergence from the Debian maintainer scripts

`packaging/drm-postinst:66-73` calls `update-initramfs -u -k` and
`packaging/drm-postinst:86-89` exits `1` when no supported kernel has usable
headers. **Neither is ported**, and the spec records this in its `%posttrans`
comment: the driver is not needed to mount the root filesystem, so the Fedora
path is `dkms install` plus `depmod -a` and neither `update-initramfs` nor
`dracut` appears anywhere in the spec; and because a failing scriptlet aborts
the transaction, `%post`, `%posttrans` and `%preun` end in `exit 0`
unconditionally with every failure reported as a warning on stderr. `modprobe`
is not run: the module loads at the next boot or on demand.

## 8. Troubleshooting

**`dkms build` reports headers not found**

```
Error! Your kernel headers for kernel 7.3.4-100.fc43.x86_64 cannot be found at
/lib/modules/7.3.4-100.fc43.x86_64/build or /lib/modules/7.3.4-100.fc43.x86_64/source.
```

On a target host that means a missing package: `sudo dnf install
kernel-devel-$(uname -r)`, then re-run the transaction. `%posttrans` skips a
kernel whose `build/Makefile` is absent, so the install still succeeds and the
warning names the remedy:

```
warning: skipping 6.18.13-200.fc43.x86_64: matching kernel headers are absent
warning: no supported installed kernel has usable headers; the module was not built
```

Recover without reinstalling:
`sudo dkms install -m sm750hdmifb -v 0.6.0 -k "$(uname -r)"`. Archived:
`docs/evidence/packaging/06-posttrans-missing-headers.log`.

**Same message in a sandbox (test only).** The headers exist on this host
(`/usr/src/kernels/7.3.4-100.fc43.x86_64` with `Makefile` and `Module.symvers`;
`/lib/modules/7.3.4-100.fc43.x86_64/build` points at it). The sandbox failure
was a lookup-path artifact, not a missing package: with a custom
`--installtree`, dkms resolves the kernel tree at
`<installtree>/<kver>/build` or `<installtree>/<kver>/source`. Both fixes are
rootless:

```sh
# preferred: keep the sandbox self-contained with a read-only header symlink
mkdir -p /mega/tmp/sm750/t6/dkms/install/$(uname -r)
ln -s /usr/src/kernels/$(uname -r) /mega/tmp/sm750/t6/dkms/install/$(uname -r)/build
# fallback: name the tree explicitly
dkms ... build -k "$(uname -r)" --kernelsourcedir=/usr/src/kernels/$(uname -r)
```

`tests/check-rpm-dkms.sh` creates the symlink and falls back to
`--kernelsourcedir` when the tree is absent. The installed `%posttrans` has no
`--installtree`, so it never needs either flag. `/usr/src/kernels` contains
`7.2.15-100`, `7.3.3-100` and `7.3.4-100` but **no** 6.17 tree, so 6.17
coverage comes only from the extracted koji tree at
`/mega/tmp/sm750/t5/k617` (build matrix, not this test).

**`Deprecated feature: CLEAN`** during `dkms add` is expected: `dkms.conf`
carries a legacy `CLEAN` directive. Harmless, no action.

**EL9 caveats.** The spec uses portable macros (`%{_usrsrc}`,
`%{_sysconfdir}`, `%{_datadir}`, `%{_prefix}`, `%config(noreplace)`, `%dir`),
so it is expected to build on EL9 with an EPEL `dkms`. Recorded rather than
treated as blockers: `%{_docdir}` is undefined on the tested host, hence `%doc`
instead of an explicit path, and the `noarch` result carries a `%{?dist}`
release tag that differs per distribution. EL9 kernels below 6.17 are
unsupported by `BUILD_EXCLUSIVE_KERNEL` and stay documented as unsupported.

## 9. Rollback

```sh
sudo dnf remove -y sm750hdmifb
```

`%preun` runs `dkms remove -m sm750hdmifb -v 0.6.0 --all` while the source tree
exists, which unregisters every kernel DKMS built the module for. Erasing is
safe even when `%posttrans` never built anything. `dkms status -m sm750hdmifb
-v 0.6.0` must then print nothing. To drop a manual copy under `/lib/modules`
after the erase, DKMS no longer knows the module: remove
`/lib/modules/<kernel>/updates/dkms/sm750hdmidrm.ko` and run
`sudo depmod -a <kernel>`.