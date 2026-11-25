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
| AC-2 | Audit and defect inventory | `docs/AUDIT.md`, `docs/DEFECTS.md`, `docs/evidence/audit/identity-and-range.txt`, `docs/evidence/audit/privilege-probe.txt`, `docs/evidence/audit/release-gate-and-environment.txt`, `docs/evidence/audit/rootless-libdrm-check.txt` | `grep -cE '^.[[:space:]]A[0-9]' docs/AUDIT.md docs/DEFECTS.md` -> 24 and 44 (that grep counts one header row per defect id; `docs/AUDIT.md` keeps the 24 it audited, `docs/DEFECTS.md` carries the later dispositions A25-A45, with A31 present as its own detail section rather than a table row) | no |
| AC-3 | Runtime and hardware validation ladder | `docs/TEST-STRATEGY.md` sections 5 and 9, `docs/evidence/baseline/03-connector.txt`, `docs/evidence/runtime/08-register-dump.txt` (the successful dump; `docs/evidence/builds/09-register-dump.log` is the earlier denied attempt), `docs/evidence/scanout/01-build.txt` .. `docs/evidence/scanout/06-crc-debugfs-runtime.txt`, `docs/evidence/EVIDENCE-GAPS.md` GAP-B3/B4 | `grep -n 'GAP-B[34]' docs/evidence/EVIDENCE-GAPS.md` | partly; see section 3 |
| AC-4 | Test strategy and recorded results | `docs/TEST-STRATEGY.md`, `tests/check-scanout-crc.sh`, `docs/evidence/builds/01-make-check.log` .. `docs/evidence/builds/19-cursor-alpha-fix.log` | evidence-existence loop in section 2.4 | no |
| AC-5 | Build integrity | `Makefile` (`check` at `Makefile:30-48`, `check-deps` at `Makefile:17-28`, `check-all-kernels` at `Makefile:50-51`), `tests/build-all-kernels.sh`, `docs/evidence/builds/01-make-check.log`, `docs/evidence/builds/02-check-all-kernels.log`, `docs/evidence/builds/03-kernel-7.2.15-100.log`, `docs/evidence/builds/04-kernel-7.3.3-100.log`, `docs/evidence/builds/05-kernel-7.3.4-100.log`, `docs/evidence/builds/06-kernel-6.17.1.log`, `docs/evidence/builds/11-warnings-scan.log` | `make check` and `./tests/build-all-kernels.sh`; section 2.5 | no |
| AC-6 | RPM/DKMS packaging and the split tools package | `packaging/sm750hdmifb.spec`, `packaging/sm750hdmifb-tools.spec`, `build-package.sh`, `docs/PACKAGING-RPM.md` (section 10), `tests/check-rpm-dkms.sh`, `tests/audit-release.sh`, `docs/evidence/packaging/01-rpmbuild.log` .. `docs/evidence/packaging/07-check-rpm-dkms.log` | `./tests/check-rpm-dkms.sh` (two RPMs, same version/release, tools payload only `/usr/bin/sm750-smi`) and `./tests/audit-release.sh` (both `.deb` files and `SHA256SUMS`); section 2.6 | no (build), yes (install) |
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

Expected: `docs/AUDIT.md:24` and `docs/DEFECTS.md:38` - the command counts one
table row per defect id, A01-A24 in the audit and A01-A30 plus A32-A39 in the
defect list (`A31` is documented in prose only, so it has no table row).
`docs/AUDIT.md` keeps the 24 defects it audited (S1 = 2, S2 = 8, S3 = 11,
S4 = 3); `docs/DEFECTS.md` adds the fourteen later dispositions `A25`-`A30` and
`A32`-`A39`. Every
row in `docs/DEFECTS.md` carries a status of `fixed`, `accepted` or `deferred`
with a change reference; `A01` (no RPM spec) and `A02` (untracked files in the
source tarball) are `fixed`.

### 2.3 AC-3: validation ladder

The ladder is connector state -> enumeration -> modeset -> framebuffer
readback -> scanout CRC -> external capture, documented in
`docs/TEST-STRATEGY.md` section 5. Tiers 1 and 2 are backed by
`docs/evidence/baseline/03-connector.txt`; tiers 3 to 6 are `GAP` rows with
closing commands (GAP-B3 for KMS clients, GAP-B4 for the register read).

T26 added the read path behind tier 4 and tier 5: `src/sm750_drm.c` computes a
CRC over the bounded visible scanout region in VRAM and exposes it as the CRTC
CRC source `scanout` and as the `sm750_scanout` debugfs dump, and
`tests/check-scanout-crc.sh` (`make crc-check`, opt-in) asserts their
structural agreement. The CRC covers the scanout source bytes, not the emitted
pixels, so tier 5 stays partial; the runtime transcript is a `SKIP` on this
host for the root-only debugfs reason in `docs/evidence/scanout/04-checks.txt`.

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

Expected: no output. The opt-in live scanout test is `tests/check-scanout-crc.sh`
(`make crc-check`), deliberately outside `check` because it needs the card,
root and a mounted debugfs; it exits 77 with one `SKIP:` line where those are
absent, and the Makefile turns 77 into success like `vbios-trace`. Recorded
totals are 13 `PASS`, 2 `FAIL`, 3 `GAP`, as
`docs/TEST-STRATEGY.md` section 4 states (`Counts: 13 PASS, 2 FAIL, 3 GAP.`);
the `GAP` rows are R11 (debugfs `regs`), R12 (the skipped live vblank probe) and
the VT-blocked IGT subset inside R15, each pointing at its denial.

