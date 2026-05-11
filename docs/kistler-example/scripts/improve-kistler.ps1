$ErrorActionPreference = "Stop"
$srcXml = "C:\Users\MudasserWahab\Claude Code\export_kistler_base\LSicar_KistlerPress.xml"
$outXml = "C:\Users\MudasserWahab\Claude Code\LSicar_KistlerPress_improved.xml"

$raw = Get-Content $srcXml -Raw -Encoding UTF8

# =============================================================================
# 1. MEMBER COMMENTS
#    Inject <Comment> after </AttributeList> for every named interface member.
#    If a <StartValue> already follows </AttributeList> the comment is inserted
#    between them (TIA schema order: AttributeList -> Comment -> StartValue).
# =============================================================================

function Add-MemberComment {
    param([string]$xml, [string]$memberName, [string]$comment)
    $search = "<Member Name=""$memberName"""
    $idx = $xml.IndexOf($search)
    if ($idx -lt 0) { Write-Warning "Member not found: $memberName"; return $xml }
    $attrEnd = $xml.IndexOf("</AttributeList>", $idx)
    if ($attrEnd -lt 0) { return $xml }
    $insertPos = $attrEnd + "</AttributeList>".Length
    $commentXml = "`n      <Comment>`n        <MultiLanguageText Lang=""en-US"">$comment</MultiLanguageText>`n      </Comment>"
    return $xml.Substring(0, $insertPos) + $commentXml + $xml.Substring($insertPos)
}

