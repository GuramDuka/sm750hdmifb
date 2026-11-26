// SPDX-License-Identifier: GPL-2.0-only
/*
 * sm750-smi - monitoring and control utility for the sm750hdmidrm driver.
 *
 * Everything is read from a real source, in order of increasing privilege:
 *   sysfs class and module attributes (world readable)
 *   the DRM card node through libdrm (udev ACL on this board)
 *   /sys/kernel/debug/dri (root only, optional)
 * A value that cannot be read is reported as "n/a" together with the reason
 * that kept it unavailable.  No number is ever invented.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <xf86drm.h>
#include <xf86drmMode.h>

#define SMI_DRIVER      "sm750hdmidrm"
#define SMI_PCI_VENDOR  0x126f
#define SMI_PCI_DEVICE  0x0750
#define SMI_VALUE_MAX   512
#define SMI_PATH_MAX    4096
#define SMI_SYSFS_PAGE  4096
#define SMI_TOOL_NAME   "sm750-smi"

/* Exit codes.  2 is the PCI-only view, 3 the --strict unresolved field set. */
enum {
	SMI_OK = 0,
	SMI_ERR = 1,
	SMI_NO_CARD = 2,
	SMI_STRICT = 3
};

enum smi_format {
	SMI_FMT_TABLE,
	SMI_FMT_CSV,
	SMI_FMT_CSV_NOHEADER,
	SMI_FMT_JSON
};

struct smi_ctx {
	const char *sysfs_root;
	const char *proc_root;
	const char *card_path;
	int id;
	int card_index;
	int card_stat_ok;
	dev_t card_dev;
	ino_t card_ino;
	int drm_fd;
	int drm_tried;
	int have_mode;
	drmModeModeInfo mode;
	uint32_t crtc_id;
	int have_crtc;
	int connector_index;      /* cached sysfs connector directory */
	char connector_dir[SMI_PATH_MAX];
	char connector_name[64];
	int connector_found;
	int partial_procs;
	int procs_scanned;
	int procs_ok;
	int procs_total;
	int procs_shown;
	struct {
		pid_t pid;
		char comm[64];
		char node[SMI_PATH_MAX];
	} procs[64];
};

typedef int (*field_getter)(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason);

struct field_def {
	const char *name;
	const char *desc;
	const char *source;
	field_getter get;
};

/* ------------------------------------------------------------------ */
/* small helpers                                                       */
/* ------------------------------------------------------------------ */

static const char *const reason_attr_missing =
	"driver attribute not present in this version";
static const char *const reason_card_missing =
	"card sysfs node missing";
static const char *const reason_needs_root =
	"needs root (debugfs)";
static const char *const reason_no_active_crtc =
	"no active CRTC";

static int join2(char *out, size_t cap, const char *a, const char *b)
{
	int n = snprintf(out, cap, "%s/%s", a, b);

	if (n < 0 || (size_t)n >= cap)
		return -ENAMETOOLONG;
	return 0;
}

static int join3(char *out, size_t cap, const char *a, const char *b,
		 const char *c)
{
	int n = snprintf(out, cap, "%s/%s/%s", a, b, c);

	if (n < 0 || (size_t)n >= cap)
		return -ENAMETOOLONG;
	return 0;
}

static void copy_str(char *dst, size_t cap, const char *src)
{
	size_t n = strlen(src);

	if (n >= cap)
		n = cap - 1;
	memcpy(dst, src, n);
	dst[n] = '\0';
}

/*
 * Append a path component in place.  snprintf must not receive the same
 * object as both destination and source, so the result is built in a
 * temporary buffer and checked before it is copied back.
 */
static int append_path(char *path, size_t cap, const char *suffix)
{
	char tmp[SMI_PATH_MAX];
	int n = snprintf(tmp, sizeof(tmp), "%s/%s", path, suffix);

	if (n < 0 || (size_t)n >= sizeof(tmp) || (size_t)n >= cap)
		return -ENAMETOOLONG;
	memcpy(path, tmp, (size_t)n + 1);
	return 0;
}

static void trim(char *s)
{
	size_t n = strlen(s);

	while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r' ||
			 s[n - 1] == ' ' || s[n - 1] == '\t'))
		s[--n] = '\0';
}

/*
 * Read the first line of a sysfs attribute.  sysfs returns at most one page,
 * so the read is always bounded by a one-page buffer plus the terminator.
 * Returns 1 on success, 0 when the file does not exist, a negative errno
 * otherwise.
 */
static int read_first_line(const char *path, char *out, size_t cap)
{
	char buf[SMI_SYSFS_PAGE + 1];
	ssize_t n;
	int fd;

	if (cap == 0)
		return -EINVAL;
	fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -errno;
	n = read(fd, buf, SMI_SYSFS_PAGE);
	close(fd);
	if (n < 0)
		return -errno;
	buf[n] = '\0';
	for (ssize_t i = 0; i < n; i++) {
		if (buf[i] == '\n') {
			buf[i] = '\0';
			break;
		}
	}
	trim(buf);
	if (buf[0] == '\0')
		return 0;
	if (strlen(buf) >= cap)
		return -ENOSPC;
	strcpy(out, buf);
	return 1;
}

/* Read a sysfs attribute relative to the card class directory. */
static int read_card_attr(struct smi_ctx *c, const char *rel, char *out,
			  size_t cap)
{
	char path[SMI_PATH_MAX];
	char base[SMI_PATH_MAX];
	int rc;

	rc = snprintf(base, sizeof(base), "%s/class/drm/card%d",
		      c->sysfs_root, c->card_index);
	if (rc < 0 || (size_t)rc >= sizeof(base))
		return -ENAMETOOLONG;
	rc = join2(path, sizeof(path), base, rel);
	if (rc)
		return rc;
	return read_first_line(path, out, cap);
}

/* Try a list of candidate attributes, first readable wins. */
static int read_candidates(struct smi_ctx *c, const char *const *rels,
			   size_t n, char *out, size_t cap, int *err)
{
	int rc = 0;

	*err = 0;
	for (size_t i = 0; i < n; i++) {
		rc = read_card_attr(c, rels[i], out, cap);
		if (rc > 0)
			return 1;
		if (rc == 0)
			continue;
		*err = rc;
	}
	return 0;
}

/* Strict unsigned decimal parse: no sign, no garbage, trailing blanks ok. */
static int parse_u64(const char *s, unsigned long long *v)
{
	char *end;
	unsigned long long r;

	if (s == NULL || *s == '\0' || *s == '-' || *s == '+')
		return -1;
	errno = 0;
	r = strtoull(s, &end, 10);
	if (errno != 0 || end == s)
		return -1;
	while (*end == ' ' || *end == '\t')
		end++;
	if (*end != '\0')
		return -1;
	*v = r;
	return 0;
}

static int parse_double(const char *s, double *v)
{
	char *end;
	double r;

	if (s == NULL || *s == '\0')
		return -1;
	errno = 0;
	r = strtod(s, &end);
	if (errno != 0 || end == s)
		return -1;
	while (*end == ' ' || *end == '\t')
		end++;
	if (*end != '\0')
		return -1;
	*v = r;
	return 0;
}

static int is_hex_string(const char *s)
{
	if (*s == '\0')
		return 0;
	for (; *s; s++) {
		if (!((*s >= '0' && *s <= '9') || (*s >= 'a' && *s <= 'f') ||
		      (*s >= 'A' && *s <= 'F')))
			return 0;
	}
	return 1;
}

/* Normalise a PCI id attribute ("0xA1", "0xa1\n") to lowercase hex. */
static int norm_hex(const char *in, char *out, size_t cap)
{
	const char *p = in;
	size_t n;

	if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X'))
		p += 2;
	if (!is_hex_string(p) || strlen(p) + 1 > cap)
		return -1;
	n = strlen(p);
	for (size_t i = 0; i < n; i++) {
		char ch = p[i];

		out[i] = (ch >= 'A' && ch <= 'F') ? (char)(ch - 'A' + 'a') : ch;
	}
	out[n] = '\0';
	return 0;
}

