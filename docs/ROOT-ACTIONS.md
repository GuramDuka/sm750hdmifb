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
commands are in section 7. Row 9 was installed by the host owner on
2026-11-21T10:28Z; the console helper is section 3.4. Row 10's helper is
installed, but the installed body is stale: the file in `/usr/local/sbin` is the
11873-byte revision, not the current source, and section 3.8 carries the
one-line refresh. Its single allowlist line replaces the per-version
`dnf install` entries. Related operational hazard: an erase followed by
a reboot leaves the card with no driver; the recovery runbook is in `README.md`,
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
| 8 | proposed | rebuild the module from the working tree, reload it, then run `tests/check-scanout-crc.sh` once as root and store the transcript (section 7) | GAP-B3 readback/CRC half; GAP-B8 if the `-110` recurs during the run |
| 9 | 2026-11-21T10:28Z | install the console helper `/usr/local/sbin/sm750-console` (144-line source `tools/sm750-console.sh`, sha256 `6e7f5dc758ec6b8d7993466784ffa5b1ab379da4f7442a6228c620829f2b1338`; the installed copy is byte-identical) and add one NOPASSWD line for it (section 3.4) | the one-command `KD_TEXT` route for a panel that looks dead (A34); no GAP |
| 10 | 2026-11-22T08:41Z | install `/usr/local/sbin/sm750-pkg` and one NOPASSWD line `/etc/sudoers.d/30-sm750-pkg` (section 3.8); source is 487 lines, sha256 `ca6e7b0a66fae43b6b332135ea8da62f61a917385accacc4d48f114e9149cf16`, but the installed body is stale, refresh required (11873 bytes, sha256 `e923a85a3389a13211869f32808b7b7cb77083355f90c5149b6c94cdaf9b976e`) | replaces the per-version `dnf install` allowlist entries; privileged install, remove, status and reload work for any version without the owner |
| 11 | proposed | install `/usr/local/sbin/sm750-vt` and the two NOPASSWD lines `/usr/local/sbin/sm750-vt off` and `/usr/local/sbin/sm750-vt on` (section 3.12), then run `sm750-vt off` to load the 0.6.7 module without a reboot | the reload blocker: a rebuilt module cannot be loaded while fbcon holds it (`modprobe: FATAL: Module sm750hdmidrm is in use.`) |

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

### The 76 NOPASSWD entries

`sudo -n -l` lists 76 distinct NOPASSWD command lines, measured 2026-11-25:
73 for this work plus three that predate it (`/usr/bin/dmidecode`,
`/usr/local/cuda/bin/ncu`, `/usr/local/cuda/bin/nvprof`). Of the 73, 45 are
`modprobe` lines - 22 loads and 23 `-r` removals, covering the 21 DRM KUnit
suites in section 3.9 above plus `kunit` and `sm750hdmidrm` - and 28 are the
helper, `dkms`, log and RPM lines. `/usr/bin/nice` is no longer granted: the
host owner removed it, because a general utility that can run an arbitrary
program as root is precisely the hole this allowlist exists to avoid. The 76,
copied verbatim from that measurement:

```text
/usr/bin/depmod -a
/usr/bin/dkms build -m sm750hdmifb -v 0.6.0
/usr/bin/dkms build -m sm750hdmifb -v 0.6.1
/usr/bin/dkms install -m sm750hdmifb -v 0.6.0
/usr/bin/dkms install -m sm750hdmifb -v 0.6.1
/usr/bin/dkms remove -m sm750hdmifb -v 0.6.0 --all
/usr/bin/dkms remove -m sm750hdmifb -v 0.6.1 --all
/usr/bin/dkms status
/usr/bin/dkms uninstall -m sm750hdmifb -v 0.6.0
/usr/bin/dkms uninstall -m sm750hdmifb -v 0.6.1
/usr/bin/dmesg
/usr/bin/dmidecode
/usr/bin/dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.0-1.fc43.noarch.rpm
/usr/bin/dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.1-1.fc43.noarch.rpm
/usr/bin/dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-1.fc43.noarch.rpm
/usr/bin/dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-2.fc43.noarch.rpm
/usr/bin/dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-3.fc43.noarch.rpm
/usr/bin/dnf remove -y sm750hdmifb
/usr/bin/journalctl -k -b --no-pager
/usr/bin/journalctl -k -b -q --no-pager
/usr/bin/modprobe drm_atomic_commit_test
/usr/bin/modprobe drm_atomic_test
/usr/bin/modprobe drm_bridge_test
/usr/bin/modprobe drm_cmdline_parser_test
/usr/bin/modprobe drm_connector_test
/usr/bin/modprobe drm_damage_helper_test
/usr/bin/modprobe drm_dp_mst_helper_test
/usr/bin/modprobe drm_exec_test
/usr/bin/modprobe drm_fixp_test
/usr/bin/modprobe drm_format_helper_test
/usr/bin/modprobe drm_format_test
/usr/bin/modprobe drm_framebuffer_test
/usr/bin/modprobe drm_gem_shmem_test
/usr/bin/modprobe drm_hdmi_state_helper_test
/usr/bin/modprobe drm_managed_test
/usr/bin/modprobe drm_mm_test
/usr/bin/modprobe drm_modes_test
/usr/bin/modprobe drm_plane_helper_test
/usr/bin/modprobe drm_probe_helper_test
/usr/bin/modprobe drm_rect_test
/usr/bin/modprobe drm_sysfb_modeset_test
/usr/bin/modprobe -r drm_atomic_commit_test
/usr/bin/modprobe -r drm_atomic_test
/usr/bin/modprobe -r drm_bridge_test
/usr/bin/modprobe -r drm_cmdline_parser_test
/usr/bin/modprobe -r drm_connector_test
/usr/bin/modprobe -r drm_damage_helper_test
/usr/bin/modprobe -r drm_dp_mst_helper_test
/usr/bin/modprobe -r drm_exec_test
/usr/bin/modprobe -r drm_fixp_test
/usr/bin/modprobe -r drm_format_helper_test
/usr/bin/modprobe -r drm_format_test
/usr/bin/modprobe -r drm_framebuffer_test
/usr/bin/modprobe -r drm_gem_shmem_test
/usr/bin/modprobe -r drm_hdmi_state_helper_test
/usr/bin/modprobe -r drm_managed_test
/usr/bin/modprobe -r drm_mm_test
/usr/bin/modprobe -r drm_modes_test
/usr/bin/modprobe -r drm_plane_helper_test
/usr/bin/modprobe -r drm_probe_helper_test
/usr/bin/modprobe -r drm_rect_test
/usr/bin/modprobe -r drm_sysfb_modeset_test
/usr/bin/modprobe -r kunit
/usr/bin/modprobe -r sm750hdmidrm
/usr/bin/modprobe sm750hdmidrm
/usr/bin/sm750-smi
/usr/local/cuda/bin/ncu
/usr/local/cuda/bin/nvprof
/usr/local/sbin/sm750-console
/usr/local/sbin/sm750-crc
/usr/local/sbin/sm750-crc-cycle
/usr/local/sbin/sm750-headless
/usr/local/sbin/sm750-lspci
/usr/local/sbin/sm750-pkg
/usr/local/sbin/sm750-regs
/usr/local/sbin/sm750-vbios-dump
```

