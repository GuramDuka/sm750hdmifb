<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Module parameters

Most parameters are read when `sm750hdmidrm` loads and cannot be changed at
runtime. Use `sm750hdmidrm.name=value` on the kernel command line or an
`options sm750hdmidrm ...` line in `/etc/modprobe.d/`. Runtime parameters
override build-time defaults.

Seven diagnostic parameters are deliberately writable after load:
`dma_batch_rows`, `staging_timing`, `test_pattern`,
`test_pattern_period_ms`, `test_pattern_anim_ms`, `crc_window_bytes` and
`a65_trace` are exposed with mode `0644`, so they can be changed through
`/sys/module/sm750hdmidrm/parameters/` to compare upload batching and timing
on a live system, to turn the test card on and off, to widen the scanout
readback window without reloading the module, or to trace the teardown of a
hot remove. Every other parameter is `0444`
and is fixed once the module is loaded.

## Everyday options

| Parameter | Default | Purpose |
|---|---:|---|
| `scanout_format` | `rgb565-bbdither` | `xrgb8888`, `rgb565`, or dithered `rgb565-bbdither`. The deprecated `rgb565-dither` alias remains accepted. |
| `dither_green_gain` | `94` | Green-channel gain from 0 to 100 for `rgb565-bbdither`. |
| `edid_only` | `1` | Use valid EDID modes instead of the driver catalogue. |
| `softscale_wide` | `0` | Add logical 2464/2560x1080 modes when `edid_only=0`. |
| `sharpen` | `0` | Apply fixed 8% sharpening after horizontal soft scaling. |
| `double_shadow` | `0` | Snapshot source rows and trim update regions to pixels that really changed. |
| `disable_hardware_cursor` | `0` | Set to `1` to use a software-rendered cursor instead of the 64x64 hardware plane. |
| `async_updates` | `1` | Copy reported changed regions into a latest-frame mailbox and perform scaling, dithering and VRAM upload on a dedicated worker. Set to `0` to restore synchronous updates for diagnosis. |
| `enable_dma` | `1` | Use optimized eight-row DMA1 uploads. Set to `0` to force write-combined CPU uploads. |
| `dma_batch_rows` | `16` | Writable through sysfs. Sampled once per update, clamped to 1-128 rows. Two staging buffers reserve 512 KiB each to support runtime comparisons. |
| `staging_timing` | `0` | Writable through sysfs. Log full-frame conversion/upload time and subsequent flip wait separately. Enable only during measurement. |
| `disable_dma` | `0` | Deprecated safety veto. If set, CPU uploads are forced even when `enable_dma=1`. |
| `backbuffer_staging` | `1` | Render an exact full-frame update into off-screen VRAM, then present it with the display controller's vblank-synchronised address flip. It is automatically unavailable when two scanout buffers do not fit. |
| `shadow_dma_min_bytes` | `4096` | Smallest aligned upload span sent through DMA1. The one-RGB565-scanline default avoids DMA setup overhead for small interactive updates. Valid range is checked at probe. |
| `crc_window_bytes` | `262144` | Writable through sysfs. Bytes read from the visible scanout offset for each CRC entry and by the `sm750_scanout` debugfs dump; the CRC source and the dump share one window, so widening it changes both. The value is sampled on every use, so a write takes effect on the next vblank or dump. Values below 4096 are raised to 4096, the length is rounded down to a multiple of 4 and clamped to the visible frame, so a larger write cannot read past it. Growing it to a whole frame is a diagnostic action, not something to poll: a full 1920x1080 XRGB8888 frame at pitch 7680 is 8294400 bytes, and the dump prints every byte in hex. |
| `a65_trace` | `0` | Writable through sysfs. Print an `A65: <step>` line through `pr_err` (stderr-level printk, visible at the default loglevel) while the driver tears down: every step of `sm750_pci_remove()` and the shadow-workqueue teardown. It is instrumentation for defect A65, off by default, and it runs only during teardown. Enable it before a controlled hot remove that is expected to wedge; the last mark names the step that was executing. See `docs/DEFECTS.md` A65 and `docs/evidence/runtime/52-a65-teardown-trace.txt`. |
| `test_pattern` | `auto` | Writable through sysfs. Test-card fallback when no client paints the panel: `off` never paints, `auto` paints only a frame that samples as entirely blank and is not owned by a userspace DRM master, `always` paints on every enable. Skipped on softscaled windows, below 320x200, and when the frame does not fit the VRAM left after the scanout offset. Inert, in every mode, while a scanout CRC source is armed: arming it cancels a running card and the flag stays set across a suspend/resume of the source. |
| `test_pattern_period_ms` | `5000` | Writable through sysfs. Milliseconds between test-card palette rotations; `0` keeps the palette static. Values outside 500-600000 ms are clamped once with a `drm_info` line. |
| `test_pattern_anim_ms` | `40` | Writable through sysfs. Milliseconds between test-card animation ticks (25 fps at the default); `0` stops the bouncing disc and leaves the card with the palette rotation only. Values outside 10-1000 ms are clamped once with a `drm_info` line. |
| `preferred_width` | `0` | Preferred exposed mode width; use with height and refresh. |
| `preferred_height` | `0` | Preferred exposed mode height. |
| `preferred_refresh` | `0` | Preferred integer refresh rate in hertz. |

