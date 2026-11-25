<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Plasma on this driver: Wayland and X11

This is the permanent answer to "can Plasma run on this driver". It records one
measured session on the reference host, the two blocks that were believed to
prevent it, why each turned out to be surmountable, the exact recipe, and what
is still missing. The transcript behind every number here is
`docs/evidence/runtime/37-plasma-wayland.txt`.

## 1. Verdict

**Verdict: yes.** A full Plasma 6.7.5 Wayland session (kwin 6.7.5, Mesa
25.3.6, Fedora 43, kernel 7.3.4-100) runs on this driver and its frames reach
the panel, with the two workarounds in section 3 and the limits in section 5.

| Path | State | Detail |
| --- | --- | --- |
| Wayland session | yes | `startplasma-wayland` brings up kwin_wayland, Xwayland and plasmashell on the SM750 card node; the panel scans the composited frame (section 4) |
| X11 session | yes | Xorg on `:1` drives the same card at 1920x1080, kwin_x11 manages windows |
| X11 compositing | no | the server's GLX is DRISWRAST and lacks `GLX_EXT_texture_from_pixmap`; kwin_x11 aborts its compositor (section 7) |
| Input | no | no `/dev/input/event*` access for this account, so the session draws but cannot be driven (section 5) |
| Screencast | no | kwin's screencast needs PipeWire and the system bus, both removed by the bypass (section 5) |
| Full-frame readback | yes in 0.6.6 | `crc_window_bytes` became runtime-writable in 0.6.6, so the whole 8294400-byte frame can be read; in 0.6.5 the window was fixed at 256 KiB / 68 scanlines (section 5) |

The session was run as the service account (uid 1005). Nothing in it required
root, and nothing touched the host owner's Plasma session on seat0 or the
owner's own GPU.

## 2. What blocked Wayland, and why both blocks were surmountable

Two statements were treated as barriers before the run. Neither is a driver
defect, and both were bypassed by a measured route.

### 2.1 "No accelerated render device"

kwin's `KWin::GpuManager::addDevice` filters RENDER devices only: it calls
`RenderDevice::isSoftwareDevice` and, for a device without hardware
acceleration, merely logs

```text
kwin_core: Ignoring render device %s without hardware acceleration
```

and drops it. OUTPUT devices take a different path, `KWin::DrmDevice::
openWithAuthentication`, which is not subject to that filter. So the SM750 was
never refused as an output: an accelerated NVIDIA render node plus the SM750 as
output works, and the driver's own render node (0.6.5, `DRIVER_RENDER`) is
accepted as a render node too even though it is software-only, which kwin
tolerates for output devices.

Conclusion: the missing acceleration was a **preference, not a barrier**. Mesa
still ships no SM750 driver (`docs/evidence/runtime/36-render-node.txt` section
8.4), so no SM750 pixel work is accelerated by this route; the SM750 is the
output, and the acceleration comes from another card's render node.

### 2.2 "No logind seat"

This one is real at the logind level. `session_device_new()` in systemd's
`logind-session-device.c` returns `-EPERM` for a session without a seat, at

```c
if (!s->seat)
        return -EPERM;
```

so `TakeDevice` fails for this remote session (session 7, `Seat=` empty).

Measured bypass: make the system bus unreachable with
`DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/sysbus`. `KWin::Session::
create()` cannot reach logind, falls through to `KWin::NoopSession`, and kwin
opens the DRM node directly. The session then has a compositor without a seat.

Two related non-facts, measured so nobody re-invests in them:

- kwin 6.7.5 does not link libseat at all, so `LIBSEAT_BACKEND` and `seatd` are
  irrelevant to it.
- `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` is a no-op here; it changed nothing.

## 3. The working session: recipe

Everything runs as the service account, with no root and no privilege helper.

1. Private runtime directory, mode `0700`:

   ```sh
   runtime=<runtime>
   mkdir -p "$runtime" && chmod 700 "$runtime"
   ```

2. Private session bus on it:

   ```sh
   dbus-daemon --session --nofork --nopidfile \
       --address=unix:path="$runtime/bus" &
   ```

