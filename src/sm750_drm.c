// SPDX-License-Identifier: GPL-2.0
#include <linux/aperture.h>
#include <linux/completion.h>
#include <linux/crc32.h>
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/fb.h>
#include <linux/hrtimer.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/pm.h>
#include <linux/poll.h>
#include <linux/seq_file.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/sysfs.h>
#include <linux/uaccess.h>
#include <linux/version.h>
#include <linux/wait.h>
#include <linux/workqueue.h>

#ifdef CONFIG_X86
#include <asm/io.h>
#endif

#include <drm/clients/drm_client_setup.h>
#include <drm/drm_atomic.h>
#include <drm/drm_atomic_helper.h>
#include <drm/drm_blend.h>
#include <drm/drm_connector.h>
#include <drm/drm_crtc_helper.h>
#include <drm/drm_damage_helper.h>
#include <drm/drm_debugfs_crc.h>
#include <drm/drm_drv.h>
#include <drm/drm_edid.h>
#include <drm/drm_fbdev_shmem.h>
#include <drm/drm_fbdev_ttm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_framebuffer.h>
#include <drm/drm_gem_atomic_helper.h>
#include <drm/drm_gem_framebuffer_helper.h>
#include <drm/drm_gem_shmem_helper.h>
#include <drm/drm_gem_vram_helper.h>
#include <drm/drm_managed.h>
#include <drm/drm_modeset_helper.h>
#include <drm/drm_plane.h>
#include <drm/drm_probe_helper.h>
#include <drm/drm_print.h>
#include <drm/drm_simple_kms_helper.h>
#include <drm/drm_vblank.h>
#include <drm/drm_vblank_work.h>

#include "ddk750_chip.h"
#include "ddk750_display.h"
#include "ddk750_mode.h"
#include "ddk750_power.h"
#include "ddk750_reg.h"
#include "sii902x.h"
#include "sm750_dither.h"
#include "sm750_drm_mode.h"

/* DRM renamed the atomic transaction object in Linux 7.2. */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 2, 0)
typedef struct drm_atomic_commit sm750_atomic_commit;
#else
typedef struct drm_atomic_state sm750_atomic_commit;
#endif

#define SM750_DRM_NAME "sm750hdmidrm"
/* Keep in step with the package version in build-package.sh and dkms.conf;
 * tests/check-release-version.sh fails when the three disagree. */
#define SM750_DRM_VERSION "0.6.10"
/* modetest reports these as the driver version, so they must track the release
 * number above; tests/check-release-version.sh fails when they drift. */
#define DRIVER_MAJOR 0
#define DRIVER_MINOR 6
#define DRIVER_PATCHLEVEL 10
#define SM750_DRM_MAX_WIDTH 2560
#define SM750_DRM_PHYSICAL_MAX_WIDTH 2048
#define SM750_DRM_PLL PRIMARY_PLL
#define SM750_DRM_CONTROLLER 0
#define SM750_DRM_OUTPUT do_LCD1_PRI
#define SM750_DRM_FB_ADDRESS PANEL_FB_ADDRESS
#define SM750_DRM_FB_ADDRESS_STATUS PANEL_FB_ADDRESS_STATUS
#define SM750_DRM_FB_ADDRESS_MASK PANEL_FB_ADDRESS_ADDRESS_MASK
#define SM750_DRM_FB_WIDTH PANEL_FB_WIDTH
#define SM750_DRM_FB_WIDTH_WIDTH_SHIFT PANEL_FB_WIDTH_WIDTH_SHIFT
#define SM750_DRM_FB_WIDTH_WIDTH_MASK PANEL_FB_WIDTH_WIDTH_MASK
#define SM750_DRM_FB_WIDTH_OFFSET_MASK PANEL_FB_WIDTH_OFFSET_MASK
#define SM750_DRM_DISPLAY_CTRL PANEL_DISPLAY_CTRL
#define SM750_DRM_DISPLAY_CTRL_FORMAT PANEL_DISPLAY_CTRL_FORMAT
#define SM750_DRM_DISPLAY_CTRL_FORMAT_16 PANEL_DISPLAY_CTRL_FORMAT_16
#define SM750_DRM_DISPLAY_CTRL_FORMAT_32 PANEL_DISPLAY_CTRL_FORMAT_32
#define SM750_DRM_CURRENT_LINE PANEL_CURRENT_LINE
#define SM750_DRM_CURRENT_LINE_MASK PANEL_CURRENT_LINE_LINE_MASK
#define SM750_DRM_MAX_HEIGHT 1152
#define SM750_DRM_EDID_SIZE 256
#define SII9024_MAX_CLOCK_KHZ 165000
/* Explicit driver modes include the physically tested 2048x1080@75 timing. */
#define SM750_DRM_MAX_CLOCK_KHZ 179000
#define SM750_DRM_LINE_ALIGN 16
#define SM750_DRM_CURSOR_WIDTH 64
#define SM750_DRM_CURSOR_HEIGHT 64
#define SM750_DRM_CURSOR_STRIDE (SM750_DRM_CURSOR_WIDTH * 2 / 8)
#define SM750_DRM_CURSOR_SIZE \
	(SM750_DRM_CURSOR_STRIDE * SM750_DRM_CURSOR_HEIGHT)
#define SM750_DRM_DMA_BATCH_ROW_SIZE (2048 * sizeof(u16))
#define SM750_DRM_DMA_BATCH_ROWS 128
#define SM750_DRM_DMA_STAGING_SIZE \
	(SM750_DRM_DMA_BATCH_ROWS * SM750_DRM_DMA_BATCH_ROW_SIZE)
#define SM750_DRM_DMA_STAGING_BUFFERS 2
#define SM750_DRM_DMA_TEST_SIZE 256
#define SM750_DRM_DMA_TIMEOUT_US 5000
#define SM750_DRM_FLIP_TIMEOUT_US 50000
#define SM750_DRM_DMA_GUARD_WORDS 4
/*
 * Smallest VRAM the probe accepts: the cursor reserve, the DMA1 test carve
 * with both guards, and one 640x480 XRGB8888 scanout buffer. Below this the
 * test carve in sm750_dma_init() underflows its u32 destination.
 */
#define SM750_DRM_MIN_SCANOUT_WIDTH 640
#define SM750_DRM_MIN_SCANOUT_HEIGHT 480
#define SM750_DRM_MIN_VRAM \
	(SM750_DRM_CURSOR_SIZE + SM750_DRM_DMA_TEST_SIZE + \
	 SM750_DRM_DMA_GUARD_WORDS * sizeof(u32) + \
	 ALIGN(SM750_DRM_MIN_SCANOUT_WIDTH * sizeof(u32), \
	       SM750_DRM_LINE_ALIGN) * SM750_DRM_MIN_SCANOUT_HEIGHT)
#define SM750_DRM_DAMAGE_SPLIT_GAP 64
#define SM750_DRM_MAX_DAMAGE_RECTS 32
/*
 * Analog (EBU/SECAM-style) test-bar colours in 0xRRGGBB order: white,
 * yellow, cyan, green, magenta, red, blue, and a black bar at the right
 * edge. These are the classic 75% EBU bar values, not a display profile.
 */
#define SM750_TEST_WHITE   0xffffff
#define SM750_TEST_YELLOW  0xffff00
#define SM750_TEST_CYAN    0x00ffff
#define SM750_TEST_GREEN   0x00ff00
#define SM750_TEST_MAGENTA 0xff00ff
#define SM750_TEST_RED     0xff0000
#define SM750_TEST_BLUE    0x0000ff
#define SM750_TEST_BLACK   0x000000
#define SM750_TEST_BAR_COUNT 8
#define SM750_TEST_GRAY_STEPS 8
#define SM750_TEST_SWEEP_WIDTH 3
#define SM750_TEST_MIN_WIDTH 320
#define SM750_TEST_MIN_HEIGHT 200
#define SM750_TEST_PERIOD_MIN_MS 500
#define SM750_TEST_PERIOD_MAX_MS 600000
#define SM750_TEST_LINE_BYTES (SM750_DRM_MAX_WIDTH * sizeof(u32))
#define SM750_TEST_ANIM_MIN_MS 10
#define SM750_TEST_ANIM_MAX_MS 1000
#define SM750_TEST_DISC_PERCENT 3
#define SM750_TEST_DISC_MIN_RADIUS 24
#define SM750_TEST_DISC_MAX_RADIUS 64
#define SM750_TEST_DISC_SPEED_X 3
#define SM750_TEST_DISC_SPEED_Y 2
#define SM750_DRM_MAX_ROW_RUNS 8
#define SM750_DRM_DENSE_RUN_NUMERATOR 3
#define SM750_DRM_DENSE_RUN_DENOMINATOR 4
#define SM750_DRM_SHARPEN_PERCENT 8
#define SM750_DRM_HWC_ADDRESS PANEL_HWC_ADDRESS
#define SM750_DRM_HWC_ADDRESS_ENABLE PANEL_HWC_ADDRESS_ENABLE
#define SM750_DRM_HWC_ADDRESS_MASK PANEL_HWC_ADDRESS_ADDRESS_MASK
#define SM750_DRM_HWC_LOCATION PANEL_HWC_LOCATION
#define SM750_DRM_HWC_LOCATION_TOP PANEL_HWC_LOCATION_TOP
#define SM750_DRM_HWC_LOCATION_LEFT PANEL_HWC_LOCATION_LEFT
#define SM750_DRM_HWC_LOCATION_Y_MASK PANEL_HWC_LOCATION_Y_MASK
#define SM750_DRM_HWC_LOCATION_X_MASK PANEL_HWC_LOCATION_X_MASK
#define SM750_DRM_HWC_COLOR_12 PANEL_HWC_COLOR_12
#define SM750_DRM_HWC_COLOR_3 PANEL_HWC_COLOR_3
#define SM750_VBLANK_RETRY_NS NSEC_PER_MSEC
#define SM750_VBLANK_MIN_DELAY_NS 50000ULL

void __iomem *mmio750;
bool sm750_test_reduced_pll_ratio;
bool sm750_test_low_vco_pll;
int sm750_test_panel_fifo = -1;
int sm750_test_refresh_centihz;

static int dvo_clock_phase = -1;
module_param(dvo_clock_phase, int, 0444);
MODULE_PARM_DESC(dvo_clock_phase,
	"DVO clock phase: -1=board option-ROM strap, 0=rising, 1=falling");

static int sii9024_scl = 12;
static int sii9024_sda = 13;
module_param(sii9024_scl, int, 0444);
module_param(sii9024_sda, int, 0444);
MODULE_PARM_DESC(sii9024_scl, "SiI9024A software-I2C SCL GPIO");
MODULE_PARM_DESC(sii9024_sda, "SiI9024A software-I2C SDA GPIO");

static unsigned int preferred_width;
static unsigned int preferred_height;
static unsigned int preferred_refresh;
module_param(preferred_width, uint, 0444);
module_param(preferred_height, uint, 0444);
module_param(preferred_refresh, uint, 0444);
MODULE_PARM_DESC(preferred_width, "Optional preferred mode width in pixels");
MODULE_PARM_DESC(preferred_height, "Optional preferred mode height in lines");
MODULE_PARM_DESC(preferred_refresh, "Optional preferred mode refresh in Hz");

#ifdef SM750_DRM_DEFAULT_XRGB8888
#define SM750_DRM_DEFAULT_SCANOUT_FORMAT "xrgb8888"
#elif defined(SM750_DRM_DEFAULT_RGB565)
#define SM750_DRM_DEFAULT_SCANOUT_FORMAT "rgb565"
#else
#define SM750_DRM_DEFAULT_SCANOUT_FORMAT "rgb565-bbdither"
#endif

#ifndef SM750_DRM_DEFAULT_EDID_ONLY
#define SM750_DRM_DEFAULT_EDID_ONLY 1
#endif
#ifndef SM750_DRM_DEFAULT_SOFTSCALE_WIDE
#define SM750_DRM_DEFAULT_SOFTSCALE_WIDE 0
#endif
#ifndef SM750_DRM_DEFAULT_SHARPEN
#define SM750_DRM_DEFAULT_SHARPEN 0
#endif
#ifndef SM750_DRM_DEFAULT_DOUBLE_SHADOW
#define SM750_DRM_DEFAULT_DOUBLE_SHADOW 0
#endif
#ifndef SM750_DRM_DEFAULT_DISABLE_HARDWARE_CURSOR
#define SM750_DRM_DEFAULT_DISABLE_HARDWARE_CURSOR 0
#endif
#ifndef SM750_DRM_DEFAULT_ENABLE_DMA
#define SM750_DRM_DEFAULT_ENABLE_DMA 1
#endif
#ifndef SM750_DRM_DEFAULT_ASYNC_UPDATES
#define SM750_DRM_DEFAULT_ASYNC_UPDATES 1
#endif

static char *scanout_format = SM750_DRM_DEFAULT_SCANOUT_FORMAT;
static unsigned int dither_green_gain = 94;
static bool edid_only = SM750_DRM_DEFAULT_EDID_ONLY;
static bool softscale_wide = SM750_DRM_DEFAULT_SOFTSCALE_WIDE;
static bool sharpen = SM750_DRM_DEFAULT_SHARPEN;
static bool double_shadow = SM750_DRM_DEFAULT_DOUBLE_SHADOW;
static bool disable_hardware_cursor =
	SM750_DRM_DEFAULT_DISABLE_HARDWARE_CURSOR;
static bool enable_dma = SM750_DRM_DEFAULT_ENABLE_DMA;
static bool disable_dma;
static bool async_updates = SM750_DRM_DEFAULT_ASYNC_UPDATES;
static bool backbuffer_staging = true;
static unsigned int dma_batch_rows = 16;
static bool staging_timing;
static unsigned int shadow_dma_min_bytes = 4096;
static unsigned int crc_window_bytes = 262144;
static char *test_pattern = "auto";
static unsigned int test_pattern_period_ms = 5000;
static unsigned int test_pattern_anim_ms = 40;
module_param(scanout_format, charp, 0444);
module_param(dither_green_gain, uint, 0444);
module_param(edid_only, bool, 0444);
module_param(softscale_wide, bool, 0444);
module_param(sharpen, bool, 0444);
module_param(double_shadow, bool, 0444);
module_param(disable_hardware_cursor, bool, 0444);
module_param(enable_dma, bool, 0444);
module_param(disable_dma, bool, 0444);
module_param(async_updates, bool, 0444);
module_param(backbuffer_staging, bool, 0444);
module_param(dma_batch_rows, uint, 0644);
module_param(staging_timing, bool, 0644);
MODULE_PARM_DESC(dma_batch_rows,
	"DMA batch rows, sampled per update and clamped to 1-128 (default 16)");
MODULE_PARM_DESC(staging_timing,
	"Log complete-frame upload and presentation timing for benchmarking");
module_param(shadow_dma_min_bytes, uint, 0444);
/* Writable so a full frame can be read back; the reader clamps to the
 * visible scanout area, so a larger value is bounded by the geometry. */
module_param(crc_window_bytes, uint, 0644);
MODULE_PARM_DESC(scanout_format,
	"Scanout backend: xrgb8888, rgb565, or rgb565-bbdither");
MODULE_PARM_DESC(dither_green_gain,
	"RGB565 bbdither green gain percentage (0-100, default 94)");
MODULE_PARM_DESC(edid_only, "Expose EDID modes instead of the driver catalogue");
MODULE_PARM_DESC(softscale_wide,
	"Enable logical 2464/2560x1080 modes when edid_only=0");
MODULE_PARM_DESC(sharpen, "Enable fixed 8% post-softscale sharpening");
MODULE_PARM_DESC(double_shadow,
	"Enable source snapshots and difference-based damage trimming");
MODULE_PARM_DESC(disable_hardware_cursor,
	"Disable the hardware cursor plane and use software cursor rendering");
MODULE_PARM_DESC(enable_dma,
	"Enable optimized eight-row DMA1 shadow uploads (default enabled)");
MODULE_PARM_DESC(disable_dma,
	"Deprecated DMA safety veto; overrides enable_dma=1");
MODULE_PARM_DESC(async_updates,
	"Coalesce shadow damage on a dedicated worker (default enabled)");
MODULE_PARM_DESC(backbuffer_staging,
	"Stage complete shadow frames off-screen and present them at vblank");
MODULE_PARM_DESC(shadow_dma_min_bytes,
	"Minimum aligned shadow span for DMA (default 4096 bytes)");
MODULE_PARM_DESC(crc_window_bytes,
	"Bytes of the visible scanout region read per CRC (default 262144, minimum 4096, clamped to the visible frame; writable at runtime)");
/* Defect A65 teardown marks; see docs/evidence/runtime/
 * 51-a65-teardown-trace.txt. Default off, writes no state. */
static bool a65_trace;
module_param(a65_trace, bool, 0644);
MODULE_PARM_DESC(a65_trace,
	"Print A65: <step> marks while the driver tears down (defect A65)");
module_param(test_pattern, charp, 0644);
module_param(test_pattern_period_ms, uint, 0644);
module_param(test_pattern_anim_ms, uint, 0644);
MODULE_PARM_DESC(test_pattern,
	"Test card fallback when no client paints: off, auto (default), or always");
MODULE_PARM_DESC(test_pattern_period_ms,
	"Milliseconds between test-card palette rotations, 0 keeps it static (default 5000, clamped to 500-600000)");
MODULE_PARM_DESC(test_pattern_anim_ms,
	"Milliseconds between test-card animation ticks, 0 disables it (default 40, clamped to 10-1000)");

/*
 * Stages of sm750_program_mode(), in call order. mode_stage holds the last
 * stage entered, so the pipe-enable error path can name the call that failed
 * and a dmesg reader can map the name back to the call site.
 */
enum sm750_mode_stage {
	SM750_MODE_STAGE_NONE,		/* failed before or outside program_mode */
	SM750_MODE_STAGE_SII_BEGIN,	/* before sm750_sii902x_begin_mode() */
	SM750_MODE_STAGE_DISPLAY_CTRL,	/* before ddk750_set_display_control() */
	SM750_MODE_STAGE_TIMING,	/* before ddk750_set_mode_timing() */
	SM750_MODE_STAGE_LOGICAL_OUT,	/* before ddk750_set_logical_disp_out() */
	SM750_MODE_STAGE_SII_ENABLE,	/* before sm750_sii902x_enable() */
};

static const char *const sm750_mode_stage_names[] = {
	[SM750_MODE_STAGE_NONE] = "none",
	[SM750_MODE_STAGE_SII_BEGIN] = "sii902x_begin_mode",
	[SM750_MODE_STAGE_DISPLAY_CTRL] = "ddk750_set_display_control",
	[SM750_MODE_STAGE_TIMING] = "ddk750_set_mode_timing",
	[SM750_MODE_STAGE_LOGICAL_OUT] = "ddk750_set_logical_disp_out",
	[SM750_MODE_STAGE_SII_ENABLE] = "sii902x_enable",
};

static const char *sm750_mode_stage_name(enum sm750_mode_stage stage)
{
	if ((unsigned int)stage >= ARRAY_SIZE(sm750_mode_stage_names))
		return "unknown";
	return sm750_mode_stage_names[stage];
}


/*
 * test_pattern is a writable charp: a root write can replace and free the
 * string while a commit reads it. Parse it once at probe and let the commit
 * path read only this enum. An unknown value keeps the historical behaviour
 * of "off" (never paint) without failing probe.
 */
enum sm750_test_pattern_mode {
	SM750_TEST_PATTERN_OFF,
	SM750_TEST_PATTERN_AUTO,
	SM750_TEST_PATTERN_ALWAYS,
};

static const char *const sm750_test_pattern_names[] = {
	[SM750_TEST_PATTERN_OFF] = "off",
	[SM750_TEST_PATTERN_AUTO] = "auto",
	[SM750_TEST_PATTERN_ALWAYS] = "always",
};

static enum sm750_test_pattern_mode
sm750_test_pattern_parse(const char *value)
{
	if (!strcmp(value, "always"))
		return SM750_TEST_PATTERN_ALWAYS;
	if (!strcmp(value, "auto"))
		return SM750_TEST_PATTERN_AUTO;
	return SM750_TEST_PATTERN_OFF;
}

/*
 * Lock invariants: shadow_lock nests before mode_lock (sm750_shadow_rect()
 * reaches sm750_present_staged_frame(), which takes mode_lock), and mode_lock
 * must never wrap sm750_crc_*() or the shadow paths, because crc_mutex and
 * shadow_lock already nest before mode_lock. A reverse edge deadlocks.
 */
struct sm750_drm_device {
	struct drm_device drm;
	struct pci_dev *pdev;
	struct drm_simple_display_pipe pipe;
	struct drm_plane cursor_plane;
	struct drm_connector connector;
	struct mutex mode_lock;
	struct mutex shadow_lock;
	struct mutex cursor_lock;
	struct mutex async_lock;
	struct workqueue_struct *shadow_workqueue;
	struct work_struct shadow_work;
	struct hrtimer vblank_timer;
	spinlock_t vblank_lock;
	struct drm_vblank_work crc_work;
	void __iomem *regs;
	void __iomem *vram;
	resource_size_t vram_base;
	u32 vram_size;
	u32 scanout_pitch;
	u32 softscale_source_width;
	struct sm750_dither *dither;
	struct sm750_dither_scale_map *dither_scale_map;
	u32 *dither_source_line;
	u32 *shadow_source_snapshot;
	u32 *async_source;
	u16 *rgb565_scanout_snapshot;
	u32 *softscale_output_line;
	u32 *xrgb_output_line;
	u32 *cursor_source;
	u8 *cursor_image;
	u32 *test_pattern_line;
	u32 *test_pattern_half;
	struct delayed_work test_pattern_work;
	u32 test_pattern_phase;
	u32 test_pattern_width;
	u32 test_pattern_height;
	u32 test_pattern_ticks;
	int test_pattern_disc_x;
	int test_pattern_disc_y;
	int test_pattern_disc_dx;
	int test_pattern_disc_dy;
	u32 test_pattern_disc_colour;
	void *dma_staging[SM750_DRM_DMA_STAGING_BUFFERS];
	dma_addr_t dma_staging_address[SM750_DRM_DMA_STAGING_BUFFERS];
	struct completion dma_completion;
	u16 *dither_output_line;
	u32 cursor_offset;
	u32 cursor_encoded_width;
	u32 dma_master_base[SM750_DRM_DMA_STAGING_BUFFERS];
	u32 dma_source_address[SM750_DRM_DMA_STAGING_BUFFERS];
	u32 dma_pending_destination;
	size_t dma_pending_size;
	u32 dma_active_destination;
	size_t dma_active_size;
	size_t dma_batch_limit;
	u64 staging_started_ns;
	u32 staging_batches;
	u64 staging_bytes;
	unsigned int staging_rows;
	bool staging_measure;
	u32 shadow_upload_offset;
	u32 scanout_offset;
	u32 backbuffer_offset;
	u32 scanout_frame_size;
	unsigned int dma_fill_index;
	unsigned int dma_active_index;
	struct drm_rect async_damage[SM750_DRM_MAX_DAMAGE_RECTS];
	unsigned int async_damage_count;
	u32 shadow_source_width;
	u32 shadow_source_height;
	u32 shadow_source_pitch;
	u32 disconnected_width;
	u32 disconnected_height;
	u32 disconnected_refresh;
	u32 hotplug_preferred_width;
	u32 hotplug_preferred_height;
	u32 hotplug_preferred_refresh;
	u8 connected_edid[SM750_DRM_EDID_SIZE];
	u64 vblank_line_ns;
	u64 vblank_frame_ns;
	u16 vblank_start;
	u16 vblank_vtotal;
	bool vblank_timer_enabled;
	bool crc_enabled;
	bool crc_warned;
	bool crc_vblank;
	struct mutex crc_mutex;
	enum sm750_mode_stage mode_stage;
	bool enable_failed;
	bool phase_falling;
	bool shadow_scanout;
	bool rgb565;
	bool bbdither;
	bool softscale_active;
	bool shadow_source_snapshot_valid;
	bool rgb565_scanout_snapshot_valid;
	bool test_pattern_active;
	enum sm750_test_pattern_mode test_pattern_mode;
	bool hardware_cursor;
	bool cursor_image_valid;
	bool shadow_dma_enabled;
	bool shadow_dma_broken;
	bool dma_irq_enabled;
	bool dma_irq_armed;
	bool dma_active;
	bool backbuffer_available;
	bool backbuffer_ready;
	bool backbuffer_mirror;
	u32 dma_irq_mask_saved;
	bool shadow_write_pending;
	bool async_source_valid;
	bool async_stopping;
	bool connected_edid_valid;
	bool monitor_disconnected;
	bool disconnected_mode_valid;
	bool hotplug_preferred_valid;
};

#define to_sm750_drm(drm_dev) container_of(drm_dev, struct sm750_drm_device, drm)
#define connector_to_sm750(conn) \
	container_of(conn, struct sm750_drm_device, connector)
#define pipe_to_sm750(display_pipe) \
	container_of(display_pipe, struct sm750_drm_device, pipe)

static enum drm_mode_status
sm750_mode_valid(const struct drm_display_mode *mode, u32 vram_size);

/*
 * Use our timer on every supported kernel. The DRM core timer restart helper
 * can wait for a callback while holding vblank_time_lock, which that callback
 * needs. Never wait for a callback in the DRM enable/disable hooks, and never
 * hold vblank_lock while calling back into DRM.
 */
static u64 sm750_vblank_first_delay_locked(struct sm750_drm_device *sdev)
{
	u32 line;
	u64 lines;

	if (!(peek32(SM750_DRM_DISPLAY_CTRL) & DISPLAY_CTRL_TIMING) ||
	    !sdev->vblank_line_ns || !sdev->vblank_vtotal)
		return SM750_VBLANK_RETRY_NS;

	line = peek32(SM750_DRM_CURRENT_LINE) & SM750_DRM_CURRENT_LINE_MASK;
	if (line >= sdev->vblank_vtotal)
		return SM750_VBLANK_RETRY_NS;

	if (line < sdev->vblank_start)
		lines = sdev->vblank_start - line;
	else
		lines = sdev->vblank_vtotal - line +
			sdev->vblank_start;

	return max_t(u64, lines * sdev->vblank_line_ns,
		     SM750_VBLANK_MIN_DELAY_NS);
}

static enum hrtimer_restart sm750_vblank_timer_fn(struct hrtimer *timer)
{
	struct sm750_drm_device *sdev =
		container_of(timer, struct sm750_drm_device, vblank_timer);
	unsigned long flags;

	spin_lock_irqsave(&sdev->vblank_lock, flags);
	if (!sdev->vblank_timer_enabled) {
		spin_unlock_irqrestore(&sdev->vblank_lock, flags);
		return HRTIMER_NORESTART;
	}
	/* A disable/re-enable may have already armed the next invocation. */
	if (hrtimer_is_queued(timer)) {
		spin_unlock_irqrestore(&sdev->vblank_lock, flags);
		return HRTIMER_NORESTART;
	}
	hrtimer_forward_now(timer, ns_to_ktime(sdev->vblank_frame_ns));
	spin_unlock_irqrestore(&sdev->vblank_lock, flags);

	drm_crtc_handle_vblank(&sdev->pipe.crtc);
	return HRTIMER_RESTART;
}

static void sm750_vblank_timer_stop(struct sm750_drm_device *sdev,
				    bool wait)
{
	unsigned long flags;

	spin_lock_irqsave(&sdev->vblank_lock, flags);
	sdev->vblank_timer_enabled = false;
	/* Serialize cancellation with enable so it cannot cancel a newer arm. */
	hrtimer_try_to_cancel(&sdev->vblank_timer);
	spin_unlock_irqrestore(&sdev->vblank_lock, flags);
	/* Only teardown callers, after releasing DRM locks, may wait. */
	if (wait)
		hrtimer_cancel(&sdev->vblank_timer);
}

