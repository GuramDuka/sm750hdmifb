#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Regenerate the T3 baseline capture corpus.
#
# Read-only with respect to the host: no sudo, no module load/unload, no
# modeset, no writes outside /mega/tmp/sm750 and this directory. Re-running
# overwrites the captures in place, so the corpus is reproducible; only
# observation-dependent values (timestamps, counters, free memory, file
# mtimes and sizes) differ between runs.
#
# Usage: ./docs/evidence/baseline/capture.sh
#
# Each capture file records: the exact command line, host, kernel, UTC
# timestamp, verbatim combined output and the exit status.

set -u
LC_ALL=C
export LC_ALL

OUT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=${REPO_ROOT:-$(CDPATH= cd -- "$OUT/../../.." && pwd)}
SCRATCH=/mega/tmp/sm750/t3
mkdir -p "$SCRATCH"

run() {
	_file=$1
	shift
	_cmd=$*
	{
		printf '# host: %s\n' "$(uname -n)"
		printf '# kernel: %s\n' "$(uname -r)"
		printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf '# command: %s\n' "$_cmd"
		printf '# ---- output (stdout+stderr, LC_ALL=C) ----\n'
		sh -c "$_cmd" 2>&1
		printf '# ---- exit: %d ----\n' $?
	} > "$OUT/$_file" 2>&1
	printf 'wrote %s\n' "$OUT/$_file"
}

# --- 00 host identity (rootless; DMI comes from world-readable sysfs) ------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# command: uname -srm; /etc/os-release; /sys/class/dmi/id/*; nproc\n'
	printf '# ---- output ----\n'
	printf '\n$ uname -srm\n'; uname -srm 2>&1
	printf '\n$ cat /etc/os-release\n'; cat /etc/os-release 2>&1
	for _f in sys_vendor product_name board_name bios_version; do
		printf '\n$ cat /sys/class/dmi/id/%s\n' "$_f"
		cat "/sys/class/dmi/id/$_f" 2>&1
	done
	printf '\n$ ls -l /.dockerenv  (absent = not a container)\n'; ls -l /.dockerenv 2>&1
	printf '\n$ cat /proc/1/cgroup\n'; cat /proc/1/cgroup 2>&1
	printf '\n$ nproc\n'; nproc 2>&1
	printf '\n$ free -h | head -2\n'; free -h 2>&1 | head -2
} > "$OUT/00-host-identity.txt" 2>&1
printf 'wrote %s\n' "$OUT/00-host-identity.txt"

# --- 01 PCI identity and capabilities -------------------------------------
run 01-lspci.txt 'lspci -vvv -d 126f:0750 -s 01:00.0'

# --- 02 EDID ---------------------------------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# command: od -Ax -tx1z -v /sys/class/drm/card0-HDMI-A-1/edid\n'
	printf '# command: python3 (crc32 and header fields of the same file)\n'
	printf '# ---- output ----\n'
	od -Ax -tx1z -v /sys/class/drm/card0-HDMI-A-1/edid 2>&1
	printf '# ---- exit: %d ----\n' $?
	printf '# ---- derived fields ----\n'
	python3 - /sys/class/drm/card0-HDMI-A-1/edid <<'PY' 2>&1
import sys, zlib
d = open(sys.argv[1], 'rb').read()
print('path=%s' % sys.argv[1])
print('bytes=%d' % len(d))
print('crc32=0x%08x' % (zlib.crc32(d) & 0xffffffff))
print('header=%s' % d[:8].hex())
print('extension_count=%d' % d[126])
mfg = (d[8] << 8) | d[9]
print('mfg_id=%s' % ''.join(chr(ord('@') + ((mfg >> s) & 0x1f)) for s in (10, 5, 0)))
print('product_code=0x%04x' % (d[11] << 8 | d[10]))
print('serial=0x%08x' % int.from_bytes(d[12:16], 'little'))
print('week=%d year=%d' % (d[16], 1990 + d[17]))
print('version=%d.%d' % (d[18], d[19]))
print('input_type=0x%02x' % d[20])
print('h_cm=%d v_cm=%d' % (d[21], d[22]))
print('per_block_crc=%s' % ' '.join('%02x' % d[127 + 128 * i] for i in range(d[126] + 1)))
PY
} > "$OUT/02-edid.txt" 2>&1
printf 'wrote %s\n' "$OUT/02-edid.txt"

