<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Evidence gaps: baseline artifacts that require privileges

Every entry below is an artifact this corpus could **not** capture, because the
operation is denied to `uid=1005(coder)` on `deneb`. Each one carries the
exact command that would close it once privileges are available, plus the
denial that was actually observed. Nothing here is inferred, and no entry
claims a result.

The denial evidence itself is in `docs/evidence/baseline/09-denials.txt`; the
working baseline is in `docs/ENVIRONMENT.md`.

## Status of record

This file is the status of record for every gap. The summary table near the end
holds one authoritative row per gap; where another document states a different
status, that document is a point-in-time record and the row here wins. Round-1
narrative in `docs/ACCEPTANCE-REPORT.md` (for example the GAP-B5 dispute at
:384-391) is kept as history and is not corrected in place; the round-2 closure
table there and the row here carry the current status.

## Activation rule

These rows are inert by default. If `sudo` is granted later, re-run the
closing command for each row, store the output next to the other baseline
captures, and flip the row's status from `GAP` to `PASS` with the date. No
task in the current plan may assume a granted privilege.

## Status legend

| Status | Meaning |
| --- | --- |
| `GAP` | Blocked, closing command known, not executed |
| `GAP-PARTIAL` | Part of the artifact is readable; the privileged remainder is missing |
| `CLOSED` | Captured; kept in this table only where a substitute had to be chosen |

---

## GAP-B1: VBIOS ROM image

The PCI ROM BAR is populated (`Expansion ROM at c7400000 [disabled] [size=64K]`)
but the sysfs file is root-only:

```
$ ls -l /sys/bus/pci/devices/0000:01:00.0/rom
-rw------- 1 root root 65536 Nov 17 19:45 /sys/bus/pci/devices/0000:01:00.0/rom
$ dd if=/sys/bus/pci/devices/0000:01:00.0/rom of=/mega/tmp/sm750/t3/vbios.bin bs=65536 count=1
dd: failed to open '/sys/bus/pci/devices/0000:01:00.0/rom': Permission denied
[exit 1]
```

VBIOS layout is 64 KiB, so a single 65536-byte read covers the whole image.
Note the ROM is `[disabled]`; reading it may require enabling the ROM BAR
first, which is itself a privileged write.

Closing command:

```sh
sudo sh -c 'echo 1 > /sys/bus/pci/devices/0000:01:00.0/rom' &&
sudo dd if=/sys/bus/pci/devices/0000:01:00.0/rom of=/mega/tmp/sm750/t3/vbios.bin bs=65536 count=1 &&
sudo sh -c 'echo 0 > /sys/bus/pci/devices/0000:01:00.0/rom'
# then: sha256sum /mega/tmp/sm750/t3/vbios.bin
```

Status: `GAP`. (Superseded by the T12 update below, which closes this row as
`CLOSED`; the line is kept so the state at the time of writing stays visible.)

Update (T12, 2026-11-18T10:11Z): this gap is CLOSED, and two statements in the
text above were wrong. They are corrected here rather than rewritten, so the
record of what was believed at the time survives:

1. "VBIOS layout is 64 KiB" is false for this device. The ROM BAR aperture is
   64 KiB (`[size=64K]`), but the image the BAR returns is 49152 bytes: the
   header size byte at 0x02 is 0x60 (96 * 512), the PCIR image-length field at
   0x2c is 0x0060 (96 units), the file length equals the declared length, and
   the whole-image byte sum is 0 modulo 256, i.e. a valid VGA checksum at
   48 KiB. Bytes 0x815d..0xbfff are a pure 0xcc padding run. The image is
   complete, not truncated.
2. The closing command above was never runnable as written: `sudo sh -c ...` is
   not in the allowlist. The grant is on three exact binaries. The capture goes
   through `/usr/local/sbin/sm750-vbios-dump`, which toggles the ROM enable bit
   itself and restores it in a trap.

Measured on this host:

```
$ sudo -n /usr/local/sbin/sm750-vbios-dump
[stdout] 16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551  /mega/tmp/sm750/vbios-01-00-0.bin
[stdout] sm750-vbios-dump: wrote /mega/tmp/sm750/vbios-01-00-0.bin
[stderr] 12+0 records in
[stderr] 12+0 records out
[stderr] 49152 bytes (49 kB, 48 KiB) copied, 0,0442739 s, 1,1 MB/s
[stderr] sm750-vbios-dump: WARNING size is 49152, expected 65536
[exit 2]
```

Exit 2 with 49152 bytes is the correct result for this device: the code is
taken only from the helper's stale `EXPECT=65536` constant. A second run to a
scratch path produced a byte-identical file (`cmp` exit 0, same sha256), so the
read is deterministic. The ROM enable bit was restored: the sysfs file is back
to `-rw------- root:root 65536` and the BAR reads
`Expansion ROM at c7400000 [disabled] [size=64K]` again.

Image: 49152 bytes, sha256
`16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`, kept at
`/mega/tmp/sm750/vbios-01-00-0.bin` and deliberately not committed (vendor
binary; `docs/PROVENANCE.md`). Signature 0x55aa; PCIR at 0x1c via the pointer
at 0x18; vendor 0x126f, device 0x0750, class 0x030000, structure length 24,
code type x86, indicator 0x80; VBE 2.0 block at 0x7f; version 1.00.59-, build
05/14/19 16:25, banner "Silicon Motion SM750 VGA BIOS (CRT)". Transcript:
`docs/evidence/baseline/18-vbios-dump.txt`.

