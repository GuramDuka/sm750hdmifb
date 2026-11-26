<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Plasma over X11 on this driver

This is the X11 counterpart to [PLASMA-WAYLAND.md](PLASMA-WAYLAND.md): the same
card, the same host, a second front. It records why an X server on this machine
needs root, the server configuration that parses, the desktop-wide environment
that made `kwin_x11` crash four times before it stayed up, the runs that clear
it, and what the result proves and does not prove. The transcript behind every
number here is
[`docs/evidence/runtime/43-plasma-x11.txt`](evidence/runtime/43-plasma-x11.txt).

## 1. Verdict

**Verdict: Plasma over X11 runs on this card.** Since 2026-11-26 a root X
server from the helper's `x11` mode drives `card0`, and `kwin_x11` manages
windows on it with one stable pid and zero crash lines. The route needs two
non-obvious things - root for the server, because a non-root `Xorg` cannot own a
virtual console here, and the desktop-wide NVIDIA selection from
`/etc/environment` cleared for the session, because otherwise `kwin_x11`
crash-loops. It renders in software. Neither requirement is a driver defect.

| Path | State | Detail |
| --- | --- | --- |
| X11 stack on the host | present | `plasma-workspace-x11` 6.7.6, `kwin-x11` 6.7.6, `kwin` 6.7.6, `xorg-x11-server-Xorg` 21.1.26 (section 2) |
| X server on `card0` as `coder` | no | the server parses the config and reaches the driver, then dies with `xf86OpenConsole: Cannot open virtual console 1 (Permission denied)`; owning a VT needs root (section 3) |
| X server on `card0` as root | yes, 2026-11-26 | the helper's `x11` mode reached display `:1` in 4 s with `modeset(0): Option "kmsdev" "/dev/dri/card0"` (section 11) |
| `kwin_x11` as a window manager | yes, on `card0` since 2026-11-26 and earlier on a scratch X server | pid 1979033 identical at t=20 s, 40 s and 60 s, zero crash lines, and a 1836586-byte 1920x1080 capture of display `:1` (sections 7, 11) |
| Panel output through X11 | OBSERVED 2026-11-26 | `card0-HDMI-A-1` `connected` with `enabled=enabled`, a content scanout window and `PANEL_CURRENT_LINE 0x00000419` (section 11) |
| Input devices | none, by design | the generated server config opens none, so the session cannot be typed into; the log's `Failed to load module "mouse"` and `"kbd"` lines are that design, not a failure (sections 5, 11) |
| Acceleration | no | the server has no GLX; kwin composites through XRender on llvmpipe (section 9) |

## 2. The X11 stack on this host

All four packages are installed and current for this host:

| Package | Version |
| --- | --- |
| `plasma-workspace-x11` | 6.7.6 |
| `kwin-x11` | 6.7.6 |
| `kwin` | 6.7.6 |
| `xorg-x11-server-Xorg` | 21.1.26 |

The real server binary is `/usr/libexec/Xorg`, 2507936 bytes, mode `0755`, and
**not** setuid. `/usr/bin/Xorg` is a small wrapper script. Anything that starts
"Xorg" through `PATH` runs the wrapper, so the helper names the real binary
(`tools/sm750-headless.sh:239`) and the gate rejects an arm that reaches a
setuid wrapper (`tests/check-headless-helper.sh:280-281`).

## 3. Why the server needs root: the virtual console

Measured as `coder`, with no privilege: the server parses its configuration and
reaches the driver exactly as it should, and the log carries

```text
(++) Using config file
(II) xfree86: Adding drm device (/dev/dri/card0)
(**) OutputClass "SM750 HDMI DRM" setting /dev/dri/card0 as PrimaryGPU
```

and then it terminates with

```text
(EE) xf86OpenConsole: Cannot open virtual console 1 (Permission denied)
(EE) Server terminated with error (1). Closing log file.
```

