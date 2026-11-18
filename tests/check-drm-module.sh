#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

module=${1:?usage: check-drm-module.sh MODULE.ko}
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
driver_source=$project_dir/src/sm750_drm.c
device=${SM750_DRM_DEVICE:-/dev/dri/card0}

test -s "$module"
test "$(modinfo -F name "$module")" = sm750hdmidrm
test "$(modinfo -F license "$module")" = "GPL v2"
expected_version=$(sed -n 's/^readonly version=//p' "$project_dir/build-package.sh")
test -n "$expected_version"
test "$(modinfo -F version "$module")" = "$expected_version"
grep -F "#define SM750_DRM_VERSION \"$expected_version\"" "$driver_source" >/dev/null
grep -F 'MODULE_VERSION(SM750_DRM_VERSION)' "$driver_source" >/dev/null
modinfo -F alias "$module" | grep 'v0000126Fd00000750' >/dev/null
modinfo -F description "$module" | grep 'DRM' >/dev/null
modinfo -F parm "$module" | grep '^preferred_width:' >/dev/null
modinfo -F parm "$module" | grep '^preferred_height:' >/dev/null
modinfo -F parm "$module" | grep '^preferred_refresh:' >/dev/null
modinfo -F parm "$module" | grep '^scanout_format:' >/dev/null
modinfo -F parm "$module" | grep '^dither_green_gain:' >/dev/null
for parameter in edid_only softscale_wide sharpen double_shadow \
		disable_hardware_cursor enable_dma disable_dma async_updates; do
	modinfo -F parm "$module" | grep "^${parameter}:" >/dev/null
done
readelf -h "$module" | grep 'ELF64' >/dev/null
if strings "$module" | grep -x 'sm750fb' >/dev/null; then
	echo "DRM module contains the stock module name as an identity." >&2
	exit 1
fi
undefined=$(nm -u "$module")
for symbol in drm_crtc_arm_vblank_event drm_crtc_vblank_get \
		drm_crtc_vblank_off drm_crtc_vblank_on \
		drm_vblank_init; do
	grep -E "[[:space:]]${symbol}$" <<<"$undefined" >/dev/null || {
		echo "DRM module lacks required vblank symbol: $symbol" >&2
		exit 1
	}
done
for symbol in drm_gem_shmem_dumb_create \
		drm_gem_simple_kms_begin_shadow_fb_access \
		drm_gem_simple_kms_end_shadow_fb_access; do
	grep -E "[[:space:]]${symbol}$" <<<"$undefined" >/dev/null || {
		echo "DRM module lacks required RGB565 shadow symbol: $symbol" >&2
		exit 1
	}
done
grep -E '[[:space:]]drm_crtc_handle_vblank$' <<<"$undefined" \
	>/dev/null || {
	echo "DRM module lacks private timer handler." >&2
	exit 1
}
if grep -E '[[:space:]]drm_crtc_vblank_(helper_.*_timer|start_timer|cancel_timer)$' \
		<<<"$undefined" >/dev/null; then
	echo "DRM module uses the core timer with the callback restart race." >&2
	exit 1
fi
for symbol in devm_request_threaded_irq wait_for_completion_timeout; do
	grep -E "[[:space:]]${symbol}$" <<<"$undefined" >/dev/null || {
		echo "DRM module lacks asynchronous DMA symbol: $symbol" >&2
		exit 1
	}
done
# Register-dump facility: a read-only debugfs file, registered from both
# drivers, whose handler must never write to the device.
grep -F 'debugfs_create_file("regs", 0444' "$driver_source" >/dev/null
grep -F 'DEFINE_SHOW_ATTRIBUTE(sm750_regs)' "$driver_source" >/dev/null
grep -F '.debugfs_init = sm750_vram_debugfs_init' "$driver_source" >/dev/null
grep -F '.debugfs_init = sm750_debugfs_init' "$driver_source" >/dev/null
show_body=$(sed -n '/^static int sm750_regs_show/,/^DEFINE_SHOW_ATTRIBUTE(sm750_regs)/p' \
	"$driver_source")
grep -F 'sm750_regs_show' <<<"$show_body" >/dev/null
if grep -E 'writel|poke32|iowrite' <<<"$show_body" >/dev/null; then
	echo "Register dump handler writes to the device; it must stay read-only." >&2
	exit 1
fi
# Live device probe. The vblank ioctl path is the only test that touches the
# DRM device; report a skip with the exact reason when the node is denied
# instead of claiming the path was exercised.
if [[ ! -x $project_dir/tests/check-vblank ]]; then
	echo "SKIP: tests/check-vblank is not built; run make check first. This is not a pass."
elif [[ ! -r $device || ! -w $device ]]; then
	echo "SKIP: cannot open $device read-write as uid $(id -u); grant the video group or run tests/check-vblank $device ${SM750_DRM_EXPECTED_HZ:-60} as root. This is not a pass."
else
	"$project_dir/tests/check-vblank" "$device" "${SM750_DRM_EXPECTED_HZ:-60}"
	echo "DRM vblank ioctl checks passed: $device"
fi
echo "DRM module metadata checks passed: $module"
