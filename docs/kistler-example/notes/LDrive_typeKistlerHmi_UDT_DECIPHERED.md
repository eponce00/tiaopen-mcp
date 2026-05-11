# LDrive_typeKistlerHmi UDT - Complete Decipherment

This is the **ACTUAL HMI interface UDT** that the faceplate binds to. It is the InOut parameter of the LSicar_KistlerPress FB.

## Top-Level Fields (UDT Root Level)

### 1. **state** (DWord) - "State tec_unit"
**Purpose:** Bit-packed status word encoding the press operational state

**Bit Mapping (from FB logic):**
- Bit 0: Ready (from `statDataExchangeReceive.systemFixed.Ready`)
- Bit 1: OkTotal (from `statDataExchangeReceive.systemFixed.OkTotal`)
- Bit 2: NOkTotal (from `statDataExchangeReceive.systemFixed.NOkTotal`)
- Bit 3: DriveEnabled (from `statDataExchangeReceive.systemFixed.DriveEnabled`)
- Bit 4: HomePosReached (from `statDataExchangeReceive.systemFixed.HomePosReached`)
- Bit 5: RefPosReached (from `statDataExchangeReceive.systemFixed.RefPosReached`)
- Bit 6: Standstill (from `statDataExchangeReceive.systemFixed.Standstill`)
- Bit 7: SequenceRunning (from `statDataExchangeReceive.systemFixed.RunSequence`)
- Bit 8: SequenceStopped (from `statDataExchangeReceive.systemFixed.SequenceStopped`)
- Bit 9: SequenceEnd (from `statDataExchangeReceive.systemFixed.SequenceEnd`)
- Bits 10+: Reserved/Other status

**HMI Usage:**
- Faceplate extracts individual bits using bitwise AND operations
- `Ready` LED: `(state & 0x0001) > 0`
- `OK Total` LED: `(state & 0x0002) > 0`
- `NOK Total` LED: `(state & 0x0004) > 0`
- `Drive Enabled` LED: `(state & 0x0008) > 0`
- `At Home` LED: `(state & 0x0010) > 0`
- `At Reference` LED: `(state & 0x0020) > 0`
- `Standstill` LED: `(state & 0x0040) > 0`
- `Running` LED: `(state & 0x0080) > 0`

**Written by:** FB networks that encode statusDataExchangeReceive bits
**Read by:** HMI for status display

---

### 2. **alarm** (DWord) - "Alarm Flags"
**Purpose:** Bit-packed alarm/fault word encoding all fault conditions

**Bit Mapping (from "Clear Faults" network, line ~3150):**
- Bit 0: spare0 (unused)
- Bit 1: hardwareNOK (from `stateAlarm.hardwareNOK`)
- Bit 2: driveEnabledNOK (from `stateAlarm.driveenabledNOK`)
- Bit 3: enableRunSequence (internal flag)
- Bit 4: enableHomePos (internal flag)
- Bit 5: timerMonitorRunSequence (timeout flag)
- Bit 6: timerMonitorHomePos (timeout flag)
- Bit 7: timerMonitorReferencePos (timeout flag)
- Bit 8: noContinueWaitCommand (flag)
- Bit 9: alarm (derived alarm flag)
- Bit 10: spare11 (unused)
- Bit 11: smesActive (state machine status)
- Bit 12: safetyNOK (from `stateAlarm.safetyNOK`)
- Bit 13: smst2Active (state machine status)
- Bit 14: smm1Active (state machine status)
- Bit 15: serialnumbermismatch (from `stateAlarm.serialnumbermismatch`)
- Bits 16+: transmissionFault, remoteControlNotActive, etc.

**HMI Usage:**
- Faceplate extracts fault flags using bit masks
- `Hardware NOK` LED: `(alarm & 0x0002) > 0` (Bit 1)
- `Drive Enable NOK` LED: `(alarm & 0x0004) > 0` (Bit 2)
- `Safety NOK` LED: `(alarm & 0x1000) > 0` (Bit 12)
- `Serial Mismatch` LED: `(alarm & 0x8000) > 0` (Bit 15)

