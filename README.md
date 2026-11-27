<!-- SPDX-License-Identifier: GPL-2.0-only -->
# SM750 HDMI DRM Driver

**Push this card to real 2048-wide output or a software-scaled 2560x1080
ultrawide desktop, with bandwidth-saving colour conversion and update
optimisations for smoother performance.**

Linux display driver for the single-HDMI `SE-DP750A-HDMI` PCIe card. Current
release **0.6.9**: atomic KMS, dithered 16-bit scanout, hardware cursor, DMA and
polling upload paths, sysfs monitoring attributes, a test-card fallback so a
panel with no client is never dead-black, DKMS packages for `.deb` and `.rpm`,
and an acceptance audit of 6 PASS / 0 FAIL / 1 GAP run against the 0.6.0 tree
and re-verified since. The devices-level sleep cycle was measured and passed on
2026-11-27 (`docs/evidence/runtime/49-pmtest-devices-cycle.txt`).

> **Scope and risk:** this out-of-tree driver supports one specific SM750
> board. Optional non-EDID modes can exceed published GPU or monitor clock
> limits and may produce no signal, distortion, or an unstable display. Keep
> SSH or another recovery route available when trying them.

## Overview

A full production pass over an out-of-tree Linux DRM/KMS driver for one
specific card: the hardware was identified, the device documentation was found,
read and archived, the option ROM was reconstructed from the image, the driver
was brought to feature-complete state, every check was written down and turned
into a gate, and the result was packaged for DKMS on RPM and Debian.

`release 0.6.9` `kernel 6.17 and newer` `x86_64` `GPL-2.0-only` `DKMS`
`no firmware blobs` `no closed libraries`

The signal path this driver owns ends at the transmitter:

```
  framebuffer           SM750 scanout          SiI9024A           monitor
+---------------+    +------------------+    +-----------+    +-----------+
| 16-bit dithered|--->| DMA1 or polling |--->| TMDS      |--->| HDMI panel|
| or 32-bit frame|    | upload, cursor   |    | encoder   |    | (EDID)    |
+---------------+    +------------------+    +-----------+    +-----------+
```

Unicode icons and remote badge images are deliberately absent: this repository
is ASCII only and every asset it references lives in the tree, so the whole
document renders the same on a forge, in a terminal mail client and in a
packaged tarball.

### Where to start

