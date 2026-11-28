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
| `%global dkms_version` | `0.6.11` |
| `%global module_name` | `sm750hdmidrm` |
| `Name` / `Version` / `Release` | `sm750hdmifb` / `0.6.11` / `1%{?dist}` |
| `BuildArch` | `noarch` |

Nothing is compiled at RPM build time: this spec's `%build` is empty, and a
`rpm -qlp` of the package lists no ELF object. The one compiled deliverable,
`sm750-smi`, ships from the separate, arch-dependent
`packaging/sm750hdmifb-tools.spec`; rpm cannot express it as a subpackage of a
noarch parent (section 10).

The package ships the DKMS source tree under
`/usr/src/sm750hdmifb-0.6.11`, the modprobe / modules-load / Xorg assets and the
Xorg helper script. DKMS compiles `src/` against each installed kernel, so one
noarch RPM serves every architecture.
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
tar -C . -czf "$topdir/SOURCES/sm750hdmifb-0.6.11-source.tar.gz" \
    --transform='s|^|sm750hdmifb-0.6.11/|' --null -T "$tracked"

rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
```

Artifacts (156 tracked files in the tarball, 36 files in the module RPM):

```
/mega/tmp/sm750/t6/rpmbuild/SRPMS/sm750hdmifb-0.6.11-1.fc43.src.rpm
/mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.11-1.fc43.noarch.rpm
```

`rpmbuild -ba` exits `0`; the transcript is
`docs/evidence/packaging/01-rpmbuild.log`. The `rm -rf "$topdir"` makes the
result independent of earlier runs. The second package, `sm750hdmifb-tools`, is
built by a second `rpmbuild -ba` over the same `Source0` (section 10); the gate
runs both invocations and captures them in the same transcript.

Archive-content rule: the source tarball is exactly the tracked tree minus the
development-only directories declared once in `packaging/source-excludes.sh`
(`docs/plan`, `docs/evidence`, `docs/images`, `docs/notes`), which is the same
list `build-package.sh` and `tests/audit-release.sh` read, so the packager and
the gate cannot drift apart. `docs/notes/` holds research that quotes vendor
documents whose redistribution terms are unknown, so it is tracked but never
shipped.

## 4. Install, upgrade, erase

Root only by definition: the payload owns `/usr/src`, `/etc` and
`/var/lib/dkms`.

```sh
sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.11-1.fc43.noarch.rpm
sudo dkms status -m sm750hdmifb -v 0.6.11     # expected: ..., <kernel>: installed
sudo modprobe sm750hdmidrm                   # requires a free DRM minor
sudo dnf remove -y sm750hdmifb               # erase; %preun unregisters
sudo dkms status -m sm750hdmifb -v 0.6.11     # expected: no such module
```

The utility is a separate transaction and does not touch any of these paths:
`sudo dnf install -y .../RPMS/x86_64/sm750hdmifb-tools-0.6.11-1.fc43.x86_64.rpm`
(section 10).

These steps run as root by definition. The install and the module reload have
been run on this host by its owner for `0.6.2-3`
(`docs/evidence/runtime/28-dangling-kernel-link.txt` section 8), and the erase
and reinstall direction is closed: `GAP-B7` is `CLOSED` as recorded in
`docs/evidence/EVIDENCE-GAPS.md:575-690`, where the transaction ran as root in
both directions (`%preun` erase with "Before uninstall, this module version was
ACTIVE on this kernel" and "Deleting module sm750hdmifb/0.6.0 completely from
the DKMS tree", and `%posttrans` install building and signing for three
kernels).

### Upgrade path (`$1 == 1` / `--rpm_safe_upgrade`)

| Stage | Scriptlet | Guard | Action |
| --- | --- | --- | --- |
| first install | `%post` | `[ "$1" -eq 1 ]` | `dkms add` |
| upgrade | `%post` | `$1 == 2`, skipped | tree already registered |
| install / upgrade | `%posttrans` | - | the stale-registration purge, then `dkms build`, `dkms install --force`, `depmod -a` per supported kernel |
| erase | `%preun` | `[ "$1" -eq 0 ]` | `dkms remove --all` |
| upgrade | `%preun` | `$1 == 1`, skipped | the new version needs the registration |
| - | `%postun` | not defined | no initramfs to regenerate |

`dkms add` runs only on first install because re-adding a populated
`/usr/src/sm750hdmifb-0.6.11` is an error and an exiting scriptlet aborts the
transaction. `%preun` (not `%postun`) removes the registration because DKMS
needs the source tree while unregistering.

### Stale-registration purge (`%posttrans`)

Releases before 0.6.0 registered the same module name at other versions and
never unregistered them, so a machine that ever carried 0.5.9 still reports it
after the upgrade:

```
sm750hdmifb/0.5.9, 7.3.3-100.fc43.x86_64, x86_64: built
sm750hdmifb/0.5.9, 7.3.4-100.fc43.x86_64, x86_64: built
sm750hdmifb/0.6.11, 7.2.15-100.fc43.x86_64, x86_64: installed
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