**Written by:** FB "Clear Faults" network, packing stateAlarm struct bits
**Read by:** HMI for fault display and alarm indicators

---

### 3. **move** (Word) - "Interface Movement Position"
**Purpose:** Control word for movement commands and position selection

**Bit Mapping (likely):**
- Used by FB to communicate movement state or position targets
- Related to press positioning (home, reference, manual position, etc.)

**HMI Usage:**
- May be written by HMI to command press movements
- May be read for feedback on current position

**Direction:** Bidirectional (HMI may write, FB reads and feeds back status)

---

### 4. **stateColour** (SInt) - "State Color Code"
**Purpose:** Single-byte color indicator for state visualization

**Values (typically):**
- 0 = Green (normal operation, ready)
- 1 = Yellow (warning, degraded mode)
- 2 = Red (fault, alarm state)
- Other values for intermediate states

**HMI Usage:**
- Faceplate changes background/border color based on this value
- Example: if stateColour = 2, show red border; if stateColour = 0, show green border

**Written by:** FB based on alarm/state conditions
**Read by:** HMI for overall state visualization

---

### 5. **plantidentifier** (WString[24])
**Purpose:** Plant/facility identifier string

**Content:** User-specified plant name (max 24 wide characters)

**HMI Usage:**
- Display in title bar or info panel
- Identify which plant/facility is being controlled

**Direction:** Bidirectional (can be read and potentially written for configuration)

---

## **receive** Struct (Data FROM PLC TO HMI)

This struct contains all data that the FB sends out to the HMI. Updated every cycle as the FB receives new data from the fieldbus.

### Process Values
| Field | Type | Source | Purpose |
|-------|------|--------|---------|
| `PVcurrentValueX` | Real | From fieldbus EO2 (Distance) | Current displacement/distance (mm) |
| `PVcurrentValueY` | Real | From fieldbus EO1 (Force) | Current force measurement (N) |
| `PV_EO3_Gradient` | Real | From fieldbus EO3 | Force/distance gradient (slope) |
| `PV_EO1_Force` | Real | From fieldbus EO1 | Force value |
| `PV_EO2_Distance` | Real | From fieldbus EO2 | Distance value |
| `PV_Real_EO7` to `PV_Real_E10` | Real | From fieldbus EO7-10 | Additional evaluation outputs |

**HMI Usage (Gauges & Display):**
- Force Gauge: binds to `receive.PVcurrentValueY`
- Distance Gauge: binds to `receive.PVcurrentValueX`
- Gradient Display: binds to `receive.PV_EO3_Gradient`
- Curve Plot X-axis: `PVcurrentValueX` (live displacement)
- Curve Plot Y-axis: `PVcurrentValueY` (live force)

---

### Curve Axis Bounds
| Field | Type | Purpose |
|-------|------|---------|
| `PVcurrentXmin-X` | Real | Curve X-axis minimum (auto-scaled) |
| `PVcurrentXmax-X` | Real | Curve X-axis maximum (auto-scaled) |
| `PVcurrentYmin-Y` | Real | Curve Y-axis minimum (auto-scaled) |
| `PVcurrentYmax-Y` | Real | Curve Y-axis maximum (auto-scaled) |

**HMI Usage:**
- Bind to curve plot's X/Y axis scaling
- Allows auto-ranging based on actual data extremes

---

### Configuration Echo
| Field | Type | Purpose |
|-------|------|---------|
| `status` | DWord | Current press status (bit-packed) |
| `mpNum` | Byte | Current MP number selected (0–127) |
| `cfgMpNum` | Byte | Configuration MP number |
| `cfgAddress` | Byte | Configuration address |
| `cfgLength` | Byte | Configuration length |
| `selectPage` | Byte | Currently selected page (0–7) |
| `selectSequence` | Byte | Currently selected sequence (0–3) |

**HMI Usage:**
- Display current MP, sequence, page selections
- Show which program/configuration is active
- Echo back user selections for confirmation

---

### Jog Feedback
| Field | Type | Purpose |
|-------|------|---------|
| `serverJogSpeed` | Real | Current/feedback jog speed (mm/s) |
| `serverJogMaxForce` | Real | Current/feedback max force (N) |