Deliberately not granted: `/bin/sh`, `/bin/bash`, `tee`, `cp`, `mv`, `chmod`,
`mount`, `dd`, `insmod`, `systemctl`, `kill`, and bare `dnf`. `kill` is in this
list for a measured reason: `sudo -n kill` prompts for a password, so an
orphaned helper process can only be cleared by the host owner. That is the
intended state, not a gap - a NOPASSWD `kill` would signal any process on the
host as root. The `setfacl` line for the
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

### 3.4 `/usr/local/sbin/sm750-console` (installed 2026-11-21T10:28Z)

Installed `0755 root:root`, 4009 bytes, 144 lines, sha256
`6e7f5dc758ec6b8d7993466784ffa5b1ab379da4f7442a6228c620829f2b1338`, mtime
2026-11-21 13:28 local (MSK). The installed file is byte-identical to its source
`tools/sm750-console.sh` and to the staged copy `/mega/tmp/sm750/sm750-console`.
It closes no GAP: it is the operational route for A34, the panel that looks
dead because no client paints it. It needs root because `chvt` needs
`CAP_SYS_TTY_CONFIG` and the debugfs files it reads are mode 0700.

Reinstall (host owner, root), from the repository root:

```sh
sudo install -m 0755 -o root -g root \
    tools/sm750-console.sh \
    /usr/local/sbin/sm750-console
```

Add one line to the allowlist in section 1, then re-run `sudo -n -l` and the
colon audit:

```text
coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-console
```

Body:

```sh
#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# sm750-console - inspect and move the SM750 panel between the text console
# and the graphical session.
#
# The panel is dark while the foreground VT is KD_GRAPHICS: the kernel console
# drops output before fbcon (drivers/tty/vt/vt.c, do_con_write) and a Wayland
# session on another card paints nothing on card0. Switching the foreground VT
# to a text VT puts the VT back into KD_TEXT, fbcon binds and the console
# reaches the panel. This script is that one-command route, plus the status an
# operator needs afterwards.
#
# Exit codes:
#   0  the requested action ran and the status was printed
#   1  environment problem (not root, no /dev/tty0, chvt failed, no SM750 card)
#   2  bad usage
set -u

PROG=sm750-console
DEBUGFS=/sys/kernel/debug

usage() {
	echo "usage: $PROG show | text [N] | graphics" >&2
	exit 2
}

say() { printf '%s\n' "$*"; }
fail() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

[ $# -ge 1 ] || usage
action=$1
shift
case "$action" in
show|text|graphics) ;;
*) usage ;;
esac

[ "$(id -u)" -eq 0 ] || fail "root is required: debugfs is mode 0700 and chvt needs CAP_SYS_TTY_CONFIG"
[ -e /dev/tty0 ] || fail "/dev/tty0 is missing"

# 0x4B3B is KDGETMODE on the tty file descriptor: 0 KD_TEXT, 1 KD_GRAPHICS,
# 4 KD_KDWANTED.
vt_mode=$(python3 -c '
import fcntl, struct, sys
f = open("/dev/tty0", "rb")
sys.stdout.write(str(struct.unpack("i", fcntl.ioctl(f.fileno(), 0x4B3B,
                                                     struct.pack("i", 0)))[0]))
' 2>/dev/null) || fail "cannot read the VT mode of /dev/tty0 with KDGETMODE"

mode_name() {
	case "$1" in
	0) echo KD_TEXT ;;
	1) echo KD_GRAPHICS ;;
	4) echo KD_KDWANTED ;;
	*) echo "unknown($1)" ;;
	esac
}

show_status() {
	active=$(cat /sys/class/tty/tty0/active 2>/dev/null) || active=
	say "active tty:   ${active:-unknown}"
	say "tty0 mode:    $(mode_name "$vt_mode") ($vt_mode)"

	for vc in /sys/class/vtconsole/vtcon*; do
		[ -r "$vc/name" ] || continue
		name=$(cat "$vc/name" 2>/dev/null) || name=
		bind=$(cat "$vc/bind" 2>/dev/null) || bind=
		say "vtconsole:    $(basename "$vc") bind=$bind name=$name"
	done

	card=
	for d in "$DEBUGFS"/dri/*; do
		[ -r "$d/name" ] || continue
		if grep -q "sm750hdmidrm" "$d/name" 2>/dev/null; then
			card=$d
			break
		fi
	done
	[ -n "$card" ] || fail "no SM750 DRM device (card absent or driver not loaded)"

	if [ -x /usr/local/sbin/sm750-regs ]; then
		regs=$(/usr/local/sbin/sm750-regs 2>/dev/null) || regs=
	else
		regs=$(cat "$card/regs" 2>/dev/null) || regs=
	fi
	if [ -n "$regs" ]; then
		addr=$(printf '%s\n' "$regs" |
			awk '$2 == "PANEL_FB_ADDRESS" { print $3; exit }')
		say "PANEL_FB_ADDRESS: ${addr:-unknown}"
	else
		say "PANEL_FB_ADDRESS: unavailable (no sm750-regs and no $card/regs)"
	fi

	if [ -r "$card/sm750_scanout" ]; then
		dump_field() {
			head -n 8 "$card/sm750_scanout" |
				awk -v key="$1" '$1 == key { print $2; exit }'
		}
		say "scanout offset:   $(dump_field offset)"
		say "scanout nonzero:  $(dump_field nonzero)"
		crc=$(dump_field crc32)
		say "scanout crc32:    $crc"
		if [ "$crc" = "0xe20eea22" ]; then
			say "(crc32 0xe20eea22 is 262144 zero bytes: nothing has painted the window)"
		else
			say "(crc32 0xe20eea22 is 262144 zero bytes; this frame is not it)"
		fi
	else
		say "scanout:          unavailable ($card/sm750_scanout is not readable)"
	fi
}

switch_vt() {
	/usr/bin/chvt "$1" || fail "chvt $1 failed"
	sleep 1
	vt_mode=$(python3 -c '
import fcntl, struct, sys
f = open("/dev/tty0", "rb")
sys.stdout.write(str(struct.unpack("i", fcntl.ioctl(f.fileno(), 0x4B3B,
                                                     struct.pack("i", 0)))[0]))
' 2>/dev/null) || fail "cannot read the VT mode of /dev/tty0 with KDGETMODE"
}

case "$action" in
show)
	[ $# -eq 0 ] || usage
	show_status
	;;
text)
	[ $# -le 1 ] || usage
	n=${1:-2}
	case "$n" in
	''|*[!0-9]*) usage ;;
	esac
	switch_vt "$n"
	show_status
	;;
graphics)
	[ $# -eq 0 ] || usage
	switch_vt 1
	show_status
	;;
esac
```