/* Extract KEY=VALUE from a uevent file. */
static int uevent_get(struct smi_ctx *c, const char *key, char *out,
		      size_t cap)
{
	char path[SMI_PATH_MAX];
	char base[SMI_PATH_MAX];
	FILE *f;
	char line[SMI_SYSFS_PAGE];
	size_t klen = strlen(key);
	int found = 0;

	if (snprintf(base, sizeof(base), "%s/class/drm/card%d/device",
		     c->sysfs_root, c->card_index) >= (int)sizeof(base))
		return -ENAMETOOLONG;
	if (join2(path, sizeof(path), base, "uevent"))
		return -ENAMETOOLONG;
	f = fopen(path, "r");
	if (f == NULL)
		return -errno;
	while (fgets(line, sizeof(line), f) != NULL) {
		trim(line);
		if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
			if (strlen(line + klen + 1) >= cap)
				break;
			strcpy(out, line + klen + 1);
			found = 1;
			break;
		}
	}
	fclose(f);
	return found ? 1 : 0;
}

static int card_sysfs_exists(struct smi_ctx *c)
{
	char path[SMI_PATH_MAX];
	struct stat st;

	if (snprintf(path, sizeof(path), "%s/class/drm/card%d", c->sysfs_root,
		     c->card_index) >= (int)sizeof(path))
		return 0;
	return stat(path, &st) == 0;
}

/* ------------------------------------------------------------------ */
/* optional libdrm layer                                               */
/* ------------------------------------------------------------------ */

static int drm_fd(struct smi_ctx *c)
{
	if (c->drm_tried)
		return c->drm_fd;
	c->drm_tried = 1;
	c->drm_fd = -1;
	if (c->card_path == NULL)
		return -1;
	c->drm_fd = open(c->card_path, O_RDWR | O_CLOEXEC);
	if (c->drm_fd < 0)
		c->drm_fd = open(c->card_path, O_RDONLY | O_CLOEXEC);
	return c->drm_fd;
}

/* Cache the current mode and CRTC from the least probing libdrm call. */
static int drm_load_mode(struct smi_ctx *c)
{
	drmModeRes *res;
	drmModeConnector *conn;
	int fd;
	int best = -1;

	if (c->have_mode)
		return 1;
	fd = drm_fd(c);
	if (fd < 0)
		return 0;
	res = drmModeGetResources(fd);
	if (res == NULL)
		return 0;
	for (int i = 0; i < res->count_connectors; i++) {
		conn = drmModeGetConnectorCurrent(fd, res->connectors[i]);
		if (conn == NULL)
			continue;
		if (conn->connection == DRM_MODE_CONNECTED) {
			best = i;
			if (conn->count_modes > 0) {
				c->mode = conn->modes[0];
				c->have_mode = 1;
			}
			if (conn->encoder_id) {
				drmModeEncoder *enc =
					drmModeGetEncoder(fd, conn->encoder_id);
				if (enc != NULL) {
					if (enc->crtc_id) {
						c->crtc_id = enc->crtc_id;
						c->have_crtc = 1;
					}
					drmModeFreeEncoder(enc);
				}
			}
			drmModeFreeConnector(conn);
			if (c->have_mode && c->have_crtc)
				break;
			continue;
		}
		drmModeFreeConnector(conn);
	}
	(void)best;

	/* A disabled output can still have the CRTC from its encoder. */
	if (!c->have_crtc) {
		for (int i = 0; i < res->count_encoders && !c->have_crtc; i++) {
			drmModeEncoder *enc = drmModeGetEncoder(fd,
								res->encoders[i]);
			if (enc == NULL)
				continue;
			if (enc->crtc_id) {
				c->crtc_id = enc->crtc_id;
				c->have_crtc = 1;
			}
			drmModeFreeEncoder(enc);
		}
	}
	drmModeFreeResources(res);
	return c->have_mode;
}

/* Index of the active CRTC in the resources array, -1 when unknown. */
static int drm_crtc_index(struct smi_ctx *c)
{
	drmModeRes *res;
	int fd = drm_fd(c);
	int idx = -1;

	if (fd < 0)
		return -1;
	res = drmModeGetResources(fd);
	if (res == NULL)
		return -1;
	if (c->have_crtc) {
		for (int i = 0; i < res->count_crtcs; i++) {
			if (res->crtcs[i] == c->crtc_id) {
				idx = i;
				break;
			}
		}
	}
	drmModeFreeResources(res);
	return idx;
}

/* ------------------------------------------------------------------ */
/* connector discovery from sysfs                                      */
/* ------------------------------------------------------------------ */

static void connector_prefix(char *out, size_t cap, int index)
{
	snprintf(out, cap, "card%d-", index);
}

/*
 * Pick the connector for this card: a connected one wins over an enabled
 * one, which wins over the first entry.  Pure sysfs, no probing.
 */
static int find_connector(struct smi_ctx *c)
{
	char drm_dir[SMI_PATH_MAX];
	char prefix[32];
	char best_dir[SMI_PATH_MAX] = "";
	char best_name[64] = "";
	int best_score = -1;
	DIR *dir;
	struct dirent *ent;

	if (c->connector_found)
		return 1;
	if (!card_sysfs_exists(c))
		return 0;
	if (snprintf(drm_dir, sizeof(drm_dir), "%s/class/drm",
		     c->sysfs_root) >= (int)sizeof(drm_dir))
		return 0;
	connector_prefix(prefix, sizeof(prefix), c->card_index);
	dir = opendir(drm_dir);
	if (dir == NULL)
		return 0;
	while ((ent = readdir(dir)) != NULL) {
		char status[SMI_PATH_MAX];
		char path[SMI_PATH_MAX];
		char value[64];
		const char *name;
		int score = 0;
		int rc;

		if (strncmp(ent->d_name, prefix, strlen(prefix)) != 0)
			continue;
		name = ent->d_name + strlen(prefix);
		if (*name == '\0')
			continue;
		if (snprintf(path, sizeof(path), "%s/%s/status", drm_dir,
			     ent->d_name) >= (int)sizeof(path))
			continue;
		status[0] = '\0';
		rc = read_first_line(path, value, sizeof(value));
		if (rc > 0) {
			strncpy(status, value, sizeof(status) - 1);
			status[sizeof(status) - 1] = '\0';
		}
		if (rc > 0 && strcmp(value, "connected") == 0)
			score = 2;
		else if (rc > 0 && strcmp(value, "disconnected") != 0)
			score = 1;
		if (snprintf(path, sizeof(path), "%s/%s", drm_dir,
			     ent->d_name) >= (int)sizeof(path))
			continue;
		if (score > best_score) {
			best_score = score;
			copy_str(best_name, sizeof(best_name), name);
			copy_str(best_dir, sizeof(best_dir), path);
		}
	}
	closedir(dir);
	if (best_score < 0)
		return 0;
	copy_str(c->connector_name, sizeof(c->connector_name), best_name);
	copy_str(c->connector_dir, sizeof(c->connector_dir), best_dir);
	c->connector_found = 1;
	return 1;
}

/* ------------------------------------------------------------------ */
/* process scan                                                        */
/* ------------------------------------------------------------------ */

/*
 * Scan <proc>/<pid>/fd and match each open file against the card node by
 * (st_dev, st_ino).  Only entries the caller may read are seen; unreadable
 * ones increment partial_procs so the output can say the list may be partial.
 * The matching entries are cached in the context because both the
 * processes.count field and the table read them.
 */
