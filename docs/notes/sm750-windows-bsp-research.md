# SM750 vendor BSP and SiI9022 integration: what the vendor code actually does

Date: 2026-11-22
Author: research subagent (read-only task)
Scope: extend `docs/notes/sii9024a-vendor-research.md` and
`docs/notes/sii9024a-i2c-research.md`. Those two notes already cover the
Silicon Image data sheet, the TPI programmer's reference, the in-tree
`drivers/gpu/drm/bridge/sii902x.c` behaviour and our own driver. This note
does not restate them. It records what the Silicon Motion vendor code and
closest available integration code do about reset, DDC ownership, retry and
HPD/RX-sense, and it records what could not be obtained.

Method: HTTP only. `websearch` returns 403 in this environment, so the
DuckDuckGo HTML endpoint, the GitHub REST API (unauthenticated, repo and tree
endpoints only, code search needs auth) and `raw.githubusercontent.com` were
used. No vendor source block is reproduced here; logic is described in prose
and at most a single short line is quoted per point, with its URL.

Terminology used below:

- "the DDK" means the Silicon Motion SM750 display driver source as published
  in the public mirrors listed in section 2, tree `ddk750/`.
- "vendor code" means that DDK, i.e. code Silicon Motion wrote for its own
  reference board. Third-party integration code is labelled as such.
- "our driver" means `src/` in this repository.

---

## 1. Summary table of verdicts

| Q | Question | Verdict |
| --- | --- | --- |
| Q1 | Does vendor code toggle a SiI9022 reset GPIO before initialisation, on which SM750 GPIO; any reset-during-D3 recovery | PARTIAL |
| Q2 | DDC ownership around HDCP: clear link security before requesting DDC, wait for grant, behaviour when the grant does not arrive | FOUND |
| Q3 | Retry policy for a failed I2C transfer: attempts, delay, bus clear, is a NACK an error | FOUND |
| Q4 | Hardware I2C or bit-bang for TPI/EDID, documented reason to prefer one | FOUND |
| Q5 | Documented workaround for HPD=1 with RX_SENSE=0 after sink power restore | PARTIAL |

Short form of the answers:

- Q1: the reset helper exists in the DDK but is compiled out (`#if 0`), its
  call site in TPI init is commented out, and the pin it would drive is an
  unimplemented abstraction with no SM750 GPIO or register binding. The DDK
  never enters D3 at all, so it needs no D3 recovery.
- Q2: the DDK requests DDC by read-modify-writing 0x1A[2], waits up to 50 x
  200 ms for 0x1A[1], sets both bits on success, and restores the saved 0x1A
  value on timeout. It never disables link security before the request, and it
  never distinguishes a NACK on the release write.
- Q3: there is no per-transfer retry. In the shipped SiI9022 build the ACK
  results are compiled out and a write always reports success; a missing ACK
  is invisible. Bus clearing is nine STOP conditions at every `swI2CInit()`,
  plus one SCL pulse when the kernel adapter is created.
- Q4: bit-bang, for both TPI and EDID. The hardware I2C engine is used
  elsewhere in the DDK and is reset before every transfer; the only stated
  reason for the bit-bang path is a comment about the hardware engine leaving
  the bus deadlocked.
- Q5: no document. The vendor state machine does handle the HPD=1 /
  RX_SENSE=0 case in code: on RX-sense loss with the cable still connected it
  mutes HDCP, disables TMDS and drops the output to DVI mode, then waits for
  the RX-sense interrupt and re-runs the full init. It does not delay the EDID
  read until RX sense is up, and it discards an EDID failure.

---

## 2. Sources obtained

All retrieved 2026-11-22.

