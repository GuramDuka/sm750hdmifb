<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Register reference and runtime dump

This file is the tracked register reference for the driver. The authoritative
vendor document (SM750/SM750G datasheet) is not redistributable, so the table
below records the offsets the driver actually uses, taken from
`src/ddk750_reg.h`.

## Reading registers on a live system

`/dev/mem` cannot be used: the kernel is built with `CONFIG_STRICT_DEVMEM=y` and
`CONFIG_IO_STRICT_DEVMEM=y`, and the PCI BAR is mode `0600`. The driver
therefore exposes its own read-only dump:

```sh
card=$(readlink -f /dev/dri/by-path/pci-0000:01:00.0-card)
minor=${card##*/card}
sudo cat /sys/kernel/debug/dri/$minor/regs
```

The directory is named after the DRM minor, which equals the `cardN` suffix and
is assigned in probe order; resolve it as above instead of assuming `0`. The
card registers no render node, so the by-path `-card` link is its only stable
handle. `/usr/local/sbin/sm750-regs` performs the same resolution.

- Registered from `.debugfs_init` (`src/sm750_drm.c:3363` for the TTM driver,
  `src/sm750_drm.c:3376` for the shadow-buffer driver) through
  `debugfs_create_file("regs", 0444, ...)` at `src/sm750_drm.c:3337`.
- Read handler `sm750_regs_show()` at `src/sm750_drm.c:3312`, attribute created
  by `DEFINE_SHOW_ATTRIBUTE(sm750_regs)` at `src/sm750_drm.c:3333`.
- Inert until read; performs only `readl()`, guarded by `drm_dev_enter()` /
  `drm_dev_exit()`. The automated check in `tests/check-drm-module.sh` fails if
  the handler ever gains a write.
- Reading requires root because `/sys/kernel/debug` is mode `0700`. Without
  root the read is a documented gap, not a driver failure.

Output format:

```
# sm750hdmidrm register dump, 49 registers, read-only
0x000000 SYSTEM_CTRL                  0x00000000
```

## Reported registers

49 registers, table order as in `sm750_reg_dump_registers[]`
(`src/sm750_drm.c:3260`).

| Offset | Register | Block |
| --- | --- | --- |
| 0x000000 | SYSTEM_CTRL | system |
| 0x000004 | MISC_CTRL | system |
| 0x000008 | GPIO_MUX | system / GPIO |
| 0x000040 | CURRENT_GATE | system clock |
| 0x000044 | MODE0_GATE | system clock |
| 0x000048 | MODE1_GATE | system clock |
| 0x00004C | POWER_MODE_CTRL | system power |
| 0x000054 | DEVICE_ID | system |
| 0x00005C | PANEL_PLL_CTRL | panel PLL |
| 0x000060 | CRT_PLL_CTRL | CRT PLL |
| 0x000070 | MXCLK_PLL_CTRL | memory clock PLL |
| 0x000088 | VGA_CONFIGURATION | VGA |
| 0x010000 | GPIO_DATA | GPIO |
| 0x010004 | GPIO_DATA_DIRECTION | GPIO |
| 0x010008 | GPIO_INTERRUPT_SETUP | GPIO |
| 0x080000 | PANEL_DISPLAY_CTRL | panel |
| 0x080004 | PANEL_PAN_CTRL | panel |
| 0x080008 | PANEL_COLOR_KEY | panel |
| 0x08000C | PANEL_FB_ADDRESS | panel |
| 0x080010 | PANEL_FB_WIDTH | panel |
| 0x080014 | PANEL_WINDOW_WIDTH | panel |
| 0x080018 | PANEL_WINDOW_HEIGHT | panel |
| 0x08001C | PANEL_PLANE_TL | panel |
| 0x080020 | PANEL_PLANE_BR | panel |
| 0x080024 | PANEL_HORIZONTAL_TOTAL | panel timing |
| 0x080028 | PANEL_HORIZONTAL_SYNC | panel timing |
| 0x08002C | PANEL_VERTICAL_TOTAL | panel timing |
| 0x080030 | PANEL_VERTICAL_SYNC | panel timing |
| 0x080034 | PANEL_CURRENT_LINE | panel status |
| 0x0800F0 | PANEL_HWC_ADDRESS | hardware cursor |
| 0x0800F4 | PANEL_HWC_LOCATION | hardware cursor |
| 0x0800F8 | PANEL_HWC_COLOR_12 | hardware cursor |
| 0x0800FC | PANEL_HWC_COLOR_3 | hardware cursor |
| 0x080040 | VIDEO_DISPLAY_CTRL | video plane |
| 0x080044 | VIDEO_FB_0_ADDRESS | video plane |
| 0x080048 | VIDEO_FB_WIDTH | video plane |
| 0x08004C | VIDEO_FB_0_LAST_ADDRESS | video plane |
| 0x080050 | VIDEO_PLANE_TL | video plane |
| 0x080054 | VIDEO_PLANE_BR | video plane |
| 0x080100 | ALPHA_DISPLAY_CTRL | alpha plane |
| 0x080104 | ALPHA_FB_ADDRESS | alpha plane |
| 0x080200 | CRT_DISPLAY_CTRL | CRT |
| 0x080204 | CRT_FB_ADDRESS | CRT |
| 0x080208 | CRT_FB_WIDTH | CRT |
| 0x08020C | CRT_HORIZONTAL_TOTAL | CRT timing |
| 0x080220 | CRT_CURRENT_LINE | CRT status |
| 0x080224 | CRT_MONITOR_DETECT | CRT status |
| 0x100054 | DE_STATE1 | display engine |
| 0x100058 | DE_STATE2 | display engine |

### Deliberately excluded

`RAW_INT` (0x000020), `INT_STATUS` (0x000024) and `GPIO_INTERRUPT_STATUS`
(0x01000C) are read-to-clear. Dumping them would consume pending interrupt
state, so they are left out to keep a before/after dump around one modeset
side-effect free.

## Known specification conflict

`GPIO_DATA_DIRECTION` is `0x010004` in `src/ddk750_reg.h:471` while the vendor
datasheet places it at `0x010008`. The driver value is the empirically working
one on the tested `SE-DP750A-HDMI` board and must not be changed without
hardware evidence; see `docs/HARDWARE.md:23`.