static int scan_procs(struct smi_ctx *c)
{
	DIR *proc;
	struct dirent *pent;

	if (c->procs_scanned)
		return c->procs_ok;
	c->procs_scanned = 1;
	c->procs_ok = 0;
	if (!c->card_stat_ok)
		return 0;
	proc = opendir(c->proc_root);
	if (proc == NULL)
		return 0;
	while ((pent = readdir(proc)) != NULL) {
		char fddir[SMI_PATH_MAX];
		char commpath[SMI_PATH_MAX];
		char comm[64] = "?";
		DIR *fd;
		struct dirent *fent;
		pid_t pid;
		char *end;
		int matched = 0;
		FILE *f;

		if (pent->d_name[0] < '0' || pent->d_name[0] > '9')
			continue;
		errno = 0;
		pid = (pid_t)strtol(pent->d_name, &end, 10);
		if (errno != 0 || *end != '\0' || pid <= 0)
			continue;
		if (snprintf(fddir, sizeof(fddir), "%s/%s/fd", c->proc_root,
			     pent->d_name) >= (int)sizeof(fddir))
			continue;
		if (snprintf(commpath, sizeof(commpath), "%s/%s/comm",
			     c->proc_root, pent->d_name) >= (int)sizeof(commpath))
			continue;
		fd = opendir(fddir);
		if (fd == NULL) {
			if (errno == EACCES || errno == EPERM)
				c->partial_procs++;
			continue;
		}
		while ((fent = readdir(fd)) != NULL) {
			char fdpath[SMI_PATH_MAX];
			struct stat st;

			if (fent->d_name[0] < '0' || fent->d_name[0] > '9')
				continue;
			if (snprintf(fdpath, sizeof(fdpath), "%s/%s",
				     fddir, fent->d_name) >=
			    (int)sizeof(fdpath))
				continue;
			if (stat(fdpath, &st) != 0)
				continue;
			if (st.st_dev == c->card_dev &&
			    st.st_ino == c->card_ino) {
				matched = 1;
				break;
			}
		}
		closedir(fd);
		if (!matched)
			continue;
		f = fopen(commpath, "r");
		if (f != NULL) {
			if (fgets(comm, sizeof(comm), f) != NULL)
				trim(comm);
			fclose(f);
		}
		c->procs_total++;
		if (c->procs_shown < (int)(sizeof(c->procs) /
					   sizeof(c->procs[0]))) {
			c->procs[c->procs_shown].pid = pid;
			copy_str(c->procs[c->procs_shown].comm,
				 sizeof(c->procs[0].comm), comm);
			copy_str(c->procs[c->procs_shown].node,
				 sizeof(c->procs[0].node),
				 c->card_path ? c->card_path : "?");
			c->procs_shown++;
		}
	}
	closedir(proc);
	c->procs_ok = 1;
	return 1;
}

static void print_process_table(struct smi_ctx *c)
{
	printf("\nProcesses:\n");
	if (!c->card_stat_ok) {
		printf("  n/a (card node not accessible)\n");
		return;
	}
	if (!scan_procs(c)) {
		printf("  n/a (cannot scan the process table)\n");
		return;
	}
	printf("  PID      COMMAND           NODE\n");
	if (c->procs_total == 0)
		printf("  (none: no process holds the card node)\n");
	for (int i = 0; i < c->procs_shown; i++)
		printf("  %-7d  %-16.16s  %s\n", (int)c->procs[i].pid,
		       c->procs[i].comm, c->procs[i].node);
	if (c->procs_total > c->procs_shown)
		printf("  (%d more not shown)\n", c->procs_total - c->procs_shown);
	if (c->partial_procs > 0)
		printf("  (list may be partial: %d /proc entries were not readable)\n",
		       c->partial_procs);
}

/* ------------------------------------------------------------------ */
/* field getters                                                       */
/* ------------------------------------------------------------------ */

static int get_name(struct smi_ctx *c, char *out, size_t cap,
		    const char **reason)
{
	char buf[256];
	int rc = uevent_get(c, "DRIVER", buf, sizeof(buf));

	if (rc > 0) {
		if (strlen(buf) >= cap) {
			*reason = "driver name does not fit the value buffer";
			return 0;
		}
		strcpy(out, buf);
		return 1;
	}
	/* Fall back to the device/driver symlink basename. */
	{
		char base[SMI_PATH_MAX];
		char path[SMI_PATH_MAX];
		char real[SMI_PATH_MAX];
		const char *slash;

		if (snprintf(base, sizeof(base), "%s/class/drm/card%d/device",
			     c->sysfs_root, c->card_index) >=
		    (int)sizeof(base))
			return 0;
		if (join2(path, sizeof(path), base, "driver"))
			return 0;
		if (realpath(path, real) != NULL) {
			slash = strrchr(real, '/');
			if (slash != NULL && slash[1] != '\0') {
				snprintf(out, cap, "%s", slash + 1);
				return 1;
			}
		}
	}
	*reason = "no driver name in uevent or driver symlink";
	return 0;
}

static int get_driver_version(struct smi_ctx *c, char *out, size_t cap,
			      const char **reason)
{
	char path[SMI_PATH_MAX];

	if (join3(path, sizeof(path), c->sysfs_root, "module",
		  SMI_DRIVER) != 0)
		return 0;
	if (append_path(path, sizeof(path), "version") != 0)
		return 0;
	if (read_first_line(path, out, cap) > 0)
		return 1;
	*reason = "module version attribute not present";
	return 0;
}

static int get_srcversion(struct smi_ctx *c, char *out, size_t cap,
			  const char **reason)
{
	char path[SMI_PATH_MAX];

	if (join3(path, sizeof(path), c->sysfs_root, "module",
		  SMI_DRIVER) != 0)
		return 0;
	if (append_path(path, sizeof(path), "srcversion") != 0)
		return 0;
	if (read_first_line(path, out, cap) > 0)
		return 1;
	*reason = "module srcversion attribute not present";
	return 0;
}

static int get_bus_id(struct smi_ctx *c, char *out, size_t cap,
		      const char **reason)
{
	char buf[128];
	char base[SMI_PATH_MAX];
	char cardsys[SMI_PATH_MAX];
	char real[SMI_PATH_MAX];
	const char *slash;
	int rc;

	rc = uevent_get(c, "PCI_SLOT_NAME", buf, sizeof(buf));
	if (rc > 0) {
		if (strlen(buf) >= cap) {
			*reason = "PCI slot name does not fit the value buffer";
			return 0;
		}
		strcpy(out, buf);
		return 1;
	}
	if (snprintf(cardsys, sizeof(cardsys), "%s/class/drm/card%d",
		     c->sysfs_root, c->card_index) >= (int)sizeof(cardsys))
		return 0;
	if (join2(base, sizeof(base), cardsys, "device"))
		return 0;
	if (realpath(base, real) != NULL) {
		slash = strrchr(real, '/');
		if (slash != NULL && strchr(slash + 1, ':') != NULL) {
			snprintf(out, cap, "%s", slash + 1);
			return 1;
		}
	}
	*reason = "PCI slot name not available";
	return 0;
}

static int get_pci_id(struct smi_ctx *c, char *out, size_t cap,
		      const char **reason, const char *devattr,
		      const char *vendattr)
{
	char dev[64];
	char ven[64];
	char path[SMI_PATH_MAX];
	char base[SMI_PATH_MAX];
	char ndev[32];
	char nven[32];

	if (snprintf(base, sizeof(base), "%s/class/drm/card%d/device",
		     c->sysfs_root, c->card_index) >= (int)sizeof(base))
		return 0;
	if (join2(path, sizeof(path), base, devattr) != 0)
		return 0;
	if (read_first_line(path, dev, sizeof(dev)) <= 0) {
		*reason = "PCI device id attribute not present";
		return 0;
	}
	if (join2(path, sizeof(path), base, vendattr) != 0)
		return 0;
	if (read_first_line(path, ven, sizeof(ven)) <= 0) {
		*reason = "PCI vendor id attribute not present";
		return 0;
	}
	if (norm_hex(dev, ndev, sizeof(ndev)) != 0 ||
	    norm_hex(ven, nven, sizeof(nven)) != 0) {
		*reason = "malformed PCI id attribute";
		return 0;
	}
	if ((size_t)snprintf(out, cap, "%s:%s", nven, ndev) >= cap) {
		*reason = "PCI id does not fit the value buffer";
		return 0;
	}
	return 1;
}