# INPUT members
$raw = Add-MemberComment $raw "plantidentifier"               "Plant/cell identifier string (max 24 chars). Embedded in all ProDiag alarm messages via the @5%s@ placeholder. Set to a unique name per press instance, e.g. KP_ST110_PRS1."
$raw = Add-MemberComment $raw "CarrierID"                     "Carrier or pallet ID (max 9 chars). Passed to the Kistler SmartClient to correlate measurement results with the workpiece carrier for traceability."
$raw = Add-MemberComment $raw "mpSerialNumber"                "Expected workpiece serial number (max 24 chars). Compared against the serial reported by the Kistler device each cycle. A mismatch sets stateAlarm.serialnumbermismatch and blocks sequence start."
$raw = Add-MemberComment $raw "additionaAlarmText"            "Additional context text (max 15 chars) appended to alarm messages. Use for extra identification, e.g. tool number or station sub-ID."
$raw = Add-MemberComment $raw "tecUnitNumber"                 "Technical unit number for this press instance. Used for HMI interface routing and identification in multi-press installations."
$raw = Add-MemberComment $raw "enableBlock"                   "Master block enable. TRUE = block logic active and outputs driven. FALSE = all drive outputs de-energised and alarms suppressed. Default TRUE."
$raw = Add-MemberComment $raw "HardwareOK"                    "Fieldbus and drive hardware health input. FALSE triggers stateAlarm.hardwareNOK and inhibits all motion commands. Connect to PROFINET device diagnostic or drive ready signal. Default TRUE."
$raw = Add-MemberComment $raw "SafetyOK"                      "Safety circuit status. FALSE gates all motion commands, de-energises the drive enable, and sets stateAlarm.safetyNOK. Must be TRUE before any press movement is permitted. Default TRUE."
$raw = Add-MemberComment $raw "servoNotInstalled"             "Set TRUE when the servo drive is physically absent (spare station). Bypasses drive-enable and drive-fault alarms and allows the block to run in passthrough mode without a physical axis."
$raw = Add-MemberComment $raw "hardwareID1"                   "TIA hardware identifier (HW_IO) for the primary Kistler PROFINET device. Used as LADDR in DPRD_DAT to read the 200-byte cyclic receive telegram each scan."
$raw = Add-MemberComment $raw "hardwareID2"                   "TIA hardware identifier (HW_IO) for the secondary Kistler PROFINET device. Used as LADDR in DPWR_DAT to write the transmit telegram to the device."
$raw = Add-MemberComment $raw "smartClientIPAddress"          "IP address string of the Kistler SmartClient application (max 20 chars). Stored for reference and remote configuration. Set to the network address of the Kistler PC running SmartClient."
$raw = Add-MemberComment $raw "mpNumber"                      "Measurement program (MP) number to load on the Kistler device. Sent via the fieldbus transmit telegram. Valid range and program definitions are configured on the Kistler SmartClient."
$raw = Add-MemberComment $raw "cfgAdd"                        "Starting byte offset in the Kistler fieldbus configuration area. Combined with CfgLentgh to define the read/write window for the configuration data telegram exchange."
$raw = Add-MemberComment $raw "CfgLentgh"                     "Length in bytes of the Kistler configuration telegram block. Determines how many bytes are transferred during each configuration read or write operation."
$raw = Add-MemberComment $raw "SelectPageNumber"              "Display page number to activate on the Kistler operator panel or SmartClient HMI. Sent in the transmit telegram each scan."
$raw = Add-MemberComment $raw "selectSequence"                "Sequence profile number to activate on the Kistler device. Sent via the fieldbus transmit telegram to select which measurement sequence to run."
$raw = Add-MemberComment $raw "extStopRequest"                "External stop request from upstream logic (e.g. part-not-present or conveyor fault). Rising edge halts the running sequence gracefully and sets sequenceStopped. Timeout monitored by timeExtStop."
$raw = Add-MemberComment $raw "strobeEnable"                  "Gate for the automatic data-strobe pulse. TRUE allows the strobe command to be sent to the Kistler device during a running sequence to trigger data capture."
$raw = Add-MemberComment $raw "startTL"                       "Rising edge initiates the teach-learn or reference-position calibration cycle on the Kistler axis. Hold TRUE until the TL cycle is confirmed complete."
$raw = Add-MemberComment $raw "autoRunSequence"               "When TRUE the block automatically triggers the measurement sequence on each new cycle trigger. When FALSE the sequence must be started manually via HMI. Default FALSE."
$raw = Add-MemberComment $raw "autoHomePosition"              "When TRUE the axis automatically returns to home position after each sequence completes normally. Disable for processes that require the axis to hold position after pressing."
$raw = Add-MemberComment $raw "autoDriveToReferencePosition"  "When TRUE the axis automatically drives to the reference/calibration position during block initialisation or after a reset. Used for absolute position referencing at startup."
$raw = Add-MemberComment $raw "JogFwd"                        "Jog press forward (downward, pressing direction). Drive moves while signal is TRUE. Only active in manual or setup mode. Rate limited by jog speed in parameters."
$raw = Add-MemberComment $raw "JogNeq"                        "Jog press negative/backward (upward, retract direction). Drive moves while signal is TRUE. Only active in manual or setup mode."
$raw = Add-MemberComment $raw "continuewait"                  "Rising edge clears the waitContinue pause state and resumes sequence execution. Used for operator-confirmation steps in semi-automatic cycles or fault-recovery sequences."
$raw = Add-MemberComment $raw "SequenceEndReset"              "Rising edge resets the Sequenceend, sequenceStopped, and internal sequence-complete flags, clearing the end-of-cycle indication and allowing a new cycle to be triggered."
$raw = Add-MemberComment $raw "enableRunSequence"             "Enable gate for sequence execution. FALSE prevents the measurement sequence from starting even if autoRunSequence is TRUE or a manual start is requested. Default TRUE."
$raw = Add-MemberComment $raw "enablehomePos"                 "Enable gate for home-position return. FALSE prevents the axis from driving to home position even when autoHomePosition is TRUE. Default TRUE."
$raw = Add-MemberComment $raw "externalAlarm"                 "External fault injection from another block or interlock. When TRUE, sets stateAlarm.alarm and contributes to GeneralAlarm. Allows upstream faults to be reflected through the Kistler block."
$raw = Add-MemberComment $raw "runWithoutEnable"              "Bypass flag for the opmode enable check. When TRUE the block runs in automatic mode even if the opmode enable signal is not active. Use for commissioning only."
$raw = Add-MemberComment $raw "hideAlarmAll"                  "Global alarm suppression. When TRUE all ProDiag alarm messages are suppressed. Does not clear active faults, only prevents message annunciation. Typically driven by a plant-level inhibit."
$raw = Add-MemberComment $raw "hideAlarmMask"                 "32-bit individual alarm suppression mask. Each bit maps to one stateAlarm bit (bit 0 = spare0, bit 1 = hardwareNOK, etc.). Set a bit TRUE to suppress that alarm channel without affecting others."
$raw = Add-MemberComment $raw "OpModeUserInterfaceOut"        "Operating mode data from SYSTEM_DB.OPmode[N].User_Interface_OUT. Contains automaticActive, manualActive, singleStepActive flags and operator preselect requests used to drive mode-selection logic."
$raw = Add-MemberComment $raw "timeOperation"                 "Maximum allowed duration for a press operation cycle (IEC Time). If the sequence does not complete within this time, stateAlarm.timerMonitorRunSequence is set and the cycle is aborted."
$raw = Add-MemberComment $raw "timeExtStop"                   "Maximum time allowed for the extStopRequest signal to clear after it rises. If the signal remains TRUE beyond this time, a timeout fault is latched in stateAlarm."
$raw = Add-MemberComment $raw "parameters"                    "LDrive_typeKistlerParameters struct. Contains press axis travel limits, force window limits, jog speed, sequence timing parameters, and SmartClient configuration values."