`%posttrans` closes that hole **before** the build loop, and the order is
load-bearing rather than cosmetic. `dkms install` of the new version is not a
plain copy: it first uninstalls the older registered version for that kernel.
On a host where that registration is broken - a leftover from an older package
whose files rpm already erased, so `/var/lib/dkms/sm750hdmifb/<version>/source`
dangles - dkms exits non-zero with `Error! Could not locate dkms.conf file.`
and installs nothing, so the shared destination path keeps the old module and
the version being installed is never delivered. Purging first leaves `dkms
install` with no stale registration to uninstall. That failure was observed on
this host with 0.6.2-1 while a broken 0.6.1 entry was registered; the verbatim
transcript is `docs/evidence/runtime/27-posttrans-install-failure.txt`.

For every `dkms status` line the purge parses the module name and version,
keeps only lines whose name is exactly `%{dkms_name}` (`sm750hdmifb/` is
matched, so a module named `sm750hdmifb-something` is never touched), skips
`%{dkms_version}`, removes each remaining version at most once with
`dkms remove -m %{dkms_name} -v <version> --all`, and downgrades a failed
removal to a warning so the transaction is never aborted. The version always
comes from the status line; a hardcoded version would rot at the next release
and `tests/check-rpm-dkms.sh` fails if one appears.

The version is also validated before it reaches a path, because the tree path
below is built from it: a value that is empty, contains `/`, is `.` or `..`, or
carries any byte outside `[0-9A-Za-z._-]` is skipped
(`packaging/sm750hdmifb.spec:198`, `:207-212`). The tree root is
`dkms_root=${SM750_RPM_DKMS_ROOT:-/var/lib/dkms}` (`:144`), overridable so the
test can point it at a sandbox; rpm never sets the variable, so the installed
default is always `/var/lib/dkms`.

Deliberately left alone: `/usr/src/sm750hdmifb-0.5.9`. It predates packaging,
no RPM owns it (`rpm -ql sm750hdmifb | grep -c 0.5.9` prints `0`), so `%files`
cannot remove it and a scriptlet must not delete an unowned 21 MB tree. The
host owner removes it by hand once, after confirming the purge ran:

```sh
sudo rm -rf /usr/src/sm750hdmifb-0.5.9
```

Verify the purge with `sudo dkms status`: exactly one version of `sm750hdmifb`
must remain, `0.6.11`, `installed` for every installed kernel, with no `0.5.9`
row and no `: added` line. The purge is idempotent - a second install finds
nothing to remove.

### The active-version link, a second shape of the leftover (A40)

A registration is not the only thing that survives an erase. For every kernel
dkms has built this module for, the tree also carries
`/var/lib/dkms/sm750hdmifb/kernel-<kernel>-<arch>`, a symlink to
`<version>/<kernel>/<arch>`. On this host the three of them still pointed at
`0.6.1`, a version rpm had erased, and nothing listed them: `dkms status` shows
registrations, and a dangling link is not one.

