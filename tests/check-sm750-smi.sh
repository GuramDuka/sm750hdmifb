#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Gate for tools/sm750-smi.  No GPU and no root are needed: every field is
# driven from a synthetic sysfs tree under $TMPDIR, the card node is a plain
# file, and the process table is a synthetic <proc> root.  Five defects are
# planted into copies of the source and must each be rejected, so the gate
# cannot pass by accident.
#
# Usage: tests/check-sm750-smi.sh
set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}
mkdir -p -- "$TMPDIR"

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tool=$project_dir/tools/sm750-smi
src=$project_dir/tools/sm750-smi.c
cc=${CC:-cc}

if ! pkg-config --exists libdrm; then
	echo "sm750-smi gate: libdrm development files are required (pkg-config libdrm)" >&2
	echo "  Debian/Ubuntu: sudo apt install libdrm-dev" >&2
	echo "  Fedora:        sudo dnf install libdrm-devel" >&2
	echo "  Rootless alternative: see docs/ENVIRONMENT.md section 3" >&2
	exit 1
fi

# libdrm may come from a rootless pkg-config root; make the runtime find it.
libdir=$(pkg-config --variable=libdir libdrm 2>/dev/null || true)
if [ -n "$libdir" ]; then
	export LD_LIBRARY_PATH=$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi

fail=0
complain() {
	echo "sm750-smi gate: $*" >&2
	fail=1
}

# --- (a) build ---------------------------------------------------------------
make -C "$project_dir" tools/sm750-smi CC="$cc" >/dev/null || {
	echo "sm750-smi gate: build failed" >&2
	exit 1
}
[ -x "$tool" ] || { echo "sm750-smi gate: $tool is missing" >&2; exit 1; }

scratch=$(mktemp -d "${TMPDIR}/sm750-smi-gate.XXXXXX")
trap 'chmod -R u+rwX "$scratch" 2>/dev/null || true; rm -rf -- "$scratch"' EXIT

# --- the field set the gate holds the tool to -------------------------------
fields=(
	name driver_version srcversion bus_id pci.device_id pci.subsystem_id
	pci.revision memory.total memory.used memory.free display.connector
	display.connected display.mode display.refresh_hz
	display.pixel_clock_khz display.hpd display.rxsense display.link
	crtc.index vblank.count crc.support test_pattern test_pattern_period_ms
	test_pattern_anim_ms processes.count power.runtime_status module_loaded
)

# --- (b) --list-fields ------------------------------------------------------
list=$("$tool" --list-fields)
listed=$(grep -cE 'source: ' <<<"$list" || true)
if [ "$listed" -ne "${#fields[@]}" ]; then
	complain "--list-fields lists $listed fields, the gate requires ${#fields[@]}"
fi
for f in "${fields[@]}"; do
	n=$(grep -cE "^${f}[[:space:]]" <<<"$list" || true)
	if [ "$n" -ne 1 ]; then
		complain "--list-fields mentions $f $n times, expected exactly once"
	fi
done
# Every listed field must also be queryable, and nothing else may be.
query_all=$("$tool" --query="$(IFS=,; echo "${fields[*]}")" --format=csv,noheader)
[ "$(awk -F, '{print NF}' <<<"$query_all")" -eq "${#fields[@]}" ] ||
	complain "querying all fields does not return ${#fields[@]} CSV columns"