static int get_pci_device_id(struct smi_ctx *c, char *out, size_t cap,
			     const char **reason)
{
	return get_pci_id(c, out, cap, reason, "device", "vendor");
}

static int get_pci_subsystem_id(struct smi_ctx *c, char *out, size_t cap,
				const char **reason)
{
	return get_pci_id(c, out, cap, reason, "subsystem_device",
			  "subsystem_vendor");
}

static int get_pci_revision(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason)
{
	char buf[64];
	int rc = read_card_attr(c, "device/revision", buf, sizeof(buf));

	if (rc > 0) {
		if (norm_hex(buf, out, cap) != 0) {
			*reason = "malformed revision attribute";
			return 0;
		}
		return 1;
	}
	*reason = "revision attribute not present";
	return 0;
}

static int get_memory_total(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason)
{
	static const char *const rels[] = {
		"device/mem_info_vram_total",
		"device/vram_total_bytes",
		"vram_total_bytes"
	};
	char buf[64];
	unsigned long long v;
	int err = 0;
	int rc;

	rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
			     sizeof(buf), &err);
	if (rc <= 0) {
		*reason = card_sysfs_exists(c) ? reason_attr_missing
					       : reason_card_missing;
		return 0;
	}
	if (parse_u64(buf, &v) != 0) {
		*reason = "malformed memory total attribute";
		return 0;
	}
	snprintf(out, cap, "%llu", v);
	return 1;
}

static int get_memory_used(struct smi_ctx *c, char *out, size_t cap,
			   const char **reason)
{
	static const char *const rels[] = {
		"device/mem_info_vram_used",
		"device/vram_used_bytes",
		"vram_used_bytes"
	};
	char buf[64];
	unsigned long long v;
	int err = 0;
	int rc;

	rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
			     sizeof(buf), &err);
	if (rc <= 0) {
		*reason = card_sysfs_exists(c) ? reason_attr_missing
					       : reason_card_missing;
		return 0;
	}
	if (parse_u64(buf, &v) != 0) {
		*reason = "malformed memory used attribute";
		return 0;
	}
	snprintf(out, cap, "%llu", v);
	return 1;
}

static int get_memory_free(struct smi_ctx *c, char *out, size_t cap,
			   const char **reason)
{
	char total[SMI_VALUE_MAX];
	char used[SMI_VALUE_MAX];
	const char *why = NULL;
	unsigned long long t, u;

	if (get_memory_total(c, total, sizeof(total), &why) != 1) {
		*reason = why;
		return 0;
	}
	if (get_memory_used(c, used, sizeof(used), &why) != 1) {
		*reason = why;
		return 0;
	}
	if (parse_u64(total, &t) != 0 || parse_u64(used, &u) != 0) {
		*reason = "malformed memory attribute";
		return 0;
	}
	if (u > t) {
		*reason = "used bytes exceed total bytes";
		return 0;
	}
	snprintf(out, cap, "%llu", t - u);
	return 1;
}

static int get_display_connector(struct smi_ctx *c, char *out, size_t cap,
				 const char **reason)
{
	if (find_connector(c)) {
		if (strlen(c->connector_name) >= cap) {
			*reason = "connector name does not fit the value buffer";
			return 0;
		}
		strcpy(out, c->connector_name);
		return 1;
	}
	*reason = "no connector entry under /sys/class/drm";
	return 0;
}

static int get_display_connected(struct smi_ctx *c, char *out, size_t cap,
				 const char **reason)
{
	char path[SMI_PATH_MAX];

	if (!find_connector(c)) {
		*reason = "no connector entry under /sys/class/drm";
		return 0;
	}
	if (join2(path, sizeof(path), c->connector_dir, "status") != 0)
		return 0;
	if (read_first_line(path, out, cap) > 0)
		return 1;
	*reason = "connector status attribute not readable";
	return 0;
}

static int get_display_mode(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason)
{
	static const char *const rels[] = {
		"device/active_mode"
	};
	char buf[SMI_VALUE_MAX];
	char path[SMI_PATH_MAX];
	char geom[64];
	unsigned int w, h;
	char extra;
	int err = 0;
	int rc;

	rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
			     sizeof(buf), &err);
	if (rc > 0) {
		if (sscanf(buf, "%u%*1[x]%u%c", &w, &h, &extra) != 2) {
			*reason = "malformed active_mode attribute";
			return 0;
		}
		snprintf(out, cap, "%ux%u", w, h);
		return 1;
	}
	if (!find_connector(c)) {
		*reason = "no connector entry under /sys/class/drm";
		return 0;
	}
	if (join2(path, sizeof(path), c->connector_dir, "modes") != 0)
		return 0;
	rc = read_first_line(path, geom, sizeof(geom));
	if (rc <= 0) {
		*reason = "no active mode (connector modes list is empty)";
		return 0;
	}
	if (sscanf(geom, "%u%*1[x]%u%c", &w, &h, &extra) != 2) {
		*reason = "malformed modes attribute";
		return 0;
	}
	snprintf(out, cap, "%ux%u", w, h);
	return 1;
}

static int get_display_refresh(struct smi_ctx *c, char *out, size_t cap,
			       const char **reason)
{
	static const char *const rels[] = {
		"device/active_mode_refresh_hz"
	};
	char buf[64];
	double v;
	int err = 0;
	int rc;

	rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
			     sizeof(buf), &err);
	if (rc > 0) {
		if (parse_double(buf, &v) != 0 || v <= 0.0) {
			*reason = "malformed refresh attribute";
			return 0;
		}
		snprintf(out, cap, "%.2f", v);
		return 1;
	}
	if (drm_load_mode(c) && c->mode.htotal > 0 && c->mode.vtotal > 0) {
		double hz = (double)c->mode.clock * 1000.0 /
			    ((double)c->mode.htotal * (double)c->mode.vtotal);

		snprintf(out, cap, "%.2f", hz);
		return 1;
	}
	*reason = "driver attribute not present and no DRM mode";
	return 0;
}

static int get_display_pixel_clock(struct smi_ctx *c, char *out, size_t cap,
				   const char **reason)
{
	static const char *const rels[] = {
		"device/active_mode_pixel_clock_khz"
	};
	char buf[64];
	unsigned long long v;
	int err = 0;
	int rc;

	rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
			     sizeof(buf), &err);
	if (rc > 0) {
		if (parse_u64(buf, &v) != 0) {
			*reason = "malformed pixel clock attribute";
			return 0;
		}
		snprintf(out, cap, "%llu", v);
		return 1;
	}
	if (drm_load_mode(c) && c->mode.clock > 0) {
		snprintf(out, cap, "%u", c->mode.clock);
		return 1;
	}
	*reason = "driver attribute not present and no DRM mode";
	return 0;
}

static int get_attr_or_reason(struct smi_ctx *c, char *out, size_t cap,
			      const char **reason, const char *const *rels,
			      size_t n)
{
	char buf[SMI_VALUE_MAX];
	int err = 0;
	int rc = read_candidates(c, rels, n, buf, sizeof(buf), &err);

	if (rc > 0) {
		if (strlen(buf) >= cap) {
			*reason = "attribute does not fit the value buffer";
			return 0;
		}
		strcpy(out, buf);
		return 1;
	}
	*reason = card_sysfs_exists(c) ? reason_attr_missing
				       : reason_card_missing;
	return 0;
}

static int get_display_hpd(struct smi_ctx *c, char *out, size_t cap,
			   const char **reason)
{
	static const char *const rels[] = { "device/hpd" };

	return get_attr_or_reason(c, out, cap, reason, rels,
				  sizeof(rels) / sizeof(rels[0]));
}

static int get_display_rxsense(struct smi_ctx *c, char *out, size_t cap,
			       const char **reason)
{
	static const char *const rels[] = { "device/rxsense" };

	return get_attr_or_reason(c, out, cap, reason, rels,
				  sizeof(rels) / sizeof(rels[0]));
}

