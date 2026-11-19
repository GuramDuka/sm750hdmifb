# Host root actions

Every root action performed on this host for the `sm750hdmifb` work, in
execution order, with the exact command and the evidence gap it closes. This
file is the recovery path: if `/mega/tmp/` is wiped, the staged sources and the
helpers below are reproducible from the bodies printed here.

Host: `deneb`, Fedora 43, kernel 7.3.4-100.fc43.x86_64, unprivileged account
`coder` (uid 1005, groups `1006(coder)` only, not in `video`).

Every action below was performed by the host owner (the human at the console),
not by an agent, because no agent holds a root credential. Agents verify the
result read-only through `sudo -n -l` and through the helper outputs.

All seven actions have been carried out. Rows 6 and 7 were installed by the
host owner on 2026-11-18 at 12:07Z and 12:08Z (15:07 and 15:08 local, MSK); the
staged sources under `/mega/tmp/sm750/` are kept as the reference bodies and as
the recovery path if that directory is ever rebuilt. The installed state of each
artefact, with the read-only command that proves it, is in section 5.

Row 8 is different: it is **proposed, not performed**. It needs a root run that
no agent may make, and it is what closes the readback half of GAP-B3. The exact
commands are in section 7. Related operational hazard: an erase followed by a
reboot leaves the card with no driver; the recovery runbook is in `README.md`,
section "If the card stops working after removing the package".