static const struct drm_display_mode sm750_standard_modes[] = {
	/* VESA CVT-RBv2: 59.94, 60, 70, 72 and 75 Hz. */
	{ DRM_MODE("640x480", DRM_MODE_TYPE_DRIVER, 21362,
		640, 648, 680, 720, 0, 480, 481, 489, 495, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("640x480", DRM_MODE_TYPE_DRIVER, 21384,
		640, 648, 680, 720, 0, 480, 481, 489, 495, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("640x480", DRM_MODE_TYPE_DRIVER, 24998,
		640, 648, 680, 720, 0, 480, 482, 490, 496, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("640x480", DRM_MODE_TYPE_DRIVER, 25764,
		640, 648, 680, 720, 0, 480, 483, 491, 497, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("640x480", DRM_MODE_TYPE_DRIVER, 26892,
		640, 648, 680, 720, 0, 480, 484, 492, 498, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("800x600", DRM_MODE_TYPE_DRIVER, 32597,
		800, 808, 840, 880, 0, 600, 604, 612, 618, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("800x600", DRM_MODE_TYPE_DRIVER, 32630,
		800, 808, 840, 880, 0, 600, 604, 612, 618, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("800x600", DRM_MODE_TYPE_DRIVER, 38192,
		800, 808, 840, 880, 0, 600, 606, 614, 620, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("800x600", DRM_MODE_TYPE_DRIVER, 39346,
		800, 808, 840, 880, 0, 600, 607, 615, 621, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("800x600", DRM_MODE_TYPE_DRIVER, 41052,
		800, 808, 840, 880, 0, 600, 608, 616, 622, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1024x768", DRM_MODE_TYPE_DRIVER, 52277,
		1024, 1032, 1064, 1104, 0, 768, 776, 784, 790, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1024x768", DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED,
		52329, 1024, 1032, 1064, 1104, 0, 768, 776, 784, 790, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1024x768", DRM_MODE_TYPE_DRIVER, 61360,
		1024, 1032, 1064, 1104, 0, 768, 780, 788, 794, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1024x768", DRM_MODE_TYPE_DRIVER, 63192,
		1024, 1032, 1064, 1104, 0, 768, 781, 789, 795, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1024x768", DRM_MODE_TYPE_DRIVER, 65908,
		1024, 1032, 1064, 1104, 0, 768, 782, 790, 796, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1152x864", DRM_MODE_TYPE_DRIVER, 65649,
		1152, 1160, 1192, 1232, 0, 864, 875, 883, 889, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1152x864", DRM_MODE_TYPE_DRIVER, 65714,
		1152, 1160, 1192, 1232, 0, 864, 875, 883, 889, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1152x864", DRM_MODE_TYPE_DRIVER, 77012,
		1152, 1160, 1192, 1232, 0, 864, 879, 887, 893, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1152x864", DRM_MODE_TYPE_DRIVER, 79301,
		1152, 1160, 1192, 1232, 0, 864, 880, 888, 894, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1152x864", DRM_MODE_TYPE_DRIVER, 82697,
		1152, 1160, 1192, 1232, 0, 864, 881, 889, 895, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x720", DRM_MODE_TYPE_DRIVER, 60405,
		1280, 1288, 1320, 1360, 0, 720, 727, 735, 741, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x720", DRM_MODE_TYPE_DRIVER, 60465,
		1280, 1288, 1320, 1360, 0, 720, 727, 735, 741, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x720", DRM_MODE_TYPE_DRIVER, 70828,
		1280, 1288, 1320, 1360, 0, 720, 730, 738, 744, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x720", DRM_MODE_TYPE_DRIVER, 72950,
		1280, 1288, 1320, 1360, 0, 720, 731, 739, 745, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x720", DRM_MODE_TYPE_DRIVER, 76092,
		1280, 1288, 1320, 1360, 0, 720, 732, 740, 746, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x800", DRM_MODE_TYPE_DRIVER, 67089,
		1280, 1288, 1320, 1360, 0, 800, 809, 817, 823, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x800", DRM_MODE_TYPE_DRIVER, 67156,
		1280, 1288, 1320, 1360, 0, 800, 809, 817, 823, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x800", DRM_MODE_TYPE_DRIVER, 78730,
		1280, 1288, 1320, 1360, 0, 800, 813, 821, 827, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x800", DRM_MODE_TYPE_DRIVER, 81077,
		1280, 1288, 1320, 1360, 0, 800, 814, 822, 828, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x800", DRM_MODE_TYPE_DRIVER, 84558,
		1280, 1288, 1320, 1360, 0, 800, 815, 823, 829, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x1024", DRM_MODE_TYPE_DRIVER, 85920,
		1280, 1288, 1320, 1360, 0, 1024, 1040, 1048, 1054, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x1024", DRM_MODE_TYPE_DRIVER, 86006,
		1280, 1288, 1320, 1360, 0, 1024, 1040, 1048, 1054, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x1024", DRM_MODE_TYPE_DRIVER, 100816,
		1280, 1288, 1320, 1360, 0, 1024, 1045, 1053, 1059, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x1024", DRM_MODE_TYPE_DRIVER, 103795,
		1280, 1288, 1320, 1360, 0, 1024, 1046, 1054, 1060, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1280x1024", DRM_MODE_TYPE_DRIVER, 108221,
		1280, 1288, 1320, 1360, 0, 1024, 1047, 1055, 1061, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1366x768", DRM_MODE_TYPE_DRIVER, 68471,
		1366, 1374, 1406, 1446, 0, 768, 776, 784, 790, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1366x768", DRM_MODE_TYPE_DRIVER, 68540,
		1366, 1374, 1406, 1446, 0, 768, 776, 784, 790, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1366x768", DRM_MODE_TYPE_DRIVER, 80368,
		1366, 1374, 1406, 1446, 0, 768, 780, 788, 794, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1366x768", DRM_MODE_TYPE_DRIVER, 82769,
		1366, 1374, 1406, 1446, 0, 768, 781, 789, 795, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1366x768", DRM_MODE_TYPE_DRIVER, 86326,
		1366, 1374, 1406, 1446, 0, 768, 782, 790, 796, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1600x900", DRM_MODE_TYPE_DRIVER, 93247,
		1600, 1608, 1640, 1680, 0, 900, 912, 920, 926, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1600x900", DRM_MODE_TYPE_DRIVER, 93340,
		1600, 1608, 1640, 1680, 0, 900, 912, 920, 926, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1600x900", DRM_MODE_TYPE_DRIVER, 109367,
		1600, 1608, 1640, 1680, 0, 900, 916, 924, 930, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1600x900", DRM_MODE_TYPE_DRIVER, 112613,
		1600, 1608, 1640, 1680, 0, 900, 917, 925, 931, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1600x900", DRM_MODE_TYPE_DRIVER, 117558,
		1600, 1608, 1640, 1680, 0, 900, 919, 927, 933, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1680x1050", DRM_MODE_TYPE_DRIVER, 113934,
		1680, 1688, 1720, 1760, 0, 1050, 1066, 1074, 1080, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1680x1050", DRM_MODE_TYPE_DRIVER, 114048,
		1680, 1688, 1720, 1760, 0, 1050, 1066, 1074, 1080, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1680x1050", DRM_MODE_TYPE_DRIVER, 133672,
		1680, 1688, 1720, 1760, 0, 1050, 1071, 1079, 1085, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1680x1050", DRM_MODE_TYPE_DRIVER, 137617,
		1680, 1688, 1720, 1760, 0, 1050, 1072, 1080, 1086, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1680x1050", DRM_MODE_TYPE_DRIVER, 143616,
		1680, 1688, 1720, 1760, 0, 1050, 1074, 1082, 1088, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
};

static const struct drm_display_mode sm750_custom_modes[] = {
	/* 2048x1080 CVT-RBv2 timings explicitly enabled by driver policy. */
	{ DRM_MODE("2048x1080", DRM_MODE_TYPE_DRIVER, 118210,
		2048, 2056, 2088, 2128, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1080", DRM_MODE_TYPE_DRIVER, 141710,
		2048, 2056, 2088, 2128, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1080", DRM_MODE_TYPE_DRIVER, 141852,
		2048, 2056, 2088, 2128, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1080", DRM_MODE_TYPE_DRIVER, 166239,
		2048, 2056, 2088, 2128, 0, 1080, 1102, 1110, 1116, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1080", DRM_MODE_TYPE_DRIVER, 171142,
		2048, 2056, 2088, 2128, 0, 1080, 1103, 1111, 1117, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1080", DRM_MODE_TYPE_DRIVER, 178592,
		2048, 2056, 2088, 2128, 0, 1080, 1105, 1113, 1119, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	/* CTA-861 50/59.94/60 Hz, then VESA CVT-RBv2. */
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 148500,
		1920, 2448, 2492, 2640, 0, 1080, 1084, 1089, 1125, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_PVSYNC) },
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 148352,
		1920, 2008, 2052, 2200, 0, 1080, 1084, 1089, 1125, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_PVSYNC) },
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 148500,
		1920, 2008, 2052, 2200, 0, 1080, 1084, 1089, 1125, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_PVSYNC) },
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 156240,
		1920, 1928, 1960, 2000, 0, 1080, 1102, 1110, 1116, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 160848,
		1920, 1928, 1960, 2000, 0, 1080, 1103, 1111, 1117, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1920x810", DRM_MODE_TYPE_DRIVER, 99860,
		1920, 1928, 1960, 2000, 0, 810, 819, 827, 833, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1920x810", DRM_MODE_TYPE_DRIVER, 99959,
		1920, 1928, 1960, 2000, 0, 810, 819, 827, 833, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1920x810", DRM_MODE_TYPE_DRIVER, 117180,
		1920, 1928, 1960, 2000, 0, 810, 823, 831, 837, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1920x810", DRM_MODE_TYPE_DRIVER, 120672,
		1920, 1928, 1960, 2000, 0, 810, 824, 832, 838, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("1920x810", DRM_MODE_TYPE_DRIVER, 125849,
		1920, 1928, 1960, 2000, 0, 810, 825, 833, 839, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x864", DRM_MODE_TYPE_DRIVER, 113394,
		2048, 2056, 2088, 2128, 0, 864, 875, 883, 889, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x864", DRM_MODE_TYPE_DRIVER, 113507,
		2048, 2056, 2088, 2128, 0, 864, 875, 883, 889, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x864", DRM_MODE_TYPE_DRIVER, 133021,
		2048, 2056, 2088, 2128, 0, 864, 879, 887, 893, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x864", DRM_MODE_TYPE_DRIVER, 136975,
		2048, 2056, 2088, 2128, 0, 864, 880, 888, 894, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x864", DRM_MODE_TYPE_DRIVER, 142842,
		2048, 2056, 2088, 2128, 0, 864, 881, 889, 895, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1024", DRM_MODE_TYPE_DRIVER, 134440,
		2048, 2056, 2088, 2128, 0, 1024, 1040, 1048, 1054, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1024", DRM_MODE_TYPE_DRIVER, 134574,
		2048, 2056, 2088, 2128, 0, 1024, 1040, 1048, 1054, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1024", DRM_MODE_TYPE_DRIVER, 157748,
		2048, 2056, 2088, 2128, 0, 1024, 1045, 1053, 1059, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1024", DRM_MODE_TYPE_DRIVER, 162408,
		2048, 2056, 2088, 2128, 0, 1024, 1046, 1054, 1060, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1152", DRM_MODE_TYPE_DRIVER, 151149,
		2048, 2056, 2088, 2128, 0, 1152, 1171, 1179, 1185, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2048x1152", DRM_MODE_TYPE_DRIVER, 151300,
		2048, 2056, 2088, 2128, 0, 1152, 1171, 1179, 1185, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
};

static const struct drm_display_mode sm750_safe_1920_modes[] = {
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 148500,
		1920, 2448, 2492, 2640, 0, 1080, 1084, 1089, 1125, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_PVSYNC) },
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 148352,
		1920, 2008, 2052, 2200, 0, 1080, 1084, 1089, 1125, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_PVSYNC) },
	{ DRM_MODE("1920x1080", DRM_MODE_TYPE_DRIVER, 148500,
		1920, 2008, 2052, 2200, 0, 1080, 1084, 1089, 1125, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_PVSYNC) },
};

static const struct drm_display_mode sm750_wide_modes[] = {
	/* Logical modes; hardware output is substituted with 2048x1080. */
	{ DRM_MODE("2464x1080", DRM_MODE_TYPE_DRIVER, 145763,
		2464, 2512, 2544, 2624, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2464x1080", DRM_MODE_TYPE_DRIVER, 174741,
		2464, 2512, 2544, 2624, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2464x1080", DRM_MODE_TYPE_DRIVER, 174915,
		2464, 2512, 2544, 2624, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2464x1080", DRM_MODE_TYPE_DRIVER, 204986,
		2464, 2512, 2544, 2624, 0, 1080, 1102, 1110, 1116, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2464x1080", DRM_MODE_TYPE_DRIVER, 211032,
		2464, 2512, 2544, 2624, 0, 1080, 1103, 1111, 1117, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2464x1080", DRM_MODE_TYPE_DRIVER, 220219,
		2464, 2512, 2544, 2624, 0, 1080, 1105, 1113, 1119, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2560x1080", DRM_MODE_TYPE_DRIVER, 151096,
		2560, 2608, 2640, 2720, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2560x1080", DRM_MODE_TYPE_DRIVER, 181134,
		2560, 2608, 2640, 2720, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2560x1080", DRM_MODE_TYPE_DRIVER, 181315,
		2560, 2608, 2640, 2720, 0, 1080, 1097, 1105, 1111, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2560x1080", DRM_MODE_TYPE_DRIVER, 212486,
		2560, 2608, 2640, 2720, 0, 1080, 1102, 1110, 1116, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2560x1080", DRM_MODE_TYPE_DRIVER, 218753,
		2560, 2608, 2640, 2720, 0, 1080, 1103, 1111, 1117, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
	{ DRM_MODE("2560x1080", DRM_MODE_TYPE_DRIVER, 228275,
		2560, 2608, 2640, 2720, 0, 1080, 1105, 1113, 1119, 0,
		DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) },
};

static bool sm750_mode_is_softscaled(const struct drm_display_mode *mode)
{
	return !edid_only && softscale_wide &&
		(mode->hdisplay == 2464 || mode->hdisplay == 2560) &&
		mode->vdisplay == 1080 &&
		(drm_mode_vrefresh(mode) == 50 ||
		 drm_mode_vrefresh(mode) == 60 ||
		 drm_mode_vrefresh(mode) == 70 ||
		 drm_mode_vrefresh(mode) == 72 ||
		 drm_mode_vrefresh(mode) == 75);
}

static int sm750_softscale_output_mode(const struct drm_display_mode *logical,
				       struct drm_display_mode *output)
{
	unsigned int refresh;

	*output = *logical;
	if (!sm750_mode_is_softscaled(logical))
		return 0;

	refresh = drm_mode_vrefresh(logical);
	output->hdisplay = 2048;
	output->hsync_start = 2056;
	output->hsync_end = 2088;
	output->htotal = 2128;
	if (refresh == 50) {
		output->clock = 118210;
		output->vsync_start = 1097;
		output->vsync_end = 1105;
		output->vtotal = 1111;
	} else if (logical->clock == 174741 || logical->clock == 181134) {
		output->clock = 141710;
		output->vsync_start = 1097;
		output->vsync_end = 1105;
		output->vtotal = 1111;
	} else if (refresh == 60) {
		output->clock = 141852;
		output->vsync_start = 1097;
		output->vsync_end = 1105;
		output->vtotal = 1111;
	} else if (refresh == 70) {
		output->clock = 166239;
		output->vsync_start = 1102;
		output->vsync_end = 1110;
		output->vtotal = 1116;
	} else if (refresh == 72) {
		output->clock = 171142;
		output->vsync_start = 1103;
		output->vsync_end = 1111;
		output->vtotal = 1117;
	} else if (refresh == 75) {
		output->clock = 178592;
		output->vsync_start = 1105;
		output->vsync_end = 1113;
		output->vtotal = 1119;
	} else {
		return -EINVAL;
	}
	drm_mode_set_name(output);
	return 1;
}

static int sm750_add_modes(struct drm_connector *connector,
			   const struct drm_display_mode *modes,
			   size_t count, bool clear_preferred)
{
	struct drm_display_mode *mode;
	size_t i;
	int added = 0;

	for (i = 0; i < count; i++) {
		mode = drm_mode_duplicate(connector->dev, &modes[i]);
		if (!mode)
			continue;
		if (clear_preferred)
			mode->type &= ~DRM_MODE_TYPE_PREFERRED;
		drm_mode_set_name(mode);
		drm_mode_probed_add(connector, mode);
		added++;
	}

	return added;
}

static bool sm750_mark_preferred_mode(struct drm_connector *connector,
				      unsigned int width,
				      unsigned int height,
				      unsigned int refresh,
				      const char *source)
{
	struct drm_display_mode *mode;
	struct drm_display_mode *preferred = NULL;

	list_for_each_entry(mode, &connector->probed_modes, head) {
		if (mode->hdisplay == width && mode->vdisplay == height &&
		    drm_mode_vrefresh(mode) == refresh)
			preferred = mode;
	}
	if (!preferred)
		return false;

	list_for_each_entry(mode, &connector->probed_modes, head)
		mode->type &= ~DRM_MODE_TYPE_PREFERRED;
	preferred->type |= DRM_MODE_TYPE_PREFERRED;
	drm_dbg_kms(connector->dev, "%s preferred mode set to %ux%u@%u\n",
		    source, width, height, refresh);
	return true;
}

static void sm750_apply_preferred_mode(struct drm_connector *connector)
{
	unsigned int supplied;

	supplied = !!preferred_width + !!preferred_height + !!preferred_refresh;
	if (!supplied)
		return;
	if (supplied != 3) {
		drm_warn(connector->dev,
			 "preferred_width, preferred_height and preferred_refresh must all be set\n");
		return;
	}

	if (!sm750_mark_preferred_mode(connector, preferred_width,
				       preferred_height, preferred_refresh,
				       "configured")) {
		drm_warn(connector->dev,
			 "requested preferred mode %ux%u@%u is unavailable\n",
			 preferred_width, preferred_height, preferred_refresh);
	}
}

static bool sm750_mode_matches_resolution_refresh(
		const struct drm_display_mode *mode, unsigned int width,
		unsigned int height, unsigned int refresh)
{
	return mode->hdisplay == width && mode->vdisplay == height &&
		drm_mode_vrefresh(mode) == refresh;
}

static bool sm750_catalog_supports_edid_mode(
		struct sm750_drm_device *sdev,
		const struct drm_display_mode *edid_mode)
{
	const struct drm_display_mode *mode;
	size_t i;

	if (edid_only)
		return sm750_mode_valid(edid_mode, sdev->vram_size) == MODE_OK;

	for (i = 0; i < ARRAY_SIZE(sm750_standard_modes); i++) {
		mode = &sm750_standard_modes[i];
		if (sm750_mode_matches_resolution_refresh(mode,
				edid_mode->hdisplay, edid_mode->vdisplay,
				drm_mode_vrefresh(edid_mode)) &&
		    sm750_mode_valid(mode, sdev->vram_size) == MODE_OK)
			return true;
	}
	for (i = 0; i < ARRAY_SIZE(sm750_custom_modes); i++) {
		mode = &sm750_custom_modes[i];
		if (sm750_mode_matches_resolution_refresh(mode,
				edid_mode->hdisplay, edid_mode->vdisplay,
				drm_mode_vrefresh(edid_mode)) &&
		    sm750_mode_valid(mode, sdev->vram_size) == MODE_OK)
			return true;
	}
	if (softscale_wide)
		for (i = 0; i < ARRAY_SIZE(sm750_wide_modes); i++) {
			mode = &sm750_wide_modes[i];
			if (sm750_mode_matches_resolution_refresh(mode,
					edid_mode->hdisplay, edid_mode->vdisplay,
					drm_mode_vrefresh(edid_mode)) &&
			    sm750_mode_valid(mode, sdev->vram_size) == MODE_OK)
				return true;
		}

	return false;
}

static bool sm750_reconnected_with_different_edid(
		struct sm750_drm_device *sdev, const struct edid *edid)
{
	bool changed = false;

	mutex_lock(&sdev->mode_lock);
	if (sdev->connected_edid_valid && sdev->monitor_disconnected &&
	    memcmp(sdev->connected_edid, edid, SM750_DRM_EDID_SIZE))
		changed = true;
	memcpy(sdev->connected_edid, edid, SM750_DRM_EDID_SIZE);
	sdev->connected_edid_valid = true;
	sdev->monitor_disconnected = false;
	mutex_unlock(&sdev->mode_lock);

	return changed;
}

static void sm750_select_reconnected_monitor_mode(
		struct drm_connector *connector)
{
	struct sm750_drm_device *sdev = connector_to_sm750(connector);
	struct drm_display_mode *mode;
	struct drm_display_mode *best = NULL;
	u64 pixels;
	u64 best_pixels = 0;
	unsigned int refresh;
	unsigned int best_refresh = 0;

	if (sdev->disconnected_mode_valid) {
		list_for_each_entry(mode, &connector->probed_modes, head) {
			if (sm750_mode_matches_resolution_refresh(mode,
					sdev->disconnected_width,
					sdev->disconnected_height,
					sdev->disconnected_refresh)) {
				best = mode;
				break;
			}
		}
	}

	if (!best) {
		list_for_each_entry(mode, &connector->probed_modes, head) {
			if (!sm750_catalog_supports_edid_mode(sdev, mode))
				continue;
			pixels = (u64)mode->hdisplay * mode->vdisplay;
			refresh = drm_mode_vrefresh(mode);
			if (!best || pixels > best_pixels ||
			    (pixels == best_pixels &&
			     mode->hdisplay > best->hdisplay) ||
			    (pixels == best_pixels &&
			     mode->hdisplay == best->hdisplay &&
			     refresh > best_refresh)) {
				best = mode;
				best_pixels = pixels;
				best_refresh = refresh;
			}
		}
	}

	if (!best) {
		sdev->hotplug_preferred_valid = false;
		drm_warn(connector->dev,
			 "new monitor EDID has no mutually supported mode\n");
		return;
	}

	sdev->hotplug_preferred_width = best->hdisplay;
	sdev->hotplug_preferred_height = best->vdisplay;
	sdev->hotplug_preferred_refresh = drm_mode_vrefresh(best);
	sdev->hotplug_preferred_valid = true;
}

static void sm750_remove_probed_modes(struct drm_connector *connector)
{
	struct drm_display_mode *mode, *next;

	list_for_each_entry_safe(mode, next, &connector->probed_modes, head) {
		list_del(&mode->head);
		drm_mode_destroy(connector->dev, mode);
	}
}

static struct edid *sm750_connector_read_edid(struct drm_connector *connector)
{
	struct sm750_drm_device *sdev = connector_to_sm750(connector);
	struct edid *edid;
	u8 checksum;
	unsigned int i;
	int ret;

	edid = kmalloc(256, GFP_KERNEL);
	if (!edid)
		return NULL;
	/*
	 * One bounded DDC attempt. ->get_modes runs under connection_mutex
	 * and the connector is polled every 10 s, so a retry with a
	 * multi-second sleep here would stall every modeset in the system.
	 * A monitor that is still waking up gets its modes on a later poll.
	 */
	mutex_lock(&sdev->mode_lock);
	ret = sm750_sii902x_read_edid(&sdev->pdev->dev, (u8 *)edid, 256);
	mutex_unlock(&sdev->mode_lock);
	if (ret) {
		kfree(edid);
		drm_connector_update_edid_property(connector, NULL);
		drm_dbg_kms(connector->dev,
			    "monitor identity EDID unavailable: %d\n", ret);
		return NULL;
	}

	/* The transmitter helper reads at most one extension. */
	if (edid->extensions > 1) {
		edid->extensions = 1;
		edid->checksum = 0;
		checksum = 0;
		for (i = 0; i < 128; i++)
			checksum += ((u8 *)edid)[i];
		edid->checksum = -checksum;
	}
	if (!edid->extensions)
		memset((u8 *)edid + 128, 0, 128);

	ret = drm_connector_update_edid_property(connector, edid);
	if (ret)
		drm_warn(connector->dev,
			 "failed to publish monitor identity EDID: %d\n", ret);
	return edid;
}

static bool sm750_connector_has_resolution(struct drm_connector *connector,
					   unsigned int width,
					   unsigned int height)
{
	struct drm_display_mode *mode;

	list_for_each_entry(mode, &connector->probed_modes, head)
		if (mode->hdisplay == width && mode->vdisplay == height)
			return true;
	return false;
}

static int sm750_connector_get_modes(struct drm_connector *connector)
{
	struct sm750_drm_device *sdev = connector_to_sm750(connector);
	struct edid *edid;
	bool changed_monitor = false;
	int count = 0;

	edid = sm750_connector_read_edid(connector);
	if (edid)
		changed_monitor = sm750_reconnected_with_different_edid(sdev,
								 edid);
	if ((edid_only || changed_monitor) && edid)
		count = drm_add_edid_modes(connector, edid);
	if (changed_monitor) {
		sm750_select_reconnected_monitor_mode(connector);
		if (!edid_only) {
			sm750_remove_probed_modes(connector);
			count = 0;
		}
	}

	if (edid_only && count > 0) {
		if (softscale_wide &&
		    !sm750_connector_has_resolution(connector, 1920, 1080))
			count += sm750_add_modes(connector, sm750_safe_1920_modes,
				ARRAY_SIZE(sm750_safe_1920_modes), true);
	} else {
		count = sm750_add_modes(connector, sm750_standard_modes,
				ARRAY_SIZE(sm750_standard_modes), false);
		if (!edid_only) {
			count += sm750_add_modes(connector, sm750_custom_modes,
				ARRAY_SIZE(sm750_custom_modes), true);
			if (softscale_wide)
				count += sm750_add_modes(connector, sm750_wide_modes,
					ARRAY_SIZE(sm750_wide_modes), true);
		}
	}
	kfree(edid);
	sm750_apply_preferred_mode(connector);
	if (sdev->hotplug_preferred_valid &&
	    !sm750_mark_preferred_mode(connector,
			sdev->hotplug_preferred_width,
			sdev->hotplug_preferred_height,
			sdev->hotplug_preferred_refresh, "hotplug"))
		drm_warn(connector->dev,
			 "hotplug preferred mode %ux%u@%u is unavailable\n",
			 sdev->hotplug_preferred_width,
			 sdev->hotplug_preferred_height,
			 sdev->hotplug_preferred_refresh);
	return count;
}

static void sm750_remember_disconnected_mode(
		struct sm750_drm_device *sdev, struct drm_connector *connector)
{
	struct drm_crtc_state *crtc_state = NULL;

	if (connector->state && connector->state->crtc)
		crtc_state = connector->state->crtc->state;

	mutex_lock(&sdev->mode_lock);
	if (!sdev->monitor_disconnected) {
		sdev->disconnected_mode_valid = crtc_state && crtc_state->active;
		if (sdev->disconnected_mode_valid) {
			sdev->disconnected_width = crtc_state->mode.hdisplay;
			sdev->disconnected_height = crtc_state->mode.vdisplay;
			sdev->disconnected_refresh =
				drm_mode_vrefresh(&crtc_state->mode);
		}
	}
	sdev->monitor_disconnected = true;
	mutex_unlock(&sdev->mode_lock);
}

static enum drm_connector_status
sm750_connector_detect(struct drm_connector *connector, bool force)
{
	struct sm750_drm_device *sdev = connector_to_sm750(connector);
	bool connected = false;
	bool receiver = false;
	bool event = false;
	int ret;

	mutex_lock(&sdev->mode_lock);
	ret = sm750_sii902x_get_link_status(&connected, &receiver, &event, false);
	mutex_unlock(&sdev->mode_lock);
	if (ret)
		return connector_status_unknown;
	if (!connected && !receiver)
		sm750_remember_disconnected_mode(sdev, connector);

	return (connected || receiver) ? connector_status_connected :
		connector_status_disconnected;
}

static bool sm750_mode_has_same_timing(const struct drm_display_mode *mode,
				       const struct drm_display_mode *candidate)
{
	return mode->clock == candidate->clock &&
		mode->hdisplay == candidate->hdisplay &&
		mode->hsync_start == candidate->hsync_start &&
		mode->hsync_end == candidate->hsync_end &&
		mode->htotal == candidate->htotal &&
		mode->vdisplay == candidate->vdisplay &&
		mode->vsync_start == candidate->vsync_start &&
		mode->vsync_end == candidate->vsync_end &&
		mode->vtotal == candidate->vtotal &&
		mode->flags == candidate->flags;
}

static bool sm750_mode_is_catalogued(const struct drm_display_mode *mode)
{
	size_t i;

	for (i = 0; i < ARRAY_SIZE(sm750_standard_modes); i++)
		if (sm750_mode_has_same_timing(mode, &sm750_standard_modes[i]))
			return true;

	for (i = 0; i < ARRAY_SIZE(sm750_custom_modes); i++)
		if (sm750_mode_has_same_timing(mode, &sm750_custom_modes[i]))
			return true;
	for (i = 0; i < ARRAY_SIZE(sm750_safe_1920_modes); i++)
		if (sm750_mode_has_same_timing(mode, &sm750_safe_1920_modes[i]))
			return true;
	if (softscale_wide)
		for (i = 0; i < ARRAY_SIZE(sm750_wide_modes); i++)
			if (sm750_mode_has_same_timing(mode, &sm750_wide_modes[i]))
				return true;

	return false;
}

static enum drm_mode_status
sm750_mode_valid(const struct drm_display_mode *mode, u32 vram_size)
{
	struct drm_display_mode output_mode;
	const struct drm_display_mode *hardware_mode = mode;
	struct pll_value pll = {
		.clock_type = SM750_DRM_PLL,
		.input_freq = DEFAULT_INPUT_CLOCK,
	};
	u64 size;
	int ret;

	if (mode->flags & (DRM_MODE_FLAG_INTERLACE | DRM_MODE_FLAG_DBLSCAN))
		return MODE_NO_INTERLACE;
	if (!edid_only && !sm750_mode_is_catalogued(mode))
		return MODE_BAD;
	ret = sm750_softscale_output_mode(mode, &output_mode);
	if (ret < 0)
		return MODE_BAD;
	if (ret > 0)
		hardware_mode = &output_mode;
	if (!hardware_mode->clock ||
	    hardware_mode->clock > SM750_DRM_MAX_CLOCK_KHZ)
		return MODE_CLOCK_HIGH;
	if (hardware_mode->hdisplay > SM750_DRM_PHYSICAL_MAX_WIDTH)
		return MODE_BAD_HVALUE;
	if (hardware_mode->vdisplay > SM750_DRM_MAX_HEIGHT)
		return MODE_BAD_VVALUE;
	if (hardware_mode->hdisplay > hardware_mode->hsync_start ||
	    hardware_mode->hsync_start >= hardware_mode->hsync_end ||
	    hardware_mode->hsync_end > hardware_mode->htotal)
		return MODE_H_ILLEGAL;
	if (hardware_mode->vdisplay > hardware_mode->vsync_start ||
	    hardware_mode->vsync_start >= hardware_mode->vsync_end ||
	    hardware_mode->vsync_end > hardware_mode->vtotal)
		return MODE_V_ILLEGAL;
	if (!sm750_calc_pll_value(hardware_mode->clock * 1000, &pll))
		return MODE_CLOCK_RANGE;

	size = (u64)ALIGN(mode->hdisplay * 4, SM750_DRM_LINE_ALIGN) *
		mode->vdisplay;
	if (size > vram_size)
		return MODE_MEM;

	return MODE_OK;
}

static enum drm_mode_status
sm750_connector_mode_valid(struct drm_connector *connector,
			   const struct drm_display_mode *mode)
{
	return sm750_mode_valid(mode, connector_to_sm750(connector)->vram_size);
}

static const struct drm_connector_helper_funcs sm750_connector_helper_funcs = {
	.get_modes = sm750_connector_get_modes,
	.mode_valid = sm750_connector_mode_valid,
};

static const struct drm_connector_funcs sm750_connector_funcs = {
	.detect = sm750_connector_detect,
	.fill_modes = drm_helper_probe_single_connector_modes,
	.destroy = drm_connector_cleanup,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 3, 0)
	.atomic_create_state = drm_atomic_helper_connector_create_state,
#else
	.reset = drm_atomic_helper_connector_reset,
#endif
	.atomic_duplicate_state = drm_atomic_helper_connector_duplicate_state,
	.atomic_destroy_state = drm_atomic_helper_connector_destroy_state,
};

static void sm750_mode_to_fb_var(struct fb_var_screeninfo *var,
				 const struct drm_display_mode *mode,
				 unsigned int bits_per_pixel)
{
	memset(var, 0, sizeof(*var));
	var->xres = mode->hdisplay;
	var->xres_virtual = mode->hdisplay;
	var->yres = mode->vdisplay;
	var->yres_virtual = mode->vdisplay;
	var->bits_per_pixel = bits_per_pixel;
	var->pixclock = div64_u64(1000000000ULL + mode->clock / 2,
				 mode->clock);
	var->right_margin = mode->hsync_start - mode->hdisplay;
	var->hsync_len = mode->hsync_end - mode->hsync_start;
	var->left_margin = mode->htotal - mode->hsync_end;
	var->lower_margin = mode->vsync_start - mode->vdisplay;
	var->vsync_len = mode->vsync_end - mode->vsync_start;
	var->upper_margin = mode->vtotal - mode->vsync_end;
	if (mode->flags & DRM_MODE_FLAG_PHSYNC)
		var->sync |= FB_SYNC_HOR_HIGH_ACT;
	if (mode->flags & DRM_MODE_FLAG_PVSYNC)
		var->sync |= FB_SYNC_VERT_HIGH_ACT;
}

static int sm750_program_mode(struct sm750_drm_device *sdev,
			      const struct drm_display_mode *drm_mode,
			      u32 pitch, u32 offset, u8 cpp)
{
	struct drm_display_mode output_mode;
	struct sm750_scanout_mode mode;
	struct mode_parameter timing;
	struct fb_var_screeninfo var;
	u32 control;
	u32 line_width;
	u32 width;
	int ret;

	sdev->mode_stage = SM750_MODE_STAGE_NONE;
	ret = sm750_softscale_output_mode(drm_mode, &output_mode);
	if (ret < 0)
		return ret;
	ret = sm750_mode_from_drm(&mode, &output_mode, pitch, offset, cpp);
	if (ret)
		return ret;

	memset(&timing, 0, sizeof(timing));
	timing.pixel_clock = mode.clock_khz * 1000UL;
	timing.horizontal_display_end = mode.hdisplay;
	timing.horizontal_sync_start = mode.hsync_start;
	timing.horizontal_sync_width = mode.hsync_end - mode.hsync_start;
	timing.horizontal_total = mode.htotal;
	timing.vertical_display_end = mode.vdisplay;
	timing.vertical_sync_start = mode.vsync_start;
	timing.vertical_sync_height = mode.vsync_end - mode.vsync_start;
	timing.vertical_total = mode.vtotal;
	timing.horizontal_sync_polarity =
		(mode.flags & DRM_MODE_FLAG_PHSYNC) ? POS : NEG;
	timing.vertical_sync_polarity =
		(mode.flags & DRM_MODE_FLAG_PVSYNC) ? POS : NEG;
	timing.clock_phase_polarity = sdev->phase_falling ? NEG : POS;
	timing.horizontal_frequency = DIV_ROUND_CLOSEST_ULL(
		timing.pixel_clock, timing.horizontal_total);
	timing.vertical_frequency = DIV_ROUND_CLOSEST_ULL(
		timing.horizontal_frequency, timing.vertical_total);

	sm750_mode_to_fb_var(&var, &output_mode, cpp * 8);
	sdev->mode_stage = SM750_MODE_STAGE_SII_BEGIN;
	sm750_sii902x_set_mode_stage(
		sm750_mode_stage_name(sdev->mode_stage));
	ret = sm750_sii902x_begin_mode(&sdev->pdev->dev, false,
				       sii9024_scl, sii9024_sda);
	if (ret)
		return ret;
	sdev->mode_stage = SM750_MODE_STAGE_DISPLAY_CTRL;
	ret = ddk750_set_display_control(SM750_DRM_CONTROLLER, false);
	if (ret)
		return ret;
	sdev->mode_stage = SM750_MODE_STAGE_TIMING;
	ret = ddk750_set_mode_timing(&timing, SM750_DRM_PLL, true);
	if (ret)
		return ret;

	poke32(SM750_DRM_FB_ADDRESS, SM750_DRM_FB_ADDRESS_STATUS |
	       (offset & SM750_DRM_FB_ADDRESS_MASK));
	line_width = ALIGN(mode.hdisplay * mode.cpp, SM750_DRM_LINE_ALIGN);
	width = ((line_width << SM750_DRM_FB_WIDTH_WIDTH_SHIFT) &
		 SM750_DRM_FB_WIDTH_WIDTH_MASK) |
		(pitch & SM750_DRM_FB_WIDTH_OFFSET_MASK);
	poke32(SM750_DRM_FB_WIDTH, width);
	poke32(PANEL_WINDOW_WIDTH,
	       ((mode.hdisplay - 1) << PANEL_WINDOW_WIDTH_WIDTH_SHIFT) &
	       PANEL_WINDOW_WIDTH_WIDTH_MASK);
	poke32(PANEL_WINDOW_HEIGHT,
	       ((mode.vdisplay - 1) << PANEL_WINDOW_HEIGHT_HEIGHT_SHIFT) &
	       PANEL_WINDOW_HEIGHT_HEIGHT_MASK);
	poke32(PANEL_PLANE_TL, 0);
	poke32(PANEL_PLANE_BR,
	       ((mode.vdisplay - 1) << PANEL_PLANE_BR_BOTTOM_SHIFT) |
	       ((mode.hdisplay - 1) & PANEL_PLANE_BR_RIGHT_MASK));

	control = peek32(SM750_DRM_DISPLAY_CTRL);
	control &= ~SM750_DRM_DISPLAY_CTRL_FORMAT;
	control |= cpp == 2 ? SM750_DRM_DISPLAY_CTRL_FORMAT_16 :
		SM750_DRM_DISPLAY_CTRL_FORMAT_32;
	poke32(SM750_DRM_DISPLAY_CTRL, control);
	sdev->mode_stage = SM750_MODE_STAGE_LOGICAL_OUT;
	ret = ddk750_set_logical_disp_out(SM750_DRM_OUTPUT);
	if (ret)
		return ret;
	sdev->mode_stage = SM750_MODE_STAGE_SII_ENABLE;
	sm750_sii902x_set_mode_stage(
		sm750_mode_stage_name(sdev->mode_stage));
	ret = sm750_sii902x_enable(&sdev->pdev->dev, &var, false,
				   sii9024_scl, sii9024_sda);
	if (!ret)
		sdev->mode_stage = SM750_MODE_STAGE_NONE;
	return ret;
}

static void sm750_dma_irq_disable(void *data)
{
	struct sm750_drm_device *sdev = data;
	u32 mask;

	if (!sdev->dma_irq_enabled)
		return;
	WRITE_ONCE(sdev->dma_irq_armed, false);
	mask = peek32(INT_MASK);
	mask &= ~INT_MASK_DMA1;
	mask |= sdev->dma_irq_mask_saved & INT_MASK_DMA1;
	poke32(INT_MASK, mask);
	sdev->dma_irq_enabled = false;
}

static irqreturn_t sm750_dma_irq_handler(int irq, void *data)
{
	struct sm750_drm_device *sdev = data;
	u32 control;
	u32 status;

	if (irq != sdev->pdev->irq)
		return IRQ_NONE;
	status = readl(sdev->regs + INT_STATUS);
	control = readl(sdev->regs + DMA_ABORT_INTERRUPT);
	if (!(status & INT_STATUS_DMA1) &&
	    !(control & DMA_ABORT_INTERRUPT_INT_1))
		return IRQ_NONE;
	if (!(control & DMA_ABORT_INTERRUPT_INT_1))
		return IRQ_NONE;
	writel(control & ~DMA_ABORT_INTERRUPT_INT_1,
	       sdev->regs + DMA_ABORT_INTERRUPT);
	if (READ_ONCE(sdev->dma_irq_armed))
		complete(&sdev->dma_completion);
	return IRQ_HANDLED;
}

static int sm750_dma_irq_init(struct sm750_drm_device *sdev)
{
	int ret;

	if (!sdev->pdev->irq)
		return -ENXIO;
	init_completion(&sdev->dma_completion);
	ret = devm_request_irq(&sdev->pdev->dev, sdev->pdev->irq,
			       sm750_dma_irq_handler, IRQF_SHARED,
			       SM750_DRM_NAME "-dma", sdev);
	if (ret)
		return ret;
	sdev->dma_irq_mask_saved = peek32(INT_MASK);
	poke32(INT_MASK, sdev->dma_irq_mask_saved | INT_MASK_DMA1);
	sdev->dma_irq_enabled = true;
	ret = devm_add_action_or_reset(&sdev->pdev->dev,
				       sm750_dma_irq_disable, sdev);
	if (ret)
		return ret;
	return 0;
}

static void sm750_dma_abort(struct sm750_drm_device *sdev)
{
	u32 control = peek32(DMA_ABORT_INTERRUPT);

	poke32(DMA_ABORT_INTERRUPT, control | DMA_ABORT_INTERRUPT_ABORT_1);
	udelay(1);
	poke32(DMA_ABORT_INTERRUPT,
		(control & ~DMA_ABORT_INTERRUPT_ABORT_1) &
		~DMA_ABORT_INTERRUPT_INT_1);
}

static int sm750_dma_start(struct sm750_drm_device *sdev,
			   unsigned int staging_index,
			   u32 destination, size_t size)
{
	u32 control;

	if (!size || size > SM750_DRM_DMA_STAGING_SIZE ||
	    staging_index >= SM750_DRM_DMA_STAGING_BUFFERS ||
	    sdev->dma_active ||
	    !IS_ALIGNED(size, sizeof(u32)) ||
	    !IS_ALIGNED(destination, sizeof(u32)) ||
	    destination + size > sdev->vram_size)
		return -EINVAL;

	control = peek32(DMA_ABORT_INTERRUPT);
	control &= ~(DMA_ABORT_INTERRUPT_ABORT_1 |
		     DMA_ABORT_INTERRUPT_INT_1);
	poke32(DMA_ABORT_INTERRUPT, control);
	if (sdev->dma_irq_enabled) {
		reinit_completion(&sdev->dma_completion);
		WRITE_ONCE(sdev->dma_irq_armed, true);
	}
	poke32(PCI_MASTER_BASE,
		sdev->dma_master_base[staging_index] &
		PCI_MASTER_BASE_ADDRESS_MASK);
	poke32(DMA_1_SOURCE, sdev->dma_source_address[staging_index]);
	poke32(DMA_1_DESTINATION,
		destination & DMA_1_DESTINATION_ADDRESS_MASK);
	sdev->dma_active_index = staging_index;
	sdev->dma_active_destination = destination;
	sdev->dma_active_size = size;
	sdev->dma_active = true;
	sdev->staging_batches++;
	sdev->staging_bytes += size;
	dma_wmb();
	poke32(DMA_1_SIZE_CONTROL,
		DMA_1_SIZE_CONTROL_STATUS |
		((size - sizeof(u32)) & DMA_1_SIZE_CONTROL_SIZE_MASK));
	return 0;
}

static int sm750_dma_wait_active(struct sm750_drm_device *sdev)
{
	bool irq_completion = sdev->dma_irq_enabled;
	unsigned long completed = 0;
	u32 control;
	int ret;

	if (!sdev->dma_active)
		return 0;
	if (irq_completion) {
		completed = wait_for_completion_timeout(&sdev->dma_completion,
			max_t(unsigned long, 1,
			      usecs_to_jiffies(SM750_DRM_DMA_TIMEOUT_US)));
		WRITE_ONCE(sdev->dma_irq_armed, false);
		ret = completed ? 0 : -ETIMEDOUT;
	} else {
		ret = readl_poll_timeout_atomic(
			sdev->regs + DMA_ABORT_INTERRUPT, control,
			control & DMA_ABORT_INTERRUPT_INT_1, 1,
			SM750_DRM_DMA_TIMEOUT_US);
	}
	if (!ret) {
		if (!irq_completion) {
			/* A zero write acknowledges channel-1 completion. */
			poke32(DMA_ABORT_INTERRUPT,
				control & ~DMA_ABORT_INTERRUPT_INT_1);
		}
		sdev->dma_active = false;
		return 0;
	}
	control = peek32(DMA_ABORT_INTERRUPT);
	if (irq_completion && (control & DMA_ABORT_INTERRUPT_INT_1)) {
		poke32(DMA_ABORT_INTERRUPT,
			control & ~DMA_ABORT_INTERRUPT_INT_1);
		drm_info(&sdev->drm,
			 "DMA1 IRQ was not delivered; reverting to completion polling\n");
		sm750_dma_irq_disable(sdev);
		sdev->dma_active = false;
		return 0;
	}
	/*
	 * The handler clears the status bit before it completes, so a raced
	 * acknowledgement can leave the bit clear while the transfer already
	 * finished. Re-read the completion counter once, then decide.
	 */
	if (irq_completion && completion_done(&sdev->dma_completion)) {
		sdev->dma_active = false;
		return 0;
	}
	drm_err(&sdev->drm,
		"DMA1 shadow upload timed out; using CPU copies from now on\n");

	sm750_dma_abort(sdev);
	sm750_enable_dma(0);
	sdev->shadow_dma_broken = true;
	sdev->shadow_dma_enabled = false;
	sdev->dma_active = false;
	return ret;
}

static int sm750_dma_complete_active(struct sm750_drm_device *sdev)
{
	unsigned int staging_index;
	u32 destination;
	size_t size;
	int ret;

	if (!sdev->dma_active)
		return 0;
	staging_index = sdev->dma_active_index;
	destination = sdev->dma_active_destination;
	size = sdev->dma_active_size;
	ret = sm750_dma_wait_active(sdev);
	if (ret)
		memcpy_toio(sdev->vram + destination,
			sdev->dma_staging[staging_index], size);
	return ret;
}

static void sm750_dma_submit_pending(struct sm750_drm_device *sdev)
{
	unsigned int staging_index;
	u32 destination;
	size_t size;

	if (!sdev->dma_pending_size)
		return;
	staging_index = sdev->dma_fill_index;
	destination = sdev->dma_pending_destination;
	size = sdev->dma_pending_size;
	sm750_dma_complete_active(sdev);
	if (sdev->shadow_dma_enabled &&
	    !sm750_dma_start(sdev, staging_index, destination, size))
		sdev->dma_fill_index ^= 1;
	else
		memcpy_toio(sdev->vram + destination,
			sdev->dma_staging[staging_index], size);
	sdev->dma_pending_size = 0;
}

static void sm750_dma_drain(struct sm750_drm_device *sdev)
{
	sm750_dma_submit_pending(sdev);
	sm750_dma_complete_active(sdev);
}

static void sm750_shadow_upload_one(struct sm750_drm_device *sdev,
				    u32 destination, const void *source,
				    size_t size)
{
	bool dma_eligible = sdev->shadow_dma_enabled &&
		size >= shadow_dma_min_bytes &&
		size <= SM750_DRM_DMA_STAGING_SIZE &&
		IS_ALIGNED(destination, sizeof(u32)) &&
		IS_ALIGNED(size, sizeof(u32));

	if (!size)
		return;
	if (size > sdev->vram_size || destination > sdev->vram_size - size)
		return;
	sdev->shadow_write_pending = true;

	if (dma_eligible && sdev->dma_pending_size) {
		if (destination == sdev->dma_pending_destination +
				sdev->dma_pending_size &&
		    sdev->dma_pending_size + size <= sdev->dma_batch_limit) {
			memcpy((u8 *)sdev->dma_staging[sdev->dma_fill_index] +
			       sdev->dma_pending_size,
			       source, size);
			sdev->dma_pending_size += size;
			if (sdev->dma_pending_size >= sdev->dma_batch_limit)
				sm750_dma_submit_pending(sdev);
			return;
		}
		sm750_dma_submit_pending(sdev);
		dma_eligible = sdev->shadow_dma_enabled;
	}

	if (dma_eligible) {
		memcpy(sdev->dma_staging[sdev->dma_fill_index], source, size);
		if (size == SM750_DRM_DMA_BATCH_ROW_SIZE) {
			sdev->dma_pending_destination = destination;
			sdev->dma_pending_size = size;
			if (size >= sdev->dma_batch_limit)
				sm750_dma_submit_pending(sdev);
			return;
		}
		sdev->dma_pending_destination = destination;
		sdev->dma_pending_size = size;
		sm750_dma_submit_pending(sdev);
		return;
	}
	sm750_dma_drain(sdev);
	memcpy_toio(sdev->vram + destination, source, size);
}

static void sm750_shadow_upload(struct sm750_drm_device *sdev,
				u32 destination, const void *source,
				size_t size)
{
	u32 second_offset;

	if (!size || size > sdev->vram_size ||
	    destination > sdev->vram_size - size ||
	    sdev->shadow_upload_offset >
		sdev->vram_size - destination - size)
		return;
	sm750_shadow_upload_one(sdev,
		destination + sdev->shadow_upload_offset, source, size);
	if (!sdev->backbuffer_mirror || !sdev->backbuffer_available)
		return;
	second_offset = sdev->shadow_upload_offset == sdev->scanout_offset ?
		sdev->backbuffer_offset : sdev->scanout_offset;
	if (second_offset == sdev->shadow_upload_offset ||
	    second_offset > sdev->vram_size - destination - size)
		return;
	sm750_shadow_upload_one(sdev, destination + second_offset, source, size);
}

static void sm750_shadow_finish_uploads(struct sm750_drm_device *sdev)
{
	sm750_dma_drain(sdev);
	if (sdev->shadow_write_pending)
		wmb();
	sdev->shadow_write_pending = false;
}

static int sm750_dma_init(struct sm750_drm_device *sdev)
{
	dma_addr_t address;
	u32 test_destination;
	u32 expected;
	unsigned int i;
	unsigned int staging_index;
	int ret;

	ret = dma_set_mask_and_coherent(&sdev->pdev->dev, DMA_BIT_MASK(31));
	if (ret)
		return ret;
	for (staging_index = 0;
	     staging_index < SM750_DRM_DMA_STAGING_BUFFERS;
	     staging_index++) {
		sdev->dma_staging[staging_index] = dmam_alloc_coherent(
			&sdev->pdev->dev, SM750_DRM_DMA_STAGING_SIZE,
			&sdev->dma_staging_address[staging_index], GFP_KERNEL);
		if (!sdev->dma_staging[staging_index])
			return -ENOMEM;
		address = sdev->dma_staging_address[staging_index];
		if (address > DMA_BIT_MASK(31) ||
		    !IS_ALIGNED(address, sizeof(u32)) ||
		    (address & GENMASK_ULL(22, 0)) +
			SM750_DRM_DMA_STAGING_SIZE > BIT_ULL(23))
			return -ERANGE;
		/* Bits 25:23 select the coherent buffer's 8 MiB window. */
		sdev->dma_master_base[staging_index] = (address >> 23) &
			PCI_MASTER_BASE_ADDRESS_MASK;
		sdev->dma_source_address[staging_index] =
			DMA_1_SOURCE_ADDRESS_EXT |
			(address & GENMASK_ULL(22, 2));
	}
	sm750_enable_dma(1);
	sm750_dma_abort(sdev);

	test_destination = sdev->cursor_offset - SM750_DRM_DMA_TEST_SIZE -
		SM750_DRM_DMA_GUARD_WORDS * sizeof(u32);
	for (i = 0; i < SM750_DRM_DMA_GUARD_WORDS; i++) {
		writel(0x51a70000U + i,
		       sdev->vram + test_destination - sizeof(u32) *
		       (SM750_DRM_DMA_GUARD_WORDS - i));
		writel(0xa75e0000U + i,
		       sdev->vram + test_destination +
		       SM750_DRM_DMA_TEST_SIZE + sizeof(u32) * i);
	}
	for (i = 0; i < SM750_DRM_DMA_TEST_SIZE; i++)
		((u8 *)sdev->dma_staging[0])[i] = (i * 73U + 19U) & 0xff;
	ret = sm750_dma_start(sdev, 0, test_destination,
			      SM750_DRM_DMA_TEST_SIZE);
	if (!ret)
		ret = sm750_dma_wait_active(sdev);
	if (!ret) {
		for (i = 0; i < SM750_DRM_DMA_TEST_SIZE; i++) {
			if (readb(sdev->vram + test_destination + i) !=
			    (((i * 73U) + 19U) & 0xff)) {
				ret = -EIO;
				break;
			}
		}
	}
	if (!ret) {
		for (i = 0; i < SM750_DRM_DMA_GUARD_WORDS; i++) {
			expected = 0x51a70000U + i;
			if (readl(sdev->vram + test_destination - sizeof(u32) *
				  (SM750_DRM_DMA_GUARD_WORDS - i)) != expected) {
				ret = -EOVERFLOW;
				break;
			}
			expected = 0xa75e0000U + i;
			if (readl(sdev->vram + test_destination +
				  SM750_DRM_DMA_TEST_SIZE + sizeof(u32) * i) !=
			    expected) {
				ret = -EOVERFLOW;
				break;
			}
		}
	}
	memset_io(sdev->vram + test_destination -
		  SM750_DRM_DMA_GUARD_WORDS * sizeof(u32), 0,
		  SM750_DRM_DMA_TEST_SIZE +
		  2 * SM750_DRM_DMA_GUARD_WORDS * sizeof(u32));
	if (ret) {
		sm750_dma_abort(sdev);
		sm750_enable_dma(0);
		sdev->shadow_dma_enabled = false;
		return ret;
	}

	sdev->shadow_dma_broken = false;
	sdev->shadow_dma_enabled = true;
	drm_info(&sdev->drm,
		 "DMA1 shadow uploads enabled after off-screen transfer verification (minimum %u bytes)\n",
		 shadow_dma_min_bytes);
	return 0;
}

static void sm750_dma_stop(void *data)
{
	struct sm750_drm_device *sdev = data;

	sm750_dma_irq_disable(sdev);
	sdev->dma_pending_size = 0;
	sdev->dma_active = false;
	sm750_dma_abort(sdev);
	sm750_enable_dma(0);
	sdev->shadow_dma_enabled = false;
}

static bool sm750_next_changed_u32_run(const u32 *source, const u32 *snapshot,
				       unsigned int end,
				       unsigned int *cursor,
				       unsigned int *run_x1,
				       unsigned int *run_x2)
{
	unsigned int x = *cursor;
	unsigned int last_changed;

	while (x < end) {
		unsigned int block_end = min(x + SM750_DRM_DAMAGE_SPLIT_GAP, end);

		if (!memcmp(source + x, snapshot + x,
			    (block_end - x) * sizeof(*source))) {
			x = block_end;
			continue;
		}
		while (source[x] == snapshot[x])
			x++;
		break;
	}
	if (x == end) {
		*cursor = end;
		return false;
	}

	*run_x1 = x;
	last_changed = x++;
	while (x < end) {
		unsigned int block_end = min(x + SM750_DRM_DAMAGE_SPLIT_GAP, end);
		unsigned int first_changed;
		unsigned int candidate;

		if (!memcmp(source + x, snapshot + x,
			    (block_end - x) * sizeof(*source))) {
			if (block_end - last_changed > SM750_DRM_DAMAGE_SPLIT_GAP)
				break;
			x = block_end;
			continue;
		}
		first_changed = x;
		while (source[first_changed] == snapshot[first_changed])
			first_changed++;
		if (first_changed - last_changed > SM750_DRM_DAMAGE_SPLIT_GAP)
			break;
		candidate = block_end;
		do {
			candidate--;
		} while (source[candidate] == snapshot[candidate]);
		last_changed = candidate;
		x = block_end;
	}

	*run_x2 = last_changed + 1;
	*cursor = *run_x2;
	return true;
}

static bool sm750_next_changed_u16_run(const u16 *source, const u16 *snapshot,
				       unsigned int end,
				       unsigned int *cursor,
				       unsigned int *run_x1,
				       unsigned int *run_x2)
{
	unsigned int x = *cursor;
	unsigned int last_changed;

	while (x < end) {
		unsigned int block_end = min(x + SM750_DRM_DAMAGE_SPLIT_GAP, end);

		if (!memcmp(source + x, snapshot + x,
			    (block_end - x) * sizeof(*source))) {
			x = block_end;
			continue;
		}
		while (source[x] == snapshot[x])
			x++;
		break;
	}
	if (x == end) {
		*cursor = end;
		return false;
	}

	*run_x1 = x;
	last_changed = x++;
	while (x < end) {
		unsigned int block_end = min(x + SM750_DRM_DAMAGE_SPLIT_GAP, end);
		unsigned int first_changed;
		unsigned int candidate;

		if (!memcmp(source + x, snapshot + x,
			    (block_end - x) * sizeof(*source))) {
			if (block_end - last_changed > SM750_DRM_DAMAGE_SPLIT_GAP)
				break;
			x = block_end;
			continue;
		}
		first_changed = x;
		while (source[first_changed] == snapshot[first_changed])
			first_changed++;
		if (first_changed - last_changed > SM750_DRM_DAMAGE_SPLIT_GAP)
			break;
		candidate = block_end;
		do {
			candidate--;
		} while (source[candidate] == snapshot[candidate]);
		last_changed = candidate;
		x = block_end;
	}

	*run_x2 = last_changed + 1;
	*cursor = *run_x2;
	return true;
}

static void sm750_upload_rgb565_span(struct sm750_drm_device *sdev,
				     const u16 *source, unsigned int y,
				     unsigned int dst_x1,
				     unsigned int dst_x2)
{
	u16 *snapshot;
	unsigned int count = dst_x2 - dst_x1;
	unsigned int cursor = 0;
	unsigned int run_x1;
	unsigned int run_x2;

	if (!count)
		return;
	snapshot = sdev->rgb565_scanout_snapshot ?
		sdev->rgb565_scanout_snapshot +
		(size_t)y * SM750_DRM_PHYSICAL_MAX_WIDTH + dst_x1 : NULL;
	if (!snapshot || !sdev->rgb565_scanout_snapshot_valid) {
		if (snapshot)
			memcpy(snapshot, source, count * sizeof(*source));
		sm750_shadow_upload(sdev,
			(size_t)y * sdev->scanout_pitch + dst_x1 * sizeof(u16),
			source, count * sizeof(*source));
		return;
	}
	if (!memcmp(source, snapshot, count * sizeof(*source)))
		return;

	while (sm750_next_changed_u16_run(source, snapshot, count, &cursor,
					  &run_x1, &run_x2)) {
		memcpy(snapshot + run_x1, source + run_x1,
		       (run_x2 - run_x1) * sizeof(*source));
		sm750_shadow_upload(sdev,
			(size_t)y * sdev->scanout_pitch +
			(dst_x1 + run_x1) * sizeof(u16),
			source + run_x1, (run_x2 - run_x1) * sizeof(*source));
	}
}

static void sm750_softscale_expand_hardware_damage(unsigned int *dst_x1,
						    unsigned int *dst_x2)
{
	/*
	 * Hardware-verified SM750 partial-update quirk: narrow softscaled damage
	 * can leave its final destination pixel stale even though ideal area-filter
	 * bounds say that pixel is covered.  The official SM750 specification is
	 * wrong for this boundary case.  Keep one extra destination pixel per side.
	 * Do not remove this margin as an apparent mathematical off-by-one.
	 */
	if (*dst_x1)
		(*dst_x1)--;
	if (*dst_x2 < SM750_DRM_PHYSICAL_MAX_WIDTH)
		(*dst_x2)++;
}

static void sm750_softscale_upload_span(struct sm750_drm_device *sdev,
					const u32 *scale_source,
					unsigned int y,
					unsigned int src_x1,
					unsigned int src_x2)
{
	unsigned int dst_x1;
	unsigned int dst_x2;
	size_t dst_offset = (size_t)y * sdev->scanout_pitch;

	if (sdev->softscale_source_width == 2464) {
		dst_x1 = src_x1 * 64U / 77U;
		dst_x2 = DIV_ROUND_UP(src_x2 * 64U, 77U);
	} else if (sdev->softscale_source_width == 2560) {
		dst_x1 = src_x1 * 4U / 5U;
		dst_x2 = DIV_ROUND_UP(src_x2 * 4U, 5U);
	} else {
		dst_x1 = (u64)src_x1 * 2048 /
			sdev->softscale_source_width;
		dst_x2 = DIV_ROUND_UP_ULL((u64)src_x2 * 2048,
					   sdev->softscale_source_width);
	}
	sm750_softscale_expand_hardware_damage(&dst_x1, &dst_x2);
	/* Sharpening also changes the immediate neighbours of scaled damage. */
	if (sharpen) {
		if (dst_x1)
			dst_x1--;
		if (dst_x2 < 2048)
			dst_x2++;
	}
	if (sdev->shadow_dma_enabled && sdev->rgb565) {
		dst_x1 &= ~1U;
		dst_x2 = min(ALIGN(dst_x2, 2), 2048U);
	}
	if (dst_x1 >= dst_x2)
		return;

	if (!sdev->rgb565) {
		unsigned int calc_x1 = sharpen && dst_x1 ? dst_x1 - 1 : dst_x1;
		unsigned int calc_x2 = sharpen ? min(dst_x2 + 1, 2048U) : dst_x2;
		u32 *output = sdev->softscale_output_line;

		sm750_scale_xrgb8888(sdev->softscale_output_line, scale_source,
			sdev->dither_scale_map, sdev->softscale_source_width,
			calc_x1, calc_x2);
		if (sharpen) {
			sm750_sharpen_xrgb8888(sdev->xrgb_output_line,
				sdev->softscale_output_line, dst_x1, dst_x2,
				SM750_DRM_SHARPEN_PERCENT);
			output = sdev->xrgb_output_line;
		}
		sm750_shadow_upload(sdev, dst_offset + dst_x1 * sizeof(u32),
			output + dst_x1, (dst_x2 - dst_x1) * sizeof(u32));
		return;
	}

	if (!sdev->bbdither) {
		unsigned int calc_x1 = sharpen && dst_x1 ? dst_x1 - 1 : dst_x1;
		unsigned int calc_x2 = sharpen ? min(dst_x2 + 1, 2048U) : dst_x2;
		u32 *output = sdev->softscale_output_line;

		sm750_scale_xrgb8888(sdev->softscale_output_line, scale_source,
			sdev->dither_scale_map, sdev->softscale_source_width,
			calc_x1, calc_x2);
		if (sharpen) {
			sm750_sharpen_xrgb8888(sdev->xrgb_output_line,
				sdev->softscale_output_line, dst_x1, dst_x2,
				SM750_DRM_SHARPEN_PERCENT);
			output = sdev->xrgb_output_line;
		}
		sm750_xrgb8888_to_rgb565(sdev->dither_output_line + dst_x1,
			output + dst_x1, dst_x2 - dst_x1);
	} else if (sharpen) {
		if (sdev->softscale_source_width == 2464)
			sm750_dither_scale_77_to_64_sharpen_xrgb8888_to_rgb565(
				sdev->dither, sdev->dither_output_line,
				scale_source, y, dst_x1, dst_x2);
		else if (sdev->softscale_source_width == 2560)
			sm750_dither_scale_5_to_4_sharpen_xrgb8888_to_rgb565(
				sdev->dither, sdev->dither_output_line,
				scale_source, y, dst_x1, dst_x2);
		else
			sm750_dither_scale_sharpen_xrgb8888_to_rgb565(
				sdev->dither, sdev->dither_output_line,
				sdev->softscale_output_line, scale_source, y,
				sdev->dither_scale_map, sdev->softscale_source_width,
				dst_x1, dst_x2);
	} else if (sdev->softscale_source_width == 2560) {
		sm750_dither_scale_5_to_4_xrgb8888_to_rgb565(sdev->dither,
			sdev->dither_output_line, scale_source, y, dst_x1, dst_x2);
	} else if (sdev->softscale_source_width == 2464) {
		sm750_dither_scale_77_to_64_xrgb8888_to_rgb565(sdev->dither,
			sdev->dither_output_line, scale_source, y, dst_x1, dst_x2);
	} else {
		sm750_dither_scale_xrgb8888_to_rgb565(sdev->dither,
			sdev->dither_output_line, scale_source, y,
			sdev->dither_scale_map, dst_x1, dst_x2);
	}
	sm750_upload_rgb565_span(sdev, sdev->dither_output_line + dst_x1,
				 y, dst_x1, dst_x2);
}

struct sm750_source_run {
	unsigned int x1;
	unsigned int x2;
};

/*
 * Choose sparse or merged row uploads from the changed-pixel density, so the
 * policy scales with any source width.  The RGB565 destination snapshot still
 * suppresses unchanged output pixels after scaling, sharpening and dithering.
 */
static void sm750_softscale_upload_changed_row(
					struct sm750_drm_device *sdev,
					const u32 *source, u32 *snapshot,
					unsigned int y,
					unsigned int src_x1,
					unsigned int src_x2)
{
	struct sm750_source_run runs[SM750_DRM_MAX_ROW_RUNS];
	unsigned int changed_pixels = 0;
	unsigned int cursor = src_x1;
	unsigned int first_x = src_x2;
	unsigned int last_x = src_x1;
	unsigned int run_count = 0;
	unsigned int run_x1;
	unsigned int run_x2;
	bool run_overflow = false;
	unsigned int i;

	while (sm750_next_changed_u32_run(source, snapshot, src_x2,
						 &cursor, &run_x1, &run_x2)) {
		memcpy(snapshot + run_x1, source + run_x1,
		       (run_x2 - run_x1) * sizeof(*source));
		changed_pixels += run_x2 - run_x1;
		first_x = min(first_x, run_x1);
		last_x = max(last_x, run_x2);
		if (run_count < ARRAY_SIZE(runs)) {
			runs[run_count].x1 = run_x1;
			runs[run_count].x2 = run_x2;
			run_count++;
		} else {
			run_overflow = true;
		}
	}
	if (!run_count)
		return;
	if (run_overflow ||
	    changed_pixels * SM750_DRM_DENSE_RUN_DENOMINATOR >=
		(last_x - first_x) * SM750_DRM_DENSE_RUN_NUMERATOR) {
		sm750_softscale_upload_span(sdev, snapshot, y, first_x, last_x);
		return;
	}
	for (i = 0; i < run_count; i++)
		sm750_softscale_upload_span(sdev, snapshot, y,
				runs[i].x1, runs[i].x2);
}

static void sm750_unscaled_upload_span(struct sm750_drm_device *sdev,
				       const u32 *source, unsigned int y,
				       unsigned int dst_x, unsigned int count)
{
	size_t dst_offset;

	if (!count)
		return;
	dst_offset = (size_t)y * sdev->scanout_pitch +
		(size_t)dst_x * (sdev->rgb565 ? sizeof(u16) : sizeof(u32));
	if (!sdev->rgb565) {
		sm750_shadow_upload(sdev, dst_offset, source,
				    count * sizeof(*source));
		return;
	}
	if (sdev->bbdither)
		sm750_dither_xrgb8888_to_rgb565(sdev->dither,
				sdev->dither_output_line, count, source, count,
				dst_x, y, count, 1);
	else
		sm750_xrgb8888_to_rgb565(sdev->dither_output_line, source,
					 count);
	sm750_upload_rgb565_span(sdev, sdev->dither_output_line, y,
				 dst_x, dst_x + count);
}

static void sm750_shadow_source_rect_locked(struct sm750_drm_device *sdev,
					    const struct iosys_map *src,
					    unsigned int source_pitch,
					    bool use_async_source,
					    const struct drm_rect *rect)
{
	unsigned int width = drm_rect_width(rect);
	unsigned int y1;
	unsigned int y2;
	unsigned int y;

	if (!width || drm_rect_height(rect) <= 0 ||
	    (!use_async_source && iosys_map_is_null(src)))
		return;
	y1 = clamp_t(int, rect->y1, 0, sdev->shadow_source_height);
	y2 = clamp_t(int, rect->y2, 0, sdev->shadow_source_height);
	if (y1 >= y2)
		return;

	for (y = y1; y < y2; y++) {
		if (sdev->softscale_active) {
			u32 *snapshot = double_shadow ?
				sdev->shadow_source_snapshot +
				(size_t)y * SM750_DRM_MAX_WIDTH : NULL;
			const u32 *source_row;
			unsigned int src_x1 = clamp_t(int, rect->x1, 0,
					     sdev->softscale_source_width);
			unsigned int src_x2 = clamp_t(int, rect->x2, 0,
					     sdev->softscale_source_width);
			unsigned int x;
			size_t src_offset = (size_t)y * source_pitch;

			if (src_x1 >= src_x2)
				continue;
			if (use_async_source) {
				unsigned int copy_x1 = snapshot &&
					sdev->shadow_source_snapshot_valid ? src_x1 : 0;
				unsigned int copy_x2 = snapshot &&
					sdev->shadow_source_snapshot_valid ? src_x2 :
					sdev->softscale_source_width;

				mutex_lock(&sdev->async_lock);
				if (sdev->async_stopping) {
					mutex_unlock(&sdev->async_lock);
					return;
				}
				memcpy(sdev->dither_source_line + copy_x1,
				       sdev->async_source +
					(size_t)y * SM750_DRM_MAX_WIDTH + copy_x1,
				       (copy_x2 - copy_x1) * sizeof(u32));
				mutex_unlock(&sdev->async_lock);
				source_row = sdev->dither_source_line;
			} else if (!src->is_iomem) {
				source_row = (const u32 *)((const u8 *)src->vaddr +
							 src_offset);
			} else if (snapshot && sdev->shadow_source_snapshot_valid) {
				iosys_map_memcpy_from(
					sdev->dither_source_line + src_x1, src,
					src_offset + (size_t)src_x1 * sizeof(u32),
					(src_x2 - src_x1) * sizeof(u32));
				source_row = sdev->dither_source_line;
			} else {
				iosys_map_memcpy_from(sdev->dither_source_line, src,
						      src_offset,
						      sdev->softscale_source_width *
						      sizeof(u32));
				source_row = sdev->dither_source_line;
			}

			if (!snapshot) {
				sm750_softscale_upload_span(sdev, source_row, y,
							 src_x1, src_x2);
				continue;
			}
			if (!sdev->shadow_source_snapshot_valid) {
				memcpy(snapshot, source_row,
				       sdev->softscale_source_width * sizeof(u32));
				sm750_softscale_upload_span(sdev, snapshot, y,
							 src_x1, src_x2);
				continue;
			}
			if (!memcmp(source_row + src_x1, snapshot + src_x1,
				    (src_x2 - src_x1) * sizeof(*source_row)))
				continue;
			if (sdev->rgb565_scanout_snapshot_valid) {
				sm750_softscale_upload_changed_row(sdev, source_row,
						snapshot, y, src_x1, src_x2);
				continue;
			}
			x = src_x1;
			while (x < src_x2) {
				unsigned int run_x1;
				unsigned int run_x2;

				if (!sm750_next_changed_u32_run(source_row, snapshot,
						src_x2, &x, &run_x1, &run_x2))
					break;
				memcpy(snapshot + run_x1, source_row + run_x1,
				       (run_x2 - run_x1) * sizeof(u32));
				sm750_softscale_upload_span(sdev, snapshot, y,
						run_x1, run_x2);
			}
			continue;
		}
		unsigned int src_x1 = clamp_t(int, rect->x1, 0,
						  sdev->shadow_source_width);
		unsigned int src_x2 = clamp_t(int, rect->x2, 0,
						  sdev->shadow_source_width);
		const u32 *source_span;
		unsigned int cursor = 0;
		unsigned int run_x1;
		unsigned int run_x2;
		u32 *snapshot = double_shadow ? sdev->shadow_source_snapshot +
			(size_t)y * SM750_DRM_MAX_WIDTH + src_x1 : NULL;
		size_t src_offset;

		if (src_x1 >= src_x2)
			continue;
		width = src_x2 - src_x1;
		src_offset = (size_t)y * source_pitch +
			(size_t)src_x1 * sizeof(u32);
		if (use_async_source) {
			mutex_lock(&sdev->async_lock);
			if (sdev->async_stopping) {
				mutex_unlock(&sdev->async_lock);
				return;
			}
			memcpy(sdev->dither_source_line,
			       sdev->async_source +
				(size_t)y * SM750_DRM_MAX_WIDTH + src_x1,
			       width * sizeof(u32));
			mutex_unlock(&sdev->async_lock);
			source_span = sdev->dither_source_line;
		} else if (!src->is_iomem) {
			source_span = (const u32 *)((const u8 *)src->vaddr +
						  src_offset);
		} else {
			iosys_map_memcpy_from(sdev->dither_source_line, src,
					      src_offset, width * sizeof(u32));
			source_span = sdev->dither_source_line;
		}
		if (!snapshot || !sdev->shadow_source_snapshot_valid) {
			if (snapshot)
				memcpy(snapshot, source_span,
				       width * sizeof(*source_span));
			sm750_unscaled_upload_span(sdev, source_span, y, src_x1,
						     width);
			continue;
		}
		if (!memcmp(source_span, snapshot, width * sizeof(*source_span)))
			continue;
		while (sm750_next_changed_u32_run(source_span, snapshot, width,
						  &cursor, &run_x1, &run_x2)) {
			memcpy(snapshot + run_x1, source_span + run_x1,
			       (run_x2 - run_x1) * sizeof(*source_span));
			sm750_unscaled_upload_span(sdev, source_span + run_x1, y,
					src_x1 + run_x1, run_x2 - run_x1);
		}
	}
	if (double_shadow && !sdev->shadow_source_snapshot_valid &&
	    rect->x1 <= 0 && rect->y1 <= 0 &&
	    rect->x2 >= sdev->shadow_source_width &&
	    rect->y2 >= sdev->shadow_source_height)
		sdev->shadow_source_snapshot_valid = true;
	if (sdev->rgb565_scanout_snapshot &&
	    rect->x1 <= 0 && rect->y1 <= 0 &&
	    rect->x2 >= sdev->shadow_source_width &&
	    rect->y2 >= sdev->shadow_source_height)
		sdev->rgb565_scanout_snapshot_valid = true;
}

static void sm750_shadow_rect_locked(struct sm750_drm_device *sdev,
				     struct drm_plane_state *plane_state,
				     const struct drm_rect *rect)
{
	struct drm_shadow_plane_state *shadow =
		to_drm_shadow_plane_state(plane_state);

	sm750_shadow_source_rect_locked(sdev, &shadow->data[0],
					plane_state->fb->pitches[0], false, rect);
}

static void sm750_shadow_rect(struct sm750_drm_device *sdev,
			      struct drm_plane_state *plane_state,
			      const struct drm_rect *rect)
{
	mutex_lock(&sdev->shadow_lock);
	sm750_shadow_rect_locked(sdev, plane_state, rect);
	sm750_shadow_finish_uploads(sdev);
	mutex_unlock(&sdev->shadow_lock);
}

static bool sm750_damage_is_full_frame(struct sm750_drm_device *sdev,
				       const struct drm_rect *rects,
				       unsigned int count)
{
	return count == 1 && rects[0].x1 <= 0 && rects[0].y1 <= 0 &&
		       rects[0].x2 >= sdev->shadow_source_width &&
		       rects[0].y2 >= sdev->shadow_source_height;
}

static bool sm750_begin_staged_frame(struct sm750_drm_device *sdev,
				     const struct drm_rect *rects,
				     unsigned int count)
{
	/* Snapshot writable controls once, before any batch becomes pending. */
	sdev->staging_rows = clamp_t(unsigned int,
		READ_ONCE(dma_batch_rows), 1, SM750_DRM_DMA_BATCH_ROWS);
	sdev->dma_batch_limit = sdev->staging_rows *
		SM750_DRM_DMA_BATCH_ROW_SIZE;
	sdev->staging_measure = false;
	if (!sdev->backbuffer_ready ||
	    !sm750_damage_is_full_frame(sdev, rects, count))
		return false;

	/* The inactive buffer may be stale, so a staged frame must be complete. */
	sdev->shadow_upload_offset = sdev->backbuffer_offset;
	sdev->shadow_source_snapshot_valid = false;
	sdev->rgb565_scanout_snapshot_valid = false;
	sdev->staging_measure = READ_ONCE(staging_timing);
	sdev->staging_batches = 0;
	sdev->staging_bytes = 0;
	sdev->staging_started_ns = ktime_get_ns();
	return true;
}

static bool sm750_present_staged_frame(struct sm750_drm_device *sdev)
{
	u32 address;
	u32 old_scanout;
	u64 uploaded_ns = ktime_get_ns();
	int ret;

	mutex_lock(&sdev->mode_lock);
	poke32(SM750_DRM_FB_ADDRESS, SM750_DRM_FB_ADDRESS_STATUS |
	       (sdev->backbuffer_offset & SM750_DRM_FB_ADDRESS_MASK));
	ret = readl_poll_timeout(sdev->regs + SM750_DRM_FB_ADDRESS, address,
			 !(address & SM750_DRM_FB_ADDRESS_STATUS), 100,
			 SM750_DRM_FLIP_TIMEOUT_US);
	mutex_unlock(&sdev->mode_lock);
	if (sdev->staging_measure)
		drm_info(&sdev->drm,
			 "staging-bench rows=%u frame_bytes=%u dma_bytes=%llu batches=%u upload_us=%llu flip_us=%llu ok=%u\n",
			 sdev->staging_rows, sdev->scanout_frame_size,
			 sdev->staging_bytes, sdev->staging_batches,
			 div_u64(uploaded_ns - sdev->staging_started_ns, 1000),
			 div_u64(ktime_get_ns() - uploaded_ns, 1000), !ret);
	if (ret) {
		drm_err_ratelimited(&sdev->drm,
			"full-frame backbuffer flip timed out; disabling flips and mirroring updates\n");
		sdev->backbuffer_ready = false;
		sdev->backbuffer_mirror = true;
		sdev->shadow_upload_offset = sdev->scanout_offset;
		sdev->shadow_source_snapshot_valid = false;
		sdev->rgb565_scanout_snapshot_valid = false;
		return false;
	}

	old_scanout = sdev->scanout_offset;
	sdev->scanout_offset = sdev->backbuffer_offset;
	sdev->backbuffer_offset = old_scanout;
	sdev->shadow_upload_offset = sdev->scanout_offset;
	return true;
}

static bool sm750_damage_lossless_union(const struct drm_rect *first,
					const struct drm_rect *second,
					struct drm_rect *result)
{
	if (first->x1 <= second->x1 && first->y1 <= second->y1 &&
	    first->x2 >= second->x2 && first->y2 >= second->y2) {
		*result = *first;
		return true;
	}
	if (second->x1 <= first->x1 && second->y1 <= first->y1 &&
	    second->x2 >= first->x2 && second->y2 >= first->y2) {
		*result = *second;
		return true;
	}
	if (first->y1 == second->y1 && first->y2 == second->y2 &&
	    first->x1 <= second->x2 && second->x1 <= first->x2) {
		result->x1 = min(first->x1, second->x1);
		result->x2 = max(first->x2, second->x2);
		result->y1 = first->y1;
		result->y2 = first->y2;
		return true;
	}
	if (first->x1 == second->x1 && first->x2 == second->x2 &&
	    first->y1 <= second->y2 && second->y1 <= first->y2) {
		result->x1 = first->x1;
		result->x2 = first->x2;
		result->y1 = min(first->y1, second->y1);
		result->y2 = max(first->y2, second->y2);
		return true;
	}
	return false;
}

static bool sm750_damage_add(struct drm_rect *rects, unsigned int *count,
			     const struct drm_rect *damage)
{
	struct drm_rect candidate = *damage;
	struct drm_rect merged;
	unsigned int i = 0;

	while (i < *count) {
		if (!sm750_damage_lossless_union(&candidate, &rects[i], &merged)) {
			i++;
			continue;
		}
		candidate = merged;
		rects[i] = rects[--*count];
		i = 0;
	}
	if (*count == SM750_DRM_MAX_DAMAGE_RECTS)
		return false;
	rects[(*count)++] = candidate;
	return true;
}

static void sm750_process_damage_rects(struct sm750_drm_device *sdev,
				       struct drm_plane_state *state,
				       struct drm_rect *rects,
				       unsigned int count)
{
	unsigned int i;

	for (i = 0; i < count; i++)
		sm750_shadow_rect_locked(sdev, state, &rects[i]);
}

static void sm750_damage_add_bounded(struct drm_rect *rects,
				     unsigned int *count,
				     const struct drm_rect *damage)
{
	struct drm_rect merged = *damage;
	unsigned int i;

	if (sm750_damage_add(rects, count, damage))
		return;
	for (i = 0; i < *count; i++) {
		merged.x1 = min(merged.x1, rects[i].x1);
		merged.y1 = min(merged.y1, rects[i].y1);
		merged.x2 = max(merged.x2, rects[i].x2);
		merged.y2 = max(merged.y2, rects[i].y2);
	}
	rects[0] = merged;
	*count = 1;
}

static void sm750_async_copy_rect_locked(struct sm750_drm_device *sdev,
					 const struct iosys_map *src,
					 unsigned int source_pitch,
					 const struct drm_rect *rect)
{
	unsigned int x1 = clamp_t(int, rect->x1, 0,
					 sdev->shadow_source_width);
	unsigned int x2 = clamp_t(int, rect->x2, 0,
					 sdev->shadow_source_width);
	unsigned int y1 = clamp_t(int, rect->y1, 0,
					 sdev->shadow_source_height);
	unsigned int y2 = clamp_t(int, rect->y2, 0,
					 sdev->shadow_source_height);
	unsigned int y;

	if (x1 >= x2 || y1 >= y2)
		return;
	for (y = y1; y < y2; y++) {
		u32 *destination = sdev->async_source +
			(size_t)y * SM750_DRM_MAX_WIDTH + x1;
		size_t source_offset = (size_t)y * source_pitch +
			(size_t)x1 * sizeof(u32);
		size_t size = (x2 - x1) * sizeof(u32);

		if (!src->is_iomem)
			memcpy(destination,
			       (const u8 *)src->vaddr + source_offset, size);
		else
			iosys_map_memcpy_from(destination, src, source_offset, size);
	}
}

static bool sm750_async_seed_source(struct sm750_drm_device *sdev,
					    struct drm_plane_state *state)
{
	struct drm_shadow_plane_state *shadow =
		to_drm_shadow_plane_state(state);
	struct drm_rect full = {
		.x1 = 0,
		.y1 = 0,
		.x2 = sdev->shadow_source_width,
		.y2 = sdev->shadow_source_height,
	};

	if (!sdev->shadow_workqueue || !sdev->async_source || !state->fb ||
	    iosys_map_is_null(&shadow->data[0]))
		return false;
	mutex_lock(&sdev->async_lock);
	sdev->async_stopping = false;
	sm750_async_copy_rect_locked(sdev, &shadow->data[0],
				      state->fb->pitches[0], &full);
	sdev->async_damage_count = 0;
	sdev->async_source_valid = true;
	mutex_unlock(&sdev->async_lock);
	return true;
}

static void sm750_async_shadow_work(struct work_struct *work)
{
	struct sm750_drm_device *sdev = container_of(work,
			struct sm750_drm_device, shadow_work);
	struct drm_rect rects[SM750_DRM_MAX_DAMAGE_RECTS];
	unsigned int count;
	unsigned int i;
	bool staged;

	for (;;) {
		mutex_lock(&sdev->async_lock);
		if (sdev->async_stopping || !sdev->async_source_valid ||
		    !sdev->async_damage_count) {
			mutex_unlock(&sdev->async_lock);
			break;
		}
		count = sdev->async_damage_count;
		memcpy(rects, sdev->async_damage,
		       count * sizeof(*rects));
		sdev->async_damage_count = 0;
		mutex_unlock(&sdev->async_lock);

		mutex_lock(&sdev->shadow_lock);
		staged = sm750_begin_staged_frame(sdev, rects, count);
		for (i = 0; i < count; i++)
			sm750_shadow_source_rect_locked(sdev, NULL,
				SM750_DRM_MAX_WIDTH * sizeof(u32), true,
				&rects[i]);
		sm750_shadow_finish_uploads(sdev);
		if (staged && !sm750_present_staged_frame(sdev)) {
			/* A late flip is harmless once both buffers match. */
			for (i = 0; i < count; i++)
				sm750_shadow_source_rect_locked(sdev, NULL,
					SM750_DRM_MAX_WIDTH * sizeof(u32), true,
					&rects[i]);
			sm750_shadow_finish_uploads(sdev);
		}
		mutex_unlock(&sdev->shadow_lock);
	}
}

static bool sm750_async_queue_damage(struct sm750_drm_device *sdev,
				     struct drm_plane_state *state,
				     struct drm_rect *rects,
				     unsigned int count)
{
	struct drm_shadow_plane_state *shadow =
		to_drm_shadow_plane_state(state);
	struct drm_rect full = {
		.x1 = 0,
		.y1 = 0,
		.x2 = sdev->shadow_source_width,
		.y2 = sdev->shadow_source_height,
	};
	unsigned int i;

	if (!count || !sdev->shadow_workqueue || !sdev->async_source ||
	    !state->fb || iosys_map_is_null(&shadow->data[0]))
		return false;
	mutex_lock(&sdev->async_lock);
	if (sdev->async_stopping) {
		mutex_unlock(&sdev->async_lock);
		return false;
	}
	if (!sdev->async_source_valid) {
		sm750_async_copy_rect_locked(sdev, &shadow->data[0],
					      state->fb->pitches[0], &full);
		sdev->async_damage[0] = full;
		sdev->async_damage_count = 1;
		sdev->async_source_valid = true;
	} else {
		for (i = 0; i < count; i++) {
			sm750_async_copy_rect_locked(sdev, &shadow->data[0],
					      state->fb->pitches[0], &rects[i]);
			sm750_damage_add_bounded(sdev->async_damage,
						 &sdev->async_damage_count,
						 &rects[i]);
		}
	}
	mutex_unlock(&sdev->async_lock);
	queue_work(sdev->shadow_workqueue, &sdev->shadow_work);
	return true;
}

static void sm750_async_quiesce(struct sm750_drm_device *sdev)
{
	if (!sdev->shadow_workqueue)
		return;
	mutex_lock(&sdev->async_lock);
	sdev->async_stopping = true;
	sdev->async_source_valid = false;
	sdev->async_damage_count = 0;
	mutex_unlock(&sdev->async_lock);
	cancel_work_sync(&sdev->shadow_work);
}

static void sm750_cursor_disable_locked(struct sm750_drm_device *sdev)
{
	poke32(SM750_DRM_HWC_ADDRESS, 0);
}

static u16 sm750_cursor_rgb565(u8 red, u8 green, u8 blue)
{
	return ((red & 0xf8) << 8) | ((green & 0xfc) << 3) | (blue >> 3);
}

static void sm750_cursor_unpremultiply(u32 pixel, u8 *alpha, u8 *red,
				       u8 *green, u8 *blue)
{
	u32 a = pixel >> 24;
	u32 r = (pixel >> 16) & 0xff;
	u32 g = (pixel >> 8) & 0xff;
	u32 b = pixel & 0xff;

	if (a && a < 255) {
		r = min(255U, DIV_ROUND_CLOSEST(r * 255, a));
		g = min(255U, DIV_ROUND_CLOSEST(g * 255, a));
		b = min(255U, DIV_ROUND_CLOSEST(b * 255, a));
	}
	*alpha = a;
	*red = r;
	*green = g;
	*blue = b;
}

static void sm750_cursor_palette(struct sm750_drm_device *sdev,
				 unsigned int width, unsigned int height,
				 u16 palette[3])
{
	u64 red_sum[3] = { 0 };
	u64 green_sum[3] = { 0 };
	u64 blue_sum[3] = { 0 };
	u64 weight[3] = { 0 };
	unsigned int x;
	unsigned int y;

	for (y = 0; y < height; y++) {
		for (x = 0; x < width; x++) {
			u8 alpha;
			u8 red;
			u8 green;
			u8 blue;
			u32 luma;
			u32 bin;

			sm750_cursor_unpremultiply(
				sdev->cursor_source[y * width + x],
				&alpha, &red, &green, &blue);
			if (!alpha)
				continue;
			luma = (77U * red + 150U * green + 29U * blue) >> 8;
			bin = min(luma / 86, 2U);
			red_sum[bin] += (u64)red * alpha;
			green_sum[bin] += (u64)green * alpha;
			blue_sum[bin] += (u64)blue * alpha;
			weight[bin] += alpha;
		}
	}

	palette[0] = 0x0000;
	palette[1] = 0x7bef;
	palette[2] = 0xffff;
	for (x = 0; x < ARRAY_SIZE(weight); x++) {
		if (weight[x])
			palette[x] = sm750_cursor_rgb565(
				DIV_ROUND_CLOSEST_ULL(red_sum[x], weight[x]),
				DIV_ROUND_CLOSEST_ULL(green_sum[x], weight[x]),
				DIV_ROUND_CLOSEST_ULL(blue_sum[x], weight[x]));
	}
}

static unsigned int sm750_cursor_nearest_color(u8 red, u8 green, u8 blue,
					       const u16 palette[3])
{
	unsigned int nearest = 0;
	u32 nearest_distance = U32_MAX;
	unsigned int i;

	for (i = 0; i < 3; i++) {
		int palette_red = ((palette[i] >> 11) & 0x1f) * 255 / 31;
		int palette_green = ((palette[i] >> 5) & 0x3f) * 255 / 63;
		int palette_blue = (palette[i] & 0x1f) * 255 / 31;
		int red_delta = (int)red - palette_red;
		int green_delta = (int)green - palette_green;
		int blue_delta = (int)blue - palette_blue;
		u32 distance = red_delta * red_delta +
			green_delta * green_delta + blue_delta * blue_delta;

		if (distance < nearest_distance) {
			nearest = i;
			nearest_distance = distance;
		}
	}
	return nearest + 1;
}

static void sm750_cursor_encode(struct sm750_drm_device *sdev,
				unsigned int source_width,
				unsigned int source_height,
				unsigned int output_width,
				u16 palette[3])
{
	static const u8 alpha_dither[16] = {
		0, 8, 2, 10,
		12, 4, 14, 6,
		3, 11, 1, 9,
		15, 7, 13, 5,
	};
	unsigned int x;
	unsigned int y;

	memset(sdev->cursor_image, 0, SM750_DRM_CURSOR_SIZE);
	for (y = 0; y < source_height; y++) {
		for (x = 0; x < output_width; x++) {
			unsigned int source_x = min_t(u64,
				((u64)(2 * x + 1) * source_width) /
				(2 * output_width), source_width - 1);
			u32 pixel = sdev->cursor_source[y * source_width + source_x];
			u8 alpha;
			u8 red;
			u8 green;
			u8 blue;
			u8 value;

			sm750_cursor_unpremultiply(pixel, &alpha, &red, &green, &blue);
			if (alpha <= alpha_dither[((y & 3) << 2) | (x & 3)] * 16)
				continue;
			value = sm750_cursor_nearest_color(red, green, blue, palette);
			sdev->cursor_image[y * SM750_DRM_CURSOR_STRIDE + x / 4] |=
				value << ((x & 3) * 2);
		}
	}
}

static int sm750_cursor_atomic_check(struct drm_plane *plane,
				    sm750_atomic_commit *atomic_state)
{
	struct drm_plane_state *state =
		drm_atomic_get_new_plane_state(atomic_state, plane);
	struct drm_crtc_state *crtc_state;
	int ret;

	if (!state->crtc || !state->fb)
		return 0;
	crtc_state = drm_atomic_get_new_crtc_state(atomic_state, state->crtc);
	ret = drm_atomic_helper_check_plane_state(state, crtc_state,
			DRM_PLANE_NO_SCALING, DRM_PLANE_NO_SCALING, true, true);
	if (ret || !state->visible)
		return ret;
	if ((state->src.x1 | state->src.y1 | state->src.x2 | state->src.y2) &
	    0xffff)
		return -EINVAL;
	if (drm_rect_width(&state->src) > (SM750_DRM_CURSOR_WIDTH << 16) ||
	    drm_rect_height(&state->src) > (SM750_DRM_CURSOR_HEIGHT << 16))
		return -EINVAL;
	return 0;
}

static void sm750_cursor_atomic_update(struct drm_plane *plane,
				       sm750_atomic_commit *atomic_state)
{
	struct sm750_drm_device *sdev =
		container_of(plane, struct sm750_drm_device, cursor_plane);
	struct drm_plane_state *state =
		drm_atomic_get_new_plane_state(atomic_state, plane);
	struct drm_plane_state *old_state =
		drm_atomic_get_old_plane_state(atomic_state, plane);
	struct drm_shadow_plane_state *shadow;
	const struct iosys_map *source;
	unsigned int source_x;
	unsigned int source_y;
	unsigned int source_width;
	unsigned int source_height;
	unsigned int output_width;
	unsigned int y;
	u16 palette[3];
	bool rebuild_image;
	int physical_x;
	int physical_y;
	u32 location = 0;

	mutex_lock(&sdev->cursor_lock);
	if (!state || !state->fb || !state->visible) {
		sm750_cursor_disable_locked(sdev);
		goto unlock;
	}
	shadow = to_drm_shadow_plane_state(state);
	source = &shadow->data[0];
	if (iosys_map_is_null(source)) {
		sm750_cursor_disable_locked(sdev);
		goto unlock;
	}
	source_x = state->src.x1 >> 16;
	source_y = state->src.y1 >> 16;
	source_width = drm_rect_width(&state->src) >> 16;
	source_height = drm_rect_height(&state->src) >> 16;
	if (!source_width || !source_height) {
		sm750_cursor_disable_locked(sdev);
		goto unlock;
	}
	output_width = source_width;
	physical_x = state->dst.x1;
	if (sdev->softscale_active) {
		output_width = max_t(u64, 1,
			DIV_ROUND_UP_ULL((u64)source_width * 2048,
					 sdev->softscale_source_width));
		physical_x = div_s64((s64)physical_x * 2048,
				       sdev->softscale_source_width);
	}
	output_width = min(output_width, (unsigned int)SM750_DRM_CURSOR_WIDTH);
	physical_y = state->dst.y1;
	if (physical_x >= 2048 || physical_y >= sdev->shadow_source_height ||
	    physical_x + output_width <= 0 ||
	    physical_y + source_height <= 0) {
		sm750_cursor_disable_locked(sdev);
		goto unlock;
	}

	rebuild_image = !sdev->cursor_image_valid || !old_state ||
		!old_state->visible || state->fb != old_state->fb ||
		!drm_rect_equals(&state->src, &old_state->src) ||
		state->fb_damage_clips != old_state->fb_damage_clips ||
		output_width != sdev->cursor_encoded_width;
	if (rebuild_image) {
		for (y = 0; y < source_height; y++) {
			size_t offset = (size_t)(source_y + y) *
				state->fb->pitches[0] +
				(size_t)source_x * sizeof(u32);

			iosys_map_memcpy_from(
				sdev->cursor_source + y * source_width,
				source, offset, source_width * sizeof(u32));
		}
		sm750_cursor_palette(sdev, source_width, source_height, palette);
		sm750_cursor_encode(sdev, source_width, source_height, output_width,
				    palette);
		memcpy_toio(sdev->vram + sdev->cursor_offset, sdev->cursor_image,
			    SM750_DRM_CURSOR_SIZE);
		poke32(SM750_DRM_HWC_COLOR_12,
			(u32)palette[1] << 16 | palette[0]);
		poke32(SM750_DRM_HWC_COLOR_3, palette[2]);
		sdev->cursor_encoded_width = output_width;
		sdev->cursor_image_valid = true;
	}
	if (physical_x < 0) {
		location |= SM750_DRM_HWC_LOCATION_LEFT;
		physical_x = -physical_x;
	}
	if (physical_y < 0) {
		location |= SM750_DRM_HWC_LOCATION_TOP;
		physical_y = -physical_y;
	}
	location |= ((physical_y << 16) & SM750_DRM_HWC_LOCATION_Y_MASK) |
		(physical_x & SM750_DRM_HWC_LOCATION_X_MASK);
	poke32(SM750_DRM_HWC_LOCATION, location);
	wmb();
	poke32(SM750_DRM_HWC_ADDRESS,
		SM750_DRM_HWC_ADDRESS_ENABLE |
		(sdev->cursor_offset & SM750_DRM_HWC_ADDRESS_MASK));
unlock:
	mutex_unlock(&sdev->cursor_lock);
}

static void sm750_cursor_atomic_disable(struct drm_plane *plane,
					sm750_atomic_commit *atomic_state)
{
	struct sm750_drm_device *sdev =
		container_of(plane, struct sm750_drm_device, cursor_plane);

	mutex_lock(&sdev->cursor_lock);
	sm750_cursor_disable_locked(sdev);
	sdev->cursor_image_valid = false;
	mutex_unlock(&sdev->cursor_lock);
}

static const struct drm_plane_funcs sm750_cursor_plane_funcs = {
	.update_plane = drm_atomic_helper_update_plane,
	.disable_plane = drm_atomic_helper_disable_plane,
	.destroy = drm_plane_cleanup,
	DRM_GEM_SHADOW_PLANE_FUNCS,
};

static const struct drm_plane_helper_funcs sm750_cursor_plane_helper_funcs = {
	.prepare_fb = drm_gem_plane_helper_prepare_fb,
	.atomic_check = sm750_cursor_atomic_check,
	.atomic_update = sm750_cursor_atomic_update,
	.atomic_disable = sm750_cursor_atomic_disable,
	DRM_GEM_SHADOW_PLANE_HELPER_FUNCS,
};

static int sm750_pipe_prepare_fb(struct drm_simple_display_pipe *pipe,
				 struct drm_plane_state *plane_state)
{
	return drm_gem_vram_plane_helper_prepare_fb(&pipe->plane, plane_state);
}

static void sm750_pipe_cleanup_fb(struct drm_simple_display_pipe *pipe,
				  struct drm_plane_state *plane_state)
{
	drm_gem_vram_plane_helper_cleanup_fb(&pipe->plane, plane_state);
}

static int sm750_shadow_pipe_prepare_fb(struct drm_simple_display_pipe *pipe,
					struct drm_plane_state *plane_state)
{
	return drm_gem_plane_helper_prepare_fb(&pipe->plane, plane_state);
}

static int sm750_pipe_check(struct drm_simple_display_pipe *pipe,
			    struct drm_plane_state *plane_state,
			    struct drm_crtc_state *crtc_state)
{
	struct sm750_drm_device *sdev = pipe_to_sm750(pipe);
	const struct drm_display_mode *mode = &crtc_state->adjusted_mode;

	if (plane_state->fb && !sdev->shadow_scanout) {
		if (plane_state->fb->pitches[0] > SM750_DRM_FB_WIDTH_OFFSET_MASK ||
		    !IS_ALIGNED(plane_state->fb->pitches[0],
				SM750_DRM_LINE_ALIGN))
			return -EINVAL;
		/*
		 * The direct path programs the panel window from the mode and
		 * scans out of the plane's own object, so a framebuffer that
		 * does not cover the mode makes the engine read past it.
		 */
		if (crtc_state->enable &&
		    (plane_state->fb->width < mode->hdisplay ||
		     plane_state->fb->height < mode->vdisplay)) {
			drm_err(&sdev->drm,
				"plane framebuffer %ux%u does not cover mode %ux%u\n",
				plane_state->fb->width, plane_state->fb->height,
				mode->hdisplay, mode->vdisplay);
			return -EINVAL;
		}
	}
	if (crtc_state->enable &&
	    sm750_mode_valid(mode, sdev->vram_size) != MODE_OK)
		return -EINVAL;

	return 0;
}

static int sm750_scanout_offset(struct drm_framebuffer *fb, u32 *offset)
{
	struct drm_gem_vram_object *gbo;
	s64 value;

	gbo = drm_gem_vram_of_gem(drm_gem_fb_get_obj(fb, 0));
	value = drm_gem_vram_offset(gbo);
	if (value < 0 || value > U32_MAX)
		return -EINVAL;
	*offset = value;
	return 0;
}

static void sm750_send_vblank_event(struct drm_simple_display_pipe *pipe);

static void sm750_arm_vblank_event(struct drm_simple_display_pipe *pipe)
{
	struct drm_crtc_state *state = pipe->crtc.state;
	struct drm_pending_vblank_event *event;
	unsigned long flags;

	if (!state->event)
		return;
	/*
	 * Canonical atomic order: take the vblank reference outside the event
	 * lock (drm_crtc_vblank_get() takes vblank_lock and may run the
	 * enable_vblank hook), then hold event_lock only for the arm.
	 */
	if (drm_crtc_vblank_get(&pipe->crtc)) {
		sm750_send_vblank_event(pipe);
		return;
	}
	spin_lock_irqsave(&pipe->crtc.dev->event_lock, flags);
	event = state->event;
	if (event) {
		state->event = NULL;
		drm_crtc_arm_vblank_event(&pipe->crtc, event);
	} else {
		drm_crtc_vblank_put(&pipe->crtc);
	}
	spin_unlock_irqrestore(&pipe->crtc.dev->event_lock, flags);
}

static void sm750_send_vblank_event(struct drm_simple_display_pipe *pipe)
{
	struct drm_crtc_state *state = pipe->crtc.state;
	unsigned long flags;

	if (!state->event)
		return;
	spin_lock_irqsave(&pipe->crtc.dev->event_lock, flags);
	drm_crtc_send_vblank_event(&pipe->crtc, state->event);
	state->event = NULL;
	spin_unlock_irqrestore(&pipe->crtc.dev->event_lock, flags);
}

/*
 * Scanout readback. Both the CRC source and the sm750_scanout debugfs dump
 * read the bytes the display engine is pointed at, in VRAM. They prove the
 * buffer the engine is fed, not the pixels the DAC emits: the RGB565 backends
 * quantise and dither, so scanout bytes are not a copy of the XRGB source.
 */

/*
 * Name the field that keeps the scanout window unreadable, or NULL when the
 * window can be read. The modeset records the geometry, so the CRC tick can
 * run while one of these is still unset; naming it is what turns a silent
 * empty stream into a diagnosable one.
 */
static const char *sm750_crc_region_missing(struct sm750_drm_device *sdev)
{
	if (!sdev->vram)
		return "vram";
	/* A zero mode is not a window: the disable commit zeroes it while a
	 * stale pitch can still be set, and a 0x0 region is unreadable. */
	if (!sdev->pipe.crtc.mode.hdisplay || !sdev->pipe.crtc.mode.vdisplay)
		return "active mode";
	if (!sdev->scanout_pitch)
		return "pitch";
	if (!sdev->scanout_frame_size)
		return "frame size";
	if (sdev->scanout_offset >= sdev->vram_size)
		return "offset bound";
	return NULL;
}

/* Bounded window: crc_window_bytes from the visible scanout offset. The
 * min() below drops any write larger than the visible frame, so a
 * full-frame grow is the only effect of a huge parameter value. */
static bool sm750_crc_region(struct sm750_drm_device *sdev, u32 *offset,
			     size_t *length, const char **missing)
{
	const char *why = sm750_crc_region_missing(sdev);
	u64 window = max_t(u64, round_down((u64)READ_ONCE(crc_window_bytes), 4),
			   4096);
	u64 visible;

	if (missing)
		*missing = why;
	if (why)
		return false;
	visible = min_t(u64, sdev->scanout_frame_size,
			sdev->vram_size - sdev->scanout_offset);
	window = round_down(min(window, visible), 4);
	if (!window) {
		if (missing)
			*missing = "frame size";
		return false;
	}
	*offset = sdev->scanout_offset;
	*length = window;
	return true;
}

/*
 * One warning per enable cycle: the tick never stops for a missing window, so
 * without a latch a card whose geometry is not recorded would fill dmesg at
 * the refresh rate. The latch is cleared by disable and by every re-arm, so a
 * later cycle reports its own reason.
 */
static void sm750_crc_region_warn(struct sm750_drm_device *sdev,
				  const char *missing)
{
	if (READ_ONCE(sdev->crc_warned))
		return;
	WRITE_ONCE(sdev->crc_warned, true);
	drm_warn(&sdev->drm,
		 "crc: scanout source is enabled but cannot read the window: %s missing; it keeps running and recovers once the modeset records the geometry\n",
		 missing ? missing : "reason");
}

/* CRC32 (IEEE, zlib-compatible) and nonzero-byte count over the window. */
static u32 sm750_scanout_crc32(struct sm750_drm_device *sdev, u32 offset,
			       size_t length, size_t *nonzero_bytes)
{
	u8 chunk[256];
	u32 crc = ~0U;
	size_t done = 0;
	size_t nonzero = 0;

	while (done < length) {
		size_t n = min_t(size_t, length - done, sizeof(chunk));
		size_t i;

		memcpy_fromio(chunk, sdev->vram + offset + done, n);
		for (i = 0; i < n; i++)
			nonzero += chunk[i] != 0;
		crc = crc32_le(crc, chunk, n);
		done += n;
	}
	if (nonzero_bytes)
		*nonzero_bytes = nonzero;
	return crc ^ ~0U;
}

/*
 * Cancel the work and drop the vblank reference it holds. Caller holds
 * crc_mutex: cancel_sync waits for a running tick, so no path reachable from
 * the work item may take that mutex.
 */
static void sm750_crc_halt(struct sm750_drm_device *sdev)
{
	struct drm_crtc *crtc = &sdev->pipe.crtc;

	drm_vblank_work_cancel_sync(&sdev->crc_work);
	if (sdev->crc_vblank) {
		sdev->crc_vblank = false;
		drm_crtc_vblank_put(crtc);
	}
}

/* User disabled the source: no work pending, no vblank reference, no state. */
static void sm750_crc_stop(struct sm750_drm_device *sdev)
{
	sdev->crc_enabled = false;
	sdev->crc_warned = false;
	sm750_crc_halt(sdev);
}

static void sm750_crc_disable(struct sm750_drm_device *sdev)
{
	mutex_lock(&sdev->crc_mutex);
	sm750_crc_stop(sdev);
	mutex_unlock(&sdev->crc_mutex);
}

/*
 * The pipe is about to go away but the user still wants CRCs: park the stream
 * and keep crc_enabled set so sm750_crc_resume() re-arms it on the next enable.
 * The work item is cancelled here, before drm_crtc_vblank_off() runs in
 * sm750_pipe_disable(): vblank work waits for an absolute vblank count, which
 * the vblank off/on pair rebuilds, so an item left queued across that pair
 * would wait on a count that no longer exists.
 */
static void sm750_crc_suspend(struct sm750_drm_device *sdev)
{
	mutex_lock(&sdev->crc_mutex);
	if (sdev->crc_enabled)
		sm750_crc_halt(sdev);
	mutex_unlock(&sdev->crc_mutex);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
/*
 * Start the tick: one vblank reference keeps vblanks coming, one work item per
 * vblank produces the entries. Shared by enable and the modeset re-arm so
 * there is a single schedule point.
 */
static int sm750_crc_arm(struct sm750_drm_device *sdev)
{
	struct drm_crtc *crtc = &sdev->pipe.crtc;
	int ret;

	ret = drm_crtc_vblank_get(crtc);
	if (ret) {
		drm_err(&sdev->drm,
			"crc: scanout source cannot take a vblank reference: %d\n",
			ret);
		return ret;
	}
	sdev->crc_vblank = true;
	ret = drm_vblank_work_schedule(&sdev->crc_work,
				       drm_crtc_vblank_count(crtc) + 1, false);
	if (ret < 0) {
		sm750_crc_halt(sdev);
		return ret;
	}
	return 0;
}

/*
 * Arm the scanout CRC source. Refusing here is the honest answer: a stream
 * whose window is not recorded would otherwise report success and never
 * produce an entry, which is indistinguishable from a broken tick. Shared by
 * the CRTC callback and the crc/control debugfs file.
 */
/* Defined with the test-card block further down. A CRC source owns the
 * scanout window and must stop a running card first (R1.1). */
static void sm750_test_pattern_cancel(struct sm750_drm_device *sdev);

static int sm750_crc_enable(struct sm750_drm_device *sdev)
{
	const char *missing = NULL;
	size_t length;
	u32 offset;
	int ret;

	mutex_lock(&sdev->crc_mutex);
	if (sdev->crc_enabled) {
		ret = 0;
		goto out_unlock;
	}
	if (!sm750_crc_region(sdev, &offset, &length, &missing)) {
		drm_err(&sdev->drm,
			"crc: scanout source not armed, cannot read the window: %s missing\n",
			missing ? missing : "reason");
		ret = -ENODEV;
		goto out_unlock;
	}
	sdev->crc_enabled = true;
	sdev->crc_warned = false;
	/* The CRC reader and the painter share the 262144-byte scanout window;
	 * leaving a paint queued would make the window torn, not static. */
	sm750_test_pattern_cancel(sdev);
	ret = sm750_crc_arm(sdev);
	if (ret)
		sm750_crc_stop(sdev);
out_unlock:
	mutex_unlock(&sdev->crc_mutex);
	return ret;
}

/*
 * The pipe is enabled again with CRC still selected: re-arm. Ordering matters:
 * drm_vblank_work_schedule() targets an absolute count derived from
 * drm_crtc_vblank_count(), so this must run after drm_crtc_vblank_on() has
 * rebuilt the vblank counter - arming before it would queue the work on a stale
 * count and it would fire at once or never - and the item was already
 * cancelled by sm750_crc_suspend() in the disable path.
 */
static void sm750_crc_resume(struct sm750_drm_device *sdev)
{
	int ret;

	mutex_lock(&sdev->crc_mutex);
	if (!sdev->crc_enabled || sdev->crc_vblank)
		goto out_unlock;
	sdev->crc_warned = false;
	ret = sm750_crc_arm(sdev);
	if (ret)
		drm_warn(&sdev->drm,
			 "crc: cannot re-arm the scanout source after a modeset: %d\n",
			 ret);
out_unlock:
	mutex_unlock(&sdev->crc_mutex);
}

/*
 * Per-vblank readback: one bounded read out of VRAM, one CRC entry. The tick is
 * unconditional while the source is enabled: the region check decides what this
 * tick can do, never whether the stream continues. Re-arming as the last
 * statement behind that check is what let one failed check kill CRC for good.
 */
static void sm750_crc_work_fn(struct kthread_work *work)
{
	struct sm750_drm_device *sdev = container_of(
		to_drm_vblank_work(work), struct sm750_drm_device, crc_work);
	struct drm_crtc *crtc = &sdev->pipe.crtc;
	const char *missing = NULL;
	size_t length;
	u32 offset;
	u32 frame;
	u32 crc;
	int ret;

	if (READ_ONCE(sdev->crc_enabled)) {
		if (!sm750_crc_region(sdev, &offset, &length, &missing)) {
			sm750_crc_region_warn(sdev, missing);
		} else {
			crc = sm750_scanout_crc32(sdev, offset, length, NULL);
			frame = drm_crtc_vblank_count(crtc);
			drm_crtc_add_crc_entry(crtc, true, frame, &crc);
		}
	}
	/*
	 * Re-arm outside the region check: a transient or persistent geometry
	 * loss must not stop the stream.
	 */
	if (READ_ONCE(sdev->crc_enabled)) {
		ret = drm_vblank_work_schedule(&sdev->crc_work,
					       drm_crtc_vblank_count(crtc) + 1,
					       false);
		if (ret < 0)
			drm_warn_once(&sdev->drm,
				      "crc: cannot re-arm the vblank work: %d\n",
				      ret);
	}
}

static bool sm750_crc_source_is_scanout(const char *source)
{
	return source && (!strcmp(source, "scanout") || !strcmp(source, "auto"));
}

static int sm750_crtc_verify_crc_source(struct drm_crtc *crtc,
					const char *source, size_t *values_cnt)
{
	if (source && *source && strcmp(source, "none") &&
	    !sm750_crc_source_is_scanout(source))
		return -EINVAL;
	*values_cnt = 1;
	return 0;
}

static const char *const sm750_crc_sources[] = { "scanout", NULL };

static const char *const *sm750_crtc_get_crc_sources(struct drm_crtc *crtc,
						     size_t *count)
{
	*count = 1;
	return sm750_crc_sources;
}

static int sm750_crtc_set_crc_source(struct drm_crtc *crtc, const char *source)
{
	struct sm750_drm_device *sdev = to_sm750_drm(crtc->dev);
	bool enable = sm750_crc_source_is_scanout(source);

	if (!enable && source && *source && strcmp(source, "none"))
		return -EINVAL;
	if (!enable) {
		sm750_crc_disable(sdev);
		return 0;
	}
	return sm750_crc_enable(sdev);
}

#endif /* LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0) */

static int sm750_pipe_enable_vblank(struct drm_simple_display_pipe *pipe)
{
	struct sm750_drm_device *sdev = pipe_to_sm750(pipe);
	const struct drm_display_mode *mode = &pipe->crtc.mode;
	unsigned long flags;
	u64 delay_ns;

	if (!mode->clock || !mode->htotal ||
	    mode->vdisplay >= mode->vtotal)
		return -EINVAL;

	spin_lock_irqsave(&sdev->vblank_lock, flags);
	sdev->vblank_line_ns = DIV_ROUND_CLOSEST_ULL(
		(u64)NSEC_PER_SEC * mode->htotal, (u64)mode->clock * 1000);
	sdev->vblank_frame_ns = sdev->vblank_line_ns * mode->vtotal;
	sdev->vblank_start = mode->vdisplay;
	sdev->vblank_vtotal = mode->vtotal;
	sdev->vblank_timer_enabled = true;
	delay_ns = sm750_vblank_first_delay_locked(sdev);
	hrtimer_start(&sdev->vblank_timer, ns_to_ktime(delay_ns),
		      HRTIMER_MODE_REL);
	spin_unlock_irqrestore(&sdev->vblank_lock, flags);
	return 0;
}

#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 0, 0)
static void sm750_pipe_disable_vblank(struct drm_simple_display_pipe *pipe)
{
	sm750_vblank_timer_stop(pipe_to_sm750(pipe), false);
}
#else
static int sm750_crtc_enable_vblank(struct drm_crtc *crtc)
{
	struct sm750_drm_device *sdev = to_sm750_drm(crtc->dev);

	return sm750_pipe_enable_vblank(&sdev->pipe);
}

static void sm750_crtc_disable_vblank(struct drm_crtc *crtc)
{
	sm750_vblank_timer_stop(to_sm750_drm(crtc->dev), false);
}
#endif

/*
 * The fbdev client's buffer is painted by fbcon, and fbcon only paints while
 * the foreground VT is in KD_TEXT: do_con_write() drops console output before
 * fbcon when vc_mode is KD_GRAPHICS. A module load on such a host therefore
 * leaves that buffer all-zero, the shadow path uploads the zeros faithfully
 * and the panel scans a blank frame with nothing else wrong. Sample the frame
 * being committed on a coarse grid so that precondition can be named once
 * instead of being mistaken for a display-path regression. Diagnostic only:
 * no caller changes what it uploads, keeps or fails.
 */
static bool sm750_shadow_frame_is_blank(struct sm750_drm_device *sdev,
					const struct drm_shadow_plane_state *shadow)
{
	unsigned int width = sdev->shadow_source_width;
	unsigned int height = sdev->shadow_source_height;
	unsigned int pitch = sdev->shadow_source_pitch;
	unsigned int x;
	unsigned int y;

	if (iosys_map_is_null(&shadow->data[0]) || width < 64 ||
	    height < 64 || pitch < width * sizeof(u32))
		return false;

	for (y = 0; y < height; y += 16) {
		for (x = 0; x < width; x += 16) {
			u32 pixel = 0;

			iosys_map_memcpy_from(&pixel, &shadow->data[0],
					      (size_t)y * pitch +
					      (size_t)x * sizeof(u32),
					      sizeof(pixel));
			if (pixel)
				return false;
		}
	}

	return true;
}

/*
 * Test-card fallback: when the pipe is about to scan a frame nobody has
 * painted, draw one instead of showing a black panel. The card is written
 * straight into the scanout window; a later client commit overwrites it
 * because sm750_pipe_update() stops the animation and re-uploads the client
 * frame. Two things move: a bouncing disc at test_pattern_anim_ms, and the
 * whole palette at test_pattern_period_ms, because a static card is the
 * burn-in pattern a kiosk panel hits overnight and a frozen disc is visible
 * at a glance. The animation repaints only the disc's bounding box, so a tick
 * costs kilobytes instead of a frame.
 */

/* EBU/analog test-bar values: white, yellow, cyan, green, magenta, red, blue. */
static const u32 sm750_test_pattern_bars[SM750_TEST_BAR_COUNT - 1] = {
	SM750_TEST_WHITE, SM750_TEST_YELLOW, SM750_TEST_CYAN,
	SM750_TEST_GREEN, SM750_TEST_MAGENTA, SM750_TEST_RED,
	SM750_TEST_BLUE,
};

/*
 * Everything the card needs to compute one pixel from first principles. The
 * background is a pure function of x, y and the palette phase, so any
 * rectangle can be recomputed without reading the screen: that is what lets
 * an animation tick erase the disc's old bounding box and draw the new one
 * instead of repainting the frame.
 */
struct sm750_test_pattern_ctx {
	u32 width;
	u32 height;
	u32 phase;
	u32 bar_bottom;
	u32 bar_w;
	u32 grid_x;
	u32 grid_y;
	u32 sweep_x;
	u32 cx;
	u32 cy;
	u32 radius;
	const u32 *half;
	bool disc;
	u32 disc_x;
	u32 disc_y;
	u32 disc_radius;
	u32 disc_colour;
};

/* Midpoint (Bresenham) circle, stored as a per-row outline half-width. */
static void sm750_test_pattern_circle(u32 radius, u32 *half)
{
	u32 x = 0;
	u32 y = radius;
	int err = 3 - 2 * (int)radius;

	while (y >= x) {
		half[y] = x;
		half[x] = y;
		x++;
		if (err > 0) {
			y--;
			err += 4 * ((int)x - (int)y) + 10;
		} else {
			err += 4 * (int)x + 6;
		}
	}
}

static void sm750_test_pattern_put(struct sm750_drm_device *sdev, void *line,
				   u32 x, u32 rgb)
{
	if (sdev->rgb565) {
		u32 r = (rgb >> 16) & 0xff;
		u32 g = (rgb >> 8) & 0xff;
		u32 b = rgb & 0xff;

		((u16 *)line)[x] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
	} else {
		((u32 *)line)[x] = rgb;
	}
}

/*
 * One background pixel: bars over the top two thirds, grayscale staircase
 * below them, then the grid, the sweep, the crosshair, the circle and the
 * inset border, each of which overwrites what came before. No text and no
 * font, so the card is identical in 16 and 32 bpp.
 */
static u32 sm750_test_pattern_pixel(const struct sm750_test_pattern_ctx *ctx,
				    unsigned int x, unsigned int y)
{
	u32 dx = x > ctx->cx ? x - ctx->cx : ctx->cx - x;
	u32 dy = y > ctx->cy ? y - ctx->cy : ctx->cy - y;
	u32 rgb;

	if (y < ctx->bar_bottom) {
		u32 slot = x / ctx->bar_w;

		if (slot >= SM750_TEST_BAR_COUNT - 1)
			rgb = SM750_TEST_BLACK;
		else
			rgb = sm750_test_pattern_bars[(slot + ctx->phase) %
					(SM750_TEST_BAR_COUNT - 1)];
	} else {
		u32 step = (x * SM750_TEST_GRAY_STEPS / ctx->width +
			    ctx->phase) % SM750_TEST_GRAY_STEPS;
		u32 v = step * 255 / (SM750_TEST_GRAY_STEPS - 1);

		rgb = (v << 16) | (v << 8) | v;
	}

	if (y < ctx->bar_bottom && (x % ctx->grid_x == 0 || y % ctx->grid_y == 0))
		rgb = SM750_TEST_WHITE;
	if ((x + ctx->width - ctx->sweep_x) % ctx->width < SM750_TEST_SWEEP_WIDTH)
		rgb = SM750_TEST_WHITE;
	if (dy <= 1 && dx <= ctx->radius)
		rgb = SM750_TEST_WHITE;
	if (dx <= 1 && dy <= ctx->cy)
		rgb = SM750_TEST_WHITE;
	if (dy < ctx->radius && ctx->half[dy] &&
	    (dx == ctx->half[dy] || dx + 1 == ctx->half[dy]))
		rgb = SM750_TEST_WHITE;
	if (y == 2 || y == ctx->height - 3 ||
	    x == 2 || x == ctx->width - 3)
		rgb = SM750_TEST_WHITE;

	return rgb;
}

/* Draw the disc over a background pixel: solid fill with a 2 px black edge so
 * it stays readable against the white bars and the white grid lines. */
static u32 sm750_test_pattern_disc_pixel(const struct sm750_test_pattern_ctx *ctx,
					 unsigned int x, unsigned int y, u32 rgb)
{
	u32 dx, dy, d2, inner;

	if (!ctx->disc)
		return rgb;
	dx = x > ctx->disc_x ? x - ctx->disc_x : ctx->disc_x - x;
	dy = y > ctx->disc_y ? y - ctx->disc_y : ctx->disc_y - y;
	d2 = dx * dx + dy * dy;
	if (d2 > ctx->disc_radius * ctx->disc_radius)
		return rgb;
	inner = ctx->disc_radius > 2 ? ctx->disc_radius - 2 : 0;
	if (d2 > inner * inner)
		return SM750_TEST_BLACK;

	return ctx->disc_colour;
}

/*
 * Recompute and write one rectangle of the card. A full-width rectangle is
 * padded to the scanout pitch; a partial one writes only its own span, which
 * is why an animation tick costs a bounding box and not a frame.
 */
static void sm750_test_pattern_rect(struct sm750_drm_device *sdev,
				    const struct sm750_test_pattern_ctx *ctx,
				    u32 x0, u32 y0, u32 x1, u32 y1)
{
	unsigned int pitch = sdev->scanout_pitch;
	unsigned int cpp = sdev->rgb565 ? sizeof(u16) : sizeof(u32);
	void *line = sdev->test_pattern_line;
	bool full;
	u32 x, y;

	if (!line || !pitch)
		return;
	x0 = min(x0, ctx->width);
	x1 = min(x1, ctx->width);
	y0 = min(y0, ctx->height);
	y1 = min(y1, ctx->height);
	if (x1 <= x0 || y1 <= y0)
		return;

	full = !x0 && x1 == ctx->width;
	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++)
			sm750_test_pattern_put(sdev, line, x,
				sm750_test_pattern_disc_pixel(ctx, x, y,
					sm750_test_pattern_pixel(ctx, x, y)));
		if (full) {
			if (pitch > ctx->width * cpp)
				memset((u8 *)line + ctx->width * cpp, 0,
				       pitch - ctx->width * cpp);
			memcpy_toio(sdev->vram + sdev->scanout_offset +
				    (u64)y * pitch, line, pitch);
		} else {
			memcpy_toio(sdev->vram + sdev->scanout_offset +
				    (u64)y * pitch + (u64)x0 * cpp,
				    (u8 *)line + (u64)x0 * cpp,
				    (u64)(x1 - x0) * cpp);
		}
	}

	/* The card bypasses the snapshot bookkeeping, so both snapshots are
	 * stale: a later client commit must re-upload every span. */
	sdev->shadow_source_snapshot_valid = false;
	sdev->rgb565_scanout_snapshot_valid = false;
}

/* Guards and geometry in one place: the full painter and the animation tick
 * must refuse the same frames for the same reasons. */
static bool sm750_test_pattern_ctx_init(struct sm750_drm_device *sdev,
					u32 width, u32 height,
					struct sm750_test_pattern_ctx *ctx)
{
	unsigned int pitch = sdev->scanout_pitch;
	unsigned int cpp = sdev->rgb565 ? sizeof(u16) : sizeof(u32);

	memset(ctx, 0, sizeof(*ctx));
	if (!sdev->test_pattern_line || !sdev->test_pattern_half || !pitch)
		return false;
	/* The softscaler rewrites every line on upload; a card here would be
	 * overwritten by the very path that produced the blank frame. */
	if (sdev->softscale_active)
		return false;
	if (width < SM750_TEST_MIN_WIDTH || height < SM750_TEST_MIN_HEIGHT)
		return false;
	if (pitch < width * cpp || pitch > SM750_TEST_LINE_BYTES)
		return false;
	if ((u64)pitch * height > sdev->vram_size - sdev->scanout_offset)
		return false;

	ctx->width = width;
	ctx->height = height;
	ctx->phase = sdev->test_pattern_phase;
	ctx->bar_bottom = height * 2 / 3;
	ctx->bar_w = max(width / SM750_TEST_BAR_COUNT, 1u);
	ctx->grid_x = max(width / 16, 1u);
	ctx->grid_y = max(ctx->bar_bottom / 12, 1u);
	ctx->sweep_x = (u32)(((u64)ctx->phase * max(width / 64, 1u)) % width);
	ctx->cx = width / 2;
	ctx->cy = ctx->bar_bottom / 2;
	ctx->radius = clamp_t(u32, min(width, ctx->bar_bottom) / 4, 16u,
			      SM750_DRM_MAX_HEIGHT / 4);
	memset(sdev->test_pattern_half, 0,
	       (ctx->radius + 1) * sizeof(*sdev->test_pattern_half));
	sm750_test_pattern_circle(ctx->radius, sdev->test_pattern_half);
	ctx->half = sdev->test_pattern_half;

	ctx->disc_radius = clamp_t(u32,
				height * SM750_TEST_DISC_PERCENT / 100,
				SM750_TEST_DISC_MIN_RADIUS,
				SM750_TEST_DISC_MAX_RADIUS);
	ctx->disc = true;
	ctx->disc_x = sdev->test_pattern_disc_x;
	ctx->disc_y = sdev->test_pattern_disc_y;
	ctx->disc_colour = sm750_test_pattern_bars[sdev->test_pattern_disc_colour %
					(SM750_TEST_BAR_COUNT - 1)];
	return true;
}

static void sm750_paint_test_pattern(struct sm750_drm_device *sdev, u32 width,
				     u32 height)
{
	struct sm750_test_pattern_ctx ctx;

	if (!sm750_test_pattern_ctx_init(sdev, width, height, &ctx))
		return;

	sm750_test_pattern_rect(sdev, &ctx, 0, 0, width, height);
}

/* Start the disc in the middle of the card, moving diagonally. Called once
 * per enable: a palette rotation must not move it. */
static void sm750_test_pattern_disc_reset(struct sm750_drm_device *sdev,
					  u32 width, u32 height)
{
	sdev->test_pattern_disc_x = width / 2;
	sdev->test_pattern_disc_y = height / 2;
	sdev->test_pattern_disc_dx = max_t(int,
			(int)height * SM750_TEST_DISC_SPEED_X / 1080, 1);
	sdev->test_pattern_disc_dy = max_t(int,
			(int)height * SM750_TEST_DISC_SPEED_Y / 1080, 1);
	sdev->test_pattern_disc_colour = 0;
	sdev->test_pattern_ticks = 0;
}

/*
 * Move the disc one tick and reflect it off the inner border. The centre is
 * clamped to the box the disc can occupy without touching the 1 px border
 * inset by 2 px, so neither a bounce nor a shrinking frame can push it off
 * the card.
 */
static void sm750_test_pattern_disc_move(struct sm750_drm_device *sdev,
					 const struct sm750_test_pattern_ctx *ctx)
{
	int reach = (int)ctx->disc_radius;
	int min_x = 3 + reach;
	int max_x = (int)ctx->width - 4 - reach;
	int min_y = 3 + reach;
	int max_y = (int)ctx->height - 4 - reach;
	bool bounced = false;

	if (max_x <= min_x || max_y <= min_y)
		return;

	sdev->test_pattern_disc_x += sdev->test_pattern_disc_dx;
	if (sdev->test_pattern_disc_x < min_x) {
		sdev->test_pattern_disc_x =
			min_x + (min_x - sdev->test_pattern_disc_x);
		sdev->test_pattern_disc_dx = -sdev->test_pattern_disc_dx;
		bounced = true;
	} else if (sdev->test_pattern_disc_x > max_x) {
		sdev->test_pattern_disc_x =
			max_x - (sdev->test_pattern_disc_x - max_x);
		sdev->test_pattern_disc_dx = -sdev->test_pattern_disc_dx;
		bounced = true;
	}
	sdev->test_pattern_disc_x = clamp_t(int, sdev->test_pattern_disc_x,
					    min_x, max_x);

	sdev->test_pattern_disc_y += sdev->test_pattern_disc_dy;
	if (sdev->test_pattern_disc_y < min_y) {
		sdev->test_pattern_disc_y =
			min_y + (min_y - sdev->test_pattern_disc_y);
		sdev->test_pattern_disc_dy = -sdev->test_pattern_disc_dy;
		bounced = true;
	} else if (sdev->test_pattern_disc_y > max_y) {
		sdev->test_pattern_disc_y =
			max_y - (sdev->test_pattern_disc_y - max_y);
		sdev->test_pattern_disc_dy = -sdev->test_pattern_disc_dy;
		bounced = true;
	}
	sdev->test_pattern_disc_y = clamp_t(int, sdev->test_pattern_disc_y,
					    min_y, max_y);

	/* A new colour per bounce, so a frozen colour means a frozen tick. */
	if (bounced)
		sdev->test_pattern_disc_colour++;
}

/* One animation frame: erase the old bounding box by recomputing its
 * background, then move and draw the disc. The palette does not change here,
 * so the erased pixels are exactly what the full painter would produce. */
static void sm750_test_pattern_disc_tick(struct sm750_drm_device *sdev,
					 struct sm750_test_pattern_ctx *ctx)
{
	struct sm750_test_pattern_ctx erase = *ctx;
	u32 reach = ctx->disc_radius + 1;
	u32 old_x = sdev->test_pattern_disc_x;
	u32 old_y = sdev->test_pattern_disc_y;
	u32 new_x, new_y;

	erase.disc = false;
	sm750_test_pattern_rect(sdev, &erase,
				old_x > reach ? old_x - reach : 0,
				old_y > reach ? old_y - reach : 0,
				min(old_x + reach + 1, ctx->width),
				min(old_y + reach + 1, ctx->height));

	sm750_test_pattern_disc_move(sdev, ctx);
	ctx->disc = true;
	ctx->disc_x = sdev->test_pattern_disc_x;
	ctx->disc_y = sdev->test_pattern_disc_y;
	ctx->disc_colour = sm750_test_pattern_bars[sdev->test_pattern_disc_colour %
					(SM750_TEST_BAR_COUNT - 1)];
	new_x = ctx->disc_x;
	new_y = ctx->disc_y;
	sm750_test_pattern_rect(sdev, ctx,
				new_x > reach ? new_x - reach : 0,
				new_y > reach ? new_y - reach : 0,
				min(new_x + reach + 1, ctx->width),
				min(new_y + reach + 1, ctx->height));
}

static unsigned int sm750_test_pattern_period(struct sm750_drm_device *sdev)
{
	unsigned int period = READ_ONCE(test_pattern_period_ms);

	if (!period)
		return 0;
	if (period < SM750_TEST_PERIOD_MIN_MS || period > SM750_TEST_PERIOD_MAX_MS) {
		unsigned int clamped = clamp_t(unsigned int, period,
					SM750_TEST_PERIOD_MIN_MS,
					SM750_TEST_PERIOD_MAX_MS);

		drm_info_once(&sdev->drm,
			      "test_pattern_period_ms=%u is outside %u-%u ms, clamped to %u\n",
			      period, SM750_TEST_PERIOD_MIN_MS,
			      SM750_TEST_PERIOD_MAX_MS, clamped);
		period = clamped;
	}

	return period;
}

static unsigned int sm750_test_pattern_anim(struct sm750_drm_device *sdev)
{
	unsigned int anim = READ_ONCE(test_pattern_anim_ms);

	if (!anim)
		return 0;
	if (anim < SM750_TEST_ANIM_MIN_MS || anim > SM750_TEST_ANIM_MAX_MS) {
		unsigned int clamped = clamp_t(unsigned int, anim,
					SM750_TEST_ANIM_MIN_MS,
					SM750_TEST_ANIM_MAX_MS);

		drm_info_once(&sdev->drm,
			      "test_pattern_anim_ms=%u is outside %u-%u ms, clamped to %u\n",
			      anim, SM750_TEST_ANIM_MIN_MS,
			      SM750_TEST_ANIM_MAX_MS, clamped);
		anim = clamped;
	}

	return anim;
}

static void sm750_test_pattern_cancel(struct sm750_drm_device *sdev)
{
	sdev->test_pattern_active = false;
	cancel_delayed_work_sync(&sdev->test_pattern_work);
}

static void sm750_test_pattern_work(struct work_struct *work)
{
	struct sm750_drm_device *sdev =
		container_of(to_delayed_work(work), struct sm750_drm_device,
			     test_pattern_work);
	unsigned int anim = sm750_test_pattern_anim(sdev);
	unsigned int period = sm750_test_pattern_period(sdev);
	unsigned int delay = anim ? anim : period;
	bool painted = false;

	mutex_lock(&sdev->mode_lock);
	/*
	 * Both conditions are set and cleared under mode_lock: a client
	 * commit or a pipe disable turns test_pattern_active off first, so a
	 * tick that loses the race paints nothing. The card is repainted in
	 * place rather than through the staged flip because
	 * sm750_present_staged_frame() takes mode_lock itself and assumes the
	 * shadow upload bookkeeping; one torn frame every few seconds is a
	 * cheaper trade than a new lock order on a diagnostic path.
	 */
	if (sdev->test_pattern_active && sdev->scanout_pitch &&
	    !READ_ONCE(sdev->crc_enabled)) {
		struct sm750_test_pattern_ctx ctx;

		if (sm750_test_pattern_ctx_init(sdev,
						sdev->test_pattern_width,
						sdev->test_pattern_height,
						&ctx)) {
			sdev->test_pattern_ticks++;
			/*
			 * The palette rotation keeps its own cadence, counted
			 * in ticks so a clamped animation period cannot drift
			 * it: integer arithmetic only, no jiffies.
			 */
			if (!anim ||
			    (period && (u64)sdev->test_pattern_ticks * anim >=
				       period)) {
				sdev->test_pattern_ticks = 0;
				sdev->test_pattern_phase++;
				/* The card just changed, so rebuild the geometry
				 * the erased rectangle would otherwise use. */
				if (sm750_test_pattern_ctx_init(sdev,
						sdev->test_pattern_width,
						sdev->test_pattern_height,
						&ctx))
					sm750_test_pattern_rect(sdev, &ctx, 0, 0,
								ctx.width,
								ctx.height);
			} else {
				sm750_test_pattern_disc_tick(sdev, &ctx);
			}
			painted = true;
		}
	}
	mutex_unlock(&sdev->mode_lock);

	if (painted && delay)
		schedule_delayed_work(&sdev->test_pattern_work,
				      msecs_to_jiffies(delay));
}

/*
 * A scanout CRC source disables the card for its whole lifetime: an armed
 * consumer is asking for a frame that does not change, and "always" is a
 * module option, not a reason to override that.
 */
static bool sm750_test_pattern_should_paint(struct sm750_drm_device *sdev,
					    bool blank)
{
	if (READ_ONCE(sdev->crc_enabled))
		return false;
	switch (sdev->test_pattern_mode) {
	case SM750_TEST_PATTERN_ALWAYS:
		return true;
	case SM750_TEST_PATTERN_AUTO:
		break;
	default:
		return false;
	}
	/*
	 * An all-black frame from a userspace master is a legitimate picture
	 * (a desktop, a screensaver, the CRC harness' own black buffer), not
	 * an unpainted buffer. The in-kernel fbdev client never becomes a
	 * master, so it still gets the card.
	 */
	return !READ_ONCE(sdev->drm.master) && blank;
}

static void sm750_pipe_enable(struct drm_simple_display_pipe *pipe,
			      struct drm_crtc_state *crtc_state,
			      struct drm_plane_state *plane_state)
{
	struct sm750_drm_device *sdev = pipe_to_sm750(pipe);
	struct drm_rect damage;
	u32 pitch;
	u32 offset;
	u64 frame_size;
	u8 cpp;
	int ret;
	/* Once per module load: the precondition does not vary per modeset. */
	static bool blank_frame_reported;

	sdev->mode_stage = SM750_MODE_STAGE_NONE;
	sdev->enable_failed = false;
	if (sdev->shadow_scanout) {
		sm750_async_quiesce(sdev);
		sdev->backbuffer_ready = false;
		sdev->backbuffer_available = false;
		sdev->backbuffer_mirror = false;
		/*
		 * Not a reset of stale device state: these two become the
		 * front buffer that the full-frame upload below fills and
		 * that sm750_program_mode() points PANEL_FB_ADDRESS at.
		 * The test card and its bounds check address VRAM through
		 * scanout_offset too, so all three must agree: never carry
		 * the previous offset across the enable.
		 */
		sdev->scanout_offset = 0;
		sdev->shadow_upload_offset = 0;
		sdev->softscale_active = sm750_mode_is_softscaled(
			&crtc_state->adjusted_mode);
		sdev->softscale_source_width = sdev->softscale_active ?
			crtc_state->adjusted_mode.hdisplay : 0;
		sdev->shadow_source_width = crtc_state->adjusted_mode.hdisplay;
		sdev->shadow_source_height = crtc_state->adjusted_mode.vdisplay;
		sdev->shadow_source_pitch = plane_state->fb ?
			plane_state->fb->pitches[0] : 0;
		sdev->shadow_source_snapshot_valid = false;
		sdev->rgb565_scanout_snapshot_valid = false;
		if (sdev->softscale_active &&
		    sdev->softscale_source_width != 2560) {
			ret = sm750_dither_scale_map_init(sdev->dither_scale_map,
					sdev->softscale_source_width, 2048);
			if (ret)
				goto fail;
		}
		cpp = sdev->rgb565 ? sizeof(u16) : sizeof(u32);
		pitch = ALIGN((sdev->softscale_active ? 2048 :
			crtc_state->adjusted_mode.hdisplay) * cpp,
			      SM750_DRM_LINE_ALIGN);
		sdev->scanout_pitch = pitch;
		sdev->dma_batch_limit = 16 * SM750_DRM_DMA_BATCH_ROW_SIZE;
		frame_size = (u64)pitch * crtc_state->adjusted_mode.vdisplay;
		if (frame_size <= U32_MAX) {
			sdev->scanout_frame_size = frame_size;
			sdev->backbuffer_offset = ALIGN(sdev->scanout_frame_size,
						       SM750_DRM_LINE_ALIGN);
			sdev->backbuffer_available = backbuffer_staging &&
				sdev->backbuffer_offset <= sdev->cursor_offset &&
				sdev->scanout_frame_size <=
					sdev->cursor_offset - sdev->backbuffer_offset;
		}
		offset = 0;
		damage.x1 = 0;
		damage.y1 = 0;
		damage.x2 = crtc_state->adjusted_mode.hdisplay;
		damage.y2 = crtc_state->adjusted_mode.vdisplay;
		sm750_shadow_rect(sdev, plane_state, &damage);
		sm750_async_seed_source(sdev, plane_state);
	} else {
		ret = sm750_scanout_offset(plane_state->fb, &offset);
		if (ret)
			goto fail;
		pitch = plane_state->fb->pitches[0];
		cpp = sizeof(u32);
		frame_size = (u64)pitch * crtc_state->adjusted_mode.vdisplay;
		if (!frame_size || frame_size > U32_MAX) {
			ret = -EINVAL;
			goto fail;
		}
		/* 64-bit: pitch * vdisplay is already promoted, offset is not. */
		if ((u64)offset + frame_size > sdev->vram_size) {
			drm_err(&sdev->drm,
				"scanout window %#x+%llu runs past %#x bytes of VRAM\n",
				offset, frame_size, sdev->vram_size);
			ret = -EINVAL;
			goto fail;
		}
		sdev->scanout_offset = offset;
		sdev->scanout_pitch = pitch;
		sdev->scanout_frame_size = frame_size;
	}
	mutex_lock(&sdev->mode_lock);
	ret = sm750_program_mode(sdev, &crtc_state->adjusted_mode,
				 pitch, offset, cpp);
	mutex_unlock(&sdev->mode_lock);
	if (!ret) {
		bool blank = false;
		unsigned int period;

		sdev->backbuffer_ready = sdev->backbuffer_available;
		if (sdev->backbuffer_ready)
			drm_info(&sdev->drm,
				 "full-frame backbuffer staging enabled (%u bytes per buffer)\n",
				 sdev->scanout_frame_size);
		/* One sample, two consumers: the A31/A33 diagnostic and the
		 * test_pattern=auto paint decision below. */
		if (sdev->shadow_scanout && plane_state->fb)
			blank = sm750_shadow_frame_is_blank(sdev,
					to_drm_shadow_plane_state(plane_state));
		if (blank && !blank_frame_reported) {
			blank_frame_reported = true;
			drm_info(&sdev->drm,
				 "console framebuffer is blank: the panel now scans a frame nobody has painted (is the foreground VT in KD_TEXT?)\n");
		}
		/*
		 * Fallback for a foreground VT in KD_GRAPHICS with no
		 * producer: paint a card so the panel is not simply dark. Any
		 * later client commit overwrites it (sm750_pipe_update()
		 * cancels the rotation first).
		 */
		if (sm750_test_pattern_should_paint(sdev, blank)) {
			sdev->test_pattern_width =
				crtc_state->adjusted_mode.hdisplay;
			sdev->test_pattern_height =
				crtc_state->adjusted_mode.vdisplay;
			sm750_test_pattern_disc_reset(sdev,
						      sdev->test_pattern_width,
						      sdev->test_pattern_height);
			sm750_paint_test_pattern(sdev,
						 sdev->test_pattern_width,
						 sdev->test_pattern_height);
			sdev->test_pattern_active = true;
			drm_info(&sdev->drm,
				 "painted a test card: no client has produced a frame (test_pattern=%s)\n",
				 sm750_test_pattern_names[sdev->test_pattern_mode]);
			period = sm750_test_pattern_anim(sdev);
			if (!period)
				period = sm750_test_pattern_period(sdev);
			if (period)
				schedule_delayed_work(&sdev->test_pattern_work,
						      msecs_to_jiffies(period));
		}
		drm_crtc_vblank_on(&pipe->crtc);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
		/* After vblank_on(): the re-arm targets the rebuilt count. */
		sm750_crc_resume(sdev);
#endif
		sm750_arm_vblank_event(pipe);
		return;
	}
fail:
	sm750_async_quiesce(sdev);
	sm750_test_pattern_cancel(sdev);
	sdev->softscale_active = false;
	sdev->softscale_source_width = 0;
	sdev->shadow_source_width = 0;
	sdev->shadow_source_height = 0;
	sdev->shadow_source_pitch = 0;
	sdev->shadow_source_snapshot_valid = false;
	sdev->rgb565_scanout_snapshot_valid = false;
	sdev->backbuffer_available = false;
	sdev->backbuffer_ready = false;
	sdev->backbuffer_mirror = false;
	sdev->shadow_upload_offset = 0;
	drm_err(&sdev->drm,
		"failed to enable HDMI mode: %d at stage %s (pipe left down; commit event not armed)\n",
		ret, sm750_mode_stage_name(sdev->mode_stage));
	/*
	 * The register state answers the ranked hypotheses in the A32 RCA:
	 * a still-running raster (TIMING/PLANE set in PANEL_DISPLAY_CTRL),
	 * a PLL that never left the old mode, a power/clock gate left off, or
	 * a display control that latched but never reached the visible scan.
	 * All four print through drm_err, so no dynamic debug needed.
	 */
	drm_err(&sdev->drm,
		"enable-fail state: PANEL_DISPLAY_CTRL=%#08x PANEL_PLL_CTRL=%#08x SYSTEM_CTRL=%#08x PANEL_CURRENT_LINE=%#08x\n",
		peek32(PANEL_DISPLAY_CTRL), peek32(PANEL_PLL_CTRL),
		peek32(SYSTEM_CTRL), peek32(PANEL_CURRENT_LINE));
	/*
	 * Leave the pipe marked down instead of faking health. vblank
	 * accounting and the CRC source stay off, and the event this commit
	 * carries is not armed: drm_atomic_helper_commit_hw_done() will warn
	 * and the commit will time out, which is visible, unlike a
	 * flip-complete for a panel that never came up. enable_failed makes
	 * the next commit retry the enable rather than trust the core's view
	 * that this CRTC is running.
	 */
	sdev->enable_failed = true;
}

static void sm750_pipe_update(struct drm_simple_display_pipe *pipe,
				      struct drm_plane_state *old_plane_state)
{
	struct sm750_drm_device *sdev = pipe_to_sm750(pipe);
	struct drm_plane_state *state = pipe->plane.state;
	struct drm_atomic_helper_damage_iter iter;
	struct drm_rect rects[SM750_DRM_MAX_DAMAGE_RECTS];
	struct drm_rect damage;
	unsigned int rect_count = 0;
	u32 offset;

	/*
	 * The last modeset's hardware enable failed and the core still
	 * believes the pipe is on. A later commit retries the enable here;
	 * a modeset commit re-runs it through the core anyway.
	 */
	if (sdev->enable_failed && !pipe->crtc.state->mode_changed)
		sm750_pipe_enable(pipe, pipe->crtc.state, state);

	/*
	 * A real client frame is arriving: stop the test-card rotation before
	 * any upload so a tick can never overwrite live pixels. The flag is
	 * cleared first, so a tick that already lost the race paints nothing.
	 * There is deliberately no one-shot skip here: planes are committed
	 * before modeset enables (drm_atomic_helper_commit_tail()), so a flag
	 * set by pipe_enable() would swallow the CLIENT's first frame, not the
	 * enabling commit's own upload.
	 */
	if (sdev->test_pattern_active)
		sm750_test_pattern_cancel(sdev);

	/*
	 * A disable clears the scanout geometry and the upload paths below
	 * multiply by the pitch. Never upload through a cleared window: the
	 * enabling pipe_enable() reprograms the mode and uploads the frame.
	 */
	if (!sdev->scanout_pitch || !sdev->scanout_frame_size)
		goto event;

	if (sdev->shadow_scanout) {
		drm_atomic_helper_damage_iter_init(&iter, old_plane_state, state);
		drm_atomic_for_each_plane_damage(&iter, &damage)
			sm750_damage_add_bounded(rects, &rect_count, &damage);
		if (rect_count && sm750_async_queue_damage(sdev, state, rects,
							 rect_count))
			goto event;
		if (rect_count) {
			bool staged;

			mutex_lock(&sdev->shadow_lock);
			staged = sm750_begin_staged_frame(sdev, rects,
							  rect_count);
			sm750_process_damage_rects(sdev, state, rects, rect_count);
			sm750_shadow_finish_uploads(sdev);
			if (staged && !sm750_present_staged_frame(sdev)) {
				/* Recover to identical buffers before more damage. */
				sm750_process_damage_rects(sdev, state, rects,
							   rect_count);
				sm750_shadow_finish_uploads(sdev);
			}
			mutex_unlock(&sdev->shadow_lock);
		}
	} else if (state->fb &&
		 !sm750_scanout_offset(state->fb, &offset)) {
		sdev->scanout_offset = offset;
		poke32(SM750_DRM_FB_ADDRESS, SM750_DRM_FB_ADDRESS_STATUS |
		       (offset & SM750_DRM_FB_ADDRESS_MASK));
	}
event:
	if (!sdev->enable_failed && !pipe->crtc.state->mode_changed)
		sm750_arm_vblank_event(pipe);
}

static void sm750_pipe_disable(struct drm_simple_display_pipe *pipe)
{
	struct sm750_drm_device *sdev = pipe_to_sm750(pipe);
	int ret;

	sm750_async_quiesce(sdev);
	sm750_test_pattern_cancel(sdev);
	sm750_crc_suspend(sdev);
	drm_crtc_vblank_off(&pipe->crtc);
	sm750_send_vblank_event(pipe);
	if (sdev->hardware_cursor) {
		mutex_lock(&sdev->cursor_lock);
		sm750_cursor_disable_locked(sdev);
		mutex_unlock(&sdev->cursor_lock);
	}
	mutex_lock(&sdev->mode_lock);
	sm750_sii902x_disable_link();
	/*
	 * A timed-out panel-off used to be invisible: the enable path that
	 * follows in the same commit then inherits a raster that is still
	 * running and has to finish the transition itself (A32).
	 */
	ret = ddk750_set_display_control(SM750_DRM_CONTROLLER, false);
	if (ret)
		drm_warn(&sdev->drm,
			 "panel did not acknowledge display-off: %d (PANEL_DISPLAY_CTRL=%#08x)\n",
			 ret, peek32(PANEL_DISPLAY_CTRL));
	mutex_unlock(&sdev->mode_lock);
	sdev->softscale_active = false;
	sdev->softscale_source_width = 0;
	sdev->shadow_source_width = 0;
	sdev->shadow_source_height = 0;
	sdev->shadow_source_pitch = 0;
	sdev->shadow_source_snapshot_valid = false;
	sdev->rgb565_scanout_snapshot_valid = false;
	sdev->backbuffer_available = false;
	sdev->backbuffer_ready = false;
	sdev->backbuffer_mirror = false;
	sdev->shadow_upload_offset = 0;
	/*
	 * The mode is zeroed by this disable commit; a surviving pitch would
	 * make the debugfs header print a dead 0x0 window with a live pitch
	 * and would let an upload multiply by the wrong geometry. Clear both
	 * members with the rest of the bookkeeping; every upload consumer
	 * guards a zero pitch (pipe_update refuses the upload until the next
	 * enable reprograms the mode).
	 */
	sdev->scanout_pitch = 0;
	sdev->scanout_frame_size = 0;
	/* The panel may never have come up; retry from a clean state next time. */
	sdev->enable_failed = false;
}

static enum drm_mode_status
sm750_pipe_mode_valid(struct drm_simple_display_pipe *pipe,
			      const struct drm_display_mode *mode)
{
	return sm750_mode_valid(mode, pipe_to_sm750(pipe)->vram_size);
}

static const struct drm_simple_display_pipe_funcs sm750_pipe_funcs = {
	.mode_valid = sm750_pipe_mode_valid,
	.enable = sm750_pipe_enable,
	.disable = sm750_pipe_disable,
	.check = sm750_pipe_check,
	.update = sm750_pipe_update,
#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 0, 0)
	.enable_vblank = sm750_pipe_enable_vblank,
	.disable_vblank = sm750_pipe_disable_vblank,
#endif
	.prepare_fb = sm750_pipe_prepare_fb,
	.cleanup_fb = sm750_pipe_cleanup_fb,
};

static const struct drm_simple_display_pipe_funcs sm750_shadow_pipe_funcs = {
	.mode_valid = sm750_pipe_mode_valid,
	.enable = sm750_pipe_enable,
	.disable = sm750_pipe_disable,
	.check = sm750_pipe_check,
	.update = sm750_pipe_update,
	.prepare_fb = sm750_shadow_pipe_prepare_fb,
#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 0, 0)
	.enable_vblank = sm750_pipe_enable_vblank,
	.disable_vblank = sm750_pipe_disable_vblank,
#endif
	DRM_GEM_SIMPLE_DISPLAY_PIPE_SHADOW_PLANE_FUNCS,
};

#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
static const struct drm_crtc_funcs sm750_crtc_funcs = {
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 3, 0)
	.atomic_create_state = drm_atomic_helper_crtc_create_state,
#else
	.reset = drm_atomic_helper_crtc_reset,
#endif
	.destroy = drm_crtc_cleanup,
	.set_config = drm_atomic_helper_set_config,
	.page_flip = drm_atomic_helper_page_flip,
	.atomic_duplicate_state = drm_atomic_helper_crtc_duplicate_state,
	.atomic_destroy_state = drm_atomic_helper_crtc_destroy_state,
	.enable_vblank = sm750_crtc_enable_vblank,
	.disable_vblank = sm750_crtc_disable_vblank,
	.get_crc_sources = sm750_crtc_get_crc_sources,
	.verify_crc_source = sm750_crtc_verify_crc_source,
	.set_crc_source = sm750_crtc_set_crc_source,
};
#endif

/* This device's simple display pipe advertises DRM_FORMAT_MOD_LINEAR alone:
 * the format_modifiers argument of drm_simple_display_pipe_init is NULL, which
 * pins the plane to the linear modifier. KWin 6.7.5 submits a framebuffer with
 * a modifier it cannot match against that list, AddFB2 fails with EINVAL and
 * the panel stops scanning, so the device withdraws the modifier capability -
 * see the fb_modifiers_not_supported assignment in sm750_modeset_init(). The
 * flag lives on struct drm_mode_config, not on this funcs struct. */
static const struct drm_mode_config_funcs sm750_mode_config_funcs = {
	.fb_create = drm_gem_fb_create,
	.atomic_check = drm_atomic_helper_check,
	.atomic_commit = drm_atomic_helper_commit,
};

static const struct drm_mode_config_funcs sm750_shadow_mode_config_funcs = {
	.fb_create = drm_gem_fb_create_with_dirty,
	.atomic_check = drm_atomic_helper_check,
	.atomic_commit = drm_atomic_helper_commit,
};

DEFINE_DRM_GEM_FOPS(sm750_drm_fops);

/*
 * MMIO snapshot for bring-up reports. Interrupt status and raw interrupt
 * registers are deliberately omitted: reading them can acknowledge or clear
 * state, which would make dumps taken around a single modeset incomparable.
 * The file is inert until read and never writes to the device.
 */
static const struct sm750_reg_dump {
	const char *name;
	u32 offset;
} sm750_reg_dump_registers[] = {
	{ "SYSTEM_CTRL", SYSTEM_CTRL },
	{ "MISC_CTRL", MISC_CTRL },
	{ "GPIO_MUX", GPIO_MUX },
	{ "CURRENT_GATE", CURRENT_GATE },
	{ "MODE0_GATE", MODE0_GATE },
	{ "MODE1_GATE", MODE1_GATE },
	{ "POWER_MODE_CTRL", POWER_MODE_CTRL },
	{ "DEVICE_ID", DEVICE_ID },
	{ "PANEL_PLL_CTRL", PANEL_PLL_CTRL },
	{ "CRT_PLL_CTRL", CRT_PLL_CTRL },
	{ "MXCLK_PLL_CTRL", MXCLK_PLL_CTRL },
	{ "VGA_CONFIGURATION", VGA_CONFIGURATION },
	{ "GPIO_DATA", GPIO_DATA },
	{ "GPIO_DATA_DIRECTION", GPIO_DATA_DIRECTION },
	{ "GPIO_INTERRUPT_SETUP", GPIO_INTERRUPT_SETUP },
	{ "PANEL_DISPLAY_CTRL", PANEL_DISPLAY_CTRL },
	{ "PANEL_PAN_CTRL", PANEL_PAN_CTRL },
	{ "PANEL_COLOR_KEY", PANEL_COLOR_KEY },
	{ "PANEL_FB_ADDRESS", PANEL_FB_ADDRESS },
	{ "PANEL_FB_WIDTH", PANEL_FB_WIDTH },
	{ "PANEL_WINDOW_WIDTH", PANEL_WINDOW_WIDTH },
	{ "PANEL_WINDOW_HEIGHT", PANEL_WINDOW_HEIGHT },
	{ "PANEL_PLANE_TL", PANEL_PLANE_TL },
	{ "PANEL_PLANE_BR", PANEL_PLANE_BR },
	{ "PANEL_HORIZONTAL_TOTAL", PANEL_HORIZONTAL_TOTAL },
	{ "PANEL_HORIZONTAL_SYNC", PANEL_HORIZONTAL_SYNC },
	{ "PANEL_VERTICAL_TOTAL", PANEL_VERTICAL_TOTAL },
	{ "PANEL_VERTICAL_SYNC", PANEL_VERTICAL_SYNC },
	{ "PANEL_CURRENT_LINE", PANEL_CURRENT_LINE },
	{ "PANEL_HWC_ADDRESS", PANEL_HWC_ADDRESS },
	{ "PANEL_HWC_LOCATION", PANEL_HWC_LOCATION },
	{ "PANEL_HWC_COLOR_12", PANEL_HWC_COLOR_12 },
	{ "PANEL_HWC_COLOR_3", PANEL_HWC_COLOR_3 },
	{ "VIDEO_DISPLAY_CTRL", VIDEO_DISPLAY_CTRL },
	{ "VIDEO_FB_0_ADDRESS", VIDEO_FB_0_ADDRESS },
	{ "VIDEO_FB_WIDTH", VIDEO_FB_WIDTH },
	{ "VIDEO_FB_0_LAST_ADDRESS", VIDEO_FB_0_LAST_ADDRESS },
	{ "VIDEO_PLANE_TL", VIDEO_PLANE_TL },
	{ "VIDEO_PLANE_BR", VIDEO_PLANE_BR },
	{ "ALPHA_DISPLAY_CTRL", ALPHA_DISPLAY_CTRL },
	{ "ALPHA_FB_ADDRESS", ALPHA_FB_ADDRESS },
	{ "CRT_DISPLAY_CTRL", CRT_DISPLAY_CTRL },
	{ "CRT_FB_ADDRESS", CRT_FB_ADDRESS },
	{ "CRT_FB_WIDTH", CRT_FB_WIDTH },
	{ "CRT_HORIZONTAL_TOTAL", CRT_HORIZONTAL_TOTAL },
	{ "CRT_CURRENT_LINE", CRT_CURRENT_LINE },
	{ "CRT_MONITOR_DETECT", CRT_MONITOR_DETECT },
	{ "DE_STATE1", DE_STATE1 },
	{ "DE_STATE2", DE_STATE2 },
};

static int sm750_regs_show(struct seq_file *m, void *unused)
{
	struct drm_device *drm = m->private;
	struct sm750_drm_device *sdev = to_sm750_drm(drm);
	size_t i;
	int idx;

	if (!drm_dev_enter(drm, &idx))
		return -ENODEV;

	seq_printf(m, "# %s register dump, %zu registers, read-only\n",
		   SM750_DRM_NAME, ARRAY_SIZE(sm750_reg_dump_registers));
	for (i = 0; i < ARRAY_SIZE(sm750_reg_dump_registers); i++)
		seq_printf(m, "0x%06x %-28s 0x%08x\n",
			   sm750_reg_dump_registers[i].offset,
			   sm750_reg_dump_registers[i].name,
			   readl(sdev->regs + sm750_reg_dump_registers[i].offset));

	drm_dev_exit(idx);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(sm750_regs);

/*
 * Full bounded-window readback with a summary. seq_file, so the whole dump is
 * readable in one read; the summary is over the same bytes the CRC source
 * hashes, which is how userspace cross-checks the two paths.
 */
static int sm750_scanout_show(struct seq_file *m, void *unused)
{
	struct drm_device *drm = m->private;
	struct sm750_drm_device *sdev = to_sm750_drm(drm);
	const char *missing = NULL;
	u8 line[16];
	size_t length;
	size_t nonzero = 0;
	size_t done = 0;
	u32 offset;
	u32 crc;
	int idx;

	if (!drm_dev_enter(drm, &idx))
		return -ENODEV;
	if (!sdev->pipe.crtc.mode.hdisplay || !sdev->pipe.crtc.mode.vdisplay)
		seq_printf(m, "# %s scanout readback, no active mode\n",
			   SM750_DRM_NAME);
	else
		seq_printf(m, "# %s scanout readback, %ux%u pitch %u\n",
			   SM750_DRM_NAME, sdev->pipe.crtc.mode.hdisplay,
			   sdev->pipe.crtc.mode.vdisplay, sdev->scanout_pitch);
	if (!sm750_crc_region(sdev, &offset, &length, &missing)) {
		seq_printf(m, "# no scanout buffer programmed: %s missing\n",
			   missing ? missing : "reason");
		drm_dev_exit(idx);
		return 0;
	}
	crc = sm750_scanout_crc32(sdev, offset, length, &nonzero);
	seq_printf(m, "offset %u\n", offset);
	seq_printf(m, "length %zu\n", length);
	seq_printf(m, "nonzero %zu\n", nonzero);
	seq_printf(m, "crc32 0x%08x\n", crc);
	while (done < length) {
		size_t n = min_t(size_t, length - done, sizeof(line));
		size_t i;

		memcpy_fromio(line, sdev->vram + offset + done, n);
		seq_printf(m, "%08zx", done);
		for (i = 0; i < n; i++)
			seq_printf(m, " %02x", line[i]);
		seq_putc(m, '\n');
		done += n;
	}
	drm_dev_exit(idx);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(sm750_scanout);

static void sm750_regs_debugfs_add(struct drm_minor *minor)
{
	debugfs_create_file("regs", 0444, minor->debugfs_root, minor->dev,
			    &sm750_regs_fops);
	debugfs_create_file("sm750_scanout", 0444, minor->debugfs_root,
			    minor->dev, &sm750_scanout_fops);
}

/*
 * Shadow driver: no vram_mm helper, so the register snapshot and the scanout
 * readback are the only files added.
 */
static void sm750_debugfs_init(struct drm_minor *minor)
{
	sm750_regs_debugfs_add(minor);
}

static void sm750_vram_debugfs_init(struct drm_minor *minor)
{
	drm_vram_mm_debugfs_init(minor);
	sm750_regs_debugfs_add(minor);
}

static int sm750_dumb_create(struct drm_file *file, struct drm_device *drm,
			     struct drm_mode_create_dumb *args)
{
	return drm_gem_vram_fill_create_dumb(file, drm, 0,
					     SM750_DRM_LINE_ALIGN, args);
}

/* A render node is advertised so that userspace which refuses a card-only
 * device can still obtain a file descriptor: kwin 6.7.5 skips every DRM
 * device whose node set has no render node. SM750 has no 3D engine, so this
 * node carries only dumb-buffer and PRIME/dma-buf primitives plus the core
 * ioctls marked render-allowed; it is not a claim of GL capability, and Mesa
 * ships no SM750 driver (kms_swrast only). DRIVER_MODESET stays: a render
 * node without it would cost the card its modesetting. Both driver_features
 * lines are pinned by tests/check-render-node.sh.
 */
static const struct drm_driver sm750_drm_driver = {
	.driver_features = DRIVER_GEM | DRIVER_MODESET | DRIVER_ATOMIC | DRIVER_RENDER,
	.fops = &sm750_drm_fops,
	.debugfs_init = sm750_vram_debugfs_init,
	.dumb_create = sm750_dumb_create,
	.dumb_map_offset = drm_gem_ttm_dumb_map_offset,
	DRM_FBDEV_TTM_DRIVER_OPS,
	.name = SM750_DRM_NAME,
	.desc = "SM750G10 SiI9024A HDMI DRM driver",
	.major = DRIVER_MAJOR,
	.minor = DRIVER_MINOR,
	.patchlevel = DRIVER_PATCHLEVEL,
};

/* Render node: same rationale as the block above sm750_drm_driver. */
static const struct drm_driver sm750_shadow_drm_driver = {
	.driver_features = DRIVER_GEM | DRIVER_MODESET | DRIVER_ATOMIC | DRIVER_RENDER,
	.fops = &sm750_drm_fops,
	.debugfs_init = sm750_debugfs_init,
	DRM_GEM_SHMEM_DRIVER_OPS,
	DRM_FBDEV_SHMEM_DRIVER_OPS,
	.name = SM750_DRM_NAME,
	.desc = "SM750G10 SiI9024A HDMI DRM shadow driver",
	.major = DRIVER_MAJOR,
	.minor = DRIVER_MINOR,
	.patchlevel = DRIVER_PATCHLEVEL,
};

static int sm750_hw_init(struct sm750_drm_device *sdev, bool reset_memory)
{
	struct initchip_param init = {
		.power_mode = 0,
		.chip_clock = 290,
		.mem_clock = 290,
		.master_clock = 96,
		.set_all_eng_off = 1,
		.reset_memory = reset_memory,
	};
	u32 value;

	mmio750 = sdev->regs;
	sm750_set_chip_type(sdev->pdev->device, sdev->pdev->revision);
	sdev->vram_size = ddk750_get_vm_size();
	if (!sdev->vram_size || sdev->vram_size > pci_resource_len(sdev->pdev, 0))
		return -ENODEV;
	ddk750_init_hw(&init);
	/*
	 * A resume reinitialises the chip, and the reset clears INT_MASK while
	 * sdev->dma_irq_enabled still says the DMA1 completion IRQ is armed.
	 * Re-arm the bit the driver believes in, or the first shadow upload
	 * after resume manufactures a timeout. A sticky shadow_dma_broken is
	 * left alone: the timeout that set it was real.
	 */
	if (sdev->dma_irq_enabled)
		poke32(INT_MASK, peek32(INT_MASK) | INT_MASK_DMA1);

	value = peek32(MISC_CTRL) | MISC_CTRL_DAC_POWER_OFF;
	poke32(MISC_CTRL, value);
	value = peek32(PANEL_DISPLAY_CTRL) &
		~(PANEL_DISPLAY_CTRL_DUAL_DISPLAY |
		  PANEL_DISPLAY_CTRL_DOUBLE_PIXEL);
	poke32(PANEL_DISPLAY_CTRL, value);
	return 0;
}

static int sm750_modeset_init(struct sm750_drm_device *sdev)
{
	static const u32 formats[] = { DRM_FORMAT_XRGB8888 };
	static const u32 cursor_formats[] = { DRM_FORMAT_ARGB8888 };
	struct drm_device *drm = &sdev->drm;
	const struct drm_simple_display_pipe_funcs *pipe_funcs;
	int ret;

	ret = drmm_mode_config_init(drm);
	if (ret)
		return ret;
	drm->mode_config.funcs = sdev->shadow_scanout ?
		&sm750_shadow_mode_config_funcs : &sm750_mode_config_funcs;
	drm->mode_config.fb_modifiers_not_supported = 1;
	drm->mode_config.min_width = 320;
	drm->mode_config.min_height = 200;
	drm->mode_config.max_width = SM750_DRM_MAX_WIDTH;
	drm->mode_config.max_height = SM750_DRM_MAX_HEIGHT;
	drm->mode_config.preferred_depth = 24;
	drm->mode_config.prefer_shadow = 1;

	ret = drm_connector_init(drm, &sdev->connector, &sm750_connector_funcs,
				 DRM_MODE_CONNECTOR_HDMIA);
	if (ret)
		return ret;
	drm_connector_helper_add(&sdev->connector,
				 &sm750_connector_helper_funcs);
	sdev->connector.polled = DRM_CONNECTOR_POLL_CONNECT |
				 DRM_CONNECTOR_POLL_DISCONNECT;

	pipe_funcs = sdev->shadow_scanout ? &sm750_shadow_pipe_funcs :
		&sm750_pipe_funcs;
	ret = drm_simple_display_pipe_init(drm, &sdev->pipe, pipe_funcs,
					   formats, ARRAY_SIZE(formats), NULL,
					   &sdev->connector);
	if (ret)
		return ret;
	if (sdev->shadow_scanout)
		drm_plane_enable_fb_damage_clips(&sdev->pipe.plane);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
	sdev->pipe.crtc.funcs = &sm750_crtc_funcs;
#endif
	if (sdev->hardware_cursor) {
		ret = drm_universal_plane_init(drm, &sdev->cursor_plane,
				drm_crtc_mask(&sdev->pipe.crtc),
				&sm750_cursor_plane_funcs, cursor_formats,
				ARRAY_SIZE(cursor_formats), NULL,
				DRM_PLANE_TYPE_CURSOR, "sm750-cursor");
		if (ret)
			return ret;
		drm_plane_helper_add(&sdev->cursor_plane,
				     &sm750_cursor_plane_helper_funcs);
		/*
		 * The cursor plane exposes DRM_FORMAT_ARGB8888, so the DRM core
		 * requires a blend mode property: drm_mode_config_validate()
		 * warns "pixel format with alpha exposed but blend mode not
		 * setup" for a plane that advertises an alpha format without
		 * one. The hardware still consumes per-pixel alpha - it becomes
		 * a dithered transparent/opaque mask over three palette entries
		 * (sm750_cursor_encode) - so hiding alpha by switching to
		 * XRGB8888 would misdescribe the cursor and break compositors
		 * that hand us ARGB8888. PREMULTI is the one mode that is true
		 * here: ARGB8888 colour is premultiplied, and
		 * sm750_cursor_unpremultiply() divides alpha back out before
		 * quantising. COVERAGE is deliberately not offered because it
		 * would claim the driver premultiplies colour it receives
		 * unpremultiplied, which it does not. PREMULTI is also the only
		 * mode every supported kernel accepts (6.17 rejects a mask
		 * without it), so no version guard is needed. No plane alpha
		 * property is created: the hardware has no plane-wide alpha.
		 */
		ret = drm_plane_create_blend_mode_property(&sdev->cursor_plane,
				BIT(DRM_MODE_BLEND_PREMULTI));
		if (ret)
			return ret;
		sdev->pipe.crtc.cursor = &sdev->cursor_plane;
		drm->mode_config.cursor_width = SM750_DRM_CURSOR_WIDTH;
		drm->mode_config.cursor_height = SM750_DRM_CURSOR_HEIGHT;
	}
	ret = drm_vblank_init(drm, 1);
	if (ret)
		return ret;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
	drm_vblank_work_init(&sdev->crc_work, &sdev->pipe.crtc,
			     sm750_crc_work_fn);
#endif

	drm_mode_config_reset(drm);
	return 0;
}

static void sm750_release_regions(void *data)
{
	struct pci_dev *pdev = data;

	pci_release_regions(pdev);
}

static void sm750_unmap_regs(void *data)
{
	struct sm750_drm_device *sdev = data;

	if (mmio750 == sdev->regs)
		mmio750 = NULL;
	pci_iounmap(sdev->pdev, sdev->regs);
}

static void sm750_unmap_vram(void *data)
{
	struct sm750_drm_device *sdev = data;

	pci_iounmap(sdev->pdev, sdev->vram);
}

static void sm750_free_shadow_buffer(void *data)
{
	kvfree(data);
}

/* Defect A65: a hot remove wedges in Unloading with fbcon bound and no
 * stack exists.  The marks record which teardown step was executing. */
static void a65_mark(const char *what)
{
	if (a65_trace)
		pr_err("A65: %s\n", what);
}

static void sm750_destroy_shadow_workqueue(void *data)
{
	struct sm750_drm_device *sdev = data;

	a65_mark("before async_quiesce");
	sm750_async_quiesce(sdev);
	a65_mark("after async_quiesce");
	destroy_workqueue(sdev->shadow_workqueue);
	a65_mark("after destroy_workqueue");
	sdev->shadow_workqueue = NULL;
}

/*
 * Monitoring attributes for tools/sm750-smi, published on the PCI device so
 * they appear as /sys/class/drm/cardN/device/<name>.  The tool falls back to
 * libdrm, debugfs or n/a when an attribute is absent, so an older module
 * still works.
 *
 * hpd, rxsense and link_state read the SiI9024A interrupt status over the
 * bit-banged i2c bus: two register reads, roughly a millisecond, and they
 * never clear the latched event bits (clear_events is false).  They are for a
 * monitoring poll, not for a tight loop.
 *
 * tests/check-sysfs-attributes.sh checks the block between the two marker
 * lines; keep the markers and the DEVICE_ATTR_RO names in step with it.
 */
/* BEGIN sysfs monitoring attributes */

#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
/* sm750_crtc_funcs registers .get_crc_sources on this kernel range. */
#define SM750_CRC_SUPPORTED 1
#else
#define SM750_CRC_SUPPORTED 0
#endif

static ssize_t mem_info_vram_total_show(struct device *dev,
					struct device_attribute *attr,
					char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);

	if (!sdev)
		return -ENODEV;
	return sysfs_emit(buf, "%u\n", sdev->vram_size);
}
static DEVICE_ATTR_RO(mem_info_vram_total);

static ssize_t vram_total_bytes_show(struct device *dev,
				     struct device_attribute *attr, char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);

	if (!sdev)
		return -ENODEV;
	return sysfs_emit(buf, "%u\n", sdev->vram_size);
}
static DEVICE_ATTR_RO(vram_total_bytes);

/*
 * Driver-reserved VRAM, not total TTM usage: the shadow front buffer and the
 * backbuffer are only owned by the driver on the shadow path (the direct path
 * scans a userspace GEM framebuffer), plus the hardware cursor buffer and the
 * DMA1 test buffer.  An exact VRAM-manager figure is not available on the
 * shadow path, which has no vram_mm helper at all.
 */
static ssize_t vram_used_bytes_show(struct device *dev,
				    struct device_attribute *attr, char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	u64 used = 0;

	if (!sdev)
		return -ENODEV;
	mutex_lock(&sdev->mode_lock);
	if (sdev->shadow_scanout && READ_ONCE(sdev->pipe.crtc.enabled))
		used += READ_ONCE(sdev->scanout_frame_size);
	if (READ_ONCE(sdev->backbuffer_ready))
		used += READ_ONCE(sdev->scanout_frame_size);
	if (READ_ONCE(sdev->hardware_cursor))
		used += SM750_DRM_CURSOR_SIZE;
	if (READ_ONCE(sdev->shadow_dma_enabled))
		used += SM750_DRM_DMA_TEST_SIZE;
	mutex_unlock(&sdev->mode_lock);
	/*
	 * The 256-byte DMA test buffer is carved below cursor_offset without
	 * shrinking the managed range, so the sum can nominally exceed
	 * vram_size by that much; clamp so free-memory arithmetic stays sane.
	 */
	return sysfs_emit(buf, "%llu\n", min_t(u64, used, sdev->vram_size));
}
static DEVICE_ATTR_RO(vram_used_bytes);

static ssize_t active_mode_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	struct drm_crtc *crtc;
	u32 width = 0;
	u32 height = 0;

	if (!sdev)
		return -ENODEV;
	crtc = &sdev->pipe.crtc;
	mutex_lock(&sdev->mode_lock);
	if (READ_ONCE(crtc->enabled)) {
		width = crtc->mode.hdisplay;
		height = crtc->mode.vdisplay;
	}
	mutex_unlock(&sdev->mode_lock);
	if (!width || !height)
		return sysfs_emit(buf, "\n");
	return sysfs_emit(buf, "%ux%u\n", width, height);
}
static DEVICE_ATTR_RO(active_mode);

static ssize_t active_mode_refresh_hz_show(struct device *dev,
					   struct device_attribute *attr,
					   char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	struct drm_crtc *crtc;
	int refresh = 0;

	if (!sdev)
		return -ENODEV;
	crtc = &sdev->pipe.crtc;
	mutex_lock(&sdev->mode_lock);
	if (READ_ONCE(crtc->enabled) && crtc->mode.hdisplay)
		refresh = drm_mode_vrefresh(&crtc->mode);
	mutex_unlock(&sdev->mode_lock);
	if (refresh <= 0)
		return sysfs_emit(buf, "\n");
	/* drm_mode_vrefresh() is integral; two decimals keep strtod() happy. */
	return sysfs_emit(buf, "%d.00\n", refresh);
}
static DEVICE_ATTR_RO(active_mode_refresh_hz);

static ssize_t active_mode_pixel_clock_khz_show(struct device *dev,
						struct device_attribute *attr,
						char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	struct drm_crtc *crtc;
	unsigned int clock = 0;

	if (!sdev)
		return -ENODEV;
	crtc = &sdev->pipe.crtc;
	mutex_lock(&sdev->mode_lock);
	if (READ_ONCE(crtc->enabled) && crtc->mode.hdisplay)
		clock = crtc->mode.clock;
	mutex_unlock(&sdev->mode_lock);
	if (!clock)
		return sysfs_emit(buf, "\n");
	return sysfs_emit(buf, "%u\n", clock);
}
static DEVICE_ATTR_RO(active_mode_pixel_clock_khz);

static int sm750_sysfs_link_status(struct device *dev,
				   struct sm750_drm_device *sdev,
				   bool *hpd, bool *rxsense)
{
	bool event = false;
	int ret;

	mutex_lock(&sdev->mode_lock);
	ret = sm750_sii902x_get_link_status(hpd, rxsense, &event, false);
	mutex_unlock(&sdev->mode_lock);
	if (ret)
		dev_dbg_once(dev, "link status read failed: %d\n", ret);
	return ret;
}

static ssize_t hpd_show(struct device *dev, struct device_attribute *attr,
			char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	bool hpd = false;
	bool rxsense = false;

	if (!sdev)
		return -ENODEV;
	if (sm750_sysfs_link_status(dev, sdev, &hpd, &rxsense))
		return sysfs_emit(buf, "-1\n");
	return sysfs_emit(buf, "%u\n", hpd ? 1U : 0U);
}
static DEVICE_ATTR_RO(hpd);

static ssize_t rxsense_show(struct device *dev, struct device_attribute *attr,
			    char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	bool hpd = false;
	bool rxsense = false;

	if (!sdev)
		return -ENODEV;
	if (sm750_sysfs_link_status(dev, sdev, &hpd, &rxsense))
		return sysfs_emit(buf, "-1\n");
	return sysfs_emit(buf, "%u\n", rxsense ? 1U : 0U);
}
static DEVICE_ATTR_RO(rxsense);

static ssize_t link_state_show(struct device *dev,
			       struct device_attribute *attr, char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	bool hpd = false;
	bool rxsense = false;

	if (!sdev)
		return -ENODEV;
	if (sm750_sysfs_link_status(dev, sdev, &hpd, &rxsense))
		return sysfs_emit(buf, "unknown\n");
	if (hpd && rxsense)
		return sysfs_emit(buf, "connected\n");
	if (rxsense)
		return sysfs_emit(buf, "receiver-only\n");
	if (hpd)
		return sysfs_emit(buf, "hpd-only\n");
	return sysfs_emit(buf, "disconnected\n");
}
static DEVICE_ATTR_RO(link_state);

static ssize_t active_crtc_show(struct device *dev,
				struct device_attribute *attr, char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	struct drm_crtc *crtc;
	int index = -1;

	if (!sdev)
		return -ENODEV;
	crtc = &sdev->pipe.crtc;
	mutex_lock(&sdev->mode_lock);
	if (READ_ONCE(crtc->enabled))
		index = drm_crtc_index(crtc);
	mutex_unlock(&sdev->mode_lock);
	return sysfs_emit(buf, "%d\n", index);
}
static DEVICE_ATTR_RO(active_crtc);

/* The vblank timer calls drm_crtc_handle_vblank(); this is that counter. */
static ssize_t vblank_count_show(struct device *dev,
				 struct device_attribute *attr, char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	u64 count;

	if (!sdev)
		return -ENODEV;
	count = drm_crtc_vblank_count(&sdev->pipe.crtc);
	return sysfs_emit(buf, "%llu\n", count);
}
static DEVICE_ATTR_RO(vblank_count);

static ssize_t crc_supported_show(struct device *dev,
				  struct device_attribute *attr, char *buf)
{
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);

	if (!sdev)
		return -ENODEV;
	return sysfs_emit(buf, "%d\n", SM750_CRC_SUPPORTED);
}
static DEVICE_ATTR_RO(crc_supported);

/*
 * pm_probe drives the two system-PM callbacks directly. System sleep cannot
 * be reached on the reference host (two neighbouring Tesla P100s return -EIO
 * from their .suspend), so sm750_pm_suspend() and sm750_pm_resume() have
 * never run on this board. This is a measurement aid, not a system sleep: it
 * saves no PCI config space, requests no D3hot transition and changes no
 * power state. See docs/PARAMETERS.md and defect A66 in docs/DEFECTS.md.
 */
static int sm750_pm_suspend(struct device *dev);
static int sm750_pm_resume(struct device *dev);

/*
 * Held for one invocation only. The callbacks take mode_lock themselves, so
 * this cannot be mode_lock. Nothing else takes this mutex.
 */
static DEFINE_MUTEX(sm750_pm_probe_lock);

static ssize_t pm_probe_store(struct device *dev,
			      struct device_attribute *attr,
			      const char *buf, size_t count)
{
	struct pci_dev *pdev = to_pci_dev(dev);
	struct sm750_drm_device *sdev = dev_get_drvdata(dev);
	int idx;
	int ret;

	if (!sdev) {
		pr_info("pm probe: refused: no driver data\n");
		return -ENODEV;
	}
	/*
	 * Exercising the PM callbacks under a live compositor must not be
	 * possible by accident. The fbcon client takes no master, so the
	 * console-only case still works.
	 */
	if (READ_ONCE(sdev->drm.master)) {
		drm_info(&sdev->drm,
			 "pm probe: refused: a DRM client holds master\n");
		return -EBUSY;
	}
	if (!sdev->drm.dev) {
		pr_info("pm probe: refused: driver not registered\n");
		return -EBUSY;
	}
	if (!drm_dev_enter(&sdev->drm, &idx)) {
		drm_info(&sdev->drm,
			 "pm probe: refused: device is not registered\n");
		return -EBUSY;
	}

	mutex_lock(&sm750_pm_probe_lock);
	if (sysfs_streq(buf, "suspend")) {
		drm_info(&sdev->drm, "pm probe: command suspend\n");
		ret = sm750_pm_suspend(&pdev->dev);
		drm_info(&sdev->drm, "pm probe: suspend returned %d\n", ret);
	} else if (sysfs_streq(buf, "resume")) {
		drm_info(&sdev->drm, "pm probe: command resume\n");
		ret = sm750_pm_resume(&pdev->dev);
		drm_info(&sdev->drm, "pm probe: resume returned %d\n", ret);
	} else if (sysfs_streq(buf, "cycle")) {
		drm_info(&sdev->drm, "pm probe: command cycle\n");
		ret = sm750_pm_suspend(&pdev->dev);
		if (ret) {
			drm_info(&sdev->drm,
				 "pm probe: cycle suspend failed: %d, resume skipped\n",
				 ret);
		} else {
			ret = sm750_pm_resume(&pdev->dev);
			if (ret)
				drm_info(&sdev->drm,
					 "pm probe: cycle suspend ok, resume failed: %d\n",
					 ret);
			else
				drm_info(&sdev->drm,
					 "pm probe: cycle suspend ok, resume ok\n");
		}
	} else {
		drm_info(&sdev->drm,
			 "pm probe: rejected unknown command '%.*s'; accepted: suspend, resume, cycle\n",
			 (int)strcspn(buf, "\n"), buf);
		ret = -EINVAL;
	}
	mutex_unlock(&sm750_pm_probe_lock);
	drm_dev_exit(idx);
	/*
	 * The log records what happened; the write's return value carries the
	 * failure. A successful invocation returns the byte count, a rejected
	 * command returns -EINVAL and a callback that returns non-zero is
	 * returned as-is, so `echo cycle > pm_probe` fails visibly and a
	 * script under `set -e` stops there.
	 */
	if (ret)
		return ret;
	return count;
}
static DEVICE_ATTR_WO(pm_probe);

static struct attribute *sm750_attrs[] = {
	&dev_attr_mem_info_vram_total.attr,
	&dev_attr_vram_total_bytes.attr,
	&dev_attr_vram_used_bytes.attr,
	&dev_attr_active_mode.attr,
	&dev_attr_active_mode_refresh_hz.attr,
	&dev_attr_active_mode_pixel_clock_khz.attr,
	&dev_attr_hpd.attr,
	&dev_attr_rxsense.attr,
	&dev_attr_link_state.attr,
	&dev_attr_active_crtc.attr,
	&dev_attr_vblank_count.attr,
	&dev_attr_crc_supported.attr,
	&dev_attr_pm_probe.attr,
	NULL,
};

static const struct attribute_group sm750_attr_group = {
	.attrs = sm750_attrs,
};

/* END sysfs monitoring attributes */

static int sm750_pci_probe(struct pci_dev *pdev,
			   const struct pci_device_id *id)
{
	const struct drm_driver *driver;
	struct sm750_drm_device *sdev;
	bool use_shadow;
	bool use_rgb565;
	bool use_bbdither;
	int ret;

	/*
	 * The SiI9022A software-I2C pin numbers are ints here but unsigned
	 * char at the conversion into sm750_sw_i2c_init(), so a value such as
	 * 256 would truncate to a different legal GPIO. Validate the int.
	 */
	if (sii9024_scl < 0 || sii9024_scl > 31 ||
	    sii9024_sda < 0 || sii9024_sda > 31)
		return dev_err_probe(&pdev->dev, -EINVAL,
			"sii9024_scl/sii9024_sda must be in 0..31 (got %d/%d)\n",
			sii9024_scl, sii9024_sda);
	if (sii9024_scl == sii9024_sda)
		return dev_err_probe(&pdev->dev, -EINVAL,
			"sii9024_scl and sii9024_sda must differ (both %d)\n",
			sii9024_scl);

	if (!strcmp(scanout_format, "xrgb8888")) {
		use_rgb565 = false;
		use_bbdither = false;
	} else if (!strcmp(scanout_format, "rgb565")) {
		use_rgb565 = true;
		use_bbdither = false;
	} else if (!strcmp(scanout_format, "rgb565-bbdither") ||
		   !strcmp(scanout_format, "rgb565-dither")) {
		use_rgb565 = true;
		use_bbdither = true;
	} else {
		return dev_err_probe(&pdev->dev, -EINVAL,
			"invalid scanout_format '%s'\n", scanout_format);
	}
	use_shadow = use_rgb565 || softscale_wide || double_shadow ||
		!disable_hardware_cursor;
	if (use_bbdither && dither_green_gain > 100)
		return dev_err_probe(&pdev->dev, -EINVAL,
			"dither_green_gain must be between 0 and 100\n");
	if (enable_dma && !disable_dma && use_shadow &&
	    (shadow_dma_min_bytes < sizeof(u32) ||
	     shadow_dma_min_bytes > SM750_DRM_DMA_STAGING_SIZE ||
	     !IS_ALIGNED(shadow_dma_min_bytes, sizeof(u32))))
		return dev_err_probe(&pdev->dev, -EINVAL,
			"shadow_dma_min_bytes must be a 4-byte aligned value from 4 to %zu\n",
			(size_t)SM750_DRM_DMA_STAGING_SIZE);
	driver = use_shadow ? &sm750_shadow_drm_driver : &sm750_drm_driver;

	ret = aperture_remove_conflicting_pci_devices(pdev, SM750_DRM_NAME);
	if (ret)
		return ret;
	ret = pcim_enable_device(pdev);
	if (ret)
		return ret;
	ret = pci_request_regions(pdev, SM750_DRM_NAME);
	if (ret)
		return ret;
	ret = devm_add_action_or_reset(&pdev->dev, sm750_release_regions, pdev);
	if (ret)
		return ret;
	pci_set_master(pdev);

	sdev = devm_drm_dev_alloc(&pdev->dev, driver,
				  struct sm750_drm_device, drm);
	if (IS_ERR(sdev))
		return PTR_ERR(sdev);
	sdev->pdev = pdev;
	sdev->shadow_scanout = use_shadow;
	sdev->rgb565 = use_rgb565;
	sdev->bbdither = use_bbdither;
	sdev->test_pattern_mode = sm750_test_pattern_parse(test_pattern);
	sdev->hardware_cursor = !disable_hardware_cursor;
	sdev->vram_base = pci_resource_start(pdev, 0);
	mutex_init(&sdev->mode_lock);
	mutex_init(&sdev->shadow_lock);
	mutex_init(&sdev->cursor_lock);
	mutex_init(&sdev->async_lock);
	mutex_init(&sdev->crc_mutex);
	INIT_WORK(&sdev->shadow_work, sm750_async_shadow_work);
	INIT_DELAYED_WORK(&sdev->test_pattern_work, sm750_test_pattern_work);
	spin_lock_init(&sdev->vblank_lock);
	hrtimer_setup(&sdev->vblank_timer, sm750_vblank_timer_fn,
		      CLOCK_MONOTONIC, HRTIMER_MODE_REL);

	sdev->regs = pci_iomap(pdev, 1, min_t(resource_size_t,
					      pci_resource_len(pdev, 1), SZ_2M));
	if (!sdev->regs)
		return -ENOMEM;
	ret = devm_add_action_or_reset(&pdev->dev, sm750_unmap_regs, sdev);
	if (ret)
		return ret;

	ret = sm750_hw_init(sdev, true);
	if (ret)
		return ret;
	/*
	 * Map VRAM in every mode: the scanout read path (CRC source and the
	 * sm750_scanout debugfs dump) reads what the engine is fed.
	 */
	sdev->vram = pci_iomap_wc(pdev, 0, sdev->vram_size);
	if (!sdev->vram)
		return -ENOMEM;
	ret = devm_add_action_or_reset(&pdev->dev, sm750_unmap_vram, sdev);
	if (ret)
		return ret;
	/*
	 * One line buffer for the test card, allocated once at probe so a
	 * rotation tick in a work item never allocates.
	 */
	sdev->test_pattern_line = devm_kmalloc_array(&pdev->dev,
		SM750_DRM_MAX_WIDTH, sizeof(*sdev->test_pattern_line),
		GFP_KERNEL);
	if (!sdev->test_pattern_line)
		return -ENOMEM;
	/* The circle outline table lives here too: a 4 KiB stack array in a
	 * workqueue tick is not worth the risk. */
	sdev->test_pattern_half = devm_kmalloc_array(&pdev->dev,
		SM750_DRM_MAX_HEIGHT / 4 + 1,
		sizeof(*sdev->test_pattern_half), GFP_KERNEL);
	if (!sdev->test_pattern_half)
		return -ENOMEM;
	if (sdev->shadow_scanout) {
		sdev->dither_scale_map = devm_kzalloc(&pdev->dev,
			sizeof(*sdev->dither_scale_map), GFP_KERNEL);
		sdev->dither_source_line = devm_kmalloc_array(&pdev->dev,
			SM750_DRM_MAX_WIDTH, sizeof(*sdev->dither_source_line),
			GFP_KERNEL);
		if (double_shadow)
			sdev->shadow_source_snapshot = kvcalloc(
				(size_t)SM750_DRM_MAX_WIDTH * SM750_DRM_MAX_HEIGHT,
				sizeof(*sdev->shadow_source_snapshot), GFP_KERNEL);
		if (double_shadow && sdev->rgb565)
			sdev->rgb565_scanout_snapshot = kvcalloc(
				(size_t)SM750_DRM_PHYSICAL_MAX_WIDTH *
				SM750_DRM_MAX_HEIGHT,
				sizeof(*sdev->rgb565_scanout_snapshot), GFP_KERNEL);
		if (async_updates)
			sdev->async_source = kvcalloc(
				(size_t)SM750_DRM_MAX_WIDTH * SM750_DRM_MAX_HEIGHT,
				sizeof(*sdev->async_source), GFP_KERNEL);
		sdev->softscale_output_line = devm_kmalloc_array(&pdev->dev,
			SM750_DITHER_SCALE_MAX_SAMPLES,
			sizeof(*sdev->softscale_output_line), GFP_KERNEL);
		sdev->xrgb_output_line = devm_kmalloc_array(&pdev->dev,
			SM750_DITHER_SCALE_MAX_SAMPLES,
			sizeof(*sdev->xrgb_output_line),
			GFP_KERNEL);
		if (sdev->hardware_cursor) {
			sdev->cursor_source = devm_kmalloc_array(&pdev->dev,
				SM750_DRM_CURSOR_WIDTH * SM750_DRM_CURSOR_HEIGHT,
				sizeof(*sdev->cursor_source), GFP_KERNEL);
			sdev->cursor_image = devm_kzalloc(&pdev->dev,
				SM750_DRM_CURSOR_SIZE, GFP_KERNEL);
		}
		if (!sdev->dither_scale_map || !sdev->dither_source_line ||
		    (double_shadow && !sdev->shadow_source_snapshot) ||
		    (double_shadow && sdev->rgb565 &&
		     !sdev->rgb565_scanout_snapshot) ||
		    (async_updates && !sdev->async_source) ||
		    !sdev->softscale_output_line || !sdev->xrgb_output_line ||
		    (sdev->hardware_cursor &&
		     (!sdev->cursor_source || !sdev->cursor_image)))
			return -ENOMEM;
		if (sdev->shadow_source_snapshot) {
			ret = devm_add_action_or_reset(&pdev->dev,
					sm750_free_shadow_buffer,
					sdev->shadow_source_snapshot);
			if (ret)
				return ret;
		}
		if (sdev->rgb565_scanout_snapshot) {
			ret = devm_add_action_or_reset(&pdev->dev,
					sm750_free_shadow_buffer,
					sdev->rgb565_scanout_snapshot);
			if (ret)
				return ret;
		}
		if (sdev->async_source) {
			ret = devm_add_action_or_reset(&pdev->dev,
					sm750_free_shadow_buffer,
					sdev->async_source);
			if (ret)
				return ret;
			sdev->shadow_workqueue = alloc_ordered_workqueue(
				"sm750-shadow", WQ_HIGHPRI | WQ_MEM_RECLAIM);
			if (!sdev->shadow_workqueue)
				return -ENOMEM;
			ret = devm_add_action_or_reset(&pdev->dev,
					sm750_destroy_shadow_workqueue, sdev);
			if (ret)
				return ret;
		}
		if (sdev->vram_size < SM750_DRM_MIN_VRAM)
			return dev_err_probe(&pdev->dev, -ENOSPC,
				"VRAM %#x is below the %lu-byte minimum (cursor, DMA test and one mode buffer)\n",
				sdev->vram_size,
				(unsigned long)SM750_DRM_MIN_VRAM);
		if (sdev->hardware_cursor &&
		    sdev->vram_size < SM750_DRM_CURSOR_SIZE)
			return -ENOSPC;
		sdev->cursor_offset = ALIGN_DOWN(
			sdev->vram_size -
			(sdev->hardware_cursor ? SM750_DRM_CURSOR_SIZE : 0), 16);
		if (sdev->hardware_cursor) {
			memset_io(sdev->vram + sdev->cursor_offset, 0,
				  SM750_DRM_CURSOR_SIZE);
			sm750_cursor_disable_locked(sdev);
		}
		if (sdev->rgb565) {
			sdev->dither_output_line = devm_kmalloc_array(&pdev->dev,
				SM750_DRM_MAX_WIDTH,
				sizeof(*sdev->dither_output_line), GFP_KERNEL);
			if (!sdev->dither_output_line)
				return -ENOMEM;
		}
		if (sdev->bbdither) {
			sdev->dither = devm_kzalloc(&pdev->dev,
				sizeof(*sdev->dither), GFP_KERNEL);
			if (!sdev->dither)
				return -ENOMEM;
			ret = sm750_dither_init(sdev->dither, dither_green_gain);
			if (ret)
				return ret;
		}
		if (enable_dma && !disable_dma) {
			ret = sm750_dma_irq_init(sdev);
			if (ret)
				drm_warn(&sdev->drm,
					 "DMA1 IRQ unavailable (%d); using completion polling on the shadow worker\n",
					 ret);
			ret = sm750_dma_init(sdev);
			if (ret) {
				sm750_dma_irq_disable(sdev);
				drm_warn(&sdev->drm,
					 "DMA1 verification failed (%d); retaining CPU shadow uploads\n",
					 ret);
			} else {
				ret = devm_add_action_or_reset(&pdev->dev,
						sm750_dma_stop, sdev);
				if (ret)
					return ret;
			}
		}
	}
#ifdef CONFIG_X86
	if (dvo_clock_phase < 0) {
		u8 saved_index = inb(0x3c4);

		outb(0x95, 0x3c4);
		sdev->phase_falling = !!(inb(0x3c5) & BIT(1));
		outb(saved_index, 0x3c4);
	} else
#endif
		sdev->phase_falling = dvo_clock_phase > 0;

	if (!sdev->shadow_scanout) {
		ret = drmm_vram_helper_init(&sdev->drm, sdev->vram_base,
					    sdev->vram_size);
		if (ret)
			return ret;
	}
	ret = sm750_modeset_init(sdev);
	if (ret)
		return ret;

	mutex_lock(&sdev->mode_lock);
	ret = sm750_sii902x_prepare(&pdev->dev, false,
				    sii9024_scl, sii9024_sda);
	mutex_unlock(&sdev->mode_lock);
	if (ret)
		return ret;

	pci_set_drvdata(pdev, sdev);
	/*
	 * pdev->dev is the /sys/class/drm/cardN/device node, which is where
	 * tools/sm750-smi looks; the group must not go on the DRM class device.
	 */
	ret = devm_device_add_group(&pdev->dev, &sm750_attr_group);
	if (ret)
		return ret;
	ret = drm_dev_register(&sdev->drm, 0);
	if (ret)
		return ret;
	drm_kms_helper_poll_init(&sdev->drm);
	drm_client_setup(&sdev->drm, drm_format_info(DRM_FORMAT_XRGB8888));
	drm_info(&sdev->drm,
		 "registered SM750 HDMI DRM device with %u MiB VRAM (%s, primary controller)\n",
		 sdev->vram_size >> 20,
		 sdev->bbdither ? "RGB565 bbdither" :
		 (sdev->rgb565 ? "RGB565" :
		  (sdev->shadow_scanout ? "XRGB8888 shadow" :
		   "XRGB8888 direct")));
	if (!strcmp(scanout_format, "rgb565-dither"))
		drm_info(&sdev->drm,
			 "scanout_format=rgb565-dither is deprecated; use rgb565-bbdither\n");
	if (softscale_wide && !edid_only) {
		drm_info(&sdev->drm,
			 "logical 2464/2560x1080 softscale to 2048x1080 enabled\n");
		if (sharpen)
			drm_info(&sdev->drm,
				 "softscale horizontal contrast sharpening enabled at 8%%\n");
	} else if (sharpen) {
		drm_info(&sdev->drm,
			 "sharpen=1 ignored because wide softscale modes are inactive\n");
	}
	if (sdev->hardware_cursor)
		drm_info(&sdev->drm,
			 "64x64 hardware cursor plane enabled with ARGB palette conversion\n");
	if (sdev->shadow_workqueue)
		drm_info(&sdev->drm,
			 "coalesced asynchronous shadow updates enabled\n");
	if (sdev->shadow_dma_enabled && sdev->dma_irq_enabled)
		drm_info(&sdev->drm,
			 "DMA1 interrupt-driven completion enabled on IRQ %u\n",
			 sdev->pdev->irq);
	return 0;
}

static void sm750_pci_remove(struct pci_dev *pdev)
{
	struct sm750_drm_device *sdev = pci_get_drvdata(pdev);

	a65_mark("remove enter");
	a65_mark("before poll_fini");
	drm_kms_helper_poll_fini(&sdev->drm);
	a65_mark("after poll_fini");
	a65_mark("before unplug");
	drm_dev_unplug(&sdev->drm);
	a65_mark("after unplug");
	a65_mark("before test_pattern_cancel");
	sm750_test_pattern_cancel(sdev);
	a65_mark("after test_pattern_cancel");
	a65_mark("before atomic_shutdown");
	drm_atomic_helper_shutdown(&sdev->drm);
	a65_mark("after atomic_shutdown");
	a65_mark("before vblank_stop");
	sm750_vblank_timer_stop(sdev, true);
	a65_mark("after vblank_stop");
	mutex_lock(&sdev->mode_lock);
	sm750_sii902x_shutdown();
	mutex_unlock(&sdev->mode_lock);
	a65_mark("after sii902x_shutdown");
	a65_mark("remove exit");
}

static void sm750_pci_shutdown(struct pci_dev *pdev)
{
	struct sm750_drm_device *sdev = pci_get_drvdata(pdev);

	if (!sdev)
		return;
	drm_atomic_helper_shutdown(&sdev->drm);
	sm750_vblank_timer_stop(sdev, true);
}

static int sm750_pm_suspend(struct device *dev)
{
	struct pci_dev *pdev = to_pci_dev(dev);
	struct sm750_drm_device *sdev = pci_get_drvdata(pdev);
	int ret;

	drm_info(&sdev->drm, "pm: suspend entry\n");
	ret = drm_mode_config_helper_suspend(&sdev->drm);
	if (ret) {
		drm_err(&sdev->drm, "pm: suspend failed: %d\n", ret);
		return ret;
	}
	sm750_vblank_timer_stop(sdev, true);
	mutex_lock(&sdev->mode_lock);
	sm750_sii902x_shutdown();
	mutex_unlock(&sdev->mode_lock);
	drm_info(&sdev->drm, "pm: suspend complete\n");
	return 0;
}

static int sm750_pm_resume(struct device *dev)
{
	struct pci_dev *pdev = to_pci_dev(dev);
	struct sm750_drm_device *sdev = pci_get_drvdata(pdev);
	int ret;

	drm_info(&sdev->drm, "pm: resume entry\n");
	ret = sm750_hw_init(sdev, false);
	if (ret) {
		drm_err(&sdev->drm, "pm: resume failed: %d\n", ret);
		return ret;
	}
	mutex_lock(&sdev->mode_lock);
	ret = sm750_sii902x_prepare(&pdev->dev, false,
				    sii9024_scl, sii9024_sda);
	mutex_unlock(&sdev->mode_lock);
	if (ret) {
		drm_err(&sdev->drm, "pm: resume failed: %d\n", ret);
		return ret;
	}
	ret = drm_mode_config_helper_resume(&sdev->drm);
	if (ret) {
		drm_err(&sdev->drm, "pm: resume failed: %d\n", ret);
		return ret;
	}
	drm_info(&sdev->drm, "pm: resume complete\n");
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(sm750_pm_ops, sm750_pm_suspend,
				 sm750_pm_resume);

static const struct pci_device_id sm750_pci_ids[] = {
	{ PCI_DEVICE(0x126f, 0x0750) },
	{ }
};
MODULE_DEVICE_TABLE(pci, sm750_pci_ids);

static struct pci_driver sm750_pci_driver = {
	.name = SM750_DRM_NAME,
	.id_table = sm750_pci_ids,
	.probe = sm750_pci_probe,
	.remove = sm750_pci_remove,
	.shutdown = sm750_pci_shutdown,
	.driver.pm = pm_sleep_ptr(&sm750_pm_ops),
};
module_pci_driver(sm750_pci_driver);

MODULE_AUTHOR("Benjamin Brown");
MODULE_DESCRIPTION("Atomic DRM/KMS driver for SM750G10 SiI9024A HDMI boards");
MODULE_LICENSE("GPL v2");
MODULE_VERSION(SM750_DRM_VERSION);
