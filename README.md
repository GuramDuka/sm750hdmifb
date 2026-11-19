<!-- SPDX-License-Identifier: GPL-2.0-only -->
# SM750 HDMI DRM Driver

**Push this card to real 2048-wide output or a software-scaled 2560x1080
ultrawide desktop, with bandwidth-saving colour conversion and update
optimisations for smoother performance.**

Linux display driver for the single-HDMI `SE-DP750A-HDMI` PCIe card. Current
release **0.6.0**: atomic KMS, dithered 16-bit scanout, hardware cursor, DMA and
polling upload paths, DKMS packages for `.deb` and `.rpm`, and an acceptance
verdict of 6 PASS / 0 FAIL / 1 GAP.

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

Release 0.6.0. The driver is feature-complete for this board and meets the
project's production criteria except for one item that needs a person at the
panel; see the [acceptance report](docs/ACCEPTANCE-REPORT.md).

| Area | Verified state |
|---|---|
| Module | `sm750hdmidrm` 0.6.0, built by DKMS from one source tree |
| Runtime | built and installed by DKMS for kernels 7.2.15-100, 7.3.3-100 and 7.3.4-100 (Fedora 43), loaded and exercised on 7.3.4-100 |
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
sudo apt install ./dist/sm750hdmifb_0.6.0_all.deb
sudo reboot
```

`make check` needs `pkg-config`, the libdrm development headers (`libdrm-dev`
on Debian and Ubuntu, `libdrm-devel` on Fedora) and `rg` from ripgrep. The
`check-deps` preflight target stops with an install hint when one is missing.

### Fedora and other RPM distributions

`packaging/sm750hdmifb.spec` builds the same DKMS package as a `noarch` RPM, so
the installed file set matches the `.deb` and DKMS compiles the module against
each installed kernel:

```sh
sudo dnf install rpm-build gcc make dkms kernel-devel libdrm-devel pkgconf-pkg-config ripgrep git tar
git clone https://github.com/GuramDuka/sm750hdmifb.git
cd sm750hdmifb

work=$(mktemp -d) && topdir=$work/rpmbuild
mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}
. ./packaging/source-excludes.sh
mapfile -t skip < <(sm750_dev_only_pathspecs)
git ls-files -z -- . "${skip[@]}" >"$work/tracked"
tar -C . -czf "$topdir/SOURCES/sm750hdmifb-0.6.0-source.tar.gz" \
    --transform='s|^|sm750hdmifb-0.6.0/|' --null -T "$work/tracked"

rpmbuild -ba --define "_topdir $topdir" packaging/sm750hdmifb.spec
sudo dnf install -y "$topdir"/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm
sudo reboot
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

**Built on 6.17 through 7.4, runtime-validated on 7.3.4.** Release 0.6.0 is
installed by DKMS for the Fedora 43 kernels 7.2.15-100, 7.3.3-100 and
7.3.4-100, and was loaded and exercised on 7.3.4-100, the reference host
kernel. The other two are built and installed but have not been booted. Linux
7.4 is still in development: only its headers have been compiled against, so it
remains untested at runtime. See the
[0.6.0 release notes](docs/RELEASE-NOTES.md) and the
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
| `SiI9024A receiver not ready after 2000 ms: HPD=1 RSEN=0 status=04; enabling for compatibility` | Hot-plug and DDC are present, but the sink does not report a TMDS receiver for 100 ms - normal behind a KVM switch or a passive HDMI-DVI adapter. A forced mode needs no DDC, so the transmitter is programmed anyway and the probe succeeds (`src/sii902x.c:576`) |
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

The card registers no render node, so `/dev/dri/by-path/pci-0000:01:00.0-card`
is the only stable handle for it; the `renderD*` nodes on a multi-GPU host
belong to other cards.

The file is mode `0444` and lives under the DRM minor's debugfs directory, so
reading it requires root. It is inert until read, never writes to the device,
and deliberately omits the read-to-clear registers (`RAW_INT`, `INT_STATUS`,
`GPIO_INTERRUPT_STATUS`) so a dump taken before and after one modeset stays
comparable. The dump is a stable `0x<offset> <name> 0x<value>` table; see
[docs/REGISTERS.md](docs/REGISTERS.md) for the list of reported registers.

