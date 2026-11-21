<!-- SPDX-License-Identifier: GPL-2.0-only -->
# RPM packaging (`packaging/sm750hdmifb.spec`)

How to build, install, verify and roll back the `sm750hdmifb` RPM. The Debian
path remains `build-package.sh`; both ship the same file set, with the
scriptlet divergences recorded in section 7.

## 1. Purpose

`packaging/sm750hdmifb.spec` produces a **noarch DKMS source carrier**:

| Macro / field | Value |
| --- | --- |
| `%global dkms_name` | `sm750hdmifb` |
| `%global dkms_version` | `0.6.2` |
| `%global module_name` | `sm750hdmidrm` |
| `Name` / `Version` / `Release` | `sm750hdmifb` / `0.6.2` / `1%{?dist}` |
| `BuildArch` | `noarch` |

Nothing is compiled at RPM build time: `%build` is empty. The package ships
the DKMS source tree under `/usr/src/sm750hdmifb-0.6.2`, the modprobe /
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

# Source0 is the tracked tree minus the development-only directories, exactly
# as build-package.sh; never tar the working tree. The list is declared once,
# in packaging/source-excludes.sh, which the packager and the release audit
# both read (defect A29).
. ./packaging/source-excludes.sh
mapfile -t skip < <(sm750_dev_only_pathspecs)
tracked=$(mktemp)
git ls-files -z -- . "${skip[@]}" >"$tracked"
tar -C . -czf "$topdir/SOURCES/sm750hdmifb-0.6.2-source.tar.gz" \
    --transform='s|^|sm750hdmifb-0.6.2/|' --null -T "$tracked"

rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
```

Artifacts (90 tracked files in the tarball, 36 files in the RPM):

```
/mega/tmp/sm750/t6/rpmbuild/SRPMS/sm750hdmifb-0.6.2-1.fc43.src.rpm
/mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-1.fc43.noarch.rpm
```

`rpmbuild -ba` exits `0`; the transcript is
`docs/evidence/packaging/01-rpmbuild.log`. The `rm -rf "$topdir"` makes the
result independent of earlier runs.

Archive-content rule: the source tarball is exactly the tracked tree minus the
development-only directories declared once in `packaging/source-excludes.sh`
(`docs/plan`, `docs/evidence`, `docs/images`), which is the same list
`build-package.sh` and `tests/audit-release.sh` read, so the packager and the
gate cannot drift apart.

## 4. Install, upgrade, erase

Root only by definition: the payload owns `/usr/src`, `/etc` and
`/var/lib/dkms`.

```sh
sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-1.fc43.noarch.rpm
sudo dkms status -m sm750hdmifb -v 0.6.2     # expected: ..., <kernel>: installed
sudo modprobe sm750hdmidrm                   # requires a free DRM minor
sudo dnf remove -y sm750hdmifb               # erase; %preun unregisters
sudo dkms status -m sm750hdmifb -v 0.6.2     # expected: no such module
```

None of these have run on this host: the account is unprivileged (`uid 1005`).
They are `GAP-B7` in `docs/evidence/EVIDENCE-GAPS.md`.

### Upgrade path (`$1 == 1` / `--rpm_safe_upgrade`)

| Stage | Scriptlet | Guard | Action |
| --- | --- | --- | --- |
| first install | `%post` | `[ "$1" -eq 1 ]` | `dkms add` |
| upgrade | `%post` | `$1 == 2`, skipped | tree already registered |
| install / upgrade | `%posttrans` | - | `dkms build`, `dkms install --force`, `depmod -a` per supported kernel, then the stale-registration purge |
| erase | `%preun` | `[ "$1" -eq 0 ]` | `dkms remove --all` |
| upgrade | `%preun` | `$1 == 1`, skipped | the new version needs the registration |
| - | `%postun` | not defined | no initramfs to regenerate |

`dkms add` runs only on first install because re-adding a populated
`/usr/src/sm750hdmifb-0.6.2` is an error and an exiting scriptlet aborts the
transaction. `%preun` (not `%postun`) removes the registration because DKMS
needs the source tree while unregistering.

### Stale-registration purge (`%posttrans`)

Releases before 0.6.0 registered the same module name at other versions and
never unregistered them, so a machine that ever carried 0.5.9 still reports it
after the upgrade:

```
sm750hdmifb/0.5.9, 7.3.3-100.fc43.x86_64, x86_64: built
sm750hdmifb/0.5.9, 7.3.4-100.fc43.x86_64, x86_64: built
sm750hdmifb/0.6.2, 7.2.15-100.fc43.x86_64, x86_64: installed
```

That is not cosmetic. Both `dkms.conf` files declare
`DEST_MODULE_LOCATION[0]="/updates/dkms"`, and `override_dest_module_location()`
in `/usr/sbin/dkms` (`dkms:509-521`, `case ... in fedora*|centos*|rhel*`)
rewrites it to `/extra`, so every registered version of this module name
installs to the single path `/lib/modules/<kernel>/extra/sm750hdmidrm.ko.xz`.
`dkms autoinstall`, which is what `dkms.service` runs on boot and what the DKMS
kernel hook runs after a kernel update, installs only the newest registered
version per module name and skips kernels where the module already looks
installed. A stale version that stays registered therefore takes the shared
destination path back on the next kernel install and silently replaces the
current driver with the pre-0.6.0 one.

`%posttrans` closes that hole after the build loop (the version being installed
must own the destination path first). For every `dkms status` line it parses
the module name and version, keeps only lines whose name is exactly
`%{dkms_name}` (`sm750hdmifb/` is matched, so a module named
`sm750hdmifb-something` is never touched), skips `%{dkms_version}`, removes each
remaining version at most once with
`dkms remove -m %{dkms_name} -v <version> --all`, and downgrades a failed
removal to a warning so the transaction is never aborted. The version always
comes from the status line; a hardcoded version would rot at the next release
and `tests/check-rpm-dkms.sh` fails if one appears.

Deliberately left alone: `/usr/src/sm750hdmifb-0.5.9`. It predates packaging,
no RPM owns it (`rpm -ql sm750hdmifb | grep -c 0.5.9` prints `0`), so `%files`
cannot remove it and a scriptlet must not delete an unowned 21 MB tree. The
host owner removes it by hand once, after confirming the purge ran:

```sh
sudo rm -rf /usr/src/sm750hdmifb-0.5.9
```

Verify the purge with `sudo dkms status`: exactly one version of `sm750hdmifb`
must remain, `0.6.2`, `installed` for every installed kernel, with no `0.5.9`
row and no `: added` line. The purge is idempotent - a second install finds
nothing to remove.


### When a removal fails (exit-code semantics)

`dkms remove` does not fail the same way for every leftover, and the purge has
to survive both outcomes:

| Host state of `/var/lib/dkms/sm750hdmifb/<version>/source` | `dkms remove -m sm750hdmifb -v <version> --all` |
| --- | --- |
| symlink dangles (target gone) | `Error! sm750hdmifb/<version> is broken!`, `Missing the source directory or the symbolic link pointing to it:`, `Manual intervention is required!`, exit **4** |
| directory exists but has no `dkms.conf`, module not installed | `Deleting module sm750hdmifb/<version> completely from the DKMS tree.`, exit **0** |

Both were measured with `dkms` 3.4.4 on this host against a scratch tree
(`--dkmstree`, `--sourcetree`, `--installtree`), never against `/var/lib/dkms`.

The exit-4 case is why `%posttrans` downgrades the call to
`|| echo "warning: dkms remove %{dkms_name}/$stale_version failed; remove it
by hand" >&2` (`packaging/sm750hdmifb.spec:227-228`) and still ends in
`exit 0`: a scriptlet that exits non-zero aborts the whole RPM transaction, so
the package would fail to install over a leftover it cannot delete anyway. The
warning is the operator's cue; the rest of the loop keeps purging the other
stale versions. `tests/check-rpm-dkms.sh` forces this branch with
`SHIM_FAIL_REMOVE=<version>` and asserts the exit 0, the exact warning text,
that the loop continued to the next version, that `%{dkms_version}` was still
never removed, and that no build or install ran during the purge.