static int get_display_link(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason)
{
	static const char *const rels[] = { "device/link_state" };

	return get_attr_or_reason(c, out, cap, reason, rels,
				  sizeof(rels) / sizeof(rels[0]));
}

static int get_crtc_index(struct smi_ctx *c, char *out, size_t cap,
			  const char **reason)
{
	static const char *const rels[] = { "device/active_crtc" };
	char buf[64];
	unsigned long long v;
	int err = 0;
	int rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
				 sizeof(buf), &err);

	if (rc > 0) {
		/* The driver writes -1 when its CRTC is not enabled. */
		if (strcmp(buf, "-1") == 0) {
			*reason = reason_no_active_crtc;
			return 0;
		}
		if (parse_u64(buf, &v) != 0) {
			*reason = "malformed active_crtc attribute";
			return 0;
		}
		snprintf(out, cap, "%llu", v);
		return 1;
	}
	if (drm_load_mode(c)) {
		int idx = drm_crtc_index(c);

		if (idx >= 0) {
			snprintf(out, cap, "%d", idx);
			return 1;
		}
		*reason = reason_no_active_crtc;
		return 0;
	}
	*reason = "no active CRTC exposed by sysfs or DRM";
	return 0;
}

static int get_vblank_count(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason)
{
	static const char *const rels[] = { "device/vblank_count" };
	char buf[64];
	unsigned long long v;
	int err = 0;
	int rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
				 sizeof(buf), &err);

	if (rc > 0) {
		if (parse_u64(buf, &v) != 0) {
			*reason = "malformed vblank_count attribute";
			return 0;
		}
		snprintf(out, cap, "%llu", v);
		return 1;
	}
	if (drm_load_mode(c) && c->have_crtc) {
		uint64_t seq = 0;
		uint64_t ns = 0;

		if (drmCrtcGetSequence(drm_fd(c), c->crtc_id, &seq, &ns) == 0) {
			snprintf(out, cap, "%llu", (unsigned long long)seq);
			return 1;
		}
	}
	*reason = "vblank sequence not available from sysfs or DRM";
	return 0;
}

static int get_crc_support(struct smi_ctx *c, char *out, size_t cap,
			   const char **reason)
{
	static const char *const rels[] = { "device/crc_supported" };
	char buf[SMI_VALUE_MAX];
	char path[SMI_PATH_MAX];
	char dir[SMI_PATH_MAX];
	int err = 0;
	int rc = read_candidates(c, rels, sizeof(rels) / sizeof(rels[0]), buf,
				 sizeof(buf), &err);

	if (rc > 0) {
		if (strlen(buf) >= cap) {
			*reason = "crc_supported does not fit the value buffer";
			return 0;
		}
		strcpy(out, buf);
		return 1;
	}
	{
		int idx = -1;

		if (drm_load_mode(c))
			idx = drm_crtc_index(c);
		if (idx < 0)
			idx = 0;
		if (snprintf(dir, sizeof(dir), "%s/kernel/debug/dri/%d",
			     c->sysfs_root, c->card_index) >=
		    (int)sizeof(dir))
			return 0;
		if (snprintf(path, sizeof(path), "%s/crtc-%d/crc/control",
			     dir, idx) >= (int)sizeof(path))
			return 0;
	}
	{
		int fd = open(path, O_RDONLY | O_CLOEXEC);

		if (fd >= 0) {
			close(fd);
			snprintf(out, cap, "yes");
			return 1;
		}
		if (errno == EACCES || errno == EPERM) {
			*reason = reason_needs_root;
			return 0;
		}
	}
	*reason = "CRC control not present (debugfs absent or no CRC support)";
	return 0;
}

static int get_module_param(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason, const char *name)
{
	char dir[SMI_PATH_MAX];
	char path[SMI_PATH_MAX];

	if (join3(dir, sizeof(dir), c->sysfs_root, "module", SMI_DRIVER) != 0)
		return 0;
	if (join3(path, sizeof(path), dir, "parameters", name) != 0)
		return 0;
	if (read_first_line(path, out, cap) > 0)
		return 1;
	*reason = "module parameter not present (module not loaded or older build)";
	return 0;
}

static int get_test_pattern(struct smi_ctx *c, char *out, size_t cap,
			    const char **reason)
{
	return get_module_param(c, out, cap, reason, "test_pattern");
}

static int get_test_pattern_period(struct smi_ctx *c, char *out, size_t cap,
				   const char **reason)
{
	return get_module_param(c, out, cap, reason, "test_pattern_period_ms");
}

static int get_test_pattern_anim(struct smi_ctx *c, char *out, size_t cap,
				 const char **reason)
{
	return get_module_param(c, out, cap, reason, "test_pattern_anim_ms");
}

static int get_processes_count(struct smi_ctx *c, char *out, size_t cap,
			       const char **reason)
{
	if (!c->card_stat_ok) {
		*reason = "card node not accessible; cannot match open files";
		return 0;
	}
	if (!scan_procs(c)) {
		*reason = "cannot scan the process table";
		return 0;
	}
	snprintf(out, cap, "%d", c->procs_total);
	return 1;
}

static int get_power_runtime_status(struct smi_ctx *c, char *out, size_t cap,
				    const char **reason)
{
	char path[SMI_PATH_MAX];
	char base[SMI_PATH_MAX];

	if (snprintf(base, sizeof(base), "%s/class/drm/card%d/device/power",
		     c->sysfs_root, c->card_index) >= (int)sizeof(base))
		return 0;
	if (join2(path, sizeof(path), base, "runtime_status") != 0)
		return 0;
	if (read_first_line(path, out, cap) > 0)
		return 1;
	*reason = "power/runtime_status attribute not present";
	return 0;
}

static int get_module_loaded(struct smi_ctx *c, char *out, size_t cap,
			     const char **reason)
{
	char path[SMI_PATH_MAX];
	struct stat st;

	(void)reason;
	if (join3(path, sizeof(path), c->sysfs_root, "module", SMI_DRIVER) != 0)
		return 0;
	snprintf(out, cap, "%s", stat(path, &st) == 0 ? "yes" : "no");
	return 1;
}

/* ------------------------------------------------------------------ */
/* field table                                                         */
/* ------------------------------------------------------------------ */