# --- 03 connector state ----------------------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# commands: cat of each /sys/class/drm/card0-HDMI-A-1 attribute\n'
	printf '# ---- output ----\n'
	for _a in status enabled dpms connector_id; do
		printf '$ cat /sys/class/drm/card0-HDMI-A-1/%s\n' "$_a"
		cat "/sys/class/drm/card0-HDMI-A-1/$_a" 2>&1
		printf '[exit %d]\n' $?
	done
	printf '$ cat /sys/class/drm/card0-HDMI-A-1/modes\n'
	cat /sys/class/drm/card0-HDMI-A-1/modes 2>&1
	printf '[exit %d]\n' $?
	printf '$ cat /sys/class/drm/card0-HDMI-A-1/modes | wc -l\n'
	cat /sys/class/drm/card0-HDMI-A-1/modes 2>/dev/null | wc -l
	printf '[exit %d]\n' $?
} > "$OUT/03-connector.txt" 2>&1
printf 'wrote %s\n' "$OUT/03-connector.txt"

# --- 04 DKMS state ---------------------------------------------------------
run 04-dkms-status.txt 'dkms status'

# --- 05 loaded module metadata --------------------------------------------
run 05-modinfo.txt 'modinfo sm750hdmidrm'

# --- 06 loaded module list -------------------------------------------------
run 06-lsmod.txt "lsmod | grep -E '^(sm750hdmidrm|drm_vram_helper|drm_ttm_helper|drm|sii902x) '"

# --- 07 PCI config space (readable unprivileged) ---------------------------
run 07-pci-config-space.txt 'lspci -xxx -s 01:00.0'

# --- 08 toolchain matrix ---------------------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# command: command -v plus one version probe per tool\n'
	printf '# ---- output ----\n'
	for _t in rpmbuild rpmdev-setuptree spectool dkms modinfo modetest gcc python3 igt-info kmscube v4l2-ctl pkg-config make dnf rpm2cpio xxd; do
		_p=$(command -v "$_t" 2>/dev/null)
		if [ -n "$_p" ]; then
			printf '%s: FOUND %s\n' "$_t" "$_p"
		else
			printf '%s: MISSING\n' "$_t"
		fi
	done
	printf '\n$ rpmbuild --version\n'; rpmbuild --version 2>&1
	printf '\n$ dkms --version\n'; dkms --version 2>&1
	printf '\n$ modinfo -V\n'; modinfo -V 2>&1
	printf '\n$ modetest --version   (no --version option; prints usage)\n'; modetest --version 2>&1 | head -1
	printf '\n$ rpm -qf /usr/bin/modetest\n'; rpm -qf /usr/bin/modetest 2>&1
	printf '\n$ /usr/bin/gcc --version | head -1\n'; /usr/bin/gcc --version 2>&1 | head -1
	printf '\n$ /usr/local/cuda/bin/gcc --version | head -1  (this is what bare gcc resolves to)\n'; /usr/local/cuda/bin/gcc --version 2>&1 | head -1
	printf '\n$ python3 --version\n'; python3 --version 2>&1
	printf '\n$ make --version | head -1\n'; make --version 2>&1 | head -1
	printf '\n$ dnf --version | head -1\n'; dnf --version 2>&1 | head -1
	printf '\n$ pkg-config --version\n'; pkg-config --version 2>&1
	printf '\n$ rpm2cpio (no version flag; usage probe)\n'; rpm2cpio 2>&1 | head -2
	printf '\n$ pkg-config --modversion libdrm  (system prefix)\n'
	pkg-config --modversion libdrm 2>&1
	printf '[exit %d]\n' $?
} > "$OUT/08-toolchain.txt" 2>&1
printf 'wrote %s\n' "$OUT/08-toolchain.txt"

