<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Deliverables index and clean-checkout reproduction

Every acceptance criterion of plan `20261117-sm750-driver-prod` mapped to a
path in this repository, with the command that verifies it. The criteria text
is the `acceptance_criteria` list in
`docs/plan/20261117-sm750-driver-prod/plan.yaml`; this file does not restate
it in different words.

Three labels are used throughout:

- `ROOT-REQUIRED` - the step needs a privilege this account does not have.
  The exact command is given, together with where its result would be stored.
  Such a step is never reported as executed.
- `GAP` - the artifact does not exist; the blocking denial and the closing
  command are in `docs/evidence/EVIDENCE-GAPS.md`.
- `PASS` - a command exited 0 and its transcript is committed under
  `docs/evidence/`.

## 1. Acceptance criteria map

| AC | Subject | Deliverable paths | Verification command | Root |
| --- | --- | --- | --- | --- |
| AC-1 | Device specifications archived with checksums | `docs/specs/INDEX.md`, `docs/specs/SHA256SUMS`, `docs/specs/GAPS.md`, `docs/specs/REGISTER-MAP.md` | `ls docs/specs` (four text files, no binary) and the checksum re-download in section 2.1 | no |
| AC-2 | Audit and defect inventory | `docs/AUDIT.md`, `docs/DEFECTS.md`, `docs/evidence/audit/identity-and-range.txt`, `docs/evidence/audit/privilege-probe.txt`, `docs/evidence/audit/release-gate-and-environment.txt`, `docs/evidence/audit/rootless-libdrm-check.txt` | `grep -cE '^.[[:space:]]A[0-9]' docs/AUDIT.md docs/DEFECTS.md` -> 24 and 25 (A25 was found post-audit in the kernel log and is recorded only in `docs/DEFECTS.md`; `docs/AUDIT.md` keeps the 24 it audited) | no |
| AC-3 | Runtime and hardware validation ladder | `docs/TEST-STRATEGY.md` sections 5 and 9, `docs/evidence/baseline/03-connector.txt`, `docs/evidence/builds/09-register-dump.log`, `docs/evidence/EVIDENCE-GAPS.md` GAP-B3/B4 | `grep -n 'GAP-B[34]' docs/evidence/EVIDENCE-GAPS.md` | partly; see section 3 |
| AC-4 | Test strategy and recorded results | `docs/TEST-STRATEGY.md`, `docs/evidence/builds/01-make-check.log` .. `docs/evidence/builds/19-cursor-alpha-fix.log` | evidence-existence loop in section 2.4 | no |
| AC-5 | Build integrity | `Makefile` (`check` at `Makefile:30-48`, `check-deps` at `Makefile:17-28`, `check-all-kernels` at `Makefile:50-51`), `tests/build-all-kernels.sh`, `docs/evidence/builds/01-make-check.log`, `docs/evidence/builds/02-check-all-kernels.log`, `docs/evidence/builds/03-kernel-7.2.15-100.log`, `docs/evidence/builds/04-kernel-7.3.3-100.log`, `docs/evidence/builds/05-kernel-7.3.4-100.log`, `docs/evidence/builds/06-kernel-6.17.1.log`, `docs/evidence/builds/11-warnings-scan.log` | `make check` and `./tests/build-all-kernels.sh`; section 2.5 | no |
| AC-6 | RPM/DKMS packaging | `packaging/sm750hdmifb.spec`, `docs/PACKAGING-RPM.md`, `tests/check-rpm-dkms.sh`, `docs/evidence/packaging/01-rpmbuild.log` .. `docs/evidence/packaging/07-check-rpm-dkms.log` | `./tests/check-rpm-dkms.sh`; section 2.6 | no (build), yes (install) |
| AC-7 | Deliverable index and reproduction | `docs/DELIVERABLES.md` (this file), `README.md`, `docs/ENVIRONMENT.md` | unreferenced-file check in section 2.7 | no |

## 2. Verification detail

Commands assume the repository root as working directory and the rootless
environment from `docs/ENVIRONMENT.md` section 4 exported (step 1 of
section 4 below). No command in this section needs root.

### 2.1 AC-1: specification archive

```sh
ls docs/specs
```