# OUTPUT members
$raw = Add-MemberComment $raw "GeneralAlarm"                  "TRUE when any active unmasked fault condition exists. Drives ProDiag supervision alarm output. Must be FALSE for the ready output to be TRUE."
$raw = Add-MemberComment $raw "AutomaticActive"               "TRUE when the block is operating in automatic mode (opmode automatic active and enableBlock TRUE). Indicates the press is available for production cycles."
$raw = Add-MemberComment $raw "okTotal"                       "Pulses TRUE for one scan when the Kistler device reports an OK result for the last completed measurement (all evaluation channels within defined limits)."
$raw = Add-MemberComment $raw "nokTotal"                      "Pulses TRUE for one scan when the Kistler device reports a NOK result (at least one evaluation channel outside its defined limit window)."
$raw = Add-MemberComment $raw "noPass"                        "TRUE when the Kistler evaluation reports a no-pass condition for the current measurement program. Distinct from NOK -- indicates an evaluation rule was not met."
$raw = Add-MemberComment $raw "sequenceRunning"               "TRUE while a measurement sequence is actively executing on the press axis. Falls FALSE when the sequence completes, is stopped, or a fault occurs."
$raw = Add-MemberComment $raw "sequenceStopped"               "TRUE after a sequence was interrupted by extStopRequest or a manual stop command. Remains TRUE until cleared by SequenceEndReset rising edge."
$raw = Add-MemberComment $raw "Sequenceend"                   "Pulses TRUE for one scan when a sequence completes normally without fault. Cleared by SequenceEndReset rising edge or the start of a new cycle."
$raw = Add-MemberComment $raw "homePos"                       "TRUE when the press axis is confirmed at the home/retracted position within the home-position tolerance window defined in parameters."
$raw = Add-MemberComment $raw "referencePos"                  "TRUE when the press axis is confirmed at the reference/calibration position. Used to validate absolute position referencing after startup or reset."
$raw = Add-MemberComment $raw "waitContinue"                  "TRUE when the block is paused at a wait-for-operator step in the sequence. Cleared by a rising edge on the continuewait input."
$raw = Add-MemberComment $raw "ready"                         "TRUE when the block is fault-free, fully enabled, axis at home position, and ready to accept a new cycle trigger. The primary go/no-go signal for upstream sequence control."
$raw = Add-MemberComment $raw "pvCurrentValueX"               "Live X-axis process value from the Kistler sensor, typically press position in mm. Scaled from the raw fieldbus data using engineering unit conversion in the Process Values Mapping network."
$raw = Add-MemberComment $raw "pvCurrentValueY"               "Live Y-axis process value from the Kistler sensor, typically press force in kN. Scaled from the raw fieldbus data using engineering unit conversion in the Process Values Mapping network."
$raw = Add-MemberComment $raw "pvCurveXminX"                  "Lower X bound (position) of the active evaluation envelope window. Sourced from the current measurement program parameters on the Kistler device."
$raw = Add-MemberComment $raw "pvCurveXmaxX"                  "Upper X bound (position) of the active evaluation envelope window. Sourced from the current measurement program parameters on the Kistler device."
$raw = Add-MemberComment $raw "pvCurveYminY"                  "Lower Y bound (force) of the active evaluation envelope window. Sourced from the current measurement program parameters on the Kistler device."
$raw = Add-MemberComment $raw "pvCurveYmaxY"                  "Upper Y bound (force) of the active evaluation envelope window. Sourced from the current measurement program parameters on the Kistler device."
$raw = Add-MemberComment $raw "customeProcessValues"          "LDrive_typeKistlerProcessValues struct. Full result set from the Kistler evaluation: all channel measured values, individual pass/fail flags, peak force, peak position, and gradient data."
$raw = Add-MemberComment $raw "displayeservoJogSpeed"         "Current servo jog speed as a percentage (0-100%). Calculated from the active jog speed parameter and displayed on the HMI for operator awareness during manual axis movement."
$raw = Add-MemberComment $raw "standstill"                    "TRUE when the servo axis velocity is confirmed at zero by the drive. Safe condition for clamp operations or position checks that require the press to be stationary."
$raw = Add-MemberComment $raw "MeasurementProgramEcho"        "Echo of the currently active measurement program number confirmed by the Kistler device. Compare against mpNumber input to verify program selection was accepted."
$raw = Add-MemberComment $raw "currentLabel"                  "Current sequence step label number as reported by the Kistler device. Indicates which step in the press sequence is active. Used on HMI for step-level diagnostics."