That link is enough to abort an install. `do_install()` in dkms 3.4.4
(`/usr/sbin/dkms:1768`) computes
`active_link="$dkms_tree/$module/kernel-$kernelver-$arch"`; `:1783-1784` runs
`old_active_version=$(readlink "$active_link")` and
`old_active_version=${old_active_version%%/*}`, so the version comes from the
link target alone with no check that it is still registered or still on disk;
`:1866-1868` then runs `delayed_depmod=1 do_uninstall "$kernelver" "$arch"` for
that version and exits `die 6` when it fails. `do_uninstall` needs
`$dkms_tree/$module/$module_version/source/dkms.conf`, which the erase removed,
so every kernel aborted before installing anything, the only visible record
being `dkms status -m sm750hdmifb` with `0.6.2, <kernel>, x86_64: built`.

The purge therefore clears these links in a second loop, after the version loop
and before the build loop (`packaging/sm750hdmifb.spec:245-251`):
`for dkms_link in "$dkms_root/%{dkms_name}"/kernel-*`, `[ -L "$dkms_link" ] ||
continue`, and only when `[ ! -d "$dkms_link/" ]` - dkms always targets a
version directory, so `-d` with a trailing slash is the resolution test -
`echo "removing dangling DKMS kernel link: $dkms_link" >&2` then
`rm -f -- "$dkms_link"`. A link that resolves is never touched, a regular file
or directory that merely shares the name prefix is skipped by `-L`, and nothing
outside `"$dkms_root/%{dkms_name}"` is considered. Removal is safe: the next
successful install recreates the link, and dkms installs nothing through it.

The `0.6.2-3` upgrade ran on this host on 2026-11-21 and took the successful
half of the branch above: the three links resolved to `0.6.2`, `do_install()`
read that version out of them and uninstalled it as the version active for the
kernel, and the module was installed for all three kernels; no
`removing dangling DKMS kernel link:` line appeared because no link dangled
(`docs/evidence/runtime/28-dangling-kernel-link.txt` section 8).


### When a removal fails (exit-code semantics)

`dkms remove` does not fail the same way for every leftover, and the purge has
to survive both outcomes:

| Host state of `/var/lib/dkms/sm750hdmifb/<version>/source` | `dkms remove -m sm750hdmifb -v <version> --all` |
| --- | --- |
| symlink dangles (target gone) | `Error! sm750hdmifb/<version> is broken!`, `Missing the source directory or the symbolic link pointing to it:`, `Manual intervention is required!`, exit **4** |
| directory exists but has no `dkms.conf`, module not installed | `Deleting module sm750hdmifb/<version> completely from the DKMS tree.`, exit **0** |

Both were measured with `dkms` 3.4.4 on this host against a scratch tree
(`--dkmstree`, `--sourcetree`, `--installtree`), never against `/var/lib/dkms`.

The exit-4 case is why `%posttrans` downgrades the call to a warning and
still ends in `exit 0` (`packaging/sm750hdmifb.spec:218-226`): a scriptlet that
exits non-zero aborts the whole RPM transaction, so the package would fail to
install over a leftover it cannot delete anyway. The rest of the loop keeps
purging the other stale versions.

A failed removal escalates exactly once, and only against a tree that is
demonstrably broken:

```
warning: dkms remove sm750hdmifb/<version> failed; remove it by hand
warning: removing broken DKMS registration tree: /var/lib/dkms/sm750hdmifb/<version>
```

The second line is followed by `rm -rf --` on that tree, and it appears only
when the version directory exists **and** `<tree>/source/dkms.conf` is not a
readable file - the shape where `dkms remove` has nothing to unregister and
only the directory is left. This is what dkms itself instructs (`If this
module version is no longer needed, you can remove the stale directory.`). A
tree with a readable `dkms.conf` is never deleted by the scriptlet; `dkms
remove` owns that case. Without the escalation the broken tree survives for
ever and blocks the next `dkms install` (A37).

