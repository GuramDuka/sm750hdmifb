# SiI9024A link status (0x3d) and I2C timeouts: kernel and open-source research

Scope: the kernel/open-source side of the SiI9024A (SiI9022-compatible) HDMI
transmitter on the SM750 DDC/I2C bus. The local driver is
`src/sii902x.c`; the in-tree reference is
`drivers/gpu/drm/bridge/sii902x.c`.

Method and source access. Kernel sources were read from
`torvalds/linux` master as fetched on 2026-11-21 (raw.githubusercontent.com and
the plain view at git.kernel.org; the file was 1262 lines). Mailing-list
material came from `lists.freedesktop.org` monthly archives (dri-devel,
linux-i2c) and from marc.info (dri-devel, linux-kernel, linux-arm-kernel,
linux-omap, linux-fbdev, linux-i2c). The generic web search tool returned
HTTP 403 for every submission, and elixir.bootlin.com, lore.kernel.org,
patchwork.kernel.org and bugzilla.kernel.org were unreachable from this host
(proxy block or JS challenge), so the catalogue below is built from the
archives and from commit objects rather than from a search engine. Every claim
is labelled: primary (kernel source, commit message, archived mailing-list
message, vendor document) or secondary (forum/blog, or my own inference).

## 1. Register 0x3d: what is actually documented

### 1.1 Bit map as implemented by open-source code

| bit | name used here | upstream Linux | QEMU model | this driver |
| --- | --- | --- | --- | --- |
| 0 | HOTPLUG_EVENT | `SII902X_HOTPLUG_EVENT BIT(0)` (sii902x.c:147) | `SII902X_HOTPLUG 0x01` (hw/display/sii9022.c:33-36) | `SII902X_HOTPLUG_EVENT BIT(0)` (src/sii902x.c:37) |
| 1 | RX_SENSE_EVENT | not defined | not defined | `SII902X_RX_SENSE_EVENT BIT(1)` (src/sii902x.c:38) |
| 2 | PLUGGED_STATUS | `SII902X_PLUGGED_STATUS BIT(2)` (sii902x.c:148) | `SII902X_PLUGGED 0x04` | `SII902X_PLUGGED_STATUS BIT(2)` (src/sii902x.c:39) |
| 3 | RX_SENSE_STATUS | not defined | not defined | `SII902X_RX_SENSE_STATUS BIT(3)` (src/sii902x.c:40) |
| 4-7 | NOT FOUND | not defined | not defined | not defined |

Primary sources:

- `drivers/gpu/drm/bridge/sii902x.c:146-149`:
  `#define SII902X_INT_STATUS 0x3d`, `#define SII902X_HOTPLUG_EVENT BIT(0)`,
  `#define SII902X_PLUGGED_STATUS BIT(2)`. There is no receiver-sense define
  anywhere in the file.
- QEMU `hw/display/sii9022.c:33-36` defines the same register and the same two
  bits; its interrupt/status path at :101-103 only ever reports PLUGGED
  ("Something is cold-plugged in, no interrupts").
- `src/sii902x.c:36-42` is the only open-source definition of bits 1 and 3 I
  could find. Those bits come from the vendor programming guide the driver
  cites elsewhere (`SiI-PR-1032`, see the comment at `src/sii902x.c:900-937`),
  which is not publicly available.

The vendor product brief (SiI-DB-1076-C01, 24 pages, retrieved from the
2010-12-30 Wayback capture of siliconimage.com docs) says only:

- "Monitor detection is supported through both Hot Plug and Receiver Sense
  circuits".
- "Flexible power management with hot-plug wakeup".

It contains no register map and no 0x3d bit table. The full SiI9022A/SiI9024A
datasheet and the programming guide are NDA; the public Wayback CDX listing of
`siliconimage.com/docs/` contains only product briefs. So "what the datasheet
requires" for bits 4-7 is NOT FOUND; only bits 0-3 have any evidence, and only
bits 0 and 2 have independent open-source corroboration.

### 1.2 Read/write semantics

Upstream treats the register as a whole-register write-1-to-clear latch:
`sii902x_interrupt()` at `drivers/gpu/drm/bridge/sii902x.c:935-953` does
`regmap_read(..., SII902X_INT_STATUS, &status)` and then
`regmap_write(..., SII902X_INT_STATUS, status)`, and only acts when
`status & SII902X_HOTPLUG_EVENT`. The local driver instead clears only the two
event bits, `SII902X_LINK_EVENT_MASK` (`src/sii902x.c:41-42`), in
`sm750_sii902x_get_link_status()` (`src/sii902x.c:518-537`), and it only does
so when its caller asks for a clear.