# INOUT member
$raw = Add-MemberComment $raw "interfaceHmi"                  "Dynamic array of LDrive_typeKistlerHmi structs, one element per configured press channel. HMI reads status and process values from this array; operator commands and parameter adjustments are written back into it each scan."

Write-Host "Member comments injected."

# =============================================================================
# 2. NETWORK COMMENTS
#    Each CompileUnit ID=X has its en-US Comment item at ID=X+3 (all hex).
#    Pattern: find MultilingualTextItem ID="X+3" then replace its <Text /> with
#    <Text>comment</Text>.
# =============================================================================

function Set-NetworkComment {
    param([string]$xml, [string]$itemIdHex, [string]$comment)
    # Escape special regex chars in comment
    $escaped = [regex]::Escape($comment)
    $pattern = "(<MultilingualTextItem ID=""$itemIdHex"" CompositionName=""Items"">[\s\S]*?<Culture>en-US</Culture>\s*)<Text />"
    $replacement = "`$1<Text>$comment</Text>"
    $result = [regex]::Replace($xml, $pattern, $replacement)
    if ($result -eq $xml) { Write-Warning "Network comment not replaced for ID=$itemIdHex" }
    return $result
}

# Network comment item IDs (CompileUnit_ID + 3, hex) and their comments
# Net 1  ID=5   comment item=8
$raw = Set-NetworkComment $raw "8"   "DPRD_DAT reads the 200-byte cyclic receive telegram from the primary Kistler PROFINET device (hardwareID1) into statDataExchangeReceive. Return value stored in tempReturnValueRead for error checking in the next network."
# Net 2  ID=E   comment item=11
$raw = Set-NetworkComment $raw "11"  "Evaluates the DPRD_DAT return value. A non-zero value indicates a fieldbus communication fault; sets stateAlarm.transmissionFault to trigger the transmission fault alarm."
# Net 3  ID=17  comment item=1A
$raw = Set-NetworkComment $raw "1A"  "Latches the externalAlarm input into stateAlarm.alarm. Allows upstream logic or interlock signals to inject a fault into the Kistler block and drive GeneralAlarm."
# Net 4  ID=20  comment item=23
$raw = Set-NetworkComment $raw "23"  "Maps each bit of the hideAlarmMask DWord input to the corresponding member of the stateHideAlarm struct. Bit 0=spare0, bit 1=hardwareNOK, bit 2=transmissionFault, etc. Enables selective per-alarm suppression."
# Net 5  ID=29  comment item=2C
$raw = Set-NetworkComment $raw "2C"  "Applies alarm suppression logic. Each stateAlarm bit is ANDed with its stateHideAlarm counterpart (after applying hideAlarmAll). Result drives the active alarm state used in Fault General Alarm network."
# Net 6  ID=32  comment item=35
$raw = Set-NetworkComment $raw "35"  "Reads OpModeUserInterfaceOut and maps automaticActive, manualActive, singleStepActive, and setup mode flags into aux state variables. These aux flags gate downstream sequence and drive control networks."
# Net 7  ID=3B  comment item=3E
$raw = Set-NetworkComment $raw "3E"  "On a rising edge reset command from HMI or SequenceEndReset, clears all latched stateAlarm fault bits except hardware and safety faults. Resets GeneralAlarm provided no active hardware/safety faults remain."
# Net 8  ID=44  comment item=47
$raw = Set-NetworkComment $raw "47"  "Evaluates HardwareOK AND SafetyOK AND enableBlock to produce the drive enable command. Uses driveEnableTMR (TON) to debounce the enable rising edge and prevent spurious enable pulses during startup."
# Net 9  ID=4D  comment item=50
$raw = Set-NetworkComment $raw "50"  "Sets aux.remoteControl TRUE when the Kistler SmartClient is connected and active, as indicated by the remote-control status flag in statDataExchangeReceive. Enables SmartClient to override local control."
# Net 10 ID=56  comment item=59
$raw = Set-NetworkComment $raw "59"  "When aux.remoteControl is TRUE and automatic mode is active, writes the remote-automatic mode activation command into the transmit telegram. Allows SmartClient to initiate measurement sequences remotely."
# Net 11 ID=5F  comment item=62
$raw = Set-NetworkComment $raw "62"  "Writes mpNumber, SelectPageNumber, cfgAdd, and CfgLentgh values into the corresponding bytes of the statDataExchangeSend transmit telegram so the Kistler device loads the correct program, page, and configuration each scan."
# Net 12 ID=68  comment item=6B
$raw = Set-NetworkComment $raw "6B"  "Handles manual data strobe triggered from the HMI (aux.manualDataStrobe). Generates a one-scan strobe pulse in the transmit telegram to trigger a manual data capture on the Kistler device for test or debug purposes."
# Net 13 ID=71  comment item=74
$raw = Set-NetworkComment $raw "74"  "Detects the strobe acknowledgement bit in the Kistler receive telegram. Sets aux.dataStrobed when the device confirms data capture was completed. Used to synchronise strobe-based data exchange handshaking."
# Net 14 ID=7A  comment item=7D
$raw = Set-NetworkComment $raw "7D"  "Generates the automatic strobe pulse when strobeEnable is TRUE and a sequence is running. Sends the strobe command bit in the transmit telegram at the correct point in the sequence to trigger force/position data capture."
# Net 15 ID=83  comment item=86
$raw = Set-NetworkComment $raw "86"  "Detects the sequence-end condition from the Kistler receive telegram flags and latches aux.sequenceEnd. Provides the internal signal that feeds sequenceRunning state transitions and the Sequenceend output."
# Net 16 ID=8C  comment item=8F
$raw = Set-NetworkComment $raw "8F"  "Core sequence start logic. When aux.runSequence is TRUE, no active faults exist, and the block is in automatic mode, triggers the start command in the transmit telegram to begin the Kistler measurement sequence."
# Net 17 ID=95  comment item=98
$raw = Set-NetworkComment $raw "98"  "Serial number validation gate. Compares mpSerialNumber input against the serial number received from the Kistler device in statDataExchangeReceive. A mismatch latches stateAlarm.serialnumbermismatch and inhibits sequence start."
# Net 18 ID=9E  comment item=A1
$raw = Set-NetworkComment $raw "A1"  "Manages the sequenceRunning output state. Sets TRUE when the sequence start command is issued and clears when a sequence-end, extStopRequest, or fault condition is detected."
# Net 19 ID=A7  comment item=AA
$raw = Set-NetworkComment $raw "AA"  "Handles the startTL input. On rising edge, sends the teach-learn initiation command to the Kistler device via the transmit telegram and holds it until the TL completion acknowledgement is received."
# Net 20 ID=B0  comment item=B3
$raw = Set-NetworkComment $raw "B3"  "Runs the operation cycle timer (statInstruction.timeroperation) and other monitoring timers. If timeOperation expires during a running sequence, sets stateAlarm.timerMonitorRunSequence and aborts the cycle."
# Net 21 ID=B9  comment item=BC
$raw = Set-NetworkComment $raw "BC"  "Maps the selectSequence input byte into the correct field of the Kistler transmit telegram to command the device to load the specified measurement sequence profile."
# Net 22 ID=C2  comment item=C5
$raw = Set-NetworkComment $raw "C5"  "Handles the extStopRequest input. On rising edge, sends the stop command to the Kistler device, sets sequenceStopped, and starts the timeExtStop timer to monitor how long the stop condition persists."
# Net 23 ID=CB  comment item=CE
$raw = Set-NetworkComment $raw "CE"  "Resume after error. On rising edge of continuewait input, clears the waitContinue pause flag and allows the sequence to continue. Sends the continue command to the Kistler device and clears any latched soft-stop faults."
# Net 24 ID=D4  comment item=D7
$raw = Set-NetworkComment $raw "D7"  "Latches and maintains the Sequenceend output. Manages the state transition from sequenceRunning to cycle-complete, ensuring the end signal persists until explicitly reset by SequenceEndReset."
# Net 25 ID=DD  comment item=E0
$raw = Set-NetworkComment $raw "E0"  "Sets aux.SeqEnd and other internal sequence-completion flags used by downstream networks to trigger result processing, output updates, and data strobe for the completed press cycle."
# Net 26 ID=E6  comment item=E9
$raw = Set-NetworkComment $raw "E9"  "Home position return logic. When autoHomePosition is TRUE and the sequence has ended, or when a manual home command is received, drives the axis to home position and sets homePos TRUE once arrival is confirmed."
# Net 27 ID=EF  comment item=F2
$raw = Set-NetworkComment $raw "F2"  "Reference position drive logic. When autoDriveToReferencePosition is TRUE at startup/reset, or on a manual reference command, drives the axis to the calibration reference position and sets referencePos TRUE on arrival."
# Net 28 ID=F8  comment item=FB
$raw = Set-NetworkComment $raw "FB"  "JOG forward (pressing direction). While JogFwd is TRUE and the block is in manual/setup mode with drive enabled, sends the jog-forward command to the servo drive at the jog speed defined in parameters."
# Net 29 ID=101 comment item=104
$raw = Set-NetworkComment $raw "104" "JOG backward (retract direction). While JogNeq is TRUE and the block is in manual/setup mode with drive enabled, sends the jog-backward command to the servo drive at the jog speed defined in parameters."
# Net 30 ID=10A comment item=10D
$raw = Set-NetworkComment $raw "10D" "Extracts individual status flags, result bytes, and diagnostic words from the 200-byte statDataExchangeReceive buffer into named members of the aux and stateAlarm structs for use by control and alarm networks."
# Net 31 ID=113 comment item=116
$raw = Set-NetworkComment $raw "116" "Maps boolean signal bits from the Kistler fieldbus receive telegram bitfield words into named boolean members of the statDataExchangeReceive structure for clean access by downstream logic networks."
# Net 32 ID=11C comment item=11F
$raw = Set-NetworkComment $raw "11F" "DPWR_DAT writes the statDataExchangeSend transmit telegram to the secondary Kistler PROFINET device (hardwareID2). Called every scan to continuously update the device with current commands and configuration."
# Net 33 ID=125 comment item=128
$raw = Set-NetworkComment $raw "128" "Evaluates the DPWR_DAT return value. A non-zero value indicates a fieldbus write communication fault and sets stateAlarm.transmissionFault."
# Net 34 ID=12E comment item=131
$raw = Set-NetworkComment $raw "131" "Maps the sequence-end status flags and result summary to the HMI interface array (interfaceHmi) for display on the operator panel. Updates the end-of-cycle indication shown to the operator."
# Net 35 ID=137 comment item=13A
$raw = Set-NetworkComment $raw "13A" "Writes the fixed/static fieldbus output bytes that must always be present in the transmit telegram regardless of sequence state. These include protocol control bytes, enable flags, and constant configuration words."
# Net 36 ID=140 comment item=143
$raw = Set-NetworkComment $raw "143" "Scales raw fieldbus receive data into engineering units and maps to pvCurrentValueX (position mm), pvCurrentValueY (force kN), pvCurveXminX/XmaxX, pvCurveYminY/YmaxY, and the full customeProcessValues struct."
# Net 37 ID=149 comment item=14C
$raw = Set-NetworkComment $raw "14C" "Evaluates all stateAlarm struct bits against the corresponding stateHideAlarm mask bits and the global hideAlarmAll flag. Produces the final set of visible alarm conditions used by Evaluate Internal Alarms and Fault General Alarm."
# Net 38 ID=152 comment item=155
$raw = Set-NetworkComment $raw "155" "Processes internal fault conditions: driveenabledNOK, timerMonitorRunSequence, timerMonitorHomePos, timerMonitorReferencePos, noContinueWaitCommand, safetyNOK, smesActive, and serialnumbermismatch. Latches each into stateAlarm bits."
# Net 39 ID=15B comment item=15E
$raw = Set-NetworkComment $raw "15E" "OR-combines all active visible alarm bits into the GeneralAlarm output. Also sets aux.generalAlarm. GeneralAlarm TRUE blocks the ready output and drives ProDiag supervision to annunciate the fault."
# Net 40 ID=164 comment item=167
$raw = Set-NetworkComment $raw "167" "Writes the active alarm word and individual alarm bit states into the interfaceHmi array elements for HMI alarm display, acknowledgement, and remote reset functionality on the operator panel."