The block above is the file as installed, byte-for-byte. When the script
changes, replace this block from `tools/sm750-console.sh` and refresh the staged
copy; the grant is on the path, so the sudoers line does not change.

### 3.5 Installing the 0.6.2 package

Historical: the commands below name the 0.6.2-2 and earlier artifacts. The build
now in the tree is 0.6.2-3, whose path is not allowlisted yet; section 3.7 has
the current recovery.

The allowlist names four `dnf install` paths, one per released package
(0.6.0, 0.6.1, 0.6.2-1), plus `/usr/local/sbin/sm750-console`. The 0.6.2-2
build needs **one more line** - the 0.6.2-1 path is granted, the 0.6.2-2 path
is not yet. Everything else the install does (`dkms build`, `dkms install` for
0.6.2, `depmod`) runs inside the scriptlets and needs no separate grant.

Install (host owner, root), in this order, so the resident module is unloaded
only after the new tree is on disk:

```sh
sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-2.fc43.noarch.rpm
sudo dkms status -m sm750hdmifb
modprobe -r sm750hdmidrm || true
sudo modprobe sm750hdmidrm
cat /sys/module/sm750hdmidrm/version
```

A host that still carries the broken 0.6.1 registration from the failed 0.6.2-1
install needs one preparation step first; see section 3.6.

The one line to add to the allowlist in section 1. It contains no colon, so it
passes the colon audit:

```text
coder ALL=(root) NOPASSWD: /usr/bin/dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-2.fc43.noarch.rpm
```

Until that line exists, the 0.6.2-2 package cannot be installed by this
account, and `/sys/module/sm750hdmidrm/version` keeps reporting the 0.6.1 label
left by the failed 0.6.2-1 install (`docs/evidence/runtime/27-posttrans-install-failure.txt`). The source is identical, so the
hardware evidence in `docs/evidence/runtime/26-test-card-crc-fix.txt` still
applies; only the version string differs.

### 3.6 Recovering from a broken 0.6.1 DKMS registration

Historical runbook for the 0.6.2-1 to 0.6.2-2 transition; section 3.7 covers
the dangling active-version link and the 0.6.2-3 build.

The state this section starts from, observed on 2026-11-21
(`docs/evidence/runtime/27-posttrans-install-failure.txt`): the 0.6.2-1 package
is installed, but `dkms install` aborted on a 0.6.1 registration whose
`/var/lib/dkms/sm750hdmifb/0.6.1/source` dangles, so no module was installed and
`cat /sys/module/sm750hdmidrm/version` still prints `0.6.1`.

0.6.2-2 removes such a tree itself, but only when it runs, and the transaction
that would run it cannot get past `dkms install` on this host: the broken entry
is already registered and rpm does not re-run `%posttrans` for an installed
package. So the tree is removed once, by hand.

1. Confirm the entry is broken (any user):

```sh
dkms status -m sm750hdmifb
ls -l /var/lib/dkms/sm750hdmifb/0.6.1/source
```

2. Remove the stale registration tree (root; `rm` is not on the allowlist, so
   this asks for a password):

```sh
sudo rm -rf /var/lib/dkms/sm750hdmifb/0.6.1
```

3. Install the 0.6.2-2 package. Its `%posttrans` purges first, deletes a broken
   tree if one is still there, and only then builds and installs:

```sh
sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-2.fc43.noarch.rpm
```

4. Reload the module and verify the version, which must read `0.6.2`:

```sh
sudo modprobe -r sm750hdmidrm || true
sudo modprobe sm750hdmidrm
cat /sys/module/sm750hdmidrm/version
modinfo sm750hdmidrm | grep ^version
sudo dkms status -m sm750hdmifb
```

5. Two negative checks, both must print nothing: a `Deprecated feature: CLEAN`
   line (A38 removed the directive) and a second version of `sm750hdmifb`
   (the purge leaves only `0.6.2` installed).

The last successful rootless run and the reason each step is needed are in
`docs/evidence/runtime/27-posttrans-install-failure.txt`. Nothing in step 3 or 4
has been run on this host yet; the account holding this repository is
unprivileged, and the 0.6.2-2 `dnf install` path is not in the allowlist
(section 1).

### 3.7 Dangling DKMS kernel links, recovery with no new package (A40)

A second leftover survives an erase and is invisible to `dkms status`: for each
kernel dkms built the module for, `/var/lib/dkms/sm750hdmifb/` carries a symlink
`kernel-<kernel>-<arch>` to `<version>/<kernel>/<arch>`, and the link keeps
pointing at the erased version. `do_install()` in dkms 3.4.4 reads the version
out of that link target alone (`/usr/sbin/dkms:1783-1784`) and dies 6 trying to
uninstall it before installing the new one (`:1866-1868`), so `dkms install`
aborts for every kernel while `dkms status -m sm750hdmifb` shows only the new
version as `built` (`docs/evidence/runtime/28-dangling-kernel-link.txt`).

