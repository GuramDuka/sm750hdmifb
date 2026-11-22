# SiI9024A vendor and embedded-integration research

Scope: the vendor (Silicon Image / Lattice) documentation and the embedded
integration record for the SiI9022A / SiI9024A HDMI transmitter, as it bears on
this driver's "SiI9024A receiver not ready after 2000 ms" wait and on the rarer
-110 (ETIMEDOUT) failure on the DDC/I2C path. Upstream Linux kernel code is the
subject of a separate investigation and is referenced here only where a vendor
document forces a conclusion.

Researched 2026-11-21. Every claim below carries one of these tags:

| Tag | Meaning |
| --- | --- |
| [DS] | Stated in the Silicon Image / Lattice device data sheet |
| [PR] | Stated in the vendor TPI Programmer's Reference |
| [DDK] | Visible in Silicon Motion SM750/SM768 vendor DDK source code |
| [VND] | Visible in other published vendor source code |
| [FORUM] | Reported by an engineer on a public forum or issue tracker |
| [INF] | My inference. Not stated by any vendor document |

Line references such as `ds2.txt:1899` point into the plain-text extracts of the
two PDFs. Those extracts are scratch files under
`/mega/tmp/bloomery/tmp/opencode/sii/`, not repository content:

- `ds2.pdf` / `ds2.txt` (5123 lines): data sheet text extract.
- `tpi.pdf` / `tpi.txt` (2509 lines): TPI Programmer's Reference text extract.

## 0. Documents obtained

### 0.1 Data sheet [DS]

"SiI9022A/SiI9024A HDMI Transmitter Data Sheet", document `SiI-DS-1076-E.01`,
cover date August 2016, footer "2009-2016 Lattice Semiconductor Corp." 80 pages.

Publicly available. Retrieved from
`https://static.chipdip.ru/lib/507/DOC052507209.pdf` on 2026-11-21. Other live
mirrors seen the same day: `datasheet.ersaelectronics.com`,
`ws.yic-electronics.com`, `si.kovich-ic.com`, `www.alterasemiconductor.com`.
`mm.digikey.com` and `media.digikey.com` serve HTML instead of the PDF.

Critical structural fact: **the data sheet contains no register map.** A search
for `0x3D`, `3Dh` and for a register table in `ds2.txt` returns nothing. The
data sheet repeatedly says "refer to the Programmer's Reference for more
details" for register-level behaviour.

### 0.2 TPI Programmer's Reference [PR]

"SiI9022A and SiI9024A Transmitter Programming Interface (TPI) Programmer's
Reference", document `SiI-PR-1064-A`, September 2011, Silicon Image, Inc.
Revision history (`tpi.txt:73-78`) reads: revision A, 9/28/2011, "First release;
content extracted from PR-1032." Every page footer carries the word
CONFIDENTIAL.

This is the document that defines register 0x3D and the whole host programming
model, and it is the one the data sheet defers to. It is not published by
Lattice. It circulates publicly: retrieved from
`http://files.chinaaet.com/files/group/2019/20170512/334-6363018347319620716706742.pdf`
on 2026-11-21. Because the document is marked confidential and Lattice does not
distribute it, treat it as a leaked-but-authentic vendor document: cite it, do
not republish it, and do not assume a customer could obtain it through normal
channels.

### 0.3 SM750/SM768 vendor DDK (source) [DDK]

`github.com/teddywlq/smifb`, branch `main`, directory `ddk750/`. This is a
publicly mirrored Silicon Motion reference DDK for SM750/SM768 that includes a
SiI9022A driver (`ddk750_sii9022.c`), the Silicon Image TPI HAL ported into the
DDK (`siHdmiTx_902x_TPI.c`, `siHdmiTx.c`, `siHdmiTx_902x_TPI.h`), a bit-banged
I2C master (`ddk750_swi2c.c`) and a hardware I2C master (`ddk750_hwi2c.c`). No
Silicon Motion DDK PDF or programming guide was found (see section 7).

### 0.4 Microchip AT91Bootstrap SiI9022 driver (source) [VND]

`github.com/linux4sam/at91bootstrap`, file `driver/hdmi_SiI9022.c`, header
"Copyright (C) 2014 Microchip Technology Inc.", SPDX MIT. Retrieved from
`https://raw.githubusercontent.com/linux4sam/at91bootstrap/master/driver/hdmi_SiI9022.c`.
A second, independent vendor integration of the same chip, useful because its
comments record vendor sequencing knowledge that the data sheet does not.

## 1. Register 0x3D: bits, latching, and what RSEN and HPD physically mean

### 1.1 The register as documented [PR]

Table 20, "TPI Interrupt Status (R/W)", offset 0x3D, appears at
`tpi.txt:1783-1800` (printed page 29 of the PDF). Verbatim from the extracted
text:

> Shows current status of interrupt events, even if the event has been disabled.
> This register can be polled for activity if the associated interrupt has been
> disabled. Write 1 to interrupt bits to clear the 'pending' status. Bits 3 and 2
> serve only to show the current state and cannot be cleared.

Bit assignments, transcribing the table columns:

| Bit | Label in Table 20 | Values given | Latched or live |
| --- | --- | --- | --- |
| 7 | HDCP Authentication status change Event pending | 0 - No, 1 - Yes | latched, write 1 to clear |
| 6 | RSVD | - | - |
| 5 | Security Status Change Event pending | 0 - No, 1 - Yes | latched, write 1 to clear |
| 4 | Audio Error Event pending | 0 - No, 1 - Yes | latched, write 1 to clear |
| 3 | RxSense current state or CPI Event pending state (RO) | 0 - No Rx sensed/CPI, 1 - Powered Rx attached/CPI event pending | live, not clearable |
| 2 | Hot Plug pin current state or CTRL Bus Transaction Event pending state (RO) | 0 - HP Low or no event pending, 1 - HP High or CTRL event pending | live, not clearable |
| 1 | Receiver Sense Event pending or CTRL Bus Error indicated | 0 - No, 1 - Yes | latched event, write 1 to clear |
| 0 | Hot Plug / Connection Event pending | 0 - No, 1 - Yes | latched event, write 1 to clear |

The two paragraphs that follow the table (`tpi.txt:1802-1812`):

> Hot Plug / Connection. The Hot Plug state (HTPLG signal from the DVI or HDMI
> sink) indicates whether a display is attached (the EDID is readable, but the
> display is not necessarily powered up). The Hot Plug event indicates whether
> the state has changed.

> Receiver Sense. The Receiver Sense state (RxSense signal from HDCP) indicates
> whether a powered-up receiver is sensed (whether the TMDS lines are being
> pulled externally to 3.3 V). The Receiver Sense event indicates whether the
> state has changed.