### 2.5 AC-5: build integrity

```sh
make check KDIR=/lib/modules/7.3.3-100.fc43.x86_64/build CC=/usr/bin/gcc
JOBS=12 CC=/usr/bin/gcc ./tests/build-all-kernels.sh
grep -nE '(warning|error):' docs/evidence/builds/*.log
```

Expected: exit 0 and 18 recipe commands for `check`; the final line
`Built 9 sm750hdmidrm kernel/format combinations`; and only the
`pahole version differs` and `compiler differs` warnings, with none attributed
to `src/*.c` or `src/*.h` (`docs/evidence/builds/11-warnings-scan.log`).

### 2.6 AC-6: packaging

```sh
./tests/check-rpm-dkms.sh
```

Expected: exit 0. The script rebuilds the noarch RPM from a fresh `_topdir`,
asserts the payload against `git ls-files` (143 payload files in the current
tree; the same command the script uses is `git ls-files -- . ':(exclude)docs/plan'
':(exclude)docs/evidence' ':(exclude)docs/images' ':(exclude)docs/notes' |
wc -l`), the `%files` list
(36 files), the scriptlets and the dependencies, runs the `%posttrans` branch
against shims, and reaches `dkms ... : built` in a sandbox. Root-only steps
print `SKIP` and are listed in section 3. Recipe and rollback:
`docs/PACKAGING-RPM.md`.

### 2.7 AC-7: this index

```sh
comm -23 <(git ls-files docs | sort) \
         <(grep -o 'docs/[A-Za-z0-9._/-]*' docs/DELIVERABLES.md | sort -u)
```

Expected: no output, meaning every tracked file under `docs/` is named by this
file. The check reads `git ls-files`, not `find`, so untracked working files
such as the final reviewer's `docs/ACCEPTANCE-REPORT.md` are outside it. Before
T23 this check printed 21 tracked paths; section 5 now lists all of them.
`README.md` links every user-facing document; see section 5.

### 2.8 Static analysis (opt-in, not part of `check`)

```sh
make static
KDIR=/usr/src/kernels/7.3.4-100.fc43.x86_64 \
  STATIC_KERNELS=/mega/tmp/sm750/t5/k617/usr/src/kernels/6.17.1-300.fc43.x86_64 \
  ./tests/check-static.sh --logs "$(mktemp -d)"
```

Expected: exit 0 and `static gate: PASS`. The target runs sparse, smatch,
cppcheck, coccinelle and pahole over `src/`, normalises each finding to a
fingerprint without line numbers and fails on any fingerprint missing from
`tests/static/baseline/`. It is deliberately outside `check`, whose 18 recipe
commands are listed at `Makefile:32-49`, and it exits 0 with an
`analysers not installed, skipping` notice where the toolchain is absent, so
building and packaging need nothing new. Triage of every recorded finding, the
planted-defect control proving each analyser analysed the files, and the
non-default tool configuration are in [STATIC-ANALYSIS.md](STATIC-ANALYSIS.md);
the one accepted residual is `A28` in [DEFECTS.md](DEFECTS.md). Evidence:
`docs/evidence/builds/20-static-sparse.log` to `25-static-gate.log`.

## 3. Root-only steps

These are the steps that need root. Four are now closed or partly closed on
this host; the rest stay `GAP` in `docs/evidence/EVIDENCE-GAPS.md` until a
transcript is stored next to the other captures. The exact commands, the helper
bodies and the recovery recipe for a broken allowlist are in
`docs/ROOT-ACTIONS.md`. Source of the original denial evidence:
`docs/evidence/baseline/09-denials.txt`.

