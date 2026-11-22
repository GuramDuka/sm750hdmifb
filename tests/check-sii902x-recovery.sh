#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# A42 gate: SiI9024A readiness and I2C-timeout recovery.
#
# docs/evidence/runtime/30-sii9024a-readiness-and-timeout.txt records what this
# board did: a monitor power cycle produced 20 "SiI9024A receiver not ready
# after 2000 ms" lines in 2.5 minutes, all of the form status=04 (HPD high,
# RSEN low), and never a -110. SiI-PR-1064-A says 0x3d bit 2 is the plugged
# state and bit 3 the powered receiver, and that a plugged, unpowered sink is
# normal and its EDID is readable. The gate therefore requires:
#
#   - the readiness wait accumulates a stable PLUGGED_STATUS (and accepts a
#     stable RX_SENSE_STATUS, the KC-KVM8201 case), with a 500 ms budget that
#     matches TPLUG_DLY, and logs RSEN=1 as ready instead of "not ready",
#   - a TPI write that times out is retried after a bus clear, three attempts
#     in total, and only a timeout is retried - a NACK is an answer,
#   - the retrying write covers the option-ROM step, the initialization
#     register, the video block, the AVI InfoFrame and the HPD workaround,
#   - a write that still times out does not fail the enable: it warns once
#     with the stage name and continues on the compatibility path,
#   - reads never go through the retrying helper, and the EDID read is skipped
#     while the transmitter is powered down.
#
# The gate is source level and rejects its own planted defects.
#
# Usage: tests/check-sii902x-recovery.sh [source dir]
#        tests/check-sii902x-recovery.sh --single [source dir]  (no self-test)

set -euo pipefail
export TMPDIR=${TMPDIR:-/mega/tmp/sm750/tmp}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

mode=full
if [ "${1:-}" = "--single" ]; then
	mode=single
	shift
fi
src_dir=${1:-${SM750_SRC_DIR:-$project_dir/src}}

sii=$src_dir/sii902x.c
drm=$src_dir/sm750_drm.c
hdr=$src_dir/sii902x.h

fail=0
complain() {
	echo "sii902x recovery: $*" >&2
	fail=1
	return 0
}
require() {
	if ! grep -Fq -- "$2" "$1"; then
		complain "$3 (missing '$2')"
	fi
}
deny() {
	if grep -Fq -- "$2" "$1"; then
		complain "$3 ('$2' is present)"
	fi
}
require_re() {
	if ! grep -Eq -- "$2" "$1"; then
		complain "$3 (no match for /$2/)"
	fi
}
# Extract one function body: from the last line matching the signature regex
# (the definition, not an earlier prototype) to the next column-0 }.
fn_body() {
	awk -v pat="$2" '
		{ lines[NR] = $0 }
		$0 ~ pat { start = NR }
		END {
			if (!start)
				exit
			for (i = start; i <= NR; i++) {
				print lines[i]
				if (lines[i] ~ /^}/)
					exit
			}
		}' "$1"
}
body_require() {
	if ! grep -Fq -- "$2" <<<"$1"; then
		complain "$3 (missing '$2')"
	fi
}
body_deny() {
	if grep -Fq -- "$2" <<<"$1"; then
		complain "$3 ('$2' is present)"
	fi
}

for file in "$sii" "$drm" "$hdr"; do
	if [ ! -f "$file" ]; then
		echo "sii902x recovery: $file is missing" >&2
		exit 1
	fi
done

# --- the readiness budget and its two live bits ------------------------------
require_re "$sii" '^#define SII902X_READY_BUDGET_MS[[:space:]]+500$' \
	"the readiness budget is not 500 ms"
require_re "$sii" '^#define SII902X_READY_STABLE_MS[[:space:]]+100$' \
	"the readiness stability window is not 100 ms"
require_re "$sii" '^#define SII902X_READY_POLL_MS[[:space:]]+25$' \
	"the readiness poll interval is not 25 ms"

wait_body=$(fn_body "$sii" '^static int sii902x_wait_receiver_ready[(]')
if [ -z "$wait_body" ]; then
	complain "sii902x_wait_receiver_ready is missing"