| # | URL | Title / description | Date | What it is |
| --- | --- | --- | --- | --- |
| S1 | https://github.com/teddywlq/smifb2 | "SiliconMotion SM768/SM750 PCIe driver for kernel5.X", 128 files | last push 2026-11-03, branch `main` | Vendor DDK ported to Linux 5.x. `ddk750/` holds `siHdmiTx_902x_TPI.c` (3490 lines), `ddk750_sii9022.c` (92 lines), `ddk750_edid.c` (2226 lines), `ddk750_swi2c.c` (823 lines), `ddk750_hwi2c.c` (479 lines). Primary source for Q1-Q5. |
| S2 | https://github.com/teddywlq/smifb4.0 | "SM770/SM768/SM750 Linux DRM Display Driver for Kernel v5.x above", 183 files | last push 2026-10-20, branch `main` | Later drop of the same DDK. `ddk750/` files are the same logic with small line offsets (for example `swI2CInit` at 360 instead of 352). Adds `ddk770/` with its own SW and HW I2C. Used to confirm that a finding is vendor policy and not one snapshot. |
| S3 | https://github.com/teddywlq/smifb | "SiliconMotion SM750/SM768/SM770 DRM driver for kernel 4.x", 178 files | last push 2026-10-17, branch `main` | Older drop, contains `ddk770/` too. Used only for cross-checks. Note: this tree has no `ddk750/siHdmiTx.c` either, see the correction in Q1. |
| S4 | https://raw.githubusercontent.com/teddywlq/smifb2/main/Makefile | build file | as S1 | Shows `EXTRA_CFLAGS += -DUSE_HDMICHIP`, which selects the ACK-discarding branch described in Q3. |

Nothing else was obtained. In particular there is no WinCE 6.0/7.0 BSP, no
WDDM or XP driver source drop, and no Silicon Motion document about I2C
arbitration between the host and the in-chip HDCP engine. Section 5 lists the
gaps and section 6 the searches.

Two artefacts that earlier notes cite as existing in a different file are
wrong and are corrected here:

- The "HW debounce to 64ms" write of 0x7C = 0x14 is not in a `siHdmiTx.c`; it
  is in `TXHAL_InitPostReset()` at `ddk750/siHdmiTx_902x_TPI.c:214-220` in all
  three drops. There is no `siHdmiTx.c` in any of them.
- `ddk750/` in S1-S3 has no file that performs an SM750 GPIO toggle for the
  transmitter. See Q1.

---

## 3. Per-question findings

### Q1. Reset GPIO before initialisation, and reset out of D3

Verdict: PARTIAL. The procedure exists, with an explicit pulse length, but it
is dead code, the pin is not bound to any SM750 GPIO, and the DDK never enters
D3.

1. The helper `TxHW_Reset()` is present but inside `#if 0`:
   `ddk750/siHdmiTx_902x_TPI.c:222` opens the block and `:237` closes it.
   Inside, the body prints a trace line, optionally calls a platform
   `reset()` hook through `Sii902xA_plat_data`, then has the pin sequence
   commented out as pseudo-code:

   - `siHdmiTx_HwResetPin = LOW;`
   - `DelayMS(TX_HW_RESET_PERIOD);`
   - `siHdmiTx_HwResetPin = HIGH;`
   - then `TXHAL_InitPostReset();`

   Source: https://raw.githubusercontent.com/teddywlq/smifb2/main/ddk750/siHdmiTx_902x_TPI.c

2. The pulse length is a named constant: `#define TX_HW_RESET_PERIOD 200` at
   `ddk750/siHdmiTx_902x_TPI.h:621` (milliseconds, used by the `DelayMS`
   macro). That is the only numeric reset timing in the vendor source, and it
   is roughly 2000x the 100 us treset-min that the in-tree `sii902x.c` uses as
   a lower bound.

3. `siHdmiTx_HwResetPin` is referenced only inside that dead block. Grepping
   all three drops for `HWResetPin`, `TxHW_Reset`, `HwReset` yields exactly
   three hits in `siHdmiTx_902x_TPI.c` (the `#if 0` definition at 222-237, one
   trace print inside it, and the commented call at 3098). It appears in no
   header, no macro definition, no GPIO register write. So there is no SM750
   GPIO number and no GPIO register associated with the transmitter reset in
   the vendor source.