3. Environment, with any inherited display variables removed:

   ```sh
   env -u WAYLAND_DISPLAY -u DISPLAY \
       XDG_RUNTIME_DIR="$runtime" \
       DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
       DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/sysbus \
       KWIN_DRM_DEVICES=/dev/dri/card0 \
       KWIN_RENDER_NODES=/dev/dri/renderD128 \
       QT_FORCE_STDERR_LOGGING=1 \
       startplasma-wayland
   ```

   On this host `renderD128` is the **SM750** render node and `renderD129` to
   `renderD131` are the NVIDIA cards - the opposite of what the numbering
   suggests, so resolve the node by
   `/dev/dri/by-path/pci-0000:01:00.0-render` rather than by number.

4. Measured outcome in the session log:

   ```text
   compositing has been successfully initialized
   kwin_wayland_drm: New output on GPU /dev/dri/card0: PHL 243V7
   drmModeAddFB2WithModifiers is supported on GPU "/dev/dri/card0"
   Using Atomic Mode Setting on gpu "/dev/dri/card0"
   Number of planes on GPU "/dev/dri/card0" : 2
   ```

5. Processes present afterwards: `startplasma-wayland`,
   `kwin_wayland_wrapper --xwayland`, `kwin_wayland --wayland-fd 7 --socket
   wayland-0`, `Xwayland :1` and `plasmashell`.

## 4. Proof that the panel scans the composited frame

Three independent readings. The first two come from the root helpers, the third
from a userspace screenshot.

### 4.1 Panel registers (`sm750-regs`)

```text
PANEL_FB_ADDRESS      = 0x003f4800
PANEL_FB_WIDTH        = 0x0f000f00     (pitch 3840, RGB565)
PANEL_WINDOW_WIDTH    = 0x077f0000
PANEL_WINDOW_HEIGHT   = 0x04370000
PANEL_CURRENT_LINE    advancing
```

The display engine is pointed at a framebuffer and its scanline counter moves.

### 4.2 Scanout window (`sm750-crc dump`, the `sm750_scanout` debugfs dump)

```text
offset   4147200        (1920 * 1080 * 2 bytes)
length   262144
nonzero  262144
crc32    0x976e751b     identical across three consecutive dumps
```

Contrast with the same dump taken earlier in a kwin-only run:

```text
offset   0
nonzero  0
crc32    0xe20eea22     (the crc32 of 256 KiB of zeros)
PANEL_FB_ADDRESS 0x00000000
```

So the earlier black panel was real, and the difference is that a full session
- plasmashell presenting frames, not just a compositor with nothing to show -
puts content at the offset the panel register points at.

### 4.3 Screenshot cross-check (`spectacle`)

`grim` does **not** work here: kwin has no `zwlr_screencopy` and needs its own
screencast protocol over PipeWire. `spectacle -b -n -o <file>.png` does work
through its own capture path and produced a 1920x1080 PNG of a live desktop
with a non-black sample fraction of 0.9999.

Correspondence test: the 262144-byte RGB565 dump was decoded at pitch 3840
(1920 px) and compared with the same scanlines of that PNG at identical
sampling. The two ASCII luminance maps matched in structure - the same bright
vertical band at the same columns, the same dark field, the same isolated
markers.

Honest limits of that test: the dump window was 256 KiB, which is 68 of 1080
scanlines, because `crc_window_bytes` defaults to 262144 and was mode `0444`
until 0.6.6 made it writable; the dump's start offset alternates between 0 and
4147200 because the
driver double-buffers; and RGB565 with blue-noise dithering is not byte
identical to an RGB888 screenshot, so the comparison is **structural, not
bit-exact**.

## 5. Limits that remain

1. **No input devices.** `/dev/input/event*` are `root:input` mode `0660` with
   no ACL for this account, so the session has no keyboard and no pointer. The
   desktop draws and is stable but cannot be driven. A real VT login (a
   non-remote session) would give a seat and device access; the alternative
   under evaluation is `org.freedesktop.portal.RemoteDesktop`, which the
   private session's portal advertises together with `InputCapture`,
   `ScreenCast` and `GlobalShortcuts` on `/org/freedesktop/portal/desktop`,
   because kwin authorized `xdg-desktop-portal-kde` for
   `org_kde_kwin_fake_input`.