static const struct field_def fields[] = {
	{ "name", "Driver name",
	  "sysfs device uevent DRIVER (fallback: driver symlink)",
	  get_name },
	{ "driver_version", "Driver version from the module",
	  "sysfs /sys/module/sm750hdmidrm/version",
	  get_driver_version },
	{ "srcversion", "Build srcversion of the loaded module",
	  "sysfs /sys/module/sm750hdmidrm/srcversion",
	  get_srcversion },
	{ "bus_id", "PCI bus id (domain:bus:slot.function)",
	  "sysfs device uevent PCI_SLOT_NAME",
	  get_bus_id },
	{ "pci.device_id", "PCI vendor:device id",
	  "sysfs device/{vendor,device}",
	  get_pci_device_id },
	{ "pci.subsystem_id", "PCI subsystem vendor:device id",
	  "sysfs device/{subsystem_vendor,subsystem_device}",
	  get_pci_subsystem_id },
	{ "pci.revision", "PCI revision id",
	  "sysfs device/revision",
	  get_pci_revision },
	{ "memory.total", "Total VRAM in bytes",
	  "sysfs device/mem_info_vram_total or device/vram_total_bytes",
	  get_memory_total },
	{ "memory.used", "VRAM in use in bytes",
	  "sysfs device/mem_info_vram_used or device/vram_used_bytes",
	  get_memory_used },
	{ "memory.free", "VRAM not in use in bytes",
	  "derived: memory.total - memory.used",
	  get_memory_free },
	{ "display.connector", "Active connector name",
	  "sysfs class/drm/cardN-*/status ordering",
	  get_display_connector },
	{ "display.connected", "Connector connection state",
	  "sysfs class/drm/cardN-*/status",
	  get_display_connected },
	{ "display.mode", "Active mode geometry WxH",
	  "sysfs device/active_mode or cardN-*/modes first line",
	  get_display_mode },
	{ "display.refresh_hz", "Active refresh rate in Hz",
	  "sysfs device/active_mode_refresh_hz or libdrm mode timings",
	  get_display_refresh },
	{ "display.pixel_clock_khz", "Active pixel clock in kHz",
	  "sysfs device/active_mode_pixel_clock_khz or libdrm mode clock",
	  get_display_pixel_clock },
	{ "display.hpd", "HPD line state",
	  "sysfs device/hpd",
	  get_display_hpd },
	{ "display.rxsense", "Receiver sense line state",
	  "sysfs device/rxsense",
	  get_display_rxsense },
	{ "display.link", "Link state",
	  "sysfs device/link_state",
	  get_display_link },
	{ "crtc.index", "Active CRTC index",
	  "sysfs device/active_crtc or libdrm encoder CRTC",
	  get_crtc_index },
	{ "vblank.count", "Vblank sequence of the active CRTC",
	  "sysfs device/vblank_count or libdrm drmCrtcGetSequence",
	  get_vblank_count },
	{ "crc.support", "Scanout CRC availability",
	  "sysfs device/crc_supported or debugfs crtc-N/crc/control",
	  get_crc_support },
	{ "test_pattern", "test_pattern module parameter",
	  "sysfs /sys/module/sm750hdmidrm/parameters/test_pattern",
	  get_test_pattern },
	{ "test_pattern_period_ms", "test_pattern_period_ms module parameter",
	  "sysfs .../parameters/test_pattern_period_ms",
	  get_test_pattern_period },
	{ "test_pattern_anim_ms", "test_pattern_anim_ms module parameter",
	  "sysfs .../parameters/test_pattern_anim_ms",
	  get_test_pattern_anim },
	{ "processes.count", "Processes holding the card node",
	  "scan of <proc>/<pid>/fd matched against the card node",
	  get_processes_count },
	{ "power.runtime_status", "PCI runtime power status",
	  "sysfs device/power/runtime_status",
	  get_power_runtime_status },
	{ "module_loaded", "Whether sm750hdmidrm is loaded",
	  "presence of sysfs /sys/module/sm750hdmidrm",
	  get_module_loaded },
};

#define FIELD_COUNT (sizeof(fields) / sizeof(fields[0]))

static int find_field(const char *name)
{
	for (size_t i = 0; i < FIELD_COUNT; i++) {
		if (strcmp(fields[i].name, name) == 0)
			return (int)i;
	}
	return -1;
}

/* ------------------------------------------------------------------ */
/* output                                                             */
/* ------------------------------------------------------------------ */

static int use_color;

static void emit_table_row(const char *name, const char *value, int pretty)
{
	int n;

	if (pretty)
		n = printf("  %-28s %s\n", name, value);
	else
		n = printf("%s  %s\n", name, value);
	(void)n;
}

static void emit_csv_header(const int *idx, int n)
{
	for (int i = 0; i < n; i++) {
		if (i > 0)
			putchar(',');
		printf("\"%s\"", fields[idx[i]].name);
	}
	putchar('\n');
}

static int csv_needs_quote(const char *s)
{
	size_t n = strlen(s);

	if (n == 0 || s[0] == ' ' || s[n - 1] == ' ')
		return 1;
	for (; *s; s++) {
		if (*s == ',' || *s == '"' || *s == '\\' || *s == '\n')
			return 1;
	}
	return 0;
}

static void csv_escape(const char *s)
{
	if (!csv_needs_quote(s)) {
		fputs(s, stdout);
		return;
	}
	putchar('"');
	for (; *s; s++) {
		if (*s == '"' || *s == '\\')
			putchar('\\');
		putchar(*s);
	}
	putchar('"');
}

static void emit_csv_row(char (*values)[SMI_VALUE_MAX], int n)
{
	for (int i = 0; i < n; i++) {
		if (i > 0)
			putchar(',');
		csv_escape(values[i]);
	}
	putchar('\n');
}

static void json_escape(const char *s)
{
	putchar('"');
	for (; *s; s++) {
		unsigned char ch = (unsigned char)*s;

		if (ch == '"' || ch == '\\') {
			putchar('\\');
			putchar(ch);
		} else if (ch == '\n') {
			fputs("\\n", stdout);
		} else if (ch == '\t') {
			fputs("\\t", stdout);
		} else if (ch < 0x20) {
			printf("\\u%04x", ch);
		} else {
			putchar(ch);
		}
	}
	putchar('"');
}

static void emit_json(const int *idx, char (*values)[SMI_VALUE_MAX],
		       int n)
{
	putchar('[');
	putchar('{');
	for (int i = 0; i < n; i++) {
		if (i > 0)
			putchar(',');
		json_escape(fields[idx[i]].name);
		putchar(':');
		json_escape(values[i]);
	}
	putchar('}');
	putchar(']');
	putchar('\n');
}

/*
 * Resolve every requested field once.  values[] holds the printable string
 * ("n/a" when unresolved) and reasons[] the unavailable reason or NULL.
 */
static void resolve_fields(struct smi_ctx *c, const int *idx, int n,
			   char (*values)[SMI_VALUE_MAX],
			   const char **reasons)
{
	for (int i = 0; i < n; i++) {
		const char *reason = NULL;
		int rc = fields[idx[i]].get(c, values[i], SMI_VALUE_MAX,
					    &reason);

		if (rc == 1) {
			reasons[i] = NULL;
			continue;
		}
		snprintf(values[i], SMI_VALUE_MAX, "n/a");
		reasons[i] = reason != NULL ? reason : "unavailable";
	}
}

static void print_banner(struct smi_ctx *c, int pretty)
{
	char version[SMI_VALUE_MAX] = "n/a";
	char srcversion[SMI_VALUE_MAX] = "n/a";
	char busid[SMI_VALUE_MAX] = "n/a";
	const char *why = NULL;
	char when[64];
	time_t now = time(NULL);
	struct tm tm_now;

	fields[find_field("driver_version")].get(c, version, sizeof(version),
						 &why);
	why = NULL;
	fields[find_field("srcversion")].get(c, srcversion,
					     sizeof(srcversion), &why);
	why = NULL;
	fields[find_field("bus_id")].get(c, busid, sizeof(busid), &why);
	localtime_r(&now, &tm_now);
	strftime(when, sizeof(when), "%a %b %e %H:%M:%S %Y", &tm_now);

	if (pretty && use_color)
		printf("\033[1m");
	printf("+-----------------------------------------------------------------------------+\n");
	printf("| %-75s |\n", SMI_TOOL_NAME " - Silicon Motion SM750 monitoring");
	printf("| Driver Version: %-20s SrcVersion: %-26.26s |\n", version,
	       srcversion);
	printf("| PCI Bus Id: %-63.63s |\n", busid);
	printf("+-----------------------------------------------------------------------------+\n");
	if (pretty && use_color)
		printf("\033[0m");
	printf("%s\n", when);
	if (!c->card_stat_ok)
		printf("%s: card node '%s' is not accessible; showing the PCI-only view (exit 2)\n",
		       SMI_TOOL_NAME, c->card_path ? c->card_path : "(none)");
	if (c->partial_procs > 0 && pretty)
		printf("processes: %d /proc entries were not readable; the list may be partial\n",
		       c->partial_procs);
}

static void render_once(struct smi_ctx *c, const int *idx, int n,
			enum smi_format fmt, int default_view, int strict)
{
	char values[FIELD_COUNT][SMI_VALUE_MAX];
	const char *reasons[FIELD_COUNT];
	int unresolved = 0;

	resolve_fields(c, idx, n, values, reasons);
	for (int i = 0; i < n; i++) {
		if (reasons[i] != NULL)
			unresolved++;
	}