### 1.2 A documented gap: "CTRL Bus Transaction Error"

Table 20 is the only place in the whole 2509-line document where the string
"CTRL Bus" appears (`grep -n "CTRL " tpi.txt` returns only lines 1787 and
1788). It is never defined, and the table contradicts the paragraph above it:
the paragraph says bits 3 and 2 "serve only to show the current state and cannot
be cleared", while the bit 2 and bit 1 labels both claim to report a "CTRL Bus
Transaction Error".

So the vendor documentation does not tell you how to distinguish, from 0x3D
alone, a latched receiver-sense event from a reported failure of the local
(TPI) I2C transaction. [INF] The nearest thing to a discriminator is the
documented write-to-clear behaviour: write the observed bits back to 0x3D and
re-read. A pure event clears; a real bus-watchdog complaint plausibly re-asserts.
That test is inference, not documented.

### 1.3 Hot plug: the documented readiness condition

This is the load-bearing statement for the driver. `tpi.txt:2040-2041`:

> The host can poll the Interrupt Status register to watch for EDID
> availability (bit 2 = 1) and monitor powered-on status (bit 3 = 1), or can
> enable interrupts for hot plug events.

and, in the "Suggested Service Flow" step 3 (`tpi.txt:2050-2056`):

> If TPI 0x3D[3:2] = 00 confirms an Unplug event; any other state indicates
> instability in the connection (which should be monitored until it becomes
> stable before proceeding).
>
> If TPI 0x3D[2] = 1, a Plug event has occurred and has likely stabilized.
> Interrupts due to Plug events are delayed until after the HPD signal has
> stabilized at a High level for ~500ms.

The data sheet defines HPD itself (`ds2.txt:611-618`):

> When HIGH, the HPD signal indicates to the transmitter that the EDID of the
> connected receiver is readable. A HIGH voltage is at least 2.0 V, and a LOW
> voltage is less than 0.8 V.

HPD is 5 V tolerant with a 10 kOhm pulldown at the connector and needs no level
shifter (`ds2.txt:4520-4522`).

Three consequences, in increasing order of force:

1. [DS] HPD high is the *definition* of "the sink's EDID is readable".
2. [PR] 0x3D[2] = 1 is the recommended poll target for EDID availability.
3. [PR] 0x3D[3] = 1 is described as "powered-on status" and nothing more: a
   monitor that is attached but powered down is a normal, documented state, and
   the PR explicitly says the EDID is readable in it.

Nothing in either vendor document makes receiver sense (0x3D[3]) a precondition
for reading EDID, for TPI register access, or for enabling the transmitter.

### 1.4 Reading the four observed values

Documented part first, then inference, kept separate.

`0x04` = bits 2 only.

- Documented: 0x3D[2] = 1 means "HP High" [PR]. 0x3D[3] = 0 means "No Rx
  sensed" [PR]. Bits 1:0 = 0 means no pending plug/RSEN event and (if that
  reading of bit 1 applies) no reported bus error.
- [INF] Meaning: the sink is plugged in and its EDID is readable; the sink is
  not powering the TMDS terminations, i.e. it is off, asleep, or behind a switch
  that keeps HPD high while the far side is unpowered. This is exactly the
  documented "display is attached but not necessarily powered up" case. It is a
  normal state, not a fault, and it is the state in which the PR says to go
  read EDID.

`0x06` = bits 2 and 1.

- Documented: HPD high, RSEN low, plus bit 1 = "Receiver Sense Event pending or
  CTRL Bus Error indicated" [PR].
- [INF] Either an as-yet-uncleared RSEN change event (most likely: the monitor
  just powered down, so RSEN fell and latched an event), or the chip is
  reporting that the last local I2C transaction to it was disturbed. The
  register cannot tell you which. If the driver sees 0x06 on a mode set that
  also produced -110, the "CTRL bus error" reading becomes the more attractive
  of the two.

`0x0e` = bits 3, 2, 1.

- Documented: HPD high, RSEN high ("Powered Rx attached") plus a pending bit 1.
- [INF] The sink is on and terminating TMDS. The pending bit 1 is the RSEN
  transition that just happened (monitor came back up). This is the *success*
  case being mislabelled: the driver's readiness predicate must therefore be
  testing something other than "HPD and RSEN are both high", or the register was
  sampled before the state finished settling. Worth checking what the driver
  treats as "not ready" for this value, because on the vendor documentation this
  is a ready panel.

`0xa0` = bits 7 and 5.

- Documented: bit 7 = HDCP authentication status change event pending; bit 5 =
  security status change event pending; bits 4:0 all zero, so HPD pin low, RSEN
  low, no pending plug/RSEN event [PR].
- [INF] The link was authenticated (HDCP was running), then the sink
  disappeared: HPD went low and both the HDCP and the security state machines
  latched a change. By the time 0x3D was read the plug event had already been
  consumed (bit 0 clear) or was never enabled. Practical reading: "the monitor
  is electrically absent right now". No amount of waiting for "receiver ready"
  can fix that; what is needed is for HPD to come back, or for the sink-side
  device (monitor, KVM, HDMI switch, panel) to be brought up.

### 1.5 Is TPI access legal while the receiver is unpowered, or while HPD is low?

- HPD low does not block register access. Neither vendor document ties TPI
  access to HPD. The only documented states that block access are D3 Hot and
  D3 Cold [PR]: "Both have no access to I2C to clear INT until a RESET is
  asserted" (`tpi.txt:1955-1960`), and the data sheet states it plainly
  (`ds2.txt:2287-2292`):

  > Once in D3 Hot or Cold modes, the I2C registers are no longer accessible,
  > and to regain full access to the internal registers, the transmitter must
  > be hardware reset.

  Entry to D3 also has a precondition [DS][PR]: "HPD must be LOW or a cable must
  not be connected prior to entering D3" (`tpi.txt:1950-1952`), and the
  Microchip driver repeats it as an operational note: "D3 cold Note: It is
  necessary to unplug the HDMI connector, otherwise would not go to D3 cold"
  [VND]. The data sheet's D3 feature table (`ds2.txt:2312-2325`) lists "Cable
  must be disconnected before entering D3 Cold".