`tests/check-rpm-dkms.sh` covers both branches with `SHIM_FAIL_REMOVE`: the
plain failure asserts exit 0, the exact warning text, that the loop continued
to the next version, that `%{dkms_version}` was still never removed, and that
no build or install ran during the purge; a second scenario plants a broken
0.6.1 tree with a sibling module's canary, asserts the tree is gone and the
canary intact, then that `dkms install` for the running kernel is still
attempted afterwards with no `dkms install failed` in the transcript.

Finding a leftover by hand:

```sh
dkms status | grep sm750hdmifb                    # every registered version
ls -l /var/lib/dkms/sm750hdmifb/<version>/source  # dangling -> exit 4 above
```

One real occurrence on this host was not a packaging defect:
`/usr/src/sm750hdmifb-0.6.2` was a **git checkout** of the repository, not an
RPM payload, so its registration pointed at a directory the package never
owned. Host state, not a defect in `%files` or in the scriptlets.

The escalation deletes a registration tree under `/var/lib/dkms` and nothing
else: it never touches `/usr/src`, where an unowned source tree may live. When
the *source* tree is the leftover, the remedy is manual:

```sh
sudo rm -rf /usr/src/sm750hdmifb-<version>
sudo dnf reinstall -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-3.fc43.noarch.rpm  # re-runs %posttrans
```

The purge is idempotent, so re-running it costs nothing; a second pass finds
either nothing to remove or a registration whose source tree is now gone and
warns again.

### Kernel-update rebuild

`dkms.conf` sets `AUTOINSTALL=yes`, so DKMS kernel hooks build and install the
module for a newly installed kernel; the RPM is not re-run. Confirm with
`dkms status -m sm750hdmifb -v 0.6.11`. The floor regex that `%posttrans` uses
is byte-identical to `BUILD_EXCLUSIVE_KERNEL` and
`packaging/drm-postinst:73-76`; the test fails if any of the three drifts.

## 5. Verification

```sh
cd /path/to/sm750hdmifb
./tests/check-rpm-dkms.sh          # exit 0 = pass, non-zero = regression
```

Rootless; writes only under `/mega/tmp/sm750/t6` (override `SM750_RPM_WORK`),
never `$HOME`, archives output in `docs/evidence/packaging/` (override
`SM750_RPM_EVIDENCE`).

The transcripts are the tool output verbatim, so every captured command runs
under `LC_ALL=C LANG=C` (`tests/check-rpm-dkms.sh:32-33`): a localized host
would otherwise commit translated `rpm`/`rpmbuild` messages, which is exactly
what happened before T45 (11 non-ASCII lines in `01-rpmbuild.log`, 40 in
`03-rpm-qlp.log`, 1 in `05-dkms-sandbox.log`). Nothing post-processes the
output; the capture environment is the fix. After the last transcript is
written, `transcripts_ascii` (`tests/check-rpm-dkms.sh:89`, called at `:1002`) fails the run on
any non-ASCII byte in
`docs/evidence/packaging/0[1-6]-*.log` and prints each offending file with its
line numbers, so the defect cannot come back silently. The planted control
`plant_localized_evidence` injects one Russian `rpmbuild` status line (as octal
escapes, so the script itself stays ASCII) into a copy of `01-rpmbuild.log` and
must be rejected. This was an evidence-hygiene fix, not a shipped-behaviour
defect: the spec, the driver and the packaged payload are unchanged. The
`docs/evidence/packaging/0.5.9/` archive is the frozen transcript of the
rejected 0.5.9 revision, produced before the C-locale capture; it is kept
unedited as the historical record and is not covered by the gate.

Expected on Fedora 43 with kernel 7.3.4-100:

```
OK: source payload matches the ship list (132 files)
OK: rpmbuild -ba exit 0: sm750hdmifb-0.6.11-1.fc43.src.rpm, sm750hdmifb-0.6.11-1.fc43.noarch.rpm, sm750hdmifb-tools-0.6.11-1.fc43.x86_64.rpm
OK: dependencies: BuildRequires 4 (module) and 2 (tools), runtime dkms, post dkms+kmod, preun dkms
OK: tools package: BuildRequires gcc+libdrm-devel, runtime libdrm, arch x86_64
OK: scriptlets: add in %post, build+install+depmod in %posttrans, remove in %preun, no %postun
OK: %files: 36 files, 4 owned directories, 2 %config(noreplace) entries
OK: tools %files: /usr/bin/sm750-smi only, 0755, no module content; payload runs
plant_purge_after_build: rejected
plant_clean_directive: rejected
plant_unconditional_hint: rejected
plant_broken_tree_escalation: rejected (no broken-tree warning)
plant_unsafe_version: rejected (an unsafe version reached dkms remove)
plant_dangling_link_kept: rejected (the second dangling kernel link survived)
plant_localized_evidence: rejected
OK: missing headers: warning on stderr, exit 0; purge, build, install, depmod sequence verified
OK: stale purge: sm750hdmifb/0.5.9 and 0.6.0 removed, 0.6.11 and other module names untouched
OK: failed removal: dkms exit 4 downgraded to the spec warning, exit 0, loop continued
OK: broken 0.6.1 tree: deleted before the build loop, install still attempted, exit 0
OK: unsafe status field: skipped before any path is formed, dkms root intact
OK: dangling kernel link: removed before the build loop, resolvable link kept, exit 0
OK: dkms.conf has no CLEAN directive; console zero-frame hint is conditional
OK: planted controls: 8 rejected
OK: evidence transcripts 01-06: no non-ASCII byte, captured under LC_ALL=C
OK: dkms sandbox: sm750hdmifb/0.6.11, 7.3.4-100.fc43.x86_64, x86_64: built
OK: built object: /mega/tmp/sm750/t6/dkms/sm750hdmifb/0.6.11/7.3.4-100.fc43.x86_64/x86_64/module/sm750hdmidrm.ko (366136 bytes, host tree untouched)
SKIP: dnf install sm750hdmifb-0.6.11-1.fc43.noarch.rpm: needs root (writes /usr/src, /etc, /var/lib/dkms)
SKIP: dnf install sm750hdmifb-tools-0.6.11-1.fc43.x86_64.rpm: needs root (writes /usr/bin)
SKIP: dkms status showing 'installed' in the host tree: needs root, follows the skipped dnf install
SKIP: dkms install (even with --installtree): 'Error! You must be root to use this command.'
SKIP: dkms remove -m sm750hdmifb -v 0.5.9 --all in the host tree: not in the sudoers allowlist (only -v 0.6.2 is); the purge runs inside the RPM %posttrans instead, and the rootless run above proves the call sequence
SKIP: modinfo of the installed module: needs root, follows the skipped dnf install
SKIP: dnf remove sm750hdmifb: needs root and the skipped dnf install
SKIP: dkms status after erase (registration gone): needs root, follows the skipped dnf remove
SKIP: closing commands recorded in docs/evidence/EVIDENCE-GAPS.md GAP-B7
RPM/DKMS checks passed: sm750hdmifb 0.6.11 (+ sm750hdmifb-tools 0.6.11/x86_64), sandbox built, 8 planted controls rejected, root-only steps skipped
```

`OK: source payload adds 1 not-yet-tracked deliverable(s): tools/sm750-smi.c`
precedes the ship-list line while `tools/sm750-smi.c` is still untracked; the
line disappears on its own once the file is committed, so the gate neither
skips the file nor needs an exemption list.

Exit codes: `0` every assertion held; `1` first failed assertion (reason on
stderr), a planted control that was not rejected, or a usage/environment error
(running as root, missing spec, unexpected `$HOME/rpmbuild`). `SKIP` lines are
printed, never silent. The count in the last line is the number of planted
controls the run rejected; it must equal the number defined in the script, and
that number is eight: `tests/check-rpm-dkms.sh` defines the seven controls named
above plus `plant_trailing_whitespace` at `:1026`. The per-control lines in the
block above are an excerpt of one run, not the full set.
The root-only steps hidden behind those `SKIP` lines have since run on this
host for `0.6.2-3`, run interactively by its owner; section 8 of
`docs/evidence/runtime/28-dangling-kernel-link.txt` holds that transcript, and
it shows the active-version branch of `do_install()` completing against a
healthy registration for all three kernels.