The reason is ownership of the console device, not of the card: `/dev/tty0` is
`crw-rw----+ root tty` and `/dev/tty1` is `crw------- duka tty`, and the
active-VT ACL belongs to the session owner (`duka`), not to this account. A real
X11 session on `card0` therefore needs the server running as root - the standard
arrangement on any desktop host, and not a driver defect. Nothing this
repository ships can change it: the alternative is a seat that hands the VT to
the session, which is a session-manager matter.

## 4. `-config` must be a relative path

Once the server is privileged it refuses an absolute configuration path:

```text
With elevated privileges -config must specify a relative path without any ".." elements.
```

The working invocation therefore runs from the directory that holds the
configuration and passes a bare filename. The helper does exactly that: it
writes the file into the run directory, changes into that directory and passes
`-config sm750-x11.conf`
(`tools/sm750-headless.sh:334-336`). The gate pins both halves - the `cd` is
required and an absolute or `..`-bearing `-config` argument is rejected
(`tests/check-headless-helper.sh:282-288`).

## 5. The generated server config, and what each option buys

The helper generates the file once per run (`tools/sm750-headless.sh:128-155`)
rather than shipping a second file, so it stays one installable unit and the
config can live next to the server's working directory as section 4 requires.
The configuration proven to parse under Xorg 21.1.26 is:

```text
Section "ServerFlags"
	Option "AutoAddDevices" "false"
	Option "AutoAddGPU" "false"
	Option "DontVTSwitch" "true"
	Option "DontZap" "true"
EndSection

Section "Device"
	Identifier "SM750 HDMI"
	Driver "modesetting"
	Option "kmsdev" "/dev/dri/card0"
	Option "AccelMethod" "none"
	Option "ShadowFB" "true"
	Option "PrimaryGPU" "true"
EndSection

Section "Screen"
	Identifier "SM750 screen"
	Device "SM750 HDMI"
EndSection

Section "ServerLayout"
	Identifier "SM750 layout"
	Screen "SM750 screen"
EndSection
```

| Section and option | What it buys |
| --- | --- |
| `ServerFlags` / `AutoAddDevices` `false` | no input device is opened at all; with no `InputDevice` section either, the root server cannot take the owner's keyboard or mouse, which is the same guarantee the compositor arms get from a mount namespace (A49) |
| `ServerFlags` / `AutoAddGPU` `false` | the NVIDIA cards are not added to this server; only the pinned `kmsdev` is |
| `ServerFlags` / `DontVTSwitch` `true` | the owner's `tty1` session is never switched away by a key combination on this server |
| `ServerFlags` / `DontZap` `true` | a root Ctrl-Alt-Backspace cannot take the server down |
| `Device` / `kmsdev` `"/dev/dri/card0"` | the output is pinned to the SM750 card node instead of auto-detection picking another card |
| `Device` / `AccelMethod` `none`, `ShadowFB` `true` | the software path; glamor refuses llvmpipe in this Xorg build (`docs/PLASMA-WAYLAND.md:372-375`) and Mesa ships no SM750 driver |
| `Device` / `PrimaryGPU` `true` | a redundant copy of the option: the modesetting driver ignores it inside the `Device` section and warns `(WW) modeset(0): Option "PrimaryGPU" is not used`; the `OutputClass` fragment above is what pins `card0`. A later task removes the line; the 2026-11-26 run still had it (section 11) |

The log confirms the layout it was given - `ServerLayout "SM750 layout"`,
`Screen "SM750 screen"`, `Device "SM750 HDMI"` - and honours the four
`ServerFlags`. The gate asserts each of these lines in the generated block and
that no `InputDevice` section and no `AutoAddDevices "true"` exists anywhere in
the helper (`tests/check-headless-helper.sh:253-320`).

## 6. The desktop-wide environment conflict

This is the root cause of the earlier "no window manager" observation, and it is
host state, not driver state. `/etc/environment` on this host is `root:root`,
mode `644`, 821 bytes, mtime 2026-11-23 13:20:32, and the uncommented lines that
matter here are