### Framebuffer console

The driver sets up fbdev emulation through `DRM_FBDEV_TTM_DRIVER_OPS` and
`drm_client_setup()`. A `/dev/fb0` node appears only when the kernel is built
with fbdev emulation and no other framebuffer driver already owns the device.
KMS output works without it, so a missing `/dev/fb0` is not a driver fault.

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
  `docs/DEFECTS.md`). The console still reaches the panel; only the character
  device is missing.
- The monitor stays attached to the SM750 HDMI connector: `card0-HDMI-A-1`
  reports `connected` at every probe, and nothing detaches it.
- The user's desktop runs on the NVIDIA GTX 1070, not on the SM750. On this
  host `card1` is `0000:02:00.0` with `card1-DVI-D-1` connected and
  `kwin_wayland` running against it; `card0` has no userspace DRM master.

So the SM750 is a second, permanent output that shows the console, and the
graphical session is unaffected by anything done to it. A modeset on `card0`
from a test tool temporarily replaces the console; closing the tool lets the
fbdev client restore its own 1920x1080 mode.

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
- [VBIOS reconstruction](docs/VBIOS-REVERSE-ENGINEERING.md) - 239-region map and the C model of the option ROM
- [Acceptance report](docs/ACCEPTANCE-REPORT.md) - criterion-by-criterion verdict with evidence paths
- [Project logbook](docs/LOGBOOK.md) - chronological record, newest entry last
- [Host root actions](docs/ROOT-ACTIONS.md) - sudoers, helpers, udev rule, recovery
- [CI recipe](docs/ci/build.yml) - inactive: GitHub Actions is disabled for this repository, the file is a copy-paste recipe

Four verification targets are opt-in and deliberately outside `make check`, so
the default gate stays the same 17 commands on machines without the analysers:

```sh
make static       # sparse, smatch, cppcheck, coccinelle, pahole against src/
make vbios-re     # rebuild the option ROM and compare it byte for byte
make vbios-trace  # execute both images and compare their instruction traces
make crc-check    # live scanout CRC and sm750_scanout readback on the card
```

`make vbios-re` and `make vbios-trace` need the captured image
(`VBIOS_ROM=...`, or the default path) and print `SKIP` with exit 0 when it is
absent, so a fresh checkout without the image still passes; the trace target
also needs `qemu-system-i386`, `gdb`, `capstone` and `unicorn`. `make static`
prints a skip message when the analysers are missing. `make crc-check` needs
the SM750 card, root and a mounted debugfs; without them it prints one
`SKIP:` line and the target turns its exit code 77 into success. The static,
VBIOS and scanout checks are documented in
[static analysis](docs/STATIC-ANALYSIS.md),
[VBIOS reconstruction](docs/VBIOS-REVERSE-ENGINEERING.md) and
[test strategy](docs/TEST-STRATEGY.md).

### Gates and test scripts

| Entry point | What it covers |
|---|---|
| `make check` | The 17 default checks: kernel build, policy checks for the module and DRM code, packaging hygiene, shadow and staging units, vblank timer |
| `tests/build-all-kernels.sh` | The 9-combination kernel and scanout-format build matrix |
| `tests/check-rpm-dkms.sh` | RPM payload against `git ls-files`, scriptlets, dependencies, sandbox DKMS build; no root needed |
| `tests/check-vblank <card> <hz>` | Live vblank rate against the programmed refresh |
| `tests/audit-release.sh` | Release tarball contents, version consistency and archive drift |
| `tests/check-static.sh` | Opt-in static analysis gate with baseline comparison |
| `make crc-check` | Opt-in live scanout readback: enables the CRTC CRC source `scanout`, checks that entries arrive, stay constant for a static frame, change with the content and agree with the `sm750_scanout` debugfs dump; exits 77 (a skip) without root, card or an active CRTC |

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