# --- 09 privilege denials (freshly observed, never asserted) ---------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# note: every line below is a fresh observation on this host.\n'
	printf '# A denial is recorded as a gap, not as a failure or a pass.\n'
	printf '# ---- output ----\n'
	printf '\n$ id\n'; id 2>&1
	printf '\n$ getent group video\n'; getent group video 2>&1
	printf '\n$ ls -l /dev/dri/\n'; ls -l /dev/dri/ 2>&1
	printf '\n$ getfacl -p /dev/dri/card0\n'; getfacl -p /dev/dri/card0 2>&1
	printf '\n$ python3 -c <open /dev/dri/card0 for reading>\n'
	python3 -c 'open("/dev/dri/card0", "rb")' 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ python3 -c <open /dev/dri/renderD128 for reading>\n'
	python3 -c 'open("/dev/dri/renderD128", "rb")' 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ modetest -c\n'; modetest -c 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ dmesg\n'; dmesg 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ ls -l /proc/kmsg\n'; ls -l /proc/kmsg 2>&1
	printf '\n$ ls -l /var/log/messages\n'; ls -l /var/log/messages 2>&1
	printf '\n$ ls -ld /sys/kernel/debug\n'; ls -ld /sys/kernel/debug 2>&1
	printf '\n$ ls /sys/kernel/debug\n'; ls /sys/kernel/debug 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ ls -l /dev/mem\n'; ls -l /dev/mem 2>&1
	printf '\n$ dd if=/dev/mem of=/dev/null bs=64 count=1\n'
	dd if=/dev/mem of=/dev/null bs=64 count=1 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ ls -l /sys/bus/pci/devices/0000:01:00.0/rom\n'
	ls -l /sys/bus/pci/devices/0000:01:00.0/rom 2>&1
	printf '\n$ dd if=/sys/bus/pci/devices/0000:01:00.0/rom of=/mega/tmp/sm750/t3/vbios.bin bs=65536 count=1\n'
	dd if=/sys/bus/pci/devices/0000:01:00.0/rom of="$SCRATCH/vbios.bin" bs=65536 count=1 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ ls -l /sys/bus/pci/devices/0000:01:00.0/resource1\n'
	ls -l /sys/bus/pci/devices/0000:01:00.0/resource1 2>&1
	printf '\n$ dd if=/sys/bus/pci/devices/0000:01:00.0/resource1 of=/dev/null bs=64 count=1\n'
	dd if=/sys/bus/pci/devices/0000:01:00.0/resource1 of=/dev/null bs=64 count=1 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ dkms install sm750hdmifb/0.5.9 -k 7.3.3-100.fc43.x86_64   (denial probe)\n'
	dkms install sm750hdmifb/0.5.9 -k 7.3.3-100.fc43.x86_64 >/mega/tmp/sm750/t3/dkms-install.err 2>&1
	_rc=$?
	cat /mega/tmp/sm750/t3/dkms-install.err 2>/dev/null
	printf '[exit %d]\n' "$_rc"
	printf '\n$ dkms build sm750hdmifb/0.5.9 -k 7.3.3-100.fc43.x86_64   (denial probe)\n'
	dkms build sm750hdmifb/0.5.9 -k 7.3.3-100.fc43.x86_64 >/mega/tmp/sm750/t3/dkms-build.err 2>&1
	_rc=$?
	cat /mega/tmp/sm750/t3/dkms-build.err 2>/dev/null
	printf '[exit %d]\n' "$_rc"
	printf '\n# sudo is never invoked by this script. The NOPASSWD list is committed in\n'
	printf '# docs/evidence/audit/privilege-probe.txt from T2; this script never runs sudo.\n'
} > "$OUT/09-denials.txt" 2>&1
printf 'wrote %s\n' "$OUT/09-denials.txt"

# --- 10 rootless libdrm toolchain -----------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# note: no package is installed; RPM payloads are unpacked into\n'
	printf '#       /mega/tmp/sm750/t3/libdrm and used through PKG_CONFIG_PATH.\n'
	printf '# ---- commands ----\n'
	printf 'mkdir -p /mega/tmp/sm750/t3/libdrm\n'
	printf 'cd /mega/tmp/sm750/t3/libdrm\n'
	printf 'dnf download libdrm libdrm-devel\n'
	printf 'for r in *.rpm; do rpm2cpio "$r" | cpio -idm; done\n'
	printf 'export PKG_CONFIG_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64/pkgconfig\n'
	printf 'export PKG_CONFIG_SYSROOT_DIR=/mega/tmp/sm750/t3/libdrm\n'
	printf 'export LD_LIBRARY_PATH=/mega/tmp/sm750/t3/libdrm/usr/lib64\n'
	printf '# ---- output ----\n'
	mkdir -p "$SCRATCH/libdrm"
	cd "$SCRATCH/libdrm" || exit 1
	if [ ! -f usr/lib64/pkgconfig/libdrm.pc ]; then
		printf '\n$ dnf download libdrm libdrm-devel\n'
		dnf download libdrm libdrm-devel 2>&1 | grep -Ev 'UserID|Fingerprint|From *:|Is this ok' | tail -8
		printf '[exit %d]\n' $?
		printf '\n$ for r in *.rpm; do rpm2cpio "$r" | cpio -idm; done\n'
		for r in *.rpm; do rpm2cpio "$r" | cpio -idm --quiet 2>/dev/null; done
		printf '[exit %d]\n' $?
	fi
	printf '\n$ ls -l *.rpm\n'; ls -l *.rpm 2>&1
	printf '\n$ PKG_CONFIG_PATH=... PKG_CONFIG_SYSROOT_DIR=... pkg-config --modversion libdrm\n'
	PKG_CONFIG_PATH=$SCRATCH/libdrm/usr/lib64/pkgconfig \
	PKG_CONFIG_SYSROOT_DIR=$SCRATCH/libdrm \
	pkg-config --modversion libdrm 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ pkg-config --cflags --libs libdrm\n'
	PKG_CONFIG_PATH=$SCRATCH/libdrm/usr/lib64/pkgconfig \
	PKG_CONFIG_SYSROOT_DIR=$SCRATCH/libdrm \
	pkg-config --cflags --libs libdrm 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ ls -l /mega/tmp/sm750/t3/libdrm/usr/include/xf86drm.h\n'
	ls -l "$SCRATCH/libdrm/usr/include/xf86drm.h" 2>&1
	printf '\n# ---- tests/check-vblank compile (isolated copy, repo untouched) ----\n'
	rm -rf "$SCRATCH/build"
	cp -a "${REPO_ROOT:-.}" "$SCRATCH/build" 2>/dev/null
	(cd "$SCRATCH/build" && \
		PKG_CONFIG_PATH=$SCRATCH/libdrm/usr/lib64/pkgconfig \
		PKG_CONFIG_SYSROOT_DIR=$SCRATCH/libdrm \
		make tests/check-vblank 2>&1)
	printf '[exit %d]\n' $?
	printf '\n$ ls -l /mega/tmp/sm750/t3/build/tests/check-vblank\n'
	ls -l "$SCRATCH/build/tests/check-vblank" 2>&1
	printf '[exit %d]\n' $?
} > "$OUT/10-rootless-libdrm.txt" 2>&1
printf 'wrote %s\n' "$OUT/10-rootless-libdrm.txt"