4. The call site is commented out in TPI initialisation. `siHdmiTx_TPI_Init()`
   at `ddk750/siHdmiTx_902x_TPI.c:3087-3119` starts with a comment that the
   chip powers up in D2, resets its state variables, then has two comment
   lines and a live register write:

   - line 3097: `// Toggle TX reset pin`
   - line 3098: `//TxHW_Reset();`
   - line 3099: `WriteByteTPI(0xF5, 0x00);`

   After that it calls `StartTPI()`, `HDCP_Init()` (only when
   `Sii9024A_HDCP_supported`) and `EnableInterrupts(HOT_PLUG_EVENT)`, and
   returns EPERM on failure.

   The net effect: on the SM750 reference design the vendor software brings
   the transmitter up by writing 0xF5 = 0x00 and running TPI init, with no pin
   toggle. Whatever board-level reset the data sheet requires is either not
   wired on that reference design or is handled outside the driver (boot
   firmware, FPGA, or a CPLD the DDK does not talk to).

5. There is no D3 recovery path because the DDK never requests D3.
   `TX_POWER_STATE_D3` is defined as 0x03 in the mask field of register 0x1E
   (`ddk750/siHdmiTx_902x_TPI.h:800-810`: control register 0x1E, mask
   `BIT_1 | BIT_0`, D0 = 0x00, D1 = 0x01, D2 = 0x02, D3 = 0x03), but no code in
   `siHdmiTx_902x_TPI.c` writes it. The only writers are
   `siHdmiTx_PowerStateD0()` at :3232-3237,
   `siHdmiTx_PowerStateD2()` at :3243-3248 and
   `siHdmiTx_PowerStateD0fromD2()` at :3254-3265, all read-modify-writes of
   0x1E that never pass 0x03. `siHdmiTx_TPI_Init()` records D0 at :3093. The
   poll loop only runs while the state is D0 (`:3299`).

   Inference (SPECULATIVE): the vendor avoids D3 precisely because it has no
   usable reset line on the reference board. The data sheet's statement that
   D3 blocks I2C and only a hardware reset recovers is consistent with a
   design that simply never enters D3.

6. Our own register use agrees with the vendor on where bit 6 of 0x1A sits:
   `src/sii902x.c:20` names it `SII902X_SYS_CTRL_LINK_DYNAMIC` and the DDK
   calls the same field `LINK_INTEGRITY_MODE_MASK` with value
   `LINK_INTEGRITY_DYNAMIC` (used at `siHdmiTx_902x_TPI.c:2697` and :2707).
   So 0x1A[6] is link-integrity mode, not a security disable. This matters for
   Q2 and is a correction to the assumption recorded in the older note.

Board identity inference (SPECULATIVE): the DDK's default bit-bang pins are
`DEFAULT_I2C_SCL 30` and `DEFAULT_I2C_SDA 31` (`ddk750/ddk750_swi2c.h:8-9`),
which are the same two GPIOs our board uses (`src/sm750_drm.c:1416` area, and
the DDK-init path in `src/ddk750_swi2c.c`). A board that reuses the DDK's
default I2C pins most likely also reuses the DDK's board wiring, that is, no
dedicated transmitter reset line visible to software. That is consistent with
the dead reset helper but does not prove anything about the schematic, which
was not available.

### Q2. DDC ownership around HDCP

Verdict: FOUND. The whole protocol is visible in
`ddk750/siHdmiTx_902x_TPI.c:337-398` and in its call sites.

1. `GetDDC_Access(byte *SysCtrlRegVal)` at `:337-367`:

   - reads 0x1A (`TPI_SYSTEM_CONTROL_DATA_REG`, header :768) into a local and
     hands the original value back to the caller through the pointer;
   - sets only the request bit (`DDC_BUS_REQUEST_REQUESTED` = 0x04, header
     :784) on a copy, and writes the whole byte back, so every other bit of
     0x1A, including the link-integrity bit 6, the AV-mute bit and the
     HDMI/DVI bit, is preserved;
   - loops at most `T_DDC_ACCESS` = 50 times (`:335`); each pass reads 0x1A,
     and if `DDC_BUS_GRANT_MASK` (bit 1) is set it also sets the grant bit
     locally, writes 0x1A with bits [2:1] = 11, and returns TRUE; otherwise it
     re-asserts the request and sleeps `DelayMS(200)`;
   - on exhaustion it writes the saved 0x1A value back, prints
     `Get DDC Access failed` and returns FALSE. Total budget is therefore
     50 x 200 ms = 10 s.