- The chip being *unpowered* is different, and this is the real constraint
  [DS] (`ds2.txt:578-583`):

  > The controller I2C interface on the transmitter (signals CSCL and CSDA) is a
  > slave interface with an operating frequency from 40 kHz to 400 kHz and with
  > an input tolerance of up to 4.0 V when all chip operating voltages are
  > present.

  The qualifier "when all chip operating voltages are present" is the whole
  point: 5 V-tolerant inputs are only guaranteed while the chip is powered.
  [INF] Driving the DDC pull-ups into an unpowered SiI9024A (back-powering
  through the ESD structures) is outside the documented envelope, and a
  device held in reset with its rails down will not answer I2C at all: the
  symptom is a plain NACK, or a stuck bus if the die is partially powered.

- Third documented gate on the DDC path, which matters for the -110 case
  [PR] (`tpi.txt:383-386`): the transmitter "has the ability to block the
  graphics host from accessing this bus when using it for HDCP, and also
  monitors the bus for activity to prevent breaking an active connection". The
  PR also requires (`tpi.txt:1394-1396`) that the host "must disable link
  security before requesting use of the DDC bus" and notes HDCP "link integrity
  checking will be taking place every 128 frames". So the DDC bus can be
  legitimately unavailable to the host while HDCP is active, which looks exactly
  like a bus fault from the driver's side. This is a strong candidate
  explanation for a -110 that appears only after a monitor power cycle, because
  that is precisely the event that tears an HDCP link down mid-frame.

## 2. Power-up and I2C readiness timing

### 2.1 Reset to register access

| Parameter | Value | Source |
| --- | --- | --- |
| TRESET, RESET# low time | min 100 us | [DS] Table 3.14, `ds2.txt:1108-1120` |
| TRST, reset pulse width | min 50 us | [PR] Table 22, `tpi.txt:2128-2138` |
| TACC, reset to host register access | max 1 ms | [PR] Table 22 |
| TI2CDVD, I2C data valid delay | max 700 ns | [DS] Table 3.14 |

Use the larger reset requirement (100 us) since it is the device-specific,
later document. [DS] also states (`ds2.txt:1131`) that "Reset on RESET# signal
can be LOW as CVCC12 and IOVCC become stable, or be pulled LOW for at least
TRESET", i.e. the vendor accepts a reset tied to the rail ramp; there is no
documented rail sequencing requirement beyond that. `ds2.txt:919` note 5 warns
only that "IOVCC, CVCC12, and AVCC12 should not be removed in the low-power
modes because input states and leakage current cannot [be guaranteed]".

### 2.2 TPI mode entry must be the first register write

[PR] (`tpi.txt:440-466`): after hardware reset the host writes `0x00` to
`0x72:0xC7`, and

> If the write is not done as the first register write, the transmitter will
> revert to Compatible Mode register set operation; the TPI registers will not
> be accessible.

The same table gives the readiness test for step 2: "When TPI 0x1B can be read
correctly, the TPI subsystem is ready." 0x1B reads 0xB0 for both SiI9022A and
SiI9024A (`tpi.txt:633-668`); 0x1D is the TPI revision (0x03) and 0x30 the HDCP
revision (0x00 on SiI9022A, 0x12 on SiI9024A), which is the only documented way
to tell the two parts apart.

### 2.3 How long vendor code actually waits

- [DDK] `ddk750/ddk750_sii9022.c:46-64`, `sii9022xInitChip()`: write 0xC7 = 0,
  then a 10-iteration loop of `msleep(1)` plus a read of 0x1B, giving up with
  `printk("cannot detect sii9022a chip:rcc=%x\n", rcc)`. Budget: **10 ms**.
- [DDK] `ddk750/siHdmiTx_902x_TPI.c:3074-3112`, `StartTPI()`: write 0xC7 = 0,
  `DelayMS(100)`, read the indexed page-0 ID bytes to build a 16-bit ID, then
  check 0x1B against 0xB0. Budget: **100 ms**.
- [VND] AT91Bootstrap `SiI9022_enter_power_state_D3_Cold()`: `unsigned int
  timeout = 10`, and each iteration re-does the whole sequence (write 0xC7 = 0,
  `mdelay(100)`, write 0x1E = D0, read 0x1B), looping `while ((--timeout) &&
  (device_id == 0x0))`. Budget: **up to 1 s**, and the retry unit is the whole
  init sequence, not a bare ID read.

So published vendor code budgets 10 ms, 100 ms, or 1 s for "the chip answers on
I2C and is in TPI mode". Nothing in vendor code waits seconds for a *receiver*
to appear.

### 2.4 Sink-side readiness after HPD

| Parameter | Value | Source |
| --- | --- | --- |
| TPLUG_DLY, HPD high and stable to INT asserted | min 400 / typ 480 / max 600 ms, programmable in 3.4 ms steps | [PR] Table 23, `tpi.txt:2130-2138` |
| TUNPLUG_DLY, HPD low to INT asserted | max 1 ms, not programmable | [PR] Table 23 |
| HPD high threshold | at least 2.0 V | [DS] `ds2.txt:611-618` |
| HDCP handshake after TMDS enable | "can take up to 2 seconds ... depending on sink readiness" | [PR] `tpi.txt:486-524`, step 10 |

The 400-600 ms figure is the *transmitter's* interrupt delay, described in the
service flow as "delayed until after the HPD signal has stabilized at a High
level for ~500ms". It is a debounce/persistence window on the HPD pin, not a
statement about how long the sink needs before it can serve EDID. [INF] It is
still the best vendor-derived number for "how long to wait after HPD rises
before touching DDC", because the vendor explicitly uses it to decide that a
plug event "has likely stabilized".

The 2-second figure is unrelated to receiver readiness: it is how long the
chip's own HDCP engine may take, without host involvement, after the host
enables the TMDS output. [INF] It is probably where the driver's 2000 ms
constant came from, but applying it to RSEN readiness is a category error.

Debounce can also be changed in hardware. [PR] gives an indexed-register
recipe (`tpi.txt:1990-2015` area): write `0xBC = 0x01` (page 0), `0xBD = 0x7A`
(index), `0xBE = 0x13` for approximately 64 ms. [DDK]/[VND] both instead write
`0x7C = 0x14`, commented "HW debounce to 64ms" (`siHdmiTx.c:246-251`, and
`SiI9022_TxHW_Reset()` in AT91Bootstrap). [INF] The two recipes differ by one
bit in the last byte; the vendor code is the empirically validated one for this
chip revision, so prefer 0x7C = 0x14 and treat the PR's 0xBE = 0x13 as the
documented-but-different path.

### 2.5 What the vendor does *not* document

A grep of the TPI Programmer's Reference for `stretch`, `timeout`, `errata`,
`erratum`, `nack`, `not ack`, `busy` returns exactly one hit in 2509 lines:

> 4. Once the host has finished reading EDID, it must write TPI 0x1A = 00 to
> clear the request. The device will not ACK this write. (`tpi.txt:1394-1398`)

That single NACK is by design: after the host releases the DDC request, the
chip does not acknowledge. [INF] A driver that treats every NACK as fatal will
report a spurious failure on every successful EDID read sequence. This is worth
checking directly against the driver's error paths.

There is no documented retry scheme, no documented timeout value, no documented
bus-recovery procedure and no published erratum for I2C/DDC timeouts, stuck
buses or ACK loss on this part. The data sheet does document that the part
*accommodates* stretching (`ds2.txt:1899-1917`: "The DSCL signal is
bi-directional, since the transmitter monitors the state of DSCL so that it can
accommodate I2C clock stretching by the slave device") and offers a stall
feature to bridge 400 kHz local I2C to 100 kHz DDC, but prescribes no host-side
timing.

## 3. Vendor application notes and SM750 DDK references

### 3.1 Application notes: none obtainable

No Lattice or Silicon Image application note for the SiI902x family was found in
public. The Lattice product page
`https://www.latticesemi.com/en/Products/ASSPs/MobileHDMITransmitters` returns a
JavaScript shell with no document list, and searches surfaced only data sheet
mirrors plus a CSDN upload of the (confidential) TPI Programmer's Reference
behind a login. Also unobtainable: any reference schematic for an "HDMI panel"
built on the SiI9024A/driver-board pair; any Lattice errata, PCN or
qualification report for the part. Section 7 lists this as a gap.

The practical substitute for an application note is the TPI Programmer's
Reference, which is written as an integration guide: it contains an
initialization table (`tpi.txt:439-466`), a hot-plug service flow
(`tpi.txt:2016-2060`), a ten-step "Servicing a Hot Plug Event" table
(`tpi.txt:486-524`), the DDC request/grant protocol (`tpi.txt:1384-1399`), the
power state machine (`tpi.txt:1929-2015`), and the timing tables (22, 23).

### 3.2 The vendor's own order of operations [PR]

`tpi.txt:398-419` is unambiguous about ordering, and it is not the order this
driver appears to use:

> Hot Plug Service. Until a device is attached, the host just monitors the
> connection status either through interrupts or by polling. The host software
> waits for an attached Sink hot plug event, and then: Reads the downstream
> Sink EDID information; Powers up the transmitter (D0 state); Sends active
> video corresponding to the Sink capabilities...

and the ten-step table (`tpi.txt:486-524`) begins with "The host requests and is
granted the DDC bus, reads video and audio capabilities from the EDID ROM, and
starts sending video at a supported resolution", with TMDS output enabled at
step 8 and HDCP left to run afterwards at step 10.

So the vendor sequence is: reset, TPI mode, TPI identity check, monitor HPD, on
plug read EDID over the DDC request/grant path, *then* configure video and power
up the transmitter, *then* enable TMDS, and let HDCP do its own thing.

Two further rules that bite in practice:

- [PR] `tpi.txt:2006`: "To prevent HPD and RSEN from clearing when writing a new
  value to TPI 0x1A[4], change at least one other bit at 0x1A[2], 0x1A[3], or
  0x1A[6]." A naive read-modify-write of 0x1A[4] can wipe the pin state
  reporting that the driver is polling.
- [PR] `tpi.txt:1384-1399`, the DDC release sequence: write 0x1A = 0x00, expect
  no ACK, then "read TPI 0x1A[2:1] and verify that they are 00 (repeat step 4
  if not)". That readback loop is the only vendor-documented recovery from a
  stuck DDC grant.

### 3.3 SM750 DDK: what Silicon Motion's own reference code does [DDK]

- `ddk750/ddk750_sii9022.c:15` `#define SII9022_DEVICE_ID 0xb0`;
  `:17-18` `#define i2cWriteReg swI2CWriteReg` / `#define i2cReadReg
  swI2CReadReg`. The SM750 DDK talks to the SiI9022 over **bit-banged GPIO I2C**,
  not the SM750 hardware I2C controller. Whatever the SM750 DDK validated, it
  validated on a bit-banged bus.
- `sii9022xSetMode()` (`:33-44`): `swI2CInit` -> `siHdmiTx_VideoSel(num)` ->
  `siHdmiTx_AudioSel(0x02)` -> `siHdmiTx_TPI_Init()` -> `siHdmiTx_VideoSet()` ->
  write 0x63 = 0. There is no receiver-ready wait anywhere in this path.
- `siHdmiTx_TPI_Init()` (`siHdmiTx_902x_TPI.c:3114-3143`): comment "Chip powers
  up in D2 mode", writes 0xF5 = 0x00, calls `StartTPI()`, then enables only
  `HOT_PLUG_EVENT` in 0x3C.
- `HotPlugService()` (`:3308-3390`) is the closest thing to a vendor "wait for
  the sink" routine, and it is event-driven: on 0x3D bit 0 it writes
  `HOT_PLUG_EVENT` back to 0x3D, `DelayMS(T_HPD_DELAY)` with `T_HPD_DELAY = 10`
  ms, re-reads 0x3D and repeats while the bit re-asserts (a 10 ms bounce
  filter); it then compares `(status & HOT_PLUG_STATE) >> 2` and
  `(status & RX_SENSE_STATE) >> 3` against cached values, and on an RSEN change
  calls `OnDownstreamRxPoweredUp/Down`, waits `DelayMS(100)`, and clears the
  RSEN event. Note the shape: a 100 ms settle after the RSEN edge, not a
  multi-second wait for RSEN to be high.
- `GetDDC_Access()` (`:361-400`): `#define T_DDC_ACCESS 50`, OR 0x04 into 0x1A,
  then loop up to 50 times on the grant bit 0x02 with `DelayMS(200)` each time,
  i.e. a **10 second** worst case that the code tolerates. A comment in the same
  routine notes that a read of TPI_SYSTEM_CONTROL is invalid while DDC is
  granted and returns 0xFF. `ReleaseDDC()` (`:403-420`) mirrors it.
- `siHdmiTx_902x_TPI.h:987-1010`: `TPI_INTERRUPT_STATUS_REG 0x3D`,
  `RX_SENSE_MASK BIT_3` with the comment "This bit is dual purpose depending on
  the value of 0x3C[3]", `RX_SENSE_ATTACHED 0x08`, `HOT_PLUG_STATE BIT_2`.
- `ddk750_swi2c.c:740-741`: `connector->bit_data.udelay = 5` (commented as
  100 kHz, "same as kernel i2c-gpio default") and
  `connector->bit_data.timeout = usecs_to_jiffies(2200)`. Comments at `:93-95`
  and `:130-132` state that to drive a line high you "just set the GPIO as input
  where the pull up resistor will pull the signal up. Do not use software to
  pull up" - i.e. the vendor bit-bang relies entirely on external pull-ups and
  never drives a line high push-pull.