| Step | `ROOT-REQUIRED` command | Observed state |
| --- | --- | --- |
| Register readback | `sudo /usr/local/sbin/sm750-regs > /mega/tmp/sm750/regs-before.txt` (resolves the `dri/<N>` index from the by-path link) | **CLOSED, GAP-B4.** Exit 0 on the loaded 0.6.0 module, 49 registers with `# card node: /dev/dri/card0 (debugfs dri/0)`; captured as `docs/evidence/runtime/08-register-dump.txt`. |
| VBIOS image | `sudo /usr/local/sbin/sm750-vbios-dump /mega/tmp/sm750/vbios-01-00-0.bin` | **CLOSED, GAP-B1.** Captured 2026-11-18T10:11Z: 49152 bytes, sha256 `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`. The image is complete at 48 KiB (header size 0x60, PCIR image length 0x0060, whole-image checksum 0), so the helper's exit 2 and its `expected 65536` warning are a stale constant, not a short read. Signature `55 aa`, PCIR at 0x1c, 126f:0750, VBE 2.0, version 1.00.59-, build 05/14/19 16:25. The v3 body documented in `docs/ROOT-ACTIONS.md` section 3.3 sets `EXPECT=49152` and adds the `55 aa` check; it was installed by the host owner on 2026-11-18T12:07Z and re-executed with exit 0, `signature 55aa, checksum ok`, hashing to the same value. Binary stays in `/mega/tmp/sm750/`, not committed; transcript `docs/evidence/baseline/18-vbios-dump.txt`. |
| Kernel log | `sudo -n dmesg` (also `sudo -n journalctl -k -b -q --no-pager`) | **CLOSED, GAP-B2.** Exit 0; 169860 bytes with 240 `sm750` lines measured 2026-11-18T09:36Z (154236 bytes / 150 lines at the earlier capture). |
| PCI config space > 0x40 | `sudo /usr/local/sbin/sm750-lspci` | **CLOSED, GAP-B5.** Exit 0, 9465 bytes, capability list above 0x40 present; stored as `docs/evidence/baseline/19-pci-config-space-full.txt`. |
| KMS clients | `modetest -c -M sm750hdmidrm`, `kmscube -D /dev/dri/card0 -c 60`, IGT `kms_setmode` | **PARTIAL, GAP-B3.** The card node opens unprivileged through the udev ACL; `modetest` and `kmscube` pass as pre-fix baselines (`docs/evidence/runtime/04-modeset.txt`, `05-kmscube.txt`), IGT on 0.6.0 (`docs/evidence/runtime/19-igt-0.6.0.txt`) runs `kms_addfb_basic` to completion with 26 SUCCESS / 14 SKIP / 1 FAIL, the single failure being `size-max` at `tests/kms_addfb_basic.c:594` which A26 records as correct by design. The `/dev/tty0` ACL in `docs/ROOT-ACTIONS.md` section 4.1 was installed on 2026-11-18T12:08Z, so the five binaries that used to abort at `kmstest_set_vt_graphics_mode` with `errno 13` can open the VT. No scanout CRC or external capture. |
| RPM install | `sudo -n dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm` | **CLOSED, GAP-B7.** Executed 2026-11-18; `%posttrans` built and installed the module for 7.2.15-100, 7.3.3-100 and 7.3.4-100 (`docs/evidence/runtime/12-rpmbuild-0.6.0.txt`). |
| Scanout readback | `sudo make crc-check` (or `sudo ./tests/check-scanout-crc.sh`) with a client drawing on CRTC-0 | **PASS.** `docs/evidence/scanout/09-crc-single-owner.txt` section 5: with DRM core owning `crtc-0/crc/{control,data}`, `crc/control` lists `scanout` (and `scanout*` while armed), `crc/data` yields twelve stable entries for a static frame, the CRC changes between a black and a white frame and the `sm750_scanout` dump agrees with both. The single root entry point is `/usr/local/sbin/sm750-crc-cycle`; it exits 0 and prints `RESULT: scanout CRC check passed`. |
| Installed-state assertion | `sudo -n dkms status -m sm750hdmifb -v 0.6.0` (expected `: installed`) and `sudo -n modprobe sm750hdmidrm` | **CLOSED, GAP-B7.** `dkms status` reports 0.6.0 `installed` for all three kernels, the module loads, and `/sys/module/sm750hdmidrm/version` reads 0.6.0. The only remaining stale rows are two `0.5.9 ... built` registrations, which task T22 removes. |
| RPM erase | `sudo -n dnf remove -y sm750hdmifb` then `sudo -n dkms status -m sm750hdmifb -v 0.6.0` (expected no output) | **CLOSED, GAP-B7.** Executed as the rollback proof: `%preun` ran `dkms remove --all`, the object file was deleted and the display survived (`docs/evidence/runtime/20-rollback.txt`). Recorded hazard: the erase leaves the module loaded with no file on disk, so a reboot in that state would leave card0 driverless; 0.6.0 was reinstalled and a `modprobe -r`/`modprobe` cycle proved the fresh package loads. |

The KMS row no longer needs a privilege step: `/etc/udev/rules.d/99-sm750-coder-acl.rules`
grants `u:coder:rw` on the card node at every probe. The SM750 also registers a
render node from 0.6.5 on (`/dev/dri/renderD131`, 226:131), but a render node
carries no KMS objects, so `/dev/dri/renderD128` (the NVIDIA card at `02:00.0`)
is still not a substitute for the card node. The three access mechanisms and
their state are recorded in `docs/ENVIRONMENT.md` section 5.1.

### 3.1 Second output: the console on the SM750 HDMI port

Why these root actions are safe to run while someone is using the machine. The
SM750 HDMI output shows the kernel console because the driver registers its own
in-kernel fbdev client at
`drm_client_setup(&sdev->drm, drm_format_info(DRM_FORMAT_XRGB8888))`
(`src/sm750_drm.c:3784`); that client is the only user of the SM750 CRTC. The
kernel log records the console takeover before any userspace client attaches:

```text
[    6.265979] sm750hdmidrm 0000:01:00.0: [drm] full-frame backbuffer staging enabled (4147200 bytes per buffer)
[    6.291648] Console: switching to colour frame buffer device 240x67
[    6.341676] sm750hdmidrm 0000:01:00.0: [drm] fb0: sm750hdmidrmdrm frame buffer device
```

`4147200` is `1920 * 1080 * 2`, one RGB565 buffer at the mode the fbdev client
sets. No `/dev/fb*` node exists because `CONFIG_FB_DEVICE` is unset (A24 in
`docs/DEFECTS.md`); the console still reaches the panel. The monitor stays
attached to the SM750 connector: `card0-HDMI-A-1` reports `connected`, and
nothing detaches it. The user's desktop runs on the NVIDIA GTX 1070 instead
(`card1`, `0000:02:00.0`, `card1-DVI-D-1` connected, `kwin_wayland` pid 2252),
and `card0` has no userspace DRM master.

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
git clone https://github.com/GuramDuka/sm750hdmifb.git
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

Expected: exit 0, 18 recipe commands (`Makefile:32-49`). The target depends on
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

Expected: `dist/sm750hdmifb_0.6.4_all.deb`, `dist/sm750hdmifb-tools_0.6.4_<arch>.deb`
(`<arch>` is `dpkg --print-architecture`, `amd64` here),
`dist/sm750hdmifb-0.6.4-source.tar.gz`, `dist/SHA256SUMS` listing exactly those
artifacts, and `Release audit passed: .../dist/RELEASE-AUDIT.txt`.
Prerequisite: `dpkg-deb` on `PATH` and, for the tools package, the libdrm
development files; without them `build-package.sh` prints a skip line and still
produces the module package and the source archive. `make check-package`
(`Makefile:71-73`) runs both commands and is what CI invokes.