Write-Host "Network comments injected."

# =============================================================================
# 3. HEADER NETWORK
#    Insert a new SCL CompileUnit (documentation only) before the first network.
#    IDs are picked above the document maximum to avoid collisions.
# =============================================================================

$allIds = @()
foreach ($m in [regex]::Matches($raw, '\bID="([0-9A-Fa-f]+)"')) {
    try { $allIds += [Convert]::ToInt32($m.Groups[1].Value, 16) } catch {}
}
$maxId = [int](($allIds | Measure-Object -Maximum).Maximum)
$h1 = ($maxId + 1).ToString("X")
$h2 = ($maxId + 2).ToString("X")
$h3 = ($maxId + 3).ToString("X")
$h4 = ($maxId + 4).ToString("X")
$h5 = ($maxId + 5).ToString("X")
$h6 = ($maxId + 6).ToString("X")
$h7 = ($maxId + 7).ToString("X")
$h8 = ($maxId + 8).ToString("X")
$h9 = ($maxId + 9).ToString("X")
Write-Host "Max existing ID: $maxId  Header network ID: $h1"

$headerComment = @"
================================================================================
  LSicar_KistlerPress  --  Kistler Force/Press Monitor Interface Block
================================================================================

DESCRIPTION
  Standardised interface block for Kistler press-force monitoring systems
  connected via PROFINET IO. Manages the full press cycle: drive enabling,
  measurement program selection, sequence execution, force/position data
  extraction, result evaluation, and alarm annunciation.

  Communicates with the Kistler device using DPRD_DAT / DPWR_DAT over two
  PROFINET hardware identifiers (hardwareID1/hardwareID2) exchanging a
  200-byte cyclic telegram each scan.