```text
KWIN_DRM_DEVICES=/dev/dri/pci-0000-02-00-0-card
KWIN_DISABLE_VULKAN=1
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
```

`/dev/dri/pci-0000-02-00-0-card` is a symlink to `card1`, the NVIDIA card at
`0000:02:00.0`. Every login session inherits these six lines, and
`startplasma-x11` hands its environment to `kwin_x11`. On the SM750 the result
was a crash loop, measured in the session log:

```text
KCrash: Application 'kwin_x11' crashing... crashRecursionCounter = 2
```

four times, after which kwin settled on a `--crashes 4` argument, and the
screenshots of that session are 16339 to 27556 bytes - a few tens of kilobytes,
nothing like a drawn desktop. Every GLX-less server in that session also printed

```text
Xlib: extension "NV-GLX" missing
```

because the vendor library was forced to `nvidia` on a card that does not have
it.

The conflicting settings are two different selections in one file: the DRM
device and the GLX vendor library for the desktop, and the GBM and Vulkan
backends. None of them is wrong for the NVIDIA desktop that the file was
written for; all of them are wrong for a session on the SM750.

## 7. The measured cure on a scratch server

The cure is per-session and needs no file edit: start the session with those
variables unset. Measured as `coder` on scratch X servers (`Xvfb :20` and
`Xvfb :21`, 1920x1080x24, a private `XDG_RUNTIME_DIR` under `/tmp`,
`QT_QPA_PLATFORM=xcb`), with no root, no seat and no DRM device:

| Run | Environment | `kwin_x11` | Crash lines | Screenshot |
| --- | --- | --- | --- | --- |
| 1 | `KWIN_DRM_DEVICES`, `KWIN_RENDER_NODES`, `__GLX_VENDOR_LIBRARY_NAME`, `KWIN_DISABLE_VULKAN` and `KWIN_COMPOSE` unset, plus a preseeded `kwinrc` with `[Compositing] Enabled=true Backend=XRender` | pid 1513813 for the whole 40 s, plain `/usr/bin/kwin_x11` command line | 0 | 1692991 bytes |
| 2 | the same environment cleared, and no `kwinrc` at all | pid 1537736, stable | 0 | 1582653 bytes |

So the crash loop was the inherited desktop-wide environment, not the driver and
not a missing configuration key: run 2 proves the compositing section is not
needed, because kwin wrote no `[Compositing]` section of its own and still came
up. A multi-megabyte screenshot is a drawn desktop, not a black screen.

## 8. The `KWIN_COMPOSE` correction

`KWIN_COMPOSE` must **not** be set. Measured with a foreground `kwin_x11` under
an 8 s timeout:

| `KWIN_COMPOSE` | Outcome |
| --- | --- |
| `X` or `Q` | exits immediately, rc 0 |
| empty or `O2` | survives the 8 s window, rc 124 from `timeout` |

An earlier note in this work claimed that "`KWIN_COMPOSE=X` makes `kwin_x11`
work". That was a misreading of the rc: under `timeout`, rc 0 means the program
exited at once, not that it stayed up. The variable is therefore one of the
eight the generated session script unsets
(`tools/sm750-headless.sh:381-382`), and the helper's plan file names it among
the variables a session on `:1` must start without
(`tools/sm750-headless.sh:162-164`).

## 9. GLX on this card is software

With the vendor library no longer forced, the server's GLX falls back to
DRISWRAST, which is software, and kwin falls back on its own: the desktop draws,
as the screenshot sizes in section 7 show. No environment variable changes that
on this build - glamor refuses llvmpipe outright
(`docs/PLASMA-WAYLAND.md:372-375`) - so there is no accelerated X11 path on this
card, and none is claimed here. The 2026-11-26 run on `card0` is the same
software path: the server came up without GLX and kwin composited through its
XRender path on llvmpipe (section 11).

## 10. What to run