Finding a leftover by hand:

```sh
dkms status | grep sm750hdmifb                    # every registered version
ls -l /var/lib/dkms/sm750hdmifb/<version>/source  # dangling -> exit 4 above
```

The one real occurrence on this host was not a packaging defect:
`/usr/src/sm750hdmifb-0.6.2` was a **git checkout** of the repository, not an
RPM payload, so its registration pointed at a directory the package never
owned. Host state, not a defect in `%files` or in the scriptlets.

`%posttrans` cannot repair such a leftover - it has no tree to remove and no
authority to delete a directory no RPM owns. The remedy is manual:

```sh
sudo rm -rf /usr/src/sm750hdmifb-<version>
sudo dnf reinstall -y /path/to/sm750hdmifb-<version>-1.fc43.noarch.rpm  # re-runs %posttrans
```

The purge is idempotent, so re-running it costs nothing; a second pass finds
either nothing to remove or a registration whose source tree is now gone and
warns again.

### Kernel-update rebuild

`dkms.conf` sets `AUTOINSTALL=yes`, so DKMS kernel hooks build and install the
module for a newly installed kernel; the RPM is not re-run. Confirm with
`dkms status -m sm750hdmifb -v 0.6.2`. The floor regex that `%posttrans` uses
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
OK: rpmbuild -ba exit 0: sm750hdmifb-0.6.2-1.fc43.src.rpm, sm750hdmifb-0.6.2-1.fc43.noarch.rpm
OK: dependencies: BuildRequires 4, runtime dkms, post dkms+kmod, preun dkms
OK: scriptlets: add in %post, build+install+depmod in %posttrans, remove in %preun, no %postun
OK: %files: 36 files, 4 owned directories, 2 %config(noreplace) entries
OK: missing headers: warning on stderr, exit 0; build/install/depmod sequence verified
OK: stale purge: only sm750hdmifb/0.5.9 removed, 0.6.2 and other module names untouched
OK: dkms sandbox: sm750hdmifb/0.6.2, 7.3.4-100.fc43.x86_64, x86_64: built
OK: built object: /mega/tmp/sm750/t6/dkms/sm750hdmifb/0.6.2/7.3.4-100.fc43.x86_64/x86_64/module/sm750hdmidrm.ko (320960 bytes, host tree untouched)
SKIP: dnf install sm750hdmifb-0.6.2-1.fc43.noarch.rpm: needs root (writes /usr/src, /etc, /var/lib/dkms)
SKIP: dkms status showing 'installed' in the host tree: needs root, follows the skipped dnf install
SKIP: dkms install (even with --installtree): 'Error! You must be root to use this command.'
SKIP: dkms remove -m sm750hdmifb -v 0.5.9 --all in the host tree: not in the sudoers allowlist (only -v 0.6.2 is); the purge runs inside the RPM %posttrans instead, and the rootless run above proves the call sequence
SKIP: modinfo of the installed module: needs root, follows the skipped dnf install
SKIP: dnf remove sm750hdmifb: needs root and the skipped dnf install
SKIP: dkms status after erase (registration gone): needs root, follows the skipped dnf remove
SKIP: closing commands recorded in docs/evidence/EVIDENCE-GAPS.md GAP-B7
RPM/DKMS checks passed: sm750hdmifb 0.6.2, sandbox built, root-only steps skipped
```

Exit codes: `0` every assertion held; `1` first failed assertion (reason on
stderr) or a usage/environment error (running as root, missing spec,
unexpected `$HOME/rpmbuild`). `SKIP` lines are printed, never silent.

Rootless checks: payload equality with `git ls-files`, full `rpmbuild -ba`
from a fresh `_topdir`, `rpm -qpR` / `rpm -qp --scripts` / `rpm -qp --qf` /
`rpm -qlp` metadata assertions, an offline `%posttrans` run with
`dkms`/`depmod` shims over two fake module roots (including a canned
`dkms status` listing that proves the stale purge removes `0.5.9` only), and a
real DKMS `add` + `build` producing `sm750hdmidrm.ko` with a matching
vermagic. `dkms install` is the one step that cannot be sandboxed: it refuses
a non-root caller even with `--dkmstree`, `--sourcetree` and `--installtree`
all on scratch, so the refusal is captured in `05-dkms-sandbox.log` and
reported as `SKIP`, while the host module tree is asserted absent.

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
dir  /usr/src/sm750hdmifb-0.6.2
0644 /usr/src/sm750hdmifb-0.6.2/{LICENSE,Makefile,README.md,dkms.conf}
dir  /usr/src/sm750hdmifb-0.6.2/src
0644 /usr/src/sm750hdmifb-0.6.2/src/{Kconfig,Makefile,ddk750.h,ddk750_chip.c,ddk750_chip.h,
     ddk750_display.c,ddk750_display.h,ddk750_hwi2c.c,ddk750_hwi2c.h,ddk750_mode.c,
     ddk750_mode.h,ddk750_power.c,ddk750_power.h,ddk750_reg.h,ddk750_swi2c.c,
     ddk750_swi2c.h,sii902x.c,sii902x.h,sm750_dither.c,sm750_dither.h,sm750_drm.c,
     sm750_drm_mode.c,sm750_drm_mode.h}
```

