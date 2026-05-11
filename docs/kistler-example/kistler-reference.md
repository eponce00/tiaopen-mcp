---
name: KistlerFinal
description: Complete holistic reference for Kistler maXYmos NC integration — device operating model, 200-byte fieldbus protocol, LSicar_KistlerPress FB full anatomy (all 51 networks), LDrive_typeKistlerHmi UDT field-by-field verified map, supervision bible, SVGHMI faceplate file, TIA project structure, Openness API limits
type: project
originSessionId: 310b40c2-7956-4bae-924a-a66d308044e0
---
# KistlerFinal — Complete Kistler maXYmos NC Reference

## QUICK INDEX (load these first based on what's being asked)

| Need to know... | Go to |
|---|---|
| **I'm about to build / extend a Kistler HMI screen** | **§23** (proven workflow: framework API, build skeleton, gotchas, iteration speed rule, post-build verification) |
| **What does bit X of state/alarm/move/receive.status/send.control mean?** | **§19** (FB-verified ground truth — always trust this over any other section) |
| **What widget to use for displaying X / making X editable?** | **§23.4** (canonical, supersedes §20) — "If the operator types into it, it's HmiIOField InputOutput. Otherwise HmiText." |
| **How are Kistler EO byte results interpreted (pass/fail)?** | **§21** (byte=0 → pass, byte≠0 → fault code; don't add redundant Result columns) |
| **How to test a screen layout after build (overlap / off-screen / truncation)?** | **§22** (mandatory layout test suite — run after EVERY build before declaring done) |
| Openness recipe (attach, build screen, save, compile, button events) | §14 |
| Bit-extraction via MappingTable (Singlebit vs Bitmask) | §16 |
| SICAR color standard (Light green / Orange / Red / etc.) | §17 |
| Current state of `_Kistler_Press_01` screen + working scripts | §18 |
| Device protocol, 200-byte fieldbus map (Kistler raw bytes — distinct from UDT) | §6 |
| FB anatomy (51 networks, FB Inputs/Outputs) | §7 |
| ProDiag supervision design (alarms + warnings + messageErrors) | §10 |
| SVGHMI faceplate file (deferred to future, currently using regular screen) | §11 |
| Faceplate / Screen Type via Openness (not viable in V20 — known limitation) | §13 (obsolete) and §14 footnote |

**Conflict resolution rule**: if §19 disagrees with anything else in this file (including §8 which is deprecated), §19 wins — it was extracted directly from the FB XML via `extract_bit_map.py`.

---

## 1. WHAT IS THE KISTLER maXYmos NC

A combined XY process-monitor + NC press controller. Physical components:
- **MEM** — measurement module (EO evaluation, Force/Displacement)
- **DIM** — display panel (Smart Client screen at device IP, VNC viewable)
- **IndraDrive** — Rexroth servo drive (letter codes: `bb`=off, `Ab`=ready, `AH`=holding, `AF`=fieldbus active, `Cxxxx`=command, `Exxxx`=error, `Fxxxx`=fatal, `PM`=parameter mode)
- **NC joining types**: NCFH, NCFS, NCFN, NCFT, NCFE, NCFC

It samples Force(Y) vs Displacement(X), evaluates against EOs (evaluation objects), emits OK/NOK per part. Commands come from PLC over a **200-byte Profibus/Profinet fieldbus** (DPRD_DAT / DPWR_DAT, big-endian Siemens byte order).

Source manuals: NC Quick_Start (005).pdf + NC Joining Manual.pdf

---

## 2. DEVICE OPERATING MODES

| Mode | PLC control? | Notes |
|---|---|---|
| **Sequence Mode (Auto)** | YES — required | Must set `Bit 1.4 AUTO=1` + `Bit 9.0 DRIVE-ENABLE` |
| **Jog Mode (Service > Jog)** | BLOCKED when `Bit 11.7 USER-MODE-ACTIVE=1` | Manual fwd/back, force-limited, parameterised speed |
| **Service** | NO | Referencing, sensor/brake tests, manual moves |
| **Setup** | NO | Parameterise MPs/EOs/fieldbus/audit — needs user-group login |

`Bit 1.4 AUTO` = production-mode flag. Must be 1 to switch MPs from PLC.

---

## 3. MEASUREMENT PROGRAMS / PAGES / SEQUENCES

- **128 MPs** (0..127). Fieldbus encodes MP+1 in bits 2.0..2.6 (so MP#1 = byte 2 value = 2).
- Each MP: up to **4 sequences** — Main, Sub1, Sub2, Sub3 (`Bit 12.0..12.1 = CURRENT-SEQUENCE`)
- Each MP: up to **8 pages** (`Bit 18.0..18.2 = SELECT-PAGE`) — page = configurable telegram window into MP data via configurable fieldbus portion
- **MP select handshake**: PLC sets AUTO=1, writes MP bits → device echoes `MIRROR-MP` when accepted. PIEZO auto-resets on MP change.

---

## 4. EVALUATION OBJECTS (EOs)

Types: NO-PASS, LINE-X, LINE-Y, UNI-BOX, ENVELOPE, TRAPEZOID, GRADIENT-X/Y, HYSTERESIS-X/Y, TUNNELBOX-X/Y, INTEGRAL, SPEED, TIME, AVERAGE, BREAK, INFLECTION, DELTA-Y, DISPLACEMENT-RANGE, FORCE-RANGE, PASS-THROUGH-BOX, GET-REF, CALC, DIG-IN.

Each EO: OK/NOK. `OK-TOTAL=1` only if ALL EOs pass. NOK can abort sequence (Online-EO-NOK → `SEQUENCE-STOPPED=1`).

FB mapping:
- `receive.PV_EO1_Force` / `PV_EO2_Distance` / `PV_EO3_Gradient` = first 3 EO outputs
- `receive.PV_E04_Nopass` / `PV_E05_Unibox` / `PV_E06_Envelope` = result bytes for those EO types

---

## 5. CYCLE / SEQUENCE FLOW (fieldbus handshake)

```
SafetyOK + servo Ab/AF + READY=1
  → set DRIVE-ENABLE (byte 9.0) → wait DRIVE-ENABLED (out 10.5)
  → set AUTO=1 (byte 1.4) + write MP (byte 2.x) → wait MIRROR-MP echo
  → write CURRENT-SEQUENCE (byte 12.x)
  → set RUN-SEQUENCE (byte 9.1) → wait MIRROR-RUN-SEQUENCE
  → sequence runs (READY drops to 0)
  → at end: READY 0→1, OK-TOTAL/NOK-TOTAL latch, SEQUENCE-END (out 10.1)=1
  → drop RUN-SEQUENCE
  → optional: DRIVE-TO-HOMEPOS (9.2) or DRIVE-TO-REFPOS (9.3)
```

**Combination rule**: at most ONE of {RUN-SEQUENCE, DRIVE-TO-HOMEPOS, DRIVE-TO-REFPOS, JOG-FW, JOG-BW} may be 1 simultaneously. Any other combo raises a Kistler alarm.

All command bits are **static-level** (hold, not pulse). Dropping mid-motion aborts.

---

## 6. 200-BYTE FIELDBUS MAP (big-endian, Siemens byte order)

### IN (PLC → maXYmos) — `statDataExchangeSend`
| Byte.Bit | Name | FB Input source |
|---|---|---|
| 0.0 | START | startTL |
| 0.1 | TARE-Y | — |
| 0.2 | ZERO-X | — |
| 0.3 | STEST-X | — |
| 0.4 | STEST-Y | — |
| 0.6 | MASTER-MEAS | — |
| 1.4 | AUTO | aux.automaticMode |
| 2.0..2.6 | MP-SELECT | MP+1 (range 1..128) |
| 9.0 | DRIVE-ENABLE | computed from enableBlock+SafetyOK |
| 9.1 | RUN-SEQUENCE | autoRunSequence / move.x1 |
| 9.2 | DRIVE-TO-HOMEPOS | autoHomePosition / move.x2 |
| 9.3 | DRIVE-TO-REFPOS | autoDriveToRef / move.x8 |
| 9.4 | JOG-FW | JogFwd / move.x14 |
| 9.5 | JOG-BW | JogNeq / move.x15 |
| 9.6 | CONTINUE-FROM-WAIT | continuewait / move.x11 |
| 9.7 | MANUAL-BRAKETEST | — |
| 12.0..12.1 | CURRENT-SEQUENCE | selectSequenceSet / selectSequence |
| 14.0..14.7 | CFG-MP | cfgMpNumSet |
| 16.0..16.7 | CFG-ADDRESS | cfgAddressSet |
| 17.0..17.7 | CFG-LENGTH | cfgLengthSet |
| 18.0..18.2 | SELECT-PAGE | selectPageSet |
| 19.0 | SAVE-TO-MP | — |
| 19.1 | STROBE | strobeEnable |
| Bytes 20-23 | JOG-SPEED (Real SWAP) | serverJogSpeedSet |
| Bytes 24-27 | MAX-FORCE (Real SWAP) | serverJogMaxForceSet |

### OUT (maXYmos → PLC) — `statDataExchangeReceive`
| Byte.Bit | Name | FB Output / receive field |
|---|---|---|
| 1.4 | MIRROR-AUTO | — |
| 2.0..2.6 | MIRROR-MP | MeasurementProgramEcho |
| 6.0 | READY | ready, receive.status.x2 |
| 6.1 | OK-TOTAL | okTotal, receive.status.x? |
| 6.2 | NOK-TOTAL | nokTotal |
| 6.7 | ALARM | stateAlarm.alarm |
| 9.1..9.3 etc | MIRROR of IN command bits | receive.status mirrors |
| 9.6 | WAIT-REQUEST | receive.status.x3, waitContinue |
| 9.7 | BRAKETEST-DONE | — |
| 10.0 | SEQUENCE-STOPPED | sequenceStopped |
| 10.1 | SEQUENCE-END | sequenceEnd (FB Out + receive.status.x12) |
| 10.2 | ONLINE-EO-NOK | — |
| 10.5 | DRIVE-ENABLED | receive.status.x1 |
| 10.6 | HOMEPOS-REACHED | homePos, receive.status.x5 |
| 10.7 | REFPOS-REACHED | referencePos, receive.status.x4 |
| 11.1 | BRAKETEST-REQUIRED | — |
| 11.3 | SERVO-ERROR | stateAlarm.driveenabledNOK, receive.status.x11 |
| 11.7 | USER-MODE-ACTIVE | blocks PLC control |
| 12.0..12.1 | CURRENT-SEQUENCE | receive.cfgMpNum (sequence echo) |
| 13.0..13.4 | LABEL | currentLabel (sequence label 0..31) |
| 19.0 | TRANSMISSION-FAULT | stateAlarm.transmissionFault, receive.status.x7 |
| 19.1 | ACK | — |
| 64-bit block | statusAlarmState | detailed alarm bits |

---

## 7. LSicar_KistlerPress FB — FULL ANATOMY

**Version**: v0.0.1 (HMI faceplate session) / v0.0.8 (latest supervision release)  
**Type**: LAD, Optimized, 51 networks  
**Library path**: LSicar → Types_PLC → Drives  
**Interface**: `interfaceHmi: Array[*] of "LDrive_typeKistlerHmi"` (InOut) — accessed as `interfaceHmi[tecUnitNumber]` throughout ALL 51 networks.

### FB Inputs (caller → FB)
- `plantidentifier WString[24]` — shown in alarm texts via `@5%s@`
- `tecUnitNumber Int` — array index for interfaceHmi[] + echoed to HMI
- `hardwareID1/2 HW_IO` — DPRD_DAT/DPWR_DAT hardware IDs
- `smartClientIPAddress String[20]` — DIM/MEM IP for VNC; FB appends `::5900`
- `enableBlock Bool`, `HardwareOK Bool`, `SafetyOK Bool`, `servoNotInstalled Bool`
- `autoRunSequence Bool`, `autoHomePosition Bool`, `JogFwd Bool`, `JogNeq Bool` [sic], `continuewait Bool`
- `OpModeUserInterfaceOut: LSicar_typeOpmodeOut` — opmodeArea, controlNoHmi, opmodeStatus.manualActive/singleStepActive/automaticMode...
- `selectSequence Byte`, `mpNumber Byte`, `cfgAdd Byte`, `CfgLentgh Byte`, `SelectPageNumber Byte`

### FB Outputs (FB → caller)
- `ready`, `okTotal`, `nokTotal`, `noPass`, `homePos`, `referencePos`, `standstill`, `sequenceRunning`, `sequenceStopped`, `waitContinue`, `AutomaticActive`, `GeneralAlarm` (Bool)
- `pvCurrentValueX/Y Real` (displacement mm / force N)
- `pvCurveXminX / XmaxX / YminY / YmaxY Real` (curve window bounds)
- `customeProcessValues: LDrive_typeKistlerProcessValues` (pv1Force, pv2Distance, pv3Gradient, pv4Nopass, pv5Unibox, pv6Envelope, pv7..10 Real/Byte)
- `MeasurementProgramEcho DInt`
- `currentLabel Byte`

---

## 8. LDrive_typeKistlerHmi UDT — DEPRECATED, see §19

**DO NOT USE THIS SECTION as a reference.** It contains unverified-against-FB-source guesses from an earlier probe session. §19 is the only authoritative bit map (extracted from `LSicar_KistlerPress.xml` FB networks 40/43/48/49 + the per-bit move networks via `extract_bit_map.py`).

This section is preserved only for archival reference. **All HMI binding work must use §19.**

### CRITICAL ARCHITECTURE RULE (still correct)
The ENTIRE `send` struct is **FB writes → HMI reads (feedback/echo)**.  
It mirrors what was actually transmitted to Kistler each scan (statDataExchangeSend).  
The HMI does NOT command via the send struct. Do not write to it from HMI.

**Actual HMI command bus**: `move Word` bits + top-level `*Set` fields + `manualSelectMpNum`.

---

### ROOT FIELDS — `state` (DWord) [network ~line 16241, "HMI state Mapping"]
FB writes → HMI reads. PLC internal state machine. NOT Kistler fieldbus status.
| Bit | Source |
|---|---|
| x0 | aux.automaticMode |
| x1 | OpModeUserInterfaceOut.opmodeStatus.singleStepActive |
| x2 | SafetyOK (FB Input) |
| x3–x7 | RCoil → always 0 |
| x8 | aux.generalAlarm |
| x9–x16 | RCoil → always 0 |
| x17 | statDataExchangeSend.systemFixed.strobe |
| x18 | autoRunSequence (FB Input) |
| x19 | autoHomePosition (FB Input) |
| x20 | RCoil → always 0 |
| x21 | interfaceHmi[n].select (reflects back) |
| x22 | enableRunSequence |
| x23 | enablehomePos |
| x24 | statDataExchangeSend.systemFixed.JogFW |
| x25 | statDataExchangeSend.systemFixed.JogBW |
| x26 | enableBlock |
| x27 | HardwareOK |
| x28 | statDataExchangeSend.systemFixed.RunSequence |
| x29 | statDataExchangeSend.systemFixed.DriveToHomePos |
| x30 | statDataExchangeSend.systemFixed.DriveToRefPos |
| x31 | statDataExchangeSend.systemFixed.AckAdmin |
Faceplate use: diagnostic panel only. Do NOT use for primary press status LEDs.

---

### ROOT FIELDS — `move` (Word) — HMI writes → FB reads — PRIMARY COMMAND BUS
| Bit | FB Network line | Action |
|---|---|---|
| x0 | ~3620 | NOT x0 → aux.remoteControl (0=remote ON, 1=remote OFF) |
| x1 | ~5100, ~6879, ~8062 | RunSequence in manual; ContinueFromWait gate; alt JogFW |
| x2 | ~7494 | DriveToHomePos (manual + remote) |
| x8 | ~7797 | DriveToRefPos (manual + remote) |
| x9 | ~3117 | AckAdmin — RCoil resets ALL stateAlarm bits |
| x10 | ~6879 | ContinueFromWait gate condition |
| x11 | ~6879, ~8062 | ContinueFromWait gate; alt JogFW |
| x13 | ~4230 | (x13 AND manualActive AND remoteControl AND x10) → manualDataStrobe |
| x14 | ~8062 | JogFW (OR with FB Input JogFwd) |
| x15 | ~8246 | JogBW (OR with FB Input JogNeq) |
| x3–x7, x12, x16+ | — | Unused/reserved |

---

### ROOT FIELDS — `alarm` (DWord) [network line 14403]
FB writes → HMI reads. No gating — always updated, direct powerrail to coil.
| Bit | stateAlarm member | Real alarm? |
|---|---|---|
| x0 | spare0 | No |
| x1 | hardwareNOK | YES |
| x2 | transmissionFault | YES |
| x3 | driveenabledNOK | YES |
| x4 | enableRunSequence | No (internal state) |
| x5 | enableHomePos | No (internal state) |
| x6 | timerMonitorRunSequence | YES |
| x7 | timerMonitorHomePos | YES |
| x8 | timerMonitorReferencePos | YES |
| x9 | noContinueWaitCommand | YES |
| x10 | alarm (general) | YES |
| x11 | spare11 | No |
| x12 | smesActive | No (SM state) |
| x13 | safetyNOK | YES |
| x14 | smst2active | No (SM state) |
| x15 | smm1active | No (SM state) |
| x16 | remoteControlNotActive | YES |
| x17 | serialnumbermismatch | YES |
Faceplate alarm LEDs: x1, x2, x3, x13, x16, x17.

---

### ROOT FIELDS — `stateColour` (SInt) [network ~line 15824, "Assign PLC Alarm Text List"]
FB writes → HMI reads. Conditional MOVEs, last rung wins (bottom = highest priority):
| Value | Condition | Priority |
|---|---|---|
| 1 | aux.automaticMode | lowest |
| 2 | opmodeStatus.manualActive | |
| 3 | opmodeStatus.singleStepActive | |
| 4 | NOT auto AND NOT manual AND NOT singleStep | |
| 5 | aux.generalAlarm | overrides mode |
| 6 | NOT enableBlock | overrides 1–5 |
| 8 | NOT SafetyOK | highest |
Faceplate: use for header/border color.

---

### ROOT FIELDS — `plantidentifier` (WString[24]) [network ~line 18395]
FB writes → HMI reads. Source: plantidentifier FB Input via S_MOVE. HMI reads for title bar.

### ROOT FIELDS — HMI command inputs (HMI writes → FB reads → fieldbus)
[networks ~line 3890, gated by aux.manualMode]
| HMI field | Fieldbus destination |
|---|---|
| `manualSelectMpNum` (Byte) | statDataExchangeSend.systemFixed.MP |
| `cfgMpNumSet` (Byte) | statDataExchangeSend.systemFixed.Cfg_MP |
| `cfgAddressSet` (Byte) | statDataExchangeSend.systemFixed.CFG_ADR |
| `cfgLengthSet` (Byte) | statDataExchangeSend.systemFixed.CFG_Length |
| `selectPageSet` (Byte) | statDataExchangeSend.systemFixed.SelectedPage |
| `selectSequenceSet` (Byte) [~6579] | statDataExchangeSend.systemFixed.SelectSequence |
| `serverJogSpeedSet` (Real) [line 8432, SCL] | SWAP(REAL_TO_DWORD) → userDefinedOutData bytes 20-23 |
| `serverJogMaxForceSet` (Real) [~line 8618] | same encoding → bytes 24-27 |

### ROOT FIELDS — metadata (FB writes → HMI reads)
| Field | Source | Network |
|---|---|---|
| `currentLabel` (Byte) | statDataExchangeReceive.systemFixed.Current_Label | ~9630 |
| `sequenceEnd` (Bool) | aux.sequenceEnd | ~6009 |
| `hmiControlNo` (Int) | OpModeUserInterfaceOut.controlNoHmi | ~18380 |
| `opmodearea` (USInt) | OpModeUserInterfaceOut.opmodeArea | ~18360 |
| `tecUnitNumber` (Int) | FB static tecUnitNumber | ~18413 |
| `ipAddressplant` (String) | CONCAT(smartClientIPAddress, '::5900') | ~18538 |

### ROOT FIELDS — other
| Field | Direction | Notes |
|---|---|---|
| `select` (Bool) | HMI→FB | Generic confirm; state.x21 reflects back |
| `hmiSelectWord` (Word) | UNUSED | Present in UDT, no FB network writes/reads it |
| `codeViewCondControl.advanceConditions` (Bool) | HMI→FB | Step fwd through diagnostic view [~17955] |
| `codeViewCondControl.reverseConditions` (Bool) | HMI→FB | Step back |
| `codeViewCondControl.condiitonsFilter` (WString[48]) | HMI→FB | ⚠️ UDT typo: double 'i' |

---

### RECEIVE STRUCT — ALL FB writes → HMI reads [network line 18638]
Source: statDataExchangeReceive.systemFixed (decoded 200-byte fieldbus OUT from Kistler).
**Use receive.status for all primary press status LEDs — NOT the `state` DWord.**

#### `receive.status` (DWord) bit map
| Bit | Kistler source | Meaning |
|---|---|---|
| x0 | Auto | Kistler in automatic mode |
| x1 | DriveEnabled AND NOT servoNotInstalled | Drive enabled |
| x2 | Ready | Press ready for cycle |
| x3 | WaitRequest | Waiting for ContinueFromWait |
| x4 | RefPosReached | At reference position |
| x5 | HomePosReached | At home position |
| x6 | Standstill | Press stationary |
| x7 | TransmissionFault | Fieldbus error from Kistler |
| x8 | OkTotal | Measurement passed |
| x9 | NOkTotal | Measurement failed |
| x10 | Alarm | Kistler alarm |
| x11 | ServoError | Servo/drive error |
| x12 | SequenceEnd | Sequence completed |
| x13 | SMES_Active | Safety module active |
| x14 | SMST2_Active | SM ST2 active |
| x15 | SMM1_Active | SM M1 active |

#### Other receive fields
| Field | Source | Notes |
|---|---|---|
| `receive.mpNum` (Byte) | statDataExchangeReceive.systemFixed.MP | Current MP from device |
| `receive.cfgMpNum` (Byte) | .Cfg_MP | |
| `receive.cfgAddress` (Byte) | .CFG_ADR | |
| `receive.cfgLength` (Byte) | fieldbus | |
| `receive.selectPage` (Byte) | .SelectedPage | |
| `receive.selectSequence` (Byte) | **UNUSED — never written** | Reserved |
| `receive.PVcurrentValueX` (Real) | pvCurrentValueX [~17227] | Displacement mm |
| `receive.PVcurrentValueY` (Real) | pvCurrentValueY [~17227] | Force N |
| `receive.PVcurrentXmin-X` (Real) | pvCurveXminX | Curve X min |
| `receive.PVcurrentXmax-X` (Real) | pvCurveXmaxX | Curve X max |
| `receive.PVcurrentYmin-Y` (Real) | pvCurveYminY | Curve Y min |
| `receive.PVcurrentYmax-Y` (Real) | pvCurveYmaxY | Curve Y max |
| `receive.serverJogSpeed` (Real) | **UNUSED — never written** | Reserved |
| `receive.serverJogMaxForce` (Real) | **UNUSED — never written** | Reserved |
| `receive.PV_EO1_Force` (Real) [ExternalVisible=false] | customeProcessValues.pv1Force | |
| `receive.PV_EO2_Distance` (Real) [ExternalVisible=false] | pv2Distance | |
| `receive.PV_EO3_Gradient` (Real) [ExternalVisible=false] | pv3Gradient | |
| `receive.PV_Real_EO7..10` (Real ×4) | pv7..10Real | |
| `receive.PV_E04_Nopass` (Byte) | pv4Nopass | EO NO-PASS result |
| `receive.PV_E05_Unibox` (Byte) | pv5Unibox | EO UNI-BOX result |
| `receive.PV_E06_Envelope` (Byte) | pv6Envelope | EO ENVELOPE result |
| `receive.PV_Byte_E07..10` (Byte ×4) | pv7..10Byte | |

---

### SEND STRUCT — ALL FB writes → HMI reads (echo of what was sent to fieldbus)
[network line 19480. FB copies statDataExchangeSend back each scan.]
| send field | Echoes FROM |
|---|---|
| send.control x0 | statDataExchangeSend.systemFixed.Auto |
| send.control x1 | statDataExchangeSend.systemFixed.DriveEnable |
| send.control x2 | statDataExchangeSend.systemFixed.RunSequence |
| send.control x3 | statDataExchangeSend.systemFixed.DriveToHomePos |
| send.control x4 | statDataExchangeSend.systemFixed.DriveToRefPos |
| send.control x5 | statDataExchangeSend.systemFixed.JogFW |
| send.control x6 | statDataExchangeSend.systemFixed.JogBW |
| send.control x7 | statDataExchangeSend.systemFixed.ContinueFromWait |
| send.control x8 | statDataExchangeSend.systemFixed.strobe |
| send.control x9 | statDataExchangeSend.systemFixed.AckAdmin |
| send.mpNum | statDataExchangeSend.systemFixed.MP |
| send.cfgMpNum | statDataExchangeSend.systemFixed.Cfg_MP |
| send.cfgAddress | statDataExchangeSend.systemFixed.CFG_ADR |
| send.cfgLength | statDataExchangeSend.systemFixed.CFG_Length |
| send.selectPage | statDataExchangeSend.systemFixed.SelectedPage |
| send.selectSeqeunce [sic] | statDataExchangeSend.systemFixed.SelectSequence |
| send.serverJogSpeed | serverJogSpeedSet (top-level field) |
| send.serverJogMaxForce | serverJogMaxForceSet (top-level field) |
Faceplate: read these to confirm commands are actually active on fieldbus.

### UDT TYPOS (exact names in TIA Portal — do not correct)
- `send.selectSeqeunce` (not selectSequence)
- `codeViewCondControl.condiitonsFilter` (double 'i')

---

## 9. FACEPLATE BINDING SUMMARY

| Faceplate element | Bind to | R/W |
|---|---|---|
| Ready/OkTotal/NOkTotal/DriveEnabled LEDs | `receive.status` bit extract | R |
| HomePos/RefPos/Standstill/SequenceEnd/WaitRequest | `receive.status.x5/x4/x6/x12/x3` | R |
| Kistler alarm: TransmissionFault, ServoError | `receive.status.x7/x11` | R |
| HW fault/safety/serial/remote LEDs | `alarm.x1/x2/x3/x13/x16/x17` | R |
| Sequence timeout alarms | `alarm.x6/x7/x8` | R |
| Force gauge | `receive.PVcurrentValueY` | R |
| Displacement gauge | `receive.PVcurrentValueX` | R |
| Gradient display | `receive.PV_EO3_Gradient` | R |
| F-D curve points | `receive.PVcurrentValueX` + `receive.PVcurrentValueY` | R |
| Curve axis bounds | `receive.PVcurrentXmin-X/Xmax-X/Ymin-Y/Ymax-Y` | R |
| EO pass/fail bytes | `receive.PV_E04_Nopass/E05_Unibox/E06_Envelope` | R |
| Current MP# | `receive.mpNum` | R |
| Current page | `receive.selectPage` | R |
| Sequence step label | `currentLabel` | R |
| Sequence complete flag | `sequenceEnd` | R |
| Command echo (what's active on fieldbus) | `send.control` bits + `send.*` | R |
| Faceplate border/header colour | `stateColour` | R |
| PLC mode indicators (auto/singleStep/safety/alarm) | `state.x0/x1/x2/x8` | R |
| Plant name title | `plantidentifier` | R |
| VNC Smart Client address | `ipAddressplant` | R |
| JogFW button | `move.x14` | W |
| JogBW button | `move.x15` | W |
| Home button | `move.x2` | W |
| Reference button | `move.x8` | W |
| AckAdmin button | `move.x9` | W |
| Remote enable toggle | `move.x0` (0=remote ON) | W |
| Run sequence (manual) | `move.x1` | W |
| ContinueFromWait | `move.x11` (+ x10 gate) | W |
| MP selection | `manualSelectMpNum` | W |
| Page selection | `selectPageSet` | W |
| Sequence selection | `selectSequenceSet` | W |
| Jog speed | `serverJogSpeedSet` | W |
| Max force | `serverJogMaxForceSet` | W |
| Cfg MP/Address/Length | `cfgMpNumSet/cfgAddressSet/cfgLengthSet` | W |
| Generic select/confirm | `select` | W |

---

## 10. SUPERVISION BIBLE (v0.0.8 — released)

Script: `add-kistler-supervisions.ps1`. Output: `LSicar_KistlerPress_with_supervisions.xml`.

### SubCategory2 = 7 (Drive) for all supervisions.
### Design: inline text (no text list), conditions on all except safety/SMES/enableBlock.
### ProDiag AV offset: `@4=AV#1`, `@5=AV#2`, `@6=AV#3`

#### Alarms (Cat=1, Sub1=2, Sub2=7)
| # | Operand | Conditions | Text |
|---|---|---|---|
| 6 | `stateAlarm.hardwareNOK` | enableBlock=T, hideAlarmPD=F | `@5%s@: Hardware fault` |
| 8 | `stateAlarm.safetyNOK` | **none — always fires** | `@5%s@: Safety circuit open` |
| 9 | `stateAlarm.driveenabledNOK` | enableBlock=T, hideAlarmPD=F | `@5%s@: Drive not enabled` |
| 10 | `stateAlarm.transmissionFault` | enableBlock=T, hideAlarmPD=F | `@5%s@: Kistler comm fault` |
| 12 | `stateAlarm.timerMonitorRunSequence` | enableBlock=T, hideAlarmPD=F | `@5%s@: Press cycle timeout` |
| 18 | `stateAlarm.alarm` | enableBlock=T, hideAlarmPD=F | `@5%s@: Kistler alarm active` |

#### Warnings (Cat=2, Sub2=7)
| # | Operand | Conditions | Text |
|---|---|---|---|
| 20 | `enableBlock=false` | none | `@5%s@: Block disabled` |
| 22 | `aux.plantIdentifierEmpty` | enableBlock=T | `@5%s@: Plant ID not configured` |
| 24 | `stateAlarm.serialnumbermismatch` | enableBlock=T | `@5%s@: Serial number mismatch` |
| 26 | `stateAlarm.remoteControlNotActive` | enableBlock=T | `@5%s@: Remote control inactive` |
| 27 | `stateAlarm.noContinueWaitCommand` | enableBlock=T | `@5%s@: Waiting for continue command` |
| 32 | `stateAlarm.smesActive` | **none — always visible** | `@5%s@: Safety mode active (SMES)` |

#### MessageErrors (Cat=1, Sub1=1, Sub2=7)
| # | AV#1 | Conditions | Text |
|---|---|---|---|
| 36 | `statAlarmNoPD` | hideAlarmPD=F, alarmPdNoChange=T | `@5%s@: Kistler device alarm` |
| 38 | `statInternalAlarmNoPD` | hideAlarmPD=F, internalAlarmPdNoChange=T | `@5%s@: Kistler device alarm` |

### Key static members
- `plantidentifier WString[24]` — alarm text via `@5%s@`
- `statHideAlarmMessagesPD Bool` — alarm suppression gate
- `enableBlock Bool` — block enable gate
- `Warning_No_PD Array[1..12] of Int` — ProDiag slot tracking
- `statAlarmNoPD Int` / `statInternalAlarmNoPD Int` — AV#1 for MessageErrors
- `aux.alarmPdNoChange Bool` / `aux.internalAlarmPdNoChange Bool` — no-change guards
- `aux.plantIdentifierEmpty Bool` — set in SCL: `aux.plantIdentifierEmpty := (plantidentifier = WSTRING#'');`

### Alarm Text List API Limitation
`PlcAlarmUserTextlists.Count = 0` via Openness API in SICAR multiuser projects — both `.amc20` and `.ap20` modes. **Workaround: always use inline text** (as done in v0.0.8). `ImportFromXlsx` also fails (version check embedded in xlsx is unknown format — do not attempt).

---

## 11. SVGHMI FACEPLATE FILE

**File**: `C:\Users\MudasserWahab\Claude Code\LSicar_KistlerPressFp.svghmi`  
**Format**: WinCC Unified native SVGHMI  
**DOCTYPE**: `<!DOCTYPE svg PUBLIC "-//SIEMENS//DTD SVG 1.0 TIA-HMI//EN" "http://tia.siemens.com/graphics/svg/1.8/dtd/svg18-hmi.dtd">`  
**Binding prefix**: `hmi-bind:` attributes, `{{ParamProps.x}}` expressions  
**Parameter declarations**: `<hmi:self>` block  
**Visual preview SVG**: `C:\Users\MudasserWahab\Claude Code\kistler_faceplate.svg` (static, 900×660px, dark industrial)

### 30 Interface Parameters

**Inputs (FB→HMI reads)**:
`receiveStatus` (Integer/DWord), `state` (Integer/DWord), `alarm` (Integer/DWord), `stateColour` (Integer), `plantidentifier` (String), `pvForceY` (Float), `pvDispX` (Float), `pvGradient` (Float), `pvXmin/Xmax/Ymin/Ymax` (Float×4), `sendControl` (Integer — feedback), `sendMpNum/Seq/Page` (Integer×3 — feedback), `rxMpNum` (Integer), `currentLabel` (Integer), `sequenceEnd` (Boolean), `opmodearea` (Integer), `hmiControlNo` (Integer), `tecUnitNumber` (Integer)

**Outputs (HMI→FB)**:
`cmdMove` (Integer/Word), `jogSpeedSet` (Float), `maxForceSet` (Float), `mpNumSet` (Integer), `seqSet` (Integer), `pageSet` (Integer)

### hmi-bind expression examples
```xml
<!-- Status LED: READY -->
<circle hmi-bind:fill="{{(ParamProps.receiveStatus & 4) ? '#4ade80' : '#374151'}}"/>
<!-- safetyNOK alarm LED -->
<circle hmi-bind:fill="{{(ParamProps.alarm & 8192) ? '#f87171' : '#374151'}}"/>
<!-- State colour header -->
hmi-bind:fill="{{ParamProps.stateColour==1?'#4ade80':ParamProps.stateColour==2?'#60a5fa':ParamProps.stateColour==5?'#f87171':'#6b7280'}}"
```

---

## 12. TIA PROJECT STRUCTURE

**Project**: `ST110_210_MVLV_Press_LS_6` (`.als20` multiuser), PID 18684  
**Access**: `([Siemens.Engineering.TiaPortal]::GetProcesses())[0].Attach()` → `LocalSessions[0].Project`

**WinCC Unified HMI devices**:
- `+TOOL01-HMI01 / HMI_RT_2` → `Siemens.Engineering.HmiUnified.HmiSoftware`
- `+TOOL02-HMI01 / HMI_RT_1` → `Siemens.Engineering.HmiUnified.HmiSoftware`

**Project Library — faceplate target**:
`ProjectLibrary → TypeFolder → LSicar → Types_HMI → Drives` (currently EMPTY — 0 types)

**Kistler MasterCopy folder**:
`ProjectLibrary → LSicar → MasterCopies → Drives → KistlerPress` (18 entries)

---

## 13. TIA PORTAL OPENNESS API LIMITS FOR WinCC UNIFIED

**OBSOLETE — see section 14. Most claims here were wrong, verified live 2026-05-09.**

What's still true: SVGHMI Screen Type *import via XML* is unverified (no working sample to reverse-engineer the schema; `Version.ExportAsDocuments` returns Warning with no files). What was *wrong*: HmiSoftware DOES expose `Screens.Create()`, `ScreenItems.Create<T>()`, `Dynamizations.Create()`, etc. — full programmatic screen build is achievable.

### SVGHMIC tool (alternative approach found)
https://github.com/mrwan84/SVGHMIC — browser-based SVG→SVGHMI converter for WinCC Unified.

---

## 14. WORKING OPENNESS PATTERN — VERIFIED 2026-05-09

End-to-end verified: programmatic build of a fully-bound Kistler press screen on `+TOOL01-HMI01 / HMI_RT_2` in project `ST110_210_MVLV_Press`. Compiles clean, 0 errors, 0 warnings.

### Attach pattern (multiuser .als20)
```powershell
[System.Reflection.Assembly]::LoadFrom("C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll") | Out-Null
$tia     = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal  = $tia.Attach()
$session = $portal.LocalSessions[0]    # multiuser
$project = $session.Project
# Save: $session.Save()  — NOT $project.Save()
```

### Find HmiUnified software (recursive walk + reflected GetService<T>)
```powershell
$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
function Get-Sw($di) { $m = $di.GetType().GetMethod('GetService').MakeGenericMethod($swT); $m.Invoke($di,$null) }
# Walk DeviceItems recursively, check $svc.Software.GetType().FullName -match 'HmiUnified'
```

### Type lookup (HmiUnified types live in `UI.Shapes`/`UI.Widgets`, NOT `ModernUI`)
```powershell
function Get-HmiType($fn) { foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { try { $t=$a.GetType($fn,$false); if ($t) { return $t } } catch {} } }
```
Verified types:
- `Siemens.Engineering.HmiUnified.UI.Shapes.{HmiRectangle, HmiText, HmiCircle, HmiLine, HmiGraphicView}`
- `Siemens.Engineering.HmiUnified.UI.Widgets.{HmiButton, HmiIOField, HmiGauge, HmiBar}`
- `Siemens.Engineering.HmiUnified.UI.Dynamization.{TagDynamization, ExpressionDynamization, Script.ScriptDynamization}`
- `Siemens.Engineering.HmiUnified.UI.Enum.HmiButtonEventType` (None/Activated/Deactivated/Tapped/Down/Up/KeyDown/KeyUp/ContextTapped)

### Screen + items
```powershell
$screen = $hmiSw.Screens.Create($name)        # 1-arg works
$screen.Width  = [uint32]1920                  # MUST cast [uint32]
$screen.Height = [uint32]1080
# ScreenItems.Create<T> — generic, must invoke via reflection (1-arg overload)
$createGen = $screen.ScreenItems.GetType().GetMethods() | Where { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } | Select -First 1
$item = $createGen.MakeGenericMethod($t).Invoke($screen.ScreenItems, @($name))
```

### Item placement quirks
- `HmiRectangle/Text/IO/Button/Line` → `Left`, `Top`, `Width`(uint32), `Height`(uint32)
- `HmiCircle` → `CenterX`, `CenterY`, `Radius`(uint32)  — NOT Left/Top/Width/Height
- `HmiLine` → `Point1.X/Y`, `Point2.X/Y`

### MultilingualText (Text, ToolTipText)
```powershell
$mlt = $item.Text
foreach ($mli in $mlt.Items) { $mli.SetAttribute('Text', "<body><p>$plain</p></body>") }
# Plain string fails: "argument 'text' has invalid format"
```

### Tag binding (90% of cases — the simple path)
```powershell
$tagDynT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'
$cg = $item.Dynamizations.GetType().GetMethods() | Where { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select -First 1
$dyn = $cg.MakeGenericMethod($tagDynT).Invoke($item.Dynamizations, @($propertyName))
$dyn.SetAttribute('Tag', 'MVterminalPressKistler.receive.PVcurrentValueY')   # full path into structured tag
```
- Path uses `.` traversal into structured HMI tag of type `LDrive_typeKistlerHmi`.
- Field names with hyphens (`PVcurrentXmin-X`) work as-is — DO NOT wrap in quotes.

### Bit extraction — DOES NOT WORK via TagDynamization path
All 7 syntaxes rejected at compile (`The tag 'X' does not exist`):
- `.%X<n>`, `.X<n>`, `.x<n>`, `[<n>]`, `.bit<n>`, `.Bit<n>`, `.<n>`

ExpressionDynamization (`ValueConverter.Formula = "Tags(...).x & mask"`) compiles clean BUT formula doesn't render in TIA UI editor (`IsFormulaSelected=True` set, but UI shows binding-type=Expression with empty body). Compile is permissive — formula content not validated. Need ScriptDynamization (different shape: `ScriptCode` + `Trigger.Tags` + `Trigger.Type`) — not yet wired up.

**Workaround used**: bind LED `BackColor` / button highlight to whole DWord field (`receive.status`, `alarm`, `state`, `send.control`). Visual not bit-correct but binding is valid and tag-pure. Bit-display can be refined in TIA editor's animation/conversion table.

### Multiuser save
- `$project.Save()` → throws `MultiuserProject does not contain Save()`
- `$session.Save()` → works
- `$session.CloseAndCommit("comment")` for full check-in

### HMI compile
HmiSoftware itself has NO `GetService<T>`. Walk up via `.Parent` until you find an object with the generic GetService (typically `Siemens.Engineering.HW.DeviceImpl`):
```powershell
$cur = $hmiSw.Parent
while ($cur -and -not $comp) {
    $gs = $cur.GetType().GetMethods() | Where { $_.Name -eq 'GetService' -and $_.IsGenericMethodDefinition } | Select -First 1
    if ($gs) { try { $comp = $gs.MakeGenericMethod($compT).Invoke($cur, $null) } catch {} }
    $cur = $cur.Parent
}
$result = $comp.Compile()   # CompileProvider.Compile() returns CompileResultMessageComposition
```
Walk `$result.Messages` recursively — sub-messages contain per-item errors. State `Success` requires Errors=0.

### Button click → tag write (JavaScript via EventHandler.Script)
```powershell
$evtT     = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiButtonEventType'
$activated = [Enum]::Parse($evtT, 'Activated')
$ev = $btn.EventHandlers.Create($activated)
$ev.Script.SetAttribute('ScriptCode', @'
var v = Tags("MVterminalPressKistler.move").Read();
Tags("MVterminalPressKistler.move").Write(v | 2);
'@)
```
- Script is `ScriptDynamization` with attributes: `ScriptCode`, `GlobalDefinitionAreaScriptCode`, `Async`, `Trigger`
- WinCC Unified runtime API: `Tags("path.to.field").Read()` / `.Write(value)`
- Per Kistler memory section 5: command bits are **static-level**. Pattern: `Activated` sets bit, `Deactivated` clears bit. Exception: `AckAdmin` (RCoil) and `Remote` (toggle via `Tapped`+XOR).

### Faceplate (Screen Type / LibraryType) — STILL OPEN
- `TypeFolder.Types.CreateFromDocuments(DirectoryInfo, fileNameWithoutExt, LibraryImportOptions)` exists, returns `TypeCreateTransferResults`. Untested — no working schema sample.
- `LibraryTypeVersion.ExportAsDocuments(...)` returns `TransferResultState=Warning` with empty `ExportedDocuments` — does NOT export faceplates as files in V20. Cannot reverse-engineer schema this way.
- `LibraryTypeVersion.Export(FileInfo, ExportOptions)` writes only metadata XML (3 KB, no faceplate body, no params, no SVG).
- `GetSupportedExportFormats()` returns empty for our LibraryTypes.
- **Conclusion**: faceplate import via Openness is theoretically possible but blocked by lack of schema. Not pursued in this session.

---

## 15. SESSION CHECKPOINT — 2026-05-09 (historical, superseded by §18)

### Live state in TIA
- Project: `ST110_210_MVLV_Press` (multiuser .als20, PID via GetProcesses)
- HMI: `+TOOL01-HMI01 / HMI_RT_2` (HmiUnified)
- Screen: **`_Kistler_Press_01`** — 131 items, 50 TagDynamizations, 15 EventHandlers, compiles clean
- Bound to: HMI tag `MVterminalPressKistler` (DataType=`LDrive_typeKistlerHmi`) at `_SICAR_HMI-tags → Tec_Units → Opmode1 → Station1`, `PlcTag="MVTermPressParameter&HMIIF".MVTermPressHMIInterface[0]`

### Scripts in `C:\Users\MudasserWahab\Claude Code\` (working set)
| Script | Purpose |
|---|---|
| `build-kistler-tags-only.ps1` | Build screen with all 50 TagDynamizations + compile |
| `add-button-events.ps1` | Add 15 click handlers (8 buttons) writing to `.move` bits |
| `dump-bindings.ps1` | List every dynamization on the screen |
| `compile-hmi.ps1` | Standalone compile + flat error report |
| `probe-hmi-min.ps1` / `probe-hmi-deep.ps1` | API discovery — keep for reference |
| `LSicar_KistlerPressFp.svghmi` v2.0.0 | Standalone SVGHMI faceplate (corrected bit map) — for future faceplate work |

### What's working
1. Visual layout: 131 items (header, 12 status LEDs, 8 alarm LEDs, F-D area, 3 PV gauges, 8 buttons, 2 setpoints, 3 program selects, echo bar, footer)
2. Tag bindings: 50/50 — process values, setpoints, MP/seq/page, plant ID, tecUnit, stateColour, echo fields, sequenceEnd
3. Button click→tag write: 15 handlers, JavaScript bodies, set/clear `.move` bits per UDT spec

### What's NOT done (for tomorrow)
1. **Bit-level LED display** — LEDs currently bound to whole DWord (`receive.status`, `alarm`, etc.). Need ScriptDynamization with proper Trigger.Tags + ScriptCode that returns Boolean per bit, OR a manual TIA-UI conversion table per LED.
2. **Button echo highlight** — currently bound to whole `send.control` DWord; same bit-extraction problem as LEDs.
3. **Runtime validation** — script bodies (`Tags(...).Read()/.Write()`) compile clean but runtime correctness unverified. Need to download/run and confirm bits actually toggle.
4. **Faceplate (Screen Type) approach** — deferred. Current approach: regular reusable screen via build script per tecUnit instance.
5. **Per-tecUnit instantiation** — script currently hardcodes `MVterminalPressKistler` (Station1, tecUnit[0]). Need parameterization for Station2/3/4 + their respective root tags.
6. **Color/styling pass** — all items use TIA defaults. Faceplate v2.0.0 SVGHMI has the dark-industrial color scheme; could be ported.

### Key gotchas (don't re-discover)
- `[uint32]` cast on Width/Height — int32 throws.
- HmiCircle uses CenterX/CenterY/Radius — not Left/Top/Width/Height. Use a `Place-Item` helper with type detection.
- MultilingualText: `<body><p>...</p></body>` XML wrap mandatory.
- Quotes around field names: `receive."PVcurrentValueY"` rejected at compile. Use `receive.PVcurrentValueY` plain.
- Bit access via Tag-path syntax: NOT supported. Use ScriptDynamization or whole-DWord binding.
- Multiuser: `$session.Save()` not `$project.Save()`.
- Compile: walk Parent until you find an object with `GetService<T>`; HmiSoftware itself has none.
- ScreenItem name uniqueness: `$b.Name -replace '\W',''` collides on `JOG +`/`JOG -` → `JOG`. Use explicit `Id` field.

---

## 16. Bit extraction via MappingTable — verified 2026-05-11

The TIA UI's bit-extraction radio buttons (None / Range / Multiple bits / Single bit) map to `TagDynamization.ValueConverter.MappingTable.ConditionType`. **Use this. Not the Formula field, not an ExpressionDynamization.**

### ConditionType enum values
```
None, Range, Bitmask, Singlebit, Expression
```
| Enum value | TIA UI radio label | Schema |
|---|---|---|
| `None` | None | direct tag→property (no mapping) |
| `Range` | Range | from/to numeric thresholds |
| `Bitmask` | **Multiple bits** | one row per bit, `BitDynamizationType=MultiBit` |
| `Singlebit` | **Single bit** | exactly 2 rows (off/on), `BitDynamizationType=SingleBit` |
| `Expression` | (Formula-only mode) | uses ValueConverter.Formula |

**`Bitmask` ≠ "Single bit" — easy to confuse.** UI label is misleading. Use `Singlebit` for the single-bit radio.

### Pattern: Single bit extraction (the canonical LED pattern)
```powershell
$ctT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.Tag.ConditionType'
$Singlebit = [Enum]::Parse($ctT, 'Singlebit')

$mt = $dyn.ValueConverter.MappingTable
# clear existing
foreach ($e in @($mt.Entries)) { try { $e.Delete() } catch {} }
# set CT — this AUTO-CREATES 2 entries (off + on); DO NOT call Entries.Create()
$mt.SetAttribute('ConditionType', $Singlebit)
$entries = @($mt.Entries)   # exactly 2

# Configure: Entry[1] is on-state. Set Condition to 2^bit (UInt64).
# Relevant auto-syncs from Condition. Value is the color.
$entries[1].Condition = [UInt64]([Math]::Pow(2, $bit))
$entries[0].Value = $offColor        # off-state color (e.g. Gray)
$entries[1].Value = $onColor         # on-state  color (e.g. Light green)
```

### Pattern: Multiple bits (one row per bit on the same tag)
```powershell
$Bitmask = [Enum]::Parse($ctT, 'Bitmask')
$bdtT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.Tag.BitDynamizationType'
$MultiBit = [Enum]::Parse($bdtT, 'MultiBit')

$mt.SetAttribute('ConditionType', $Bitmask)
# add N entries via Entries.Create(MultiBit), one per bit
$mt.Entries.Create($MultiBit)  # returns IList`1, count=1 each call
# set per entry: $entry.Condition = [UInt64](bit position), Value, AlternateValue, Flashing, FlashingRate
```

### Entry attribute access modes (MappingTableEntryBitmask)
| Attribute | Type | Access |
|---|---|---|
| `Condition` | UInt64 | **ReadWrite** — needs `[UInt64]` cast, int rejected |
| `Relevant` | UInt64 | **Read-only** — auto-syncs from Condition |
| `Value` | Color | ReadWrite — on-state color |
| `AlternateValue` | Color | ReadWrite — defaults to Red, used in Range/Expression modes |
| `Flashing` | Boolean | ReadWrite |
| `FlashingRate` | FlashingRate enum | ReadWrite — Slow/Medium/Fast |
| `BitDynamizationType` | enum | Read-only — set at entry creation |

### TagDynamization Formula DSL — NOT useful for bit extraction
- Probed live: it's the WinCC "Direct Connection" formula language, NOT JavaScript
- All variable identifiers rejected: `value`, `Tag`, `X`, `Source`, `this`, `self` — all `ERR201 Undefined symbol`
- Bitwise `&` rejected: `Invalid operator "value&4"`
- `AND` / `OR` are LOGICAL operators (reserved), not bitwise
- Bound-tag value reference uses positional `$T1`/`$T2` from a tag list that **cannot be constructed via Openness** (composition not exposed) — formula errors with `Invalid tag.`
- Formula is for scaling/comparison: `$T1 * 0.1 + 5`, `$T1 >= 50`. **Use Type=Singlebit/Bitmask/Range for bit logic and color mapping.**

### ExpressionDynamization formula (separate animal)
Different dynamization class. `ValueConverter.Formula` accepts JS-like expressions like `Tags("name").receive.status & 4` — compile accepts any string (formula content not validated at build time). But **TIA UI editor does not render the formula in the Expressions tab** — the dynamization shows as type=Expression with empty body even though `IsFormulaSelected=True` is set. The proper UI-visible binding for bit extraction is TagDynamization + Type=Singlebit (section 16 pattern above).

---

## 17. SICAR V5.1 Standards reference

Source: `SICAR_Docu_V51.zip` from SICAR Workshop, V5.1 (11/2024). Extracted to `C:\Users\MudasserWahab\Claude Code\sicar_docu\`. Plain-text PDFs under `sicar_text\`.

### Color standard (named, from SICAR_TecUnit_HMI-Objects.pdf §4.3 + §4.5)
Canonical state-color map for `statHmi.stateColour` (SInt) — also used on TecUnit faceplate borders and Moveline elements:

| Value | Named color | State |
|---|---|---|
| 0 | Gray | No PLC connection |
| 1 | Light green | Auto active |
| 2 | Light blue | Manual active |
| 4 | Olive green / Green | Single step active |
| 5/6/9 | (flashing) | preselected modes |
| 10 | Red | Group alarm |
| 11 | Orange/Black flashing | Enable block missing |
| 12 | Light blue/Black flashing | Run without enable |

### Element semantic colors (from same doc §4.5)
- **Light green** = good/active/present/OK
- **Light blue** = manual operation / remote
- **Olive green** = single step
- **Orange** = enable missing / multimovement / operator action needed
- **Red** = alarm / fault / NOK
- **Yellow** = safety violation (`safetyOk` missing)
- **Gray** = inactive / not reached / off
- **White** = unconfigured area
- **Black** = button is pressable in manual mode

### Approximate hex (Siemens-standard Office palette — pending verification against `LSicar_GeneralScripts.ColorStyle()`)
The exact RGB lives in the library script `ColorStyle(name, alpha)` in `LSicar_GeneralScripts` (v5.1.1). **Openness cannot export this library type** — `LibraryTypeVersion.ExportAsDocuments` returns Warning with no files; single-file Export gives metadata only. Currently using these standard values:
| Named | Hex | RGB |
|---|---|---|
| Light green | #92D050 | 146, 208, 80 |
| Light blue | #00B0F0 | 0, 176, 240 |
| Olive green | #00B050 | 0, 176, 80 |
| Orange | #FFC000 | 255, 192, 0 |
| Red | #FF0000 | 255, 0, 0 |
| Yellow | #FFFF00 | 255, 255, 0 |
| Gray (off) | #C8CDD7 | 200, 205, 215 (TIA default neutral) |

If user opens `ColorStyle()` script in TIA UI and reports the literal hex from each `case` branch, swap values in `apply-sicar-colors.ps1`.

### Other SICAR standards documented
Complete summary in `C:\Users\MudasserWahab\Claude Code\SICAR_STANDARDS.md`:
- 9 SICAR Global PDFs (Conventions, WinCC-RT, TecUnit-HMI-Objects, MovelineFaceplates, ProDiag, GraphSequence, SiVArc, AlarmTextLists, User Authentication)
- `statHmi.movement` Word bit map (FwdRev/PosDev — distinct from Kistler `move` bus)
- 18 standard SICAR faceplate types in `Tec_Units` library (DeviceOnOff, DeviceFwdRev, PosDev*, Rb2S*, Lifter, Valve, PartControl, IdentMv/Rf, Estop, ProfinetDevDiag, etc.)
- Naming conventions: `LSicar_*`, `statHmi`, tag table tree `_SICAR_HMI-tags → Tec_Units → Opmode<n> → Station<m>`

---

## 19. `LDrive_typeKistlerHmi` UDT — SINGLE SOURCE OF TRUTH

> **This is the ONLY authoritative UDT reference. Do not derive bit maps from anywhere else (including §8 of this file, the Kistler protocol manual, or my earlier sessions).** All assignments here were extracted from the actual FB source `LSicar_KistlerPress.xml` (Library type v0.0.1) via `extract_bit_map.py`. Re-run that script if the FB changes.

### Full top-level member list (from `LDrive_typeKistlerHmi.xml` UDT export)

| Member | Type | Direction | Purpose |
|---|---|---|---|
| `state` | DWord | FB→HMI | Internal state for diagnostic LEDs (see bit map below) |
| `plantidentifier` | WString[24] | FB→HMI | Plant identifier for alarm text |
| `move` | Word | **HMI→FB** | Command bus — buttons write here |
| `alarm` | DWord | FB→HMI | Alarm bits (see bit map below) |
| `stateColour` | SInt | FB→HMI | TecUnit border color code (0..12 per SICAR §17) |
| `receive` | Struct | FB→HMI | Decoded Kistler protocol IN (see substruct below) |
| `send` | Struct | FB→HMI | Echo of what FB sent OUT this scan |
| `serverJogSpeedSet` | Real | HMI→FB | Setpoint: jog speed (mm/s) |
| `serverJogMaxForceSet` | Real | HMI→FB | Setpoint: max force (N) |
| `cfgMpNumSet` | Byte | HMI→FB | Config: MP number setter |
| `cfgAddressSet` | Byte | HMI→FB | Config: byte address setter |
| `cfgLengthSet` | Byte | HMI→FB | Config: length setter |
| `selectPageSet` | Byte | HMI→FB | Page setpoint (0..7) |
| `selectSequenceSet` | Byte | HMI→FB | Sequence setpoint (0..3) |
| `manualSelectMpNum` | Byte | HMI→FB | Manual MP picker (0..127) |
| `currentLabel` | Byte | FB→HMI | Sequence step label (0..31) |
| `sequenceEnd` | Bool | FB→HMI | Sequence completed |
| `hmiControlNo` | Int | FB→HMI | Controlling client ID |
| `opmodearea` | USInt | FB→HMI | Operation mode area |
| `select` | Bool | HMI→FB | Generic HMI confirm (reflected on state.x21) |
| `hmiSelectWord` | Word | unused | Reserved |
| `tecUnitNumber` | Int | FB→HMI | This unit's index in interfaceHmi array |
| `codeViewCondControl` | Struct | mixed | `advanceConditions` (Bool, HMI→FB), `reverseConditions` (Bool, HMI→FB), `condiitonsFilter` (WString[48], HMI→FB — typo `condiitons` is intentional) |
| `ipAddressplant` | String | FB→HMI | VNC client IP |

### `receive` substruct (FB→HMI, decoded fieldbus IN from Kistler)
| Member | Type | Notes |
|---|---|---|
| `status` | DWord | 16 bits used — see Network 48 table below |
| `mpNum` | Byte | active MP number echo |
| `cfgMpNum` | Byte | config MP echo |
| `cfgAddress` | Byte | config address echo |
| `cfgLength` | Byte | config length echo |
| `selectPage` | Byte | active page echo |
| `selectSequence` | Byte | active sequence echo |
| `PVcurrentValueX` | Real | live displacement (mm) |
| `PVcurrentValueY` | Real | live force (N) |
| `PVcurrentXmin-X` / `PVcurrentXmax-X` | Real | curve X bounds (hyphens are part of field name — do NOT quote when binding) |
| `PVcurrentYmin-Y` / `PVcurrentYmax-Y` | Real | curve Y bounds |
| `serverJogSpeed` / `serverJogMaxForce` | Real | active setpoint echoes |
| `PV_EO1_Force` / `PV_EO2_Distance` / `PV_EO3_Gradient` | Real | first 3 EO outputs |
| `PV_Real_EO7..10` | Real ×4 | additional EO real outputs |
| `PV_E04_Nopass` / `PV_E05_Unibox` / `PV_E06_Envelope` | Byte | EO result bytes |
| `PV_Byte_E07..10` | Byte ×4 | additional EO byte outputs |

### `send` substruct (FB→HMI, echo of fieldbus OUT just sent)
| Member | Type |
|---|---|
| `control` | DWord (10 bits used — see Network 49 table below) |
| `mpNum` / `cfgMpNum` / `cfgAddress` / `cfgLength` / `selectPage` | Byte each |
| `selectSeqeunce` | Byte — **typo intentional** ("Seqeunce" not "Sequence") |
| `serverJogSpeed` / `serverJogMaxForce` | Real |

### Critical architecture rules
1. **`move` is the ONLY HMI-writable bus on this UDT** (plus the explicit `*Set` setters, `manualSelectMpNum`, `select`, and `codeViewCondControl` sub-bits). All other DWords/Words are FB-written, HMI read-only.
2. The `send` struct is **echo only** — it shows what the FB transmitted this scan. The HMI never writes to `send.*`. To make the press do something, write to `move` and the FB will translate it into the appropriate `statDataExchangeSend` action and reflect it on `send.control`.
3. **`state` ≠ `receive.status`.** `state` is the FB's INTERNAL diagnostic bits (built from inputs like `enableBlock`, `SafetyOK`, `aux.automaticMode`). `receive.status` is the DECODED KISTLER PROTOCOL bits coming in from the device. For press operational LEDs (Ready, OK, Standstill, etc.) use `receive.status`. For diagnostic LEDs (SafetyOK, general alarm) use `state`.
4. Kistler protocol byte.bit addresses (e.g. "byte 6.0 = Ready") are **not** the same as `receive.status.x<n>`. The FB owns the translation. Always bind to `receive.status.x<n>` from this section, never to a protocol address.

---

### Source extraction

### Network 48 "Map FIx Receieved Data to HMI" — `interfaceHmi[].receive.status` DWord
| Bit | Direct FB source signal |
|---|---|
| x0 | `statDataExchangeReceive.systemFixed.Auto` |
| x1 | `statDataExchangeReceive.systemFixed.DriveEnabled` AND NOT `servoNotInstalled` |
| **x2** | **`statDataExchangeReceive.systemFixed.Ready`** |
| x3 | `statDataExchangeReceive.systemFixed.WaitRequest` |
| x4 | `statDataExchangeReceive.systemFixed.RefPosReached` |
| x5 | `statDataExchangeReceive.systemFixed.HomePosReached` |
| x6 | `statDataExchangeReceive.systemFixed.Standstill` |
| x7 | `statDataExchangeReceive.systemFixed.TransmissionFault` |
| x8 | `statDataExchangeReceive.systemFixed.OkTotal` |
| x9 | `statDataExchangeReceive.systemFixed.NOkTotal` |
| x10 | `statDataExchangeReceive.systemFixed.Alarm` |
| x11 | `statDataExchangeReceive.systemFixed.ServoError` |
| x12 | `statDataExchangeReceive.systemFixed.SequenceEnd` |
| x13 | `statDataExchangeReceive.systemFixed.SMES_Active` |
| x14 | `statDataExchangeReceive.systemFixed.SMST2_Active` |
| x15 | `statDataExchangeReceive.systemFixed.SMM1_Active` |

### Network 40 "Map Alarms to HMI Interface Alarm" — `interfaceHmi[].alarm` DWord
| Bit | Source |
|---|---|
| x0 | `stateAlarm.spare0` |
| x1 | `stateAlarm.hardwareNOK` |
| x2 | `stateAlarm.transmissionFault` |
| x3 | `stateAlarm.driveenabledNOK` |
| x4 | `stateAlarm.enableRunSequence` |
| x5 | `stateAlarm.enableHomePos` |
| x6 | `stateAlarm.timerMonitorRunSequence` |
| x7 | `stateAlarm.timerMonitorHomePos` |
| x8 | `stateAlarm.timerMonitorReferencePos` |
| x9 | `stateAlarm.noContinueWaitCommand` |
| x10 | `stateAlarm.alarm` |
| x11 | `stateAlarm.spare11` |
| x12 | `stateAlarm.smesActive` |
| x13 | `stateAlarm.safetyNOK` |
| x14 | `stateAlarm.smst2active` |
| x15 | `stateAlarm.smm1active` |
| x16 | `stateAlarm.remoteControlNotActive` |
| x17 | `stateAlarm.serialnumbermismatch` |

### Network 49 "Map Fix Send Data to HMI" — `interfaceHmi[].send.control` DWord
Echo of what was sent to the Kistler fieldbus this scan. Useful for showing command-active feedback on buttons.
| Bit | Source |
|---|---|
| x0 | `statDataExchangeSend.systemFixed.Auto` |
| x1 | `statDataExchangeSend.systemFixed.DriveEnable` |
| x2 | `statDataExchangeSend.systemFixed.RunSequence` |
| x3 | `statDataExchangeSend.systemFixed.DriveToHomePos` |
| x4 | `statDataExchangeSend.systemFixed.DriveToRefPos` |
| x5 | `statDataExchangeSend.systemFixed.JogFW` |
| x6 | `statDataExchangeSend.systemFixed.JogBW` |
| x7 | `statDataExchangeSend.systemFixed.ContinueFromWait` |
| x8 | `statDataExchangeSend.systemFixed.strobe` |
| x9 | `statDataExchangeSend.systemFixed.AckAdmin` |

### Network 43 "HMI state Mapping" — `interfaceHmi[].state` DWord (FB internal state for HMI diagnostics)
| Bit | Source / meaning |
|---|---|
| x0 | (powerrail-only — likely `aux.automaticMode` source upstream; appears as always-true rung) |
| x1 | `OpModeUserInterfaceOut.opmodeStatus.singleStepActive` |
| x2 | `SafetyOK` |
| x3..x7 | RCoil — internal-state reservations, always reset each scan |
| x8 | `aux.generalAlarm` |
| x9, x10 | RCoil — reserved |
| x11 | `aux.automaticMode` (RCoil-gated) |
| x12..x16 | RCoil — reserved |
| x17 | `statDataExchangeSend.systemFixed.strobe` |
| x18 | `autoRunSequence` (FB Input) |
| x19 | `autoHomePosition` (FB Input) |
| x20 | RCoil — reserved |
| x21 | `interfaceHmi[*].select` (HMI confirm bit reflects back) |
| x22 | `enableRunSequence` |
| x23 | `enablehomePos` |
| x24 | `statDataExchangeSend.systemFixed.JogFW` |
| x25 | `statDataExchangeSend.systemFixed.JogBW` |
| x26 | `enableBlock` (FB Input) |
| x27 | `HardwareOK` (FB Input) |
| x28 | `statDataExchangeSend.systemFixed.RunSequence` |
| x29 | `statDataExchangeSend.systemFixed.DriveToHomePos` |
| x30 | `statDataExchangeSend.systemFixed.DriveToRefPos` |
| x31 | `statDataExchangeSend.systemFixed.AckAdmin` |

Note all rungs gated by `enableBlock` series. Faceplate `state` is NOT the same as `receive.status` — use `receive.status` for press operational LEDs, `state` for diagnostic LEDs (SafetyOK, generalAlarm, single-step active).

### `interfaceHmi[].move` Word — HMI-writable command bus (the user-facing button targets)
Bits are written by the HMI; FB reads them in per-bit networks. Different network per bit (not a single "map" network).
| Bit | Network | Network title | Meaning |
|---|---|---|---|
| x0 | 9 | "Control Remotely" | Remote control toggle (HMI takeover) |
| x1 | 16 | "Run the sequence" | RunSequence (manual trigger) |
| x2 | 26 | "ReturnHomePos" | DriveToHomePos |
| x8 | 27 | "DrivetoRefPOs" | DriveToRefPos |
| x9 | 7 | "Clear Faults" | AckAdmin |
| x10 | 12 | "DataStrobe Manually" | DataStrobe gate (paired with x13) |
| x11 | 23 | "Resume After Error" | ContinueFromWait |
| x13 | 12 | "DataStrobe Manually" | DataStrobe command |
| x14 | 28 | "JOG Forward" | JogFW |
| x15 | 29 | "JOG Backward" | JogBW |

Bits 3..7, 12 reserved.

### Verification
`extract_bit_map.py` reads the FB XML and reproduces every table above. Re-run if the FB version changes.

### Common confusion to NOT re-make
The bit positions in `receive.status` are *not* the same as the byte.bit addresses in the 200-byte Kistler fieldbus protocol. The protocol has Ready at byte 6.0; the FB remaps it to `receive.status.x2`. **Bind HMI elements to `receive.status.x<n>` (from this table). Never to a protocol byte address — the FB owns the translation.**

---

## 21. Kistler EO result encoding — verified 2026-05-11

The Kistler `receive.PV_E04_Nopass`, `PV_E05_Unibox`, `PV_E06_Envelope`, and `PV_Byte_E07..E10` **byte values ARE the pass/fail indicator** per the Kistler NC manual:
- **byte = 0** → EO passed
- **byte ≠ 0** → EO failed (the value encodes a Kistler-specific fault code)

So don't add a separate "Result" column to UI tables that shows the same info as the byte column. The byte value IS the result. For visual pass/fail status:
- Aggregate via the existing `receive.status.x8 OkTotal` / `receive.status.x9 NOkTotal` LEDs (already on the screen)
- Per-EO, the byte numeric value IS sufficient — value of 0 means passed
- For a quick visual: bind an `HmiCircle.BackColor` via a Range mapping (Condition `value=0` → green, otherwise → red)

For `receive.PV_EO1_Force/PV_EO2_Distance/PV_EO3_Gradient` and `PV_Real_EO7..EO10` (Reals): these are **process measurements, not pass/fail flags**. No inherent good/bad — they're the captured curve characteristics (force, distance, gradient, etc.). Their pass/fail is determined by whether they fell inside their EO's tolerance band, which is what the byte results above evaluate.

**Lesson**: don't invent UI columns/cells without a clear data binding. Every display element should map to a §19 field. If you find yourself adding a column "to look nicer", stop and check if the data already exists elsewhere.

---

## 22. Layout testing — mandatory at end of every HMI build (verified 2026-05-11)

**Hard lesson**: compile-clean + bindings-correct does NOT mean the screen looks right. The 1st operator-facing build had 4 visual bugs that compile + binding tests missed:
1. EO panel x=20 collided with Alarm panel x=20 (vertical overlap)
2. `HmiLine` separators rendered as diagonals (Point1/Point2 stayed at defaults)
3. Operator hint text truncated to "...Rer..."
4. Section content escaped its card bounds

**All four issues are catchable by running these layout tests after every build.** Make them mandatory.

### Layout test suite (run after every build, before declaring done)

```powershell
# SIX layout tests are mandatory:
#   1. Screen-bounds (item AABB inside screen)
#   2. Card-to-card overlap (top-level cards must not collide)
#   3. Child-in-card (items inside parent card's bounding box)
#   4. Text-fits-container (heuristic char-width check)
#   5. Orphan detector (every item registered to a parent)  [ADDED 2026-05-11]
#   6. Sibling overlap (no two interactive items overlap)  [ADDED 2026-05-11]
#
# Tests 5 and 6 are essential — tests 1-4 alone missed a real LED-over-value
# overlap because the LED was never registered to a parent.

# 1. SCREEN-BOUNDS — every item must be inside (0,0)..(screenWidth,screenHeight)
foreach ($r in $rects) {
    $within = ($r.L -ge 0) -and ($r.T -ge 0) -and ($r.R -le $screen.Width) -and ($r.B -le $screen.Height)
    Test "$($r.Name) inside screen" $within
}

# 2. CARD-TO-CARD OVERLAP — top-level cards / background panels must not overlap each other.
#    AABB intersection: a.L < b.R && b.L < a.R && a.T < b.B && b.T < a.B
$topCards = @('hdr_bg','status_card','alarm_card','fd_card','ctrl_card','eo_card','echo_card', ...)
$topRects = $rects | Where-Object { $topCards -contains $_.Name }
for ($i=0; $i -lt $topRects.Count; $i++) {
    for ($j=$i+1; $j -lt $topRects.Count; $j++) {
        $a = $topRects[$i]; $b = $topRects[$j]
        $overlap = ($a.L -lt $b.R) -and ($b.L -lt $a.R) -and ($a.T -lt $b.B) -and ($b.T -lt $a.B)
        Test "$($a.Name) does not overlap $($b.Name)" (-not $overlap)
    }
}

# 3. CHILD-IN-CARD — every named child of a card must fit inside its parent card's bounding box
foreach ($card in $cardChildren.Keys) {
    $cardR = $rects | Where-Object { $_.Name -eq $card } | Select-Object -First 1
    foreach ($childName in $cardChildren[$card]) {
        $cr = $rects | Where-Object { $_.Name -eq $childName } | Select-Object -First 1
        $inside = ($cr.L -ge $cardR.L) -and ($cr.T -ge $cardR.T) -and ($cr.R -le $cardR.R) -and ($cr.B -le $cardR.B)
        Test "'$childName' fits inside '$card'" $inside
    }
}

# 4. TEXT-FITS-CONTAINER (heuristic) — at font size N, ~0.55*N pixels per char
#    For each long label, verify text length × char width <= container width
function FitsWidth($it, $charWidth) {
    $txt = (extract plain text)
    return ($txt.Length * $charWidth) -le $it.Width
}
$labelChecks = @(  # All labels that are operator-facing AND have variable length
    @{ Name='led_standstill_label'; CharWidth=7 }   # 11pt regular
    @{ Name='op_hint';              CharWidth=5 }   # 9pt regular
    ...
)
```

### Card-children mapping

To run §22 test #3, you need a `$cardChildren` hashtable mapping each parent card name to its expected child item names. Build this WHILE you're building the screen — every time you place a child inside a card, add it to the map. Don't try to reconstruct after the fact.

### Bounding-box extraction by widget type

```powershell
foreach ($it in $screen.ScreenItems) {
    $tn = $it.GetType().Name
    if ($tn -eq 'HmiCircle') {
        $cx = $it.CenterX; $cy = $it.CenterY; $r = $it.Radius
        $rect = @{ L=($cx-$r); T=($cy-$r); R=($cx+$r); B=($cy+$r) }
    } else {
        $L = $it.Left; $T = $it.Top; $W = $it.Width; $H = $it.Height
        $rect = @{ L=$L; T=$T; R=($L+$W); B=($T+$H) }
    }
}
```

HmiCircle uses CenterX/CenterY/Radius (not Left/Top/Width/Height) — handle separately.

### HmiLine rendering bug (verified 2026-05-11)

`HmiLine.Point1` and `Point2` are **value-type accessors** — assigning `.X` and `.Y` to the local copy doesn't persist back to the line. Lines whose Point1/Point2 weren't actually written render at the default (corner-to-corner of bounding box) → **diagonal appearance**.

**Workaround**: do NOT use `HmiLine` for horizontal/vertical separators. Instead use a **thin `HmiRectangle`**:
```powershell
$sep = NewItem $screen.ScreenItems $TRect "sep_$n"
Place $sep $L $T $W 1       # 1px tall
$sep.BackColor = $CardBorder
$sep.BorderWidth = [byte]0
```

If you must use HmiLine, set Point1/Point2 via `SetAttribute` (untested — verify before relying).

### PowerShell gotchas that broke screens this session

1. **Variable name collision (case-insensitive)** — `$Accent` (color) and `$accent` (rectangle) are the SAME variable. Renaming locals to `$accentRect`, `$alarmRect`, etc. avoids overwriting palette vars.
2. **String interpolation syntax** — Use `"text_$($var.Property)_more"`, NOT `"text_${($var.Property)}_more"`. The `${...}` form is for variable names with special chars, not subexpressions. The wrong syntax silently produces duplicate names → `ValueIsNotUnique` errors on Create.
3. **PowerShell typed function parameters help debugging** — declaring `[System.Drawing.Color]$bg` on `StyleRect` would have caught the `$Accent` collision immediately with a clear "cannot convert HmiRectangle to Color" error, instead of failing inside the function with a confusing exception.
4. **Function return values pollute pipeline** — `BindTag` returning the dynamization caused 60-line dump to STDOUT when not captured. Use a `BindTag` that returns nothing, plus a separate `BindTagAndGet` for callers who need the dynamization (e.g. for setting the MappingTable on bit-extracts).

### Two additional tests required (added 2026-05-11 after first miss)

**The original §22 four-test suite was insufficient.** It caught the EO/Alarm collision (card-to-card overlap) but missed a sequence-end LED overlapping a cfg-length value because:
- The LED and its label were never added to any card's `cardChildren` map → invisible to child-in-card test
- There was no sibling overlap test → siblings could collide with no signal

**Mandatory additions:**

**Layout test 5 — Orphan detector**: every interactive item (`HmiText`/`HmiIOField`/`HmiButton`/`HmiCircle`/`HmiLine`) must belong to a known parent card OR be on an explicit whitelist (e.g. screen-spanning footer). Items that exist on the screen but aren't registered fail this test. Forces every new visual element to be associated with a parent.

```powershell
$registeredChildren = @{}
foreach ($childList in $cardChildren.Values) { foreach ($n in $childList) { $registeredChildren[$n] = $true } }
foreach ($r in $rects) {
    if ($cardBackgrounds -contains $r.Name) { continue }   # the cards themselves
    if ($whitelistOrphan -contains $r.Name) { continue }   # known intentional orphans (footer)
    Test "orphan-detector: '$($r.Name)' belongs to a known card" ($registeredChildren.ContainsKey($r.Name))
}
```

**Layout test 6 — Sibling overlap**: no two interactive items (`HmiText`/`HmiIOField`/`HmiButton`/`HmiCircle`) may have intersecting bounding boxes. Rectangles (backgrounds, dividers) are excluded because they're intentionally beneath/behind other items.

```powershell
$interactive = $rects | Where-Object { $_.Type -in @('HmiText','HmiIOField','HmiButton','HmiCircle') }
for ($i=0; $i -lt $interactive.Count; $i++) {
    for ($j=$i+1; $j -lt $interactive.Count; $j++) {
        $a = $interactive[$i]; $b = $interactive[$j]
        $hit = ($a.L -lt $b.R) -and ($b.L -lt $a.R) -and ($a.T -lt $b.B) -and ($b.T -lt $a.B)
        Test "sibling overlap: $($a.Name) vs $($b.Name)" (-not $hit)
    }
}
```

This second test also catches **labels with oversized bounding boxes overlapping their unit-suffix labels** (e.g. "Force Y" label at width 320 overlapping "[N]" label that should be next to it). The fix is to size labels to fit their text, not the whole row.

### Standard build → test → done flow

After EVERY screen build:
```
1. Run build script
2. Run binding tests (verify §19 path correctness)
3. Run layout tests (§22 test suite)
4. Compile HMI
5. Only if all 4 are clean: report "done" to user
```

Never declare a UI done after just compile-clean. Compile is necessary but not sufficient.

---

## 20. HMI element selection by direction (canonical pattern)

**Verified live 2026-05-11.** Always pick the widget that matches the data's *direction* (FB→HMI read-only, HMI→FB write, or bit-extract for animation). Mixing them (e.g. using an `InputOutput` IOField for a display-only string) gives users an editable cursor on a value they can't actually write — wrong UX.

**REVISED 2026-05-11 (user correction):** **HmiIOField is ONLY for operator-entered setpoints.** Any value coming FROM the device — string OR number — must be `HmiText` with `TagDynamization` on `Text`. `IOFieldType=Output` looks like an input box to the operator and is misleading. The previous matrix entry recommending `HmiIOField Output` for read-only numbers is deprecated.

### Decision matrix (revised)

| Data direction | Data type | Widget | Key config |
|---|---|---|---|
| **HMI reads, can't write** — String/WString | `HmiText` | `TagDynamization` on `Text` property bound to the string tag |
| **HMI reads, can't write** — numeric (Real/Int/Byte/SInt) | `HmiText` | `TagDynamization` on `Text` bound to the numeric tag (runtime stringifies) |
| **HMI reads, can't write** — Bool (single bit standalone) | `HmiCircle` (or shape) | `TagDynamization` on `Visible` or `BackColor` to the Bool tag |
| **HMI reads, can't write** — single bit of DWord/Word | `HmiCircle` (or shape) | `TagDynamization` on `BackColor` to the DWord; `MappingTable.ConditionType=Singlebit`; Entry[1].`Condition = 2^bit` (UInt64); per-state colors |
| **HMI writes, FB reads** — numeric setpoint (e.g. MP to send) | `HmiIOField` | **`IOFieldType = InputOutput`**; `TagDynamization` on `ProcessValue` to the *Set tag |
| **HMI writes, FB reads** — Bool/bit command | `HmiButton` | `EventHandlers.Create([HmiButtonEventType]::Activated)` + `Deactivated` (hold-style) or `Tapped` (toggle); `Script.ScriptCode` reads/writes the target tag |

**Mnemonic:** "If the operator types into it, it's `HmiIOField InputOutput`. Otherwise it's `HmiText`."

### Why `HmiText` for read-only strings (not `HmiIOField Output`)
- `HmiText` has no border/input cursor — semantically a label
- `HmiIOField Output` still renders as a boxed field — visually wrong for a display-only string like a plant identifier
- Direct `TagDynamization` on `Text` property works and compiles clean (verified live on `plant_io`)
- For numbers, `HmiIOField Output` is still right because it handles formatting (`OutputFormat` property) — `HmiText` would require manual number-to-string conversion

### Why `IOFieldType=Output` for read-only numbers
- The default `InputOutput` mode gives a focus cursor + keyboard entry — wrong for FB-owned values
- `Output` mode disables input but keeps the formatted display + threshold/quality animations
- Setting via Openness: `$io.IOFieldType = [Enum]::Parse([Siemens.Engineering.HmiUnified.UI.Enum.HmiIOFieldType], 'Output')`

### Why `HmiCircle` + Singlebit (not Bool tag) for bits of a DWord
- WinCC Unified TagDynamization rejects bit-access in tag paths (`.%X<n>` etc.) — verified via 7 different syntaxes, all rejected
- Pre-creating per-bit Bool HMI tags with bit-access PlcTag fails: `set_PlcTag` rejects the syntax
- The only mechanism that works: bind to whole DWord, then `ConditionType=Singlebit` does the extraction inside the dynamization

### Code snippet: HmiText + Text dynamization
```powershell
$txt = NewItem $screen.ScreenItems 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiText' 'plant_io'
$txt.Left = 488; $txt.Top = 28; $txt.Width = [uint32]300; $txt.Height = [uint32]30
$tagDynT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'
$cg = $txt.Dynamizations.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
$dyn = $cg.MakeGenericMethod($tagDynT).Invoke($txt.Dynamizations, @('Text'))
$dyn.SetAttribute('Tag', 'MVterminalPressKistler.plantidentifier')
```

### Code snippet: IOField with Output mode
```powershell
$io = NewItem $screen.ScreenItems 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField' 'pv_force'
$io.IOFieldType = [Enum]::Parse(
    (Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiIOFieldType'),
    'Output'
)
# Bind ProcessValue as usual...
```

### Applied to `_Kistler_Press_01` (current state)
- `plant_io` (plantidentifier WString) → **HmiText** with Text-dyn to `MVterminalPressKistler.plantidentifier`
- 14 numeric display-only fields → **HmiIOField** with `IOFieldType=Output`: `tu_io`, `fd_xmin/xmax/ymin/ymax`, `pv_force/disp/grad`, `a_mp_io/a_seq_io/a_pg_io`, `lbl_io`, `om_io`, `cn_io`
- 5 numeric editable setpoints → **HmiIOField** with `IOFieldType=InputOutput`: `js_io`, `mf_io`, `mp_io`, `seq_io`, `pg_io`
- 20 LED/button-echo bits → **HmiCircle/HmiButton** with `ConditionType=Singlebit` (per memory §16 pattern, verified per §19 bit map)
- 8 button click commands → **HmiButton** with EventHandlers + JS scripts (per memory §14 pattern, mapped per §19 move bits)

---

## 18. Kistler screen current state — 2026-05-11 FINAL

`_Kistler_Press_01` on `+TOOL01-HMI01 / HMI_RT_2` (project `ST110_210_MVLV_Press`):

### Element inventory (131 items)
- **131 ScreenItems** total
- **50 TagDynamizations** all bound under structured tag `MVterminalPressKistler` (DataType `LDrive_typeKistlerHmi`, `PlcTag="MVTermPressParameter&HMIIF".MVTermPressHMIInterface[0]`, lives at `_SICAR_HMI-tags → Tec_Units → Opmode1 → Station1`)
- **20 bit-extract dynamizations** (12 status LEDs + 8 alarm LEDs) with `ConditionType=Singlebit` per §16 pattern
- **8 button echo dynamizations** on `send.control` bits, same Singlebit pattern
- **15 EventHandlers** on 8 buttons writing to `MVterminalPressKistler.move` bits per §19 (Activated/Deactivated press-hold; Tapped XOR for Remote toggle)
- **1 read-only HmiText** (`plant_io`) bound to `plantidentifier` via TagDynamization on Text property
- **14 read-only HmiIOFields** with `IOFieldType=Output` (numeric displays)
- **5 editable HmiIOFields** with `IOFieldType=InputOutput` (setpoints + program selectors)

### Verification
- **Compile**: clean (0 errors, 0 warnings) via `compile-hmi.ps1`
- **Bit map vs FB source**: every bit verified by wire-trace in `extract_bit_map.py` against networks 40/43/48/49 + per-bit move networks (§19 ground truth)
- **58/58 binding verification tests pass** (`verify-against-fb.ps1`) — every LED + button + tag-bound element checked against §19
- **222/222 unit tests pass** (`test-kistler-mapping.ps1`) — label/bit-text/tag/property consistency

### Bindings reference — all 50, all matching §19

**Header (3 read-only)** — `plant_io` (HmiText) → plantidentifier, `tu_io` → tecUnitNumber, `sc_badge` BackColor → stateColour

**Status LEDs (12, bit-extract on receive.status / state)** — Ready=x2, OkTotal=x8, NokTotal=x9, DriveEnabled=x1, HomePos=x5, RefPos=x4, Standstill=x6, SeqEnd=x12, WaitRequest=x3, KistlerAuto=x0, SmesActive=x13, SafetyOK=state.x2

**Alarm LEDs (8, bit-extract on alarm)** — HardwareNOK=x1, TxFault=x2, DriveEnableNOK=x3, SafetyNOK=x13, CycleTimeout=x6, WaitMissing=x9, RemoteInactive=x16, SerialMismatch=x17

**Buttons (8 echoes on send.control + 15 click handlers on move)** — Run (echo x2, click x1), AckAdmin (echo x9, click x9), Home (echo x3, click x2), Ref (echo x4, click x8), Remote (echo x0, toggle x0), ContWait (echo x7, click x10+x11), JogPlus (echo x5, click x14), JogMinus (echo x6, click x15)

**F-D area (4 read-only IOField Output)** — `receive.PVcurrentXmin-X/Xmax-X/Ymin-Y/Ymax-Y`

**Process values (3 read-only IOField Output)** — `receive.PVcurrentValueY` (force), `receive.PVcurrentValueX` (disp), `receive.PV_EO3_Gradient`

**Setpoints (2 editable IOField)** — `serverJogSpeedSet`, `serverJogMaxForceSet`

**Program selection (3 editable IOField)** — `manualSelectMpNum`, `selectSequenceSet`, `selectPageSet`

**Echo bar (6 read-only IOField Output + 1 LED + 1 sc_badge)** — `receive.mpNum`, `send.selectSeqeunce` (UDT typo intentional), `send.selectPage`, `currentLabel`, `sequenceEnd` (HmiCircle Visible), `opmodearea`, `hmiControlNo`

### SICAR-aligned color palette applied (per §17)
| Semantic | Hex | RGB |
|---|---|---|
| Off / Gray | `#C8CDD7` | 200,205,215 (TIA default neutral) |
| Light green (on / good) | `#92D050` | 146,208,80 |
| Light blue (manual / remote) | `#00B0F0` | 0,176,240 |
| Olive green (single step) | `#00B050` | 0,176,80 |
| Orange (enable missing / wait) | `#FFC000` | 255,192,0 |
| Red (alarm / NOK) | `#FF0000` | 255,0,0 |
| Yellow (safety / info) | `#FFFF00` | 255,255,0 |
Exact `LSicar_GeneralScripts.ColorStyle()` literals still pending verification — open `ColorStyle` in TIA UI script editor and swap exact hex codes into `apply-sicar-colors.ps1` if they differ.

### Working scripts (production set in `C:\Users\MudasserWahab\Claude Code\`)
| Script | Purpose |
|---|---|
| `build-kistler-tags-only.ps1` | Build screen from scratch with all 50 TagDynamizations |
| `fix-singlebit-mode.ps1` | Configure `ConditionType=Singlebit` on 28 bit-extract dynamizations |
| `apply-sicar-colors.ps1` | Apply SICAR-standard named-color palette to all 28 |
| `add-button-events.ps1` | Add 15 click handlers writing to `.move` bits |
| `fix-readonly-iofields.ps1` | Set IOFieldType=Output on 15 read-only, InputOutput on 5 editable |
| `swap-plant-to-text.ps1` | Replace plant_io HmiIOField with HmiText + Text dynamization |
| `verify-against-fb.ps1` | 58-test binding verification against §19 ground truth |
| `test-kistler-mapping.ps1` | 222-test label/bit-text/tag/property consistency |
| `dump-bindings.ps1` | Read-back of every dynamization on the screen |
| `compile-hmi.ps1` | Standalone HMI compile + flat error report |
| `extract_bit_map.py` | Re-extract §19 ground truth from FB XML (re-run if FB changes) |

### Things explicitly avoided (don't re-attempt — verified dead-ends)
- **TagDynamization Formula with `value & mask`** — DSL rejects, no variable identifier works (§16)
- **Bit-access tag-path syntax** (`.%X<n>`, `.X<n>`, `[<n>]`, `.bit<n>`) — all 7 variants rejected at compile (§14)
- **ExpressionDynamization for bit-extract** — compiles clean but doesn't surface in TIA UI editor (§14)
- **Pre-creating per-bit Bool HMI tags** with bit-path `PlcTag` — `set_PlcTag` rejects `.%X<n>` syntax (verified live; 28 empty tags created then cleaned up)
- **Faceplate (Screen Type) export via Openness** — `ExportAsDocuments` returns Warning with empty `ExportedDocuments`; same for library script types (§14)
- **`ConditionType=Bitmask` with `BitDynamizationType=SingleBit` entries** — TIA UI labels this "Multiple bits" and doesn't render the entries cleanly. Use `ConditionType=Singlebit` for the single-bit radio (§16)
- **`InputOutput` IOField for read-only data** — gives users a phantom cursor on values they can't write. Use `Output` for display-only (§20)

### Session history (chronological)
1. **Day 1**: Initial probe of Openness HmiUnified API → discovered screen creation, item creation, tag dynamization all work via reflection (§14)
2. **Day 1**: Built `_Kistler_Press_01` v1 with 131 items, all bound via TagDynamization to `MVterminalPressKistler` paths
3. **Day 1**: Added button click handlers writing to `move` bits via EventHandlers + Script.ScriptCode (JS)
4. **Day 2 morning**: Memory consolidated as §14, §15, §16 (initial bit-extract pattern using `ConditionType=Bitmask`)
5. **Day 2**: User flagged "Multiple bits" UI label confusion — debugged `ConditionType=Bitmask` vs `Singlebit`; corrected to `Singlebit` (now §16)
6. **Day 2**: SICAR documentation extracted (`SICAR_Docu_V51.zip`), color standard identified; SICAR-aligned palette applied (§17)
7. **Day 2**: User challenged bit-map correctness — wire-traced every coil in FB networks 40/43/48/49 via `extract_bit_map.py`; verified all bindings match FB source; §19 written as authoritative reference
8. **Day 2**: User flagged `plant_io` as wrong widget — `IOFieldType=Output` mode set on 15 display-only fields, kept InputOutput on 5 editable; plant_io specifically swapped to `HmiText` with TagDynamization on Text property; §20 written as widget-selection canon
9. **End state**: clean compile, 58 binding tests + 222 consistency tests passing, full memory consolidated under Quick Index + §19 ground truth + §20 pattern matrix

### Open items for next session
1. Read exact `ColorStyle()` RGB values from `LSicar_GeneralScripts` library script in TIA UI; swap into `apply-sicar-colors.ps1`
2. **Parameterize the build for Station2/3/4 instances** (other tecUnits) — current scripts hardcode `MVterminalPressKistler` and tecUnit index 0; need a parameter-driven version
3. **HmiTrendControl on the F-D area** — bind X axis to `receive.PVcurrentValueX`, Y axis to `receive.PVcurrentValueY`
4. **Runtime validation** — download to a real or simulated PLC, observe LEDs/echoes/buttons actually toggle correctly
5. **Additional alarm LEDs** — currently 8; could add Home Timeout (alarm.x7) and Ref Timeout (alarm.x8) for parity with CycleTimeout (alarm.x6)
6. **Optional**: promote `_Kistler_Press_01` into a Screen Type (faceplate) once stable — blocked on faceplate import schema (see §14)

## 23. HMI build recipe — proven workflow (verified 2026-05-11)

Use this every time a Kistler (or similar UDT-bound) screen is being built. **Don't open-code Openness calls** — go through the framework.

### 23.1 Files
- **`C:\Users\MudasserWahab\Claude Code\kistler-design.ps1`** — layout-aware framework module. Dot-source it; never duplicate its internals.
- **`C:\Users\MudasserWahab\Claude Code\build-kistler-pro-v3.ps1`** — current reference consumer. Pattern after this.
- **`C:\Users\MudasserWahab\Claude Code\test-dyn-quick.ps1`** — post-build dynamization audit (read-only).
- **`C:\Users\MudasserWahab\Claude Code\fix-emdash.ps1`** — example of a surgical post-fix that touches only specific items (don't rebuild the screen for cosmetic tweaks).

### 23.2 Framework API surface (kistler-design.ps1)

| Function | Purpose | Validation it performs at call time |
|---|---|---|
| `Initialize-Design` | Attach TIA, resolve HmiSoftware, create/replace screen, load type cache + SICAR color palette | Screen W/H set; types resolved |
| `New-Card` | Styled panel + optional header band. Auto-registers bg/hdr_bg/header as card children. | screen-bounds, card-card overlap |
| `Add-StatusLed` | HmiCircle (Singlebit BackColor) + label, auto-positioned on row cursor | within-card, sibling overlap, label fits |
| `Add-DisplayValue` | **HmiText with Text dynamization** — for any FB-owned value (string OR numeric). NEVER produces HmiIOField. | within-card, sibling overlap |
| `Add-EditableValue` | HmiIOField `InputOutput` — operator-entered setpoint only | within-card, sibling overlap |
| `Add-DisplayText` | Same as Add-DisplayValue but for explicit string semantics | within-card, sibling overlap |
| `Add-Label` | Static descriptive text | within-card, sibling overlap, text-fits-width heuristic |
| `Add-Button` | HmiButton with hold (`Activated`+`Deactivated`) or toggle (`Tapped`) scripts on `move` bits; optional echo bit on `send.control` | within-card, sibling overlap |
| `Test-LayoutSelfCheck` | Runs all 5 invariants over tracked cards/children — call before `Save-AndCompile` to abort bad layout | screen bounds, card overlap, child-in-card, sibling overlap, orphan detector |
| `Save-AndCompile` | `$session.Save()` + compile via parent device ICompilable | none — assumes layout is clean |

### 23.3 Invariants enforced

1. **Screen bounds** — every item AABB inside (0,0)..(W,H)
2. **No card-card overlap** — set on `New-Card`
3. **Children inside their card** — set on every `Add-*`
4. **No sibling overlap among interactive widgets** (`HmiText`, `HmiIOField`, `HmiButton`, `HmiCircle`). `HmiRectangle` is excluded so card backgrounds don't poison the test.
5. **No orphans** — every screen item must be registered to a card (catches off-framework `_NewItem` calls that forget `Register-Child`)
6. **Text fits width** — heuristic char-width × length ≤ widget width

If a future build needs an off-framework primitive (e.g. a special line, gradient, image), the pattern is:
```powershell
$x = _NewItem $screen.ScreenItems $script:Types.Rect 'my_special'
Assert-Placement 'my_special' $card $L $T $W $H
_Place $x $L $T $W $H
Register-Child $card 'my_special' 'HmiRectangle' $L $T $W $H   # ← always do this
```

### 23.4 Widget selection (canonical, supersedes earlier §20 entries)

> **"If the operator types into it, it's `HmiIOField InputOutput`. Otherwise it's `HmiText`."**

| Direction | Type | Widget | Property bound |
|---|---|---|---|
| FB → HMI string | any | `HmiText` | `Text` |
| FB → HMI number | any | `HmiText` | `Text` (runtime stringifies) |
| FB → HMI bit-of-DWord | Bool inside DWord | `HmiCircle` | `BackColor` + `MappingTable.ConditionType=Singlebit`, mask=2^bit (UInt64), 2 entries |
| FB → HMI standalone Bool | Bool | `HmiCircle` | `Visible` or `BackColor` |
| HMI → FB number | Real/Int | `HmiIOField InputOutput` | `ProcessValue` to the `*Set` tag |
| HMI → FB bit command | Bool | `HmiButton` | `EventHandlers.Create(Activated/Deactivated)` for hold, `Tapped` for toggle, script Reads/Writes the DWord with mask |

**Why no HmiIOField Output:** even in Output mode it renders as a boxed input control — visually misleading on FB-owned values. Use HmiText always for read.

### 23.5 Standard build skeleton

```powershell
. "$PSScriptRoot\kistler-design.ps1"
Initialize-Design -ScreenName '_Kistler_Press_01' -RootTag 'MVterminalPressKistler'
$C = Get-Colors; $screen = Get-Screen

# 1) HEADER ribbon (full-width card)
$hdr = New-Card -Name 'hdr_bg' -X 0 -Y 0 -W 1920 -H 72 -BgColor $C.HeaderBg -BorderColor $C.HeaderBg
Add-Label       -Card $hdr -Name 'hdr_title'  -X 28 -Y 10 -W 360 -H 28 -Text 'KISTLER maXYmos NC' -FontSize 16 -Weight Bold -ForeColor $C.HeaderText
Add-DisplayValue -Card $hdr -Name 'plant_value' -X 600 -Y 26 -W 720 -H 36 -Path 'plantidentifier' -FontSize 18 -Weight Bold -ForeColor $C.HeaderText -HAlign Center
# ... operating state, unit, etc.

# 2) Status card with LEDs
$status = New-Card -Name 'status_card' -X 20 -Y 92 -W 300 -H 468 -Header 'PRESS STATUS'
Add-StatusLed -Card $status -Name 'led_ready' -Label 'Ready' -Field 'receive.status' -Bit 2 -OnColor $C.LightGreen
# ... bits per §19

# 3) Alarms card -- LEDs on `alarm` field
# 4) Move/command card -- Add-Button -MoveBits @(n) -Toggle:$false -EchoBit n
# 5) Operator setpoints card -- Add-EditableValue
# 6) Echo card -- current vs sent values, side-by-side
#    Use HeaderTextWidth on New-Card if you'll place a badge in the header's right corner
#    e.g. -HeaderTextWidth 500 leaves 240 px for a status LED + label cluster

# 7) Validate, then save
$lc = Test-LayoutSelfCheck
if ($lc.Fail -gt 0) { Write-Host 'aborting'; return }
Save-AndCompile
```

### 23.6 Gotchas re-encountered and resolved

| Symptom | Cause | Fix |
|---|---|---|
| `â€"` rendering in labels | `—` in .ps1 saved as UTF-8 but PS5.1 reads as CP1252 | Use ASCII (`-`, `:`) in label strings; or save script as UTF-8 with BOM |
| "PLACEMENT FAIL: header overlaps badge" on echo_card | Auto-header text spans full width and collides with custom right-corner items | Pass `-HeaderTextWidth N` to `New-Card` to clip the header text |
| Test-LayoutSelfCheck flags `*_hdr_bg`/`*_header` as orphans | Earlier framework didn't auto-Register-Child the auto-created header items | Already fixed: `New-Card` registers all three (bg, hdr_bg, header) |
| Operator sees a typing cursor on a value they can't change | Used HmiIOField Output for an FB-owned numeric | Switch to `Add-DisplayValue` (HmiText with Text binding) |
| `_NewItem` items overlapping registered items, not caught | The raw item was never registered | Always call `Register-Child` after `_NewItem` outside the helpers |
| `${($x.Y)}` in interpolation produces empty | PowerShell `${name}` doesn't take expressions | Use `$($x.Y)` |
| `[System.Drawing.Color]$Param = $null` parser error | Color is a value-type struct | Drop the type constraint on optional Color params |
| `[AllowEmptyString()]` needed for empty `-Text` | Mandatory string param rejects empty | Add the attribute |
| MappingTable rejects `Bitmask` for single-bit watch | Multi-bit logic differs from single-bit | Use `ConditionType=Singlebit`, mask=2^bit as UInt64 |

### 23.7 Standing rule about iteration speed

Do not rebuild the entire screen for cosmetic or single-item fixes. Pattern:
1. Identify exactly which items need changes.
2. Write a small targeted script that attaches to TIA, finds items by name pattern, mutates only those, calls `$session.Save()`.
3. Update the build script source so the next full rebuild stays consistent.

The full v3 build is ~30 s for ~200 items + compile. A targeted fix is sub-second.

### 23.8 Post-build verification suite

1. `Test-LayoutSelfCheck` (built into the framework, runs pre-save) — 3893+ checks pass on a clean v3 build.
2. `test-dyn-quick.ps1` — audits every dynamization: prop name vs widget type, tag root, Singlebit mask is 2^n, entries count == 2. Last clean run: 80 dynamizations, 0 flags.
3. Compile result — `Errors=0 Warnings=0`.

If any of those three fail, do not declare done.

## Why
Complete holistic reference for all Kistler maXYmos NC work: device protocol, PLC FB implementation, HMI UDT, supervision design, and faceplate. All verified from actual FB XML and Kistler NC manuals.

## How to apply
Load this memory at the start of any Kistler-related session. Skip reprobing — everything is confirmed. Go directly to the relevant section. Do not guess UDT field directions — the architecture rule in section 8 is verified.