FEATURES
  - Fieldbus I/O       : DPRD_DAT / DPWR_DAT cyclic 200-byte telegram exchange
  - Drive control      : Enable, jog forward/backward, home, reference position
  - Measurement        : MP selection, sequence start/stop, strobe, result capture
  - Result outputs     : OK/NOK/NoPass flags, X/Y process values, envelope bounds
  - Serial validation  : Workpiece serial number check before sequence start
  - Alarm management   : 18-bit stateAlarm struct, per-bit mask, global suppress
  - HMI interface      : Dynamic LDrive_typeKistlerHmi array for operator panel
  - Timeout monitoring : Operation cycle timer, ext-stop timeout

INTERFACE SUMMARY
  Input  : plantidentifier, CarrierID, mpSerialNumber, additionaAlarmText,
           tecUnitNumber, enableBlock, HardwareOK, SafetyOK, servoNotInstalled,
           hardwareID1, hardwareID2, smartClientIPAddress, mpNumber, cfgAdd,
           CfgLentgh, SelectPageNumber, selectSequence, extStopRequest,
           strobeEnable, startTL, autoRunSequence, autoHomePosition,
           autoDriveToReferencePosition, JogFwd, JogNeq, continuewait,
           SequenceEndReset, enableRunSequence, enablehomePos, externalAlarm,
           runWithoutEnable, hideAlarmAll, hideAlarmMask,
           OpModeUserInterfaceOut, timeOperation, timeExtStop, parameters
  InOut  : interfaceHmi (dynamic array of LDrive_typeKistlerHmi)
  Output : GeneralAlarm, AutomaticActive, okTotal, nokTotal, noPass,
           sequenceRunning, sequenceStopped, Sequenceend, homePos,
           referencePos, waitContinue, ready, pvCurrentValueX, pvCurrentValueY,
           pvCurveXminX, pvCurveXmaxX, pvCurveYminY, pvCurveYmaxY,
           customeProcessValues, displayeservoJogSpeed, standstill,
           MeasurementProgramEcho, currentLabel

