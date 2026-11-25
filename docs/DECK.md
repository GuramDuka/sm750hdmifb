---
marp: true
paginate: true
theme: default
---

<!-- Forgejo renders this file as one page (the slide separators become horizontal rules); docs/deck/index.html is the viewing format. -->

## SM750 DRM/KMS driver: production status

- Repository `sm750hdmifb`, out-of-tree kernel module `sm750hdmidrm`, version 0.6.2
- Card `SE-DP750A-HDMI`: Silicon Motion `126f:0750` at PCI `0000:01:00.0`, one HDMI output (`docs/HARDWARE.md:5-15`)
- Version 0.6.2: `src/sm750_drm.c:78`, `dkms.conf:3`, `packaging/sm750hdmifb.spec:21`
- Kernel floor 6.17: `BUILD_EXCLUSIVE_KERNEL` in `dkms.conf:8`
- Acceptance record: 6 PASS, 0 FAIL, 1 GAP, the gap being pixel-level proof at the panel (`docs/ACCEPTANCE-REPORT.md:20`)

---

## The hardware problem

- SM750G10-AC revision A1, 16 MiB integrated DDR, 64 MiB BAR0, 2 MiB BAR1 (`docs/HARDWARE.md:9-15`)
- No HDMI PHY on the SM750: it emits 24-bit parallel RGB/DVO, and the board's SiI9024ACNU converts that to HDMI (`docs/HARDWARE.md:11`, `:18-19`)
- In-tree Linux support for the chip is the staging fbdev driver `sm750fb`; the `src/ddk750*` register layer here descends from it (`docs/PROVENANCE.md:10-16`, `:27`)
- Capability table: 2D engine (128-bit BitBLT/ROP3), DMA, two cursor layers, scaling implemented in software (`docs/HARDWARE.md:47-58`)
- Three board quirks kept non-fatal: DMA1 IRQ not routed, SiI9024A receiver sense absent, PCI cache-line mismatch (`docs/HARDWARE.md:21-32`)

---

## Architecture

The outline below mirrors the diagram on slide 3 of `docs/deck/index.html`, same layers in the same order.

- Userspace: libdrm / IGT / compositor, issuing `drmModeSetCrtc`, `drmModeAtomicCommit`, `drmModeSetCrcSource`
- DRM core: atomic commit tail, vblank accounting, the `crc/control` and `crc/data` debugfs files, the in-kernel fbdev client
- `sm750hdmidrm`: GEM with `drm_vram_helper`/TTM, atomic simple pipe, shadow upload and full-frame staging, scanout CRC engine, `ddk750_*` register layer
- Hardware: SM750 registers and 16 MiB VRAM, SiI9024A bridge
- Panel: the HDMI sink
- Side boxes: test-card fallback painting the scanout buffer, and the core-owned CRC stream reading it

---

## Modeset path

Every modeset funnels through `sm750_program_mode()` (`src/sm750_drm.c:1356`), which records the last stage it entered in `mode_stage`:

| Stage | Call | Line |
|---|---|---|
| `SM750_MODE_STAGE_SII_BEGIN` | `sm750_sii902x_begin_mode()` | `:1399` |
| `SM750_MODE_STAGE_DISPLAY_CTRL` | `ddk750_set_display_control()` | `:1404` |
| `SM750_MODE_STAGE_TIMING` | `ddk750_set_mode_timing()` | `:1408` |
| `SM750_MODE_STAGE_LOGICAL_OUT` | `ddk750_set_logical_disp_out()` | `:1436` |
| `SM750_MODE_STAGE_SII_ENABLE` | `sm750_sii902x_enable()` | `:1440` |

- Enum and names: `src/sm750_drm.c:293-299`, `:302-318`; the field is cleared on success at `:1443`
- A failure prints `failed to enable HDMI mode: %d at stage %s (commit finished, event consumed)` (`src/sm750_drm.c:3824-3825`)

---

## Framebuffer path: shadow upload and staging

- Shadow upload copies reported damage into VRAM through `sm750_shadow_upload()` (`src/sm750_drm.c:1705`), one aligned span at a time via `sm750_shadow_upload_one()` (`:1655`)
- With `backbuffer_staging=1` a full-frame update is rendered into the off-screen buffer instead; availability is decided at `:3725` from the module parameter and a VRAM fit test (`:400` field, `:417`)
- Buffer size at 1920x1080 RGB565 is 4147200 bytes (1920 * 1080 * 2); the driver logs it as `full-frame backbuffer staging enabled (4147200 bytes per buffer)` (`src/sm750_drm.c:3762-3764`, captured in `docs/DELIVERABLES.md:207-212`)
- Async updates run on a dedicated ordered workqueue: `sm750_async_shadow_work()` (`src/sm750_drm.c:2606`), queued at `:4540`
- `sm750_present_staged_frame()` (`src/sm750_drm.c:2425`) pokes `FB_ADDRESS` and polls for the flip; on timeout it disables flips and falls back to mirroring updates (`:2447-2457`)

---

## vblank and the CRC engine