- `ddk750_hwi2c.c:201-218`: `#define HWI2C_WAIT_TIMEOUT 0xF0000`,
  `hwI2CWaitTXDone()` busy-waits on the status register's TX field and returns
  -1 on timeout with **no retry**. Every transfer starts with
  `pokeRegisterByte(I2C_RESET, 0)` at `:248` and `:312`, commented "Reset I2C by
  writing 0 to I2C_RESET register to clear the previous status". So Silicon
  Motion's own recovery practice is a controller reset before every transfer,
  not a retry after a failure. Max 16 bytes per start (MAX_HWI2C_FIFO).

### 3.4 Names from the task brief that do not exist publicly

`sii902x_begin_mode` and `sii902x_enable` were not found in any public source
(DuckDuckGo returns "No results found"; GitHub code search requires
authentication; grep.app was blocked). They are presumably internal names in the
driver under test. The closest public equivalents are the DDK's
`sii9022xSetMode()` / `siHdmiTx_TPI_Init()` and the vendor HAL's
`siHdmiTx_VideoSet()`.

## 4. Catalogue of engineering reports

Each entry: what was observed, how it ended, and what it implies here. Snippet
only means the page body was behind Cloudflare or a JS shell and only the search
snippet could be read; that limitation is stated per entry.

### 4.1 NVIDIA Jetson TX2, DDC read with no/absent sink: 10 s timeouts then fallback EDID

`https://forums.developer.nvidia.com/t/tx2-edid-hdmi-i2c-errors-disable-edid-read/242374`,
created 2023-02-10, 20 posts. Fetched in full.

Observed: repeated `tegra-i2c 3190000.i2c: rx dma timeout txlen:28 rxlen:128`
and `i2c transfer timed out addr: 0x50`, each followed by
`tegradc 15210000.nvdisplay: hdmi: edid read failed` / `using fallback edid`.
Reproduced with no monitor attached on both a devkit and a production board.
NVIDIA's @WayneWWW: "There is no such control in device tree ... The edid read
is triggered by display driver". @linuxdev: "i2c errors for EDID (the DDC wire)
won't interfere if you don't have a display connected, but it may indicate that
your setup thinks there is a display connected."

Resolution: none in-thread; the accepted workaround was to disable the display
controller node or live with fallback EDID.

Why it matters: same failure shape as this driver's -110. A host controller
that believes a display is present, but has no ACK on the DDC address, burns a
multi-second DMA timeout per attempt and then falls back. The instructive part
is @linuxdev's diagnosis: the *presence bit lied*, which in this driver's terms
is "HPD said 1, so we proceeded, and the DDC read had nothing to talk to".

### 4.2 ST community, STM32MP157 + SII9022, "I2C always busy"

`https://community.st.com/stm32-mpus-products-and-hardware-related-39/stm32mp157-sii9022-i2c-always-busy-60565`.
Snippet only (HTTP 403 Cloudflare; r.jina.ai returns 451).

Observed per snippet: "I used the i2c4 for sii9022 chip, but it always busy and
don't response for hdmi plug in."

Resolution: not readable. Directly relevant because "always busy" on the local
bus, with no response to plug events, is what a driver sees when the part is
held in reset, unpowered, or never entered TPI mode (see 2.2: without the
0xC7 = 0 first write the TPI registers are unreachable).

### 4.3 ST community, STM32MP157C + SII9022ACNU, probe fails with -11

`https://community.st.com/stm32-mpus-products-and-hardware-related-39/hdmi-display-related-issues-166641`.
Snippet only.

Observed per snippet: kernel 6.6, "driver keeps reporting probe failure with a
return value of -11. The SII9022 HDMI chip does not respond to I2C communication
on..." -11 is EAGAIN, i.e. the adapter reported a busy/arbitration condition
rather than a NACK.

Resolution: not readable. Value here is the error-class precedent: the same part
produces -11 (busy) rather than -ENXIO on a bus it cannot arbitrate.

### 4.4 AMD/Xilinx adaptive support, "Unable to output HDMI with SII9022 under Petalinux"

`https://adaptivesupport.amd.com/s/question/0D5Pd00000oGuLSKA0/unable-to-output-hdmi-with-sii9022-under-petalinux?language=en_US`.
Body not obtainable (page returns a JS/CSS error shell; snippet only: "That chip
is on my board and controlled via I2C ... pins ... constrained to the Sii9022
chip").

Observed: integration-level, pin/constraint oriented. Resolution: not readable.
Recorded only so the next searcher knows the thread exists and is not fetchable
without a browser session.

### 4.5 NXP i.MX53 QSB/Loco, kernel boot blocked for 2-3 minutes with HDMI

`https://community.nxp.com/t5/i-MX-Processors/kernel-boot-block-for-2-3-minutes-when-using-HDMI-on-i-mx53-QSB/m-p/160422`.
Body not obtainable (403 Cloudflare; direct fetch also 403). Snippet only.

Observed per snippet: an i.MX53 Quick Start Board / Loco board whose boot stalls
for minutes when HDMI is enabled, which is the classic "synchronous EDID read
with no sink, several retries, multi-second timeout each" pattern.

Resolution: not readable. Included because it is the single most-cited NXP
thread on this exact symptom and because the board's HDMI path is the same
SiI9022 companion-chip arrangement that the SM750 driver board uses.

### 4.6 NXP i.MX6UL EVK HDMI add-on card

Referenced repeatedly in i.MX community threads as needing "Hardware changes ...
for SiI9022(HDMI transmitter) steps as mentioned in IMX6ULEVKHUG document,
section 2.21". The referenced document ("i.MX 6UltraLite EVK Board Hardware
User's Guide", IMX6ULEVKHUG Rev. 0, 08/2015 per the search index; Rev 1, 03/2016
per other mirrors) could not be downloaded: mirrors hang or return HTML (see
section 7). [FORUM] therefore: NXP shipped an SiI9022A-based HDMI daughter card
for the i.MX6UL EVK and documented board-level changes for it, but the text of
that section is not verified here.

### 4.7 Microchip/Atmel AT91Bootstrap source as an integration report [VND]

`driver/hdmi_SiI9022.c` (MIT, 2014) is the only vendor integration found that
documents the D3 trap in code comments and that retries the whole init sequence
rather than an ID read: 10 iterations, `mdelay(100)` each, clearing 0x3D with
0xFF before and after, and setting `0x3C = HOT_PLUG_EVENT | 0x08` so that both
HPD and RSEN can wake the part. See 2.3 and 3.2.