Two steps, and only the first needs root.

1. **Start the server through the helper.** The in-tree helper has an `x11`
   mode, and the installed `/usr/local/sbin/sm750-headless` on this host is now
   the same file: sha256
   `bef39ba73cacdbcce93bc7319203689f98947a7556484d8cd51d06faf0591df7` on both.
   The 2026-11-26 run used exactly that installed copy. From the repository
   tree:

   ```sh
   sudo ./tools/sm750-headless.sh x11 600
   ```

   The run directory is `/mega/tmp/sm750/headless/<stamp>-x11`. It holds
   `sm750-x11.conf`, `xorg.log`, `00-plan.txt` (the variables the session must
   start without), `04-display.txt`, and - once the display socket appears -
   `run-plasma-x11.sh`. The helper waits up to 20 s for
   `/tmp/.X11-unix/X1` (`tools/sm750-headless.sh:359-367`) and writes
   `DISPLAY=:1` when it is there (`tools/sm750-headless.sh:368`); if no socket
   appears it says so and names the server log
   (`tools/sm750-headless.sh:394`).

2. **Start the session as the desktop user**, with the script the run wrote:

   ```sh
   /mega/tmp/sm750/headless/<stamp>-x11/run-plasma-x11.sh
   ```

   That script (`tools/sm750-headless.sh:374-388`) unsets `KWIN_DRM_DEVICES`,
   `KWIN_RENDER_NODES`, `KWIN_DISABLE_VULKAN`, `KWIN_COMPOSE`,
   `__GLX_VENDOR_LIBRARY_NAME`, `GBM_BACKEND`, `VK_DRIVER_FILES` and
   `VK_ICD_FILENAMES`, exports `DISPLAY=:1`, `XDG_SESSION_TYPE=x11`,
   `XDG_CURRENT_DESKTOP=KDE` and `KDE_FULL_SESSION=true`, and execs
   `/usr/bin/startplasma-x11`. It is written `0755`
   (`tools/sm750-headless.sh:389`), so the desktop user can run it without
   copying anything.

The server half is a fixed argument list with no passthrough
(`tools/sm750-headless.sh:328-337`): display `:1`, the generated config, and
`-sharevts -novtswitch -noreset -ac -nolisten tcp`. `-sharevts` and
`-novtswitch` mean no VT is allocated and the owner's `tty1` is neither switched
away nor reused; `-ac` is required because the server writes no auth file and
an unprivileged session user could not connect otherwise, and it is bounded by
`-nolisten tcp` and by the run's lifetime.

## 11. The measured session on card0 (2026-11-26)

Run once as root with the installed helper and a 240 s lifetime:

```sh
sudo -n /usr/local/sbin/sm750-headless x11 240
```

Run directory `/mega/tmp/sm750/headless/20261126T125401Z-x11`; the transcript is
section 12 of
[`43-plasma-x11.txt`](evidence/runtime/43-plasma-x11.txt).

- **The server is on the card.** It was up on `:1` in 4 s, and `xorg.log` shows
  `ServerLayout "SM750 layout"`, the `OutputClass` that sets `/dev/dri/card0` as
  primary, `LoadModule: "modesetting"` with
  `/usr/lib64/xorg/modules/drivers/modesetting_drv.so`, and
  `modeset(0): Option "kmsdev" "/dev/dri/card0"`.
- **The window manager holds.** The session ran as `coder` through
  `dbus-run-session -- <run>/run-plasma-x11.sh` with a private
  `XDG_RUNTIME_DIR=/tmp/sm750-x11-sess` and the eight desktop-wide variables
  absent. `kwin_x11` was pid 1979033, plain `/usr/bin/kwin_x11`, identical at
  t=20 s, t=40 s and t=60 s; the session log has zero `crashing` lines and zero
  `kwin_wayland_drm` or `Failed to create framebuffer` lines.