2. **No screencast or screen recording.** kwin's screencast needs a PipeWire
   graph and the system bus, and both were deliberately removed by the
   `NoopSession` bypass of section 2.2. `grim` fails with `compositor doesn't
   support the screen capture protocol` and spectacle's video mode aborts with
   exit code 134. Still images through spectacle's own capture path do work.
3. **The VRAM readback window was capped at 256 KiB / 68 scanlines until
   0.6.6.** A full 1920x1080 XRGB8888 frame is 8294400 bytes. In 0.6.5 the
   module parameter `crc_window_bytes` had mode `0444`, so neither this account
   nor root could widen it. 0.6.6 makes it `0644` and the reader's existing
   clamp bounds any write by the visible scanout area, so
   `echo 8294400 > /sys/module/sm750hdmidrm/parameters/crc_window_bytes` is
   enough for a full-frame dump. It stays a diagnostic action, not a poll: one
   256 KiB dump already takes about 1.24 s, so a full frame is far slower than
   any frame rate.

## 6. How to reproduce from a clean boot

No step here needs the host owner, and none needed root. Two prerequisites are
host state rather than repository state: the module is loaded and bound to
`0000:01:00.0`, and the account has read-write access to `/dev/dri/card0`
(the udev ACL of `docs/ROOT-ACTIONS.md`).

| Step | Needs owner action | Check |
| --- | --- | --- |
| 1. Confirm the SM750 is bound to this driver | no | `lspci -nnk -d 126f:0750` shows `Kernel driver in use: sm750hdmidrm` |
| 2. Resolve the card and render nodes by path | no | `/dev/dri/by-path/pci-0000:01:00.0-card` and `-render` resolve; the render link only exists from 0.6.5 |
| 3. Create the private runtime dir and session bus | no | `dbus-daemon` listens on `$runtime/bus` |
| 4. Export the environment of section 3 and run `startplasma-wayland` | no | `compositing has been successfully initialized` appears in the log |
| 5. Confirm the four processes | no | `pgrep -a 'kwin_wayland|plasmashell|Xwayland'` |
| 6. Read the panel registers and the scanout window | yes, root helpers | `sm750-regs`, `sm750-crc dump`; see `docs/ROOT-ACTIONS.md` for the allowlist |
| 7. Cross-check with a screenshot | no | `spectacle -b -n -o /mega/tmp/sm750/wayland-barriers/desktop.png` |

The root helpers in step 6 already exist in the sudoers allowlist; nothing new
has to be granted for this procedure.

## 7. X11 comparison

The X11 route works and was measured in the same session family:

- Xorg starts as `/usr/libexec/Xorg :1` with the shipped `OutputClass` config
  and drives `card0` at 1920x1080; `plasmashell` and `kwin_x11` run and window
  management works.
- X11 compositing is **impossible** on this host: the server's GLX is
  `DRISWRAST` and lacks `GLX_EXT_texture_from_pixmap`, so `kwin_x11` aborts its
  compositor with `No provider of glXBindTexImageEXT found`.
- glamor refuses llvmpipe in this Xorg build: `/usr/lib64/xorg/modules/
  libglamoregl.so` prints `Refusing to try glamor on llvmpipe`, and no
  environment variable reaches the `Allowing glamor on llvmpipe for PRIME`
  string. There is therefore no accelerated X11 path either.

So the two routes differ in exactly one respect that matters: Wayland gives a
composited desktop on this driver, X11 gives an uncomposited one.

## 8. What this document does not claim

- It does not claim input works. It does not.
- It does not claim screencast or recording works. It does not.
- It does not claim the driver renders. It does not; it scans out, and the
  composition happens in kwin on another card's render node.
- It does not claim the scanout dump is byte-identical to the panel image; the
  correspondence test is structural and the window is 68 lines.
- It does not claim this works on any other board, panel or host. One card, one
  panel, one host, one session.