## Board wiring

| Parameter | Default | Purpose |
|---|---:|---|
| `dvo_clock_phase` | `-1` | `-1` uses the board option-ROM strap, `0` rising edge, `1` falling edge. |
| `sii9024_scl` | `12` | SM750 GPIO used for SiI9024A software-I2C clock. |
| `sii9024_sda` | `13` | SM750 GPIO used for SiI9024A software-I2C data. |

Changing these can prevent transmitter detection. Defaults match the tested
`SE-DP750A-HDMI`; they are not generic SM750 wiring.

## Transmitter diagnostics

These switches exist to reproduce individual hardware investigations. They are
not normal configuration and may blank or destabilize the link.

| Parameter | Default | Diagnostic effect |
|---|---:|---|
| `sii9024_dvi` | `0` | Force DVI signalling through the HDMI connector. |
| `sii9024_falling_edge` | `0` | Sample the 24-bit input bus on the falling pixel-clock edge. |
| `sii9024_tpi_totals` | `1` | Program TPI raster totals as documented by the programming guide and board ROM. |
| `sii9024_no_termination` | `0` | Disable internal TMDS source termination for an isolated electrical test. |
| `sii9024_force_termination` | `0` | Explicitly enable source termination, including in the ROM replay path. Do not combine with `sii9024_no_termination`. |
| `sii9024_clean_init` | `0` | Omit inherited board-ROM compatibility writes and use only documented TPI initialization. |
| `sii9024_rom_exact` | `0` | Replay the board's 720p option-ROM initialization order. Limited diagnostic modes only. |
| `sii9024_rom_hdmi` | `0` | With `sii9024_rom_exact`, replace the final DVI enable with HDMI and a valid AVI InfoFrame. |
| `sii9024_force_black` | `0` | With `sii9024_rom_exact`, replace incoming RGB with transmitter-generated black while retaining sync/TMDS. |

## Build-time defaults

One package supports every profile. Separate DKMS variants are unnecessary.
To compile different defaults:

```sh
make \
  SM750_DRM_SCANOUT_DEFAULT=rgb565-bbdither \
  SM750_DRM_DEFAULT_EDID_ONLY=1 \
  SM750_DRM_DEFAULT_SOFTSCALE_WIDE=0 \
  SM750_DRM_DEFAULT_SHARPEN=0 \
  SM750_DRM_DEFAULT_DOUBLE_SHADOW=0 \
  SM750_DRM_DEFAULT_DISABLE_HARDWARE_CURSOR=0 \
  SM750_DRM_DEFAULT_ENABLE_DMA=1 \
  SM750_DRM_DEFAULT_ASYNC_UPDATES=1
```

`SM750_DRM_SCANOUT_DEFAULT` also accepts `xrgb8888` and `rgb565`.

## Sysfs attributes

These are not module parameters and are not writable. Since 0.6.4 the driver
publishes twelve read-only monitoring attributes on the PCI device, so they
appear as `/sys/class/drm/cardN/device/<name>`. They exist for
`tools/sm750-smi`; the tool keeps its libdrm, debugfs and `n/a` fallbacks, so
an older module still works. Format is what `sysfs_emit()` writes, one value
per file.

