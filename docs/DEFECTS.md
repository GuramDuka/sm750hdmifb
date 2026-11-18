<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Defect dispositions

One row per defect inventoried in [AUDIT.md](AUDIT.md), plus two found later:
`A25`, in the kernel log of the running 0.5.9 build, and `A26`, in the IGT
`kms_addfb_basic` run. They are recorded here because this table is the current
defect state, not a copy of the audit. [AUDIT.md](AUDIT.md) still describes the
pre-fix tree and is not rewritten. Statuses:

- **fixed** - changed in this task and verified on this host.
- **deferred** - not fixed here; the reason names the blocker.
- **accepted** - deliberate behaviour; the residual risk is documented.

Evidence lives in `docs/evidence/builds/`; the numbers in the evidence column
refer to `<NN>-<slug>.log` in that directory.
`10-defect-before-after.log` shows the before (`git show HEAD:<path>`) and
after (working tree) form of every fixed item. All logs were produced unprivileged with `CC=/usr/bin/gcc` (GCC
15.3.1) against the header trees installed on this host.

| ID | Sev | Defect | Status | Change reference | Evidence |
| --- | --- | --- | --- | --- | --- |
| A01 | S1 | No RPM spec; Debian is the only packaging path | fixed | `packaging/sm750hdmifb.spec` (noarch DKMS source carrier, 36 files); rootless gate `tests/check-rpm-dkms.sh`; recipe `docs/PACKAGING-RPM.md` | `docs/evidence/packaging/01`-`07` |
| A02 | S1 | Source tarball ships untracked working-tree files | fixed | `build-package.sh:90-117` (tracked-only `git ls-files -z` manifest); `tests/audit-release.sh:36-73` (archive-rooted manifest diff) and `:75-101` (licence/path scan of what ships) | `02`, `07`, `08`, `10` |
| A03 | S2 | `make check` fails deep in the build when libdrm is missing | fixed | `Makefile:17-28` (`check-deps` preflight, prerequisite of `check` at `Makefile:30`); `README.md:41-52` | `10`, `01` |
| A04 | S2 | `tests/check-vblank` compiled but never executed | fixed | `tests/check-drm-module.sh:80-90` (live probe with explicit `SKIP` reasons) | `01`, `10` |
| A05 | S2 | No register-dump facility in the driver | fixed | `src/sm750_drm.c:3258-3352` (`regs` debugfs file), `:3363`, `:3376`; `docs/REGISTERS.md`; `README.md:290-305` | `09`, `10` |
| A06 | S2 | No 6.17 header tree, so the declared floor was never built here | fixed | extracted `kernel-devel-6.17.1-300.fc43` to `/mega/tmp/sm750/t5/k617` (scratch) and built all three formats | `06`, `10` |
| A07 | S2 | Module compiled by a different gcc than the kernel | fixed | build and CI pin `CC=/usr/bin/gcc`; documented at `README.md:53-59` | `01`-`05`, `10`, `11` |
| A08 | S2 | `postinst` calls Debian-only `update-initramfs` unconditionally under `set -e` | fixed | `packaging/drm-postinst:12-20,83` (`refresh_initramfs` with dracut fallback), `packaging/drm-postrm:5-13`; `build-package.sh:69` (`Recommends: initramfs-tools \| dracut`) | `10`, `08` |
| A09 | S2 | `postinst`/`prerm` hardcode 0.5.9 with no check | fixed | `packaging/drm-postinst:8`, `packaging/drm-prerm:7` (`version=@VERSION@`), `build-package.sh:56-59` (substitution), `tests/check-release-version.sh:15-24` | `10`, `01`, `08` |
| A10 | S2 | Two different Xorg snippets named `20-sm750hdmidrm.conf` | fixed | generated file renamed to `20-sm750hdmidrm-device.conf` (`packaging/drm-postinst:38`, `packaging/drm-prerm:19`); shipped asset name unchanged for the T6 file list | `10`, `01` |
| A11 | S3 | No tracked hardware specification or register reference | fixed (register reference); datasheet not redistributable | `docs/REGISTERS.md` (49-register table + dump instructions); `src/sm750_drm.c:3258-3309` | `10`, `09` |
| A12 | S3 | No independent KMS conformance tool available | deferred | needs `/dev/dri` access this host does not grant; `modetest` is installed but denied, and `kmscube`/IGT extract but cannot open the node either | `09`, `10` |
| A13 | S3 | Install dependencies omit `ripgrep` | fixed | `README.md:34` (Ubuntu line), `README.md:41-52` (dependency paragraph and Fedora line) | `10`, `01` |
| A14 | S3 | `.deb` has no `DEBIAN/md5sums` | fixed | `build-package.sh:82-88`; verified by `tests/audit-release.sh:103-107` | `07`, `08`, `10` |
| A15 | S3 | Module cannot report its package version | fixed | `src/sm750_drm.c:70` (`SM750_DRM_VERSION`), `:3866` (`MODULE_VERSION`); `tests/check-drm-module.sh:14-17` | `09`, `10` |
| A16 | S3 | Stale-version release gate only covered 0.5.0-0.5.5 | fixed | `tests/audit-release.sh:22-31` (current version derived from `build-package.sh`) | `08`, `10` |
| A17 | S3 | Documentation claimed all parameters are load-time only | fixed | `docs/PARAMETERS.md:4-11` | `10` |
| A18 | S3 | CI only ran on `workflow_dispatch` | fixed | `.github/workflows/build.yml:4-7` (`push`, `pull_request`) | `10` |
| A19 | S3 | `make check` never built or audited a package | fixed | `Makefile:71-74` (`check-package`); CI step at `.github/workflows/build.yml:48` | `07`, `08`, `10` |
| A20 | S3 | DKMS auto-installs on kernels the release notes call untested | accepted | rationale at `docs/RELEASE-NOTES.md:14-19`; no change to `dkms.conf:7-8` | `10` |
| A21 | S3 | No committed evidence for the claimed kernel matrix | fixed | `docs/evidence/builds/01`-`11` (this task's logs; T4 cites them) | `02`-`06`, `11` |
| A22 | S4 | Source tarball carried about 9 MB of screenshots | fixed | same fix as A02; `docs/images` excluded from the manifest (`build-package.sh:98`) | `07`, `10` |
| A23 | S4 | Planning note said 18 `make check` commands; it runs 17 | fixed | `docs/plan/20261117-sm750-driver-prod/plan.yaml:28` (corrected), count re-verified in `01-make-check.log` | `01`, `10` |
| A24 | S4 | fbdev compiled in but never appears and was not documented | accepted | behaviour and conditions documented at `README.md:307-313` | `10` |
| A25 | S3 | Found post-audit in the kernel log, not by the audit: `[PLANE:40:sm750-cursor] pixel format with alpha exposed but blend mode not setup. Please fix.` The cursor plane exposed `DRM_FORMAT_ARGB8888` with no blend-mode property, so the DRM core could not tell how the driver expresses alpha | fixed | `src/sm750_drm.c:3491` (`drm_plane_create_blend_mode_property()` offering `BIT(DRM_MODE_BLEND_PREMULTI)`); format list unchanged at `src/sm750_drm.c:3424`; gate `tests/check-hardware-cursor.sh:32-33` plus the negative assertion at `:43-45` | `docs/evidence/runtime/cursor-alpha-01-warning-before.txt`, `docs/evidence/builds/19-cursor-alpha-fix.log` |
| A26 | S4 | IGT `kms_addfb_basic --run-subtest size-max` fails with `DRM_IOCTL_MODE_ADDFB2` EINVAL. Not a driver defect and not a hardware limit: the subtest issues a `1024x2048` `DRM_FORMAT_RGB565` framebuffer at `tests/kms_addfb_basic.c:594` without a format probe, and the driver exposes only `DRM_FORMAT_XRGB8888` on the primary plane (`src/sm750_drm.c:3423`) with `max_height` declared as 1152 (`src/sm750_drm.c:95`, `:3437`). DRM core rejects it first on height (2048 > 1152) and would reject it again on format. The silicon allows it: DS-1 rev 1.4 p151 `PANEL_FB_WIDTH` permits 16368 bytes of pitch and p153 `PANEL_PLANE_BR` permits a 2048-line window, so the limit is driver policy, not hardware | accepted | no code change recommended; both rejections are generic DRM checks on declared limits, and raising `max_height` alone cannot make the subtest pass because the format gate rejects RGB565 independently. Contract and IGT gap documented in `docs/evidence/runtime/10-addfb-size-max.txt` section 5 | `docs/evidence/runtime/06-igt.txt:52,68-76,150,161`, `docs/evidence/runtime/10-addfb-size-max.txt` |

## Deferred and accepted items in detail

### A01 - no RPM spec (closed in T6)
`packaging/sm750hdmifb.spec` is a noarch DKMS source carrier (`Version 0.6.0`,
`BuildArch noarch`) that ships the same 36 files as the `.deb` and replaces the
dpkg maintainer scripts with `%post` (`dkms add`, first install only),
`%posttrans` (`dkms build`, `dkms install --force`, `depmod -a`) and `%preun`
(`dkms remove --all`), with no `%postun`. `rpmbuild -ba` exits 0 from a fresh
`_topdir`; `tests/check-rpm-dkms.sh` re-verifies it rootlessly and exits 0.
The root-only transaction test remains `GAP-B7` in
`docs/evidence/EVIDENCE-GAPS.md`; the build recipe is
`docs/PACKAGING-RPM.md`.

### A12 - no independent KMS conformance tool (deferred)
`igt_info` and `kmscube` are not installed and cannot be installed without
root. `modetest` is present but prints `no device found` without `video` group
membership, and `/dev/dri/card0` is `root:video 0660` with the ACL granted to
another user. The conformance gap is recorded with its exact blocked command in
`docs/evidence/builds/09-register-dump.log`; it cannot be turned into a pass
from this host.

### A20 - DKMS AUTOINSTALL (accepted)
`AUTOINSTALL="yes"` is what makes a kernel update rebuild the module at all.
Removing it would silently drop the display driver on the next kernel upgrade,
and narrowing `BUILD_EXCLUSIVE_KERNEL` to the tested range would contradict the
project's declared 6.17+ support. The residual risk - an untested kernel above
the last verified version is attempted - is now stated in
`docs/RELEASE-NOTES.md:14-19`. The offline matrix in this task's evidence
reduces the risk for 6.17.1 through 7.3.4.

### A24 - fbdev (accepted)
`drm_client_setup()` and `DRM_FBDEV_TTM_DRIVER_OPS` are intentional. A
`/dev/fb0` node only appears when the kernel provides fbdev emulation and no
other framebuffer driver owns the device, so its absence on this host is
environmental rather than a driver defect. The conditions are documented in
`README.md:307-313`.

### A11 - datasheet (partially deferred by licensing)
The vendor SM750 datasheet cannot be redistributed in this repository.
`docs/REGISTERS.md` now tracks the register map the driver actually uses, which
is what the defect asked for at the level a GPL repository can carry.

### A25 - cursor plane exposes alpha without a blend mode (fixed; found post-audit)

The kernel log of the running pre-fix 0.5.9 module carries, on every probe:

```
sm750hdmidrm 0000:01:00.0: [drm] [PLANE:40:sm750-cursor] pixel format with alpha exposed but blend mode not setup. Please fix.
```

It is emitted by `validate_blend_mode_for_alpha_formats()` in the DRM core,
called from `drm_mode_config_validate()` during `drm_dev_register()`. The
function returns immediately when `plane->blend_mode_property` is set; otherwise
it walks the plane's format list and warns for the first format whose
`drm_format_info()` reports `has_alpha`. The driver's cursor plane advertised
`DRM_FORMAT_ARGB8888` at `src/sm750_drm.c:3424` and created no property, so the
warning was accurate.

**Route chosen: keep `ARGB8888` and create the blend-mode property**, not switch
to `XRGB8888`. The hardware does consume per-pixel alpha: `sm750_cursor_encode()`
uses alpha as a dithered transparent/opaque mask over three palette entries, and
`sm750_cursor_unpremultiply()` (`src/sm750_drm.c:2618`) divides the colour by
alpha before quantising, which means the input contract is premultiplied ARGB.
Exposing `XRGB8888` would deny the alpha the driver actually implements and
would hide it from compositors, which hand a cursor plane `ARGB8888` by
convention. The property is created at `src/sm750_drm.c:3491`:

```c
ret = drm_plane_create_blend_mode_property(&sdev->cursor_plane,
		BIT(DRM_MODE_BLEND_PREMULTI));
if (ret)
	return ret;
```

Only `PREMULTI` is offered. `COVERAGE` would state that the driver premultiplies
colour it receives unpremultiplied, which is the opposite of what
`sm750_cursor_unpremultiply()` does, so advertising it would be a second
mismatch. `PREMULTI` is also the one mode every supported kernel accepts: 6.17
rejects a mask without it (`WARN_ON` in `drivers/gpu/drm/drm_blend.c`), and 7.2
and 7.3 accept it, so the call needs no `LINUX_VERSION_CODE` guard. No plane
alpha property is created - `drm_plane_create_alpha_property()` is deliberately
absent - because the hardware has no plane-wide alpha and the core check does not
require one.

Nothing else changed: the format list (`src/sm750_drm.c:3424`), the palette
conversion and the enable message `64x64 hardware cursor plane enabled with ARGB
palette conversion` (`src/sm750_drm.c:3807`) are untouched, and the
`hardware_cursor` default stays on.

The before capture is `docs/evidence/runtime/cursor-alpha-01-warning-before.txt`
(kernel log plus the pre-fix `modetest` property surface, which shows plane 40
with `type` and `IN_FORMATS` only). The after side is
`docs/evidence/builds/19-cursor-alpha-fix.log`: the gate passes, the built
object calls the property helper with mask 1, and all four kernel builds carry
it. The live log can only be re-read after a fixed module is installed, which is
not this task; T11 installs the rebuilt 0.6.0 and owns that capture.

### A26 - IGT size-max asks for a format and a height the driver does not expose (accepted)

`kms_addfb_basic --run-subtest size-max` is the only genuine driver-behaviour
failure in the IGT baseline (`docs/evidence/runtime/06-igt.txt:52,150,161`):
`DRM_IOCTL_MODE_ADDFB2` returns EINVAL at `tests/kms_addfb_basic.c:594`.

The subtest builds three framebuffers on one 4 MiB XRGB8888 object
(`tests/kms_addfb_basic.c:577-578`): `f` = 1024x1024 XRGB8888 pitch 4096,
`f_16` = 1024x2048 RGB565 pitch 2048, `f_8` = 2048x2048 C8 pitch 2048. The
first addfb succeeds; the second, at `:594`, is the one that fails. Only the C8
step is gated on `igt_display_has_format_mod()` (`:597`), so the RGB565 request
is issued unconditionally even though the driver never advertises that format.

Two generic DRM checks reject the request, and neither is driver-local code:

- height: `drm_internal_framebuffer_create()` compares `r->height` against the
  driver's declared `max_height` and returns `-EINVAL` with
  `"bad framebuffer height %d, should be >= %d && <= %d\n"`. 2048 > 1152.
- format: `drm_gem_fb_init_with_funcs()` rejects a format no plane advertises
  (`drm_any_plane_has_format()`) because the driver sets `DRIVER_ATOMIC`; the
  message is `"Unsupported pixel format %p4cc / modifier 0x%llx\n"`. RGB565 is
  not in `src/sm750_drm.c:3423`.

The GEM `min_size` gate does not fire: the fixture object is exactly the
4194304 bytes the request needs.

The datasheet is not the constraint. DS-1 rev 1.4 p151 `PANEL_FB_WIDTH` allows
16368 bytes per line, p152 `PANEL_WINDOW_HEIGHT` allows 4095 lines and p153
`PANEL_PLANE_BR` allows a 2048-line window, with 64 MiB of VRAM available
(datasheet identity at `docs/specs/INDEX.md:29`). A 1024x2048 framebuffer at
2048-byte pitch is inside all of them, so this is
driver policy: `max_height` is the tallest catalogue mode (`docs/MODES.md:76-86`)
and RGB565 is the internal scanout conversion, not a KMS format
(`docs/MODES.md:91-96`, `docs/PARAMETERS.md:19`).

No code change is recommended. Raising `max_height` would not make the subtest
pass, because the format gate rejects RGB565 on its own; adding RGB565 to the
primary plane would require 16-bit source rows in a pipeline whose converters all
assume u32 XRGB8888 rows (`src/sm750_drm.c:1991-2015`), contradicting the
documented contract. The full probe matrix, the datasheet page quotes and the
re-test notes for 0.6.0 are in `docs/evidence/runtime/10-addfb-size-max.txt`.

## Evidence handling

`docs/plan/` and `docs/evidence/` are development-only and stay untracked.
`tests/audit-release.sh` fails if either appears in the source archive, and the
logs in `docs/evidence/` contain absolute host paths that the release scan
rejects by design. The release documents added here (`docs/DEFECTS.md`,
`docs/REGISTERS.md`, `README.md`, `docs/PARAMETERS.md`,
`docs/RELEASE-NOTES.md`) were verified to pass `build-package.sh` plus
`tests/audit-release.sh` while tracked.

## Out of scope diagnostics

No warning or error originates in `src/*.c` or `src/*.h` in any archived build
log; the scan and the exact residual kernel/tooling messages are recorded in
`docs/evidence/builds/11-warnings-scan.log`:

- `warning: pahole version differs from the one used to build the kernel` -
  emitted by `/usr/src/kernels/*/Makefile` because pahole is not installed
  (`You are using: 0`); BTF generation is skipped as a result.
- `warning: the compiler differs from the one used to build the kernel`
  (6.17.1-300.fc43 only) - the archived Fedora kernel was built by gcc 15.2.1
  and this host has 15.3.1; not fixable without the upstream compiler.
- `Skipping BTF generation for sm750hdmidrm.ko due to unavailability of
  vmlinux` - informational; the kernel tree ships no vmlinux.