- The driver paces vblank with its own hrtimer, `sm750_vblank_timer_fn()` (`src/sm750_drm.c:468`, set up at `:4445`), not the generic DRM timer (`docs/VBLANK.md:1-12`)
- One CRC entry per vblank: `sm750_crc_work_fn()` (`src/sm750_drm.c:3311`) reads the window and calls `drm_crtc_add_crc_entry()` (`:3329`), then re-arms unconditionally
- `sm750_scanout_crc32()` (`src/sm750_drm.c:3147`) is `crc32_le` over `crc_window_bytes`, default 262144 bytes (`:243`), starting at the visible scanout offset
- `crc/control` and `crc/data` are created and owned by DRM core; the driver only supplies `.get_crc_sources` (`:4009`) and `.set_crc_source` (`:4011`)
- The value proves the VRAM buffer handed to the display engine, not the pixels the panel emits (`docs/TEST-STRATEGY.md:597-599`)

---

## Defects found and fixed

| Id | Defect | Disposition |
|---|---|---|
| A27 | A failed modeset became a kernel WARNING, 10 s commit stalls and a refcount underflow | fixed: the fail path finishes the abandoned commit (`docs/DEFECTS.md:55`) |
| A31 | A black panel was misread as a display-path fault; fbcon paints only under `KD_TEXT` | accepted and diagnosed, one diagnostic per load (`docs/DEFECTS.md:435-467`) |
| A32 | The fbdev restore path timed out because it compared whole control registers | fixed: masked compare plus re-poke (`docs/DEFECTS.md:59`) |
| A34 | The panel showed dead black when no client painted the fbdev buffer | fixed: bounded test card (`docs/DEFECTS.md:61`) |
| A35 | The 0.6.1 tree failed its own release gate: a literal path in `tools/sm750-restore-cycle.sh:36` | fixed via `SM750_REPO` (`docs/DEFECTS.md:62`) |

- A32 on hardware: 30/30 client exit/restore cycles, 20/20 mode changes, and a nine-marker dmesg census of `0` (`docs/evidence/runtime/22-restore-fix-hardware-proof.txt:80-88`, `:96-104`, `:129-140`)

---

## Test strategy

- `make check`: 17 recipe commands, `Makefile:32-48`, prerequisites built at `Makefile:30-31`, preflight at `Makefile:17-28` (`docs/TEST-STRATEGY.md:455-470`)
- Source-level gates carry planted negative controls: the console-blank gate and the restore-path gate each reject four planted defects (`docs/DEFECTS.md:481`, `:59`)
- Root-only gates: `make console-check` (`tests/check-console-scanout.sh`) and `tools/sm750-restore-cycle.sh`, which refuses to run as non-root
- Static analysis is a separate target, `make static`: sparse, smatch, cppcheck, coccinelle, pahole against a recorded baseline (`docs/STATIC-ANALYSIS.md:4-9`)

```sh
make check KDIR=/lib/modules/$(uname -r)/build CC=/usr/bin/gcc
make static
```

---

## Packaging and release

- DKMS builds the module from one source tree; the kernel floor is encoded once in `dkms.conf:8`
- The RPM is `noarch` and carries source only: `packaging/sm750hdmifb.spec:21` fixes version 0.6.2, `:26` names the tracked-tree source tarball
- `%posttrans` (`packaging/sm750hdmifb.spec:127`) removes every stale DKMS registration, then builds and installs the current version (`docs/PACKAGING-RPM.md:115-145`)
- Installed and exercised for kernels 7.2.15-100, 7.3.3-100 and 7.3.4-100 (`docs/PACKAGING-RPM.md:363`, `docs/DELIVERABLES.md:186`)
- The Debian package comes from `build-package.sh`; the release audit `tests/audit-release.sh` must exit 0 before a release

| Artifact | Source |
|---|---|
| RPM | `packaging/sm750hdmifb.spec` |
| deb | `build-package.sh` |
| source tarball | `Source0`, `packaging/sm750hdmifb.spec:26` |
| gate | `tests/audit-release.sh` |

---

## Evidence discipline and open items

- A claim is a result only if a file under `docs/evidence/` supports it; otherwise it is a gap (`AGENTS.md:14-17`)
- `docs/LOGBOOK.md` is append-only: every action gets one entry with time, actor, files and evidence (`AGENTS.md:8-13`)
- Fixed: the test-card fallback corrupted the scanout CRC stream (3 distinct values in 12 static frames); a CRC source now cancels the card and owns the window (`docs/DEFECTS.md:63`, `docs/evidence/runtime/26-test-card-crc-fix.txt`)
- Open: GAP-B8, which of the five `sm750_program_mode()` calls returns `-110`; the trigger reproduced 1 of 206 attempts (`docs/evidence/EVIDENCE-GAPS.md:655`, `:747`)
- VBIOS reconstruction leaves 61 of 18034 code bytes carried as `db` (`docs/VBIOS-REVERSE-ENGINEERING.md:907`)
- Known limits: AC-3 remains a gap, no pixel-level proof at the panel (`docs/ACCEPTANCE-REPORT.md:41`)