# --- fixture builder --------------------------------------------------------
# fixture <root>: a complete synthetic device with every source present.
fixture() {
	local root=$1
	mkdir -p "$root/sys/class/drm/card0/device/power" \
		"$root/sys/class/drm/card0-HDMI-A-1" \
		"$root/sys/module/sm750hdmidrm/parameters" \
		"$root/sys/kernel/debug/dri/0/crtc-0/crc" \
		"$root/proc/4242/fd" "$root/proc/5353/fd" "$root/proc/9999/fd" \
		"$root/dev/dri"
	: >"$root/dev/dri/card0"
	cat >"$root/sys/class/drm/card0/device/uevent" <<-EOF
		DRIVER=sm750hdmidrm
		PCI_CLASS=30000
		PCI_ID=126F:0750
		PCI_SUBSYS_ID=126F:0750
		PCI_SLOT_NAME=0000:07:00.0
	EOF
	echo 0x126f >"$root/sys/class/drm/card0/device/vendor"
	echo 0x0750 >"$root/sys/class/drm/card0/device/device"
	echo 0x126f >"$root/sys/class/drm/card0/device/subsystem_vendor"
	echo 0x0750 >"$root/sys/class/drm/card0/device/subsystem_device"
	echo 0xa1 >"$root/sys/class/drm/card0/device/revision"
	echo 1073741824 >"$root/sys/class/drm/card0/device/mem_info_vram_total"
	echo 268435456 >"$root/sys/class/drm/card0/device/mem_info_vram_used"
	echo 1920x1080 >"$root/sys/class/drm/card0/device/active_mode"
	echo 60.00 >"$root/sys/class/drm/card0/device/active_mode_refresh_hz"
	echo 148500 >"$root/sys/class/drm/card0/device/active_mode_pixel_clock_khz"
	echo high >"$root/sys/class/drm/card0/device/hpd"
	echo high >"$root/sys/class/drm/card0/device/rxsense"
	echo on >"$root/sys/class/drm/card0/device/link_state"
	echo 0 >"$root/sys/class/drm/card0/device/active_crtc"
	echo 123456 >"$root/sys/class/drm/card0/device/vblank_count"
	echo yes >"$root/sys/class/drm/card0/device/crc_supported"
	echo connected >"$root/sys/class/drm/card0-HDMI-A-1/status"
	echo enabled >"$root/sys/class/drm/card0-HDMI-A-1/enabled"
	printf '1920x1080\n1280x720\n' >"$root/sys/class/drm/card0-HDMI-A-1/modes"
	echo 9.9.9 >"$root/sys/module/sm750hdmidrm/version"
	echo TEST1234 >"$root/sys/module/sm750hdmidrm/srcversion"
	echo 1 >"$root/sys/module/sm750hdmidrm/parameters/test_pattern"
	echo 1000 >"$root/sys/module/sm750hdmidrm/parameters/test_pattern_period_ms"
	echo 33 >"$root/sys/module/sm750hdmidrm/parameters/test_pattern_anim_ms"
	echo active >"$root/sys/class/drm/card0/device/power/runtime_status"
	printf 'Xorg\n' >"$root/proc/4242/comm"
	printf 'kmscube\n' >"$root/proc/5353/comm"
	printf 'bash\n' >"$root/proc/9999/comm"
	ln -s "$root/dev/dri/card0" "$root/proc/4242/fd/7"
	ln -s "$root/dev/dri/card0" "$root/proc/5353/fd/9"
	ln -s /dev/null "$root/proc/9999/fd/0"
	: >"$root/sys/kernel/debug/dri/0/crtc-0/crc/control"
}

# run <root> [tool args...]
run() {
	local root=$1
	shift
	"$tool" --sysfs-root "$root/sys" --card "$root/dev/dri/card0" \
		--proc-root "$root/proc" --no-color "$@"
}

# value <root> <field>
value() {
	run "$1" --query="$2" --format=csv,noheader
}

# --- (c) the fixture matrix -------------------------------------------------
full=$scratch/full
fixture "$full"