# --- 11 journalctl-as-dmesg probe -----------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# question: can journalctl replace dmesg without privileges?\n'
	printf '# ---- output ----\n'
	printf '\n$ journalctl -k -b --no-pager\n'
	journalctl -k -b --no-pager 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ journalctl -k -b -q --no-pager | wc -l\n'
	journalctl -k -b -q --no-pager 2>/dev/null | wc -l
	printf '[exit %d]\n' $?
	printf '\n$ journalctl --user -q --no-pager | wc -l  (user journal is readable)\n'
	journalctl --user -q --no-pager 2>/dev/null | wc -l
	printf '[exit %d]\n' $?
	printf '\n$ id -nG\n'; id -nG 2>&1
} > "$OUT/11-journalctl.txt" 2>&1
printf 'wrote %s\n' "$OUT/11-journalctl.txt"

# --- 12 external suite availability ---------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# command: dnf -q --color=never list --available <pkg>\n'
	printf '# ---- output ----\n'
	dnf -q --color=never list --available igt-gpu-tools kmscube v4l-utils libdrm libdrm-devel 2>&1 \
		| grep -Ev 'UserID|Fingerprint|From *:|Is this ok|Importing OpenPGP' \
		| sed -e 's/\x1b\[[0-9;]*m//g'
	printf '[exit %d]\n' $?
} > "$OUT/12-external-suites.txt" 2>&1
printf 'wrote %s\n' "$OUT/12-external-suites.txt"

# --- 13 make check recipe-command count -----------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# command: awk NR>=16 && NR<=32 && /^\\t/ Makefile | wc -l\n'
	printf '# ---- output ----\n'
	awk 'NR>=16 && NR<=32 && /^\t/' "${REPO_ROOT:-.}/Makefile" 2>&1 | nl -ba
	printf '# ---- count: %d ----\n' "$(awk 'NR>=16 && NR<=32 && /^\t/' "${REPO_ROOT:-.}/Makefile" | wc -l)"
} > "$OUT/13-make-check-count.txt" 2>&1
printf 'wrote %s\n' "$OUT/13-make-check-count.txt"