Resolved, and not a residual limit: the `EXPECT` constant was the stale part. The
v3 helper body, recorded at `docs/ROOT-ACTIONS.md:365-373`, was installed at
`/usr/local/sbin/sm750-vbios-dump` on 2026-11-18T12:07Z with `EXPECT=49152`, and
it exits 2 on a size mismatch and 3 on a bad `55aa` signature, so a good capture
no longer warns. The exit-2 transcript above was produced by the v2 body and
stays as it was recorded.

Status: `CLOSED`. The image is captured, verified and documented.

## GAP-B2: kernel log excerpt (`dmesg`)

`dmesg` is denied, and `/var/log/messages` and `/proc/kmsg` are root-only:

```
$ dmesg
dmesg: read kernel buffer failed: Operation not permitted
[exit 1]
$ ls -l /proc/kmsg
-r-------- 1 root root 0 Nov 17 20:44 /proc/kmsg
$ ls -l /var/log/messages
-rw------- 1 root root <size> Nov 17 20:47 /var/log/messages
```

(`/var/log/messages` is root-only; its size grows during operation and is not
a stable value, so it is not quoted as one.)

Question asked by the handoff: **is `journalctl -k -b` an available
substitute?** Answer, measured on this host: **no.** The command runs and
exits 0, but returns no kernel records at all for this user, so it is a
successful exit with empty output rather than a usable excerpt:

```
$ journalctl -k -b --no-pager
Hint: You are currently not seeing messages from other users and the system.
      Users in groups 'adm', 'systemd-journal', 'wheel' can see all messages.
      Pass -q to turn off this notice.
-- No entries --
[exit 0]
$ journalctl -k -b -q --no-pager | wc -l
0
[exit 0]
```

`coder` is in no group that grants journal access (`id -nG` -> `coder`). The
user journal *is* readable (`journalctl --user -q --no-pager | wc -l` ->
`31604` lines at capture time) but contains no kernel records, so it is not a
substitute either. Letting `-q` suppress the hint makes the emptiness silent, which is
why the hint-bearing invocation is the one recorded.

CORRECTION (T12, 2026-11-18T10:22Z): the paragraph above is wrong about the
allowlisted path and must not be read as a statement about `journalctl -k -b`
in general. The zero-line result was measured **without** the sudo grant, as
the unprivileged `coder` user, which is why it came back empty. With the grant
the same invocation returns the full ring buffer:

```
$ sudo -n /usr/bin/journalctl -k -b -q --no-pager | wc -l
2017
[exit 0]
$ sudo -n /usr/bin/dmesg | wc -l
2017
[exit 0]
```

The 2017-line measurement is T10's, recorded in
`docs/evidence/runtime/07-kernel-log.txt`, which already flags the passage
above as contradicted. The 169860-byte / 240-`sm750`-line `sudo -n dmesg`
capture at 2026-11-18T09:36Z is recorded in `docs/DELIVERABLES.md` section 3
and in the T13 update below, which measures 2096/2097 lines because the ring
buffer had grown by then. All of these agree: the line count depends on when
the buffer is read, and none of them is zero.

The unprivileged denial itself is unchanged and still reproduces: `coder` is in
no journal group (`id -nG` now reports `coder vtune`), so the unprivileged
`journalctl -k -b` remains empty. That is a statement about the unprivileged
reader, not about the command.

Closing command:

```sh
sudo dmesg > /mega/tmp/sm750/t3/dmesg-boot.txt
# or, equivalently and with timestamps:
sudo journalctl -k -b --no-pager > /mega/tmp/sm750/t3/journal-kernel-boot.txt
```

Update (T13, 2026-11-18): this gap is closed. The `sudoers` allowlist in
`/etc/sudoers.d/10-sm750-debug` permits passwordless execution of the three
exact binaries in the closing command above, so the denial quoted here is a
statement about the unprivileged path only. Measured on this host:

```
$ sudo -n /usr/bin/dmesg > dmesg-before-fix.txt
[exit 0]
$ wc -l dmesg-before-fix.txt
2096 dmesg-before-fix.txt
$ grep -c sm750 dmesg-before-fix.txt
240
$ sha256sum dmesg-before-fix.txt
eed1f7c9d2c5567846fa6a91c88cec6c2501ab6ce6be8a656162157800ab330a  dmesg-before-fix.txt
$ sudo -n /usr/bin/journalctl -k -b -q --no-pager > journal-before-fix.txt
[exit 0]
$ wc -l journal-before-fix.txt
2097 journal-before-fix.txt
$ sha256sum journal-before-fix.txt
8e614642555d55cd4cc1b4247a7a2e18d6546bf53a1793f20e9e722828b1b667  journal-before-fix.txt
```

Both files contain 240 `sm750` lines and agree line for line; the journal copy
adds a localized `deneb kernel:` timestamp prefix (the host locale is not
English, so the month name is not ASCII - the verbatim line is kept in
`docs/evidence/runtime/cursor-alpha-01-warning-before.txt` rather than copied
here). The unprivileged denial still reproduces exactly as quoted above, and
`id -nG` now reports `coder vtune` (the earlier capture recorded `coder` only;
`vtune` grants nothing here - the journal hint lists `adm`, `systemd-journal`
and `wheel`). The `journalctl` substitute is still empty for `coder`
(`journalctl -k -b -q --no-pager | wc -l` -> `0`), so the working path is the
allowlisted `sudo -n` one, not an unprivileged reader.

The captured excerpt used by the current work is in
`docs/evidence/runtime/cursor-alpha-01-warning-before.txt`, which quotes the
probe warning at `dmesg-before-fix.txt:1245` with its neighbours and states the
stale-build proof for the module that produced it. The allowlisted commands and
the earlier 169860-byte capture are recorded in `docs/ROOT-ACTIONS.md`.