expected=(
	"name|sm750hdmidrm"
	"driver_version|9.9.9"
	"srcversion|TEST1234"
	"bus_id|0000:07:00.0"
	"pci.device_id|126f:0750"
	"pci.subsystem_id|126f:0750"
	"pci.revision|a1"
	"memory.total|1073741824"
	"memory.used|268435456"
	"memory.free|805306368"
	"display.connector|HDMI-A-1"
	"display.connected|connected"
	"display.mode|1920x1080"
	"display.refresh_hz|60.00"
	"display.pixel_clock_khz|148500"
	"display.hpd|high"
	"display.rxsense|high"
	"display.link|on"
	"crtc.index|0"
	"vblank.count|123456"
	"crc.support|yes"
	"test_pattern|1"
	"test_pattern_period_ms|1000"
	"test_pattern_anim_ms|33"
	"processes.count|2"
	"power.runtime_status|active"
	"module_loaded|yes"
)
for row in "${expected[@]}"; do
	f=${row%%|*}
	want=${row#*|}
	got=$(value "$full" "$f")
	if [ "$got" != "$want" ]; then
		complain "full fixture: $f is '$got', expected '$want'"
	fi
done
# processes table names both holders; the count field counts the same two.
table=$(run "$full")
for want in "Xorg" "kmscube" "4242" "5353"; do
	grep -qF "$want" <<<"$table" ||
		complain "full fixture: process table does not show $want"
done

# F2: debugfs missing -> CRC unresolved for a reason, not invented.
f2=$scratch/f2-debugfs-missing
fixture "$f2"
rm -rf "$f2/sys/kernel/debug"
rm -f "$f2/sys/class/drm/card0/device/crc_supported"
if [ "$(value "$f2" crc.support)" != "n/a" ]; then
	complain "debugfs-missing fixture: crc.support is not n/a"
fi
set +e
out=$(run "$f2" --query=crc.support --strict 2>&1)
rc=$?
set -e
[ "$rc" -eq 3 ] || complain "debugfs-missing fixture: --strict exit $rc, expected 3"
grep -q "CRC control not present" <<<"$out" ||
	complain "debugfs-missing fixture: reason is not reported"

# F3: debugfs present but not readable by this caller -> needs root reason.
f3=$scratch/f3-needs-root
fixture "$f3"
rm -f "$f3/sys/class/drm/card0/device/crc_supported"
chmod 000 "$f3/sys/kernel/debug/dri/0/crtc-0/crc/control"
if [ "$(id -u)" -eq 0 ]; then
	echo "sm750-smi gate: SKIP needs-root reason (running as root)" >&2
else
	if [ "$(value "$f3" crc.support)" != "n/a" ]; then
		complain "needs-root fixture: crc.support is not n/a"
	fi
	set +e
	out=$(run "$f3" --query=crc.support --strict 2>&1)
	rc=$?
	set -e
	[ "$rc" -eq 3 ] || complain "needs-root fixture: --strict exit $rc, expected 3"
	grep -qF "needs root (debugfs)" <<<"$out" ||
		complain "needs-root fixture: reason is not 'needs root (debugfs)'"
fi

# F4: companion attributes absent -> named reason and --strict exit 3.
f4=$scratch/f4-absent-attrs
fixture "$f4"
rm -f "$f4/sys/class/drm/card0/device"/{mem_info_vram_total,mem_info_vram_used,active_mode,active_mode_refresh_hz,active_mode_pixel_clock_khz,hpd,rxsense,link_state,active_crtc,vblank_count,crc_supported}
rm -rf "$f4/sys/kernel/debug"
for f in memory.total memory.used display.hpd display.rxsense display.link; do
	if [ "$(value "$f4" "$f")" != "n/a" ]; then
		complain "absent-attrs fixture: $f is not n/a"
	fi
done
set +e
out=$(run "$f4" --query=memory.total --strict 2>&1)
rc=$?
set -e
[ "$rc" -eq 3 ] || complain "absent-attrs fixture: --strict exit $rc, expected 3"
grep -qF "driver attribute not present in this version" <<<"$out" ||
	complain "absent-attrs fixture: attribute-absent reason is missing"
set +e
run "$f4" --query=driver_version --strict >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || complain "absent-attrs fixture: resolvable field exits $rc, expected 0"

# F5: disconnected connector, modes still listed.
f5=$scratch/f5-disconnected
fixture "$f5"
echo disconnected >"$f5/sys/class/drm/card0-HDMI-A-1/status"
[ "$(value "$f5" display.connected)" = "disconnected" ] ||
	complain "disconnected fixture: display.connected is wrong"
[ "$(value "$f5" display.connector)" = "HDMI-A-1" ] ||
	complain "disconnected fixture: connector is not reported"

# F6: zero modes -> mode unresolved, no crash, reason names the empty list.
f6=$scratch/f6-zero-modes
fixture "$f6"
: >"$f6/sys/class/drm/card0-HDMI-A-1/modes"
rm -f "$f6/sys/class/drm/card0/device/active_mode"
[ "$(value "$f6" display.mode)" = "n/a" ] ||
	complain "zero-modes fixture: display.mode is not n/a"
set +e
out=$(run "$f6" --query=display.mode --strict 2>&1)
rc=$?
set -e
[ "$rc" -eq 3 ] || complain "zero-modes fixture: --strict exit $rc, expected 3"
grep -qF "no active mode" <<<"$out" ||
	complain "zero-modes fixture: reason does not name the empty modes list"

# F7: a sysfs file longer than one page must be read bounded and still work.
f7=$scratch/f7-truncated
fixture "$f7"
{
	printf '1920x1080\n'
	for _ in $(seq 1 400); do printf '1280x720\n'; done
} >"$f7/sys/class/drm/card0-HDMI-A-1/modes"
rm -f "$f7/sys/class/drm/card0/device/active_mode"
[ "$(value "$f7" display.mode)" = "1920x1080" ] ||
	complain "truncated fixture: first mode line was not read"

# F8: malformed numbers must become n/a, never a silent zero.
f8=$scratch/f8-malformed
fixture "$f8"
echo 12x4 >"$f8/sys/class/drm/card0/device/mem_info_vram_used"
echo abc >"$f8/sys/class/drm/card0/device/active_mode_refresh_hz"
[ "$(value "$f8" memory.used)" = "n/a" ] ||
	complain "malformed fixture: memory.used is not n/a"
[ "$(value "$f8" memory.free)" = "n/a" ] ||
	complain "malformed fixture: memory.free is not n/a"
[ "$(value "$f8" display.refresh_hz)" = "n/a" ] ||
	complain "malformed fixture: display.refresh_hz is not n/a"
set +e
out=$(run "$f8" --query=memory.used,display.refresh_hz --strict 2>&1)
rc=$?
set -e
[ "$rc" -eq 3 ] || complain "malformed fixture: --strict exit $rc, expected 3"
grep -qF "malformed" <<<"$out" ||
	complain "malformed fixture: reason does not say malformed"

# F8b: the driver's documented -1 means "no CRTC is enabled", not garbage.
f8b=$scratch/f8b-inactive-crtc
fixture "$f8b"
echo -1 >"$f8b/sys/class/drm/card0/device/active_crtc"
[ "$(value "$f8b" crtc.index)" = "n/a" ] ||
	complain "inactive-crtc fixture: crtc.index is not n/a"
set +e
out=$(run "$f8b" --query=crtc.index --strict 2>&1)
rc=$?
set -e
[ "$rc" -eq 3 ] || complain "inactive-crtc fixture: --strict exit $rc, expected 3"
grep -qF "n/a (no active CRTC)" <<<"$out" ||
	complain "inactive-crtc fixture: reason is not 'n/a (no active CRTC)'"
if grep -qF "malformed" <<<"$out"; then
	complain "inactive-crtc fixture: -1 was reported as malformed"
fi

# F8c: a value that really is garbage is still malformed, not "no CRTC".
f8c=$scratch/f8c-garbage-crtc
fixture "$f8c"
echo bogus >"$f8c/sys/class/drm/card0/device/active_crtc"
[ "$(value "$f8c" crtc.index)" = "n/a" ] ||
	complain "garbage-crtc fixture: crtc.index is not n/a"
set +e
out=$(run "$f8c" --query=crtc.index --strict 2>&1)
rc=$?
set -e
[ "$rc" -eq 3 ] || complain "garbage-crtc fixture: --strict exit $rc, expected 3"
grep -qF "malformed active_crtc attribute" <<<"$out" ||
	complain "garbage-crtc fixture: reason does not say malformed"
if grep -qF "no active CRTC" <<<"$out"; then
	complain "garbage-crtc fixture: garbage was reported as no active CRTC"
fi

# F9: card node missing -> PCI-only view and exit 2.
f9=$scratch/f9-no-card
fixture "$f9"
set +e
out=$("$tool" --sysfs-root "$f9/sys" --card "$f9/dev/dri/absent" \
	--proc-root "$f9/proc" --no-color 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || complain "missing-card fixture: exit $rc, expected 2"
grep -qF "PCI-only view" <<<"$out" ||
	complain "missing-card fixture: no PCI-only notice"
grep -qF "0000:07:00.0" <<<"$out" ||
	complain "missing-card fixture: PCI bus id missing from the PCI-only view"
set +e
"$tool" --sysfs-root "$f9/sys" --card "$f9/dev/dri/absent" --id=5 \
	--no-color >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || complain "missing index: exit $rc, expected 2"

# --- (d) --strict exit codes ------------------------------------------------
set +e
run "$full" --strict >/dev/null 2>"$scratch/strict.err"
rc=$?
set -e
[ "$rc" -eq 0 ] || complain "full fixture --strict exit $rc, expected 0"
[ ! -s "$scratch/strict.err" ] ||
	complain "full fixture --strict wrote reasons for resolved fields"

# --- (e) CSV and JSON shapes ------------------------------------------------
csv=$(run "$full" --query=name,memory.total,display.mode --format=csv)
python3 - "$csv" <<'PY' || complain "CSV shape is invalid"
import csv, io, sys
rows = list(csv.reader(io.StringIO(sys.argv[1])))
assert len(rows) == 2, rows
assert rows[0] == ["name", "memory.total", "display.mode"], rows[0]
assert len(rows[1]) == 3, rows[1]
assert rows[1][0] == "sm750hdmidrm", rows[1]
assert rows[1][1] == "1073741824", rows[1]
PY
js=$(run "$full" --query=name,memory.total,display.mode --format=json)
python3 - "$js" <<'PY' || complain "JSON shape is invalid"
import json, sys
doc = json.loads(sys.argv[1])
assert isinstance(doc, list) and len(doc) == 1, doc
assert doc[0]["name"] == "sm750hdmidrm", doc
assert doc[0]["memory.total"] == "1073741824", doc
assert doc[0]["display.mode"] == "1920x1080", doc
PY
# JSON must stay valid when a requested field is unavailable.
js_na=$(run "$f4" --query=name,memory.total --format=json)
python3 - "$js_na" <<'PY' || complain "JSON with n/a is invalid"
import json, sys
doc = json.loads(sys.argv[1])
assert doc[0]["memory.total"] == "n/a", doc
PY

# Non-tty output must never carry ANSI escapes.
for args in "" "--query=name" "--query=name --format=json"; do
	out=$(run "$full" $args 2>&1)
	if printf '%s' "$out" | LC_ALL=C grep -q $'\033'; then
		complain "ANSI escape in output for arguments: '$args'"
	fi
done

# --loop redraws, and SIGINT exits 0.  One second is the minimum.
set +e
run "$full" --loop=0 >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] || complain "--loop=0 exit $rc, expected 1"
run "$full" --loop=1 >"$scratch/loop.out" 2>&1 &
loop_pid=$!
sleep 2
kill -INT "$loop_pid"
set +e
wait "$loop_pid"
rc=$?
set -e
[ "$rc" -eq 0 ] || complain "--loop did not exit 0 on SIGINT (exit $rc)"
[ "$(grep -c 'sm750-smi gate' "$scratch/loop.out" || true)" -eq 0 ] ||
	complain "--loop produced gate errors"

# --- (f) planted negative controls ------------------------------------------
# Each control is planted into a private copy of the source, rebuilt, and run.
# If the planted tool still passes the expectation, the gate fails.
build_copy() {
	"$cc" -O2 -Wall -Wextra -Werror $(pkg-config --cflags libdrm) \
		-o "$2" "$1/tools/sm750-smi.c" $(pkg-config --libs libdrm)
}

report_rejected() {
	echo "planted control '$1' rejected: $2"
}

# 1. A field in the table with no getter (listed but not implemented).
p1=$scratch/plant1
mkdir -p "$p1/tools"
cp "$src" "$p1/tools/sm750-smi.c"
sed -i '/get_module_loaded },/a\	{ "planted_field", "planted", "none", NULL },' \
	"$p1/tools/sm750-smi.c"
if ! build_copy "$p1" "$scratch/plant1.bin"; then
	complain "planted control 'field-without-getter' did not build"
else
	set +e
	out=$("$scratch/plant1.bin" --list-fields 2>&1)
	rc=$?
	set -e
	if [ "$rc" -eq 0 ]; then
		complain "planted control 'field-without-getter' was not rejected"
	elif ! grep -q "no getter" <<<"$out"; then
		complain "planted control 'field-without-getter' failed for the wrong reason: $out"
	else
		report_rejected field-without-getter \
			"$scratch/plant1.bin --list-fields -> exit $rc, '$(head -n 1 <<<"$out")'"
	fi
fi

# 2. A hardcoded driver version instead of the module attribute.
p2=$scratch/plant2
mkdir -p "$p2/tools"
cp "$src" "$p2/tools/sm750-smi.c"
sed -i '/^static int get_driver_version/,/^}/ s|if (read_first_line(path, out, cap) > 0)|snprintf(out, cap, "0.6.2"); if (1)|' \
	"$p2/tools/sm750-smi.c"
if ! build_copy "$p2" "$scratch/plant2.bin"; then
	complain "planted control 'hardcoded-version' did not build"
else
	got=$("$scratch/plant2.bin" --sysfs-root "$full/sys" \
		--card "$full/dev/dri/card0" --proc-root "$full/proc" \
		--no-color --query=driver_version --format=csv,noheader)
	if [ "$got" = "9.9.9" ]; then
		complain "planted control 'hardcoded-version' was not rejected"
	else
		report_rejected hardcoded-version \
			"fixture version 9.9.9, planted tool printed '$got'"
	fi
fi

# 3. A missing attribute silently rendered as 0 instead of n/a.
p3=$scratch/plant3
mkdir -p "$p3/tools"
cp "$src" "$p3/tools/sm750-smi.c"
sed -i '/^static int get_memory_used/,/^}/ s|return 0;|snprintf(out, cap, "0"); return 1;|' \
	"$p3/tools/sm750-smi.c"
if ! build_copy "$p3" "$scratch/plant3.bin"; then
	complain "planted control 'zero-instead-of-na' did not build"
else
	got=$("$scratch/plant3.bin" --sysfs-root "$f4/sys" \
		--card "$f4/dev/dri/card0" --proc-root "$f4/proc" \
		--no-color --query=memory.used --format=csv,noheader)
	if [ "$got" = "n/a" ]; then
		complain "planted control 'zero-instead-of-na' was not rejected"
	elif [ "$got" != "0" ]; then
		complain "planted control 'zero-instead-of-na' failed for the wrong reason: '$got'"
	else
		report_rejected zero-instead-of-na \
			"attribute absent, planted tool printed '$got', expected n/a"
	fi
fi

# 4. An ANSI escape emitted even with --no-color.
p4=$scratch/plant4
mkdir -p "$p4/tools"
cp "$src" "$p4/tools/sm750-smi.c"
sed -i 's|printf("+---|printf("\\033[1m"); printf("+---|' "$p4/tools/sm750-smi.c"
if ! build_copy "$p4" "$scratch/plant4.bin"; then
	complain "planted control 'ansi-with-no-color' did not build"
else
	set +e
	out=$("$scratch/plant4.bin" --sysfs-root "$full/sys" \
		--card "$full/dev/dri/card0" --proc-root "$full/proc" \
		--no-color 2>&1)
	rc=$?
	set -e
	if ! printf '%s' "$out" | LC_ALL=C grep -q $'\033'; then
		complain "planted control 'ansi-with-no-color' was not rejected"
	else
		report_rejected ansi-with-no-color \
			"--no-color output carried an ESC byte (exit $rc)"
	fi
fi

# 5. The driver's -1 ("no CRTC enabled") treated as a malformed attribute.
p5=$scratch/plant5
mkdir -p "$p5/tools"
cp "$src" "$p5/tools/sm750-smi.c"
python3 - "$p5/tools/sm750-smi.c" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = '\t\tif (strcmp(buf, "-1") == 0) {\n'
assert needle in s, "planted control anchor missing"
open(p, "w").write(s.replace(needle, '\t\tif (0) {\n', 1))
PY
if ! build_copy "$p5" "$scratch/plant5.bin"; then
	complain "planted control 'minus-one-is-malformed' did not build"
else
	set +e
	out=$("$scratch/plant5.bin" --sysfs-root "$f8b/sys" \
		--card "$f8b/dev/dri/card0" --proc-root "$f8b/proc" \
		--no-color --query=crtc.index --strict 2>&1)
	rc=$?
	set -e
	if grep -qF "malformed" <<<"$out"; then
		report_rejected minus-one-is-malformed \
			"active_crtc -1 reported as malformed (exit $rc): '$(head -n 1 <<<"$out")'"
	else
		complain "planted control 'minus-one-is-malformed' was not rejected: $out"
	fi
fi

[ "$fail" -eq 0 ] || exit 1
echo "sm750-smi checks passed (${#fields[@]} fields, 11 fixtures, 5 planted controls)"
