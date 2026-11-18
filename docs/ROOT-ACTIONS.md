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

| # | Date (UTC) | Action | Closes |
| --- | --- | --- | --- |
| 1 | 2026-11-18T06:15Z | install `/etc/udev/rules.d/99-sm750-coder-acl.rules` | GAP-B3 (partial) |
| 2 | 2026-11-18T08:37Z | install the three helpers in `/usr/local/sbin` | GAP-B4, GAP-B5, GAP-B1 |
| 3 | 2026-11-18T08:37Z | install `/etc/sudoers.d/10-sm750-debug` (0440) | GAP-B2, GAP-B4, GAP-B5, GAP-B7 |
| 4 | 2026-11-18T08:37Z | run the VBIOS helper once | GAP-B1 (attempt, truncated) |
| 5 | pending | reinstall the VBIOS helper with the v2 body | GAP-B1 |

Sections below are ordered by subject, not by date: allowlist, recovery recipe,
helpers, udev rule, pending action, gap map.

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
Observed output: 9465 bytes, exit 0.

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

Closes GAP-B1 (VBIOS ROM image). Two bodies exist:

| Version | Size | sha256 | State |
| --- | --- | --- | --- |
| v1 | 648 B | `e2f6f68791ebd3f341ca77cb84169bda8843c1ce192f2e500b51faa01e67f585` | **installed**, defective |
| v2 | 1092 B | `9e6c5db7853e3a58160d83c63aaee01144b20061a98a57c241188b3b6dd62a8f` | staged, **pending install** |

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

v2 body, verbatim, staged at `/mega/tmp/sm750/sm750-vbios-dump`:

```sh
#!/bin/sh
# /usr/local/sbin/sm750-vbios-dump  (mode 0755 root:root)
# Reads the 64 KiB SM750 VBIOS image. The ROM BAR is disabled by the kernel, so it is
# enabled for the read and disabled again on every exit path.
#
# v2: the read uses a 4096-byte block size and no count. A sysfs binary attribute
# returns at most one page per read(2) call, so `dd bs=65536 count=1` yields 4096
# bytes and dd treats the short read as end of file. v1 produced a 4096-byte file.
set -eu

DEV=/sys/bus/pci/devices/0000:01:00.0
OUT=${1:-/mega/tmp/sm750/vbios-01-00-0.bin}
EXPECT=65536

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
if [ "$size" -ne "$EXPECT" ]; then
	echo "sm750-vbios-dump: WARNING size is $size, expected $EXPECT" >&2
	echo "sm750-vbios-dump: wrote $OUT"
	exit 2
fi
echo "sm750-vbios-dump: wrote $OUT ($size bytes)"
```

Why v1 is wrong: a sysfs binary attribute serves at most one page (4096 bytes)
per `read(2)` call, and `dd` treats the resulting short read as end of file. So
`bs=65536 count=1` returns 4096 bytes of a 65536-byte ROM. Proven on an
unrelated attribute, `/sys/kernel/btf/nf_conntrack` (26549 bytes):
`dd bs=65536 count=1` yields 4096, `dd bs=4096` yields all 26549.

What the truncated dump did prove (`/mega/tmp/sm750/vbios-01-00-0.bin`, 4096 B):
signature `55 aa`, `PCIR` structure at 0x18, vendor/device `0x126f`/`0x0750` at
0x1c/0x1e, version string `Version 1.00.59-`, build date `05/14/19 16:25`,
banner `Silicon Motion SM750 VGA BIOS (CRT)`, `Copyright 2000/2010, Silicon
Motion Inc.`. The ROM enable bit was restored after the run; `sm750-lspci`
reports `Expansion ROM at c7400000 [disabled] [size=64K]`.

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

## 5. Pending root action

One item is outstanding.

```sh
sudo install -m 0755 -o root -g root \
    /mega/tmp/sm750/sm750-vbios-dump \
    /usr/local/sbin/sm750-vbios-dump
```

Then capture the full ROM:

```sh
sudo /usr/local/sbin/sm750-vbios-dump /mega/tmp/sm750/vbios-01-00-0.bin
```

Expected: `65536` bytes, exit 0. A size other than 65536 exits 2 with
`WARNING size is <n>, expected 65536` and the dump must not be used.

Why: the installed v1 body used `dd bs=65536 count=1`, and a sysfs binary
attribute returns at most one page per `read(2)`, so the dump was truncated to
4096 bytes of a 65536-byte ROM. v2 uses `dd bs=4096` with no count and exits 2
when the size is not 65536.

No sudoers change is needed: the grant is on the path
`/usr/local/sbin/sm750-vbios-dump`, not on the file content.

## 6. Action to gap

| Root action | Gap | State after the action |
| --- | --- | --- |
| `sudo -n /usr/bin/dmesg`, `sudo -n /usr/bin/journalctl -k -b -q --no-pager` | GAP-B2 kernel log | CLOSED: exit 0, 169860 bytes and 240 sm750 lines measured 2026-11-18T09:36Z; 154236 bytes and 150 lines at the earlier capture |
| `sudo -n /usr/local/sbin/sm750-lspci` | GAP-B5 PCI config space | CLOSED: exit 0, 9465 bytes including the capability list above 0x40 |
| `sudo -n /usr/local/sbin/sm750-regs` | GAP-B4 register readback | GAP: the debugfs facility exists, but the 0.6.0 module is not installed yet (T11) |
| `sudo /usr/local/sbin/sm750-vbios-dump` | GAP-B1 VBIOS image | PARTIAL: 4096 of 65536 bytes captured; awaiting the v2 reinstall |
| udev ACL rule | GAP-B3 device access | PARTIAL: the card node opens unprivileged; no modeset, framebuffer readback, scanout CRC or external capture yet |
| `sudo -n dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm` | GAP-B7 RPM install | GAP: granted, not yet executed |
| `sudo -n dnf remove -y sm750hdmifb` and `sudo -n dkms status -m sm750hdmifb -v 0.6.0` | GAP-B7 RPM erase | GAP: granted, not yet executed |

The authoritative per-gap text is `docs/evidence/EVIDENCE-GAPS.md`; this table
records what the root actions themselves achieved.