Status: `CLOSED`. Kernel-log excerpts are readable through the allowlist and
have been captured; the only residual limit is that the reader is a specific
allowlisted command rather than a general privilege.

## GAP-B3: modeset capture through `/dev/dri`

Update (T9, 2026-11-18): the device-access half of this gap is closed. The
staged udev rule **is installed** and re-applies the ACL on every probe:

```
$ ls -l /etc/udev/rules.d/99-sm750-coder-acl.rules
-rw-r--r-- 1 root root 710 Nov 18 09:15 /etc/udev/rules.d/99-sm750-coder-acl.rules
$ ls /etc/udev/rules.d/
72-vkms-seat.rules
99-sm750-coder-acl.rules
$ getfacl /dev/dri/by-path/pci-0000:01:00.0-card
# file: dev/dri/by-path/pci-0000:01:00.0-card
# owner: root
# group: video
user::rw-
user:duka:rw-
user:coder:rw-
group::rw-
mask::rw-
other::---
```

`coder` therefore opens the card node without `sudo`, and `modetest -c`
enumerates the connector. The three failures before `card0` are the other DRM
cards in the `cardN` scan order, not a permission problem (the transcript below
is re-wrapped for width; the verbatim capture is in the evidence log):

```
$ modetest -c
trying to open device '/dev/dri/card3'... failed
trying to open device '/dev/dri/card2'... failed
trying to open device '/dev/dri/card1'... failed
trying to open device '/dev/dri/card0'... done
opened device `SM750G10 SiI9024A HDMI DRM shadow driver` on driver `sm750hdmidrm` (version 0.1.0 at 0)
Connectors:
id      encoder status          name            size (mm)       modes   encoders
35      39      connected       HDMI-A-1        530x300         28      39
  modes:
        index name refresh (Hz) hdisp hss hse htot vdisp vss vse vtot
  #0 1920x1080 60.00 1920 2008 2052 2200 1080 1084 1089 1125 148500 flags: phsync, pvsync; type: preferred, driver
  #1 1920x1080 59.94 1920 2008 2052 2200 1080 1084 1089 1125 148352 flags: phsync, pvsync; type: driver
  ... 26 further modes, see docs/evidence/builds/12-version-and-gapb3.log
```

The `version 0.1.0 at 0` in that transcript is the **stale installed module**
(the pre-0.6.0 build), not the tree under test: 0.6.0 sets
`DRIVER_MAJOR`/`DRIVER_MINOR`/`DRIVER_PATCHLEVEL` and the built object carries
`0.6.0`. Reloading the module to show it live needs root, which this host does
not grant; that is T11's job. Evidence:
`docs/evidence/builds/12-version-and-gapb3.log`.

Residual gap (tiers above connector enumeration): connector and mode
enumeration now works unprivileged, but nothing above it has been exercised -
no modeset (no mode has been set or read back), no framebuffer readback, no
scanout CRC, no external capture of the signal. `kmscube` and IGT remain
unexecuted, so no conformance result is claimed. Those tiers need either the
`modeset`/`atomic` capability test (`modetest -s`, `modetest -a`), which was
not run here, or root for a framebuffer/CRC capture path.

Closing commands for the remaining tiers:

```sh
# modeset + plane dump, rootless now that the ACL exists:
modetest -M sm750hdmidrm -s 35:1920x1080 -a
# framebuffer readback / CRC capture: still needs root or a vkms-style sink:
# (the CRC line formerly here is withdrawn - see the correction below)
```

Status: `PARTIAL`. Device access and connector/mode enumeration are verified;
modeset, readback, CRC and external capture remain `GAP`. See
`docs/ENVIRONMENT.md` section 5.1.

Correction (T23, 2026-11-18): the CRC line that this block originally carried
(`sudo cat /sys/kernel/debug/dri/0/crtc-0/crc/data`) is withdrawn. The driver
registers no CRC source, so that debugfs file cannot exist at any privilege
level; the CRC bullet further down states what closing that tier would
actually require.

Update (T11, 2026-11-18T12:33Z): the modeset and conformance tiers named as
`GAP` above have since been executed, twice, without root - T10 on the stale
build and T11 on 0.6.0 - so this row is re-scoped rather than left overstated:

- modeset: `docs/evidence/runtime/04-modeset.txt` (pre-fix) and
  `16-modeset-0.6.0.txt` (0.6.0), including the 1024x768-60 set and the
  restoration, with the CRTC line proving each state.
- `kmscube`: `05-kmscube.txt` and `17-kmscube-0.6.0.txt`, rendering at ~54 fps
  through llvmpipe on 0.6.0.
- IGT: `06-igt.txt` and `19-igt-0.6.0.txt`; `core_getversion` passes and now
  reports `v0.6`, `kms_addfb_basic` gives an identical 26/14/1 tally in both
  halves.

What remains genuinely blocked is the last two tiers only, and neither has a
test command that could succeed on this host:

- Framebuffer readback: no `/dev/fb*` node exists (`CONFIG_FB_DEVICE` is unset,
  A24 in `docs/DEFECTS.md`), the driver registers no writeback connector
  (`grep -rn writeback src/` returns nothing), and a second DRM client cannot
  map a framebuffer it did not allocate. There is no unprivileged reader of the
  scanned-out pixels on this host.