NETWORK LAYOUT
  Net  1  Block Header -- documentation only (this network)
  Net  2  Read RAW Data from Kistler (SCL - DPRD_DAT)
  Net  3  Read OK -- DPRD_DAT error check
  Net  4  External Alarm
  Net  5  Set Hide Alarm -- mask mapping
  Net  6  Hide Alarm -- suppression logic
  Net  7  Mode Selection
  Net  8  Clear Faults
  Net  9  Enable the Drive
  Net 10  Control Remotely
  Net 11  Turn to Auto mode remotely
  Net 12  SetupMP and Pages
  Net 13  DataStrobe Manually
  Net 14  DataStrobe Acknowledged
  Net 15  Strobe data
  Net 16  Sequence End (detect)
  Net 17  Run the sequence
  Net 18  Validate Serial Before Running
  Net 19  Run Sequence (state)
  Net 20  Initiate TL Devices
  Net 21  Monitor Operation Timeouts
  Net 22  Select Sequence
  Net 23  SeqExtStopReq
  Net 24  Resume After Error
  Net 25  Sequence End (latch)
  Net 26  Flag Internal Seq End Flags
  Net 27  ReturnHomePos
  Net 28  DrivetoRefPos
  Net 29  JOG Forward
  Net 30  JOG Backward
  Net 31  Map Incoming Field Bus data (200 bytes)
  Net 32  Map Digital Signals
  Net 33  Write Raw Data to Kistler (DPWR_DAT)
  Net 34  Write OK -- DPWR_DAT error check
  Net 35  Display Seq END
  Net 36  Map Fixed Fieldbus outputs
  Net 37  Process Values Mapping
  Net 38  Alarms
  Net 39  Evaluate Internal Alarms
  Net 40  Fault General Alarm
  Net 41  Map Alarms to HMI Interface