The 0.6.2-3 package clears these links itself, but the host can be repaired
without it. Step 1 lists them, step 2 removes only the ones whose target is
gone (`ls` shows the link in red or `-d` on it fails), step 3 reinstalls.

1. List the links and their targets (any user):

```sh
ls -l /var/lib/dkms/sm750hdmifb/kernel-*
dkms status -m sm750hdmifb
```

2. Remove the dangling ones (root; `rm` is not on the allowlist, so this asks
   for a password). The glob covers every kernel; a link that resolves is a
   working install and must be kept, so pass only the names step 1 showed as
   dangling:

```sh
sudo rm -f /var/lib/dkms/sm750hdmifb/kernel-7.2.15-100.fc43.x86_64-x86_64
sudo rm -f /var/lib/dkms/sm750hdmifb/kernel-7.3.3-100.fc43.x86_64-x86_64
sudo rm -f /var/lib/dkms/sm750hdmifb/kernel-7.3.4-100.fc43.x86_64-x86_64
```

3. Remove and reinstall the package so `%posttrans` runs again, then verify:

```sh
sudo dnf remove -y sm750hdmifb
sudo dnf install -y /mega/tmp/sm750/t6/rpmbuild/RPMS/noarch/sm750hdmifb-0.6.2-3.fc43.noarch.rpm
sudo modprobe sm750hdmidrm
cat /sys/module/sm750hdmidrm/version
sudo dkms status -m sm750hdmifb
```

The version must read `0.6.2` and `dkms status` must show one row per installed
kernel with `installed`, not `built`. Neither the `rm` lines nor the 0.6.2-3
`dnf install` are in the allowlist yet (section 1), so both ask for a password.
Nothing in this section has been run on this host.

### 3.8 `/usr/local/sbin/sm750-pkg` (version-independent package helper)

Source `tools/sm750-pkg.sh`: 14584 bytes, 487 lines, sha256
`ca6e7b0a66fae43b6b332135ea8da62f61a917385accacc4d48f114e9149cf16`; self-test
`tests/check-sm750-pkg.sh`. It replaces the
per-version `dnf install` allowlist entries (section 1 names
`.../sm750hdmifb-0.6.0-...` and `.../sm750hdmifb-0.6.2-...`): one allowlisted
command, four subcommands, and the version and the file names are chosen by the
helper from the local build tree, never by the caller.

The installed copy is stale. `/usr/local/sbin/sm750-pkg` is `0755 root:root`,
11873 bytes, sha256
`e923a85a3389a13211869f32808b7b7cb77083355f90c5149b6c94cdaf9b976e`, mtime
2026-11-22 11:41 local (MSK). That body is the pre-change revision: it prints
the `dkms status` block twice and refuses the 0.6.3 pair with `release
mismatch: sm750hdmifb 0.6.3-1.fc43.noarch vs sm750hdmifb-tools
0.6.3-1.fc43.x86_64`. It is not the revision in the tree, and it must be
refreshed.

Refresh (host owner, root), from the repository root:

```sh
sudo install -m 0755 -o root -g root tools/sm750-pkg.sh /usr/local/sbin/sm750-pkg
```

The full install, if the allowlist line is missing too (as root or with your
own sudo):

```sh
sudo install -m 0755 -o root -g root tools/sm750-pkg.sh /usr/local/sbin/sm750-pkg
printf '%s\n' 'coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-pkg' > /etc/sudoers.d/30-sm750-pkg
chmod 0440 /etc/sudoers.d/30-sm750-pkg
visudo -c
```

Verify, unprivileged:

```sh
sudo -n /usr/local/sbin/sm750-pkg status
```

`status` exits 0, changes nothing, and prints `dkms status`, the loaded module
version, its `lsmod` line, the PCI device from sysfs, and the newest built RPM
pair with the version that `install` would use.

What this grants and what it does not. The allowlist line names one file and
matches it with any argument list, so the helper's own argv check is the whole
boundary: exactly one of `install`, `remove`, `status`, `reload`, anything else
exits 2 with the usage block. No path and no package name from the caller
reaches `dnf`. `install` searches only
`/mega/tmp/sm750/t6/rpmbuild/RPMS` (`noarch` and any arch subdirectory) for the
newest `sm750hdmifb` and `sm750hdmifb-tools` RPMs, requires the same version and
release, refuses a symlinked file or directory, refuses any path that resolves
outside that root, requires each RPM to be a regular file owned by root or by
the invoking user (`SUDO_UID`, else the current uid), requires no group or
other write bit on the file, requires its directory to be a non-symlink with no
group or other write bit either, then runs one
`dnf install` transaction on exactly those two files. `remove` runs `dnf remove`
for the two package names only and tolerates a package that is not installed.
`reload` runs `modprobe -r` and `modprobe` for `sm750hdmidrm` only. There is no
shell, no `eval`, no root shell and no arbitrary `dnf` invocation, so the blast
radius is installing or removing this driver's own packages from the local
build tree. Because `rpmbuild` runs as `coder`, the built files are owned by
uid 1005; the `SUDO_UID` rule (`tools/sm750-pkg.sh:102-112`, `:274-283`) exists
so the builder's own output installs with no `chown` step, while a file planted
by another local account is refused.

The installed stale body's two defects, both fixed in the tree revision:
`run` executed a command and then printed it before testing the exit code, so
`dkms status`, `cat` and `rpm -q` ran twice (`echo_cmd()`,
`tools/sm750-pkg.sh:83-92`, prints the line and the caller runs the command
once); and `scan_newest` parsed the file name with `.rpm` still attached,
reading the arch as `rpm` and the release as `1.fc43.noarch`, so the noarch plus
x86_64 pair was refused as a release mismatch (`tools/sm750-pkg.sh:148-207`).

`dnf` on this host is dnf5 5.2.18, which rejects the literal
`--nogpgcheck=false` ("unexpected value for named argument"); the helper passes
`--setopt=gpgcheck=True`, the same policy in a spelling dnf5 accepts, and
`status` prints the exact command it would run (`install would run: ...`).

### 3.9 DRM KUnit sweep loader (T55, INSTALLED 2026-11-22)

`tests/check-kunit-drm.sh` (`make check-kunit`) loads the kernel's own DRM
KUnit test modules from
`/lib/modules/$(uname -r)/internal/drivers/gpu/drm/tests/` and parses the
KUnit TAP results from the kernel log.