2. The vendor never disables link security before requesting the bus. There is
   no write of 0x1A that clears bit 6 in the request path; the only 0x1A
   writes around HDCP are AV mute plus protection level. `HDCP_Off()`
   (`:1273-1283`) read-modify-writes 0x1A with `AV_MUTE_MASK` set to muted and
   writes `PROTECTION_LEVEL_MIN` to the HDCP control register (a different
   register from 0x1A), then clears the software HDCP flags. `HDCP_On()`
   (`:1289-1303`) writes `PROTECTION_LEVEL_MAX`.

   Observation (SPECULATIVE, but well grounded): the vendor satisfies the TPI
   reference's "disable link security before requesting the DDC bus" only
   indirectly, by ordering, not by clearing a bit. `DoEdidRead()` is called
   from `OnHdmiCableConnected()` at `:3209`; the disconnect handler
   `OnHdmiCableDisconnected()` (`:3165-3176`) has already called
   `OnDownstreamRxPoweredDown()`, which calls `HDCP_Off()` when HDCP was
   started (`:3134-3135`). So at the moment of a re-read, HDCP has been
   switched off by the unplug path. The DDK never demonstrates a DDC request
   while HDCP is actively running. That is a design-level answer to the
   arbitration question, not an explicit protocol.

3. `ReleaseDDC(byte SysCtrlRegVal)` at `:377-398`: clears bits [2:1] while
   preserving the rest of the saved byte, writes it, then re-reads 0x1A up to
   `T_DDC_ACCESS` times waiting for both bits to read back zero, and prints
   `failed to release DDC bus control` on exhaustion. A comment in the vendor
   source explains that the register cannot be read-modify-written while the
   bus is granted because such a read returns 0xFF; the code therefore uses
   the cached copy and pure writes for the release.

4. What it does when the grant does not arrive: restores the caller's saved
   0x1A (so a partially written request does not persist), logs one line, and
   returns FALSE. The EDID reader then returns `EDID_DDC_BUS_REQ_FAILURE` and
   the caller ignores it (see Q5). There is no retry of the request sequence,
   no bus clear, and no power-cycle of the transmitter.

5. Our driver already matches the parts that matter: it saves 0x1A, ORs in
   the request bit without clobbering the others
   (`src/sii902x.c:1088`, `:1107`), polls for the grant, and on release
   restores the saved value with bits [2:1] cleared (`:1152`). The vendor
   evidence therefore supports the existing sequence and adds a concrete
   budget (10 s) that is 20x the 500 ms used by the in-tree `sii902x.c` mux
   gate.

### Q3. Retry policy for a failed I2C transfer

Verdict: FOUND. The answer is that the shipped SiI9022 build has no
per-transfer retry and does not report NACK at all.

1. The build selects a branch that ignores ACK. `ddk750/ddk750_swi2c.c:510-541`
   has two halves under `#ifndef USE_HDMICHIP` / `#else`. The first half checks
   the three byte writes and returns -1 on failure. The second half calls the
   same three writes and discards the results, leaving `returnValue` at 0.
   The top-level `Makefile` of S1 contains `EXTRA_CFLAGS += -DUSE_HDMICHIP`,
   so the DDK as published compiles the discarding half. Every TPI write,
   including the DDC release write, therefore reports success unconditionally.

2. Reads discard ACK as well. `swI2CReadReg()` (`:406-431`) issues the start,
   the device address write and the register index write without inspecting
   either return value, then reads one byte and returns it. A NACK cannot
   reach the caller on the read path either.