# --- 14 compiler resolution ------------------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# note: PATH puts /usr/local/cuda/bin ahead of /usr/bin, so bare\n'
	printf '#       gcc resolves to the CUDA toolchain, not the system gcc.\n'
	printf '# ---- output ----\n'
	printf '\n$ command -v cc\n'; command -v cc 2>&1
	printf '\n$ readlink -f "$(command -v cc)"\n'; readlink -f "$(command -v cc)" 2>&1
	printf '\n$ cc --version | head -1\n'; cc --version 2>&1 | head -1
	printf '\n$ command -v gcc\n'; command -v gcc 2>&1
	printf '\n$ rpm -qf /usr/bin/gcc\n'; rpm -qf /usr/bin/gcc 2>&1
	printf '\n$ rpm -qf /usr/local/cuda/bin/gcc\n'; rpm -qf /usr/local/cuda/bin/gcc 2>&1
	printf '\n$ printf "%%s\\n" "$PATH"\n'; printf '%s\n' "$PATH"
	printf '\n$ rpm -q libdrm\n'; rpm -q libdrm 2>&1
	printf '\n$ rpm -qf /usr/bin/modetest\n'; rpm -qf /usr/bin/modetest 2>&1
	printf '\n$ rpm -qf /usr/lib64/libdrm.so.2\n'; rpm -qf /usr/lib64/libdrm.so.2 2>&1
	printf '\n$ ls -l /usr/include/xf86drm.h\n'; ls -l /usr/include/xf86drm.h 2>&1
} > "$OUT/14-compiler-and-libdrm-rpm.txt" 2>&1
printf 'wrote %s\n' "$OUT/14-compiler-and-libdrm-rpm.txt"

# --- 15 edid-decode (rootless, from extracted v4l-utils) -------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# note: edid-decode is not installed; it is unpacked rootless from the\n'
	printf '#       v4l-utils RPM into /mega/tmp/sm750/t3/v4l.\n'
	printf '# command: rpm2cpio v4l-utils-1.32.0-1.fc43.x86_64.rpm | cpio -idm\n'
	printf '# command: ./usr/bin/edid-decode /sys/class/drm/card0-HDMI-A-1/edid\n'
	printf '# ---- output ----\n'
	if [ ! -x "$SCRATCH/v4l/usr/bin/edid-decode" ]; then
		mkdir -p "$SCRATCH/v4l"
		(cd "$SCRATCH/v4l" && dnf -q download v4l-utils >/dev/null 2>&1 && \
			for r in *.rpm; do rpm2cpio "$r" | cpio -idm --quiet 2>/dev/null; done)
	fi
	"$SCRATCH/v4l/usr/bin/edid-decode" /sys/class/drm/card0-HDMI-A-1/edid 2>&1
	printf '[exit %d]\n' $?
} > "$OUT/15-edid-decode.txt" 2>&1
printf 'wrote %s\n' "$OUT/15-edid-decode.txt"

# --- 16 kernel devmem policy ----------------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# note: /proc/config.gz is absent; the boot config file is world-readable.\n'
	printf '# ---- output ----\n'
	printf '\n$ ls -l /boot/config-%s\n' "$(uname -r)"
	ls -l "/boot/config-$(uname -r)" 2>&1
	printf '\n$ grep -E "^CONFIG_(STRICT_DEVMEM|IO_STRICT_DEVMEM)" /boot/config-%s\n' "$(uname -r)"
	grep -E '^CONFIG_(STRICT_DEVMEM|IO_STRICT_DEVMEM)' "/boot/config-$(uname -r)" 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ modinfo sm750hdmidrm | grep -c "^parm:"\n'
	modinfo sm750hdmidrm 2>/dev/null | grep -c '^parm:'
} > "$OUT/16-kernel-devmem-policy.txt" 2>&1
printf 'wrote %s\n' "$OUT/16-kernel-devmem-policy.txt"

# --- 17 kernel header trees ------------------------------------------------
{
	printf '# host: %s\n' "$(uname -n)"
	printf '# kernel: %s\n' "$(uname -r)"
	printf '# utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '# command: readlink of every /lib/modules/*/build plus rpm -q of the\n'
	printf '#          kernel packages and available kernel-devel candidates\n'
	printf '# ---- output ----\n'
	for _l in /lib/modules/*/build; do
		printf '\n$ readlink -f %s\n' "$_l"
		readlink -f "$_l" 2>&1
	done
	printf '\n$ for d in /lib/modules/*/; do echo $d; ls $d; done\n'
	for _d in /lib/modules/*/; do
		printf '%s\n' "$_d"
		ls "$_d" 2>&1
	done
	printf '\n$ rpm -q kernel-core kernel-devel\n'
	rpm -q kernel-core kernel-devel 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ rpm -q kernel-core-6.18.13-200.fc43.x86_64\n'
	rpm -q kernel-core-6.18.13-200.fc43.x86_64 2>&1
	printf '[exit %d]\n' $?
	printf '\n$ dnf list --available kernel-devel\n'
	dnf -q --color=never list --available kernel-devel 2>/dev/null
} > "$OUT/17-kernel-headers.txt" 2>&1
printf 'wrote %s\n' "$OUT/17-kernel-headers.txt"

printf 'capture complete\n'