Deliberately **not** shipped: `DEBIAN/` (control, md5sums, postinst, prerm,
postrm - RPM metadata and the scriptlets in section 7 replace them),
`build-package.sh`, `tests/`, `tools/`, and every `docs/` file
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

The stale-registration purge is the one place where the RPM is *wider* than
the Debian script: `packaging/drm-postinst` removes a fixed predecessor list
and `rm -rf`s stale `/var/lib/dkms` trees whose `dkms.conf` is unreadable, while
`%posttrans` enumerates `dkms status` and removes every other registered
version of this module name. It removes registrations only; it never deletes an
unowned source tree, so `/usr/src/sm750hdmifb-0.5.9` survives and stays a
manual step (section 4).

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
`sudo dkms install -m sm750hdmifb -v 0.6.2 -k "$(uname -r)"`. Archived:
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

`%preun` runs `dkms remove -m sm750hdmifb -v 0.6.2 --all` while the source tree
exists, which unregisters every kernel DKMS built the module for. Erasing is
safe even when `%posttrans` never built anything. `dkms status -m sm750hdmifb
-v 0.6.2` must then print nothing. To drop a manual copy under `/lib/modules`
after the erase, DKMS no longer knows the module: remove
`/lib/modules/<kernel>/updates/dkms/sm750hdmidrm.ko` and run
`sudo depmod -a <kernel>`.