One consequence is worth stating because it explains the observed bytes: a
plain read does not clear anything, so once a receiver-sense edge has happened,
bit 1 stays set until someone writes it back. That is exactly what the
0x04/0x06/0x0e sequence shows.

### 1.3 The observed values

`status` is the raw byte read from 0x3d; HPD is bit 2 and RSEN is bit 3 as the
driver decodes them (`src/sii902x.c:574-578`).

| value | bits set | reading |
| --- | --- | --- |
| 0x04 | 2 | HPD/plug present, receiver sense absent, no latched link event. This is the KVM case already recorded in `docs/HARDWARE.md:29`: DDC/hot-plug is asserted by the KVM chain while no TMDS receiver is presented. |
| 0x06 | 1, 2 | HPD present plus a latched receiver-sense event (bit 1) while the live receiver-sense bit (bit 3) is still 0. Consistent with an edge that happened and then went away, or with an edge latched during the monitor power cycle and never cleared. Justified by the write-1-clear semantics in 1.2. |
| 0x0e | 1, 2, 3 | HPD present, receiver sense present, and a latched receiver-sense event still pending. This is the fully powered, terminated sink state. |
| 0xa0 | 5, 7 | Neither HPD nor RSEN, and no documented event bit. Bits 5 and 7 have no public definition, so the value cannot be decoded from any source I could reach (NOT FOUND). It is not a valid combination of the documented bits: it can only mean "no plug, no receiver, no pending documented event" plus whatever the undocumented upper bits carry. |

For 0xa0 the honest statement is: it is consistent with the chip reporting no
hot-plug and no receiver sense while the monitor is unpowered, and the two set
bits are undocumented. The plausible readings -- that the upper nibble holds
sticky state or that the byte is undefined while the internal DDC/receiver side
is unpowered -- are SPECULATIVE and cannot be confirmed without the NDA
datasheet.

The observed log sequence is therefore self-consistent: 0xa0 (monitor off, no
HPD, no RSEN), then 0x04 (HPD back, receiver not yet up), then 0x06 / 0x0e as
the receiver sense edge latches and the receiver asserts. The 2 s warning fires
because the transition from 0x04 to 0x0e did not complete inside the driver's
window, and behind the KVM chain it never completes at all (0x04 forever).

## 2. In-tree `drivers/gpu/drm/bridge/sii902x.c` behaviour

All line numbers are from `torvalds/linux` master fetched 2026-11-21.

Power-up and reset:

- `sii902x_reset()` at :245-256 asserts the reset GPIO, waits
  `usleep_range(150, 200)` with the comment "The datasheet says treset-min =
  100us. Make it 150us to be sure.", then releases reset. This is the only
  datasheet-derived timing constant in the power path.
- `sii902x_init()` (:1078 and following) calls `sii902x_reset()`, sets up the
  regmap, reads 0x3d and writes the value back (clearing any latched event),
  then enables the hot-plug interrupt in `SII902X_INT_ENABLE`.
- There is no receiver-sense handling and no wait for the sink at all.

Detection and HPD:

- `sii902x_detect()` (:258-274) takes the mutex, performs one
  `regmap_read(..., SII902X_INT_STATUS, &status)` and returns
  `connector_status_connected` if and only if `status & SII902X_PLUGGED_STATUS`.
  A single failed read is reported and treated as disconnected; there is no
  retry here. 0x04, 0x06 and 0x0e would all read as connected.
- `sii902x_interrupt()` (:935-953) reads 0x3d, writes it back (write-1-clear),
  and on `HOTPLUG_EVENT` calls `drm_helper_hpd_irq_event()` and
  `drm_bridge_hpd_notify()` with the PLUGGED bit.

EDID and DDC:

- `sii902x_edid_read()` (:289-301) is
  `drm_edid_read_ddc(connector, sii902x->i2cmux->adapter[0])` under the mutex.
  `get_modes()` (:303-317) returns 0 when there is no EDID and relies on the
  DRM core fallback (see section 4).
- DDC reaches the sink only through an `i2c-mux` channel. The parent adapter is
  locked around the whole mux select/transfer/deselect, so no other traffic can
  hit the bus while the bridge has the DDC channel.