3. ACK detection itself is a poll, not an edge sample. In `swI2CWriteByte()`
   (`:252-303`) the ninth clock is raised, then SDA is sampled in a loop of up
   to 0xff iterations waiting for it to go low. A slow or heavily loaded slave
   that holds SDA high for a while can therefore be mistaken for an ACK if it
   eventually pulls low, and a stuck-low SDA is also read as an ACK. This is
   the same shape as a bus-recovery wait, which is why the DDK's bit-bang path
   tolerates a stuck bus better than a strict implementation but reports
   nothing when it fails.

4. Bus clear policy, three places:

   - `swI2CInit()` ends with a nine-iteration loop of `swI2CStop()`
     (`:388-390` in S1, `:396-398` in S2) under the comment "Clear the i2c
     lines". `swI2CStop()` is SCL high, SDA low, SDA high, so this is nine
     STOP conditions, not nine SCL pulses. It runs on every
     `sii9022xSetMode()` because that function calls `swI2CInit()` first.
   - The kernel-adapter path has the equivalent loop disabled under `#if 0`
     (`:793-800`).
   - `ddk750_AdapSWI2CCleanBus()` (`:804-821`) is the only on-demand clear:
     GPIO direction init, 20 us, SCL low, 20 us, SCL high, 20 us. One clock
     pulse, no STOP, described by the comment "After closing HW I2C, give a
     SCL clk by SW to avoid the deadlock".

   So the vendor has no nine-clock unwedge as a failure response. The nine
   STOPs happen before transfers, not after a failure, and they do not generate
   clocks.

5. Retries that do exist, and their scale:

   - chip detect: `sii9022xInitChip()` in `ddk750/ddk750_sii9022.c` reads
     register 0x1B up to 10 times with a 1 ms sleep between tries and prints
     `cannot detect sii9022a chip` when it gives up;
   - DDC grant: 50 attempts, 200 ms apart (Q2);
   - EDID: `#define EDID_TOTAL_RETRY_COUNTER 1` in `ddk750/ddk750_edid.c`
     (line 976 in S1), used as the bound of a `for` loop around one complete
     EDID read attempt, that is, no retry beyond the first.

6. Is a NACK an error? In the shipped SiI9022 build, no: it is invisible. In
   the non-HDMI build of the same file it is an error, and even there only for
   register writes, not reads. Nothing in the DDK special-cases the
   unacknowledged 0x1A release write that the TPI reference mentions; the
   write "succeeds" because the return value is fabricated. This is consistent
   with treating that NACK as normal, and it is also why the DDK cannot detect
   a transmitter that has stopped acknowledging.

### Q4. Hardware I2C or bit-bang for TPI and EDID

Verdict: FOUND. Bit-bang for both, with a documented caveat about the hardware
engine.

1. TPI traffic: `ddk750/ddk750_sii9022.c` at the top maps the generic names to
   the software engine (`#define i2cWriteReg swI2CWriteReg`, `#define
   i2cReadReg swI2CReadReg`), and `siHdmiTx_902x_TPI.c:39-94` builds
   `ReadByteTPI`/`WriteByteTPI`/`I2CReadBlock`/`I2CReadEDID` on top of those
   two names. Every TPI register access and every EDID byte in the DDK goes
   through the bit-bang engine on GPIO 30/31.

2. EDID traffic: `#define ReadBlockEDID(a,b,c) I2CReadEDID(siiEDID, a, b, c)`
   at `siHdmiTx_902x_TPI.c:324`, and `I2CReadEDID` loops over
   `i2cReadReg(0xA0, addr + i)`. `ddk750_edid.c` independently uses the same
   software engine with `EDID_PANEL_I2C_SCL/SDA` aliased to the DDK defaults,
   and only a second evaluation-board path uses GPIO 17/18.

3. The hardware engine is present and used for other traffic:
   `ddk750/ddk750_hwi2c.c` has `#define HWI2C_WAIT_TIMEOUT 0xF0000` (:190)
   and a `hwI2CWaitTXDone()` busy loop (:191-201); before each write and read
   it writes 0 to the `I2C_RESET` register to clear previous status (:237-238,
   :301-302). A controller that must be reset before every transfer is a
   controller that can be left in a bad state by one.