Rootless checks: payload equality with `git ls-files`, full `rpmbuild -ba`
from a fresh `_topdir`, `rpm -qpR` / `rpm -qp --scripts` / `rpm -qp --qf` /
`rpm -qlp` metadata assertions, an offline `%posttrans` run with
`dkms`/`depmod` shims over sandbox module and DKMS roots (canned `dkms status`
listings that prove the purge runs before the build loop, removes every other
registered version at most once, deletes one demonstrably broken tree, and
never lets an unsafe version token reach a path), eight planted controls that
must each be rejected, and a real DKMS `add` + `build` producing
`sm750hdmidrm.ko` with a matching vermagic. `dkms install` is the one step that cannot be sandboxed: it refuses
a non-root caller even with `--dkmstree`, `--sourcetree` and `--installtree`
all on scratch, so the refusal is captured in `05-dkms-sandbox.log` and
reported as `SKIP`, while the host module tree is asserted absent.

Companion files: `packaging/sm750hdmifb.spec`,
`packaging/sm750hdmifb-tools.spec`, `tests/check-rpm-dkms.sh`,
`docs/evidence/packaging/01`-`07`, `docs/evidence/EVIDENCE-GAPS.md` `GAP-B7`,
and `build-package.sh` (the Debian path this spec mirrors, including the split
`sm750hdmifb-tools` `.deb`).

## 6. File inventory

`rpm -qlp`: 36 files, 4 owned directories - the same set the module `.deb`
installs. The utility is one more file in its own package (section 10).

```
0644 /etc/modprobe.d/sm750hdmidrm.conf            (config(noreplace))
0644 /etc/modules-load.d/sm750hdmidrm.conf        (config(noreplace))
dir  /usr/lib/sm750hdmifb
0755 /usr/lib/sm750hdmifb/write-xorg-config
0644 /usr/share/X11/xorg.conf.d/20-sm750hdmidrm.conf
dir  /usr/share/doc/sm750hdmifb
0644 /usr/share/doc/sm750hdmifb/{LICENSE,README.md,RELEASE-NOTES.md,TESTING.md,copyright}
dir  /usr/src/sm750hdmifb-0.6.11
0644 /usr/src/sm750hdmifb-0.6.11/{LICENSE,Makefile,README.md,dkms.conf}
dir  /usr/src/sm750hdmifb-0.6.11/src
0644 /usr/src/sm750hdmifb-0.6.11/src/{Kconfig,Makefile,ddk750.h,ddk750_chip.c,ddk750_chip.h,
     ddk750_display.c,ddk750_display.h,ddk750_hwi2c.c,ddk750_hwi2c.h,ddk750_mode.c,
     ddk750_mode.h,ddk750_power.c,ddk750_power.h,ddk750_reg.h,ddk750_swi2c.c,
     ddk750_swi2c.h,sii902x.c,sii902x.h,sm750_dither.c,sm750_dither.h,sm750_drm.c,
     sm750_drm_mode.c,sm750_drm_mode.h}
```