| Attribute | Format | Meaning |
|---|---|---|
| `mem_info_vram_total` | decimal bytes | Total VRAM. Same value as `vram_total_bytes`; the tool tries both names. |
| `vram_total_bytes` | decimal bytes | Total VRAM. |
| `vram_used_bytes` | decimal bytes | VRAM the driver reserves: the shadow front buffer, the staged backbuffer, the hardware cursor buffer and the DMA1 test buffer. Not total TTM usage; an exact VRAM-manager figure is not available on the shadow path. |
| `active_mode` | `WxH`, or empty | Active pipe's `hdisplay`x`vdisplay`. Empty when no pipe is enabled, which makes the tool fall back to the connector's modes list. |
| `active_mode_refresh_hz` | `NN.NN`, or empty | `drm_mode_vrefresh()` of the active mode, two decimals. |
| `active_mode_pixel_clock_khz` | decimal kHz, or empty | `mode->clock` of the active mode. |
| `hpd` | `0`, `1` or `-1` | SiI9024A hot-plug-detect bit. `-1` when the transmitter read fails. |
| `rxsense` | `0`, `1` or `-1` | SiI9024A receiver-sense bit. `-1` when the transmitter read fails. |
| `link_state` | `connected`, `receiver-only`, `hpd-only`, `disconnected`, or `unknown` | Derived from the same two bits. `unknown` when the read fails. |
| `active_crtc` | decimal index, or `-1` | Index of the enabled CRTC. `-1` when no pipe is enabled. |
| `vblank_count` | decimal | DRM core's vblank counter for the pipe, the one `drm_crtc_handle_vblank()` advances. |
| `crc_supported` | `0` or `1` | `1` only on kernels where the driver registers `.get_crc_sources` (`7.0.0` and later). |

`hpd`, `rxsense` and `link_state` read the transmitter's interrupt status over
the bit-banged i2c bus: two register reads, roughly a millisecond. They never
clear the latched event bits, so a monitoring read cannot consume a link event,
but they are not suitable for a tight polling loop.

### pm_probe

`/sys/bus/pci/devices/0000:01:00.0/pm_probe` is the one writable attribute the
driver publishes. Its mode is `0200`, so only root can write it, and it exists
only to call the driver's suspend and resume callback bodies from a running
system. Write one of three words:

| Write | Effect |
|---|---|
| `suspend` | Calls `sm750_pm_suspend()` once and logs its return value. |
| `resume` | Calls `sm750_pm_resume()` once and logs its return value. |
| `cycle` | Calls suspend, then resume only if suspend returned 0. A failed suspend logs `resume skipped` and nothing is resumed. |

Three guards run before either callback, each refusing with an error and a
`pm probe: refused: ...` line: a DRM client holds master (`-EBUSY`); the device
is not registered with DRM, so `sdev->drm.dev` is NULL (`-EBUSY`); or
`drm_dev_enter()` fails because the device is unplugged or already shutting
down (`-EBUSY`). A missing driver-data pointer is refused as well (`-ENODEV`);
that case can only be logged with `pr_info()`, because there is no DRM device
to name. A dedicated mutex serialises concurrent probes, and the callback runs
inside the `drm_dev_enter()` / `drm_dev_exit()` bracket.

The write returns the byte count on success, `-EINVAL` for anything that is not
one of the three words, and the callback's own non-zero return otherwise. A
failing callback therefore makes `echo cycle > pm_probe` fail, and a script
under `set -e` stops at that line. The kernel log carries the evidence, and the
wording differs per command:

| Write | Result lines in the kernel log |
|---|---|
| `suspend` | `pm probe: command suspend`, then `pm probe: suspend returned <n>` |
| `resume` | `pm probe: command resume`, then `pm probe: resume returned <n>` |
| `cycle` | `pm probe: command cycle`, then one of `pm probe: cycle suspend failed: <n>, resume skipped`, `pm probe: cycle suspend ok, resume failed: <n>`, or `pm probe: cycle suspend ok, resume ok` |

`<n>` is the callback return value; the guarded paths return 0. The three
`cycle` lines are the only result a guarded cycle writes, and a consumer that
matched only `<cmd> returned <n>` therefore read a successful `cycle` as a
missing result line. That was defect A67, fixed in `tools/sm750-pm-probe.sh`
and pinned against the literals above by `tests/check-pm-probe.sh` section k,
so a drift in either file fails `make check`
(`docs/evidence/runtime/50-pm-probe-cycle.txt`).

This is NOT a system sleep. It calls the driver's callback bodies only: there
is no PCI config space save and restore, the device never enters D3hot, and no
power state changes. A pass here says the callbacks run and return 0; it is not
evidence that system sleep works, because the parts of a real cycle the driver
does not own - PCI core state, the platform wake path, the firmware and every
other device on the bus - are not exercised.

Intended use: reach the callbacks without a system-wide cycle. On the reference
host two neighbouring Tesla P100s refused `pm_test=devices`
(`docs/DEFECTS.md` A66); the owner then set
`nvidia.NVreg_PreserveVideoMemoryAllocations=0` and the armed devices cycle
passed on 2026-11-27
(`docs/evidence/runtime/49-pmtest-devices-cycle.txt`). The attribute remains a
convenience for a running system, not the measurement itself.