- **The panel shows it.** `card0-HDMI-A-1` is `connected` with
  `enabled=enabled`; `PANEL_DISPLAY_CTRL 0x0f010105`, `PANEL_CURRENT_LINE
  0x00000419` advancing, `PANEL_FB_ADDRESS 0x00000000`; the scanout window over
  the last four 16-byte rows carries content (`49 21 49 29` alternating), not
  the all-zero frame whose crc32 is `0xe20eea22`; a 1920x1080
  `ffmpeg -f x11grab` capture of `:1` is 1836586 bytes.
- **Two log lines are expected, not failures.** `Failed to load module "mouse"`
  and `"kbd"` with `No input driver matching` and `PreInit returned 2` for the
  default pointer and keyboard follow from having no `InputDevice` section: the
  server opens no input device, which is the guarantee of section 5. The
  session therefore cannot be typed into.
- **One warning is a redundant option.**
  `(WW) modeset(0): Option "PrimaryGPU" is not used` comes from the `Device`
  copy of the option, which modesetting ignores; the `OutputClass` fragment is
  what pins `card0` (section 5). The line is still in the generated config at
  the time of this run.
- **Rendering is software.** This server has no GLX, so kwin composites through
  its XRender path on llvmpipe. Nothing here is hardware acceleration.

Two harness lessons cost a failed attempt each, and a future run must repeat
both: a stale `/tmp/.X1-lock` aborts the server with `(EE) Server is already
active for display 1`, and a live orphan `Xvfb :1` aborts it with
`_XSERVTransSocketUNIXCreateListener: ...SocketCreateListener() failed`, so the
lock must be removed and the orphan killed by pid (`pkill -x` cannot match
names longer than 15 characters); and killing `sudo` does not stop the helper,
because the root child runs until its own `seconds` value expires, so an early
teardown needs a short `seconds`, not a kill.

## 12. What is proven and what is not

Proven on this host, from the evidence of
[`43-plasma-x11.txt`](evidence/runtime/43-plasma-x11.txt):

- The four X11 packages are installed and the real server is
  `/usr/libexec/Xorg` 21.1.26, not setuid.
- A non-root server reaches the driver and is stopped only by console
  ownership, with the exact error of section 3.
- The generated configuration parses and is honoured.
- `kwin_x11` stays up with zero crash lines and a drawn desktop on a scratch X
  server once the six `/etc/environment` selections are cleared, with no
  `kwinrc` preseed.
- `KWIN_COMPOSE` set to `X` or `Q` makes the window manager exit at once.
- Since 2026-11-26 the same holds on `card0`: a root server drives the card at
  1920x1080, `kwin_x11` holds one pid with zero crashes, the connector reports
  `enabled`, and the scanout window carries content (section 11).

NOT OBSERVED, and stated as a limit rather than a result:

- **A driven session.** No input device is opened by design, so no keystroke,
  pointer event or window interaction has been performed in an X11 session on
  this card.
- **A Plasma shell.** The `card0` run establishes the server and the window
  manager; `plasmashell` itself was not sampled for.
- **Acceleration.** The server has no GLX and kwin composites on llvmpipe; no
  accelerated X11 path exists on this card and none was measured (section 9).
- **Compositing cost.** Frame rate, tearing and latency of the XRender path on
  this card are unmeasured.

## 13. What this document does not claim

- It does not claim hardware acceleration. The `card0` session composites
  through XRender on llvmpipe, and this server has no GLX.
- It does not claim the session can be driven. No input device is opened, so
  the desktop draws but cannot be typed into.
- It does not claim X11 is better than the Wayland front of
  [PLASMA-WAYLAND.md](PLASMA-WAYLAND.md). It is a second front with a different
  privilege requirement, not a replacement.
- It does not claim input works. It does not.
- It does not claim the `/etc/environment` content is wrong. It is right for the
  NVIDIA desktop it was written for, and wrong for a session on this card; the
  cure is per session, and nothing here edits that file.
- It does not claim this works on any other board, panel or host. One card, one
  panel, one host.