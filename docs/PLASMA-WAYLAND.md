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
There is one more condition that a session may meet: kwin can start, log
`Failed to create framebuffer` with errno 22 and freeze the scanout, because it
asks for a buffer modifier the plane never advertised - a compositor
capability problem, not a driver defect. It is covered in sections 4.4 to 4.6,
with a one-variable workaround and a device-level fix in 0.6.7.

| Path | State | Detail |
| --- | --- | --- |
| Wayland session | yes, with the section 4.5 caveat | `startplasma-wayland` brings up kwin_wayland, Xwayland and plasmashell on the SM750 card node; the panel scans the composited frame (section 4). On a driver older than 0.6.7 a session can freeze the scanout through a rejected buffer modifier unless `KWIN_DRM_USE_MODIFIERS=0` is exported (section 4.4) |
| X11 session | yes, on `card0` since 2026-11-26 | a root Xorg on `:1`, started by the helper's `x11` mode, drives the same card at 1920x1080 and `kwin_x11` manages windows; the earlier evidence was a scratch X server only. See `docs/PLASMA-X11.md` and `docs/evidence/runtime/43-plasma-x11.txt` |
| X11 compositing | software only | the server has no GLX, so `kwin_x11` composites through its XRender path on llvmpipe and the desktop draws; no GLX-backed compositing exists on this host (section 7, `docs/PLASMA-X11.md` section 9) |
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

   On a module older than 0.6.7 add `KWIN_DRM_USE_MODIFIERS=0` to that
   environment; section 4.5 records what it changes and why it becomes
   redundant on 0.6.7.

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
from a userspace screenshot. Sections 4.4 to 4.6 record the opposite outcome -
a session whose scanout dies - because it is the failure most easily mistaken
for a driver fault.

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

### 4.4 The other outcome: compositing starts, then the scanout freezes

Sections 4.1 to 4.3 prove the healthy case. The same card, the same panel and a
session launched the same way also produced the opposite outcome once, and that
case is recorded here because it looks like a driver failure and is not.

kwin 6.7.5 initialised compositing, the screen went black while every process
stayed alive, and the session log filled with **359** lines of the shape

```text
kwin_wayland_drm: Failed to create framebuffer: <strerror(EINVAL) text>
```

The suffix is the localised `strerror(22)` text of the locale kwin runs in; the
errno is **22**, `EINVAL`. While those lines repeated, `PANEL_CURRENT_LINE` read
`0x00000000` and every screenshot region read `nonblack=0.0`: the compositor
process, plasmashell and Xwayland were all running, and the raster was dead
because the kernel rejected every framebuffer kwin asked it to create.

The driver is not the cause. It passes `NULL` as the `format_modifiers` argument
of `drm_simple_display_pipe_init()` at `src/sm750_drm.c:4624-4626`, and the
kernel documents that a driver which supports only the linear modifier may pass
NULL, in which case the plane advertises exactly `DRM_FORMAT_MOD_LINEAR`
(`/usr/src/kernels/7.3.4-100.fc43.x86_64/include/drm/drm_plane.h:885-886` and
`:929-930`). A direct probe confirmed that the plane is correct:

- `DRM_CAP_ADDFB2_MODIFIERS` reads `1`.
- The plane lists one format, `0x34325258`, and its `IN_FORMATS` blob contains
  `LINEAR`.
- `AddFB2` succeeds both with no modifier flag and with `LINEAR`.
- `AddFB2` fails with errno 22 only for a modifier the plane does not
  advertise, which is the correct answer; the NVIDIA card on this host answers
  the same way for the same request.

So the capability the driver advertises is right, and what kwin submits is a
modifier the plane never advertised. The kernel therefore refuses each
framebuffer, and the scanout keeps the buffer it already had, which is the black
one.

### 4.5 Workaround, and the 0.6.7 device-level fix

Measured workaround: launch the session with `KWIN_DRM_USE_MODIFIERS=0` in the
environment of section 3. kwin then logs

```text
kwin_wayland_drm: modifier support disabled by environment variable
```

the framebuffer failures are **zero**, and the scanout is live:
`PANEL_CURRENT_LINE` advances and the readback window reports `nonzero 262144`
with `crc32 0xe00643f1`, not the all-zero frame signature `0xe20eea22`.

The device-level fix, in 0.6.7, removes the need for the variable: the driver
sets `drm->mode_config.fb_modifiers_not_supported = 1` once, immediately after
the `drm->mode_config.funcs` selection (`src/sm750_drm.c:4604-4606`), so the
kernel reports `DRM_CAP_ADDFB2_MODIFIERS` as **0** to userspace, and every
client - kwin and any other that hits the same path - takes the modifiers-free
route by itself. On 0.6.7 or newer the environment variable is redundant, not
wrong: the capability it suppresses is no longer offered, so exporting it
changes nothing and a launcher that still sets it needs no change.

### 4.6 How to tell which case you are in

1. The session log names it: `grep 'Failed to create framebuffer' <session log>`
   is empty when the scanout is healthy and repeats the line of section 4.4 when
   it is not.