### 4.8 ddcutil issue 148, a sink that answers but returns garbage

`https://github.com/rockowitz/ddcutil/issues/148`, opened 2020-10-19, closed
2020-11-09, labels "monitor specific", "lg". Fetched in full.

Observed: GreatWall 32CL36 over an AMDGPU hardware I2C bus. EDID at 0x50 reads
fine; DDC/CI at 0x37 reports "responsive: true" but the payload is garbage.
Maintainer @rockowitz: "It appears that your monitor has a marginal I2C
implementation ... The first read() returns bytes that are almost valid, the
second and third are pure garbage", and advised `--sleep-multiplier 4`: "if that
doesn't solve the problem I doubt anything larger would succeed". The reporter
tried multipliers 4, 16, 32, 64 and 96; all failed.

Resolution: closed as a monitor defect, no fix. Lesson for this driver: a bad
sink can present as intermittent ACK loss and garbage reads, and neither retries
nor added delays fix it. If the panel in this project is a custom HDMI panel
rather than a retail monitor, its own EDID EEPROM and DDC front end are a
legitimate suspect and should be tested with an external reader.

### 4.9 i2c-bus.org, blocked bus and clock stretching

`https://www.i2c-bus.org/i2c-primer/analysing-obscure-problems/blocked-bus/` and
`https://www.i2c-bus.org/clock-stretching/`. Fetched in full.

Blocked bus: a slave is a state machine; if the master is reset mid-byte the
slave keeps waiting for clocks and ignores the next START. Recommended:
"toggle the clock line multiple (16) times before doing any I2C operation after
power-up ... followed by a stop condition", and "In many cases this will advance
the state machine of any blocked slave to a point where it accepts the next
start condition again." The safer, more complex alternative is to power-cycle
all devices on the bus. Key sentence: "an I2C slave is not stateless".

Clock stretching: "The master ... is required to read back the clock signal
after releasing it to the high state and wait until the line has actually gone
high." A bit-banged master that does not read SCL back will corrupt transfers
against any stretching slave.

Both are generic I2C sources, not SiI-specific, and are labelled as such.

### 4.10 KVM with EDID emulation, extension block missing on first DDC read after host boot

`https://forum.gl-inet.com/t/edid-extension-block-not-served-on-first-ddc-read-after-host-reboot-windows-caps-at-1080p-and-loses-hdmi-audio-dvi-fallback/70992`,
created 2026-09-02, 5 posts. Fetched in full.

Observed: GL.iNet Comet Pro KVM (GL-RM10, firmware 1.10.0 release 4, with an
LT6911C-class HDMI front end on the input side) feeding a Windows 11 host. After
every host restart Windows came up at 1920x1080 with no HDMI audio. EDID
parsing worked, but the EDID declared an extension block that the KVM did not
serve on the first DDC read.

Root cause as diagnosed in the thread: the host read the EDID after the KVM's
HDMI chip had reset but before its EDID emulation was fully programmed, so the
host latched a stale or partial image that declared an extension block it could
not then serve. Switching EDID preset and back (which re-pulses HPD and forces a
re-read) immediately restored 2560x1440 and audio.

Resolution: reported upstream; the vendor's R&D acknowledged it and said it was
"optimizing the sequence of releasing HPD and DDC timing". Community fix: a
PowerShell EDID override installed via a helper script, or CRU. The reporter
notes the workaround cannot help when a host reads *no* EDID at all.

Why this is the most transferable report in the list: it is the same failure
family as "status=0x04, receiver not ready, enabling for compatibility". A
transmitter-side agent that treats HPD-high as licence to read EDID immediately
can serve and cache a stale image. The fix that worked was to hold HPD down
until the EDID image was complete and only then release it.

### 4.11 Electronics Stack Exchange, repairing HPD/EDID on a monitor

`https://electronics.stackexchange.com/questions/635591/repair-hdmi-hpd-and-edid-failure`,
score 1, no answers. EDID EEPROMs "not found by i2cdetect", "HDMI EDID
negotiation and HPD failure"; the same monitor later worked for a week and then
failed again.

Resolution: none. Useful only as evidence that intermittent HPD/EDID failures on
a marginal sink board look identical to a host-side driver bug.

### 4.12 Analog Devices EngineerZone, replacing SiI9022 with ADV7511 (secondary)

`https://ez.analog.com/video/f/q-a/540497/about-replacement-from-sii9022-to-adv7511`.
Fetch timed out; the search digest describes a custom i.MX7D-based board where
the SiI9022 was swapped for an ADV7511 and the resulting failures were traced to
"missing power supplies in the device tree", fixed by declaring the correct
regulators and I2C address. Secondary: the thread body was not read, only a
digest of it. [FORUM] nonetheless relevant: regulator/DT mistakes on a
transmitter produce "no response on I2C", not a clean NACK.

## 5. I2C timeout mechanisms and recovery practice for bit-banged DDC

### 5.1 The physical bus on this path [DS]

DSCL and DSDA are open-drain, 5 V tolerant, Schmitt-trigger inputs, and the
vendor requires "An external pullup resistor between 1.8 kOhm and 2.2 kOhm on
the board" on *both* lines (`ds2.txt:1899-1917`). They "operate from an
internally generated power plane, but are tolerant up to the 5 V power specified
for DDC". The transmitter actively monitors DSCL so that it can pass through
sink clock stretching.

Master DDC clock limits: FDSCL 40 / 70 / 100 kHz min/typ/max in Table 3.14
(`ds2.txt:1108-1120`). [PR] adds "There is a lower speed limit of 40 kHz on DDC
pass-through operation" and "The host software is responsible for ensuring its
DDC access speed does not exceed the limitations of any device present on the
bus - all devices must be determined capable of supporting 400 kHz operation
before the host attempts to do any accesses at that speed. Speeds in excess of
100 kHz may not be allowed by the interface specification in use"
(`tpi.txt:363-371`).

[INF] For this board, 100 kHz is the ceiling and the vendor's 1.8-2.2 kOhm
pull-ups are a hard requirement. A bit-banged master that relies on SoC-internal
pull-ups (tens of kOhm) at 100 kHz produces slow rising edges into a 5 V
Schmitt input, which the receiver can legitimately read as a stretched or
marginal clock. That is a board-level cause of -110 that no software change
fixes. It is worth measuring the two lines with a scope before rewriting the
driver's retry logic.

### 5.2 Four distinct mechanisms that all surface as a timeout