- Scanout CRC: the driver has no CRC source. `grep -rn 'crc' src/*.c src/*.h`
  returns nothing, and the CRTC CRC debugfs file is added only for a CRTC whose
  `drm_crtc_funcs` provides `get_crc_sources`
  (`/usr/src/kernels/7.3.4-100.fc43.x86_64/include/drm/drm_crtc.h:843-861`), so
  `/sys/kernel/debug/dri/0/crtc-0/crc/data` cannot exist for this driver. The
  earlier closing command for this tier, `sudo cat
  /sys/kernel/debug/dri/0/crtc-0/crc/data`, was wrong and is withdrawn: no
  permission level makes that file appear. Closing the tier needs code -
  implement `get_crc_sources` and `set_crc_source` on the CRTC and feed the
  running CRC from the SM750 vsync interrupt - which is a driver change, not a
  documentation task.

Reachable substitutes, both already used: an external capture of the panel
(hardware not attached to this host, and no task in the plan asks for it), and
the register-dump diff, which shows which registers a modeset changes:
`docs/evidence/runtime/08-register-dump.txt` holds three states around a held
modeset, and 12 of the 49 registers change.

Status: `PARTIAL` - modeset and conformance evidence now exists; readback and
CRC remain `GAP`. The CRC half is `GAP` because the driver implements no CRC
source, not because of a permission.

Update (T46, 2026-11-21): the CRC half of this row is **CLOSED**, and the
paragraph above is superseded on that point. The driver now registers a CRC
source, which the earlier text said was missing:

- `sm750_crtc_get_crc_sources()` at `src/sm750_drm.c:3388` and
  `sm750_crtc_set_crc_source()` at `src/sm750_drm.c:3395`, wired into
  `drm_crtc_funcs` at `src/sm750_drm.c:4320` and `:4322`. The core therefore
  creates `/sys/kernel/debug/dri/0/crtc-0/crc/data`, the file this row
  previously called impossible for any privilege level.
- The CRC is computed over the live scanout window
  (`sm750_scanout_crc32()`, 256-byte chunks, one entry per vblank), so it is a
  genuine reader of the pixels the panel is scanning - exactly the framebuffer
  readback tier this row listed as unreachable.
- Hardware evidence, on the panel, verbose 0.6.2:
  `PASS: CRC entries arrive and are stable over 12 static frames (crc
  0xe20eea22)` and `PASS: CRC changes with frame content (black 0xe20eea22,
  white 0x06cf606c)` from `/usr/local/sbin/sm750-crc-cycle`, with the window
  read back as `nonzero 200394 crc32 0x3521e059`; transcripts in
  `docs/evidence/runtime/26-test-card-crc-fix.txt` and the host results in
  `docs/evidence/runtime/28-dangling-kernel-link.txt`.
- What this does NOT close, and should not be read as closing: there is still
  no `/dev/fb*` node (A24) and no unprivileged reader of the scanned pixels.
  The readback tier is closed by a root helper, not by a new interface, and the
  external-capture tier remains `GAP` because no capture hardware is attached.
  Whether that is acceptable for the row is stated in the final status line
  below rather than implied.

Status: `PARTIAL`, re-scoped - device access, connector and mode enumeration,
modeset, `kmscube`, IGT, and scanout-CRC readback are all verified; the only
remaining `GAP` is external capture of the signal by hardware not attached to
this host, which no permitted command can close.

Update (T44, 2026-11-21): the open question R3 from the test-card CRC work -
whether `sm750_pipe_enable()` loses a frame by setting `scanout_offset` to zero
after the enabling commit's plane update - is answered: it is not a defect, it
is adjudicated in `docs/evidence/runtime/29-scanout-offset-reset-rca.txt` and
carried as A41 in `docs/DEFECTS.md`. Nothing in this row's `PARTIAL` status
changes: that verdict rests on source reading, and no capture path was added.

## GAP-B4: MMIO register dumps

No unprivileged path to the SM750 register file exists on this host:

- `/dev/mem` is `crw-r----- root kmem` and opens denied, and the boot config
  `/boot/config-7.3.3-100.fc43.x86_64` (world-readable) sets
  `CONFIG_STRICT_DEVMEM=y` and `CONFIG_IO_STRICT_DEVMEM=y`, so even a
  root-owned reader is restricted to safe regions. `/dev/kmem` does not exist.
- BAR1 (`/sys/bus/pci/devices/0000:01:00.0/resource1`, `c7200000`, 2 MiB) is
  `-rw------- 1 root root`:

```
$ dd if=/sys/bus/pci/devices/0000:01:00.0/resource1 of=/dev/null bs=64 count=1
dd: failed to open '/sys/bus/pci/devices/0000:01:00.0/resource1': Permission denied
[exit 1]
```

- `/sys/kernel/debug` is `drwx------ root root`, so no debugfs file can be
  read even if the driver exposed one.

**`modetest` is not a register-dump source.** It dumps connector, encoder,
CRTC and plane properties through libdrm; it has no option that reads driver
MMIO registers. It is cited here only as a modeset/connector client, never as
a way to obtain register values.

Update (T5, 2026-11-18): the facility now exists. `src/sm750_drm.c:3258-3352`
adds a 49-register snapshot as a mode `0444` debugfs file named `regs`,
created at `src/sm750_drm.c:3337` and registered from `.debugfs_init`
(`src/sm750_drm.c:3363` for the TTM driver, `:3376` for the shadow driver).
The read handler only calls `readl()` under `drm_dev_enter()`, and the
read-to-clear registers (`RAW_INT`, `INT_STATUS`, `GPIO_INTERRUPT_STATUS`) are
deliberately excluded so a before/after pair around one modeset stays
comparable. `tests/check-drm-module.sh:69-78` fails the build if the handler
ever gains a write. The register table is documented in `docs/REGISTERS.md`.