**HMI Usage:**
- Display current jog speed (read-only feedback)
- Display current max force limit (read-only feedback)

---

### Custom Evaluation Outputs (Bytes)
| Field | Type | Purpose |
|-------|------|---------|
| `PV_E04_Nopass` | Byte | EO4 result (Nopass/pass indicator) |
| `PV_E05_Unibox` | Byte | EO5 result (Unibox envelope) |
| `PV_E06_Envelope` | Byte | EO6 result (Envelope check) |
| `PV_Byte_E07` to `PV_Byte_E10` | Byte | EO7-10 results |

**HMI Usage:**
- Display byte-based evaluation outputs
- Show pass/fail, envelope violations, etc.

---

## **send** Struct (Data FROM HMI TO PLC)

This struct contains all commands and setpoints that the HMI writes to control the press.

### Commands (Control Bits)
| Field | Type | Source | Purpose |
|-------|------|--------|---------|
| `control` | DWord | HMI buttons | Bit-packed command word |

**Bit Mapping (from Kistler maXYmos NC protocol):**
- Bit 0.0: START (execute cycle)
- Bit 0.1: STOP (halt cycle)
- Bit 9.4: JOG-FW (jog forward)
- Bit 9.5: JOG-BW (jog backward)
- Other bits: RESET, HOME, REFERENCE, etc. (per fieldbus spec)

**HMI Usage:**
- Start Button → sets START bit (Bit 0.0)
- Stop Button → sets STOP bit (Bit 0.1)
- Jog Forward → sets JOG-FW bit (Bit 9.4)
- Jog Backward → sets JOG-BW bit (Bit 9.5)
- etc.

**Note:** Bits are set by HMI, FB encodes into 200-byte fieldbus, press responds

---

### MP/Sequence/Page Selection
| Field | Type | Purpose |
|-------|------|---------|
| `mpNum` | Byte | MP to select (write 0–127) |
| `selectSeqeunce` | Byte | Sequence to select (write 0–3) [typo: "Seqeunce"] |
| `selectPage` | Byte | Page to select (write 0–7) |
| `cfgMpNum` | Byte | Configuration MP number |
| `cfgAddress` | Byte | Configuration address |
| `cfgLength` | Byte | Configuration length |

**HMI Usage:**
- MP Selector Dropdown: writes to `send.mpNum`
- Sequence Selector: writes to `send.selectSeqeunce`
- Page Selector: writes to `send.selectPage`
- Configuration inputs: write to cfg* fields

---

### Jog Setpoints
| Field | Type | Purpose |
|-------|------|---------|
| `serverJogSpeed` | Real | Desired jog speed (mm/s) |
| `serverJogMaxForce` | Real | Desired max force (N) |

**HMI Usage:**
- Jog Speed Slider: writes to `send.serverJogSpeed`
- Max Force Slider: writes to `send.serverJogMaxForce`
- FB reads these and limits jog operation accordingly

---

## Additional Top-Level Fields (Metadata & Configuration)

### Setpoint Shadows
| Field | Type | Purpose |
|-------|------|---------|
| `serverJogSpeedSet` | Real | Setpoint shadow for jog speed |
| `serverJogMaxForceSet` | Real | Setpoint shadow for max force |
| `cfgMpNumSet` | Byte | Setpoint shadow for cfg MP |
| `cfgAddressSet` | Byte | Setpoint shadow for cfg address |
| `cfgLengthSet` | Byte | Setpoint shadow for cfg length |
| `selectPageSet` | Byte | Setpoint shadow for page |
| `selectSequenceSet` | Byte | Setpoint shadow for sequence |

**Purpose:** These are "Set" copies used by the FB for storing user inputs that get confirmed/applied. HMI may write to these before final application.

---

### Sequence & Program Info
| Field | Type | Purpose |
|-------|------|---------|
| `currentLabel` | Byte | Current sequence label (0–31) |
| `sequenceEnd` | Bool | Sequence has ended flag |
| `manualSelectMpNum` | Byte | Manually selected MP number |

**HMI Usage:**
- Display `currentLabel` in sequence status box
- Show `sequenceEnd` with "Sequence Complete" indicator
- Echo manual MP selection back