1. Sink holds SDA low (stuck bus). If the sink is power-cycled mid-transaction,
   it can remain parked mid-byte, holding SDA low, and then every subsequent
   START is interpreted as data. Generic I2C mechanism, documented by
   i2c-bus.org (4.9); recovery is a clock-train plus STOP, or a power cycle of
   the whole bus.
2. Clock stretching that never ends. Either the sink stretches indefinitely
   (sink crashed mid-byte) or the transmitter's DDC stall feature delays data.
   A bit-bang master that does not read back SCL will either violate timing or
   spin until its own guard trips. [INF] `-ETIMEDOUT` from a bit-banged adapter
   is usually exactly this: the wait-for-line-high loop exhausted.
3. The transmitter refusing the bus on purpose. [PR] documents that the
   transmitter "monitors the bus for activity to prevent breaking an active
   connection" and can "block the graphics host from accessing this bus when
   using it for HDCP" (`tpi.txt:383-386`), and requires the host to disable link
   security before requesting DDC. This is not an I2C-level fault at all; the
   chip simply does not grant or does not forward. The vendor-documented
   recovery is the 0x1A release/readback loop (`tpi.txt:1394-1399`).
4. Power/reset state. If the part is in D3, "the I2C registers are no longer
   accessible, and to regain full access to the internal registers, the
   transmitter must be hardware reset" [DS]. If the part is unpowered or held in
   reset, it will NACK or hold the bus. [PR] states the host "must have hardware
   reset control over the transmitter, typically through a GPIO pin"
   (`tpi.txt:359-361`) - a reset line is a documented design requirement, not an
   option.

### 5.3 What -110 means on this driver's path

The SM750 DDK's bit-bang is configured at `udelay = 5` (about 100 kHz) with
`bit_data.timeout = usecs_to_jiffies(2200)` [DDK]. [INF] If that field is the
`i2c-algo-bit` adapter timeout in jiffies, then the literal value is about 2.2 ms
at HZ=1000 - which is far shorter than one 128-byte EDID block at 100 kHz takes,
so the value may be dead code in the DDK port, and either way it is a plausible
source of spurious timeouts if it is live. Verify what the driver under test
actually sets before theorising further; that is a concrete, testable question.

The other documented piece of evidence is the NACK that is not an error:
releasing DDC with `0x1A = 0x00` is documented to go unacknowledged
(`tpi.txt:1394-1398`). [INF] A driver that maps every NACK to a timeout or to a
hard failure will report -110 on a *successful* EDID read cycle. This is the
cheapest thing to rule out.

### 5.4 Recovery practice, by source

- Vendor, documented [PR]: release DDC by writing `0x1A = 0x00`, then read back
  `0x1A[2:1]` and repeat until both read 0. This is the only vendor-documented
  recovery for a bus the transmitter will not hand over.
- Vendor, documented [DS][PR]: from D3, only a hardware reset recovers. There is
  no I2C-only path out of D3.
- Vendor, code [DDK]: the hardware I2C master resets the controller before every
  transfer (`pokeRegisterByte(I2C_RESET, 0)`) and does not retry on timeout; the
  bit-bang has a fixed per-transfer timeout and no recovery hook.
- Vendor, code [VND]: AT91Bootstrap clears 0x3D with 0xFF at both ends of its
  init sequence and retries the entire sequence, not individual reads.
- Generic engineering practice (i2c-bus.org): 16 clocks plus STOP; if that
  fails, power-cycle the bus. The kernel's own equivalent (a nine-clock pulse
  driven from `scl-gpios`/`sda-gpios` recovery info via `i2c_recover_bus`) is
  kernel-side and belongs to the companion investigation, but note that a plain
  `i2c-gpio` adapter has no recovery capability unless the board describes one.

### 5.5 Pull-ups, speed, and the "do not drive high" rule

[DDK] comments are explicit that the vendor bit-bang only ever drives a line low
and releases it to the external pull-up. [INF] That is correct I2C practice, and
it means the bus rise time is entirely a board property. Combined with the
data sheet's mandatory 1.8-2.2 kOhm, the first hardware question for this board
is whether both DSCL and DSDA really have 1.8-2.2 kOhm to the *sink-side* 5 V,
and whether the SM750 GPIO side is 5 V tolerant at all when the panel is off. A
level shifter on the DDC pair, or a series resistor with a too-weak pull-up, will
produce exactly the intermittent -110 pattern described here.

## 6. Recommended sequence for this driver

Each step is tagged STRONG (vendor-documented or vendor-code-documented),
PLAUSIBLE (supported by forum practice or by vendor statements that do not
directly address this case), or SPECULATIVE (my inference only).

1. STRONG - Assert the transmitter's reset line for at least 100 us and release
   it. The host is required to have reset control (`tpi.txt:359-361`), and 100 us
   is the data sheet minimum (`ds2.txt:1108-1120`).
2. STRONG - Wait, then write `0x72:0xC7 = 0x00` as the first register write, and
   confirm the part by polling TPI 0x1B for 0xB0. Both the TPI PR
   (`tpi.txt:439-466`) and every vendor code path do this. Budget: 100 ms to 1 s
   total (DDK uses 10 ms and 100 ms; AT91Bootstrap allows 1 s).
3. STRONG - Clear 0x3D by writing 0xFF (or by writing back the observed event
   bits), then read 0x3D once to establish a baseline. Vendor code clears 0x3D
   this way at both ends of init.
4. STRONG - Poll 0x3D[2] for HPD high. This, and only this, is the documented
   "EDID is readable" condition (`ds2.txt:611-618`, `tpi.txt:2040-2041`).
5. STRONG - Do not gate anything on 0x3D[3] (RSEN). No vendor document makes
   RSEN a precondition for TPI access or for reading EDID; the PR says a
   plugged-but-unpowered display still has a readable EDID, and 0x3D[3] is
   described only as "powered-on status". The current two-second wait for RSEN
   is not supported by any source found here, and the observed 0x0e case (HPD
   high, RSEN high) shows it firing even when the panel *is* powered.
