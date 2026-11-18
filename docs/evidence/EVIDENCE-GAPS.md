<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Evidence gaps: baseline artifacts that require privileges

Every entry below is an artifact this corpus could **not** capture, because the
operation is denied to `uid=1005(coder)` on `deneb`. Each one carries the
exact command that would close it once privileges are available, plus the
denial that was actually observed. Nothing here is inferred, and no entry
claims a result.

The denial evidence itself is in `docs/evidence/baseline/09-denials.txt`; the
working baseline is in `docs/ENVIRONMENT.md`.

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

Residual limit, not a gap in the capture: the helper's `EXPECT` constant should
become 49152, so that a good capture stops exiting 2. Changing it needs the
host owner, because the helper is a root-owned host path and the sudo grant is
on the path. That edit is out of scope for T12.

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
# framebuffer readback / CRC capture, still needs root or a vkms-style sink:
sudo cat /sys/kernel/debug/dri/0/crtc-0/crc/data
```

Status: `PARTIAL`. Device access and connector/mode enumeration are verified;
modeset, readback, CRC and external capture remain `GAP`. See
`docs/ENVIRONMENT.md` section 5.1.

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

Closing command:

```sh
sudo lspci -vvv -xxx -d 126f:0750 -s 01:00.0 > /mega/tmp/sm750/t3/lspci-full.txt
```

Status: `GAP-PARTIAL`.

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

---

## Summary

| Gap | Artifact | Blocking denial | Status |
| --- | --- | --- | --- |
| B1 | VBIOS ROM (48 KiB) | rom node `0600 root`; captured via allowlisted `sm750-vbios-dump` (T12) | `CLOSED` |
| B2 | kernel log excerpt | `dmesg` EPERM unprivileged; allowlisted `sudo -n /usr/bin/dmesg` works (T13) | `CLOSED` |
| B3 | modeset / IGT / kmscube | `/dev/dri/card0` `0660 root:video` + ACL | `GAP` |
| B4 | MMIO register dumps | strict devmem, BAR1 `0600`, debugfs `0700`; facility now present (T5, `regs` at `src/sm750_drm.c:3337`), read still needs root | `GAP` |
| B5 | config space > 0x40 | `Capabilities: <access denied>` | `GAP-PARTIAL` |
| B6 | EDID checksum detail | none | `CLOSED` |
| B7 | RPM install/erase, DKMS hooks | `dkms install` needs root; `rpm -i --root=` cannot chroot | `GAP` |

One further fact, recorded rather than resolved: the handoff anticipated a
`journalctl -k -b` substitute for `dmesg`. It exits 0 on this host but yields
zero records unprivileged, so it is a shape-compatible but content-empty
substitute for `coder`. The `sudo -n` path in B2 is now exercised and kernel-log
excerpts are captured; a later task needing one should use the allowlisted
`sudo -n /usr/bin/dmesg` or `sudo -n /usr/bin/journalctl -k -b -q --no-pager`,
not unprivileged `journalctl`.