4. Documented reason to prefer bit-bang: the only one in the source is the
   comment quoted in Q3, that a software clock pulse is needed after the
   hardware engine is closed "to avoid the deadlock". There is no errata note,
   no application note and no comment that mentions arbitration with the
   in-chip HDCP engine. Inference (SPECULATIVE): the vendor chose bit-bang for
   the shared DDC/TPI path because the SM750 hardware controller cannot be
   recovered without driving SCL from software, and because the transmitter
   may hold SCL low while its own HDCP engine owns the bus, which the
   hardware engine does not tolerate.

5. Consequence for us: our `use_hardware_i2c = false` choice
   (`src/sm750_drm.c:1416`) matches the vendor. There is no vendor evidence
   that switching to the SM750 hardware I2C engine would improve reliability;
   the one piece of evidence points the other way.

### Q5. HPD asserted while the sink receiver is not up

Verdict: PARTIAL. There is no document, but there is a state machine, and it
is not the behaviour one would design today.

1. The interrupt poll (`siHdmiTx_TPI_Poll()`, `siHdmiTx_902x_TPI.c:3295-3374`)
   treats the two conditions separately. It reads the interrupt status
   register and tests the HPD bit and the RX-sense bit independently:

   - HPD: bit 2 of the status (`HOT_PLUG_STATE`, header :356-359). When the
     state differs from `g_sys.hdmiCableConnected` it calls
     `OnHdmiCableConnected()` or `OnHdmiCableDisconnected()`, then writes page
     0 register 0x0A with bit 3 (0x08) on connect (`:3325`).
   - RX sense: bit 3 (`RX_SENSE_STATE`). When the state differs from
     `g_sys.dsRxPoweredUp` and the cable is connected, it calls
     `OnDownstreamRxPoweredDown()` or `OnDownstreamRxPoweredUp()`, sleeps
     100 ms "for metastability protection", and clears the RX-sense interrupt
     (`:3336-3351`).

   The header notes on the RX-sense mask that the bit is dual purpose
   depending on 0x3C[3], so the polarity is configurable.

2. What happens on the HPD=1, RX_SENSE=0 combination: the connect handler runs
   on the HPD edge, sets `hdmiCableConnected` and reads EDID; when the RX-sense
   comparison then shows the receiver is down, the driver calls
   `OnDownstreamRxPoweredDown()` (`:3129-3138`), which:

   - calls `HDCP_Off()` if HDCP had been started;
   - calls `DisableTMDS()`;
   - read-modify-writes 0x1A to DVI output mode, with the source comment that
     this is done "to reset HDCP".

   So the vendor response to a sink that asserts HPD while its TMDS receiver
   is not up is to stop TMDS and drop out of HDMI mode, not to retry the mode
   set. When RX sense returns, `OnDownstreamRxPoweredUp()` (`:3149-3155`) calls
   `HotPlugService()` (`:3275-3284`), which masks all interrupts with
   `DisableInterrupts(0xFF)` and re-runs `siHdmiTx_Init()`: video PLL and
   colour depth, `siHdmiTx_PowerStateD0()`, AVI info frames, audio, then TMDS
   enable and interrupt re-enable (`:2649-2714`).

3. The HPD edge itself is debounced in software: a loop clears the HPD
   interrupt, sleeps `T_HPD_DELAY` (10 ms, header) "to help filter out
   connection bouncing", re-reads status and repeats while the event
   re-appears (`:3309-3314`). This is a bounce filter, not a readiness check.

4. Critically, the EDID read is not gated on RX sense. `DoEdidRead()` is
   called from `OnHdmiCableConnected()` at `:3209` with its return value
   discarded, and `DoEdidRead()` itself (`:1094-1170`) only checks its own
   `edidDataValid` cache. So on a sink that raises HPD before its receiver is
   ready, the vendor reads EDID at the HPD edge, may fail, keeps the cache
   invalid, and would retry only on the next HPD event (which does not come).
   The DDC request itself will already have been made, up to 10 s of retries
   against a chip whose TPI may not answer yet.

   That the vendor accepted this is evidence that the reference design rarely
   hits it, not that it is correct.