6. PLAUSIBLE - After HPD goes high, wait about 500 ms before touching DDC
   (`TPLUG_DLY` typ 480 ms, max 600 ms; PR's "HPD has stabilized at a High level
   for ~500ms"). Equivalent and better: wait for the latched plug event in
   0x3D[0] to appear, which the chip asserts only after that window.
7. PLAUSIBLE - If the driver must keep a bounded wait, make it a wait for *any*
   of: the plug event bit, a successful 0x1B read, or expiry - and log the raw
   0x3D value, not a derived boolean. The four observed values decode very
   differently (section 1.4) and the log currently cannot distinguish "monitor
   absent" (0xa0) from "monitor present and powered, event pending" (0x0e).
8. PLAUSIBLE - Take the DDC bus with the request/grant protocol: set 0x1A[2],
   poll 0x1A[1] until granted, then write 0x1A = 0x06 to close the switch out to
   the DDC bus. Allow a generous grant timeout (the DDK allows 10 s) but expect
   sub-second.
9. STRONG - Release the bus by writing `0x1A = 0x00` and **ignore the NACK**
   (`tpi.txt:1394-1398`), then read back 0x1A[2:1] and repeat until zero.
10. PLAUSIBLE - On a DDC failure, before declaring the panel dead: clear 0x3D,
    re-run the release/readback loop of step 9, and pulse the clock line on the
    DDC pair (nine clocks plus STOP) to unstick a sink that was power-cycled
    mid-byte. Neither action is SiI-documented; the clock train is generic I2C
    practice and the readback loop is the vendor's documented one.
11. PLAUSIBLE - On -110: treat it as a bus-state problem, not a chip-presence
    problem. Toggle the transmitter's reset line and restart from step 1. The
    vendor documents exactly one recovery from an unreachable state, and it is a
    hardware reset.
12. STRONG - Never enter D3 with HPD high ("HPD must be LOW or a cable must not
    be connected prior to entering D3"; "Cable must be disconnected before
    entering D3 Cold"). If the driver uses D3 to save power on this panel, that
    is a latent hang: after the monitor power-cycles, HPD is high, D3 entry
    either fails or strands the part, and only a hardware reset brings it back.
13. PLAUSIBLE - Before touching the DDC bus, ensure HDCP link security is off
    (`tpi.txt:1394-1396`), otherwise the transmitter may legitimately refuse to
    hand over the bus. This is the most likely non-hardware explanation for a
    -110 that only appears right after a monitor power cycle destroys an
    authenticated link (the 0xa0 status is exactly "HDCP and security state
    changed, sink now absent").
14. SPECULATIVE - Add a board-level check of the DDC pull-ups (1.8-2.2 kOhm to
    the sink-side 5 V on both DSCL and DSDA, present even when the panel is
    unpowered) and a scope measurement of the rising edges at 100 kHz. If they
    are wrong, no driver change will remove the timeouts.

Two things the driver should stop doing, both contradicted by the documentation:
waiting for RSEN before proceeding (step 5), and treating the documented DDC
release NACK as an error (step 9).

## 7. What could not be obtained

- Any Lattice or Silicon Image **application note** for the SiI9022A/SiI9024A.
  The Lattice product page is a JavaScript shell with no document list, and no
  app note surfaced in any search. Say plainly: no public vendor app note exists
  that I could find.
- Any **reference schematic** for a SiI9024A-based HDMI panel or transmitter
  daughter card, including the NXP i.MX6UL EVK HDMI card schematic.
- The **SM750/SM768 DDK programming guide** (PDF). Only the ported source tree
  in `teddywlq/smifb` is public; the surrounding Silicon Motion documentation,
  including whatever section describes the SiI902x companion chip and the
  `sii902x_begin_mode` / `sii902x_enable` sequence named in the task brief, was
  not found.
- The functions `sii902x_begin_mode` and `sii902x_enable` themselves: no public
  source contains these names.
- **Lattice errata, PCN, qualification or IBIS documents** for these parts.
- Bodies of the following threads (Cloudflare, JS shells, or 403):
  `community.nxp.com` (the i.MX53 QSB/Loco HDMI boot-block thread and the
  i.MX6UL HDMI threads), `community.st.com` (both SiI9022 threads),
  `adaptivesupport.amd.com` (the Petalinux SiI9022 thread),
  `ez.analog.com` (the SiI9022-to-ADV7511 thread). Snippets were captured;
  resolutions were not.
- `IMX6ULEVKHUG` (i.MX 6UltraLite EVK Board Hardware User's Guide), section
  2.21 on the SiI9022 HDMI add-on card: all mirrors tried either hung or
  returned HTML (`manuals.plus` 403, `static6.arrow.com` HTTP/2 error then
  timeout).
- The I2C specification itself, NXP `UM10204`: `nxp.com` returns an Akamai
  "Access Denied" page. Generic I2C behaviour is therefore sourced from
  i2c-bus.org instead.
- ddcutil's troubleshooting page: now HTTP 404 at the URL that search indexes
  still list.
- The `websearch` tool available in this environment returns HTTP 403 for every
  query, so all searching was done through the DuckDuckGo HTML endpoint, which
  rate-limits after roughly six to eight queries and then serves captchas or
  empty result blocks. Mojeek returns 403; grep.app is behind a Vercel
  checkpoint; GitHub code search requires authentication. This is why the forum
  catalogue leans on a small number of well-verified threads rather than a broad
  sweep.

## 8. Searched for

Queries retained verbatim from this session's transcript:

- `sii9024a hdmi transmitter "no signal" board bring-up`
- `IMX6ULEVKHUG hardware user guide pdf HDMI section 2.21`
- `"sii9022" application note lattice OR "silicon image" pdf`
- `sii9022 u-boot edid read failed mailing list`
- `hdmi kvm switch holds HPD low EDID DDC read fails source`

Query themes run before the transcript was compacted, where the exact strings
were not retained (each was run through the DuckDuckGo HTML endpoint, often in
several variants):

- SiI9022A / SiI9024A / SiI9022U data sheet, TPI programmer's reference,
  register map, "0x3D", RSEN, RxSense.
- `sii902x_begin_mode`, `sii902x_enable`, SM750 SiI9022 driver source, SM750 DDK.
- SiI9022 I2C timeout, NACK, clock stretching, stuck bus, ACK loss.
- SiI9022 with i.MX (NXP community), Zynq/Petalinux (AMD), STM32MP1 (ST),
  Raspberry Pi, BeagleBone, Jetson (NVIDIA), Lattice.
- HDMI HPD held low by KVM/switch/splitter, EDID unreadable after monitor
  power cycle.
- DDC bus recovery, nine clock pulses, `i2c-gpio` recovery, i2c-alarm.
- ETIMEDOUT / -110 on DDC, `i2c transfer timed out addr: 0x50`,
  `tegra-i2c rx dma timeout`.

Tool availability during the session: `websearch` HTTP 403 on every attempt (3
tries); `webfetch` worked; DuckDuckGo HTML endpoint worked with spacing;
Cloudflare-protected vendor communities, `nxp.com` PDFs, `adaptivesupport.amd.com`
and `grep.app` were not retrievable.