else
	body_require "$wait_body" \
		'elapsed < SII902X_READY_BUDGET_MS' \
		"the readiness wait does not poll to the 500 ms budget"
	body_require "$wait_body" \
		'plugged = (value & SII902X_PLUGGED_STATUS) ?' \
		"the readiness wait does not accumulate the plugged (HPD) bit"
	body_require "$wait_body" \
		'plugged >= SII902X_READY_STABLE_MS' \
		"the readiness wait does not require HPD to be stable"
	body_require "$wait_body" \
		'receiver = (value & SII902X_RX_SENSE_STATUS) ?' \
		"the readiness wait ignores receiver sense entirely"
	body_require "$wait_body" \
		'receiver >= SII902X_READY_STABLE_MS' \
		"receiver sense does not count as ready when it is stable"
	body_deny "$wait_body" '2000' \
		"the readiness wait still carries the 2000 ms budget"
	body_require "$wait_body" \
		'SiI9024A receiver ready after %u ms: HPD=%u RSEN=%u status=%02x\n' \
		"the ready line does not report both live bits"
	body_require "$wait_body" \
		'SiI9024A receiver not ready after %u ms: HPD=%u RSEN=%u status=%02x; enabling for compatibility\n' \
		"the compatibility line changed shape"
	body_require "$wait_body" 'dev_warn(dev,' \
		"the not-ready line is not a warning"
	body_deny "$wait_body" '-ETIMEDOUT' \
		"the readiness wait can fail the enable"
	body_deny "$wait_body" '-ENXIO' \
		"the readiness wait can fail the enable"
fi

# --- the retrying write helper ----------------------------------------------
require_re "$sii" '^#define SII902X_WRITE_ATTEMPTS[[:space:]]+3$' \
	"the retry count is not three attempts"
require_re "$sii" '^#define SII902X_RECOVER_DELAY_US[[:space:]]+10000$' \
	"the post-recovery delay is not 10 ms"

retry_body=$(fn_body "$sii" '^static int sii902x_write_block_retrying[(]')
if [ -z "$retry_body" ]; then
	complain "sii902x_write_block_retrying is missing"
else
	body_require "$retry_body" 'ret != -ETIMEDOUT' \
		"the retry loop does not distinguish a timeout from a NACK"
	body_deny "$retry_body" '-ENXIO' \
		"the retry loop treats a NACK as recoverable"
	body_require "$retry_body" 'attempt < SII902X_WRITE_ATTEMPTS' \
		"the retry loop does not use the attempt bound"
	body_require "$retry_body" 'sm750_sw_i2c_recover_bus();' \
		"the retry does not clear the bus first"
	body_require "$retry_body" 'if (!sii902x_use_hardware_i2c)' \
		"the retry clears a bus the hardware I2C path owns"
	body_require "$retry_body" 'usleep_range(SII902X_RECOVER_DELAY_US,' \
		"the retry does not wait for the sink after the bus clear"
	body_require "$retry_body" '*retries = attempt;' \
		"the retry does not report how many attempts it took"
fi

wrap_body=$(fn_body "$sii" '^static int sii902x_write_recovering[(]')
if [ -z "$wrap_body" ]; then
	complain "sii902x_write_recovering is missing"
else
	body_require "$wrap_body" \
		'sii902x_write_block_retrying(reg, data, length, &retries)' \
		"the recovering write does not use the retry loop"
	body_require "$wrap_body" 'if (ret != -ETIMEDOUT)' \
		"the recovering write does not keep the other errors"
	body_require "$wrap_body" '(transient I2C timeout, retried %u times)' \
		"the timeout line does not name the retry count"
	body_require "$wrap_body" 'sii902x_mode_stage' \
		"the timeout line does not name the failing stage"
	body_require "$wrap_body" 'return 0;' \
		"a write that still times out fails the enable"
fi

# --- the call sites ----------------------------------------------------------
require "$sii" 'sii902x_write_recovering(dev, "option-ROM step",' \
	"the option-ROM register sequence does not retry a timed-out step"
require "$sii" 'sii902x_write_recovering(dev, "initialization register",' \
	"the initialization register sequence does not retry a timed-out write"
require "$sii" 'sii902x_write_recovering(dev, "TPI video timing",' \
	"the video block write does not retry a timeout"
require "$sii" 'SII902X_TPI_VIDEO_DATA, video,' \
	"the video block write no longer targets TPI 0x00"
require "$sii" 'sii902x_write_recovering(dev, "AVI InfoFrame",' \
	"the AVI InfoFrame write does not retry a timeout"
require "$sii" 'SII902X_TPI_AVI_INFOFRAME,' \
	"the AVI InfoFrame write no longer targets TPI 0x0c"