Read attempt on this host, recorded in
`docs/evidence/builds/09-register-dump.log`:

```
$ ls -ld /sys/kernel/debug
drwx------ 52 root root 0 Nov 18  2026 /sys/kernel/debug
$ cat /sys/kernel/debug/dri/0/regs
cat: /sys/kernel/debug/dri/0/regs: Permission denied
[exit 1]
```

So the closing mechanism is in place, but the *read* still needs root and the
values are still absent: the row stays `GAP` until someone runs the command
below. The `dri/<N>` node number is the SM750 card.

Closing command (now exact). The debugfs directory is named after the DRM minor,
which is assigned in probe order, so it is resolved from the by-path link rather
than hardcoded as `dri/0`:

```sh
card=$(readlink -f /dev/dri/by-path/pci-0000:01:00.0-card)
minor=${card##*/card}
sudo cat /sys/kernel/debug/dri/$minor/regs > /mega/tmp/sm750/t3/regs-before.txt &&
sudo modetest -M sm750hdmidrm -s <connector-id>@<crtc-id>:1920x1080 &&
sudo cat /sys/kernel/debug/dri/$minor/regs > /mega/tmp/sm750/t3/regs-after.txt &&
diff -u /mega/tmp/sm750/t3/regs-before.txt /mega/tmp/sm750/t3/regs-after.txt
```

`/usr/local/sbin/sm750-regs` performs the same resolution and is the preferred
form; the sudoers allowlist already permits it.

Status: `GAP` for the read (debugfs is `0700`, so the values still need root);
the closing mechanism is in place - T5 added the `regs` debugfs file at
`src/sm750_drm.c:3337`, and `docs/evidence/builds/09-register-dump.log` records
the denied read as well as the exact command that closes it.

Update (T11, 2026-11-18T12:33Z): this gap is **CLOSED**. The read was executed
through the allowlisted helper against the installed 0.6.0 module, before and
after a modeset, and the three states are comparable in one file -
`docs/evidence/runtime/08-register-dump.txt` (238 lines, 12.5 KB):

```
$ sudo -n /usr/local/sbin/sm750-regs
# card node: /dev/dri/card0 (debugfs dri/0)
# date: 2026-11-18T11:52:04Z
# sm750hdmidrm register dump, 49 registers, read-only
0x000000 SYSTEM_CTRL                  0x20a00000
...
0x000004 MISC_CTRL                    0x01020060
```

The same command had failed one module version earlier, which is the denial
recorded above side by side with the success:
`sm750-regs: /sys/kernel/debug/dri/0/regs not readable` / `is debugfs mounted
and the module loaded?`, exit 1, under the stale 0.5.9 build that has no `regs`
file at all. Both attempts are in the file. So the earlier failure was the
missing facility, not the privilege.

Method result, recorded because the naive command in the closing block above
does not produce a valid comparison: `modetest -s` exits as soon as it has
committed, and the last close runs `drm_fbdev_client_restore`, which re-asserts
the preferred mode. A dump taken right after `modetest -s` returns therefore
shows the RESTORED timing set - the first attempt differed in only 1 of 49
registers (`PANEL_CURRENT_LINE`, a live scanline counter) and looked like a
no-op modeset. Holding the client open (`modetest -s 35@38:1024x768-60 &`,
dump, then kill) gives the real set: **12 of 49 registers change** -
`PANEL_PLL_CTRL`, `PANEL_DISPLAY_CTRL`, `PANEL_FB_ADDRESS`, `PANEL_FB_WIDTH`,
`PANEL_WINDOW_WIDTH`, `PANEL_WINDOW_HEIGHT`, `PANEL_PLANE_BR`,
`PANEL_HORIZONTAL_TOTAL`, `PANEL_HORIZONTAL_SYNC`, `PANEL_VERTICAL_TOTAL`,
`PANEL_VERTICAL_SYNC`, `PANEL_CURRENT_LINE`. A 633-sample race control
(8 modesets x repeated dumps) observed both timing sets in roughly equal
proportions (314 vs 319), which proves the modeset really programs the panel and
that the 1-of-49 reading was a sampling artefact.

Restored-vs-baseline is 3 of 49: `PANEL_CURRENT_LINE` (expected), plus
`PANEL_FB_ADDRESS` (the staged flip moves it: `0x003f4800` is
`ALIGN(1920 * 1080 * 2, 16)`, the driver's backbuffer, so no buffer object was
re-allocated on restore; corrected in T31) and
`MISC_CTRL` bit 17 (`0x01020060` -> `0x01000060`). The last one has no name in
`src/ddk750_reg.h` and is absent from `docs/REGISTERS.md:52`; it is recorded as
an observation, not a defect, and no closing command is owed for it.

Closing command (executed, keep for re-runs after any change to the snapshot):

```sh
sudo -n /usr/local/sbin/sm750-regs > /mega/tmp/sm750/t11/regs-A.txt
modetest -s 35@38:1024x768-60 & sleep 2
sudo -n /usr/local/sbin/sm750-regs > /mega/tmp/sm750/t11/regs-held.txt
kill %1; wait; sleep 2
sudo -n /usr/local/sbin/sm750-regs > /mega/tmp/sm750/t11/regs-C.txt
```

Status: `CLOSED` by `docs/evidence/runtime/08-register-dump.txt`.

## GAP-B5: PCI configuration space beyond 0x40

