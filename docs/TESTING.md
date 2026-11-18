<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Testing and recovery

## Offline checks

`make check` builds the module for the running kernel and runs metadata, mode,
dither, softscale, sharpening, cursor, DMA, changed-region, Xorg and packaging
checks. DRM documentation calls a reported changed screen region "damage";
this means pixels needing refresh, not corruption or physical damage.
It does not install or load the resulting module.

`make check-all-kernels` repeats module builds for all supported installed
kernel-header trees and all three scanout defaults. The dithered RGB565 build
runs the full regression suite on each kernel; the other two defaults receive
module metadata and compiler-flag checks.

To include downloaded headers without installing a kernel, unpack both the
common and generic header packages into the same directory, then pass the
generic build directories explicitly:

```sh
CC=/path/to/gcc-15 JOBS=12 ./tests/build-all-kernels.sh \
    /path/to/unpacked/usr/src/linux-headers-VERSION-generic \
    /lib/modules/$(uname -r)/build
```

Use a compiler supported by the target headers. Run builds and packaging in an
isolated copy outside any source-only synced checkout; the scripts write build
outputs into that copy. Run `make KDIR=/path/to/headers check` there for the full
regression suite. No command above installs or loads the resulting module.

`./build-package.sh` creates the DKMS package and source archive. Run
`tests/audit-release.sh` afterward to produce the final audit report.

### Offline build validation

Two matrices exist and mean different things.

**Distribution headers, 2026-11-17/18 (current).** The release host is Fedora 43
with exactly three kernels that have matching `kernel-devel`:

| Kernel headers | Built | Installed by DKMS | Booted with the module |
|---|---|---|---|
| 6.17.1-300 (koji, floor) | yes | no | no |
| 7.2.15-100.fc43 | yes | yes | no |
| 7.3.3-100.fc43 | yes | yes | no |
| 7.3.4-100.fc43 | yes | yes | **yes** |

The floor is enforced by `BUILD_EXCLUSIVE_KERNEL` in `dkms.conf`; 6.17.1-300 is
the oldest tree the source compiles against. The per-kernel logs are in
`docs/evidence/builds/`. `/lib/modules/6.18.13-200.fc43.x86_64` also exists on
that host but is a leftover NVIDIA directory owned by no package, with no
`build` link; it is not a kernel and DKMS skips it with
`matching kernel headers are absent`.

**Generic upstream headers, 2026-10-28 (historical).** Before packaging existed
the matrix was run against distribution-installed and mainline header trees
(Ubuntu 6.17.0-42 and 7.0.0-38/42, mainline 6.18.0, 7.1.0, 7.2.0,
7.3.0-070300rc3 and the 7.3.0-070300daily20261028 snapshot that carried the
merged 7.4 DRM changes). Those results are offline compilation and regression
checks only and are kept as history; they are not evidence about the current
release host.

**What is runtime-validated.** Only 7.3.4-100: modeset, the IGT `kms_*` subset,
the vblank timer test, the hardware cursor plane and the in-kernel console. The
other two Fedora kernels were built and installed but never booted. No kernel
above 7.3.4-100 has been built or booted; repeat this matrix when 7.4-rc1 and
final 7.4 headers become available. None of this establishes suspend, resume or
hotplug behaviour - that still needs the hardware verification below.

## Hardware verification

After a deliberate package installation and reboot, verify:

```sh
lspci -nnk -d 126f:0750
modinfo sm750hdmidrm
xrandr --current
journalctl -b -k | grep -i sm750
```

Check login, logout, mode changes, cursor movement, window movement, partial
clock-widget updates, suspend/resume and a cold boot. Test full-screen updates
in both RGB565 dither and XRGB8888 before calling a build validated.

## Recovery

Keep remote access or another display adapter. Remove experimental kernel
arguments and run `sudo update-grub` if a mode is unstable. To remove the
package from a remote shell:

```sh
sudo apt remove sm750hdmifb
sudo update-initramfs -u
sudo reboot
```

Removal restores only predecessor files previously renamed by this package.
No timer, rollback service or display-manager restart service is installed.