Deliberately **not** shipped: `DEBIAN/` (control, md5sums, postinst, prerm,
postrm - RPM metadata and the scriptlets in section 7 replace them),
`build-package.sh`, `tests/`, `tools/`, and every `docs/` file
except the four installed under `/usr/share/doc/sm750hdmifb`. `tools/` here
means the source: the compiled binary ships from `sm750hdmifb-tools`
(section 10), never the `.c` file. The two Debian
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
the Debian script: `packaging/drm-postinst` removes a fixed predecessor list,
while `%posttrans` enumerates `dkms status` and removes every other registered
version of this module name. Both delete a registration tree under
`/var/lib/dkms` when dkms itself refuses to remove it because its
`source/dkms.conf` is unreadable (section 4); neither deletes an unowned
`/usr/src` tree, so `/usr/src/sm750hdmifb-0.5.9` survives and stays a manual
step (section 4). Unlike the Debian script, the RPM purge runs *before* the
build loop, because a broken registration makes `dkms install` abort (A37).

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
warning: no kernel received the module; check the warnings above and run: dkms install -m sm750hdmifb -v 0.6.11 -k <kernel>
```

The last line names the remedy rather than a diagnosis: it is printed whenever
no kernel was served, whichever warning above explains why. Headers are one
cause; a broken stale registration that blocked `dkms install` was another
before A37, and a failed build is a third. The warnings above it carry the
specific reason.

Recover without reinstalling:
`sudo dkms install -m sm750hdmifb -v 0.6.11 -k "$(uname -r)"`. Archived:
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

**`Deprecated feature: CLEAN`** must not appear any more. It used to: every
`dkms add` printed `Deprecated feature: CLEAN
(/var/lib/dkms/sm750hdmifb/<version>/source/dkms.conf)` because `dkms.conf`
carried a legacy `CLEAN=` directive, and this section used to call it expected
and harmless. The directive was in fact inert - in dkms 3.4.4
`/usr/sbin/dkms:582-585` is the only occurrence of `CLEAN` in the script and it
exists to emit that warning, so the clean command never ran (defect A38). The
line is deleted, so a warning of this shape means an older package is still
installed. The rule for the shipped file: no `dkms.conf` directive may produce
a deprecation warning, and `tests/check-rpm-dkms.sh` rejects `CLEAN=` in the
working tree and in the payload extracted from the built RPM.

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

`%preun` runs `dkms remove -m sm750hdmifb -v 0.6.11 --all` while the source tree
exists, which unregisters every kernel DKMS built the module for. Erasing is
safe even when `%posttrans` never built anything. `dkms status -m sm750hdmifb
-v 0.6.11` must then print nothing. To drop a manual copy under `/lib/modules`
after the erase, DKMS no longer knows the module: remove
`/lib/modules/<kernel>/updates/dkms/sm750hdmidrm.ko` and run
`sudo depmod -a <kernel>`.
## 10. The two packages

The DKMS module ships as source and is architecture-independent; `sm750-smi`
is a compiled ELF binary. One noarch parent cannot carry an arch-dependent
subpackage: rpm 6.0.2 refuses the spec outright.

```
$ rpmbuild -ba packaging/sm750hdmifb.spec        # with a %package tools block
error: line 11: Only noarch subpackages are supported: BuildArch: x86_64
error: query of specfile packaging/sm750hdmifb.spec failed, can't parse
```

Without an explicit `BuildArch` the subpackage inherits `noarch` from
`BuildArch: noarch` in the parent and the binary is filed as noarch, which
would break a multi-arch repository. Removing `noarch` from the parent is the
other escape, and it would make the module package arch-specific too, losing
the one-RPM-serves-every-architecture property and diverging from
`dist/sm750hdmifb_0.6.11_all.deb`. Both shapes were measured on this host
before choosing the third: **two specs built from one `Source0`**.

| | `packaging/sm750hdmifb.spec` | `packaging/sm750hdmifb-tools.spec` |
| --- | --- | --- |
| `Name` | `sm750hdmifb` | `sm750hdmifb-tools` |
| `Version` / `Release` | `0.6.11` / `1%{?dist}` | `0.6.11` / `1%{?dist}` |
| `BuildArch` | `noarch` | none; the build target, `x86_64` here |
| `BuildRequires` | `rpm-build`, `dkms`, `make`, `gcc` | `gcc`, `libdrm-devel` |
| `Requires` | `dkms`; post `dkms`, `kmod`; preun `dkms` | `libdrm` |
| `%build` | empty | compiles `tools/sm750-smi.c` |
| payload | 36 files, 4 owned directories | `/usr/bin/sm750-smi`, mode 0755 |

Both specs read `Source0: sm750hdmifb-%{version}-source.tar.gz`, the same
archive the `%prep` of section 3 produces, so the two packages always carry the
same source revision. The tools spec declares `%global debug_package %{nil}`:
the utility is a single 50 KB file, and the distribution default would add
`-debuginfo` and `-debugsource` subpackages, turning this project's deliverable
from two package names into four artifacts that the `.deb` side does not have.
The tool's payload is exactly one file and owns no directory - `%{_bindir}` is
owned by `filesystem` - so `rpm -qlp` prints one line:

```
/usr/bin/sm750-smi
```

and none of the module package's paths (no `/usr/src`, `/etc`, `/usr/lib` or
`/usr/share` entry); the module package's file list is unchanged, 36 files and
4 owned directories, with no `/usr/bin/sm750-smi`.

### Building both

```sh
rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb-tools.spec
```

produces two SRPMs and two binary RPMs (0.6.11 / Fedora 43):

```
$topdir/SRPMS/sm750hdmifb-0.6.11-1.fc43.src.rpm
$topdir/SRPMS/sm750hdmifb-tools-0.6.11-1.fc43.src.rpm
$topdir/RPMS/noarch/sm750hdmifb-0.6.11-1.fc43.noarch.rpm
$topdir/RPMS/x86_64/sm750hdmifb-tools-0.6.11-1.fc43.x86_64.rpm
```

`libdrm-devel` is a real `BuildRequires` of the tools package: `%build` starts
with `pkg-config --exists libdrm` and fails with
`sm750hdmifb-tools: pkg-config cannot find libdrm; install libdrm-devel` rather
than compiling against a guessed path. On a host without it, the pinned
rootless tree works without root (see `docs/ENVIRONMENT.md` section 3):

```sh
export PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm
export LD_LIBRARY_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64
```

### Installing and removing

```sh
sudo dnf install -y "$topdir"/RPMS/noarch/sm750hdmifb-0.6.11-1.fc43.noarch.rpm \
                    "$topdir"/RPMS/x86_64/sm750hdmifb-tools-0.6.11-1.fc43.x86_64.rpm
