// SPDX-License-Identifier: GPL-2.0-only
/*
 * tests/scanout-pattern.c - put one known colour on the SM750 CRTC.
 *
 * T27: the host has no /dev/fb0 (CONFIG_FB_DEVICE unset, defect A24), so
 * tests/check-scanout-crc.sh can no longer draw through fbdev. This helper
 * draws through KMS instead: dumb buffer, fill, addfb, setcrtc.
 *
 * Usage: scanout-pattern <card-node> <black|white>
 *
 * Exit codes:
 *   0  the frame is on the CRTC
 *   1  a KMS call failed (errno printed)
 *   3  the process could not become DRM master, which is an environment
 *      condition (another client owns the card), not a driver fault
 *
 * The frame buffer is deliberately not removed. drmModeRmFB() on the fb that
 * is currently scanned out disables the CRTC, which would stop the vblanks the
 * CRC check needs; each invocation therefore leaves one dumb buffer behind.
 * The check runs at most twice per boot and the buffers go with the module.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#define EXIT_ENV 3

static void step(const char *what, const char *detail)
{
	fprintf(stderr, "scanout-pattern: %s%s%s\n", what,
		detail ? ": " : "", detail ? detail : "");
}

static int die(const char *what)
{
	fprintf(stderr, "scanout-pattern: %s: %s\n", what, strerror(errno));
	return 1;
}

int main(int argc, char **argv)
{
	const char *node;
	uint32_t colour;
	int fd, ret = 1;
	drmModeRes *res = NULL;
	drmModeConnector *conn = NULL;
	drmModeEncoder *enc = NULL;
	drmModeCrtc *cur = NULL;
	drmModeModeInfo mode;
	uint32_t conn_id = 0, crtc_id = 0;
	uint32_t handle = 0, fb = 0, pitch = 0;
	uint64_t size = 0, offset = 0;
	void *map = MAP_FAILED;
	char detail[128];

	if (argc != 3 && argc != 4) {
		fprintf(stderr,
			"usage: %s <card-node> <black|white> [hold-seconds]\n",
			argv[0]);
		return 1;
	}
	node = argv[1];
	if (!strcmp(argv[2], "black"))
		colour = 0x000000;
	else if (!strcmp(argv[2], "white"))
		colour = 0xffffff;
	else {
		fprintf(stderr, "scanout-pattern: unknown colour %s\n", argv[2]);
		return 1;
	}

	fd = open(node, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return die(node);
	step("opened", node);

	res = drmModeGetResources(fd);
	if (!res)
		return die("drmModeGetResources");

	/* Prefer the connector the driver already has enabled. */
	for (int i = 0; i < res->count_connectors; i++) {
		drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);

		if (!c)
			continue;
		if (c->connection == DRM_MODE_CONNECTED && c->encoder_id) {
			conn = c;
			conn_id = c->connector_id;
			break;
		}
		drmModeFreeConnector(c);
	}
	if (!conn) {
		fprintf(stderr, "scanout-pattern: no connected connector with an encoder\n");
		goto out;
	}
	enc = drmModeGetEncoder(fd, conn->encoder_id);
	if (!enc) {
		fprintf(stderr, "scanout-pattern: drmModeGetEncoder failed\n");
		goto out;
	}
	crtc_id = enc->crtc_id;
	if (!crtc_id) {
		fprintf(stderr, "scanout-pattern: encoder %u has no CRTC\n", enc->encoder_id);
		goto out;
	}

	/* Keep the mode that is on screen; a fresh boot has none. */
	cur = drmModeGetCrtc(fd, crtc_id);
	if (cur && cur->mode_valid) {
		mode = cur->mode;
	} else if (conn->count_modes > 0) {
		mode = conn->modes[0];
	} else {
		fprintf(stderr, "scanout-pattern: CRTC %u has no mode and the connector has none either\n",
			crtc_id);
		goto out;
	}

	if (drmModeCreateDumbBuffer(fd, mode.hdisplay, mode.vdisplay, 32, 0,
				    &handle, &pitch, &size) < 0) {
		step("drmModeCreateDumbBuffer", strerror(errno));
		goto out;
	}
	if (drmModeMapDumbBuffer(fd, handle, &offset) < 0) {
		step("drmModeMapDumbBuffer", strerror(errno));
		goto out;
	}
	map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, offset);
	if (map == MAP_FAILED) {
		step("mmap", strerror(errno));
		goto out;
	}
	for (uint64_t y = 0; y < mode.vdisplay; y++) {
		uint32_t *row = (uint32_t *)((char *)map + y * pitch);

		for (uint32_t x = 0; x < mode.hdisplay; x++)
			row[x] = colour;
	}
	snprintf(detail, sizeof(detail), "%ux%u pitch %u size %llu",
		 mode.hdisplay, mode.vdisplay, pitch, (unsigned long long)size);
	step("filled", detail);

	uint32_t handles[4] = { handle };
	uint32_t pitches[4] = { pitch };
	uint32_t offsets[4] = { 0 };

	if (drmModeAddFB2(fd, mode.hdisplay, mode.vdisplay, DRM_FORMAT_XRGB8888,
			  handles, pitches, offsets, &fb, 0) < 0) {
		if (drmModeAddFB(fd, mode.hdisplay, mode.vdisplay, 24, 32, pitch,
				 handle, &fb) < 0) {
			step("drmModeAddFB", strerror(errno));
			goto out;
		}
	}
	snprintf(detail, sizeof(detail), "fb %u", fb);
	step("added", detail);

	/* The CRTC programming is the part that needs DRM master. */
	if (drmSetMaster(fd) < 0) {
		int err = errno;

		step("drmSetMaster", strerror(err));
		ret = EXIT_ENV;
		errno = err;
		goto out;
	}
	if (drmModeSetCrtc(fd, crtc_id, fb, 0, 0, &conn_id, 1, &mode) < 0) {
		step("drmModeSetCrtc", strerror(errno));
		goto out;
	}
	printf("%s: connector %u crtc %u %ux%u %s fb %u\n", node, conn_id,
	       crtc_id, mode.hdisplay, mode.vdisplay, argv[2], fb);
	fflush(stdout);
	ret = 0;
	/* Keep the frame and the master while a caller samples it. */
	if (argc == 4)
		sleep(atoi(argv[3]));

out:
	if (map != MAP_FAILED)
		munmap(map, size);
	if (cur)
		drmModeFreeCrtc(cur);
	if (enc)
		drmModeFreeEncoder(enc);
	if (conn)
		drmModeFreeConnector(conn);
	if (res)
		drmModeFreeResources(res);
	close(fd);
	return ret;
}