5. No vendor text describes the HPD=1/RX_SENSE=0 case as a known condition, no
   delay constant for "wait for receiver" exists beyond `T_HPD_DELAY` 10 ms and
   the 100 ms RX-sense metastability sleep, and neither the TPI reference nor
   the data sheet (per the earlier note) prescribe a workaround. Hence
   PARTIAL: code behaviour found, documentation not found.

---

## 4. What would change our driver

Only items justified by FOUND evidence. No code is proposed here beyond what
the evidence forces, and nothing speculative is included.

1. Keep the transmitter out of D3, explicitly. FOUND: the vendor defines D3 in
   the 0x1E mask field and never writes it; only D0 and D2 appear in the code
   (`siHdmiTx_902x_TPI.c:3232-3265`); no reset line is bound to a GPIO
   anywhere in the DDK. Our driver writes 0x1E = 0x00 once in the init table
   (`src/sii902x.c:397`) and does not write D3, so this is a constraint to
   preserve with a comment and, if a suspend or power-down path is ever added,
   an explicit rule: power down through 0x1A[4] and 0x1E[1:0] = D2 only. The
   data sheet's D3 statement then becomes unreachable rather than
   unrecoverable.

2. Do not plan a GPIO-reset recovery for D3. FOUND: the vendor's reset helper
   is dead code with no SM750 GPIO binding, so the DDK provides neither a pin
   number nor a register to imitate, and its own board evidently works without
   one. If this board does wire a reset line, the vendor source will not tell
   us which pin; that needs the schematic or an experiment, and belongs in
   `docs/evidence/EVIDENCE-GAPS.md`, not in the driver as a guess.

3. Treat a NACK on the 0x1A release as normal, and do not model vendor
   behaviour as a retry reference. FOUND: in the shipped build a write's ACK
   result is discarded and a write always returns success, so the DDK has no
   NACK handling to copy. Our current handling, where the release write may go
   unacknowledged and the readback of 0x1A[2:1] is what decides, is the only
   correct option available and is consistent with the TPI reference.

4. Keep bit-bang. FOUND: TPI and EDID traffic in the vendor code both use the
   software engine, and the hardware engine is reset before every transfer and
   is described as able to leave the bus deadlocked. There is no vendor
   evidence for `use_hardware_i2c = true`.

5. Keep the 0x1A read-modify-write discipline. FOUND: the vendor preserves
   every bit of 0x1A except the DDC request/grant pair and restores the saved
   value when the grant times out. Our driver does the same; the vendor
   evidence means a future refactor must not replace this with a constant
   write.

6. Optionally widen the DDC grant budget, with evidence. FOUND: the vendor
   allows 50 x 200 ms = 10 s and re-asserts the request on every pass, against
   500 ms in the in-tree `sii902x.c` mux gate. This does not address the -110
   on our board, which the earlier note localises to SCL not rising, but it is
   the only vendor number available for how long a real sink may take to grant
   the bus.

7. Note the EDID-at-HPD behaviour as a known vendor weakness, not a model.
   FOUND: the vendor reads EDID at the HPD edge, does not wait for RX sense,
   ignores the failure and keeps the cache invalid. Our existing plan to treat
   EDID failure as non-fatal and to retry on HPD rise is a deliberate
   divergence, and this note is the citation for why copying the vendor is
   wrong here.

Nothing in the vendor source justifies changing the bit-bang ACK polling to a
clock-edge sample, adding nine-clock recovery, or changing the 0x1A bit 6
handling. Those remain our own choices, documented in the two earlier notes.

---

## 5. Still unknown

1. Whether this board wires a SiI9024A reset line at all. No schematic, no
   board file, and no vendor BSP GPIO table was obtainable. The dead
   `TxHW_Reset()` names a pin but never binds it.