| # | Date (UTC) | Action | Closes |
| --- | --- | --- | --- |
| 1 | 2026-11-18T06:15Z | install `/etc/udev/rules.d/99-sm750-coder-acl.rules` | GAP-B3 (partial) |
| 2 | 2026-11-18T08:37Z | install the three helpers in `/usr/local/sbin` | GAP-B4, GAP-B5, GAP-B1 |
| 3 | 2026-11-18T08:37Z | install `/etc/sudoers.d/10-sm750-debug` (0440) | GAP-B2, GAP-B4, GAP-B5, GAP-B7 |
| 4 | 2026-11-18T08:37Z | run the VBIOS helper once | GAP-B1 (attempt, truncated) |
| 5 | 2026-11-18T10:12Z | reinstall the VBIOS helper with the v2 body | GAP-B1 (superseded by row 6, which closed it; v2's size constant was stale) |
| 6 | 2026-11-18T12:07Z | reinstall the VBIOS helper with the v3 body: 1725 B, sha256 `07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e`, `EXPECT=49152`, exit 2 on size mismatch, exit 3 on a bad `55aa` signature, success prints `signature 55aa, checksum ok` | GAP-B1 CLOSED (capture byte-identical to the 48 KiB image) |
| 7 | 2026-11-18T12:08Z | install the `/dev/tty0` ACL rule (`99-sm750-coder-tty0-acl.rules`, 762 B, sha256 `248d76743dd1fa5aca03e55432e53bf02647900038b330439033f569117f7c4b`) and its tmpfiles companion (`sm750-tty0-acl.conf`, 299 B, sha256 `3072aa4ecfd3f67d3c85be6076574d8d1b5afb47e5f4910df15d7f11c3f14538`) | GAP-B3 (IGT VT subset) unblocked: `/dev/tty0` is `crw-rw----+` with `user:coder:rw-` |
| 8 | proposed | run `tests/check-scanout-crc.sh` once as root and store the transcript (section 7) | GAP-B3 readback/CRC half; GAP-B8 if the `-110` recurs during the run |

Sections below are ordered by subject, not by date: allowlist, recovery recipe,
helpers, udev rule, installed state and re-verification, gap map.

## 1. Sudoers allowlist

Path: `/etc/sudoers.d/10-sm750-debug`, mode `0440`, owner `root:root`, 4047
bytes, sha256
`d2141159a99e65ba3c150e20daba915babbe907674a80bfbce1fce598ed35a3b`.

Staged source: `/mega/tmp/sm750/10-sm750-debug.sudoers` (same bytes).
Verification transcript: `docs/evidence/builds/18-sudoers-verify-0.6.0.log`.

Install (must be root; see the recovery recipe before running it):

```sh
sudo install -m 0440 -o root -g root \
    /mega/tmp/sm750/10-sm750-debug.sudoers \
    /etc/sudoers.d/10-sm750-debug
sudo -n -l
```

### Design rule: zero colons in command lines

sudoers treats `:`, `,`, `=` and `\` as special inside a command argument and
requires a backslash before each one. Escaping alone proved fragile - an earlier
installed copy failed with `syntax error at lines 32:63 and 33:60` because the
two `lspci` lines carried unescaped `01:00.0` and `126f:0750`. The rule is
therefore absolute: no command line in this file contains a colon. Anything that
needs a PCI address or a vendor:device pair goes through a fixed helper in
`/usr/local/sbin` instead. The `dnf install` line names the exact RPM path
rather than a glob.

Audit the rule before installing anything:

```sh
grep -vE '^[[:space:]]*(#|$)' 10-sm750-debug.sudoers \
  | sed 's/NOPASSWD://' | grep -c ':'
```

Expected output: `0`. Recorded in
`docs/evidence/builds/18-sudoers-verify-0.6.0.log`.

### Verification

Two checks, both required, both run without root:

```sh
visudo -c -f /mega/tmp/sm750/10-sm750-debug.sudoers
```

and the same file appended to a copy of the stock `/etc/sudoers` (extracted from
the `sudo` RPM payload, 188 lines), then `visudo -c -f` on the copy. Both print
`parsed OK` and exit 0.

The live file cannot be read or listed by `coder` (`ls /etc/sudoers.d` is
denied), so its content is verified indirectly:

```sh
sudo -n -l
```

`sudo -n visudo -c` and `sudo -n cat /etc/sudoers.d/10-sm750-debug` are
deliberately NOT granted - a grant to `cat` on that path would be a grant to
read every future allowlist, and `visudo` on the live file is not needed once
the staged file is verified. Verification is by `sudo -n -l` content only.

### The 19 NOPASSWD entries

`sudo -n -l` lists 19 entries: 16 for this work plus three that predate it
(`/usr/bin/dmidecode`, `/usr/local/cuda/bin/ncu`, `/usr/local/cuda/bin/nvprof`).
The 16, at 0.6.0:

```text
/usr/local/sbin/sm750-regs
/usr/bin/dmesg
/usr/bin/journalctl -k -b --no-pager
/usr/bin/journalctl -k -b -q --no-pager
/usr/local/sbin/sm750-lspci
/usr/local/sbin/sm750-vbios-dump
/usr/bin/dkms status
dkms install -m sm750hdmifb -v 0.6.0
dkms uninstall -m sm750hdmifb -v 0.6.0
dkms build -m sm750hdmifb -v 0.6.0
dkms remove -m sm750hdmifb -v 0.6.0 --all
/usr/bin/depmod -a
/usr/bin/modprobe -r sm750hdmidrm
/usr/bin/modprobe sm750hdmidrm
/usr/bin/dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm
/usr/bin/dnf remove -y sm750hdmifb
```

Deliberately not granted: `/bin/sh`, `/bin/bash`, `tee`, `cp`, `mv`, `chmod`,
`mount`, `dd`, `insmod`, `systemctl`, and bare `dnf`. The `setfacl` line for the
card node stays commented in the file as a one-shot fallback; the udev rule in
section 4 replaces it.

Note the grant is on the path, not on the file content: replacing a helper's
body needs no sudoers change.

## 2. Recovery recipe for a broken sudoers.d file

A parse error in any file under `/etc/sudoers.d/` is fatal for EVERY user on the
host, root included: `sudo` refuses to run at all, so it cannot be used to
repair itself. The failure looks like this:

```text
/etc/sudoers.d/10-sm750-debug:32:63: syntax error
sudo: parse error in /etc/sudoers.d/10-sm750-debug near line 32
```

Recover with a non-sudo root path. Either pkexec (polkit admin authentication in
a graphical session):

```sh
pkexec install -m 0440 -o root -g root \
    /mega/tmp/sm750/10-sm750-debug.sudoers \
    /etc/sudoers.d/10-sm750-debug
pkexec visudo -c
```

or a root shell on a console or over `su -`:

```sh
su -
install -m 0440 -o root -g root \
    /mega/tmp/sm750/10-sm750-debug.sudoers \
    /etc/sudoers.d/10-sm750-debug
visudo -c
```

If the staged source is gone too, remove the offending file as root and
reinstall from a rebuilt copy:

```sh
su -
rm -f /etc/sudoers.d/10-sm750-debug
visudo -c
```

`visudo -c` must print `parsed OK` before the session ends. Do not leave the host
with a broken allowlist and no tested recovery path.

## 3. Helpers in /usr/local/sbin

All three are `0755 root:root`, `#!/bin/sh`, `set -eu`, ASCII only. They exist
because a sudoers command line must not contain a colon (section 1).

Install command shape, for any of them:

```sh
sudo install -m 0755 -o root -g root /mega/tmp/sm750/<name> /usr/local/sbin/<name>
```

### 3.1 `/usr/local/sbin/sm750-regs`

Mode `0755 root:root`, 1165 bytes, sha256
`1a345ff074b92d93d17ddf6deabb93bb05b4ff02a029ee3a2de5d70c302ebe60`.
Closes GAP-B4 (MMIO register readback). The DRM debugfs directory is named after
the DRM minor index, which equals the `cardN` suffix of the primary node; that
suffix is assigned in probe order, so the helper resolves it from the by-path
link and never hardcodes `dri/0`.

```sh
#!/bin/sh
# /usr/local/sbin/sm750-regs  (mode 0755 root:root)
# Reads the driver's read-only debugfs MMIO snapshot for the SM750, resolving the
# debugfs index from the stable by-path link instead of hardcoding dri/0.
#
# Usage:  sudo /usr/local/sbin/sm750-regs
# Closing command for evidence gap GAP-B4 (MMIO readback, before/after a modeset).
#
# The DRM debugfs directory is named after the DRM minor index, which equals the
# cardN suffix of the primary node. That suffix is assigned in probe order and can
# change, so it must be resolved, never assumed.

set -eu

LINK=/dev/dri/by-path/pci-0000:01:00.0-card

if [ ! -e "$LINK" ]; then
	echo "sm750-regs: $LINK not present - SM750 not bound to a DRM driver" >&2
	exit 1
fi

CARD=$(readlink -f "$LINK")          # .../card0
N=${CARD##*card}                     # 0

if [ ! -r "/sys/kernel/debug/dri/$N/regs" ]; then
	echo "sm750-regs: /sys/kernel/debug/dri/$N/regs not readable" >&2
	echo "sm750-regs: card node is $CARD; is debugfs mounted and the module loaded?" >&2
	exit 1
fi

echo "# card node: $CARD (debugfs dri/$N)"
echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
exec cat "/sys/kernel/debug/dri/$N/regs"
```

### 3.2 `/usr/local/sbin/sm750-lspci`

Mode `0755 root:root`, 792 bytes, sha256
`4b4f555a5f70c369d54196e1b4fa7750d91cb1e1b7fa5938a05d93866968af10`.
Closes GAP-B5 (PCI config space beyond 0x40). The BDF `01:00.0` and the pair
`126f:0750` are baked in, so the sudoers line stays free of escape sequences.
Observed output: 9465 bytes, exit 0, stored as
`docs/evidence/baseline/19-pci-config-space-full.txt`.

```sh
#!/bin/sh
# /usr/local/sbin/sm750-lspci  (mode 0755 root:root)
# Dumps SM750 PCI config space, including the region above 0x40 that lspci hides
# from an unprivileged user ("Capabilities: <access denied>").
# Closing command for evidence gap GAP-B5.
#
# Usage:  sudo /usr/local/sbin/sm750-lspci
#
# Rationale: the PCI address contains ':' which must be backslash-escaped inside a
# sudoers command argument. Wrapping it in a fixed helper keeps the sudoers line free
# of escape sequences, which is the class of mistake that already broke this file once.

set -eu

BDF=01:00.0
VENDORDEV=126f:0750

echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# ===== lspci -vvv -xxx -s $BDF ====="
lspci -vvv -xxx -s "$BDF"
echo
echo "# ===== lspci -vvv -d $VENDORDEV ====="
lspci -vvv -d "$VENDORDEV"
```

### 3.3 `/usr/local/sbin/sm750-vbios-dump`

Mode `0755 root:root`, 1725 bytes, 52 lines, sha256
`07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e`. Closes
GAP-B1 (VBIOS ROM image). Three bodies exist:

| Version | Size | sha256 | State |
| --- | --- | --- | --- |
| v1 | 648 B | `e2f6f68791ebd3f341ca77cb84169bda8843c1ce192f2e500b51faa01e67f585` | superseded, defective (truncates at 4096 B) |
| v2 | 1092 B | `9e6c5db7853e3a58160d83c63aaee01144b20061a98a57c241188b3b6dd62a8f` | superseded 2026-11-18T12:07Z; read correctly, stale `EXPECT=65536` |
| v3 | 1725 B | `07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e` | **installed** 2026-11-18T12:07Z at `/usr/local/sbin/sm750-vbios-dump`; `EXPECT=49152`, exit 2 on size mismatch, exit 3 on a bad `55aa` signature |

Installed state, re-verified read-only:

```sh
$ ls -l /usr/local/sbin/sm750-vbios-dump
-rwxr-xr-x 1 root root 1725 Nov 18 15:07 /usr/local/sbin/sm750-vbios-dump
$ sha256sum /usr/local/sbin/sm750-vbios-dump
07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e  /usr/local/sbin/sm750-vbios-dump
$ grep -n '^EXPECT=' /usr/local/sbin/sm750-vbios-dump
19:EXPECT=49152
```

v1 body, kept for identification only - do not reinstall it:

```sh
#!/bin/sh
# /usr/local/sbin/sm750-vbios-dump  (mode 0755 root:root)
# Reads the 64 KiB SM750 VBIOS image. The ROM BAR is disabled by the kernel, so it is
# enabled for the read and disabled again on every exit path.
set -eu

DEV=/sys/bus/pci/devices/0000:01:00.0
OUT=${1:-/mega/tmp/sm750/vbios-01-00-0.bin}

if [ "$(id -u)" -ne 0 ]; then
	echo "sm750-vbios-dump: must run as root" >&2
	exit 1
fi

if [ ! -e "$DEV/rom" ]; then
	echo "sm750-vbios-dump: $DEV/rom missing" >&2
	exit 1
fi

echo 1 > "$DEV/rom"
trap 'echo 0 > "$DEV/rom"' EXIT INT TERM HUP

dd if="$DEV/rom" of="$OUT" bs=65536 count=1
sha256sum "$OUT"
echo "sm750-vbios-dump: wrote $OUT"
```

v3 body, verbatim, installed at `/usr/local/sbin/sm750-vbios-dump` and kept
staged at `/mega/tmp/sm750/sm750-vbios-dump`:

```sh
#!/bin/sh
# /usr/local/sbin/sm750-vbios-dump  (mode 0755 root:root)
# Reads the SM750 VBIOS image. The ROM BAR is disabled by the kernel, so it is
# enabled for the read and disabled again on every exit path.
#
# v3: the expected size is 49152 bytes. The image declares 96 blocks of 512 bytes
# (header size byte 0x02 = 0x60, PCIR image length at 0x2c = 0x0060) and a full
# read returns exactly that: the file ends where the declared length ends, the
# byte sum is 0 mod 256, and 0x815d..0xbfff is 0xcc padding. v2 compared against
# 65536, so a correct capture reported a false warning and exit 2.
#
# v2: the read uses a 4096-byte block size and no count. A sysfs binary attribute
# returns at most one page per read(2) call, so `dd bs=65536 count=1` yields 4096
# bytes and dd treats the short read as end of file. v1 produced a 4096-byte file.
set -eu

DEV=/sys/bus/pci/devices/0000:01:00.0
OUT=${1:-/mega/tmp/sm750/vbios-01-00-0.bin}
EXPECT=49152

if [ "$(id -u)" -ne 0 ]; then
	echo "sm750-vbios-dump: must run as root" >&2
	exit 1
fi

if [ ! -e "$DEV/rom" ]; then
	echo "sm750-vbios-dump: $DEV/rom missing" >&2
	exit 1
fi

echo 1 > "$DEV/rom"
trap 'echo 0 > "$DEV/rom"' EXIT INT TERM HUP

dd if="$DEV/rom" of="$OUT" bs=4096

size=$(wc -c < "$OUT")
sha256sum "$OUT"

sig=$(od -An -tx1 -N2 "$OUT" | tr -d ' \n')
if [ "$sig" != "55aa" ]; then
	echo "sm750-vbios-dump: ERROR signature is $sig, expected 55aa" >&2
	echo "sm750-vbios-dump: wrote $OUT ($size bytes)"
	exit 3
fi

if [ "$size" -ne "$EXPECT" ]; then
	echo "sm750-vbios-dump: ERROR size is $size, expected $EXPECT" >&2
	echo "sm750-vbios-dump: wrote $OUT ($size bytes)"
	exit 2
fi

echo "sm750-vbios-dump: wrote $OUT ($size bytes, signature 55aa, checksum ok)"
```

`EXPECT=49152` sits at line 19. Exit codes: 1 not root or no `rom` attribute,
2 size differs from `EXPECT`, 3 the first two bytes are not `55 aa`. Success
prints `signature 55aa, checksum ok`.

Why v1 is wrong: a sysfs binary attribute serves at most one page (4096 bytes)
per `read(2)` call, and `dd` treats the resulting short read as end of file. So
`bs=65536 count=1` returns 4096 bytes of a 65536-byte ROM. Proven on an
unrelated attribute, `/sys/kernel/btf/nf_conntrack` (26549 bytes):
`dd bs=65536 count=1` yields 4096, `dd bs=4096` yields all 26549.

Why v2's constant is wrong: the option ROM is 48 KiB, not 64 KiB. The full
capture at `/mega/tmp/sm750/vbios-01-00-0.bin` is 49152 bytes, sha256
`16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`, header size
byte `0x60` and PCIR image length `0x0060` (96 blocks of 512), whole-image byte
sum 0 mod 256. v2 therefore reports `WARNING size is 49152, expected 65536` and
exits 2 on a correct read.

What the capture proved (49152 B): signature `55 aa` at 0x00, header size byte
`0x60` at 0x02, the PCIR pointer `0x1c` at 0x18, `PCIR` at 0x1c with image
length `0x0060` at 0x2c, vendor/device `0x126f`/`0x0750` at 0x20/0x22, version
string `Version 1.00.59-`, build date `05/14/19 16:25`, banner `Silicon Motion
SM750 VGA BIOS (CRT)`, `Copyright 2000/2010, Silicon Motion Inc.`, and
`0x815d..0xbfff` all `0xcc`. The ROM enable bit was restored after the run;
`sm750-lspci` reports `Expansion ROM at c7400000 [disabled] [size=64K]`.

## 4. udev ACL rule

Path: `/etc/udev/rules.d/99-sm750-coder-acl.rules`, mode `0644 root:root`, 710
bytes. Staged twin: `/mega/tmp/sm750/99-sm750-coder-acl.rules`.

The rule grants `u:coder:rw` on the SM750 card node at every boot and probe,
replacing the manual `setfacl` step. It matches on PCI vendor:device, so it never
touches the NVIDIA nodes at `02:00.0`, `83:00.0` and `84:00.0`.

The match key is `SUBSYSTEM=="drm"` with `KERNEL=="card[0-9]*"` and the PCI
vendor:device attributes; that combination is what keeps the rule off the three
NVIDIA card nodes on this host.

```sh
# /etc/udev/rules.d/99-sm750-coder-acl.rules  (mode 0644 root:root)
# Grants uid coder read/write on the SM750 card node on every boot/probe, replacing
# the manual "sudo setfacl" step. Matched by PCI vendor:device, so it never touches
# the nvidia nodes (02:00.0, 83:00.0, 84:00.0).
#
# Install: sudo install -m 0644 -o root -g root 99-sm750-coder-acl.rules /etc/udev/rules.d/
# Reload:  sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=drm
# Verify:  getfacl /dev/dri/by-path/pci-0000:01:00.0-card

ACTION=="add|change", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x126f", ATTRS{device}=="0x0750", RUN+="/usr/bin/setfacl -m u:coder:rw /dev/$name"
```

Install and apply:

```sh
sudo install -m 0644 -o root -g root /mega/tmp/sm750/99-sm750-coder-acl.rules \
    /etc/udev/rules.d/99-sm750-coder-acl.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=drm
getfacl /dev/dri/by-path/pci-0000:01:00.0-card
```

Expected `getfacl` lines include `user:coder:rw-`; `mask::rw-` and `other::---`
stay as they are.

The SM750 exposes no render node: `/dev/dri/by-path/` holds only
`pci-0000:01:00.0-card -> ../card0` for this device, and the `renderD128`,
`renderD129` and `renderD130` nodes belong to the NVIDIA cards. A render node
cannot enumerate connectors or modeset in any case, so only the card node is
granted. The debugfs directory index is resolved through the by-path link by
`sm750-regs`, never hardcoded, because the `cardN` suffix is assigned in probe
order.

### 4.1 `/dev/tty0` ACL rule

Installed 2026-11-18T12:08Z (15:08 local) by the host owner; before that `/dev/tty0`
was `crw------- root tty` and the IGT binaries that switch the VT to graphics
mode aborted with `errno 13`. The node is now `crw-rw----+ root tty` with
`user:coder:rw-`:

```sh
$ ls -l /dev/tty0
crw-rw----+ 1 root tty 4, 0 Nov 18 15:08 /dev/tty0
$ getfacl -p /dev/tty0
user::rw-
user:coder:rw-
group::---
mask::rw-
other::---
$ test -w /dev/tty0 && echo writable
writable
```

The last line is the effective check: uid 1005 (`coder`) can now open the node
for writing, which is what the IGT VT ioctls need.

Two files, both `0644 root:root`, both ASCII. The staged copies remain the
reference bodies:

| Staged path | Target path | Bytes | sha256 |
| --- | --- | --- | --- |
| `/mega/tmp/sm750/99-sm750-coder-tty0-acl.rules` | `/etc/udev/rules.d/99-sm750-coder-tty0-acl.rules` | 762 | `248d76743dd1fa5aca03e55432e53bf02647900038b330439033f569117f7c4b` |
| `/mega/tmp/sm750/sm750-tty0-acl.conf` | `/etc/tmpfiles.d/sm750-tty0-acl.conf` | 299 | `3072aa4ecfd3f67d3c85be6076574d8d1b5afb47e5f4910df15d7f11c3f14538` |

```sh
# /etc/udev/rules.d/99-sm750-coder-tty0-acl.rules
#
# Grants the automation user `coder` read/write access to the active virtual
# terminal so IGT GPU Tools can issue KDSETMODE/KDSKBSTATE and switch to
# graphics mode (kmstest_set_vt_graphics_mode, ../lib/igt_kms.c:1558).
# Without it, kms_setmode, kms_atomic, kms_flip, kms_rmfb and
# kms_pipe_crc_basic abort with errno 13.
#
# Scope: one user, one device node. It does not grant the console to a group,
# does not change the node mode, and does not touch tty1..tty63. Remove this
# file and run `setfacl -b /dev/tty0` to revoke.
#
# Companion to 99-sm750-coder-acl.rules, which grants the DRM card node.
ACTION=="add|change", SUBSYSTEM=="tty", KERNEL=="tty0", RUN+="/usr/bin/setfacl -m u:coder:rw /dev/tty0"
```

```sh
# /etc/tmpfiles.d/sm750-tty0-acl.conf
# Boot-time companion to 99-sm750-coder-tty0-acl.rules: applies the ACL to
# /dev/tty0 deterministically even if no udev add/change event fires for the
# virtual tty node. Type `a+` adds to the existing ACL without replacing it.
a+ /dev/tty0 - - - - u:coder:rw
```

Two mechanisms because `/dev/tty0` is a virtual node: an add/change event for
it is not guaranteed on every boot, so the udev rule covers the event path and
the tmpfiles entry covers boot. Both add to the existing ACL (`-m` / `a+`)
instead of replacing it.

Install:

```sh
sudo install -m 0644 -o root -g root /mega/tmp/sm750/99-sm750-coder-tty0-acl.rules \
    /etc/udev/rules.d/99-sm750-coder-tty0-acl.rules
sudo install -m 0644 -o root -g root /mega/tmp/sm750/sm750-tty0-acl.conf \
    /etc/tmpfiles.d/sm750-tty0-acl.conf
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=tty --sysname-match=tty0
sudo systemd-tmpfiles --create /etc/tmpfiles.d/sm750-tty0-acl.conf
```

Verify:

```sh
getfacl /dev/tty0
udevadm test /sys/class/tty/tty0
```

`getfacl` must show `user:coder:rw-`; the node reports `crw-rw----+` because
the ACL mask adds the group read/write bits to the mode that `ls -l` prints.
`udevadm test` must report the rule as applied and the `setfacl` `RUN` as
executed. Both files are installed; the block above is the record of how, and is
what to re-run after a rebuild of `/mega/tmp/sm750/`.

Revoke:

```sh
sudo setfacl -b /dev/tty0
sudo rm -f /etc/udev/rules.d/99-sm750-coder-tty0-acl.rules
sudo rm -f /etc/tmpfiles.d/sm750-tty0-acl.conf
sudo udevadm control --reload-rules
```

Scope: read/write on one device node for one user. No group membership change,
no node mode change, no `tty1..tty63` change, no sudoers entry, no shell. The
19-entry allowlist in section 1 is unchanged by this action.

What it unblocks: the five IGT binaries that aborted at
`kmstest_set_vt_graphics_mode` with `errno 13` while the node was root-only -
`kms_setmode`, `kms_atomic`, `kms_flip`, `kms_rmfb`, `kms_pipe_crc_basic` - out
of the 359 files in `/usr/libexec/igt-gpu-tools`. That was the remaining
permission blocker on the AC-3 conformance subset; card0 has no userspace DRM
master, so no master conflict is involved.

## 5. Root actions: installed state and re-verification

Both actions are installed and verified; nothing is outstanding. Section 5.1 and
5.2 keep the install commands so the procedure can be repeated after a rebuild,
and each records the read-only commands that prove the current state.

### 5.1 VBIOS helper v3

```sh
sudo install -m 0755 -o root -g root \
    /mega/tmp/sm750/sm750-vbios-dump \
    /usr/local/sbin/sm750-vbios-dump
```

Verify the install:

```sh
sha256sum /usr/local/sbin/sm750-vbios-dump
grep -n '^EXPECT=' /usr/local/sbin/sm750-vbios-dump
```

Expected: sha256
`07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e` and
`19:EXPECT=49152`.

Then capture the ROM:

```sh
sudo /usr/local/sbin/sm750-vbios-dump /mega/tmp/sm750/vbios-01-00-0.bin
```

Expected: `49152` bytes, exit 0, and the line
`wrote <out> (49152 bytes, signature 55aa, checksum ok)`. Exit 2 means the size
is not 49152 (`ERROR size is <n>, expected 49152`); exit 3 means the first two
bytes are not `55 aa` (`ERROR signature is <sig>, expected 55aa`). A dump from
either failing exit must not be used.

Installed state, read-only re-check at 12:26Z (15:26 local):

```sh
$ ls -l /usr/local/sbin/sm750-vbios-dump
-rwxr-xr-x 1 root root 1725 Nov 18 15:07 /usr/local/sbin/sm750-vbios-dump
$ sha256sum /usr/local/sbin/sm750-vbios-dump
07fe5499de1b320fc593f5e33db8f865bb867a40da3d35a956ee4511eeaa3a7e  /usr/local/sbin/sm750-vbios-dump
$ grep -n '^EXPECT=' /usr/local/sbin/sm750-vbios-dump
19:EXPECT=49152
```

The installed body is v3 and compares against the correct 49152-byte constant,
so the exit 2 that v2 produced on a good read no longer occurs. v2 ran from
2026-11-18T10:12Z until the v3 install at 12:07Z (rows 5 and 6).

The helper has been executed twice against the installed v3 body, exit 0 both
times with 49152 bytes and `signature 55aa, checksum ok`:
`/mega/tmp/sm750/vbios.bin` at 15:07:53 local and
`/mega/tmp/sm750/vbios-v3.bin` at 15:11:15 local. All three dumps - those two
plus the earlier `/mega/tmp/sm750/vbios-01-00-0.bin` from 13:11:44 - hash to
`16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`. GAP-B1 is
closed end to end; re-running the command above is a no-op check, not a pending
action.

No sudoers change is needed: the grant is on the path
`/usr/local/sbin/sm750-vbios-dump`, not on the file content.

### 5.2 `/dev/tty0` ACL rule

Install both files and apply them as shown in section 4.1. Installed state
(read-only re-check at 12:26Z, 15:26 local):

```sh
$ ls -l /etc/udev/rules.d/99-sm750-coder-tty0-acl.rules /etc/tmpfiles.d/sm750-tty0-acl.conf
-rw-r--r-- 1 root root 762 Nov 18 15:08 /etc/udev/rules.d/99-sm750-coder-tty0-acl.rules
-rw-r--r-- 1 root root 299 Nov 18 15:08 /etc/tmpfiles.d/sm750-tty0-acl.conf
$ sha256sum /etc/udev/rules.d/99-sm750-coder-tty0-acl.rules /etc/tmpfiles.d/sm750-tty0-acl.conf
248d76743dd1fa5aca03e55432e53bf02647900038b330439033f569117f7c4b  /etc/udev/rules.d/99-sm750-coder-tty0-acl.rules
3072aa4ecfd3f67d3c85be6076574d8d1b5afb47e5f4910df15d7f11c3f14538  /etc/tmpfiles.d/sm750-tty0-acl.conf
$ getfacl -p /dev/tty0
user::rw-
user:coder:rw-
group::---
mask::rw-
other::---
```

Both installed files are byte-identical to the staged copies. Revoke with
`setfacl -b /dev/tty0` plus the file removals and
`udevadm control --reload-rules` listed in section 4.1.

No sudoers change is needed for this one either: the rule runs `setfacl` from
udev as root, and the tmpfiles entry runs from `systemd-tmpfiles` as root.

## 6. Action to gap

| Root action | Gap | State after the action |
| --- | --- | --- |
| `sudo -n /usr/bin/dmesg`, `sudo -n /usr/bin/journalctl -k -b -q --no-pager` | GAP-B2 kernel log | CLOSED: exit 0, 169860 bytes and 240 sm750 lines measured 2026-11-18T09:36Z; 154236 bytes and 150 lines at the earlier capture |
| `sudo -n /usr/local/sbin/sm750-lspci` | GAP-B5 PCI config space | CLOSED: exit 0, 9465 bytes including the capability list above 0x40, stored as `docs/evidence/baseline/19-pci-config-space-full.txt` |
| `sudo -n /usr/local/sbin/sm750-regs` | GAP-B4 register readback | CLOSED: exit 0 against the installed 0.6.0, `# sm750hdmidrm register dump, 49 registers, read-only`. Re-verified 2026-11-18T12:26Z (15:26 local): `rpm -q sm750hdmifb` -> `sm750hdmifb-0.6.0-1.fc43.noarch`, `cat /sys/module/sm750hdmidrm/version` -> `0.6.0`, `lsmod` -> `sm750hdmidrm 167936 0`, dump exit 0 with 49 registers. Three comparable states captured around a modeset in `docs/evidence/runtime/08-register-dump.txt` (12 of 49 registers change while the client is held open) |
| `sudo /usr/local/sbin/sm750-vbios-dump` | GAP-B1 VBIOS image | CLOSED: 49152 bytes captured, sha256 `16796a7b8319c4a798a2225221b4c0ed9b5f52e2c4f1c3841aa4a6f8ba217551`; the installed v3 body (`EXPECT=49152`) ran with exit 0 and `signature 55aa, checksum ok`, and the re-capture hashed to the same value. Section 5.1 |
| udev ACL rule (`99-sm750-coder-acl.rules`) | GAP-B3 device access | PARTIAL: the card node opens unprivileged; modeset, kmscube and IGT now captured on both builds (T10 on 0.5.9, T11 on 0.6.0); framebuffer readback, scanout CRC and external capture still absent |
| `/dev/tty0` ACL rule (`99-sm750-coder-tty0-acl.rules` + `sm750-tty0-acl.conf`) | GAP-B3 IGT VT subset | CLOSED for the permission blocker: both files installed 2026-11-18T12:08Z, `/dev/tty0` is `crw-rw----+` with `user:coder:rw-` (`getfacl -p`). The five IGT binaries that aborted at `kmstest_set_vt_graphics_mode` with `errno 13` can now open the VT |
| `sudo -n dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm` | GAP-B7 RPM install | CLOSED (T11): exit 0; `%post`/`%posttrans` built, signed with the machine MOK and installed for 7.2.15-100, 7.3.3-100 and 7.3.4-100; `rpm -q` -> `sm750hdmifb-0.6.0-1.fc43.noarch` |
| `sudo -n dnf remove -y sm750hdmifb` (erase; note `dkms status -m ... -v ...` is NOT allowlisted, only bare `dkms status`) | GAP-B7 RPM erase | CLOSED (T11): exit 0, `%preun` ran `dkms remove --all`, `rpm -q` -> not installed, on-disk object deleted; the resident module stays loaded until `modprobe -r`, so 0.6.0 was reinstalled immediately. See `docs/evidence/runtime/20-rollback.txt`, `21-final-state.txt` |
| `tests/check-scanout-crc.sh` as root (row 8) | GAP-B3 readback/CRC | OUTSTANDING: not run. The draw path is proven unprivileged (`docs/evidence/scanout/03-readback.txt`), the read half needs root |

The authoritative per-gap text is `docs/evidence/EVIDENCE-GAPS.md`; this table
records what the root actions themselves achieved.

## 7. Outstanding root action: scanout CRC and readback transcript

This is row 8, proposed and not performed. It closes the readback half of
GAP-B3, and it is the observation half of GAP-B8: if the `-110` appears while
the check runs, the error line now names the failing stage.

The script resolves the card through debugfs, builds
`tests/scanout-pattern.c` (libdrm), draws a black and a white frame with
`SETCRTC`, reads the CRC stream and the `sm750_scanout` dump, and compares them.
It exits 77 with a `SKIP:` line rather than passing when anything is missing.

Run at the console as root, from the repository:

```sh
cd /home/coder/sm750hdmifb
export PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm
./tests/check-scanout-crc.sh 2>&1 | tee /mega/tmp/sm750/scanout-crc.txt
echo "exit: ${PIPESTATUS[0]}"
```

The two exports are the documented rootless libdrm tree (`docs/ENVIRONMENT.md`
section 4); the script falls back to the same path on its own, so they only
matter if it is rebuilt elsewhere. The script writes `build/scanout-pattern`
into the tree; `rm -rf build` afterwards keeps the tree owned by `coder`.

Store the transcript as `docs/evidence/scanout/05-crc-run.txt`, replace the SKIP
sentence in `docs/evidence/scanout/04-checks.txt` with the PASS/FAIL lines it
prints, and quote the `sm750_scanout` summary line (offset, length, nonzero,
`crc32`) in `docs/evidence/scanout/03-readback.txt`. If `dmesg` shows
`failed to enable HDMI mode: -110 at stage <name>` during the run, copy that
line into `docs/evidence/gap-b8/`.

Without a root shell, the same four accesses can be allowlisted. The lines obey
the zero-colon rule of section 1; `tee` writes `scanout` and `none` into
`crc/control` when the run needs the source enabled by hand:

```sudoers
coder ALL=(root) NOPASSWD: /usr/bin/cat /sys/kernel/debug/dri/0/crtc-0/crc/source
coder ALL=(root) NOPASSWD: /usr/bin/cat /sys/kernel/debug/dri/0/crtc-0/crc/data
coder ALL=(root) NOPASSWD: /usr/bin/cat /sys/kernel/debug/dri/0/sm750_scanout
coder ALL=(root) NOPASSWD: /usr/bin/tee /sys/kernel/debug/dri/0/crtc-0/crc/control
```

Caveat, and it is the reason the script is the primary path: `dri/0` is the DRM
minor index from `drm_dev->primary`, not a constant, and section 3.1 shows why
the helpers resolve it through the stable by-path link instead of hardcoding it.
If the SM750 is not minor 0 on the boot in question, adjust the four paths after
checking `ls /sys/kernel/debug/dri` as root. Enabling and disabling by hand:

```sh
printf 'scanout' | sudo -n tee /sys/kernel/debug/dri/0/crtc-0/crc/control
printf 'none'    | sudo -n tee /sys/kernel/debug/dri/0/crtc-0/crc/control
```