---

### Control & Operational Info
| Field | Type | Purpose |
|-------|------|---------|
| `hmiControlNo` | Int | HMI control index/handshake |
| `opmodearea` | USInt | Operational mode area (manual, auto, setup) |
| `select` | Bool | Generic select flag |
| `hmiSelectWord` | Word | Generic selection word |
| `tecUnitNumber` | Int | Which technical unit (0, 1, 2, ...) |

**HMI Usage:**
- May be used for mode switching (manual/auto/setup)
- May be used for multi-unit coordination (if multiple press units)
- Control handshake/synchronization

---

### Advanced Features
| Field | Type | Purpose |
|-------|------|---------|
| `codeViewCondControl` (Struct) | Struct | Code view filter controls |
| `ipAddressplant` | String | IP address for plant connectivity |

---

## Summary: What the Faceplate Binds To

```
LDrive_typeKistlerHmi.state              → Extract bits for status LEDs
LDrive_typeKistlerHmi.alarm              → Extract bits for fault LEDs
LDrive_typeKistlerHmi.stateColour        → Background color/theme
LDrive_typeKistlerHmi.receive.PVcurrentValueX  → Distance gauge
LDrive_typeKistlerHmi.receive.PVcurrentValueY  → Force gauge
LDrive_typeKistlerHmi.receive.PV_EO3_Gradient  → Gradient display
LDrive_typeKistlerHmi.receive.PVcurrentXmin-X/max-X  → Curve X bounds
LDrive_typeKistlerHmi.receive.PVcurrentYmin-Y/max-Y  → Curve Y bounds
LDrive_typeKistlerHmi.receive.serverJogSpeed   → Jog speed feedback
LDrive_typeKistlerHmi.receive.serverJogMaxForce → Max force feedback
LDrive_typeKistlerHmi.receive.mpNum     → Current MP display
LDrive_typeKistlerHmi.receive.selectSequence → Current sequence display
LDrive_typeKistlerHmi.receive.status    → Status DWord (for advanced indicators)

LDrive_typeKistlerHmi.send.control      → Command bit-packing (START, STOP, JOG-FW, JOG-BW)
LDrive_typeKistlerHmi.send.mpNum        → HMI writes MP selection
LDrive_typeKistlerHmi.send.selectSeqeunce → HMI writes sequence
LDrive_typeKistlerHmi.send.selectPage   → HMI writes page
LDrive_typeKistlerHmi.send.serverJogSpeed → HMI writes jog speed
LDrive_typeKistlerHmi.send.serverJogMaxForce → HMI writes max force

LDrive_typeKistlerHmi.currentLabel      → Sequence label display
LDrive_typeKistlerHmi.sequenceEnd       → "Sequence Complete" indicator
LDrive_typeKistlerHmi.plantidentifier   → Title/info display
```

---

## Data Flow Summary

```
HMI USER ACTIONS
    ↓
Faceplate writes to interfaceHmi[0].send.*
    ↓
FB reads from interfaceHmi[0].send.*
    ↓
FB encodes to 200-byte fieldbus OUT
    ↓
Kistler maXYmos receives command
    ↓
maXYmos executes, measures, evaluates
    ↓
maXYmos sends 200-byte fieldbus IN
    ↓
FB decodes 200-byte fieldbus IN
    ↓
FB writes to interfaceHmi[0].state, alarm, receive.*
    ↓
Faceplate reads from interfaceHmi[0].receive.*, state, alarm
    ↓
HMI DISPLAY UPDATED (gauges, indicators, curves)
```

---

## Key Insight

**The `LDrive_typeKistlerHmi` UDT IS the HMI interface.** There is NO separate "HMI-side UDT"—this IS it. The faceplate binds directly to the fields in this UDT array, reading status/PV from `receive` and writing commands to `send`.

The UDT is designed with:
- **receive**: All data flowing FROM PLC/press TO HMI (read-only for HMI)
- **send**: All data flowing FROM HMI TO PLC/press (write-only for HMI)
- **Top-level fields**: Status/metadata accessible to HMI for display

---