sm750-smi --query=name,driver.version
sudo dnf remove -y sm750hdmifb-tools     # removes /usr/bin/sm750-smi only
```

The two packages are independent: erasing `sm750hdmifb-tools` leaves the DKMS
registration and the module alone, and erasing `sm750hdmifb` leaves the utility
in place, reporting the driver as absent. `dnf` resolves the arch automatically
when both come from a repository (`sudo dnf install sm750hdmifb
sm750hdmifb-tools`), so no `.x86_64` suffix is needed there.

### The Debian path

`build-package.sh` produces the same split: `sm750hdmifb_0.6.11_all.deb`
(`Architecture: all`, the module payload) and
`sm750hdmifb-tools_0.6.11_<arch>.deb` (`Architecture:` from
`dpkg --print-architecture`, `Depends: libdrm2`, payload `./usr/bin/sm750-smi`
at 0755), plus the source archive. If `pkg-config --exists libdrm` fails the
script prints
`build-package.sh: skipping sm750hdmifb-tools: pkg-config cannot find libdrm`
and still builds the module package and the source archive - a release is
never half built - and `SHA256SUMS` covers exactly the artifacts that exist.
`./build-package.sh --help` states that rule; `tests/audit-release.sh` fails if
the tools `.deb` is missing, has a different version/release, lacks
`Depends: libdrm2`, carries module content, or if `SHA256SUMS` does not verify.

### Verification

`tests/check-rpm-dkms.sh` runs both `rpmbuild` invocations and asserts the
two-package contract: exactly two SRPMs, one `noarch` binary RPM, one RPM for
`$(uname -m)`, identical `Version`/`Release` in both, the tools spec's
`BuildRequires` (`gcc`, `libdrm-devel`), the tools package's runtime `libdrm`
requirement, its `%files` as exactly `/usr/bin/sm750-smi` at `0755` with no
owned directory and no module path, the module package without
`/usr/bin/sm750-smi`, and a payload extracted with `rpm2cpio` that runs
`--list-fields`. Every assertion about the DKMS lifecycle in sections 4 and 5 is
unchanged and still runs against the module package.