	if (default_view && fmt == SMI_FMT_TABLE)
		print_banner(c, 1);

	switch (fmt) {
	case SMI_FMT_TABLE:
		if (!default_view) {
			printf("Field Value\n");
		}
		for (int i = 0; i < n; i++) {
			char shown[SMI_VALUE_MAX + 96];

			if (reasons[i] != NULL && default_view) {
				snprintf(shown, sizeof(shown), "n/a (%s)",
					 reasons[i]);
				emit_table_row(fields[idx[i]].name, shown, 1);
			} else {
				emit_table_row(fields[idx[i]].name, values[i], 1);
			}
		}
		break;
	case SMI_FMT_CSV:
		emit_csv_header(idx, n);
		emit_csv_row(values, n);
		break;
	case SMI_FMT_CSV_NOHEADER:
		emit_csv_row(values, n);
		break;
	case SMI_FMT_JSON:
		emit_json(idx, values, n);
		break;
	}

	if (default_view && fmt == SMI_FMT_TABLE)
		print_process_table(c);

	if (strict && unresolved > 0) {
		for (int i = 0; i < n; i++) {
			if (reasons[i] != NULL)
				fprintf(stderr, "%s: n/a (%s)\n",
					fields[idx[i]].name, reasons[i]);
		}
	}
}

/* ------------------------------------------------------------------ */
/* options                                                            */
/* ------------------------------------------------------------------ */

static void usage(FILE *out)
{
	fputs(
"NAME\n"
"       sm750-smi - monitor the Silicon Motion SM750 DRM/KMS driver\n"
"\n"
"SYNOPSIS\n"
"       sm750-smi [OPTION]...\n"
"\n"
"DESCRIPTION\n"
"       Prints a banner and one device block: driver name, version and\n"
"       srcversion, PCI identity, VRAM use, display state, vblank, CRC\n"
"       availability, tunable module parameters and the processes that hold\n"
"       the card node.  Every value is read from sysfs, from libdrm through\n"
"       the card node, or from debugfs; a value that cannot be read is shown\n"
"       as n/a together with the reason.\n"
"\n"
"OPTIONS\n"
"       --query=FIELD[,FIELD...]\n"
"              Print only the requested fields.  Values are comma separated\n"
"              unless --format selects another shape.  Exits 3 with --strict\n"
"              when any requested field is unresolved.\n"
"       --format=table|csv|csv,noheader|json\n"
"              Output shape.  The default for --query is csv,noheader; the\n"
"              default device view is table.\n"
"       --list-fields\n"
"              List every supported field, a one-line description and its\n"
"              data source, then exit.\n"
"       --loop=SECONDS\n"
"              Redraw every SECONDS seconds (minimum 1).  SIGINT exits 0.\n"
"       --once\n"
"              Print once and exit.  This is the default for --query.\n"
"       -i, --id=INDEX\n"
"              Select the device index.  This board has one SM750, index 0.\n"
"       --sysfs-root=PATH\n"
"              Read sysfs below PATH instead of /sys.  Used by the gate with\n"
"              synthetic trees.\n"
"       --card=PATH\n"
"              Use PATH as the DRM card node instead of the detected\n"
"              /dev/dri/cardN.\n"
"       --proc-root=PATH\n"
"              Scan processes below PATH instead of /proc.\n"
"       --no-color\n"
"              Never emit ANSI escape sequences.  Output to a non-tty never\n"
"              contains them regardless of this option.\n"
"       --strict\n"
"              Exit 3 when any requested field is unresolved; the reasons are\n"
"              written to stderr.\n"
"       -h, --help\n"
"              Print this page.\n"
"\n"
"EXIT STATUS\n"
"       0  success\n"
"       1  usage or I/O error in the tool itself\n"
"       2  the card node is not accessible; the PCI-only view was printed\n"
"       3  --strict was given and at least one requested field is unresolved\n"
"\n"
"FIELDS\n"
"       Run --list-fields for the authoritative list, its descriptions and\n"
"       the data source of each value.\n"
"\n"
"EXAMPLES\n"
"       sm750-smi\n"
"       sm750-smi --query=driver_version,memory.total,memory.used\n"
"       sm750-smi --query=display.mode,display.refresh_hz --format=json\n"
"       sm750-smi --loop=2 --no-color\n",
	      out);
}

static int parse_format(const char *s, enum smi_format *fmt)
{
	if (strcmp(s, "table") == 0) {
		*fmt = SMI_FMT_TABLE;
		return 0;
	}
	if (strcmp(s, "csv") == 0) {
		*fmt = SMI_FMT_CSV;
		return 0;
	}
	if (strcmp(s, "csv,noheader") == 0) {
		*fmt = SMI_FMT_CSV_NOHEADER;
		return 0;
	}
	if (strcmp(s, "json") == 0) {
		*fmt = SMI_FMT_JSON;
		return 0;
	}
	return -1;
}

/* Split a comma separated field list.  The string is modified in place. */
static int split_fields(char *list, int *idx, int max)
{
	char *p = list;
	int n = 0;

	if (list == NULL || *list == '\0')
		return -1;
	while (p != NULL && *p != '\0') {
		char *comma = strchr(p, ',');
		int f;

		if (comma != NULL)
			*comma = '\0';
		if (*p == '\0')
			return -1;
		f = find_field(p);
		if (f < 0) {
			fprintf(stderr, "%s: unknown field '%s'\n", SMI_TOOL_NAME,
				p);
			return -1;
		}
		for (int i = 0; i < n; i++) {
			if (idx[i] == f) {
				fprintf(stderr,
					"%s: field '%s' requested twice\n",
					SMI_TOOL_NAME, p);
				return -1;
			}
		}
		if (n >= max)
			return -1;
		idx[n++] = f;
		p = comma != NULL ? comma + 1 : NULL;
	}
	return n;
}

static int detect_card_index(struct smi_ctx *c)
{
	char drm_dir[SMI_PATH_MAX];
	DIR *dir;
	struct dirent *ent;
	int fallback = -1;

	if (snprintf(drm_dir, sizeof(drm_dir), "%s/class/drm",
		     c->sysfs_root) >= (int)sizeof(drm_dir))
		return 0;
	dir = opendir(drm_dir);
	if (dir == NULL)
		return 0;
	while ((ent = readdir(dir)) != NULL) {
		char uevent[SMI_PATH_MAX];
		char line[SMI_SYSFS_PAGE];
		char *end;
		long value;
		FILE *f;

		if (strncmp(ent->d_name, "card", 4) != 0)
			continue;
		errno = 0;
		value = strtol(ent->d_name + 4, &end, 10);
		if (errno != 0 || *end != '\0' || value < 0)
			continue;
		if (fallback < 0 || value < fallback)
			fallback = (int)value;
		if (snprintf(uevent, sizeof(uevent), "%s/%s/device/uevent",
			     drm_dir, ent->d_name) >= (int)sizeof(uevent))
			continue;
		f = fopen(uevent, "r");
		if (f == NULL)
			continue;
		while (fgets(line, sizeof(line), f) != NULL) {
			char *eq;

			trim(line);
			if (strncmp(line, "PCI_ID=", 7) != 0)
				continue;
			eq = line + 7;
			if (strcasecmp(eq, "126F:0750") == 0) {
				closedir(dir);
				fclose(f);
				return (int)value;
			}
		}
		fclose(f);
	}
	closedir(dir);
	return fallback >= 0 ? fallback : 0;
}

static void auto_card_path(struct smi_ctx *c, char *out, size_t cap)
{
	char bypath[SMI_PATH_MAX];

	if (snprintf(bypath, sizeof(bypath),
		     "/dev/dri/by-path/pci-0000:01:00.0-card") == 0)
		bypath[0] = '\0';
	/* Prefer the stable by-path link, then the class index node. */
	if (realpath(bypath, out) == NULL)
		snprintf(out, cap, "/dev/dri/card%d", c->card_index);
}

static volatile sig_atomic_t stop_loop;