### Step 6: `rpmbuild`

`rpmdev-setuptree` is deliberately not used, because `~/.rpmmacros` points
`%_topdir` at `$HOME`. The recipe is `docs/PACKAGING-RPM.md` section 3:

```sh
work=/mega/tmp/sm750/t6
topdir=$work/rpmbuild
rm -rf -- "$topdir"
mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}

tracked=$work/tracked
. ./packaging/source-excludes.sh
mapfile -t skip < <(sm750_dev_only_pathspecs)
git ls-files -z -- . "${skip[@]}" >"$tracked"
tar -C . -czf "$topdir/SOURCES/sm750hdmifb-0.6.4-source.tar.gz" \
    --transform='s|^|sm750hdmifb-0.6.4/|' --null -T "$tracked"

rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb-tools.spec
```

Expected: `RPMS/noarch/sm750hdmifb-<version>-1.fc43.noarch.rpm` and
`RPMS/x86_64/sm750hdmifb-tools-<version>-1.fc43.x86_64.rpm`, each with a matching
`.src.rpm`, exit 0. Prerequisites: `rpm-build`, `git`, `tar`, plus `gcc` and
`libdrm-devel` for the tools package. The module package is a noarch DKMS source
carrier; nothing is compiled for it at RPM build time. The tools package compiles
`tools/sm750-smi.c` and ships only `/usr/bin/sm750-smi`; the second spec exists
because rpm rejects an arch-dependent subpackage under a noarch parent
(`docs/PACKAGING-RPM.md` section 10).

Archive-content rule: the source tarball is exactly the tracked tree minus the
development-only directories declared once in `packaging/source-excludes.sh`
(`docs/plan`, `docs/evidence`, `docs/images`, `docs/notes`), the same list
`build-package.sh` and `tests/audit-release.sh` read, so `docs/` additions ship
unless they are declared there.

### Step 7: RPM/DKMS gate and sandbox

```sh
./tests/check-rpm-dkms.sh
```

Expected: exit 0 with the `OK:` assertions and nine `SKIP:` lines for the
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
| `README.md` | status and evidence summary, install (Debian `.deb`, RPM/DKMS), modes, parameters, non-error boot messages, troubleshooting, test entry points, publishing remotes |
| `docs/LOGBOOK.md` | append-only chronological record of every action and change, newest entry last |
| `docs/ROOT-ACTIONS.md` | every host root action with its exact command, the helper bodies and the GAP each closes |
| `docs/HARDWARE.md` | board identification, observed board quirks, capability comparison |
| `docs/MODES.md` | catalogue, clock and transmitter risk |
| `docs/PARAMETERS.md` | module parameters and their defaults |
| `docs/REGISTERS.md` | tracked register reference and how to read the dump |
| `docs/PROVENANCE.md` | licensing and third-party material policy |
| `docs/RELEASE-NOTES.md` | 0.6.0 changes and the kernels tested at runtime |
| `docs/STAGING-BENCHMARK.md` | DMA batch benchmark procedure and analysis rules |
| `docs/TESTING.md` | validation scope, recovery, live reload |
| `docs/VBLANK.md` | private vblank timer and its locking |
| `docs/VBIOS-REVERSE-ENGINEERING.md` | option-ROM structure map, the bit-exact 16-bit reconstruction, and the execution-trace comparison of both images, with their limits |
| `docs/DECK.md` | ten-slide presentation deck in Marp-flavoured Markdown: what the driver is, the architecture, the panel path, the test card, defects, tests, packaging, open items, verified citations |
| `docs/deck/index.html` | the same ten slides as one standalone page: hand-written reveal-style JavaScript, inline SVG architecture diagram, hash routing (`#/3`), print stylesheet, no-script fallback, zero external requests |

### 5.2 Audit, test and packaging documentation