Expected: exactly `GAPS.md`, `INDEX.md`, `REGISTER-MAP.md`, `SHA256SUMS` - four
text files, no PDF or other vendor binary, which keeps `docs/PROVENANCE.md:47`
true. After the branch is committed, `git ls-files docs/specs` must list the
same four paths.

The checksums are reproduced by re-download, not by a committed copy; the
procedure is in `docs/specs/INDEX.md` under "Re-download and verify". The two
archived hashes are the datasheet `fac31257...531889` and the product brief
`6eafa724...bfd19f`, recorded in `docs/specs/SHA256SUMS`. Register coverage is
`docs/specs/REGISTER-MAP.md`; the unresolved items are `docs/specs/GAPS.md`.

### 2.2 AC-2: audit and defects

```sh
grep -cE '^.[[:space:]]A[0-9]' docs/AUDIT.md docs/DEFECTS.md
```

Expected: `24` for each file (S1 = 2, S2 = 8, S3 = 11, S4 = 3). Every row in
`docs/DEFECTS.md` carries a status of `fixed`, `accepted` or `deferred` with a
change reference; `A01` (no RPM spec) and `A02` (untracked files in the source
tarball) are `fixed`.

### 2.3 AC-3: validation ladder

The ladder is connector state -> enumeration -> modeset -> framebuffer
readback -> scanout CRC -> external capture, documented in
`docs/TEST-STRATEGY.md` section 5. Tiers 1 and 2 are backed by
`docs/evidence/baseline/03-connector.txt`; tiers 3 to 6 are `GAP` rows with
closing commands (GAP-B3 for KMS clients, GAP-B4 for the register read).

```sh
grep -n 'GAP-B[34]' docs/evidence/EVIDENCE-GAPS.md
cat docs/evidence/builds/09-register-dump.log
```

### 2.4 AC-4: test strategy and results

Every path named as evidence in `docs/TEST-STRATEGY.md` must exist:

```sh
grep -o 'docs/evidence/[A-Za-z0-9._/-]*' docs/TEST-STRATEGY.md | sort -u |
while read -r p; do test -e "$p" || echo "MISSING $p"; done
```

Expected: no output. Recorded totals are 10 `PASS`, 0 `FAIL`, 5 `GAP`; the
`GAP` rows are the four KMS-client probes and the register read, each pointing
at its denial.

### 2.5 AC-5: build integrity

```sh
make check KDIR=/lib/modules/7.3.3-100.fc43.x86_64/build CC=/usr/bin/gcc
JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh
grep -nE '(warning|error):' docs/evidence/builds/*.log
```

Expected: exit 0 and 17 recipe commands for `check`; the final line
`Built 9 sm750hdmidrm kernel/format combinations`; and only the
`pahole version differs` and `compiler differs` warnings, with none attributed
to `src/*.c` or `src/*.h` (`docs/evidence/builds/11-warnings-scan.log`).

### 2.6 AC-6: packaging

```sh
./tests/check-rpm-dkms.sh
```

Expected: exit 0. The script rebuilds the noarch RPM from a fresh `_topdir`,
asserts the payload against `git ls-files` (73 files), the `%files` list
(36 files), the scriptlets and the dependencies, runs the `%posttrans` branch
against shims, and reaches `dkms ... : built` in a sandbox. Root-only steps
print `SKIP` and are listed in section 3. Recipe and rollback:
`docs/PACKAGING-RPM.md`.

### 2.7 AC-7: this index

```sh
comm -23 <(find docs -type f | sort) \
         <(grep -o 'docs/[A-Za-z0-9._/-]*' docs/DELIVERABLES.md | sort -u)
```

Expected: no output, meaning every file under `docs/` is named by this file.
`README.md` links every user-facing document; see section 5.

## 3. Root-only steps

These are the steps that need root. Four are now closed or partly closed on
this host; the rest stay `GAP` in `docs/evidence/EVIDENCE-GAPS.md` until a
transcript is stored next to the other captures. The exact commands, the helper
bodies and the recovery recipe for a broken allowlist are in
`docs/ROOT-ACTIONS.md`. Source of the original denial evidence:
`docs/evidence/baseline/09-denials.txt`.