`lspci -xxx` returns the first 64 bytes because the config-space node is
world-readable for that range only; anything beyond reports
`Capabilities: <access denied>`.

```
$ lspci -vvv -d 126f:0750 -s 01:00.0
...
	Expansion ROM at c7400000 [disabled] [size=64K]
	Capabilities: <access denied>
	Kernel driver in use: sm750hdmidrm
```

The readable 0x00-0x3f dump *is* captured
(`docs/evidence/baseline/07-pci-config-space.txt`), which is enough to
confirm vendor/device ID, command/status, BAR0, BAR1, ROM BAR and revision.

Closing command, executed 2026-11-18T09:35:17Z through the root helper:

```sh
sudo -n /usr/local/sbin/sm750-lspci
```

Status: `CLOSED` by `docs/evidence/baseline/19-pci-config-space-full.txt` - the
helper's 9465 bytes of output, stored as a 174-line transcript with the header
block that records the run. It carries `-vvv` descriptions for the capability
blocks at 0x40 (PM), 0x50 (MSI), 0x70 (Express), 0xb0 (MSI-X), 0x100 (AER) and
0x140 (VC), plus the 256-byte register dump (`40:` to `f0:`). The unprivileged
64-byte capture stays as `docs/evidence/baseline/07-pci-config-space.txt` for
the before/after comparison.

## GAP-B6: per-block EDID checksum verification

The 256-byte EDID is world-readable and fully captured, but only the first
128-byte block is validated against a decoded timing set; the CTA-861
extension is validated only by `edid-decode`'s own checksum pass, which
reports `Checksum: 0xcd`. No privileged operation is needed and nothing is
missing here; the row is listed so later tasks know the EDID source is the
sysfs file, not an I2C read of the monitor, which would require the i2c-dev
device node.

Status: `CLOSED` by `docs/evidence/baseline/02-edid.txt` and
`15-edid-decode.txt`. An I2C re-read of the panel would additionally need
`/dev/i2c-*` access, which is not requested by any task.

## GAP-B7: RPM install/erase and DKMS hook execution

`packaging/sm750hdmifb.spec` is built and verified rootless: `rpmbuild -ba`
exits 0, the metadata and `%files` assertions hold, and a sandbox DKMS tree
reaches `built` with a real `sm750hdmidrm.ko`
(`docs/evidence/packaging/01`-`07`). What is **not** exercised is the
transaction itself: `dnf install` writes `/usr/src`, `/etc`, `/var/lib/dkms`
and the host module tree, and the `%post`/`%posttrans`/`%preun` scriptlets run
against the real root. Both routes are denied to `uid 1005`:

```
$ dkms install -m sm750hdmifb -v 0.5.9 -k 7.3.4-100.fc43.x86_64
Error! You must be root to use this command.
[exit 1]
$ rpm -i --root=/mega/tmp/sm750/t6/fakeroot \
    /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.5.9-1.fc43.noarch.rpm
error: Unable to change root directory: Operation not permitted
[exit 1]
```

So no claim is made that the scriptlets ran under rpm. The offline `%posttrans`
harness (`tests/check-rpm-dkms.sh`, shims over fake module roots) covers the
branch logic only; it is not a package transaction. The kernel headers were
present throughout (`/usr/src/kernels/7.3.4-100.fc43.x86_64`, `Makefile` and
`Module.symvers` included); the one "kernel headers cannot be found" report
came from dkms resolving headers relative to a sandbox `--installtree`, not
from a missing `kernel-devel` package, and the sandbox build now succeeds.
`dkms install` is refused for a non-root caller even with every tree pointed at
scratch, so the sandbox stops at `built`.

The denial transcript above was captured against the 0.5.9 artifact. The
closing commands below target the 0.6.0 build produced by
`tests/check-rpm-dkms.sh` (T9), which is also what
`/mega/tmp/sm750/10-sm750-debug.sudoers` now allowlists.

Closing commands:

```sh
sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm
sudo dkms status -m sm750hdmifb -v 0.6.0
sudo modprobe sm750hdmidrm
sudo dnf remove -y sm750hdmifb
sudo dkms status -m sm750hdmifb -v 0.6.0
```

Expected post-conditions, in order: `dnf install` exits 0 with no `warning:`
lines on stderr (headers present) and the `%posttrans` build produces
`/lib/modules/$(uname -r)/updates/dkms/sm750hdmidrm.ko`; `dkms status` prints
`sm750hdmifb/0.6.0, <kernel>, <arch>: installed`; `modprobe` exits 0 and
`modinfo sm750hdmidrm` reports `version: 0.6.0` and a `vermagic` matching the
running kernel; `modetest -c` then reports
`(version 0.6.0 at 0)` instead of the `0.1.0` the 0.5.9 build printed;
`dnf remove` exits 0; the final `dkms status` prints nothing
(no `sm750hdmifb/0.6.0` line) and
`/usr/src/sm750hdmifb-0.6.0` no longer exists.

Status: `GAP`.

Update (T11, 2026-11-18T12:33Z): this gap is **CLOSED**. The transaction ran as
root three times, and the last two of those prove both directions. Evidence:
`docs/evidence/runtime/11-preconditions.txt` (allowlist and pre-state),
`12-rpmbuild-0.6.0.txt` (the rebuilt artifact), `/mega/tmp/sm750/t11/install.log`
(install), `20-rollback.txt` (erase), `21-final-state.txt` (end state),
with the raw scriptlet transcripts in `/mega/tmp/sm750/t11/{install,remove,
reinstall}.log`.