- `sii902x_i2c_bypass_select()` (:969-1013) sets DDC_BUS_REQ in 0x1a and
  busy-polls 0x1a for DDC_BUS_GRTD for up to
  `SII902X_I2C_BUS_ACQUISITION_TIMEOUT_MS` = 500 ms (:162), with no sleep. On
  failure: `dev_err(dev, "Failed to acquire the i2c bus\n"); return
  -ETIMEDOUT;`.
- `sii902x_i2c_bypass_deselect()` (:1014-1066) contains the two empirically
  derived workarounds:

  ```
  /*
   * When the HDMI transmitter is in pass through mode, we need an
   * (undocumented) additional delay between STOP and START conditions
   * to guarantee the bus won't get stuck.
   */
  udelay(30);
  ...
  /*
   * Sometimes the I2C bus can stall after failure to use the
   * EDID channel. Retry a few times to see if things clear
   * up, else continue anyway.
   */
  retries = 5;
  ```

  It then clears REQ|GRTD, busy-polls another 500 ms, and on failure logs
  "failed to release the i2c bus" and returns -ETIMEDOUT. Note the shape: a
  failed teardown can fail the whole DDC operation, but the repeated status
  read is retried five times and then merely logged.

Mode set:

- `sii902x_atomic_enable()` decides HDMI vs DVI from the EDID (moved there by
  commit d6732ef4ab25, 2025-10-30), resets the chip, programs the mode, and
  does not wait for the sink to be ready. There is no "receiver ready" gate and
  no RSEN concept.

The two historical patches that define the upstream position on I2C failure:

- Commit 2e7a66a8b5eb "drm/bridge: sii902x: Retry status read after DDI I2C"
  (Linus Walleij, 2018-03-05). Commit message, verbatim: "The following happens
  when connection a DVI output driven from the SiI9022 using a DVI-to-VGA
  adapter plug: i2c i2c-0: sendbytes: NAK bailout. i2c i2c-0: sendbytes: NAK
  bailout. Then no picture. Apparently the I2C engine inside the SiI9022 is not
  smart enough to try to fall back to DDC I2C. ... After this, the I2C bus seems
  stalled and the first attempt to read the status register fails, and the code
  returns with negative return value, and the display fails to initialized.
  Instead, retry status readout five times and continue even if this fails."
  This is the direct precedent for not letting a single 0x3d read failure kill
  a mode set.
- Commit 21d808405fe4 "drm/bridge/sii902x: Fix EDID readback" (Fabrizio Castro,
  2018-11-06) replaced direct DDC access with the i2c-mux gate described above,
  because pass-through "is not compliant with the I2C specification anymore, as
  it requires a far bigger tbuf, due to a delay the HDMI transmitter is adding
  when relaying the STOP condition on the monitor i2c side of things" and
  because "any other traffic on the bus while talking to the monitor may cause
  the transaction to fail or even cause issues with the i2c bus as well".

## 3. Catalogue of reports, threads and patches

Primary (mailing list or commit object), in date order:

1. 2018-02-14, reposted 2018-03-01. "[PATCH] drm/bridge: sii902x: Fall back to
   standard modes", Linus Walleij.
   https://marc.info/?l=linux-arm-kernel&m=151861332118101&w=2
   (repost https://marc.info/?l=linux-arm-kernel&m=151993928613918&w=2).
   Trigger: DVI-to-VGA adapter, "i2c i2c-0: sendbytes: NAK bailout.", no
   picture. Patch adds `DRM_INFO("EDID readout failed, falling back to standard
   modes\n")`, `drm_add_modes_noedid(connector, 1920, 1080)` and
   `drm_set_preferred_mode(connector, 1024, 768)`. Ville Syrjala replied that
   the probe helper already has a noedid fallback for mode count 0; Walleij
   said he would debug from there. Conclusion: patch NOT merged (it is absent
   from the 2026 source); the fallback was left to the DRM core.
2. 2018-03-05. Commit 2e7a66a8b5eb, quoted in section 2.
   https://github.com/torvalds/linux/commit/2e7a66a8b5ebf1b04a866e5d7c981640f7f62934
   Conclusion: after a stalled bus, retry the status read five times and
   continue; a failed read must not abort initialisation. Merged.
3. 2018-10-31 to 2018-11-15. "[RFC] / [PATCH v2] / [PATCH v3]
   drm/bridge/sii902x: Fix EDID readback", Fabrizio Castro (Renesas).
   https://marc.info/?l=linux-i2c&m=154102111806176&w=2 and neighbours in the
   linux-i2c and dri-devel archives. Discussion covers the non-compliant tbuf
   of the pass-through path, the need to freeze the parent adapter, and Mark
   Brown's objection that driving the mux from inside the driver "doesn't sound
   terribly clever". Conclusion: merged as 21d808405fe4 with the i2c-mux gate;
   the bus-stuck problem is treated as an electrical/protocol problem of the
   pass-through mode, not as a reason to skip EDID.
4. 2026-04-01. "[PATCH] drm/bridge: sii902x: Add Power Management hooks with
   audio context", Sen Wang (TI).
   https://marc.info/?l=linux-kernel&m=177501019231115&w=2
   On resume the driver reads TPI register 0xc7 and compares it with the saved
   context; if it changed, the comment reads "TPI register context has changed.
   SII902X power supply device has been turned off and on." and the driver runs
   `sii902x_reset()`, rewrites 0xc7 with 0 to re-enter TPI mode, re-enables the
   interrupt mask, and reads/writes 0x3d to clear pending interrupts.
   Conclusion: upstream now accepts that a sink-side power cycle can silently
   reset the transmitter's register context and that recovery is a full reset
   plus TPI re-entry, not a retry of one transaction.
5. 2026-04-23. "[PATCH v2 28/28] drm/bridge: sii902x: Implement hw state
   readout", Maxime Ripard.
   https://marc.info/?l=dri-devel&m=177694225624804&w=2
   The readout returns early when `SII902X_SYS_CTRL_PWR_DWN` is set: register
   state is considered meaningless while the chip is powered down.
6. No date-stamped user bug report. `drivers/gpu/drm/bridge/synopsys/dw-hdmi.c`
   :291-356 carries an in-code report of the same class of failure: "This is a
   huge hack to workaround a problem where the dw_hdmi i2c bus could sometimes
   get wedged ... This wedging was only ever seen on one TV, and only on one of
   its HDMI ports. It happened when the TV was powered on while the device was
   plugged in. A scope trace shows the TV bringing both SDA and SCL low, then
   bringing them both back up at roughly the same time ... after coming back
   alive, transfers seem to immediately resume, so if we unwedge due to a
   timeout we should wait a little longer for our transfer to finish". This is
   the closest documented match to the monitor power cycle case: the sink
   itself pulls the bus low during power-up.

NOT FOUND, after searching: any report of `-ETIMEDOUT`/`-110` from the
in-tree sii902x driver; any "sii902x: failed to read EDID" message (that string
does not exist upstream); any kernel Bugzilla entry for sii9022/sii9024
(Bugzilla was unreachable, so this is unverified rather than proven absent); any
public errata sheet; the 0x3d bit table from the datasheet.

## 4. Timeout and retry practice across drivers

| driver | mechanism | numbers | on final failure |
| --- | --- | --- | --- |
| drm_edid.c `drm_do_probe_ddc_edid()` :2195-2241 | retry the whole EDID block transfer | `retries = 5`; `-ENXIO` breaks out at once as "non-existent adapter" | returns failure to the caller, which degrades |
| drm_probe_helper.c :662-667 | not a retry: the fallback | `count == 0 && status == connected` -> `drm_add_modes_noedid(connector, 1024, 768)` | connector still works at 1024x768 (640x480 only for DP) |
| sii902x.c (in-tree) :969-1066 | busy-poll for DDC grant/release, 5 retries on the status read, `udelay(30)` before the next START | 500 ms each direction, 5 retries | `-ETIMEDOUT`, logged |
| dw-hdmi.c :339-356 | 100 ms completion wait, on timeout unwedge the bus (pulse SDA/SCL via pinctrl, `msleep(10)`) and retry the transfer once | `HZ/10`, one retry | `-EAGAIN` (deliberately not `-ETIMEDOUT`) |
| adv7511_drv.c :494-514, :541 | poll the EDID-done flag every 25 ms, or wait on the interrupt | 200 ms total | `-EIO` |
| adv7511_drv.c :588-612 | power the chip on for the read, power off afterwards, rewrite EDID_I2C_ADDR because it "might be cleared" | n/a | -- |
| ite-it66121.c :477-494, :533-580 | `regmap_read_poll_timeout` on DDC status, abort DDC on error, `msleep(50)` after power-on ("Per programming manual, sleep here for bridge to settle") | 20 ms step, 200 ms total | `-EAGAIN`, DDC op aborted |
| lontium-lt9611.c :510-525, :577-620 | sleeps in power/init, chunked EDID reads | 20/20/100/20 ms | -EIO style errors, no retry loop |

The policy that emerges, consistently across these drivers:

1. Retry the transaction, not the mode set. No upstream bridge re-runs
   `atomic_enable` after a bus timeout; the retries are per I2C operation
   (5x in drm_edid and sii902x, one unwedge-and-retry in dw-hdmi).
2. Distinguish NACK from timeout. drm_edid treats `-ENXIO` (no sink) as
   terminal and stops immediately; only timeouts are retried. dw-hdmi returns
   `-EAGAIN` so the I2C core retries, and `-EIO` for a real bus error.
3. A missing EDID is not fatal. A connected connector with zero modes gets
   1024x768 from the DRM core; the bridge driver just returns 0 modes.
4. DDC is only valid while the transmitter is powered (adv7511 powers it on
   for the read and restores EDID_I2C_ADDR; sii902x's readout patch refuses to
   read state while PWR_DWN is set), and only while the driver owns the bus
   (sii902x's mux gate plus parent-adapter locking).
5. A wedged bus is unwedged, not abandoned: 9 clocks plus STOP, then retry
   (dw-hdmi; the same routine already exists locally in
   `src/ddk750_swi2c.c:574-593`).

There is no upstream precedent for treating an enable-time bus timeout as
fatal, and none for degrading the mode list because of it. `-ETIMEDOUT` from
`sii902x_i2c_bypass_select/deselect` is reported upward because it is an I2C
*mux* callback, where the error has to reach the I2C core for the EDID read to
fail cleanly; it is not a verdict on the mode set.

## 5. Recommendations for this driver

Where the -110 can actually come from. `src/sm750_drm.c:1416` calls
`sm750_sii902x_begin_mode(&sdev->pdev->dev, false, ...)`, so
`use_hardware_i2c` is false and the SM750 hardware I2C engine is not in use.
On the software path `sii902x_read()`/`sii902x_write()`
(`src/sii902x.c:233-249`) collapse every failure to `-ENXIO`; the only
functions that can return `-ETIMEDOUT` are `sii902x_write_block()`
(`src/sii902x.c:251-259`, returning the result of
`sm750_sw_i2c_write_block()`, `src/ddk750_swi2c.c:546-568`) and the DDC-grant
timeout at `src/sii902x.c:1013`. The block writer is called from
`src/sii902x.c:655` (AVI infoframe) and `src/sii902x.c:876` (video data block
inside enable). A `-110` logged at stage `sii902x_enable` is therefore a
bit-banged transfer in which SCL never came back high, i.e. the sink was
holding the bus low -- exactly the dw-hdmi "TV powered on while plugged in"
signature -- or the DDC-grant wait expired. It is not a NACK (`-ENXIO`) and it
is not the SM750 engine.

| # | recommendation | tag | where it would change |
| --- | --- | --- | --- |
| R1 | Retry the failing block write a bounded number of times (5, matching drm_edid.c:2201 and commit 2e7a66a8b5eb) and, if it still fails, log and continue instead of failing the mode set. A lost AVI infoframe or video block only costs colour/format metadata, not pixels. | STRONG | `src/sii902x.c:251-259` (add the retry), `src/sii902x.c:655`, `src/sii902x.c:876` (downgrade `return ret` to a warning for the metadata blocks) |
| R2 | On `-ETIMEDOUT`, unwedge the bus before retrying: `sm750_sw_i2c_recover_bus()` already implements the 9-clock clear plus STOP (`src/ddk750_swi2c.c:574-593`) and is already used by the EDID path (`src/sii902x.c:1036`) and at shutdown (`src/sii902x.c:513`), but not on the enable-time write timeout. This is the dw-hdmi unwedge policy (dw-hdmi.c:291-356). | STRONG | `src/sii902x.c:251-259` or the two call sites `:655`/`:876` |
| R3 | Do not request DDC or read EDID while the transmitter is powered down. `sm750_sii902x_read_edid()` reads 0x1a into `saved` (`src/sii902x.c:994`) but never tests the PWR_DWN bit before setting DDC_REQUEST; adv7511 powers the chip on for the read (:588-612) and the upstream readout patch refuses to read state while PWR_DWN is set. | STRONG | `src/sii902x.c:994-1002` (bail out with `-EAGAIN`/`-ENODEV` when `saved & PWR_DWN`, or power up first as `src/sii902x.c:483-499` mirrors) |
| R4 | Treat an EDID/DDC failure as non-fatal for the connector: keep the forced mode already used for the KVM case and let the DRM core supply 1024x768 when no modes were found (`drivers/gpu/drm/drm_probe_helper.c:662-667`). Do not propagate `-ETIMEDOUT` from `sm750_sii902x_read_edid()` into the mode-set path. | STRONG | `src/sii902x.c:1013` (return 0/`-EAGAIN` upward), the EDID caller in `src/sm750_drm.c` |
| R5 | Keep the "enabling for compatibility" behaviour, but make the wait impervious to a late HPD: if HPD is 0, the current loop still burns the full 2000 ms and then warns. Restart the budget when bit 2 rises, and require the 100 ms of stable RSEN only after that. | PLAUSIBLE | `src/sii902x.c:546-583` |
| R6 | Mask the status byte to the documented bits (0x0f) before logging or comparing. The observed 0xa0 shows that bits 4-7 carry something; using the raw byte in log text invites misreading, and the poll loop only tests bit 3 anyway. | PLAUSIBLE | `src/sii902x.c:574-578`, `src/sii902x.c:518-537` |
| R7 | Add a settle delay before the first status read after any power-down-to-on transition (adv7511: 200 ms EDID budget; it66121: 50 ms "for bridge to settle"; dw-hdmi: 10 ms after unwedge). The local disable path already sleeps 20 ms (`src/sii902x.c:483-499`); 50 ms before the first 0x3d read after a monitor power event is a cheap insurance. | PLAUSIBLE | `src/sii902x.c:483-499`, `src/sii902x.c:777-830` |
| R8 | Detect a lost transmitter context the way the TI PM patch does: compare a TPI register (0xc7, or the 0x1a value the driver already reads) against the expected value at the start of enable, and on mismatch re-run reset plus TPI entry instead of applying read-modify-write deltas to a chip that silently reset. This would also make 0xa0 interpretable as "the sink cycled our chip's analog side". | SPECULATIVE | `src/sii902x.c:768-830` (`sm750_sii902x_begin_mode`), `src/sii902x.c:900-937` |
| R9 | Extend the receiver-ready window beyond 2000 ms when HPD rose late in the window (monitors can take several seconds to bring their scaler up), and re-arm the wait on a hot-plug event rather than only at enable. No document gives a number; treat as a tuning knob. | SPECULATIVE | `src/sii902x.c:546-583` |
| R10 | Use the 0x3d event bits as an interrupt source (upstream `sii902x_interrupt()`, sii902x.c:935-953) and re-run the readiness wait from there, instead of polling only inside enable. The driver currently has no IRQ path, so a monitor that comes up after the mode set is never noticed. | SPECULATIVE | `src/sii902x.c:518-537`, the probe path in `src/sm750_drm.c` |

Note on the rare -110: R1 plus R2 fix it with the smallest semantic change. The
error surfaces at `src/sm750_drm.c:4148-4150` because the enable stage returns
non-zero; making a metadata block write best-effort keeps that fail path for
real register failures while removing the once-in-446 mode sets event.

## Searched for

marc.info body search, lists dri-devel, linux-kernel, linux-arm-kernel,
linux-omap, linux-fbdev and linux-i2c, query strings `sii902x`, `sii9022`,
`sii9024` (492 matching messages reviewed: patches, reviews, LKP boot-log
noise, no user failure reports). Commit history of
`drivers/gpu/drm/bridge/sii902x.c` via the GitHub commits API (74 commits
reviewed) and individual commit objects / `.patch` texts for 2e7a66a8b5eb,
21d808405fe4, d6732ef4ab25, 675605c1c8e6. lists.freedesktop.org dri-devel
monthly mbox archives for 2016-03/04/05/06, 2018-03/04/05/10/11,
2019-02..07, 2020-09/10, 2022-01, 2024-01, 2025-07, 2026-03/04. Wayback CDX
prefix queries for `siliconimage.com/docs/` (product briefs only). Source files
read in full: in-tree `sii902x.c`, `drm_probe_helper.c`, `drm_edid.c`,
`dw-hdmi.c`, `adv7511_drv.c`, `ite-it66121.c`, `lontium-lt9611.c`, QEMU
`hw/display/sii9022.c`. The generic web search tool and the
elixir/patchwork/lore/bugzilla endpoints were unavailable from this host
(HTTP 403, proxy block, or JS challenge), so no result from them is cited.