| Step | `ROOT-REQUIRED` command | Observed state |
| --- | --- | --- |
| Register readback | `sudo /usr/local/sbin/sm750-regs > /mega/tmp/sm750/regs-before.txt` (resolves the `dri/<N>` index from the by-path link) | **GAP-B4** until the 0.6.0 module is installed (T11). The debugfs facility exists and the grant works, but the loaded module is still 0.5.9 and has no `regs` file. |
| VBIOS image | `sudo /usr/local/sbin/sm750-vbios-dump /mega/tmp/sm750/vbios-01-00-0.bin` | **CLOSED, GAP-B1.** Captured 2026-11-18T10:11Z: 49152 bytes, sha256 `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`. The image is complete at 48 KiB (header size 0x60, PCIR image length 0x0060, whole-image checksum 0), so the helper's exit 2 and its `expected 65536` warning are a stale constant, not a short read. Signature `55 aa`, PCIR at 0x1c, 126f:0750, VBE 2.0, version 1.00.59-, build 05/14/19 16:25. Binary stays in `/mega/tmp/sm750/`, not committed; transcript `docs/evidence/baseline/18-vbios-dump.txt`. |
| Kernel log | `sudo -n dmesg` (also `sudo -n journalctl -k -b -q --no-pager`) | **CLOSED, GAP-B2.** Exit 0; 169860 bytes with 240 `sm750` lines measured 2026-11-18T09:36Z (154236 bytes / 150 lines at the earlier capture). |
| PCI config space > 0x40 | `sudo /usr/local/sbin/sm750-lspci` | **CLOSED, GAP-B5.** Exit 0, 9465 bytes, capability list above 0x40 present. |
| KMS clients | `modetest -c -M sm750hdmidrm`, `kmscube -D /dev/dri/card0 -c 60`, IGT `kms_setmode` | **PARTIAL, GAP-B3.** The card node opens unprivileged through the udev ACL; `modetest` and `kmscube` pass as pre-fix baselines (`docs/evidence/runtime/04-modeset.txt`, `05-kmscube.txt`), IGT fails (`06-igt.txt`). No scanout CRC or external capture. |
| RPM install | `sudo -n dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm` | **GAP-B7.** Granted, not executed. |
| Installed-state assertion | `sudo -n dkms status -m sm750hdmifb -v 0.6.0` (expected `: installed`) and `sudo -n modprobe sm750hdmidrm` | **GAP-B7.** Follows the install row; `dkms status` currently reports 0.5.9. |
| RPM erase | `sudo -n dnf remove -y sm750hdmifb` then `sudo -n dkms status -m sm750hdmifb -v 0.6.0` (expected no output) | **GAP-B7.** Granted, not executed. |

The KMS row no longer needs a privilege step: `/etc/udev/rules.d/99-sm750-coder-acl.rules`
grants `u:coder:rw` on the card node at every probe, and the SM750 registers no
render node, so `/dev/dri/renderD128` (the NVIDIA card at `02:00.0`) is not a
substitute. The three access mechanisms and their state are recorded in
`docs/ENVIRONMENT.md` section 5.1.

## 4. Clean-checkout reproduction

Reproduced rootless on Fedora 43, kernel `7.3.4-100.fc43.x86_64`, uid 1005, no
`$HOME` writes. Steps 1 to 7 are the whole software chain; step 8 is the
root-only remainder.

| Step | Needs | Root | Evidence produced by the recorded run |
| --- | --- | --- | --- |
| 0. clone and prerequisites | `git`, `make`, `/usr/bin/gcc` 15.3.1, `pkg-config`, `rg`, `python3` | no | - |
| 1. rootless libdrm | `dnf`, `rpm2cpio`, `cpio`, network | no | `docs/evidence/baseline/10-rootless-libdrm.txt` |
| 2. `make check` | kernel headers for the `KDIR` used | no | `docs/evidence/builds/01-make-check.log` |
| 3. build matrix | `kernel-devel` trees in `/usr/src/kernels` | no | `docs/evidence/builds/02-check-all-kernels.log` |
| 4. 6.17 floor tree | `dnf download` from Fedora koji, network, about 4 minutes | no | `docs/evidence/builds/06-kernel-6.17.1.log` |
| 5. `.deb` and release audit | `dpkg-deb` on the host | no | `docs/evidence/builds/07-build-package.log`, `docs/evidence/builds/08-audit-release.log` |
| 6. `rpmbuild` | `rpm-build`, `tar`, `git` | no | `docs/evidence/packaging/01-rpmbuild.log` |
| 7. RPM/DKMS gate | `dkms`, sandbox writable | no | `docs/evidence/packaging/07-check-rpm-dkms.log` |
| 8. install/erase, register dump, KMS clients | root | yes | section 3; GAP rows |