1. `dnf install` exit 0. The scriptlets ran against the real root:
   `%post` did `dkms add` (`$1 == 1`), `%posttrans` built and signed with the
   machine MOK and installed for **three** kernels - 7.2.15-100, 7.3.3-100 and
   7.3.4-100 (6.18.13-200 was skipped with `matching kernel headers are
   absent`, which the spec treats as a warning, not a failure). `depmod` ran.
   `dkms status` afterwards: `sm750hdmifb/0.6.0` `installed` for all three.
2. `%preun` erased cleanly on `dnf remove` (exit 0): three
   `Before uninstall, this module version was ACTIVE on this kernel` lines, then
   `Deleting module sm750hdmifb/0.6.0 completely from the DKMS tree.`
   `rpm -q` -> not installed; `/usr/src/sm750hdmifb-0.6.0` gone;
   `/lib/modules/$(uname -r)/extra/sm750hdmidrm.ko.xz` deleted; the 0.6.0 dkms
   rows gone. No `%postun` and no initramfs rebuild, as designed.

Three corrections to the expected post-conditions stated above, all measured:

- The installed object path is `/lib/modules/<kver>/extra/sm750hdmidrm.ko.xz`,
  not `.../updates/dkms/sm750hdmidrm.ko`. `dkms.conf` sets
  `DEST_MODULE_LOCATION[0]="/extra"` and dkms compresses with `.xz`.
- `dnf remove` does **not** leave `dkms status` empty: the orphaned
  `sm750hdmifb/0.5.9 ... built` rows for 7.3.3-100 and 7.3.4-100 survive, along
  with `/usr/src/sm750hdmifb-0.5.9`. They are residue of the pre-fix install
  that 0.6.0 displaced, not of this transaction. Harmless here, but a later
  `dkms install -m sm750hdmifb -v 0.5.9` could resurrect the stale build;
  cleanup is not T11's (0.5.9 is outside its package version).
- Erasing the package does not unload the module, so it leaves a
  live-but-unloadable driver: the resident `sm750hdmidrm 167936 0 - Live` keeps
  running while `modinfo` reports `Module sm750hdmidrm not found` and no file
  exists for the running kernel. The SM750 console therefore survives the erase
  only until the next reboot or `modprobe -r`. This is inherent (dnf cannot
  unload, and the package has no `%postun` by design), so the rollback is a
  proof, not a safe resting state: 0.6.0 was reinstalled immediately afterwards
  and the final machine state is verified in `21-final-state.txt`.

Also corrected: `sudo dkms status -m sm750hdmifb -v 0.6.0` in the closing block
does not work on this host - only bare `dkms status` is in the sudoers
allowlist, and the argument form returns `sudo: a password is required`. Use
`sudo -n dkms status` and read the lines.

Closing command (executed, keep for re-runs):

```sh
sudo -n dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm
sudo -n dkms status
modinfo -F version sm750hdmidrm
modetest -c | head -1
sudo -n dnf remove -y sm750hdmifb
sudo -n dkms status; rpm -q sm750hdmifb
```

Status: `CLOSED` by the five evidence files named above.

---

## GAP-B8: which `sm750_program_mode` call returns `-110`

T16 reproduced the `failed to enable HDMI mode: -110` episode from
`docs/evidence/runtime/07-kernel-log.txt:50-110` (1 hit in 205 attempts, see
`docs/evidence/runtime/09-hdmi-minus-110.txt`) but could not identify which of the
five fallible calls in `sm750_program_mode` returned the error, because that
function contains no logging statement at all:

```
$ grep -c 'dev_dbg\|drm_dbg' src/ddk750_display.c src/ddk750_mode.c src/ddk750_swi2c.c src/ddk750_hwi2c.c
src/ddk750_display.c:0
src/ddk750_mode.c:0
src/ddk750_swi2c.c:0
src/ddk750_hwi2c.c:0
$ grep -rn 'dev_dbg\|drm_dbg' src/*.c | grep -c sm750_drm.c
3            # :818, :998, :1007 - none on the program_mode path
```

Dynamic debug is root-only on this host, so even the existing three sites could
not be enabled from `coder`, and the running 0.5.9 module has no `regs` debugfs
file (B4). The 330.003 ms gap between the last successful program and the `-110`
narrows the producer to a single 100 ms `wait_display_value()` timeout after the
fixed ~155 ms of `sii902x` quiesce, but it does not name the call.

Closing command (needs a debug rebuild of 0.6.0 with one `drm_dbg_kms` per stage,
then the T16 trigger):

```
for i in 1 2 3 4 5; do
  tail -f /dev/null | kmscube -c 600 > /dev/null 2>&1 &
  sleep 0.3; pkill -INT kmscube
  timeout -k 5 90 modetest -s 35@38:1024x768-60 > /dev/null
  modetest -s 35@38:1920x1080 > /dev/null
done
sudo -n dmesg | grep -E 'stage=|failed to enable HDMI mode'
```

Complementary, and sufficient without a rebuild: on 0.6.0 sample
`/sys/kernel/debug/dri/0/regs` (`src/sm750_drm.c:3343`) before the failing
restore and immediately after the `-110`; `PANEL_DISPLAY_CTRL` bit 8 (`TIMING`)
and bit 2 (`PLANE`) name the stage, and two `PANEL_CURRENT_LINE` samples 20 ms
apart say whether the raster was still scanning.