Status: INSTALLED. The owner granted exact per-module lines instead of bare
`/usr/bin/modprobe`: for each of the 21 DRM test suites, one forward line
`/usr/bin/modprobe <module>` and one reverse line
`/usr/bin/modprobe -r <module>` (42 lines total, verified with `sudo -n -l`
2026-11-22). The exact-single-argument match means `modprobe -a`, `--force`,
`-v` or any second argument is refused; the gate therefore passes exactly one
module name per call. The support modules `drm_kunit_helpers` and
`drm_kunit_edid` are deliberately NOT granted: modprobe pulls them in as
dependencies, and the gate never loads them directly. `/usr/bin/dmesg` was
already granted (row 4 of the allowlist), so the TAP reader needs no new
line.

Unprivileged run on this host:

```sh
MODPROBE_CMD='sudo -n /usr/bin/modprobe' DMESG_CMD='sudo -n dmesg' \
  ./tests/check-kunit-drm.sh
```

or as root: `sudo -n ./tests/check-kunit-drm.sh`. On machines without the
allowlist the gate skips with exit 77 and one SKIP line.

### 3.10 Installed: enable KUnit at runtime (INSTALLED 2026-11-22)

Measured 2026-11-22: this kernel is built with
`# CONFIG_KUNIT_DEFAULT_ENABLED is not set` in
`/boot/config-7.3.4-100.fc43.x86_64`, so the `kunit` module loads with
`enable=0` even though `CONFIG_KUNIT_AUTORUN_ENABLED=y`. Every suite load
then prints only

```text
KTAP version 1
1..1
kunit: disabled
```

to the kernel log and runs no subtest. The gate treats that as an unavailable
runner (SKIP, exit 77, naming the reason) rather than a pass.

Two owner-side fixes, either suffices (do both for boot-time and module
runs):

1. Persistent, no reboot needed for module-loaded tests - create
   `/etc/modprobe.d/kunit-enable.conf` containing exactly:

```text
options kunit enable=1
```

   `kunit` must not be resident when this takes effect; after the earlier
   sweep runs it may still be loaded (see below), so unload it first
   (`modprobe -r kunit` as root) and let the next sweep load it with the
   option applied.

2. Boot-time: add `kunit.enable=1` to the kernel command line (GRUB).

Two residual grants make the sweep fully self-cleaning; neither is in the
allowlist yet:

```text
/usr/bin/modprobe -r kunit
```

and, if per-suite reverse lines are not enough after option 1 is installed,
nothing else is needed. Note `/sys/module/kunit/parameters/*` exists only
while `kunit` is loaded, is mode 0600 root-only, and has no `enable` file on
this kernel (the runtime knob is the module parameter, not a sysfs file), so
writing sysfs is not an alternative.