2. `cat /sys/module/sm750hdmidrm/version` says which driver answers: 0.6.7 or
   newer carries the device-level fix, older modules need the environment
   variable.
3. `sudo -n /usr/local/sbin/sm750-regs | grep CURRENT_LINE` says whether the
   raster is moving: a value that stays `0x00000000` across two reads is the
   freeze of section 4.4, an advancing value is a live scanout.

Diagnosis here is done from kwin's own log because `strace` cannot be attached
to kwin on this host: `ptrace(PTRACE_SEIZE, ...)` fails with the localised
`strerror(EPERM)` text, errno **1**. The compositor's log is the only trace
available, which is why the framebuffer line is worth knowing by name.

### 4.7 The same result with the fix loaded, and no override

Sections 4.4 to 4.6 describe an outcome seen on module 0.6.5 and a fix that
shipped in 0.6.7 but was then only built and gated. 0.6.7 has since been loaded
on this host by the hot reload of `docs/evidence/runtime/41-vt-hot-reload.txt`
section 10, and the fixed case was measured on the panel.

The session was started the same way as section 3 except that
`KWIN_DRM_USE_MODIFIERS` was explicitly unset (`env -u KWIN_DRM_USE_MODIFIERS`),
so no environment variable can be credited for the result. KWin discovers the
missing capability for itself and logs

```text
kwin_wayland_drm: drmModeAddFB2WithModifiers is not supported on GPU "/dev/dri/card0"
```

and reaches `kwin_core: OpenGL compositing has been successfully initialized`
with output PHL 243V7 in about a second, with plasmashell up about a second
later. `grep -c 'Failed to create framebuffer'` over the session log returns
**0**, where the 0.6.5 session of section 4.4 returned **359**. The raster
advanced (`PANEL_CURRENT_LINE` took three different values over three samples
two seconds apart), and twelve scanout samples five seconds apart all read
`nonzero 262144` with `crc32 0x976e751b` while the offset alternated between 0
and 4147200, so the scanout is a live double-buffered frame, not one frozen
buffer.

Chronology, stated once so it cannot be read backwards: the 0.6.5 session of
section 4.4 REQUIRED the override, section 4.5 records that override as the
workaround, and 0.6.7 makes it redundant because the driver refuses
modifier-flagged framebuffer creation for the whole device. Nothing in sections
4.4 to 4.6 is withdrawn by this one; it is the fixed case reaching the panel.

The two limits of section 5 are unchanged by this. A session that initialises
and scans still cannot be driven, because `/dev/input/event*` are unreadable to
this account, and it still cannot be screencast, because kwin's screencast
needs the PipeWire graph and system bus that the `NoopSession` bypass removes.
Both remain documented in section 5.

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

The X11 route is the second front, documented in `docs/PLASMA-X11.md` with its
transcript in `docs/evidence/runtime/43-plasma-x11.txt`. It was first measured
under a scratch X server (`Xvfb`, no DRM device) and, since 2026-11-26, on the
card itself through the helper's `x11` mode:

- `/usr/libexec/Xorg :1` runs as root - a non-root server cannot own a VT on
  this host - with the generated config whose `OutputClass` pins
  `/dev/dri/card0`. In the 2026-11-26 run the server was up in 4 s and
  `xorg.log` shows `modeset(0): Option "kmsdev" "/dev/dri/card0"`.
- On `card0`, `kwin_x11` held pid 1979033 at t=20 s, 40 s and 60 s with zero
  `crashing` lines, `card0-HDMI-A-1` read `connected` and `enabled=enabled`,
  `PANEL_CURRENT_LINE` advanced, and a 1920x1080 capture of `:1` was 1836586
  bytes. The route needs the six `/etc/environment` NVIDIA selections cleared
  for the session, or kwin crash-loops four times (A53).
- There is no GLX on that server: kwin composites through its XRender path on
  llvmpipe. GLX-backed compositing remains unavailable, and glamor refuses
  llvmpipe in this Xorg build (`/usr/lib64/xorg/modules/libglamoregl.so`
  prints `Refusing to try glamor on llvmpipe`), so there is no accelerated X11
  path either.

So the two routes differ in how the desktop is composed: Wayland gives a
GL-composited desktop on another card's render node, X11 gives a software
XRender one on this host's llvmpipe.

## 8. What this document does not claim

- It does not claim input works. It does not.
- It does not claim screencast or recording works. It does not.
- It does not claim the driver renders. It does not; it scans out, and the
  composition happens in kwin on another card's render node.
- It does not claim the scanout dump is byte-identical to the panel image; the
  correspondence test is structural and the window is 68 lines.
- It does not claim the buffer-modifier freeze is driver-side. The plane
  advertises exactly `DRM_FORMAT_MOD_LINEAR` and answers the probe correctly;
  what fails is a request kwin makes for a modifier that was never advertised
  (section 4.4).
- It does not claim this works on any other board, panel or host. One card, one
  panel, one host, one session.