if [ "$(grep -Fc 'sii902x_write_recovering(dev, "HPD workaround' "$sii")" -lt 3 ]; then
	complain "the HPD workaround does not retry its timed-out writes"
fi

# --- reads and the powered-down precondition ---------------------------------
edid_body=$(fn_body "$sii" '^int sm750_sii902x_read_edid[(]')
if [ -z "$edid_body" ]; then
	complain "sm750_sii902x_read_edid is missing"
else
	body_deny "$edid_body" 'sii902x_write_recovering' \
		"the EDID read goes through the write retry helper"
	body_deny "$edid_body" 'sii902x_write_block_retrying' \
		"the EDID read goes through the write retry helper"
	body_require "$edid_body" \
		'sm750_sw_i2c_read_block(EDID_I2C_ADDR_WRITE, 0, edid,' \
		"the EDID block read is no longer a direct DDC read"
	body_require "$edid_body" \
		'ret = sii902x_read(SII902X_SYS_CTRL_DATA, &value);' \
		"the DDC grant poll is no longer a plain register read"
	body_require "$edid_body" 'if (saved & SII902X_SYS_CTRL_PWR_DWN) {' \
		"the EDID read does not check the powered-down state"
	body_require "$edid_body" 'return -ENODATA;' \
		"a powered-down transmitter does not skip the EDID read"
fi
guard_line=$(grep -nF 'if (saved & SII902X_SYS_CTRL_PWR_DWN) {' "$sii" |
	head -n 1 | cut -d: -f1 || true)
request_line=$(grep -nF 'value = saved | SII902X_SYS_CTRL_DDC_REQUEST;' "$sii" |
	head -n 1 | cut -d: -f1 || true)
if [ -z "$guard_line" ] || [ -z "$request_line" ] ||
	[ "$guard_line" -ge "$request_line" ]; then
	complain "the powered-down check does not precede the DDC request"
fi

# --- the stage name the timeout line prints ----------------------------------
require "$sii" 'void sm750_sii902x_set_mode_stage(const char *stage)' \
	"the stage setter is missing"
require "$hdr" 'void sm750_sii902x_set_mode_stage(const char *stage);' \
	"the stage setter is not exported"
if [ "$(grep -Fc 'sm750_sii902x_set_mode_stage(' "$drm")" -lt 2 ]; then
	complain "sm750_program_mode does not hand the stage to the SiI9024A path"
fi

[ "$fail" -eq 0 ] || exit 1
if [ "$mode" = single ]; then
	exit 0
fi

# --- planted defects: each must be rejected ----------------------------------
scratch=$(mktemp -d "${TMPDIR}/sm750-sii902x-gate.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

plant_rsen_gate() {
	sed -i 's/plugged = (value & SII902X_PLUGGED_STATUS)/plugged = (value \& SII902X_RX_SENSE_STATUS)/' \
		"$1/sii902x.c"
}
plant_enxio_retry() {
	sed -i 's/if (ret != -ETIMEDOUT)$/if (ret != -ENXIO)/' "$1/sii902x.c"
}
plant_no_bus_clear() {
	sed -i '/^\t\t\tsm750_sw_i2c_recover_bus();$/d' "$1/sii902x.c"
}
plant_retry_on_read() {
	sed -i 's/^\tret = sm750_sw_i2c_read_block(EDID_I2C_ADDR_WRITE, 0, edid,$/&\n\tret = sii902x_write_block_retrying(0x3d, edid, 1, NULL);/' \
		"$1/sii902x.c"
}
plant_abort_on_timeout() {
	awk '
		/^static int sii902x_write_recovering\(/ { in_fn = 1 }
		in_fn && /^\treturn 0;$/ { print "\treturn ret;"; next }
		{ print }' "$1/sii902x.c" >"$1/sii902x.c.new"
	mv "$1/sii902x.c.new" "$1/sii902x.c"
}

control() {
	local name=$1
	local planted=$scratch/src
	local err=$scratch/stderr

	rm -rf "$planted"
	mkdir -p "$planted"
	cp "$sii" "$drm" "$hdr" "$planted/"
	shift
	"$@" "$planted"
	if "$0" --single "$planted" >/dev/null 2>"$err"; then
		complain "negative control $name was not rejected"
	fi
	echo "negative control $name: rejected (exit 1): $(head -n 1 "$err")"
}

control rsen_gate plant_rsen_gate
control enxio_retry plant_enxio_retry
control no_bus_clear plant_no_bus_clear
control retry_on_read plant_retry_on_read
control abort_on_timeout plant_abort_on_timeout

[ "$fail" -eq 0 ] || exit 1
echo "Sii902x readiness and I2C recovery checks passed"