Status: INSTALLED 2026-11-22 by the owner: `/etc/modprobe.d/kunit-enable.conf`
containing `options kunit enable=1` exists on this host, and the sudoers
allowlist carries the residual grant `/usr/bin/modprobe -r kunit` (verified
2026-11-22: `sudo -n /usr/bin/modprobe -r kunit` exits 0, and
`/etc/modprobe.d/kunit-enable.conf` reads exactly `options kunit enable=1`).
The first real KUnit census was obtained the same day: all 21 DRM KUnit
suites ran for real, 0 failures, in 8.7 s wall clock
(`docs/evidence/runtime/33-kunit-and-oops-sweep.txt`, section "LIVE SWEEP,
KUNIT ENABLED"). The earlier SKIP for disabled KUnit recorded in that file
is superseded by that census.

### 3.11 `/usr/local/sbin/sm750-headless` (installed copy stale since 2026-11-26)

Source `tools/sm750-headless.sh`: 12020 bytes, 336 lines, sha256
`bc1d3a06fdf59bb25f9b0f572c2be6085731332109a4231a80e3d2076308922f` as measured
2026-11-26; static
gate `tests/check-headless-helper.sh` (part of `make check` through
`tests/check-drm-policy.sh`).

**Installed copy must be refreshed.** The host still carries the previous
9223-byte revision, which has no input isolation. Refresh it from the
repository root with exactly:

```sh
sudo install -m 0755 -o root -g root tools/sm750-headless.sh /usr/local/sbin/sm750-headless
```

The 12020-byte revision isolates input: both compositor arms run inside a
private mount namespace with an empty `/dev/input` (`isolate()`,
`tools/sm750-headless.sh:244-253`), so no compositor can open the owner's
keyboard or mouse. Defect A49 in `docs/DEFECTS.md` records the
2026-11-26T06:32:48 incident that made this necessary.

What it is for: a panel that stays black has three candidate owners - the
driver's mode, the compositor, and whoever holds DRM master. `sm750-console`
answers the first (section 3.4), and nothing answered the other two. This
helper takes master on the SM750 itself, runs one named compositor for a fixed
number of seconds, and writes a verdict that is either backed by a measured
vertical-blank delta or is a FAIL.

The helper takes master to prove the card is free (`DRM_IOCTL_SET_MASTER`
`0x641E`, dropped again with `0x641F`), not to keep it: it drops master before
the compositor starts, so the compositor acquires it the normal way. A card
already held by another process is not fought over; that run exits 4 and names
the holder.

Allowlist line, one line, no argument restrictions beyond the helper's own
argv check:

```text
coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-headless
```

The grant is on the path, not on the file content, so replacing the body needs
no sudoers change.

Install (host owner, root), from the repository root:

```sh
sudo install -m 0755 -o root -g root tools/sm750-headless.sh /usr/local/sbin/sm750-headless
```

The path is relative to the repository root on purpose: the body is read from
the tree and written to `/usr/local/sbin`. Re-run it after every edit of
`tools/sm750-headless.sh`, or the installed copy keeps running the old logic -
that is exactly the state of the installed copy today, see "Installed state"
below.

Modes, and the longest each may run:

| Mode | What it does | Run time |
| --- | --- | --- |
| `probe` | Snapshots the driver attributes, takes and drops master, snapshots again, writes no compositor log. The cheapest answer to "is the card free and does it still respond" | immediate |
| `diagnose` | Skips the master probe and instead enumerates every `/proc/*/fd` link pointing at `card0`, the `sm750hdmidrm` module refcount from `/proc/modules` and the `vtcon1` bind state. Answers "who is holding it" | immediate |
| `weston [SECONDS]` | Weston with the DRM backend, the pixman renderer and the kiosk shell, plus one `weston-terminal` client on `wayland-0` | `SECONDS`, default 20, 1..600 |
| `cage [SECONDS]` | `cage -d -- /usr/bin/weston-terminal`, a kiosk compositor around one terminal | `SECONDS`, default 20, 1..600 |
| `kmscube [SECONDS]` | `kmscube -A -D <card> -c 300`: the frame count is the argument, the run time is still bounded by `SECONDS` | `SECONDS`, default 20, 1..600 |

`SECONDS` must be numeric and is clamped to 1..600; a second argument in any
other shape, an unknown mode, or more than two arguments all reach the usage
path and exit 2. There is no passthrough argument, no shell, no `eval`, and the
program list is fixed: `/usr/bin/weston`, `/usr/bin/cage`, `/usr/bin/kmscube`,
`/usr/bin/weston-terminal`, `python3`, and the coreutils already on the
allowlist.

What it does not touch:

- **The owner's input devices.** Both compositor arms run inside
  `unshare --mount --propagation private` with a 1M tmpfs mounted over
  `/dev/input`, so the namespace the compositor sees contains no `event*` node
  at all. The mount exists only in that child namespace and dies with the
  compositor; the host `/dev/input` is never modified. `--propagation private`
  is required because `/dev` is a shared mount here (`/proc/self/mountinfo`
  field 7 = `shared:2`), and a mount under shared propagation can reach the
  host. There is no compositor flag that does this: weston 14.0.2 offers
  `--no-input` only for its x11 backend, and its DRM backend accepts only
  `--seat`, `--drm-device`, `--additional-devices`, `--use-pixman`,
  `--current-mode` and `--continue-without-input`, the last meaning only that
  weston starts with zero input devices. cage 0.2.x has no input option at all.
  The run announces `sm750-headless: input devices are isolated in a private
  mount namespace (empty /dev/input)` on the console and records the same line
  in `00-plan.txt`.
- **seat0 and the owner's session.** The compositors are started with
  `LIBSEAT_BACKEND=noop`, which opens the DRM device directly and performs no
  VT operation. libseat 0.9.3 offers exactly three backends - `logind`, `seatd`
  and `noop`; there is no `builtin` backend. `noop` is the only one that needs
  neither a seat manager nor a logind session.
- **No VT switch.** `cage` runs with `-d` and deliberately without `-s`,
  because `-s` would let it switch the VT out from under the owner.
- **No other card.** The device is fixed to the by-path link for
  `0000:01:00.0`, and the run refuses to start unless that card is bound to
  `sm750hdmidrm`. `card0` in the compositor arguments is a name weston and
  kmscube resolve inside that same private environment.
- **No permanent state.** Every run writes under
  `/mega/tmp/sm750/headless/` (override with `SM750_HEADLESS_DIR`), never into
  `/etc` or the repository. The compositor is stopped with TERM, then KILL, on
  an EXIT trap, so a Ctrl-C or a failed assertion does not leave a process
  holding the card.

Log directory layout, one directory per run, `<UTC stamp>-<mode>`:

| Path | Content |
| --- | --- |
| `00-plan.txt` | Weston and cage only: the input isolation line, the `unshare` and `mount` commands used, the mode and `SECONDS` |
| `01-before.txt` | Driver attributes and connector state before anything ran |
| `02-master.txt` | The master probe result: acquired, or the errno it failed with |
| `03-compositor.log` | The compositor's own stdout and stderr (weston also writes `weston.log`) |
| `04-client.log`, `04-client.pid` | Weston only: the terminal client's output and pid |
| `04-holders.txt` | Diagnose only: every fd-table holder of the card, the module refcount, the vtcon bind |
| `05-verdict.txt` | Survivor line, the two vblank counters, the delta, and `RESULT: PASS` or `RESULT: FAIL` with the reason |
| `06-after.txt` | The same attribute set as `01-before.txt`, after cleanup |
| `runtime/` | The compositor's `XDG_RUNTIME_DIR`, mode `0700` |

The verdict fails on two conditions and passes only when neither holds: the
compositor did not survive the full `SECONDS` (except for `kmscube`, which is
given a fixed frame count by `-c` and passes when it exits `0` early, so an
early clean exit is not a failure - a non-zero exit is), or the
`vblank_count` delta is zero or negative. `05-verdict.txt` states why a frame count alone proves
nothing - the raster scans out whether or not a user client owns the card - so
a PASS is "the compositor held the card and the pipe advanced", not "the
compositor drew a picture". Only a panel observation or an external capture
proves the pixels.

Exit codes: 0 the run completed and every expectation held, 1 environment
problem (not root, wrong driver, program missing), 2 usage, 3 the compositor
started but an expectation failed, 4 nothing could take master.

Installed state, measured 2026-11-25T13:49Z and unchanged on the host on
2026-11-26:

```text
-rwxr-xr-x 1 root root 9223 2026-11-25 17:26 /usr/local/sbin/sm750-headless
sha256 137c665b7f60c17a95a6bdcd7948fb7064239eb62a6a108932e60315ce80913c
```

Source in the tree, measured 2026-11-26:

```text
12020 bytes, 336 lines
sha256 bc1d3a06fdf59bb25f9b0f572c2be6085731332109a4231a80e3d2076308922f
```

Status: **INSTALLED, STALE.** The allowlist line is present (`sudo -n -l` lists
`(root) NOPASSWD: /usr/local/sbin/sm750-headless`), but the installed body is
the previous revision and **has no input isolation**. Until it is refreshed,
`/usr/local/sbin/sm750-headless weston` and `... cage` can still take the
owner's keyboard and mouse - the A49 incident. The installed copy must be
refreshed with
`sudo install -m 0755 -o root -g root tools/sm750-headless.sh /usr/local/sbin/sm750-headless`
from the repository root, after which `sha256sum /usr/local/sbin/sm750-headless`
must print `bc1d3a06fdf59bb25f9b0f572c2be6085731332109a4231a80e3d2076308922f`
and `stat -c %s` must print 12020. Re-run that pair after every edit of the
source: the static gate validates the tree, and it cannot see
`/usr/local/sbin`.

The 7387-byte revision of 2026-11-23, now superseded on the host, carried these
four defects:

- `LIBSEAT_BACKEND=builtin` - not a libseat backend, so the compositor cannot
  open a seat at all;
- `cage -d -s -- ...` - `-s` allows VT switching, which is the one thing the
  helper must not permit;
- `kmscube -D <card> -n 300` - `-n` is a connector id, so the frame count is
  lost;
- no survivor check - a compositor that died immediately still reached the
  vblank test and could read as a PASS.

Refresh (host owner, root), from the repository root:

```sh
sudo install -m 0755 -o root -g root tools/sm750-headless.sh /usr/local/sbin/sm750-headless
sha256sum /usr/local/sbin/sm750-headless
stat -c '%s bytes, %n' /usr/local/sbin/sm750-headless
```

Expected after the refresh: 12020 bytes, 336 lines,
`bc1d3a06fdf59bb25f9b0f572c2be6085731332109a4231a80e3d2076308922f`. The
9223-byte / `137c665b...` value the host carried from 2026-11-25T14:26Z is the
superseded revision and must not be the result. The static gate
`tests/check-headless-helper.sh` validates the source in the tree; it cannot see
the installed copy, so the hash pair is the only evidence that the refresh
happened. This section is the place that records the expected value; update it
when the source changes.

After the refresh, the first isolated run writes `00-plan.txt` naming
`/usr/bin/unshare --mount --propagation private` and the tmpfs mount over
`/dev/input`, and prints
`sm750-headless: input devices are isolated in a private mount namespace (empty /dev/input)`.
That run has **not** been executed yet: it is the owner's action, and the
evidence file records it as NOT YET OBSERVED
(`docs/evidence/runtime/40-headless-input-isolation.txt`).

Every mode has been exercised through the installed helper. The runs of
2026-11-25T13:41Z used the then-installed 8759-byte revision: probe PASS,
diagnose PASS (no holders, module refcount 0, fbcon bind 1), weston 30 PASS 333
frames, cage 20 PASS 341 frames, kmscube 15 finished `rc=0` with 443 frames -
and kmscube was still reported as FAIL, which is the sixth defect A43 records.
The runs of 2026-11-25T14:27Z used the installed 9223-byte revision with the
per-mode verdict model, and all of them passed:

```text
probe    master acquired, dropped                                  rc 0
diagnose no card0 holders, module refcount 0, fbcon bind 1          rc 0
weston   RESULT: PASS weston held the card for 15s and VBlank advanced   rc 0
cage     RESULT: PASS cage held the card for 15s and VBlank advanced     rc 0
kmscube  RESULT: PASS kmscube rendered its frame count and exited rc=0   rc 0
```

The kmscube PASS of 14:27Z advanced the counter by 428, which is the proof the
per-mode rule asks for: a clean exit only passes when the pipe actually
advanced. Measured vblank deltas and the defect history are recorded under A43
in `docs/DEFECTS.md`; the five log directories are under
`/mega/tmp/sm750/headless/`.

### 3.12 `/usr/local/sbin/sm750-vt` (hot module reload without a reboot; allowlist present, helper NOT YET INSTALLED)

Source `tools/sm750-vt.sh`: 279 lines, 9226 bytes, sha256
`4e2b3ab7fb6f8f68b700ac373fff2d24bdc597106ea146ed71ddb20c7954a91b` as measured
2026-11-26; static gate `tests/check-vt-helper.sh` (287 lines, sha256
`4b8d0f2310da5a5a7b760b21a2556d1fabf45ba0792a447f0f686d7c80f93e1e`, part of
`make check` through `tests/check-drm-policy.sh`, 10 assertions and 5 planted
controls).

**Installed copy must be refreshed with** (measured 2026-11-26: the two
allowlist lines below are already present in `sudo -n -l`, but the helper
itself does not exist - `ls -l /usr/local/sbin/sm750-vt` fails with
`No such file or directory` - so every mode currently fails at the missing
file), from the repository root:

```sh
sudo install -m 0755 -o root -g root tools/sm750-vt.sh /usr/local/sbin/sm750-vt
```

What it is for: a rebuilt module cannot be loaded without a reboot while the
framebuffer console holds it. Measured on this host 2026-11-26:

```text
$ cat /sys/module/sm750hdmidrm/version            # 0.6.5, the DKMS tree has 0.6.7
0.6.5
$ cat /sys/module/sm750hdmidrm/srcversion
76EE5488E11276C6D8610B7
$ ls /sys/module/sm750hdmidrm/holders/
$ cat /sys/module/sm750hdmidrm/refcnt
1
$ sudo -n /usr/bin/modprobe -r sm750hdmidrm
modprobe: FATAL: Module sm750hdmidrm is in use.
```

`refcnt` is 1 with an empty `holders/` directory, so the reference is not a
module: it is the built-in framebuffer console bound to the SM750 vtconsole
(`/sys/class/vtconsole/vtcon1/name` = `(M) frame buffer device`, `bind` = 1).
Writing `0` to that `bind` file releases the reference, and writing `1` takes
it back. `/usr/bin/tee` and `/usr/bin/systemctl` are not on the allowlist, so
a bare sudo rule cannot perform that write; the helper is the grant.

Modes, one line each:

| Mode | State change | Root |
| --- | --- | --- |
| `show` | none, read-only | no, `show` runs as `coder` |
| `off` | unbind fbcon, `modprobe -r`, `modprobe`, re-bind fbcon | yes |
| `on` | re-bind fbcon only, for recovery after an interrupted `off` | yes |

Allowlist lines, one line each, no argument restrictions beyond the helper's
own argv check and no colons:

```sudoers
coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-vt off
coder ALL=(root) NOPASSWD: /usr/local/sbin/sm750-vt on
```

`show` needs no allowlist line because it changes nothing and reads only
world-readable files (`/sys/class/vtconsole/*`, `/sys/module/sm750hdmidrm/*`,
`/sys/class/tty/tty0/active`) plus the `/proc/*/fd` table for the holder scan.
The helper refuses `off` and `on` with `sm750-vt: must run as root` when the
caller is not root, so `show` is the only mode that works unprivileged.

**Hazard, and it is why `off` is not automatic: while fbcon is unbound there
is no text console on any VT.** Run `off` from an SSH session or from the
serial console, never from the SM750 monitor itself at `tty1`
(`/sys/class/tty/tty0/active` reads `tty1` on this host). The window is
normally a few hundred milliseconds; if the reload fails the helper's EXIT
trap re-binds fbcon and the message says so, and if the process is killed
outright, `sm750-vt on` restores the console from another terminal.

Resolution basis, stated by the helper itself: the target is the **sole
vtconsole whose name contains `frame buffer device`**, cross-checked against
`basename $(readlink -f /sys/bus/pci/devices/0000:01:00.0/driver)` =
`sm750hdmidrm`. It is not a hardcoded `vtcon1`: kernel 7.3.4 exposes no
`device` link under a vtconsole directory, `/sys/class/graphics/` carries only
`fbcon` (because `CONFIG_FB_DEVICE` is unset), and there is no `fb0` to walk,
so the class glob plus the driver check is the only measurable basis available.
Zero candidates and more than one candidate are both refused with a message
that lists what was found.

Shape of `show`, with the values measured read-only on 2026-11-26. The helper
has not been executed on this host - it is not installed - so this is its
documented layout, not a captured transcript; the numbers are the sysfs values
above.

```text
vtconsole:    /sys/class/vtconsole
  vtcon0       bind=0 name=(S) VGA+
  vtcon1       bind=1 name=(M) frame buffer device
target:       /sys/class/vtconsole/vtcon1
basis:        sole framebuffer vtconsole on the host, with the sole sm750hdmidrm card (card0, 0000:01:00.0); not by a hardcoded index
  bind now:   1
module:       version=0.6.5 srcversion=76EE5488E11276C6D8610B7 refcnt=1
active tty:   tty1
card:         /dev/dri/by-path/pci-0000:01:00.0-card -> /dev/dri/card0 inode 9:297
holders:      0 userspace processes hold the card
```

Guard rails: it refuses when fbcon is already unbound (`run 'sm750-vt on'`),
when any process holds the card (it prints `pid:comm` per holder instead of
letting `modprobe -r` fail with `Module ... is in use`), and when the version
file does not appear after the load. Every sysfs write is read back before it
is reported, so no line claims success that sysfs does not confirm. While
`fbcon` is unbound the module reference count is 0 and `modprobe -r` proceeds;
this is the exact reference the measured error above names.

What it does not touch: the DRM modes, the panel, the EDID, the udev ACL rule
and the sudoers allowlist. It changes the vtconsole `bind` values and the
module in memory, and nothing else.

Exit codes: 0 success, 1 environment or restore problem, 2 usage error, 3 a
measured expectation failed (a bind write that did not take, or a load with no
version file).

Status: the two allowlist lines are INSTALLED (verified read-only on
2026-11-26 with `sudo -n -l | grep sm750-vt`, which prints
`(root) NOPASSWD: /usr/local/sbin/sm750-vt off` and
`(root) NOPASSWD: /usr/local/sbin/sm750-vt on`); the helper body is NOT
installed and the reload is NOT YET OBSERVED. Installing the body and running
`sm750-vt off` are the owner's action; the evidence file
`docs/evidence/runtime/41-vt-hot-reload.txt` records the measured blocker, the
sysfs paths and an explicit NOT YET OBSERVED section.

**Refresh (host owner, root), from the repository root:**

```sh
sudo install -m 0755 -o root -g root tools/sm750-vt.sh /usr/local/sbin/sm750-vt
sha256sum /usr/local/sbin/sm750-vt tools/sm750-vt.sh
/usr/local/sbin/sm750-vt show
```

The two `sha256sum` digests must match, and `show` must name `vtcon1` on this
host with `bind now: 1`. Until the `install` line runs, the allowlist entries
resolve to a file that does not exist and `sudo -n sm750-vt show` fails with
`command not found`, which is the state measured on 2026-11-26.

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
| `tests/check-scanout-crc.sh` as root (row 8) | GAP-B3 readback/CRC | OUTSTANDING: not run. The draw path is proven unprivileged (`docs/evidence/scanout/03-readback.txt`), the read half needs root. The driver now hosts `crtc-N/crc/{source,control,data}` in the source tree, but the loaded module is still the packaged 0.6.0 from HEAD, and debugfs is root-only, so nothing about it is observed yet: `docs/evidence/scanout/06-crc-debugfs-runtime.txt` |

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

Run at the console as root, from the repository. The packaged 0.6.0 predates
the CRC debugfs hosting, so the module must be rebuilt from the tree and
reloaded first; the version string stays 0.6.0, so only the reload distinguishes
the two builds:

```sh
cd ~coder/sm750hdmifb
make CC=/usr/bin/gcc
modprobe -r sm750hdmidrm
modprobe drm_vram_helper
insmod src/sm750hdmidrm.ko
export PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm
export LD_LIBRARY_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64
./tests/check-scanout-crc.sh 2>&1 | tee /mega/tmp/sm750/scanout-crc.txt
echo "exit: ${PIPESTATUS[0]}"
modprobe -r sm750hdmidrm
modprobe sm750hdmidrm
rm -rf build
```

`modprobe drm_vram_helper` is not optional. `modprobe -r sm750hdmidrm` also
unloads the dependency modules that `modprobe` had auto-loaded for the DKMS
module, and `insmod` resolves no dependencies at all, so the load fails with
`ERROR: could not insert module ...: Unknown symbol in module` from the six
`drm_gem_vram_*` / `drmm_vram_helper_init` / `drm_vram_mm_debugfs_init` imports.

The last three commands return the host to the packaged DKMS module and keep
the tree owned by `coder`. The exports are the documented rootless libdrm tree
(`docs/ENVIRONMENT.md` section 4); the script falls back to the same path on its
own, so they only matter if it is rebuilt elsewhere. The script writes
`build/scanout-pattern` into the tree.

Store the transcript as `docs/evidence/scanout/07-crc-debugfs-run.txt`, replace
the SKIP sentence in `docs/evidence/scanout/04-checks.txt` with the PASS/FAIL
lines it prints, and quote the `sm750_scanout` summary line (offset, length,
nonzero, `crc32`) in `docs/evidence/scanout/03-readback.txt`. The run also
observes the files the driver hosts itself (`crc/source` reads `scanout`,
`crc/control` reads `none` then `scanout`), which is what
`docs/evidence/scanout/06-crc-debugfs-runtime.txt` is waiting on. If `dmesg`
shows `failed to enable HDMI mode: -110 at stage <name>` during the run, copy
that line into `docs/evidence/gap-b8/`.

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