| Path | Content |
| --- | --- |
| `docs/AUDIT.md` | repository audit, 24 defects with reproduction and evidence |
| `docs/DEFECTS.md` | one disposition per defect: fixed, accepted or deferred |
| `docs/TEST-STRATEGY.md` | suites S1-S21, recorded results, remaining gaps |
| `docs/STATIC-ANALYSIS.md` | static-analysis gate, per-tool counts, triage of every finding, tool configuration and limits |
| `docs/PACKAGING-RPM.md` | spec purpose, build recipe, install, verify, rollback |
| `docs/ENVIRONMENT.md` | host, header trees, tool matrix, privilege state |
| `docs/ci/build.yml` | inactive CI recipe: GitHub Actions is disabled, the file is kept outside `.github/workflows/` |
| `docs/DELIVERABLES.md` | this index and the reproduction guide |
| `tests/check-console-blank.sh` | T31 source-level gate: `sm750_shadow_frame_is_blank()` samples the shadow source on a coarse grid, the exact `console framebuffer is blank` line is emitted from `sm750_pipe_enable()` after `sm750_program_mode()` behind a once-per-load latch, and the guard carries no control flow; four planted defects rejected. Run by `tests/check-drm-policy.sh`, so it stays inside the default `make check` |
| `tests/check-console-scanout.sh` | T31 root-only runtime check (`make console-check`, opt-in): on a `KD_TEXT` foreground VT it writes to `/dev/tty0` and requires a non-blank `sm750_scanout` window, a `crc32` other than the all-zero sentinel `0xe20eea22` and an `offset` equal to `PANEL_FB_ADDRESS`; exits 77 with one `SKIP:` line, naming `KD_GRAPHICS` when that is the cause |
| `tests/check-restore-path.sh` | T32 source-level gate (part of `make check` through `tests/check-drm-policy.sh`): the display and mode transition waits compare through `DISPLAY_CTRL_TIMING \| DISPLAY_CTRL_PLANE` and re-poke per poll, the mode budget is `max(20 ms, 2 vertical periods)`, `sm750_pipe_disable()` keeps and reports the display-off result, and the `sm750_pipe_enable()` fail path stays terminal and dumps four registers. Rejects four planted defects; 223 lines |
| `tests/check-test-pattern.sh` | T37 source-level gate (part of `make check` through `tests/check-drm-policy.sh`): the `test_pattern` / `test_pattern_period_ms` parameters and their documented defaults, the bounded painter with its pitch-padded row copy and both pixel encodings, the card elements, the exact paint message and the call ordering in `sm750_pipe_enable()`, and the rotation's four cancel sites and per-tick silence. Rejects nine planted defects |
| `tools/sm750-crc-cycle.sh` | single root entry point for the CRC/readback check: reloads the locally built module after a vermagic guard, waits for scanout geometry, runs `tests/check-scanout-crc.sh` and prints the transcript; `--diag` adds an strace of `crc/data`, `--dump` prints the crc file set |
| `tools/sm750-restore-cycle.sh` | T32 root-only stress harness for the restore path: reloads the module after a vermagic guard, repeats the client-exit restore trigger with `build/scanout-pattern` plus an optional `modetest` mode change, and fails on any new `did not latch` / `panel did not acknowledge` / `failed to enable HDMI mode` line. Exit 0 clean, 1 environment, 2 no scanout readback, 3 failure seen; 208 lines. Not yet run on the card |
| `tests/check-sm750-smi.sh` | Fixture-driven gate for `tools/sm750-smi`: rebuilds the tool, asserts all 27 fields are listed and queryable, drives nine synthetic sysfs/DRM trees (full data, absent debugfs, non-root reason, absent driver attributes, disconnected connector, zero modes, truncated and malformed attributes, missing card node), checks `--strict` exit 0/3, parses CSV and JSON, and rejects four planted controls. No GPU and no root needed; the 18th recipe command of `make check` |
| `tools/sm750-smi.c` | the `sm750-smi` monitoring and control utility: 27 fields from sysfs, libdrm and optional debugfs, `--query`, `--format=table|csv|csv,noheader|json`, `--list-fields`, `--loop`, `--strict`, `--sysfs-root`/`--card`/`--proc-root` for fixtures, man page in `--help`; built by `make tools`, installed by `make install-tools` as `/usr/local/sbin/sm750-smi`, and shipped by the `sm750hdmifb-tools` package as `/usr/bin/sm750-smi` (`packaging/sm750hdmifb-tools.spec`, `build-package.sh`) |
| `tests/check-sysfs-attributes.sh` | T52 source-level gate (part of `make check` through `tests/check-drm-policy.sh`): the twelve monitoring attributes `sm750-smi` reads from `/sys/class/drm/cardN/device/` exist as `DEVICE_ATTR_RO()` plus array entries and are published by `sm750_attr_group` on `&pdev->dev` before `drm_dev_register()`; every show function uses `dev_get_drvdata()` behind a NULL guard and `sysfs_emit()`, sleeps nowhere and takes no lock other than the mode lock; the link-status read passes `clear_events = false`; `vblank_count` reads DRM core's counter and `crc_supported` follows the kernel range that registers `.get_crc_sources`. Rejects five planted defects |
| `tests/check-kunit-drm.sh` | T55 DRM KUnit sweep (`make check-kunit`, opt-in): discovers the DRM KUnit suites under `/lib/modules/$(uname -r)/internal/drivers/gpu/drm/tests/` with a floor of 8 so an empty directory fails, modprobes each suite (KUnit autorun, `CONFIG_KUNIT_AUTORUN_ENABLED=y`), parses the TAP results from the kernel log via `DMESG_CMD`, fails naming the suite and the failing subtest, and unloads every module in an EXIT trap. Root is required, or the per-module modprobe allowlist of `docs/ROOT-ACTIONS.md` section 3.9 via `MODPROBE_CMD='sudo -n /usr/bin/modprobe'`; with neither an unprivileged run exits 77 with one SKIP line naming the uid and the loader. On this host the loader is installed and all 21 suites load, but they print only `kunit: disabled` because `# CONFIG_KUNIT_DEFAULT_ENABLED is not set`, so the gate skips naming the runtime enable of section 3.10 rather than passing; `--self-test` runs four planted parser defects and two negative controls without root |
| `tests/check-oops-delta.sh` | T55 reusable oops detector (`make check-oops`, opt-in, and standalone `tests/check-oops-delta.sh -- <command...>`): snapshots the kernel log before and after the wrapped command through `DMESG_CMD` (default `dmesg`, this host `sudo -n dmesg`), diffs the delta, filters `--allow` regexes or `OOPS_ALLOW_FILE`, and fails on a new `BUG:`, `WARNING:`, `Oops`, GPF, NULL-deref, `lockdep`, call-trace or `RIP:` line; exits 77 when the log is unreadable; taint is deliberately not a signal (the host carries the nvidia taint); `--self-test` runs three planted defects and four negative controls |
| `tests/check-sm750-pkg.sh` | Self-tests for the sudo package helper `tools/sm750-pkg.sh`: argv and file policy, newest-pair selection, stubbed dnf/dkms/rpm through a temporary PATH, nine groups, no root |
| `tools/sm750-console.sh` | T37 console helper, installed as `/usr/local/sbin/sm750-console` (root only): `show` prints the active tty, `KDGETMODE` of `/dev/tty0` decoded as `KD_TEXT`/`KD_GRAPHICS`/`KD_KDWANTED`, the `vtconsole` bind state, `PANEL_FB_ADDRESS` and the `sm750_scanout` offset/nonzero/crc32; `text [N]` runs `chvt` (default 2) and prints the same status; `graphics` runs `chvt 1`. Usage errors exit 2 |
| `tools/sm750-headless.sh` | T56 operator helper, installed as `/usr/local/sbin/sm750-headless` (root only): refuses to run unless `0000:01:00.0` is bound to `sm750hdmidrm`, takes DRM master (`0x641E`, dropped with `0x641F`) to prove the card is free and exits 4 when another process holds it, then runs one fixed program for a bounded time and writes a verdict. Modes `probe`, `diagnose`, `weston [SECONDS]`, `cage [SECONDS]`, `kmscube [SECONDS]`; `SECONDS` is numeric, defaults to 20 and is clamped to 1..600; no free-form arguments. The compositors run with `LIBSEAT_BACKEND=noop` (libseat 0.9.3 has `logind`, `seatd` and `noop`, and `noop` opens the device directly, so seat0, logind and every VT are untouched), `cage` is invoked without `-s` because that flag permits VT switching, and `kmscube` gets `-c` (frame count) rather than `-n` (a connector id). Each run writes `01-before.txt`, `02-master.txt`, `03-compositor.log`, `04-client.log`/`.pid` (weston), `05-verdict.txt`, `06-after.txt` and a `0700` `runtime/` under `/mega/tmp/sm750/headless/`. The verdict fails when the compositor did not survive `SECONDS` or the `vblank_count` delta is `<= 0`, and states that a frame count alone never proves a compositor rendered. Exit 0 success, 1 environment, 2 usage, 3 expectation failed, 4 master held |
| `tests/check-headless-helper.sh` | T56 source-level gate for `tools/sm750-headless.sh` (part of `make check` through `tests/check-drm-policy.sh`): POSIX `sh` plus `sh -n`, the five modes and the usage path that exits 2, the `0000:01:00.0` / `sm750hdmidrm` binding test, `LIBSEAT_BACKEND=noop` exported and never `builtin`, the weston, cage and kmscube argument sets read out of the switch body with comments stripped (so `-s` on cage and `-n` on kmscube are rejected where they would be executed), the `SECONDS` numeric test and 1..600 clamp, the survivor and vblank-delta failures with `status=3`, TERM before KILL on an EXIT trap, no local absolute path and no non-ASCII byte. Static only: no compositor, no root, no card. `--self-test` runs eight planted defects plus a pristine control |
| `tests/check-render-node.sh` | T57 source-level and live gate for the render node (part of `make check` through `tests/check-drm-policy.sh:270-276`): both `driver_features` lines in `src/sm750_drm.c` carry `DRIVER_RENDER` on the same line as `DRIVER_MODESET`, no executable line sets `DRIVER_RENDER` without `DRIVER_MODESET` because a render-only device would lose card0 and every mode, `SM750_DRM_VERSION` agrees with the `readonly version=` line of `build-package.sh`, and the live half requires the `renderD*` node whose `device/driver` basename is `sm750hdmidrm` to exist as a character device writable by the invoking user, printing one `SKIP:` line when the running module predates 0.6.5. Rejects three planted controls `render_dropped`, `render_only` and `version_drift`. Adds no `make check` recipe command, so the count stays 18 |

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
| `docs/evidence/EVIDENCE-GAPS.md` | GAP-B1 .. GAP-B8 with denial and closing command |
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
| `docs/evidence/scanout/01-build.txt` | compiler versions and the three-tree build of the CRC/readback change |
| `docs/evidence/scanout/02-crc-source.txt` | `crc/source` list and enabled state for `crtc-0`, or the skip reason |
| `docs/evidence/scanout/03-readback.txt` | `sm750_scanout` dump excerpt with offset, length, nonzero count and crc32, or the skip reason |
| `docs/evidence/scanout/04-checks.txt` | PASS/FAIL/SKIP lines of `tests/check-scanout-crc.sh` |
| `docs/evidence/scanout/05-crc-debugfs-build.txt` | four-kernel build record of the T28 hosting attempt; the hosting itself was removed in T30, kept as history |
| `docs/evidence/scanout/06-crc-debugfs-runtime.txt` | SKIP record for the T28 hosted files as uid 1005; superseded by `09-crc-single-owner.txt` |
| `docs/evidence/runtime/25-test-card-animation.txt` | T38: the animated test card - the disc geometry and the per-tick cost at 1024x768 and 1920x1080, the two timing parameters with their clamps, how a tick avoids a full-frame write, the gate transcript with thirteen rejected negative controls, and an explicit `NOT YET OBSERVED ON THE PANEL` section |
| `docs/evidence/runtime/27-posttrans-install-failure.txt` | T41: the 0.6.2-1 install that installed no module - the verbatim host transcript with `Error! Could not locate dkms.conf file.` and `Error! sm750hdmifb/0.6.1 is broken!`, `cat /sys/module/sm750hdmidrm/version` still printing `0.6.1`, the diagnosis of A37 (the purge ran after the step it protects) with A38 and A39 alongside, the fix list with spec line numbers, the five-control gate transcript, and an explicit `NOT YET OBSERVED` section for the 0.6.2-2 install |
| `docs/evidence/runtime/26-test-card-crc-fix.txt` | T40: the CRC-ownership fix - why the T37 one-shot skip swallowed the client's first frame, R1 (an armed scanout CRC source cancels the card, refuses a paint and stops a racing tick) and R2 (the paint condition becomes `!master && blank`), the files touched, the eighteen-control gate transcript with the five new controls and the defect each catches, the verification exit codes, and an explicit `NOT YET OBSERVED ON THE PANEL` section with the arm/disarm runbook |
| `docs/evidence/runtime/23-test-card-fallback.txt` | T37: the test-card fallback - trigger condition, the guard set with the geometry math, the pixel encoding for both bpp, the parameter values and clamping, the gate transcript with nine rejected negative controls, the fixed A31 single-sample restructure, and an explicit `NOT YET OBSERVED ON THE PANEL` section |
| `docs/evidence/runtime/22-restore-fix-hardware-proof.txt` | T34: the on-card run of the T32 restore-path fix - module srcversion and vermagic, the six CRC-cycle PASS lines, the single T31 blank-console line, 30/30 restore cycles, 20/20 mode changes, 95 enable events across two geometries, the zero-fault census with the exact grep, the S10 console-scanout result under `KD_TEXT`, and the limitations (one card, one panel, harness form unexercised) |
| `docs/evidence/runtime/21-fbdev-restore-fix.txt` | T32: the restore-path failure chain, the two wait loops before and after with the mask rationale, the `max(20 ms, 2 vertical periods)` budget derivation, the disable/enable hook changes, the gate transcript with its four rejected controls, the root harness design, and an explicit not-yet-proven-on-hardware section naming the run that would settle it |
| `docs/evidence/runtime/19-console-blank-diagnosis.txt` | T31: the black-panel misdiagnosis, `KDGETMODE=1` on `/dev/tty0`, `crc32(262144 zeros) = 0xe20eea22`, the blank and white register/scanout states, the conclusion, and the S9/S10 transcripts |
| `docs/evidence/scanout/09-crc-single-owner.txt` | T30: core owns `crtc-N/crc/{control,data}`, the deleted driver symbols, the two defects found (positive return from `drm_vblank_work_schedule()`, lastclose console restore), the seven gate exit codes and the root run ending in `RESULT: scanout CRC check passed` |
| `docs/evidence/scanout/08-crc-stream-fix.txt` | T29: the stalled stream diagnosis (a failed region check returned before the re-arm), the fix, the gate transcript, and the runtime run that still produced no entries |
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
| `docs/evidence/builds/20-static-sparse.log` | T19: sparse 0.6.4 over `src/`, 7.3.4-100 and 6.17.1-300, exit 0 / 0 warnings after the declaration fix, plus the four pre-fix lines |
| `docs/evidence/builds/21-static-smatch.log` | T19: smatch 1.73 over both trees, exit 0, 5 and 3 driver findings, all kernel-macro false positives |
| `docs/evidence/builds/22-static-cppcheck.log` | T19: bear 3.1.6 compile database plus cppcheck 2.19.1, zero findings, with the planted-defect control |
| `docs/evidence/builds/23-static-coccinelle.log` | T19: coccinelle 1.3, 12 patches (3 local, 9 kernel), zero findings, with the planted-defect control |
| `docs/evidence/builds/24-static-pahole.log` | T19: pahole v1.32, BTF absent and every driver struct layout |
| `docs/evidence/builds/25-static-gate.log` | T19: the gate passing on the tree, failing on a planted copy, and skipping with exit 0 when the analysers are absent |
| `docs/evidence/packaging/01-rpmbuild.log` | `rpmbuild -ba`, exit 0, captured under `LC_ALL=C` and ASCII-gated (regenerated at 0.6.2; the 0.5.9 run is archived in `docs/evidence/packaging/0.5.9/`) |
| `docs/evidence/packaging/02-rpm-qp-scripts.log` | scriptlet assertions |
| `docs/evidence/packaging/03-rpm-qlp.log` | `%files` list, 36 files, captured under `LC_ALL=C` and ASCII-gated |
| `docs/evidence/packaging/04-rpm-qpR.log` | dependency assertions |
| `docs/evidence/packaging/05-dkms-sandbox.log` | sandbox DKMS `built` with a real module, captured under `LC_ALL=C` and ASCII-gated |
| `docs/evidence/runtime/28-dangling-kernel-link.txt` | T42: the three dangling `/var/lib/dkms/sm750hdmifb/kernel-<kernel>-x86_64` symlinks verbatim, the `/usr/sbin/dkms` lines that turn one into `die 6`, the transcript excerpt of the abort, the fix with spec line numbers, the six-control gate transcript, and an explicit `NOT YET OBSERVED ON THE HOST` section |
| `docs/evidence/runtime/36-render-node.txt` | T57: the render node from missing to observed - the gate assertions and its three planted controls, the earlier `NOT YET OBSERVED` section kept as history, and the 2026-11-25 observation on module 0.6.5: `/dev/dri/renderD131` as `crw-rw-rw- root:render 226:131` with its sysfs counterpart, the `DRM_IOCTL_VERSION` identity of both nodes and the shadow-driver description it returns, the kwin 6.7.5 refusal with its exact log lines and the strace showing card0 is stat-ed but never opened, the two remaining barriers (no Mesa SM750 driver, no logind seat), and the X11 route where Plasma runs with compositing off |
| `docs/evidence/packaging/06-posttrans-missing-headers.log` | missing-header branch of `%posttrans`, plus the stale-purge run whose `dkms remove` fails (exit 4) and the dangling-link run (A40) |
| `docs/evidence/packaging/07-check-rpm-dkms.log` | full `tests/check-rpm-dkms.sh` run |
| `docs/evidence/packaging/0.5.9/01-rpmbuild.log` | `rpmbuild -ba` at 0.5.9, exit 0, frozen: produced before the T45 `LC_ALL=C` capture, non-ASCII lines left unedited as the historical record |
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
| `docs/evidence/runtime/09-hdmi-minus-110.txt` | T16: isolation of the `failed to enable HDMI mode: -110` episode, 1 hit in 205 attempts |
| `docs/evidence/runtime/10-addfb-size-max.txt` | T15: root cause of the `kms_addfb_basic` `size-max` `ADDFB2` EINVAL |
| `docs/evidence/runtime/11-preconditions.txt` | T11: machine state captured before the 0.6.0 replacement |
| `docs/evidence/runtime/13-module-reload.txt` | T11: unload of the stale 0.5.9 module and load of 0.6.0 |
| `docs/evidence/runtime/14-modetest-connector-0.6.0.txt` | `modetest -c` connector enumeration on 0.6.0 |
| `docs/evidence/runtime/15-modetest-properties-0.6.0.txt` | `modetest -p` CRTC, plane and property enumeration on 0.6.0 |
| `docs/evidence/runtime/16-modeset-0.6.0.txt` | `modetest -s` modeset and restoration on 0.6.0 |
| `docs/evidence/runtime/17-a27-fix-build.txt` | T20: static gate, build and RPM rebuild after the A27 fix |
| `docs/evidence/runtime/17-kmscube-0.6.0.txt` | `kmscube` run on 0.6.0 |
| `docs/evidence/runtime/18-a27-fix-install.txt` | T20: delivery of the A27 fix to the running kernel through the allowlisted dnf pair |
| `docs/evidence/runtime/18-kernel-log-0.6.0.txt` | kernel log captured on 0.6.0, cross-checked against `journalctl -k` |
| `docs/evidence/runtime/19-a27-fix-reproduce.txt` | T20: post-fix reproduction of the `-110` episode, 108 attempts |
| `docs/evidence/runtime/21-final-state.txt` | T11: final machine state after the rollback proof and reinstall |
| `docs/evidence/runtime/22-dkms-stale-purge.txt` | T22: the `%posttrans` stale-registration purge, with the pre-fix `dkms status` and the post-purge result |
| `docs/evidence/vbios-re/01-rebuild.txt` | T17: `tools/vbios-re/reencode.py` rebuild of the captured ROM, every structural check PASS |
| `docs/evidence/vbios-re/02-bitexact.txt` | T17: rebuilt image is byte-identical to the capture, 49152 bytes each |
| `docs/evidence/vbios-re/03-decode-equality.txt` | T17: `objdump` disassembly of both images compares equal |
| `docs/evidence/vbios-re/04-toolchain.txt` | T17: why the reconstruction is 16-bit assembly, with the toolchain it was built by |
| `docs/evidence/vbios-re/05-execution-trace.txt` | T25: `make vbios-trace` - the captured image and the reconstruction executed through qemu's gdb stub and through unicorn, 2000 steps each, identical step lists and 198 identical port events |
| `docs/evidence/vbios-re/06-trace-stops.txt` | T25: the four SKIP paths, the gdb port collision, and both stop rules proved on synthetic images (far transfer, repeated-PC loop) |
| `docs/evidence/vbios-re/07-trace-divergence.txt` | T25: one flipped instruction byte makes the comparison report `DIVERGED at step 1` and exit 1 instead of claiming success |
| `docs/evidence/builds/26-audit-release.log` | T18: `build-package.sh` and `tests/audit-release.sh` after the A29 fix |
| `docs/evidence/builds/27-source-archive-manifest.log` | T18: tarball manifest after the A29 fix, with the development-only directory counts |
| `docs/evidence/builds/28-static-determinism.log` | T24: the spatch non-determinism cause, the twelve-patch matrix and the controls |