Update (T11, 2026-11-18T12:33Z): the complementary path is now executable. 0.6.0
is installed and loaded, and `sudo -n /usr/local/sbin/sm750-regs` succeeds, so
the `regs` half of this closing plan no longer needs anything that is missing
(GAP-B4 is `CLOSED`; see `docs/evidence/runtime/08-register-dump.txt`). T11 also
reproduced the `-110` on 0.6.0 during a plain `kmscube -c 300` exit, so the
trigger does not need the SIGINT shaping to fire - `18-kernel-log-0.6.0.txt`
holds the window, `/mega/tmp/sm750/t11/minus110-full.txt` the raw lines. The
stage instrumentation still requires a debug rebuild, so this row stays `GAP`.

Update (T27, 2026-11-19): the driver now names the stage, so the next occurrence
needs no debug rebuild. `sm750_program_mode()` sets `sdev->mode_stage` before
each of the five fallible calls and resets it to `SM750_MODE_STAGE_NONE` when
the last one succeeds; the failure path in `sm750_pipe_enable()` reports it, so
the next occurrence prints

```
failed to enable HDMI mode: -110 at stage <name> (pipe left down; commit event not armed)
```

where `<name>` is one of `sii902x_begin_mode`, `ddk750_set_display_control`,
`ddk750_set_mode_timing`, `ddk750_set_logical_disp_out`, `sii902x_enable`, or
`none` when the failure predates the first call. The names are the names of the
functions the stage precedes, in source order, so a dmesg line maps to one call
in `src/sm750_drm.c`. The format string is at `src/sm750_drm.c:4366` and its
suffix has read `(pipe left down; commit event not armed)` since 0.6.8; an
earlier revision of this paragraph quoted `(commit finished, event consumed)`,
which is the suffix the 0.6.0-era build printed (the logbook entry of
2026-11-19). Plain `drm_err` is used, not `drm_dbg`, so no dynamic
debug is needed and no root-only switch exists to miss. There is deliberately no
retry: a retry of a half-progressed modeset can corrupt state, and this branch
identifies, it does not recover. `tests/check-drm-policy.sh` asserts that every
stage has a name and an assignment on the modeset path.

The instrumentation has been loaded. Module 0.6.10, which carries the
stage-name format, is installed and live on this host
(`srcversion 6DA22404EEA85B6D6535912`), and the guarded unload path was
exercised sixteen times in one second on the mitigated reload
(`docs/evidence/runtime/54-a65-trace-mitigated-reload.txt`). What has not
happened is the `-110` itself: the trigger has not been re-raised since the
instrumentation went in, so no `at stage <name>` line has been produced and this
row stays `GAP` for the trigger, not for the instrumentation. The instrumentation
record is `docs/evidence/gap-b8/01-stage-instrumentation.txt`.

Status: `GAP`.

---

## Summary

| Gap | Artifact | Blocking denial | Status |
| --- | --- | --- | --- |
| B1 | VBIOS ROM (48 KiB) | rom node `0600 root`; captured via allowlisted `sm750-vbios-dump` (T12) | `CLOSED` |
| B2 | kernel log excerpt | `dmesg` EPERM unprivileged; allowlisted `sudo -n /usr/bin/dmesg` works (T13) | `CLOSED` |
| B3 | modeset / IGT / kmscube | `/dev/dri/card0` `0660 root:video` + ACL; modeset, kmscube and IGT now captured on both builds (T10, T11); the CRC half is `CLOSED` (see the CRC section above, Update T46 of 2026-11-21): the driver registers `sm750_crtc_get_crc_sources` (`src/sm750_drm.c:3499`, `.get_crc_sources` at `:4578`), so `crtc-0/crc/data` is readable through the allowlisted `sm750-crc-cycle` and the scanout CRC gate runs green. What stays `PARTIAL` is proof of the pixels leaving the connector: no `/dev/fb*`, no writeback connector, no external capture (`docs/evidence/scanout/03-readback.txt`) | `PARTIAL` |
| B4 | MMIO register dumps | strict devmem, BAR1 `0600`, debugfs `0700`; `regs` facility (T5) read via allowlisted `sm750-regs` before/during/after a modeset (T11) | `CLOSED` |
| B5 | config space > 0x40 | `Capabilities: <access denied>` unprivileged; allowlisted `sudo -n /usr/local/sbin/sm750-lspci` returns the full space (T14) | `CLOSED` |
| B6 | EDID checksum detail | none | `CLOSED` |
| B7 | RPM install/erase, DKMS hooks | `dkms install` needs root; `rpm -i --root=` cannot chroot; install, `%preun` erase and reinstall all executed as root (T11) | `CLOSED` |
| B8 | which `sm750_program_mode` call returns `-110` | that path had zero `dev_dbg`/`drm_dbg`, and dynamic debug is root-only; T27 instruments the five calls instead (the next occurrence prints `failed to enable HDMI mode: -110 at stage <name>`, see `docs/evidence/gap-b8/01-stage-instrumentation.txt`); the instrumented build is loaded and live (0.6.10, `srcversion 6DA22404EEA85B6D6535912`, `docs/evidence/runtime/54-a65-trace-mitigated-reload.txt`), but the trigger itself reproduced only 1/206 and has not been re-raised | `GAP` |

One further fact, recorded rather than resolved: the handoff anticipated a
`journalctl -k -b` substitute for `dmesg`. It exits 0 on this host but yields
zero records unprivileged, so it is a shape-compatible but content-empty
substitute for `coder`. The `sudo -n` path in B2 is now exercised and kernel-log
excerpts are captured; a later task needing one should use the allowlisted
`sudo -n /usr/bin/dmesg` or `sudo -n /usr/bin/journalctl -k -b -q --no-pager`,
not unprivileged `journalctl`.