static void on_sigint(int sig)
{
	(void)sig;
	stop_loop = 1;
}

int main(int argc, char **argv)
{
	static const struct option long_opts[] = {
		{ "query", required_argument, NULL, 'q' },
		{ "format", required_argument, NULL, 'f' },
		{ "list-fields", no_argument, NULL, 'L' },
		{ "loop", required_argument, NULL, 'l' },
		{ "once", no_argument, NULL, 'o' },
		{ "id", required_argument, NULL, 'i' },
		{ "sysfs-root", required_argument, NULL, 's' },
		{ "card", required_argument, NULL, 'c' },
		{ "proc-root", required_argument, NULL, 'p' },
		{ "no-color", no_argument, NULL, 'C' },
		{ "strict", no_argument, NULL, 'S' },
		{ "help", no_argument, NULL, 'h' },
		{ NULL, 0, NULL, 0 }
	};
	struct smi_ctx ctx;
	int query_idx[FIELD_COUNT];
	int query_n = -1;
	enum smi_format fmt = SMI_FMT_TABLE;
	int fmt_given = 0;
	int list_fields = 0;
	int loop = 0;
	int strict = 0;
	int no_color = 0;
	int id_given = 0;
	int opt;
	int rc = SMI_OK;
	char card_buf[SMI_PATH_MAX];
	char card_real[SMI_PATH_MAX];

	memset(&ctx, 0, sizeof(ctx));
	ctx.sysfs_root = "/sys";
	ctx.proc_root = "/proc";
	ctx.drm_fd = -1;
	ctx.id = 0;
	ctx.card_index = 0;

	while ((opt = getopt_long(argc, argv, "i:h", long_opts, NULL)) != -1) {
		switch (opt) {
		case 'q':
			query_n = 1; /* parsed after the table exists */
			break;
		case 'f':
			if (parse_format(optarg, &fmt) != 0) {
				fprintf(stderr,
					"%s: invalid --format '%s' (table, csv, csv,noheader, json)\n",
					SMI_TOOL_NAME, optarg);
				return SMI_ERR;
			}
			fmt_given = 1;
			break;
		case 'L':
			list_fields = 1;
			break;
		case 'l': {
			char *end;
			long v;

			errno = 0;
			v = strtol(optarg, &end, 10);
			if (errno != 0 || *end != '\0' || v < 1) {
				fprintf(stderr,
					"%s: --loop needs an integer >= 1\n",
					SMI_TOOL_NAME);
				return SMI_ERR;
			}
			loop = (int)v;
			break;
		}
		case 'o':
			break;
		case 'i': {
			char *end;
			long v;

			errno = 0;
			v = strtol(optarg, &end, 10);
			if (errno != 0 || *end != '\0' || v < 0) {
				fprintf(stderr, "%s: invalid --id '%s'\n",
					SMI_TOOL_NAME, optarg);
				return SMI_ERR;
			}
			ctx.id = (int)v;
			id_given = 1;
			break;
		}
		case 's':
			ctx.sysfs_root = optarg;
			break;
		case 'c':
			ctx.card_path = optarg;
			break;
		case 'p':
			ctx.proc_root = optarg;
			break;
		case 'C':
			no_color = 1;
			break;
		case 'S':
			strict = 1;
			break;
		case 'h':
			usage(stdout);
			return SMI_OK;
		default:
			usage(stderr);
			return SMI_ERR;
		}
	}
	if (optind < argc) {
		fprintf(stderr, "%s: unexpected argument '%s'\n", SMI_TOOL_NAME,
			argv[optind]);
		return SMI_ERR;
	}

	/* The tool's own table must be complete before anything is printed. */
	for (size_t i = 0; i < FIELD_COUNT; i++) {
		if (fields[i].name == NULL || fields[i].desc == NULL ||
		    fields[i].source == NULL || fields[i].get == NULL) {
			fprintf(stderr,
				"%s: internal error: field table entry %zu has no getter or metadata\n",
				SMI_TOOL_NAME, i);
			return SMI_ERR;
		}
	}

	if (list_fields) {
		for (size_t i = 0; i < FIELD_COUNT; i++)
			printf("%-26s  %-64s  source: %s\n", fields[i].name,
			       fields[i].desc, fields[i].source);
		return SMI_OK;
	}

	/* Re-scan argv for --query: getopt already advanced it. */
	for (int i = 1; i < argc; i++) {
		if (strncmp(argv[i], "--query=", 8) == 0) {
			query_n = split_fields(argv[i] + 8, query_idx,
					       FIELD_COUNT);
			if (query_n < 1)
				return SMI_ERR;
		} else if (strcmp(argv[i], "--query") == 0 && i + 1 < argc) {
			query_n = split_fields(argv[i + 1], query_idx,
					       FIELD_COUNT);
			if (query_n < 1)
				return SMI_ERR;
		}
	}

	if (query_n < 0) {
		query_n = (int)FIELD_COUNT;
		for (int i = 0; i < query_n; i++)
			query_idx[i] = i;
	} else if (!fmt_given) {
		fmt = SMI_FMT_CSV_NOHEADER;
	}

	/* Locate the device. */
	if (id_given) {
		ctx.card_index = ctx.id;
	} else {
		ctx.card_index = detect_card_index(&ctx);
	}
	if (ctx.card_path == NULL) {
		auto_card_path(&ctx, card_buf, sizeof(card_buf));
		ctx.card_path = card_buf;
	} else {
		strncpy(card_buf, ctx.card_path, sizeof(card_buf) - 1);
		card_buf[sizeof(card_buf) - 1] = '\0';
		ctx.card_path = card_buf;
	}

	if (!card_sysfs_exists(&ctx) && id_given) {
		fprintf(stderr,
			"%s: device index %d has no sysfs card directory under %s/class/drm\n",
			SMI_TOOL_NAME, ctx.id, ctx.sysfs_root);
		return SMI_NO_CARD;
	}

	{
		struct stat st;

		if (stat(ctx.card_path, &st) == 0) {
			ctx.card_stat_ok = 1;
			ctx.card_dev = st.st_dev;
			ctx.card_ino = st.st_ino;
			/* Resolve symlinks so the table shows the same node the
			 * kernel reports. */
			if (realpath(ctx.card_path, card_real) != NULL) {
				strncpy(card_buf, card_real,
					sizeof(card_buf) - 1);
				card_buf[sizeof(card_buf) - 1] = '\0';
			}
		}
	}

	use_color = !no_color && isatty(STDOUT_FILENO);

	if (loop > 0) {
		struct sigaction sa;

		memset(&sa, 0, sizeof(sa));
		sa.sa_handler = on_sigint;
		sigemptyset(&sa.sa_mask);
		sigaction(SIGINT, &sa, NULL);
		signal(SIGPIPE, SIG_IGN);
		while (!stop_loop) {
			render_once(&ctx, query_idx, query_n, fmt, query_n != (int)FIELD_COUNT,
				    strict);
			if (!stop_loop) {
				if (use_color && fmt == SMI_FMT_TABLE)
					printf("\033[H\033[2J");
				else
					fflush(stdout);
				{
					struct timespec ts = { loop, 0 };

					while (nanosleep(&ts, &ts) != 0 &&
					       errno == EINTR && !stop_loop)
						;
				}
			}
		}
		return SMI_OK;
	}

	render_once(&ctx, query_idx, query_n, fmt, query_n == (int)FIELD_COUNT,
		    strict);

	if (!ctx.card_stat_ok)
		return SMI_NO_CARD;
	if (strict) {
		char values[FIELD_COUNT][SMI_VALUE_MAX];
		const char *reasons[FIELD_COUNT];
		int unresolved = 0;

		resolve_fields(&ctx, query_idx, query_n, values, reasons);
		for (int i = 0; i < query_n; i++) {
			if (reasons[i] != NULL)
				unresolved++;
		}
		if (unresolved > 0)
			rc = SMI_STRICT;
	}
	return rc;
}