### 5.5 Images and plan

| Path | Content |
| --- | --- |
| `docs/images/desktop-2464x1080-logical.png` | logical 2464x1080 desktop, used by `README.md` |
| `docs/images/desktop-2048x1080-scanout.png` | the 2048x1080 compressed scanout |
| `docs/images/desktop-2560x1080-physical.jpg` | the panel after monitor stretch |
| `docs/plan/20261117-sm750-driver-prod/plan.yaml` | plan, acceptance criteria and task record |
| `docs/notes/sii9024a-vendor-research.md`, `docs/notes/sii9024a-i2c-research.md`, `docs/notes/sm750-windows-bsp-research.md` | tracked development-only research: the SiI9024A register and TPI behaviour behind A42, the SiI9024A I2C/DDC behaviour, and the SM750 paths of the Windows BSP. Excluded from the source archive by `packaging/source-excludes.sh`, because the notes quote vendor documents whose redistribution terms are unknown |

## 6. Source-of-truth order

When two documents disagree, the archived evidence wins, then the source, then
the prose. The resolved conflicts are listed in `docs/TEST-STRATEGY.md`
section 10. Two values that are easy to get wrong:

- The `check` target has 18 recipe commands at `Makefile:32-49`; the
  prerequisite list at `Makefile:30-31` continues on a tab-indented line that is
  not a command.
- The header matrix is 7.2.15-100, 7.3.3-100 and 7.3.4-100 plus the extracted
  6.17.1-300 tree. `7.2.13-100` no longer has a `build` link on this host.