2. Which SM750 GPIO a reset line would use if it existed. The DDK uses GPIO
   30/31 for I2C and GPIO 17/18 for a second evaluation-board EDID path, and
   has no other transmitter-related pin. Pins 0-7 are used by the DDK for
   panel power and backlight on some boards, but nothing names HDMI reset.
3. Whether any Silicon Motion document describes I2C arbitration between the
   host and the in-chip HDCP engine. None found; the TPI reference's single
   sentence about disabling link security is the only statement available.
4. The exact bit the TPI reference means by "link security". The DDK and our
   header both use 0x1A[6] as link-integrity mode and the DDK sets it to
   dynamic on purpose, so the local assumption that 0x1A[6] is a security
   disable is not supported by any source read so far. This should be
   corrected in the older note.
5. Whether the vendor's Windows driver (WDDM/XP) or any WinCE BSP exists in
   public. None found; see section 6.
6. What the vendor firmware does about D3 on boards that do have a reset line.
   The Linux DDK has no D3 path at all.
7. Whether the SM750 hardware I2C engine can serve the TPI at all. Untested
   here; the vendor resets it before every transfer and never uses it for the
   transmitter.

---

## 6. Searched for

Endpoints and verbatim queries. Note that `websearch` is unusable here (HTTP
403), GitHub code search requires auth, `grep.app` timed out and the
`searchcode.com` API returned 404, so the surface actually covered is small.

DuckDuckGo HTML endpoint (`https://html.duckduckgo.com/html/?q=...`):

- `"siHdmiTx" "SII9022A"` - "No results found".
- `sm750 wince bsp sii9022` - only generic hits (part listings, product
  brief, the smifb2 Makefile, an ADV7511 thread); no BSP.
- `sm750 wince bsp driver source` - returned `teddywlq/smifb4.0` (new to this
  research, used as S2), our own repository, and a Toradex WinCE knowledge-base
  page that is unrelated to SM750.

Bing (`https://www.bing.com/search?q=...`):

- `"sm750" "sii9022" wince bsp` - 89 results, all unrelated codec and Windows
  media pages; the endpoint geo-redirected to a non-English locale and the
  result extraction was unusable. Not pursued further.

GitHub REST repository search (`https://api.github.com/search/repositories`):

- `sii9022` - no repositories.
- `sm750 bsp` - no repositories.
- `sm750 wince` - no repositories.
- `sm750 hdmi` - only `KodeMunkie/sm750hdmifb` (this project).

Direct `raw.githubusercontent.com` probes for a known third-party SiI9022
driver file (`drivers/video/sii9022.c`) in u-boot trees:

- `varigit/uboot-imx` master - 404.
- `boundarydevices/u-boot-imx6` master - 404.
- `OPENAILab/u-boot` master - 404.
- `u-boot/u-boot` master - 404.

Direct file probes inside S1/S2/S3 for the vendor artefacts named in the task
brief:

- `ddk750/siHdmiTx.c` - 404 in S1 and S2; absent from the S3 tree listing too.
- `ddk750/ddk750_hdmi.c` - 404 in S1 and S2.
- present instead: `ddk750/siHdmiTx_902x_TPI.c`, `ddk750/siHdmiTx_902x_TPI.h`,
  `ddk750/ddk750_sii9022.c`, `ddk750/ddk750_sii9022.h`,
  `ddk750/ddk750_edid.c`, `ddk750/ddk750_swi2c.c`, `ddk750/ddk750_hwi2c.c`,
  `ddk750/ddk750_reggpio.h`.

Not searched, recorded as gaps rather than as negative evidence: board vendor
support portals (IEI, Advantech, Portwell, DFI, Avalue, Congatec, Arbor,
Vecow) which require login, the Silicon Motion partner download area, and any
Chinese-language forum or CSDN copy of a WinCE BSP. A CSDN SM750 data sheet
mirror appeared in the DuckDuckGo results but is a scan of the public data
sheet already covered by the earlier note and was not opened.