VERSION HISTORY
  0.0.1  Initial release.
  0.0.2  Added block-header documentation network, interface member comments,
         and network comments on all 40 networks.

AUTHOR  : Amperesand
COMPANY : Amperesand Pte. Ltd.
LICENSE : Internal use only -- Amperesand Engineering
================================================================================
"@

$firstCU = '<SW.Blocks.CompileUnit ID="5" CompositionName="CompileUnits">'
$newNetwork = @"
      <SW.Blocks.CompileUnit ID="$h1" CompositionName="CompileUnits">
        <AttributeList>
          <NetworkSource><StructuredText xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/StructuredText/v4">
  <Token Text="REGION" UId="1" />
  <Blank UId="2" />
  <Text UId="3">Block Header</Text>
  <NewLine UId="4" />
  <Token Text="END_REGION" UId="5" />
</StructuredText></NetworkSource>
          <ProgrammingLanguage>SCL</ProgrammingLanguage>
        </AttributeList>
        <ObjectList>
          <MultilingualText ID="$h2" CompositionName="Comment">
            <ObjectList>
              <MultilingualTextItem ID="$h3" CompositionName="Items">
                <AttributeList>
                  <Culture>de-DE</Culture>
                  <Text />
                </AttributeList>
              </MultilingualTextItem>
              <MultilingualTextItem ID="$h4" CompositionName="Items">
                <AttributeList>
                  <Culture>en-US</Culture>
                  <Text>$headerComment</Text>
                </AttributeList>
              </MultilingualTextItem>
              <MultilingualTextItem ID="$h5" CompositionName="Items">
                <AttributeList>
                  <Culture>zh-CN</Culture>
                  <Text />
                </AttributeList>
              </MultilingualTextItem>
            </ObjectList>
          </MultilingualText>
          <MultilingualText ID="$h6" CompositionName="Title">
            <ObjectList>
              <MultilingualTextItem ID="$h7" CompositionName="Items">
                <AttributeList>
                  <Culture>de-DE</Culture>
                  <Text />
                </AttributeList>
              </MultilingualTextItem>
              <MultilingualTextItem ID="$h8" CompositionName="Items">
                <AttributeList>
                  <Culture>en-US</Culture>
                  <Text>Block Header</Text>
                </AttributeList>
              </MultilingualTextItem>
              <MultilingualTextItem ID="$h9" CompositionName="Items">
                <AttributeList>
                  <Culture>zh-CN</Culture>
                  <Text />
                </AttributeList>
              </MultilingualTextItem>
            </ObjectList>
          </MultilingualText>
        </ObjectList>
      </SW.Blocks.CompileUnit>

"@

$raw = $raw.Replace($firstCU, $newNetwork + $firstCU)

[System.IO.File]::WriteAllText($outXml, $raw, [System.Text.Encoding]::UTF8)
Write-Host "Written: $outXml"
$cuCount = [regex]::Matches($raw, '<SW\.Blocks\.CompileUnit ').Count
Write-Host "Total networks: $cuCount (was 40, +1 header)"