### Step 0: clone and tool check

```sh
git clone https://github.com/KodeMunkie/sm750hdmifb.git
cd sm750hdmifb
command -v make gcc pkg-config rg python3 dnf rpm2cpio cpio
/usr/bin/gcc --version | head -1     # must match CONFIG_GCC_VERSION of the kernel used
```

`gcc` on `PATH` may resolve to `/usr/local/cuda/bin/gcc`; every build command
below pins `CC=/usr/bin/gcc` for that reason (`docs/ENVIRONMENT.md` section 3).

### Step 1: rootless libdrm

No package is installed and no root is used. `make check` needs
`pkg-config --exists libdrm`, which this provides.

```sh
mkdir -p /mega/tmp/sm750/t3/libdrm
cd /mega/tmp/sm750/t3/libdrm
dnf download libdrm libdrm-devel
for r in *.rpm; do rpm2cpio "$r" | cpio -idm; done

export PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm
export LD_LIBRARY_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64
export C_INCLUDE_PATH=/mega/tmp/sm750/t3/libdrm/usr/include
pkg-config --modversion libdrm      # expected: 2.4.134
```

### Step 2: `make check`

```sh
make check KDIR=/lib/modules/7.3.3-100.fc43.x86_64/build CC=/usr/bin/gcc
```

Expected: exit 0, 17 recipe commands (`Makefile:32-48`). The target depends on
`check-deps` (`Makefile:17-28`), which prints an install hint instead of a raw
`xf86drm.h` error when libdrm or ripgrep is missing. The build writes module
objects into `src/`; `make clean` removes them.

### Step 3: build matrix on installed trees

```sh
JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh
```

Expected final line: `Built 9 sm750hdmidrm kernel/format combinations` (three
installed trees times three scanout defaults). Per tree:

```sh
JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh \
    /lib/modules/7.2.15-100.fc43.x86_64/build
```

Header trees are a host property: `kernel-devel` for each kernel built must be
installed, and `/lib/modules/<kver>/build` must resolve.

### Step 4: declared 6.17 floor

The floor is `BUILD_EXCLUSIVE_KERNEL` in `dkms.conf` (`6.17` and newer). No
6.17 package is installable from the configured repositories on Fedora 43, so
the tree is extracted instead of installed:

```sh
mkdir -p /mega/tmp/sm750/k617 && cd /mega/tmp/sm750/k617
dnf download --destdir . \
  https://kojipkgs.fedoraproject.org/packages/kernel/6.17.1/300.fc43/x86_64/kernel-devel-6.17.1-300.fc43.x86_64.rpm
rpm2cpio kernel-devel-6.17.1-300.fc43.x86_64.rpm | cpio -idm

JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh \
    /mega/tmp/sm750/k617/usr/src/kernels/6.17.1-300.fc43.x86_64
```

Expected final line: `Built 3 ...`. The extraction takes about four minutes and
one retry is needed when `dnf` reports
`Interrupted by header callback: Inconsistent server data`. Prerequisite:
network access only; nothing is installed.

### Step 5: `.deb` and release audit

```sh
./build-package.sh
./tests/audit-release.sh
```

Expected: `dist/sm750hdmifb_0.6.0_all.deb`, `dist/sm750hdmifb-0.6.0-source.tar.gz`,
`dist/SHA256SUMS`, and `Release audit passed: .../dist/RELEASE-AUDIT.txt`.
Prerequisite: `dpkg-deb` on `PATH`. `make check-package` (`Makefile:71-73`) runs
both commands and is what CI invokes.

### Step 6: `rpmbuild`

`rpmdev-setuptree` is deliberately not used, because `~/.rpmmacros` points
`%_topdir` at `$HOME`. The recipe is `docs/PACKAGING-RPM.md` section 3:

```sh
work=/mega/tmp/sm750/t6
topdir=$work/rpmbuild
rm -rf -- "$topdir"
mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}

tracked=$work/tracked
git ls-files -z -- . ':(exclude)docs/images/*' >"$tracked"
tar -C . -czf "$topdir/SOURCES/sm750hdmifb-0.6.0-source.tar.gz" \
    --transform='s|^|sm750hdmifb-0.6.0/|' --null -T "$tracked"

rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
```

Expected: `RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm` and the matching
`.src.rpm`, exit 0. Prerequisites: `rpm-build`, `git`, `tar`. The package is a
noarch DKMS source carrier; nothing is compiled at RPM build time.

### Step 7: RPM/DKMS gate and sandbox

```sh
./tests/check-rpm-dkms.sh
```

Expected: exit 0 with the `OK:` assertions and seven `SKIP:` lines for the
root-only steps. Work directory and evidence directory default to
`/mega/tmp/sm750/t6` and `docs/evidence/packaging/`; override with
`SM750_RPM_WORK` and `SM750_RPM_EVIDENCE`. A sandbox `dkms` run needs a header
symlink at `<installtree>/<kver>/build` or `--kernelsourcedir`
(`docs/PACKAGING-RPM.md` section 8); the script creates it.

### Step 8: root-only remainder

Nothing here is executed by this repository's checks. Use the commands in
section 3 and store each transcript next to the existing captures; only then
does the corresponding `GAP` row become `PASS`.

## 5. Documentation inventory

Every file under `docs/` is listed once; no other file is needed to reproduce
or audit the work. `README.md` links the user-facing subset in its Developers
list.

### 5.1 User and developer documentation

| Path | Content |
| --- | --- |
| `README.md` | install (Debian `.deb`, RPM/DKMS), modes, parameters, troubleshooting |
| `docs/LOGBOOK.md` | append-only chronological record of every action and change, newest entry last |
| `docs/ROOT-ACTIONS.md` | every host root action with its exact command, the helper bodies and the GAP each closes |
| `docs/HARDWARE.md` | board identification and capability comparison |
| `docs/MODES.md` | catalogue, clock and transmitter risk |
| `docs/PARAMETERS.md` | module parameters and their defaults |
| `docs/REGISTERS.md` | tracked register reference and how to read the dump |
| `docs/PROVENANCE.md` | licensing and third-party material policy |
| `docs/RELEASE-NOTES.md` | 0.6.0 changes and the untested-kernel statement |
| `docs/STAGING-BENCHMARK.md` | DMA batch benchmark procedure and analysis rules |
| `docs/TESTING.md` | validation scope, recovery, live reload |
| `docs/VBLANK.md` | private vblank timer and its locking |

### 5.2 Audit, test and packaging documentation

| Path | Content |
| --- | --- |
| `docs/AUDIT.md` | repository audit, 24 defects with reproduction and evidence |
| `docs/DEFECTS.md` | one disposition per defect: fixed, accepted or deferred |
| `docs/TEST-STRATEGY.md` | suites S1-S8, recorded results, remaining gaps |
| `docs/PACKAGING-RPM.md` | spec purpose, build recipe, install, verify, rollback |
| `docs/ENVIRONMENT.md` | host, header trees, tool matrix, privilege state |
| `docs/DELIVERABLES.md` | this index and the reproduction guide |

### 5.3 Specification archive

| Path | Content |
| --- | --- |
| `docs/specs/INDEX.md` | source URL, version, date, SHA-256 and authority per document |
| `docs/specs/SHA256SUMS` | the two archived vendor-document hashes |
| `docs/specs/GAPS.md` | unresolved specifications, each with a substitute |
| `docs/specs/REGISTER-MAP.md` | every MMIO register used by `src/*.c` with a citation |

### 5.4 Evidence