| I want to | Go to |
| --- | --- |
| check whether my card is supported | [Is my card supported?](#is-my-card-supported) |
| install it | [Install](#install) |
| see it running | [Screenshots](#screenshots) and the [presentation deck](#presentation-deck) |
| read what the driver can do | [Status](#status), [Normal use](#normal-use), [Module parameters](docs/PARAMETERS.md) |
| reproduce or dispute a claim | [Acceptance report](docs/ACCEPTANCE-REPORT.md), [test strategy](docs/TEST-STRATEGY.md), [deliverables](docs/DELIVERABLES.md) |
| see the full work log | [Project logbook](docs/LOGBOOK.md) |

### What was delivered

| Area | Result | Recorded in |
| --- | --- | --- |
| Device identification | Silicon Motion `SM750G10-AC` rev A1, PCI `126f:0750`, `SiI9024ACNU` HDMI transmitter, 16 MiB display memory, one HDMI output; EDID, DDC, HPD and receive-sense behaviour measured on the panel | [hardware](docs/HARDWARE.md) |
| Specification archive | SM750 datasheet v1.4 and the product brief stored with SHA-256 hashes, an index, a register map and a gap list; every MMIO register the source touches is cross-referenced to a page | [specification archive](docs/specs/INDEX.md), [registers](docs/REGISTERS.md) |
| Option ROM | 49152-byte VBIOS captured, mapped into 239 regions and rebuilt byte for byte; the reconstruction is executed and compared instruction by instruction against the original | [VBIOS reconstruction](docs/VBIOS-REVERSE-ENGINEERING.md) |
| Scanout | atomic KMS, 16-bit `rgb565` scanout with ordered dithering, software scaling for ultrawide modes, double-buffered staging with an asynchronous upload worker, hardware cursor, CRTC CRC source and a debugfs scanout window | [modes](docs/MODES.md), [staging benchmark](docs/STAGING-BENCHMARK.md) |
| Panel safety | a test card with a bouncing-disc animation paints whenever no client has produced a frame, rotates its colours against burn-in, and yields the scanout the moment a real client commits | [parameters](docs/PARAMETERS.md) |
| Observability | twelve sysfs monitoring attributes and one root-only `pm_probe` diagnostic beside the DRM device node, and `sm750-smi`, a 27-field reporting tool for mode, link, HPD, receive sense, memory, CRC and process state | [sm750-smi](#gates-and-test-scripts), [parameters](docs/PARAMETERS.md) |
| Robustness | bridge readiness polled with a bounded budget, I2C transaction timeouts survived and retried with a bus recovery, restore path reworked so a failed commit cannot blank the panel, stale DKMS registrations purged on upgrade | [defect inventory](docs/DEFECTS.md) |
| Test suites | the vendor-neutral suites located, piloted and recorded: IGT KMS subset, `modetest`, `kmscube`, nine-combination build matrix, plus 30 project gates of which 18 run in the default `make check` | [test strategy and results](docs/TEST-STRATEGY.md) |
| Packaging | one DKMS source tree with a noarch module package and an arch-dependent tools package, RPM and Debian, changelogs, dependency checks, sandbox build and a stale-version upgrade path | [RPM packaging](docs/PACKAGING-RPM.md) |
| Audit | every finding tracked with an id, a disposition and evidence; acceptance verdict recorded criterion by criterion | [repository audit](docs/AUDIT.md), [defects](docs/DEFECTS.md), [acceptance](docs/ACCEPTANCE-REPORT.md) |

### At a glance

| Measure | Value |
| --- | --- |
| Driver source | 11252 lines of C and headers under `src/` |
| Defect findings tracked | 66, from A01 to A67, each with a disposition |
| Acceptance criteria | 6 PASS, 0 FAIL, 1 GAP - the gap is pixel-level capture at the panel, which needs a human or capture hardware |
| Project gates | 34 gate scripts, 18 commands in `make check`, seven opt-in verification targets with planted-defect controls |
| Kernel and format matrix | 9 combinations, kernel 6.17.1 through the 7.4 daily headers |
| IGT KMS subset | 26 pass, 14 skip, 1 fail by design |
| GL path | `kmscube`, 299 frames in 5.07 s, 59.01 fps on llvmpipe |
| Vblank rate | 60.43 per second measured over 120 events |
| Evidence | 57 runtime transcripts, 28 build transcripts and 7 packaging transcripts under `docs/evidence/` |
| Documentation | 22 documents under `docs/`, plus the specification archive and the deck |

### How a claim is checked

Three habits run through the whole repository, and they are what the gates
enforce:

- **Evidence or it is a gap.** A statement in prose that no transcript under
  `docs/evidence/` supports is filed as an open gap, not as a result.
- **A gate, not a promise.** Each fixed defect gets a check with planted
  defects: the gate is re-run against a deliberately broken copy and must fail
  by name, so a check that silently stops detecting anything is itself caught.
- **No weakened checks.** A check changes only together with a stated reason
  and an evidence path; the release audit refuses a tarball that drifts from
  the tracked tree, a transcript that carries a local path, or a version that
  disagrees between `dkms.conf`, the specs and the build script.

### Documentation map

| Document | Contents |
| --- | --- |
| [Acceptance report](docs/ACCEPTANCE-REPORT.md) | Criterion-by-criterion verdict with the command and the evidence path behind each row |
| [Test strategy](docs/TEST-STRATEGY.md) | Every suite, its selection rationale, pass criteria and recorded results |
| [Plasma on this driver](docs/PLASMA-WAYLAND.md) | The measured Wayland session, its two working bypasses, the scanout proof, the buffer-modifier freeze and its two remedies, and what is still missing |
| [Plasma over X11](docs/PLASMA-X11.md) | The second front: why the X server needs root here, the generated config, the `/etc/environment` NVIDIA selection that crash-loops `kwin_x11`, the session launcher that clears it, and the observed `card0` session with its scanline and capture evidence |
| [Defects](docs/DEFECTS.md) | Findings with ids, root causes, dispositions and the gate that guards each fix |
| [Repository audit](docs/AUDIT.md) | Point-in-time audit of the tree, with dated path notes where the tree moved on |
| [Deliverables](docs/DELIVERABLES.md) | What ships, how it is rebuilt, and the exact reproduction commands |
| [Hardware](docs/HARDWARE.md) | Board identification, empirical quirks, and workarounds that must not be removed on the strength of the datasheet alone |
| [Specifications](docs/specs/INDEX.md) | Archived vendor documents, hashes, register map and the documented-but-unused register list |
| [Registers](docs/REGISTERS.md), [modes](docs/MODES.md) | MMIO reference and the mode, clock and bandwidth limits with their risks |
| [Parameters](docs/PARAMETERS.md) | Every module parameter, its default, its range and its live behaviour |
| [Packaging](docs/PACKAGING-RPM.md) | RPM and DKMS layout, scriptlets, upgrade and purge behaviour |
| [Build environment](docs/ENVIRONMENT.md) | Host, toolchain, kernels, privileges and the reason behind each workaround |
| [Root actions](docs/ROOT-ACTIONS.md) | The exact privileged commands, the helpers they install and the recovery routes |
| [Logbook](docs/LOGBOOK.md) | The chronological record: what happened, when, by whom, with the evidence path |
| [Plan of record](docs/plan/20261117-sm750-driver-prod/plan.yaml) | Task scope, acceptance criteria and every decision with its rationale |
| [Presentation deck](docs/DECK.md) | Ten slides on the architecture and the open items |

> **Scope and risk:** this out-of-tree driver supports one specific SM750
> board. Optional non-EDID modes can exceed published GPU or monitor clock
> limits and may produce no signal, distortion, or an unstable display. Keep
> SSH or another recovery route available when trying them.

## Is my card supported?

The tested board is sold or marked as `SE-DP750A-HDMI` and has all of these:

- Silicon Motion `SM750G10-AC`, revision A1
- PCI ID `126f:0750`
- Silicon Image/Lattice `SiI9024ACNU` HDMI transmitter
- 16 MiB display memory
- One HDMI output

The PCI ID alone is not enough. Other SM750 cards may use VGA, a different
transmitter, or different GPIO wiring and are not currently supported.

## Status

Release 0.6.9. The driver is feature-complete for this board and meets the
project's production criteria except for one item that needs a person at the
panel; see the [acceptance report](docs/ACCEPTANCE-REPORT.md).

| Area | Verified state |
|---|---|
| Module | `sm750hdmidrm` 0.6.9, built by DKMS from one source tree |
| Runtime | 0.6.9 loaded and exercised on kernel 7.3.5-100 (Fedora 43); DKMS built and installed it from this tree for 7.2.15-100, 7.3.3-100, 7.3.4-100 and 7.3.5-100; the version-free `sm750-pkg` helper performs install and rollback (`docs/ROOT-ACTIONS.md` 3.8) |
| Sleep path | devices-level `pm_test` cycle PASS 2026-11-27: all four `pm:` edges once, `suspend_stats` unchanged, panel back at 1024x768 and 75 Hz, CRC `0xa76f0aeb` (`docs/evidence/runtime/49-pmtest-devices-cycle.txt`); a `pm_probe` pass is not a system sleep |
| Test card | seen on the panel; the disc animates and the scanout CRC gate stays green while it runs (`docs/evidence/runtime/26-test-card-crc-fix.txt`) |
| Build matrix | 9 kernel and scanout-format combinations, 6.17.1 through the 7.4 daily headers |
| Modeset | atomic commit verified with `modetest`, 1920x1080 at 60 Hz |
| Vblank | 60.43 vblanks/s measured over 120 events |
| IGT subset | 26 pass, 14 skip, 1 fail by design (see the limitation list below) |
| GL path | `kmscube` 299 frames in 5.07 s, 59.01 fps on llvmpipe |
| Packaging | RPM payload, scriptlets, DKMS sandbox build, install, erase, reinstall and stale-version purge |
| Specifications | datasheet and product brief archived with hashes; every MMIO register the source uses is cross-referenced |
| Static analysis | sparse clean (four findings fixed); smatch, cppcheck, coccinelle and pahole triaged |

Acceptance verdict: **6 PASS, 0 FAIL, 1 GAP**. The gap is AC-3, pixel-level
proof at the panel, which needs a human looking at the monitor or capture
hardware, neither of which exists on the reference host. Everything up to the
panel is evidenced.

Known limitations, each with an id in [docs/DEFECTS.md](docs/DEFECTS.md):

- A failed modeset no longer becomes a kernel WARNING plus stalled commits, but
  the underlying `-110` bridge timeout is survived rather than prevented
  (GAP-B8 in `docs/evidence/EVIDENCE-GAPS.md`).
- `kms_addfb_basic size-max` fails by design: the driver declares its real
  limits - maximum height 1152, plus the pitch and window limits - instead of
  accepting a framebuffer the hardware cannot scan out (A26).
- There is no pixel-level readback path on this host: no `/dev/fb*` because
  `CONFIG_FB_DEVICE` is unset (A24), no writeback connector, and no external
  capture. The driver does expose a CRTC CRC source and an `sm750_scanout`
  debugfs dump, but the CRC source is computed over the scanout source bytes in
  VRAM. It proves the buffer the display engine is fed, not the pixels it
  emits; AC-3 tier 5 remains partial for that reason.
- `smatch` reports one shift-versus-mask precedence warning that originates in
  `GENMASK_TYPE()` in the kernel headers, not in this driver (A28).
- A KWin Wayland session on a module older than 0.6.7 can start compositing and
  then freeze the scanout: kwin asks for a buffer modifier the plane never
  advertised and the kernel rejects every framebuffer with errno 22
  (`kwin_wayland_drm: Failed to create framebuffer`). Exporting
  `KWIN_DRM_USE_MODIFIERS=0` works around it; 0.6.7 removes the need by
  reporting `DRM_CAP_ADDFB2_MODIFIERS` as 0. Details, probe results and the
  three checks that tell which case you are in are in
  [Plasma on this driver](docs/PLASMA-WAYLAND.md) sections 4.4 to 4.6.

## Install

### Debian and Ubuntu

Ubuntu 24.04 and Linux Mint 22 users can build a DKMS package locally:

```sh
sudo apt update
sudo apt install build-essential dkms linux-headers-$(uname -r) libdrm-dev ripgrep git
git clone https://github.com/GuramDuka/sm750hdmifb.git
cd sm750hdmifb
make check
./build-package.sh
sudo apt install ./dist/sm750hdmifb_0.6.9_all.deb ./dist/sm750hdmifb-tools_0.6.9_*.deb
sudo reboot
```

The second package is the arch-dependent `sm750hdmifb-tools`; it installs
`/usr/bin/sm750-smi`, which then runs unprivileged. If the libdrm development
files are absent, `build-package.sh` prints a skip message and still builds the
module package and the source archive - a release is never half built
(`./build-package.sh --help`).

`make check` needs `pkg-config`, the libdrm development headers (`libdrm-dev`
on Debian and Ubuntu, `libdrm-devel` on Fedora) and `rg` from ripgrep. The
`check-deps` preflight target stops with an install hint when one is missing.

### Fedora and other RPM distributions

`packaging/sm750hdmifb.spec` builds the same DKMS package as a `noarch` RPM, so
the installed module file set matches the `.deb` and DKMS compiles the module
against each installed kernel. The utility is a second, arch-dependent RPM from
`packaging/sm750hdmifb-tools.spec`, because rpm cannot attach an arch subpackage
to a noarch parent (`docs/PACKAGING-RPM.md` section 10):

```sh
sudo dnf install rpm-build gcc make dkms kernel-devel libdrm-devel pkgconf-pkg-config ripgrep git tar
git clone https://github.com/GuramDuka/sm750hdmifb.git
cd sm750hdmifb

work=$(mktemp -d) && topdir=$work/rpmbuild
mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}
. ./packaging/source-excludes.sh
mapfile -t skip < <(sm750_dev_only_pathspecs)
git ls-files -z -- . "${skip[@]}" >"$work/tracked"
tar -C . -czf "$topdir/SOURCES/sm750hdmifb-0.6.9-source.tar.gz" \
    --transform='s|^|sm750hdmifb-0.6.9/|' --null -T "$work/tracked"

rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb-tools.spec
sudo dnf install -y "$topdir"/RPMS/noarch/sm750hdmifb-0.6.9-1.fc43.noarch.rpm \
    "$topdir"/RPMS/x86_64/sm750hdmifb-tools-0.6.9-1.fc43.x86_64.rpm
sm750-smi
sudo reboot
```

With the packages in a repository, the same two install in one step:

```sh
sudo dnf install sm750hdmifb sm750hdmifb-tools
sm750-smi
```

The RPM build needs no root; only `dnf install` and the reboot do. The package
carries no compiled module: DKMS builds `src/` for every installed kernel that
satisfies `BUILD_EXCLUSIVE_KERNEL` in `dkms.conf` (6.17 and newer, the same
floor as the `.deb`). Runtime validation covers the 7.2 and 7.3 kernels listed
under [Kernel compatibility](#kernel-compatibility).

`./tests/check-rpm-dkms.sh` re-verifies the package without root - fresh
`rpmbuild`, payload against `git ls-files`, scriptlets, dependencies and a
sandbox DKMS build - and exits non-zero on regression. See
[RPM packaging](docs/PACKAGING-RPM.md) for the full recipe, verification and
rollback.

To run the checks before packaging anything:

```sh
make KDIR=/lib/modules/$(uname -r)/build CC=/usr/bin/gcc check
```

Pin `CC` to the compiler that built the running kernel. If `gcc` on `PATH`
resolves to a different toolchain (CUDA toolkits do this), the kernel build
prints `warning: the compiler differs from the one used to build the kernel`
and the log is no longer clean. `scripts/gcc-version.sh` on Fedora reports the
expected version as `150301` for GCC 15.3.1.

The reboot matters: it lets the package blacklist Linux's old `sm750fb` driver
before it can claim the card. The package is named `sm750hdmifb`; the kernel
module is `sm750hdmidrm.ko` so it cannot be confused with `sm750fb.ko`.

### Kernel compatibility

**Built on 6.17 through 7.4, runtime-validated on 7.3.5.** Release 0.6.9 is
installed by DKMS for the Fedora 43 kernels 7.2.15-100, 7.3.3-100, 7.3.4-100 and
7.3.5-100, and was loaded and exercised on 7.3.5-100, the reference host kernel,
including the devices-level `pm_test` cycle. The earlier trees are built and
installed; 7.3.4-100 was the reference kernel until 2026-11-27. Linux
7.4 is still in development: only its headers have been compiled against, so it
remains untested at runtime. See the
[release notes](docs/RELEASE-NOTES.md) and the
[acceptance report](docs/ACCEPTANCE-REPORT.md).

The driver is intended for **Linux 6.17 and newer**. DKMS deliberately refuses
older kernels because the required DRM interfaces are not supported by this
project. The source has compatibility paths for Linux 6.17 through the 6.x
series and for Linux 7.0 onward, including the atomic transaction rename in
7.2 and the state-creation callbacks introduced in 7.3 before removal of the
old CRTC reset API in 7.4. The compatibility matrix covers Ubuntu 6.17 and
7.0 headers, mainline 6.18, 7.1 and 7.2 headers, 7.3-rc3 headers, and the
2026-10-28 mainline daily headers from the 7.4 merge window. All three scanout
defaults are built. That matrix is offline compilation; the kernels named above
are the ones boot-tested with the live module.
See [Testing and recovery](docs/TESTING.md) for the exact validation scope.

All supported kernels use the driver's private vblank timer to avoid a restart
deadlock in the DRM core timer helper. See [vblank timer locking and tests](docs/VBLANK.md).

There is no fixed upper version cap, but future kernels can change internal DRM
APIs. Linux 7.4 is still in development, so its final release must be checked
again. Because this is an out-of-tree driver, a new kernel version may require a
source update even though it falls within the intended `6.17+` range.

No prebuilt packages are published. GitHub Actions is disabled for this
repository, so no CI job produces binaries; build the package locally from the
tree you checked out. DKMS then compiles against the installed kernel headers.

## Normal use

By default the driver:

- Uses monitor EDID modes
- Uses dithered 16-bit RGB565 scanout
- Uses a hardware cursor
- Coalesces updates on a worker
- Uploads eight-row batches with DMA
- Falls back safely if DMA fails

Applications still render in 32-bit colour. Immediately before upload, the
driver converts changed screen regions to RGB565 and applies KodeMunkie's
ordered dither with a 94% green-channel correction. This is the default because
the SM750 framebuffer is reached over a PCIe 1.1 x1 link. At the higher
resolutions that link cannot provide responsive full-screen 32-bit updates:
XRGB8888 sends four bytes per output pixel, while RGB565 sends two. Dithered
RGB565 therefore halves device-bound pixel traffic while preserving much of
the apparent colour detail.

Common kernel or GRUB options are:

The table omits the common `sm750hdmidrm.` prefix to keep it readable. For
example, enter `enable_dma=0` as `sm750hdmidrm.enable_dma=0` in GRUB.

| Option and default | When to specify it | Effect and tradeoff |
|---|---|---|
| `scanout_format=rgb565-bbdither`<br>Default: `rgb565-bbdither` | No need; this is the recommended default | Dithered 16-bit scanout with green correction |
| `scanout_format=xrgb8888`<br>Default: `rgb565-bbdither` | Only for 32-bit scanout | Disables RGB565, dither and green correction; doubles upload traffic and can lag at high resolutions |
| `scanout_format=rgb565`<br>Default: `rgb565-bbdither` | Only for plain RGB565 | Disables the dither and green correction, reducing colour quality |
| `dither_green_gain=94`<br>Default: `94` | No need; correction is on by default | Enables the tuned green correction while dithering |
| `dither_green_gain=100`<br>Default: `94` | To turn green correction off | Keeps the dither but may produce a greener colour balance |
| `enable_dma=1`<br>Default: `1` | No need; DMA is on by default | Verified eight-row DMA uploads with automatic CPU fallback |
| `enable_dma=0`<br>Default: `1` | To disable DMA | Forces CPU uploads, usually with lower update performance |
| `disable_hardware_cursor=1`<br>Default: `0` | For the software cursor fallback | Disables the hardware cursor and may reduce cursor responsiveness |
| `edid_only=0`<br>Default: `1` | Required for the driver catalogue and ultrawide modes | **DANGEROUS: STOPS EDID RESTRICTING MODES AND CLOCKS THE MONITOR MAY NOT SUPPORT** |
| `softscale_wide=1`<br>Default: `0` | Required for 2464x1080 and 2560x1080; also set `edid_only=0` | **DANGEROUS / EXPERIMENTAL: ENABLES WIDE COMPRESSION AND REQUIRES MONITOR STRETCHING** |
| `sharpen=1`<br>Default: `0` | Recommended with ultrawide modes | Adds fixed 8% contrast sharpening after compression |
| `double_shadow=1`<br>Default: `0` | Recommended to avoid redundant uploads | Adds source and output comparison snapshots; skips unchanged pixels but uses more system memory. This is not front/back page flipping |
| `async_updates=1`<br>Default: `1` | No need; enabled by default | Keeps only the latest pending update instead of queuing stale frames |
| `crc_window_bytes=262144`<br>Default: `262144` | To bound the cost of scanout readback | Bytes read from the visible scanout offset for each CRC and by the `sm750_scanout` debugfs dump; minimum 4096, rounded down to a multiple of 4, clamped to the visible area |

Add options to the existing `GRUB_CMDLINE_LINUX_DEFAULT` value in
`/etc/default/grub`, then apply them with:

```sh
sudo update-grub
sudo reboot
```

Every option and its default is listed in
[Module parameters](docs/PARAMETERS.md).

### sm750-smi

`tools/sm750-smi` is a monitoring and control utility modelled on `nvidia-smi`;
the reporting side is read-only, and the tunable `test_pattern*` parameters are
reported with their live values.
It needs no root: it reads sysfs, the DRM card node through libdrm and, where
it exists, debugfs. A value that cannot be read is printed as `n/a` with the
reason instead of a guess, and `--strict` turns such a value into exit code 3
for a monitoring script that must fail closed. It builds against libdrm only.
The released packages install it as `/usr/bin/sm750-smi` - the
`sm750hdmifb-tools` package, separate from the DKMS module package and built
for the host architecture - while a source build installs it as
`/usr/local/sbin/sm750-smi`. It carries a man page in `--help`:

```sh
make tools
sudo make install-tools
sm750-smi                                  # banner, one device block, processes
sm750-smi --query=display.mode,vblank.count    # values only, CSV
sm750-smi --format=json --query=memory.total
sm750-smi --list-fields                    # fields, descriptions, data sources
sm750-smi --loop=2                         # redraw every 2 s, Ctrl-C exits 0
```

Run on this host, 0.6.4 module and a 1024x768 panel:

```
+-----------------------------------------------------------------------------+
| sm750-smi - Silicon Motion SM750 monitoring                                 |
| Driver Version: 0.6.4                SrcVersion: 53463BAE2A15EB88A4376E8    |
| PCI Bus Id: 0000:01:00.0                                                    |
+-----------------------------------------------------------------------------+
Sun Nov 22 17:44:25 2026
  name                         sm750hdmidrm
  driver_version               0.6.4
  srcversion                   53463BAE2A15EB88A4376E8
  bus_id                       0000:01:00.0
  pci.device_id                126f:0750
  pci.subsystem_id             126f:0750
  pci.revision                 a1
  memory.total                 16777216
  memory.used                  3147008
  memory.free                  13630208
  display.connector            HDMI-A-1
  display.connected            connected
  display.mode                 1024x768
  display.refresh_hz           60.00
  display.pixel_clock_khz      52329
  display.hpd                  1
  display.rxsense              1
  display.link                 connected
  crtc.index                   0
  vblank.count                 311
  crc.support                  1
  test_pattern                 auto
  test_pattern_period_ms       5000
  test_pattern_anim_ms         40
  processes.count              0
  power.runtime_status         active
  module_loaded                yes

Processes:
  PID      COMMAND           NODE
  (none: no process holds the card node)
```

Every row above is live. Since 0.6.4 the module publishes twelve attributes on
the PCI device (`/sys/class/drm/cardN/device/`), so `memory.total`,
`memory.used`, `memory.free`, `display.hpd`, `display.rxsense`,
`display.link`, `crtc.index`, `vblank.count` and `crc.support` read from the
driver instead of falling back; `display.mode`, `display.refresh_hz` and
`display.pixel_clock_khz` prefer the driver's own view of the active pipe.
The fallbacks stay in place, so an older module is still picked up with no
rebuild: with a 0.6.2 module those rows print
`n/a (driver attribute not present in this version)` and `crc.support` prints
`n/a (needs root (debugfs))` because the CRC control file lives in debugfs.
`--sysfs-root`, `--card` and `--proc-root`
point the tool at a synthetic tree, which is how `tests/check-sm750-smi.sh`
exercises every field without a GPU; a missing card node prints the PCI-only
view and exits 2.

## Ultrawide scaling

The device is normally described as supporting up to 1920 pixels horizontally.
With `edid_only=0`, the driver also exposes these real 2048-wide hardware
modes:

| Desktop and HDMI mode | Refresh rates | Output and risk |
|---|---|---|
| `2048x864` | 59.94, 60, 70, 72, 75 Hz | Native or monitor-scaled. **EXPERIMENTAL: NOT RESTRICTED BY EDID** |
| `2048x1024` | 59.94, 60, 70, 72 Hz | Native or monitor-scaled. **EXPERIMENTAL: NOT RESTRICTED BY EDID** |
| `2048x1080` | 50, 59.94, 60, 70, 72, 75 Hz | Native or monitor-scaled. **EXPERIMENTAL: HIGH REFRESH MAY EXCEED SPECIFICATION** |
| `2048x1152` | 59.94, 60 Hz | Native or monitor-scaled. **EXPERIMENTAL: NOT RESTRICTED BY EDID** |

`softscale_wide=1` adds two wider logical desktops. Both require a physical
2560x1080 ultrawide monitor with **FULL WIDESCREEN STRETCH ENABLED** in its
on-screen menu:

| Logical desktop | Physical monitor | Width ratio | HDMI and monitor path |
|---|---|---|---|
| `2464x1080` | `2560x1080` | `77:64`<br>16.9% compression | `2048x1080 -> 2560x1080` stretch |
| `2560x1080` | `2560x1080` | `5:4`<br>20% compression | `2048x1080 -> 2560x1080` stretch |

| Mode | Refresh rates | Guidance |
|---|---|---|
| `2464x1080` | 50, 59.94, 60, 70, 72, 75 Hz | **RECOMMENDED:** more detail and better responsiveness; enable `sharpen=1` |
| `2560x1080` | 50, 59.94, 60, 70, 72, 75 Hz | Less detail and lower performance because more width is compressed; see [the reasoning](#why-2464x1080-is-recommended) |

For both modes, the HDMI signal is stretched from `2048x1080` to the physical
`2560x1080` pixels of a 2K ultrawide monitor.

**2048 pixels is the highest real width this card can produce in hardware.**
The SM750 primary graphics plane has an 11-bit right-edge field, so its physical
scanout width cannot exceed 2048 pixels. This is a hardware constraint;
reducing the height does not release more horizontal bits. The 2464 and 2560
modes create wider workspaces in software, but the card still outputs only a
2048-pixel-wide signal.

An ultrawide monitor with its full-width or full-widescreen stretch option
enabled is required for the intended result. The complete path is:

```text
logical desktop -> driver compression -> 2048x1080 HDMI -> monitor stretch to 2560x1080 physical pixels
```

The monitor's stretch setting spatially expands the compressed 2048-pixel HDMI
image across all 2560 physical panel pixels. It is not recovering lost source
data, but it restores the intended ultrawide screen coverage and approximately
restores the intended aspect ratio. What looks "correct" is subjective because
the 2464 mode deliberately retains a small aspect difference.

### Why 2464x1080 is recommended

For `2560x1080`, the driver performs an optimized 5:4 reduction from 2560 to
2048 pixels, a 20% horizontal compression. A 2560-wide monitor then expands the
2048-pixel signal by 25% back across its panel. This provides a true
2560x1080-sized workspace, but some fine horizontal detail is necessarily
combined during the first step and more source pixels must be rendered and
processed.

For a physical 2560x1080 monitor, `2464x1080` is the recommended,
higher-performance and often sharper mode. It starts with
3.75% fewer desktop pixels and compresses width by only 16.9% before sending the
same 2048x1080 signal. The monitor still expands that signal across 2560 panel
pixels, so less source detail was discarded by the driver, but the final image
is about 3.9% wider than its logical geometry. This slight aspect distortion is
generally difficult to notice and is the tradeoff for improved responsiveness
and perceived sharpness. Enabling `sm750hdmidrm.sharpen=1` is recommended.

Both wide modes can apply a small fixed 8% contrast sharpen after compression.
It restores some edge definition lost to filtering; it does not recreate
discarded pixels. The dither and green correction are applied during the final
RGB565 conversion before the 2048-wide scanout is uploaded.

This tested profile enables the driver mode catalogue and wide scaling:

> **DANGER: THIS PROFILE DISABLES EDID MODE RESTRICTIONS AND EXPOSES
> EXPERIMENTAL OR ABOVE-SPECIFICATION CLOCKS. A LISTED MODE MAY BLANK OR
> DESTABILIZE THE DISPLAY OR EXCEED A GPU, TRANSMITTER OR MONITOR LIMIT.**

```text
sm750hdmidrm.edid_only=0 sm750hdmidrm.softscale_wide=1 sm750hdmidrm.sharpen=1 sm750hdmidrm.scanout_format=rgb565-bbdither sm750hdmidrm.double_shadow=1 sm750hdmidrm.enable_dma=1
```

Some catalogue refresh rates run the SM750 DVO path or the monitor outside
published limits. A mode being listed does not guarantee that every monitor,
cable, KVM, or adapter will accept it. See
[Modes and clock risks](docs/MODES.md) before experimenting.

## Custom desktop dither

`rgb565-bbdither` uses an 8x8 ordered dither conceived and tuned by KodeMunkie
specifically for desktop use on this card. It includes an adjustable
green-channel correction and anchors the pattern to screen coordinates, so
small updates do not make the pattern crawl or leave mismatched patches.

## Screenshots

The three images below visualise the complete ultrawide conversion process.
Click any preview to open the original image. The logical desktop and physical
photo are shown at 50% page width. The compressed preview is shown at 41.56%,
preserving the `2048 / 2464` width reduction instead of stretching both digital
stages to the same preview width.

### 1. Logical desktop

<a href="docs/images/desktop-2464x1080-logical.png"><img src="docs/images/desktop-2464x1080-logical.png" alt="Original 2464x1080 logical desktop" width="50%"></a>

The driver receives this original `2464x1080` logical desktop.

### 2. Compressed HDMI scanout

<a href="docs/images/desktop-2048x1080-scanout.png"><img src="docs/images/desktop-2048x1080-scanout.png" alt="The 2464x1080 desktop compressed to the SM750's 2048x1080 hardware scanout" width="41.56%"></a>

The image above deliberately looks horizontally squashed. It reproduces the
`2048x1080` HDMI scanout generated by compressing the `2464x1080` logical
desktop to the SM750's hardware-width limit.

### 3. Physical monitor result

<a href="docs/images/desktop-2560x1080-physical.jpg"><img src="docs/images/desktop-2560x1080-physical.jpg" alt="The monitor stretching the SM750 scanout across its physical ultrawide panel" width="50%"></a>

The photographed result fills the monitor's `2560x1080` physical pixels at
75 Hz, using the driver's 16-bit `rgb565-bbdither` dithered scanout.

The monitor's **FULL WIDESCREEN STRETCH** option expands that signal across its
physical `2560x1080` panel. The complete path is therefore:

*Logical desktop -> SM750 hardware scanout -> physical panel, stretched by the
monitor.*

## Troubleshooting

Check binding and recent driver messages:

```sh
lspci -nnk -d 126f:0750
journalctl -k -b | grep -iE 'sm750|sii902'
```

If an experimental mode gives no signal, boot an older kernel entry or remove
the added `sm750hdmidrm.*` GRUB options from recovery access. Testing and live
reload guidance is in [Testing and recovery](docs/TESTING.md).

### If the card stops working after removing the package

`dnf remove sm750hdmifb` runs the RPM `%preun` scriptlet, which calls
`dkms remove -m sm750hdmifb -v <version> --all`
(`packaging/sm750hdmifb.spec`). That unregisters the DKMS module for every
kernel and deletes the built `sm750hdmidrm.ko`, but it cannot unload a module
that is already resident, so the running display keeps working. At the next
boot there is no object left to load, card0 does not appear, and a console that
only has the SM750 output stays dark. Nothing in the source is broken; the file
the kernel would load is gone.

Recovery, in this order:

1. Do not erase the package on a machine whose only console is the SM750
   output. If it already happened, get a working console first: SSH over the
   network, a serial console, or another GPU.
2. Confirm the state: `dkms status` prints no `sm750hdmifb/<version>` line, and
   `ls /usr/src | grep sm750hdmifb` is empty because the source tree belongs to
   the RPM.
3. Reinstall the same or a newer package. `%post` re-registers the tree and
   `%posttrans` builds it for every installed kernel with headers:
   `sudo dnf install ./sm750hdmifb-<version>-<release>.noarch.rpm` (or
   `sudo dnf reinstall sm750hdmifb` from the repository it came from).
4. If no package is at hand, reinstall the RPM to restore
   `/usr/src/sm750hdmifb-<version>` and run what `%posttrans` runs:
   `sudo dkms build -m sm750hdmifb -v <version>` then
   `sudo dkms install -m sm750hdmifb -v <version> --force`.
5. Attach the module without rebooting: `sudo modprobe sm750hdmidrm`, then
   check `ls /dev/dri/`, `cat /sys/class/drm/card*/status` and
   `journalctl -k -b | grep -i sm750`. `card0-HDMI-A-1` should be `connected`.
6. Reboot only if a reboot was the goal; the display is back after step 5.

The ordering is the whole hazard: `%preun` deletes the object while the module
is resident, and nothing re-runs `modprobe` for a module that is already
loaded. Reinstalling restores the object and the `depmod` entry; `modprobe`
then attaches card0 again. Erase-state transcripts are in
`docs/evidence/runtime/20-rollback.txt`.

### Boot messages that are not errors

Four lines appear on every boot of the reference host and none of them is a
fault:

| Message | Meaning |
|---|---|
| `loading out-of-tree module taints kernel`, `module verification failed: signature and/or required key missing` | Expected for a DKMS module that is not signed with a key enrolled in the kernel |
| `DMA1 IRQ was not delivered; reverting to completion polling` | The DMA1 completion interrupt is not routed on this board. The driver confirms the first transfer by polling the completion bit, disables the interrupt and keeps polling. One `drm_info` per boot (`src/sm750_drm.c:1499`) |
| `SiI9024A receiver not ready after 500 ms: HPD=1 RSEN=0 status=04; enabling for compatibility` | Hot-plug (0x3d bit 2) is present but the sink has not reported a powered receiver (bit 3) for 100 ms - a plugged, unpowered sink, which SiI-PR-1064-A calls normal and whose EDID is still readable. Behind a KVM switch or a passive HDMI-DVI adapter the same line appears. A forced mode needs no DDC, so the transmitter is programmed anyway and the probe succeeds (`src/sii902x.c:661-671`) |
| `pci 0000:01:00.0: CLS mismatch (64 != 32), using 64 bytes` | PCI cache-line-size negotiation by the kernel |

The real failures to watch for are `DMA1 shadow upload timed out; using CPU
copies from now on` (`src/sm750_drm.c:1504`), which means the DMA path was
abandoned, and `failed to enable HDMI mode`, which is survivable since 0.6.0 -
the commit is completed and the atomic state stays consistent - but still
indicates the bridge timeout described in `docs/evidence/EVIDENCE-GAPS.md` as GAP-B8.
Since T27 that line ends with `at stage <name>`, and `<name>` is the
`sm750_program_mode` call that failed (`sii902x_begin_mode`,
`ddk750_set_display_control`, `ddk750_set_mode_timing`,
`ddk750_set_logical_disp_out` or `sii902x_enable`; `none` means the failure came
from before those calls) - quote the full line when reporting it.

### Register dump

The driver registers a read-only MMIO dump as a debugfs file, which is the only
supported way to read SM750 registers without `/dev/mem` (`CONFIG_STRICT_DEVMEM`
blocks that path). The debugfs directory is named after the DRM minor, which is
not always `0`; resolve it from the card node first:

```sh
card=$(readlink -f /dev/dri/by-path/pci-0000:01:00.0-card)
minor=${card##*/card}
sudo cat /sys/kernel/debug/dri/$minor/regs
```

The driver advertises a render node beside the card node, so
`/dev/dri/by-path/pci-0000:01:00.0-render` resolves to the same device as
`/dev/dri/by-path/pci-0000:01:00.0-card`; before 0.6.5 no render node existed
and the card node was the only stable handle. The node carries the dumb-buffer
and PRIME primitives only: it is not a claim of GL acceleration, and no Mesa
driver exists for this GPU, so a client that needs an accelerated render node
still will not find one. The `renderD*` nodes of other cards on a multi-GPU host
are unrelated.

The file is mode `0444` and lives under the DRM minor's debugfs directory, so
reading it requires root. It is inert until read, never writes to the device,
and deliberately omits the read-to-clear registers (`RAW_INT`, `INT_STATUS`,
`GPIO_INTERRUPT_STATUS`) so a dump taken before and after one modeset stays
comparable. The dump is a stable `0x<offset> <name> 0x<value>` table; see
[docs/REGISTERS.md](docs/REGISTERS.md) for the list of reported registers.

### Scanout CRC

DRM core publishes the CRC uapi for the CRTC under `crtc-<index>/crc/` in the
same debugfs directory as `regs` (resolve `<index>` and the minor as above) and
routes it to the driver's `drm_crtc_funcs` hooks. Core creates two files:

- `control` (mode `0644`) reads `none` or `scanout`. Writing `scanout` or `auto`
  enables the source, `none` or an empty write disables it; anything else fails
  with `EINVAL`. The write fails with `ENODEV` when the CRTC has no scanout
  geometry yet, which is the case before the first modeset: arm the source after
  `drmModeSetCrtc`, not before, because the tick rides the vblank that the mode
  produces. The stream then survives modesets by itself: `sm750_pipe_disable()`
  parks it and `sm750_pipe_enable()` re-arms it.
- `data` (mode `0444`) emits the number of CRC values per entry, `1`, on the
  first read after open, then one line per frame of the form `<frame> <crc>`:
  a decimal vblank count followed by the CRC of the visible scanout bytes in
  hex (bounded by `crc_window_bytes`), for example `12345 a1b2c3d4`. A read
  blocks until the next frame arrives, one reader at a time, and core's ring
  keeps the newest 128 entries.

Core does not create a `source` file for a driver that reports its list through
`get_crc_sources`; `control` names the selected source, so reading it back after
the write is how the selection is confirmed.

If the geometry the source reads is not recorded, the driver logs one `crc:`
warning per enable cycle naming the missing field (`vram`, `pitch`, `frame
size` or `offset bound`) and keeps the tick running, so the stream starts
producing entries as soon as a modeset records the geometry instead of dying
silently.

```sh
minor=${card##*/card}
# draw a frame first (drmModeSetCrtc): the arm needs scanout geometry
printf scanout | sudo tee /sys/kernel/debug/dri/$minor/crtc-0/crc/control
sudo cat /sys/kernel/debug/dri/$minor/crtc-0/crc/control
sudo cat /sys/kernel/debug/dri/$minor/crtc-0/crc/data
printf none | sudo tee /sys/kernel/debug/dri/$minor/crtc-0/crc/control
```

The driver owns no file here: `crtc-N/crc/` with `control` and `data` is
created by `drm_debugfs_crtc_crc_add()` inside `drm_dev_register()` because
`sm750_crtc_funcs` is in place by then, and core's `control` write calls the
same `sm750_crtc_set_crc_source()` hook. A driver-owned copy of those files
would shadow core's and leave core's CRC state unset, so a write through it
enables nothing and a read of core's `data` fails; that shim was removed in
T30. The CRC covers the scanout source buffer in VRAM, not the pixels the
encoder emits; `sm750_scanout` prints the same `crc32` for a frame, and
`make crc-check` compares the two on the card.

### Framebuffer console

The driver sets up fbdev emulation through `DRM_FBDEV_TTM_DRIVER_OPS` and
`drm_client_setup()`. A `/dev/fb0` node appears only when the kernel is built
with fbdev emulation and no other framebuffer driver already owns the device.
KMS output works without it, so a missing `/dev/fb0` is not a driver fault.

### Test card fallback

A module load on a foreground VT in `KD_GRAPHICS` leaves the panel scanning an
all-zero frame (see the next section). Instead of leaving a dead-black panel,
the driver can paint an analog-style test card into the window it is about to
scan: seven EBU colour bars over the top two thirds, an 8-step grayscale
staircase along the bottom, a 16x12 grid, a centred crosshair and circle, an
inset white border, a moving white sweep and a bouncing disc. The card is pure
geometry, so it renders the same in 16 and 32 bpp.

`test_pattern` selects the behaviour:

| Value | Meaning |
| --- | --- |
| `off` | never paint |
| `auto` (default) | paint when the frame being enabled is entirely blank and no userspace DRM client owns the display |
| `always` | paint on every enable, blank or not |

Two timers keep it moving, so a frozen card is obvious at a glance and a panel
left on it does not burn in:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `test_pattern_anim_ms` | `40` | animation tick, 25 fps; `0` stops the disc |
| `test_pattern_period_ms` | `5000` | full-card palette rotation; `0` keeps the palette |

`test_pattern_anim_ms` values outside 10-1000 ms are clamped once, with a
`drm_info` line naming the clamp, and the same holds for
`test_pattern_period_ms` outside 500-600000 ms.

The disc is the Atari-screensaver part: a filled circle with a 2 px black
outline, radius 3 percent of the frame height clamped to 24-64 px, travelling
diagonally at 3 px per tick horizontally and 2 px per tick vertically at 1080p
and proportionally slower on a smaller panel. It reflects off the inner border,
never crosses it, and takes the next EBU colour on every bounce. A tick
recomputes only the two bounding boxes it touches, 35 KiB per tick at 1080p in
32 bpp, not the 8 MiB frame. The palette rotation keeps its own 5 s cadence,
counted in ticks, and the disc keeps its position across a rotation.

```sh
# paint a card even when a client did paint (diagnostics, cable hunting)
sudo sh -c 'echo always > /sys/module/sm750hdmidrm/parameters/test_pattern'
# static card: no disc, no rotation, no burn-in protection
sudo sh -c 'echo 0 > /sys/module/sm750hdmidrm/parameters/test_pattern_anim_ms'
sudo sh -c 'echo 0 > /sys/module/sm750hdmidrm/parameters/test_pattern_period_ms'
# back to the default: paint only a blank frame
sudo sh -c 'echo auto > /sys/module/sm750hdmidrm/parameters/test_pattern'
```

The card is a fallback, not a display path. It is skipped when the window is
softscaled (the scanout pitch is 2048 there, not the display width), when the
frame does not fit the VRAM left after the scanout offset, and on modes below
320x200. A userspace DRM master is by definition producing frames, so `auto`
leaves its output alone even when that output is black - a desktop, a
screensaver, a paused video or a CRC harness buffer; only an unowned CRTC (the
in-kernel fbdev client never becomes a master) gets the card. The first real
client commit cancels the animation before it uploads. There is deliberately no
one-shot upload skip: the RCA in
`docs/evidence/runtime/24-test-card-crc-conflict-rca.txt` proved that such a
flag dropped the client's first frame instead of the enabling commit's own
upload, because planes are committed before modeset enables.

An armed scanout CRC source owns the window. Arming it cancels a running card,
`test_pattern` stays inert for the source's whole lifetime, and a tick that was
already waiting on the mode lock re-checks the flag before it paints.
`test_pattern=always` does not override an armed CRC source either.

`tools/sm750-console.sh` (installed as `/usr/local/sbin/sm750-console`, root
only) is the alternative when a static image is unacceptable: it moves the
foreground VT into `KD_TEXT` so fbcon paints the panel for real.

```sh
sudo sm750-console show      # active tty, KDGETMODE, vtcon bind, PANEL_FB_ADDRESS, scanout crc
sudo sm750-console text      # chvt 2: foreground VT becomes KD_TEXT
sudo sm750-console text 3    # a specific VT
sudo sm750-console graphics  # chvt 1: back to the session VT
```

`tools/sm750-headless.sh` (installed as `/usr/local/sbin/sm750-headless`, root
only) answers the two questions `sm750-console` does not: who holds DRM master
on the card, and does a compositor survive on it. It refuses to start unless
`0000:01:00.0` is bound to `sm750hdmidrm`, takes master itself (`0x641E`,
dropped with `0x641F`) to prove the card is free, exits 4 when another process
holds it, then runs one fixed program for a bounded time:

```sh
sudo sm750-headless probe               # snapshots and the master probe only, immediate
sudo sm750-headless diagnose            # who holds card0, module refcount, vtcon bind
sudo sm750-headless weston              # weston kiosk plus one terminal, 20 s
sudo sm750-headless cage 30             # cage around one terminal, 30 s
sudo sm750-headless kmscube 15          # kmscube, 15 s
```

`weston` and `cage` run inside a private mount namespace whose `/dev/input` is
an empty tmpfs, so neither can open or grab the owner's keyboard and mouse;
`kmscube` opens only the card and is not isolated. The run prints
`sm750-headless: input devices are isolated in a private mount namespace (empty /dev/input)`
and records the same line, with the `unshare` and `mount` commands used, in
`00-plan.txt`. Defect A49 in `docs/DEFECTS.md` records why a namespace is the
only guard: weston's DRM backend offers no `--no-input` (that option is x11
only) and cage has no input option at all.

`tools/sm750-vt.sh` (installed as `/usr/local/sbin/sm750-vt`, root only for
`off` and `on`) covers the other half of the reload problem: a rebuilt module
stays unloadable while the built-in framebuffer console is bound to the SM750
vtconsole, because that console is the reference behind
`modprobe: FATAL: Module sm750hdmidrm is in use.`. Detaching that console is
necessary but not sufficient: the first live run did it and `modprobe -r` was
still refused, so the helper also writes the BDF to
`/sys/bus/pci/drivers/sm750hdmidrm/unbind` to run the driver remove path and
drop the reference to 0, prints the refcount before and after that step,
reloads the module, verifies the version attribute after the load, re-binds the
device, and writes `1` back to the console:

```sh
sudo sm750-vt show      # read-only: vtconsoles, resolved target, driver dir, module, holders
sudo sm750-vt off       # detach fbcon, unbind device, modprobe -r, modprobe, rebind, re-bind
sudo sm750-vt on        # re-bind fbcon only, recovery after an interrupted off
```

While fbcon is unbound there is no text console on any VT, so `off` is run from
an SSH or serial session, never from the SM750 monitor; the helper prints that
warning itself, refuses while a process holds the card, and restores the
module, the device and then the console from an EXIT trap on every failing
path. That refusal matches the card and render nodes on their `dev:inode`
identity resolved from `/dev/dri/by-path/pci-0000:01:00.0-card` and
`-render`, not on a node name, because the node is `card0` before a reload and
`card4` after it and a name match would report no holder while the module was
really held (the holder-scan name-glob bug); each holder is printed as
`pid:comm node`. `on` re-binds the console only, so a device left unbound needs the BDF
written to `/sys/bus/pci/drivers/sm750hdmidrm/bind`. The target is resolved by
globbing `/sys/class/vtconsole`, never by a hardcoded index, and more than one
candidate is a refusal. Defects A50 and A51 in `docs/DEFECTS.md` record the
measured blocker and the failed first attempt; refreshing the installed copy is
the owner's action (`docs/ROOT-ACTIONS.md` section 3.12).

`SECONDS` defaults to 20 and is clamped to 1..600; no other argument is
accepted. The compositors run with `LIBSEAT_BACKEND=noop`, so they open the
DRM device directly and never touch seat0, logind or a VT; `cage` gets no `-s`
and `kmscube` gets `-c` (frame count), not `-n` (a connector id). Each run
writes a verdict directory under `/mega/tmp/sm750/headless/`, and the verdict
is FAIL when the compositor did not survive the full time or the
`vblank_count` delta is `<= 0` - a frame count alone never proves a compositor
rendered.

### What the HDMI output actually shows

On the reference host the SM750 HDMI output carries the kernel console, and the
desktop is on a different card. This is observed behaviour, not a configuration
instruction:

- The driver registers its own in-kernel fbdev client at probe, through
  `drm_client_setup(&sdev->drm, drm_format_info(DRM_FORMAT_XRGB8888))` at
  `src/sm750_drm.c:3784`. That client is the only user of the SM750 CRTC.
- The kernel log records the console takeover and the framebuffer device, both
  before any userspace client attaches:

  ```text
  [    6.265979] sm750hdmidrm 0000:01:00.0: [drm] full-frame backbuffer staging enabled (4147200 bytes per buffer)
  [    6.291648] Console: switching to colour frame buffer device 240x67
  [    6.341676] sm750hdmidrm 0000:01:00.0: [drm] fb0: sm750hdmidrmdrm frame buffer device
  ```

  `4147200` bytes is `1920 * 1080 * 2`, the size of one RGB565 buffer at the
  mode the fbdev client sets.
- No `/dev/fb*` node appears despite that registration, because
  `CONFIG_FB_DEVICE` is unset on this kernel (recorded as A24 in
  `docs/DEFECTS.md`). The character device is missing; the console still
  reaches the panel whenever the foreground VT is in `KD_TEXT`.
- The console reaches the panel through fbcon, and fbcon only paints while the
  foreground VT is in `KD_TEXT`: `do_con_write()` in `drivers/tty/vt/vt.c`
  drops console output before fbcon when `vc_mode` is `KD_GRAPHICS`. Loading
  the module on such a host therefore leaves the fbdev client's buffer blank,
  and the panel scans zeros with nothing else wrong. The driver says so once
  per module load at the modeset instead of leaving a black panel unexplained:

  ```text
  [    6.265979] sm750hdmidrm 0000:01:00.0: [drm] console framebuffer is blank: the panel now scans a frame nobody has painted (is the foreground VT in KD_TEXT?)
  ```

  This is a diagnostic, not a behaviour change: no upload is skipped and no
  commit fails. `make console-check` (root only) tells the two states apart on
  the card: it skips when the foreground VT is `KD_GRAPHICS`, and on a text VT
  it writes to the console and asserts that the `sm750_scanout` window carries
  content, that its `crc32` is not the all-zero sentinel `0xe20eea22` and that
  its `offset` is the `PANEL_FB_ADDRESS` the panel register points at. The
  source-level counterpart is `tests/check-console-blank.sh`, part of
  `make check`.
- The monitor stays attached to the SM750 HDMI connector: `card0-HDMI-A-1`
  reports `connected` at every probe, and nothing detaches it.
- The user's desktop runs on the NVIDIA GTX 1070, not on the SM750. On this
  host `card1` is `0000:02:00.0` with `card1-DVI-D-1` connected and
  `kwin_wayland` running against it; `card0` has no userspace DRM master.

So the SM750 is a second, permanent output that shows the console, and the
graphical session is unaffected by anything done to it.

That is this host's arrangement, not a limit of the driver. A full Plasma
Wayland session does run on `card0` with two environment workarounds and no
root privileges; the measured session, the recipe and the remaining gaps are in
[Plasma on this driver](docs/PLASMA-WAYLAND.md). One of those workarounds can be
a third: on a module older than 0.6.7, kwin may start compositing and then starve
the scanout because it asks for a buffer modifier the plane never advertised
(`kwin_wayland_drm: Failed to create framebuffer`, errno 22). Exporting
`KWIN_DRM_USE_MODIFIERS=0` makes the session use the modifiers-free path;
driver 0.6.7 and newer makes the variable unnecessary by reporting
`DRM_CAP_ADDFB2_MODIFIERS` as 0 itself. Sections 4.4 to 4.6 of
[Plasma on this driver](docs/PLASMA-WAYLAND.md) have the probe results, the
measured effect of the variable and how to tell which case you are in. A
modeset on `card0`
from a test tool temporarily replaces the console; closing the tool lets the
fbdev client restore its own 1920x1080 mode.

A second front, X11, is documented in [Plasma over X11](docs/PLASMA-X11.md).
It needs one thing Wayland does not: the X server must run as root, because a
non-root `Xorg` cannot own a VT on this host and dies with
`xf86OpenConsole: Cannot open virtual console 1 (Permission denied)`. It also
needs a per-session fix, because `/etc/environment` points `KWIN_DRM_DEVICES`
and GLX at the NVIDIA card, which crash-loops `kwin_x11` four times before it
gives up. With the desktop-wide variables cleared, `kwin_x11` holds a single
process and draws. Since 2026-11-26 that is measured on the panel too: the
helper's `x11` mode ran as root, the server came up on `:1` in 4 s against
`/dev/dri/card0`, `kwin_x11` stayed on one pid with zero crash lines, the
connector read `enabled`, and a 1920x1080 capture was 1836586 bytes. The
composition is software, through kwin's XRender path on llvmpipe, because that
server has no GLX.

That restore is a disable-then-enable pair inside one atomic commit, and both
halves can now say what happened instead of failing quietly. The transition
waits compare only the timing and plane enable bits - the bits the hardware
latches at the next vertical sync - rather than a whole register snapshot, and
a mode change budgets for two vertical periods of the mode it programs. If a
display still refuses to switch off, the log carries
`panel did not acknowledge display-off: -110 (PANEL_DISPLAY_CTRL=0x...)`; if
the enable half then fails, it prints one `enable-fail state:` line with
`PANEL_DISPLAY_CTRL`, `PANEL_PLL_CTRL`, `SYSTEM_CTRL` and
`PANEL_CURRENT_LINE`. A failing restore is therefore a register readback to
report, not a silent timeout.

The restore path is verified on hardware: 30 consecutive client exit/restore
cycles and 20 mode changes ran on 2026-11-20, 95 enable events in total
across 1920x1080 and 1024x768, with no timeout, no `did not latch` line and no
`enable-fail state` line in the kernel log. The run, its counts and its
limitations are in
[`docs/evidence/runtime/22-restore-fix-hardware-proof.txt`](docs/evidence/runtime/22-restore-fix-hardware-proof.txt).

## Developers

- [Hardware and capability comparison](docs/HARDWARE.md)
- [Module parameters](docs/PARAMETERS.md)
- [Register reference](docs/REGISTERS.md)
- [Modes and clock risks](docs/MODES.md)
- [Provenance and licensing audit](docs/PROVENANCE.md)
- [Testing and recovery](docs/TESTING.md)
- [Test strategy and results](docs/TEST-STRATEGY.md)
- [RPM packaging](docs/PACKAGING-RPM.md)
- [Staging benchmark](docs/STAGING-BENCHMARK.md)
- [Device specification archive](docs/specs/INDEX.md)
- [Repository audit](docs/AUDIT.md) and [defect inventory](docs/DEFECTS.md)
- [Build environment](docs/ENVIRONMENT.md)
- [Deliverables index and reproduction](docs/DELIVERABLES.md)
- [Static analysis](docs/STATIC-ANALYSIS.md) - sparse, smatch, cppcheck, coccinelle, pahole
- [Plasma on this driver](docs/PLASMA-WAYLAND.md) - the measured Wayland session, the bypasses, the limits
- [VBIOS reconstruction](docs/VBIOS-REVERSE-ENGINEERING.md) - 239-region map and the C model of the option ROM
- [Acceptance report](docs/ACCEPTANCE-REPORT.md) - criterion-by-criterion verdict with evidence paths
- [Project logbook](docs/LOGBOOK.md) - chronological record, newest entry last
- [Host root actions](docs/ROOT-ACTIONS.md) - sudoers, helpers, udev rule, recovery
- [CI recipe](docs/ci/build.yml) - inactive: GitHub Actions is disabled for this repository, the file is a copy-paste recipe

### Presentation deck

A ten-slide overview of the driver, its architecture and its open items, in two
forms. The links are raw HTML on purpose: a forge renders HTML in a Markdown
file by stripping it, so the deck is kept as a standalone page and only linked.

- <a href="https://polaris.root.sx/code/duka/sm750hdmifb/raw/branch/main/docs/deck/index.html">Slides (rendered)</a> - the standalone page, served as `text/html` by this repository's primary remote
- <a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/GuramDuka/sm750hdmifb/main/docs/deck/index.html">Slides (rendered, GitHub mirror)</a> - the same page through a viewer, because `raw.githubusercontent.com` serves `.html` as `text/plain`
- [Slides (Markdown source)](docs/DECK.md) - Marp-flavoured Markdown, ten slides, for editing and for `marp --pdf`
- [Deck source](docs/deck/index.html) - the page itself: hand-written reveal-style JavaScript, an inline SVG architecture diagram, hash routing (`#/3`), a print stylesheet and a no-script fallback that stacks all ten slides

Seven verification targets are opt-in and deliberately outside `make check`, so
the default gate stays the same 18 commands on machines without the analysers:

```sh
make static       # sparse, smatch, cppcheck, coccinelle, pahole against src/
make vbios-re     # rebuild the option ROM and compare it byte for byte
make vbios-trace  # execute both images and compare their instruction traces
make crc-check    # live scanout CRC and sm750_scanout readback on the card
make console-check # console reachability: the scanout window is not blank
make check-kunit  # sweep the kernel's own DRM KUnit test suites (root)
make check-oops   # oops-detector wrap around the policy gate
```

Three further targets are build and self-test wrappers rather than verification
targets and are not part of that count: `make check-pkg` (byte-for-byte
reproducibility of the built RPM), `make check-package` (the release package
build and audit) and `make check-all-kernels` (builds the module against each
available kernel tree). The seven above need the analysers, the card or root;
`make check` needs none of them.

`make vbios-re` and `make vbios-trace` need the captured image
(`VBIOS_ROM=...`, or the default path) and print `SKIP` with exit 0 when it is
absent, so a fresh checkout without the image still passes; the trace target
also needs `qemu-system-i386`, `gdb`, `capstone` and `unicorn`. `make static`
prints a skip message when the analysers are missing. `make crc-check` and
`make console-check` need the SM750 card, root and a mounted debugfs; without
them they print one `SKIP:` line and the target turns the exit code 77 into
success. `make console-check` also skips, with a line naming the cause, when
the foreground VT is `KD_GRAPHICS`. The static,
VBIOS and scanout checks are documented in
[static analysis](docs/STATIC-ANALYSIS.md),
[VBIOS reconstruction](docs/VBIOS-REVERSE-ENGINEERING.md) and
[test strategy](docs/TEST-STRATEGY.md).

### Gates and test scripts

| Entry point | What it covers |
|---|---|
| `make check` | The 18 default checks: kernel build, policy checks for the module and DRM code, packaging hygiene, shadow and staging units, the `sm750-smi` fixture gate, vblank timer |
| `tests/build-all-kernels.sh` | The 9-combination kernel and scanout-format build matrix |
| `tests/check-rpm-dkms.sh` | RPM payload against `git ls-files`, scriptlets, dependencies, sandbox DKMS build; no root needed |
| `tests/check-vblank <card> <hz>` | Live vblank rate against the programmed refresh |
| `tests/audit-release.sh` | Release tarball contents, version consistency and archive drift |
| `tests/check-static.sh` | Opt-in static analysis gate with baseline comparison |
| `tests/check-sm750-smi.sh` | Fixture-driven gate for `tools/sm750-smi`: 27 fields from synthetic sysfs/DRM trees, `--strict` exit codes, CSV/JSON parsing, five planted controls; no GPU or root needed |
| `tests/check-sysfs-attributes.sh` | Source-level gate for the twelve monitoring attributes `sm750-smi` reads plus the write-only `pm_probe` diagnostic from `/sys/class/drm/cardN/device/`: names and array entries, the group on the PCI device before `drm_dev_register`, `sysfs_emit()` with no sleep and no lock beyond the mode lock in every show function, `clear_events` false on the link-status read, and `pm_probe` as the only non-monitoring attribute; five planted controls |
| `tests/check-pm-probe.sh` | Source-level gate for the 0.6.9 `pm_probe` attribute (part of `make check` through `tests/check-drm-policy.sh`): `DEVICE_ATTR_WO` (mode 0200) plus its array entry and group registration, `dev_get_drvdata()`, the master, registration and `drm_dev_enter()` guards in that order, the dedicated mutex with `mode_lock` rejected, exactly `suspend`/`resume`/`cycle`, the `pm probe: ` log lines and `resume skipped` after a failed suspend, and the return value: the byte count on success and a callback failure propagated so a script under `set -e` stops; eleven assertions and six planted controls plus a pristine control |
| `tests/check-headless-helper.sh` | Source-level gate for `tools/sm750-headless.sh`: POSIX `sh` plus `sh -n`, the five modes and the usage path, the `0000:01:00.0` / `sm750hdmidrm` binding test, `LIBSEAT_BACKEND=noop` and never `builtin`, the weston, cage and kmscube argument sets read out of the executed switch arms (`-s` rejected on cage, `-n` rejected on kmscube), the `SECONDS` numeric test and 1..600 clamp, the survivor and vblank failures, TERM before KILL on an EXIT trap, no local absolute path and no non-ASCII byte, and that both compositor arms run in a private mount namespace with an empty `/dev/input` (`unshare --mount --propagation private` plus a tmpfs over `/dev/input` mounted before the exec, `isolate` in the weston arm and in the cage arm and absent from the kmscube arm, `WLR_LIBINPUT_NO_DEVICES` documented as wlroots-only); twelve planted controls in `--self-test`, no compositor, no root and no card needed |
| `tests/check-render-node.sh` | Source-level and live gate for the render node: both `driver_features` lines in `src/sm750_drm.c` carry `DRIVER_RENDER` beside `DRIVER_MODESET`, no executable line sets `DRIVER_RENDER` without `DRIVER_MODESET`, `SM750_DRM_VERSION` agrees with `build-package.sh`, and a live `renderD*` node owned by `sm750hdmidrm` must be writable by the invoking user; three planted controls `render_dropped`, `render_only` and `version_drift` in `--self-test`, one `SKIP:` line before a 0.6.5 module is loaded |
| `tests/check-vt-helper.sh` | Source-level gate for `tools/sm750-vt.sh`, the hot-reload helper: the three modes and the usage path, the class-glob vtconsole resolution with no `vtconN` literal, the PCI driver cross-check, `bind` 0 and 1 each read back, one EXIT trap that restores the module, the device and then the console on any failure with a `FINISHED=1` disarm, the holder gate on the unload with the scan matched on the node `dev:inode` identity through the by-path card and render links instead of a node name, `modprobe -r` before `modprobe`, the post-load version read-back, and the A51 PCI step: the unbind after the console detach and before the unload, the refcount printed on both sides of it, and the device re-bound and read back after the load; thirteen assertions and ten planted controls in `--self-test`, no sysfs write, no modprobe, no root and no card needed |
| `make console-check` | Opt-in console reachability: writes to the foreground VT, then requires the `sm750_scanout` window to carry content, to differ from the all-zero sentinel `0xe20eea22` and to report the `PANEL_FB_ADDRESS` offset; exits 77 (a skip) without root, card or a `KD_TEXT` foreground VT |
| `make crc-check` | Opt-in live scanout readback: enables the CRTC CRC source `scanout`, checks that entries arrive, stay constant for a static frame, change with the content and agree with the `sm750_scanout` debugfs dump; exits 77 (a skip) without root, card or an active CRTC |
| `make check-pkg` | Self-tests for the sudo package helper (`tools/sm750-pkg.sh` into `/usr/local/sbin/sm750-pkg`): stubbed dnf/dkms/rpm through a temporary PATH, so no package is touched and no root is needed; nine groups |
| `make check-kunit` | Opt-in DRM KUnit sweep: discovers the DRM KUnit suites under `/lib/modules/$(uname -r)/internal/drivers/gpu/drm/tests/`, modprobes each (KUnit autorun) and parses the TAP results from the kernel log; runs as root or through the allowlisted loader `MODPROBE_CMD='sudo -n /usr/bin/modprobe'` (`docs/ROOT-ACTIONS.md` section 3.9), exits 77 (a skip) without either. On this host the suites load but print only `kunit: disabled` because KUnit is not enabled at runtime (`# CONFIG_KUNIT_DEFAULT_ENABLED is not set`), so the gate skips naming that prerequisite (`docs/ROOT-ACTIONS.md` section 3.10) rather than reporting a pass |
| `make check-oops` | Opt-in oops detector wrapped around `tests/check-drm-policy.sh`: snapshots the kernel log before and after through `DMESG_CMD` (default `dmesg`; this host: `sudo -n dmesg`) and fails on any new `BUG:`/`WARNING:`/`Oops`/GPF/NULL-deref/lockdep/call-trace/`RIP:` line; `--allow` regexes exclude known baseline lines; exits 77 when the log is unreadable |

Hardware-side validation uses the standard tools rather than project scripts:
`modetest` from libdrm for atomic commits and connector state, `kmscube` for the
GL path, and the IGT suite from `igt-gpu-tools` for the KMS conformance subset.
The selected subtests, their pass criteria and the recorded results are in
[test strategy and results](docs/TEST-STRATEGY.md).

### Publishing

The repository has three remotes:

- `origin` carries two push URLs, the Polaris forge and
  `https://github.com/GuramDuka/sm750hdmifb.git`, so one
  `git push origin main` publishes to both.
- `github` names the same GitHub repository directly.
- `upstream` is `https://github.com/KodeMunkie/sm750hdmifb.git`, pull only: its
  `pushurl` is set to `DISABLED`. Fetch from it to pick up upstream changes.

GitHub Actions is disabled, and the CI recipe is kept at
[docs/ci/build.yml](docs/ci/build.yml) as a copy-paste procedure. GitHub loads
workflows only from `.github/workflows/`, and creating or updating a file there
requires a token with the `workflow` scope; see
[build environment](docs/ENVIRONMENT.md) sections 1.2 and 1.3.

The official SM750 specification is known to be wrong for at least one
hardware-observed partial-update boundary. Empirically verified workarounds are
documented in the source and must not be removed solely because an ideal model
or specification says they are unnecessary.

## Licence and disclosure

The project is **GPL-2.0-only**. DDK-derived files came from Linux's GPL-2.0
staging `sm750fb` driver. No proprietary Silicon Motion driver, binary object,
firmware blob, or closed library is included or linked. See the
[provenance audit](docs/PROVENANCE.md) for details.

This project was created through extensive AI-assisted or "vibe coding". I have
specified and physically tested the behaviour and designed the custom dither,
but do not claim enough Linux DRM, KMS, DKMS, or kernel-framework expertise to
independently guarantee every implementation detail. The source is published
for review and improvement, not as a claim of upstream kernel quality. Expert
review is welcome.

**YOU USE THIS EXPERIMENTAL DRIVER AND EVERY NON-EDID OR ABOVE-SPECIFICATION
MODE ENTIRELY AT YOUR OWN RISK. YOU ARE RESPONSIBLE FOR RECOVERY ACCESS,
BACKUPS, MODE SELECTION AND HARDWARE COMPATIBILITY. THE AUTHORS AND
CONTRIBUTORS ARE NOT RESPONSIBLE FOR LOSS OF DISPLAY, DATA, TIME, HARDWARE,
INCOME OR ANY OTHER DIRECT OR INDIRECT LOSS.**

The software is provided without warranty. See [LICENSE](LICENSE).