| Path | Content |
| --- | --- |
| `docs/evidence/EVIDENCE-GAPS.md` | GAP-B1 .. GAP-B7 with denial and closing command |
| `docs/evidence/audit/identity-and-range.txt` | HEAD, remotes, layout, declared kernel range |
| `docs/evidence/audit/privilege-probe.txt` | privilege denials as probed by the audit |
| `docs/evidence/audit/release-gate-and-environment.txt` | release-gate failure and host toolchain |
| `docs/evidence/audit/rootless-libdrm-check.txt` | rootless libdrm chain and `make check` |
| `docs/evidence/baseline/capture.sh` | regenerates the baseline corpus, read-only |
| `docs/evidence/baseline/00-host-identity.txt` | `uname`, `/etc/os-release`, DMI, CPU, RAM |
| `docs/evidence/baseline/01-lspci.txt` | `lspci -vvv` for `01:00.0` |
| `docs/evidence/baseline/02-edid.txt` | EDID hex dump and checksum |
| `docs/evidence/baseline/03-connector.txt` | connector status, DPMS, mode list |
| `docs/evidence/baseline/04-dkms-status.txt` | `dkms status` |
| `docs/evidence/baseline/05-modinfo.txt` | `modinfo sm750hdmidrm` |
| `docs/evidence/baseline/06-lsmod.txt` | loaded module rows |
| `docs/evidence/baseline/07-pci-config-space.txt` | first 64 bytes of config space |
| `docs/evidence/baseline/08-toolchain.txt` | presence and version of every tool |
| `docs/evidence/baseline/09-denials.txt` | every privilege denial, verbatim |
| `docs/evidence/baseline/10-rootless-libdrm.txt` | libdrm extraction and `check-vblank` compile |
| `docs/evidence/baseline/11-journalctl.txt` | whether `journalctl -k` substitutes for `dmesg` |
| `docs/evidence/baseline/12-external-suites.txt` | repository availability of the external suites |
| `docs/evidence/baseline/13-make-check-count.txt` | the 17 recipe lines of the `check` target |
| `docs/evidence/baseline/14-compiler-and-libdrm-rpm.txt` | `gcc`/`cc` resolution, libdrm RPM facts |
| `docs/evidence/baseline/15-edid-decode.txt` | `edid-decode` of the panel EDID |
| `docs/evidence/baseline/16-kernel-devmem-policy.txt` | strict-devmem settings, module-parameter count |
| `docs/evidence/baseline/17-kernel-headers.txt` | `build` link resolution, kernel packages |
| `docs/evidence/baseline/18-vbios-dump.txt` | VBIOS capture through the allowlisted helper: size, sha256, `PCIR`, VBE block, ROM-restore check |
| `docs/evidence/builds/01-make-check.log` | `make check`, exit 0, 17 commands |
| `docs/evidence/builds/02-check-all-kernels.log` | matrix over three installed trees, Built 9 |
| `docs/evidence/builds/03-kernel-7.2.15-100.log` | matrix on 7.2.15-100, Built 3 |
| `docs/evidence/builds/04-kernel-7.3.3-100.log` | matrix on 7.3.3-100, Built 3 |
| `docs/evidence/builds/05-kernel-7.3.4-100.log` | matrix on 7.3.4-100, Built 3 |
| `docs/evidence/builds/06-kernel-6.17.1.log` | extracted 6.17.1 floor tree, Built 3 |
| `docs/evidence/builds/07-build-package.log` | `.deb` and source tarball build |
| `docs/evidence/builds/08-audit-release.log` | release audit, exit 0 |
| `docs/evidence/builds/09-register-dump.log` | debugfs `regs` read attempt, denied |
| `docs/evidence/builds/10-defect-before-after.log` | before/after form of every fixed defect |
| `docs/evidence/builds/11-warnings-scan.log` | warning scan of all build logs, none from `src/` |
| `docs/evidence/builds/12-version-and-gapb3.log` | 0.6.0 declarations, spec/driver guard proofs, built-object version, GAP-B3 access capture |
| `docs/evidence/builds/13-make-check-0.6.0.log` | `make check` at 0.6.0, exit 0, 17 commands |
| `docs/evidence/builds/14-check-all-kernels-0.6.0.log` | matrix at 0.6.0 over three installed trees, Built 9 |
| `docs/evidence/builds/15-kernel-6.17.1-0.6.0.log` | 6.17.1 floor tree at 0.6.0, Built 3 |
| `docs/evidence/builds/16-build-package-0.6.0.log` | `.deb` + source tarball at 0.6.0 and release audit, exit 0 |
| `docs/evidence/builds/17-check-rpm-dkms-0.6.0.log` | full `tests/check-rpm-dkms.sh` run at 0.6.0 |
| `docs/evidence/builds/18-sudoers-verify-0.6.0.log` | regenerated allowlist: zero colons, `visudo -c -f` twice |
| `docs/evidence/builds/19-cursor-alpha-fix.log` | T13: the blend-mode property, the object proof, `make check` and both kernel matrices after the fix |
| `docs/evidence/packaging/01-rpmbuild.log` | `rpmbuild -ba`, exit 0 (0.6.0; the 0.5.9 run is archived in `docs/evidence/packaging/0.5.9/`) |
| `docs/evidence/packaging/02-rpm-qp-scripts.log` | scriptlet assertions |
| `docs/evidence/packaging/03-rpm-qlp.log` | `%files` list, 36 files |
| `docs/evidence/packaging/04-rpm-qpR.log` | dependency assertions |
| `docs/evidence/packaging/05-dkms-sandbox.log` | sandbox DKMS `built` with a real module |
| `docs/evidence/packaging/06-posttrans-missing-headers.log` | missing-header branch of `%posttrans` |
| `docs/evidence/packaging/07-check-rpm-dkms.log` | full `tests/check-rpm-dkms.sh` run |
| `docs/evidence/packaging/0.5.9/01-rpmbuild.log` | `rpmbuild -ba` at 0.5.9, exit 0 |
| `docs/evidence/packaging/0.5.9/02-rpm-qp-scripts.log` | scriptlet assertions at 0.5.9 |
| `docs/evidence/packaging/0.5.9/03-rpm-qlp.log` | `%files` list at 0.5.9 |
| `docs/evidence/packaging/0.5.9/04-rpm-qpR.log` | dependency assertions at 0.5.9 |
| `docs/evidence/packaging/0.5.9/05-dkms-sandbox.log` | sandbox DKMS `built` at 0.5.9 |
| `docs/evidence/packaging/0.5.9/06-posttrans-missing-headers.log` | missing-header branch at 0.5.9 |
| `docs/evidence/packaging/0.5.9/07-check-rpm-dkms.log` | full `tests/check-rpm-dkms.sh` run at 0.5.9 (rejected revision) |
| `docs/evidence/runtime/01-original-state.txt` | display state before any T10 modeset |
| `docs/evidence/runtime/02-modetest-connector.txt` | connector and mode enumeration unprivileged |
| `docs/evidence/runtime/03-modetest-properties.txt` | plane, CRTC and connector properties |
| `docs/evidence/runtime/04-modeset.txt` | `modetest -s` modeset, pre-fix baseline |
| `docs/evidence/runtime/05-kmscube.txt` | `kmscube` run, pre-fix baseline |
| `docs/evidence/runtime/06-igt.txt` | IGT `kms_setmode` result, still a gap |
| `docs/evidence/runtime/07-kernel-log.txt` | kernel log during the runtime tiers, pre-fix baseline |
| `docs/evidence/runtime/cursor-alpha-01-warning-before.txt` | T13: the cursor-plane alpha warning reproduced from the pre-fix 0.5.9 build |

### 5.5 Images and plan

| Path | Content |
| --- | --- |
| `docs/images/desktop-2464x1080-logical.png` | logical 2464x1080 desktop, used by `README.md` |
| `docs/images/desktop-2048x1080-scanout.png` | the 2048x1080 compressed scanout |
| `docs/images/desktop-2560x1080-physical.jpg` | the panel after monitor stretch |
| `docs/plan/20261117-sm750-driver-prod/plan.yaml` | plan, acceptance criteria and task record |

## 6. Source-of-truth order

When two documents disagree, the archived evidence wins, then the source, then
the prose. The resolved conflicts are listed in `docs/TEST-STRATEGY.md`
section 10. Two values that are easy to get wrong:

- The `check` target has 17 recipe commands at `Makefile:32-48`; the
  prerequisite list at `Makefile:30-31` continues on a tab-indented line that is
  not a command.
- The header matrix is 7.2.15-100, 7.3.3-100 and 7.3.4-100 plus the extracted
  6.17.1-300 tree. `7.2.13-100` no longer has a `build` link on this host.
