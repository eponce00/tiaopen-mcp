# add-kistler-supervisions.ps1
# ============================================================
# Patches LSicar_KistlerPress_improved.xml with:
#   1. Warning_No_PD : Array[1..12] of Int  (in Static section)
#   2. plantIdentifierEmpty : Bool           (in aux struct)
#   3. Full <Supervisions> XML block         (14 supervisions)
#
# Supervision design:
#   6 Alarms  (Cat=1) - inline text, conditions on enableBlock + hideAlarm
#   6 Warnings(Cat=2) - inline text, conditions on enableBlock where applicable
#   2 MessageError    - Kistler alarm channel passthrough
#
# NOTE: After import, add this SCL line in the ProDiag network:
#   aux.plantIdentifierEmpty := (plantidentifier = WSTRING#'');
# ============================================================

$base    = 'C:\Users\MudasserWahab\Claude Code'
$inFile  = Join-Path $base 'LSicar_KistlerPress_improved.xml'
$outFile = Join-Path $base 'LSicar_KistlerPress_with_supervisions.xml'

if (-not (Test-Path $inFile)) { Write-Error "Input not found: $inFile"; exit 1 }

Write-Host "Reading $inFile ..."
$xml = [System.IO.File]::ReadAllText($inFile, [System.Text.Encoding]::UTF8)

$crlf = $xml.Contains("`r`n")
$NL   = if ($crlf) { "`r`n" } else { "`n" }

function Find-Anchor([string]$xml, [string]$anchor) {
    $pos = $xml.IndexOf($anchor)
    if ($pos -ge 0) { return @{ pos = $pos; len = $anchor.Length } }
    $alt = $anchor.Replace("`r`n", "`n").Replace("`n", "`r`n")
    $pos = $xml.IndexOf($alt)
    if ($pos -ge 0) { return @{ pos = $pos; len = $alt.Length } }
    $alt2 = $anchor.Replace("`r`n", "`n")
    $pos  = $xml.IndexOf($alt2)
    if ($pos -ge 0) { return @{ pos = $pos; len = $alt2.Length } }
    return $null
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1.  Warning_No_PD : Array[1..12] of Int
# ═══════════════════════════════════════════════════════════════════════════════
if ($xml.Contains('Warning_No_PD')) {
    Write-Host '  [SKIP] Warning_No_PD already present'
} else {
    $anchor1 = "  </Section>${NL}  <Section Name=""Temp"">"
    $found1  = Find-Anchor $xml $anchor1
    if ($null -eq $found1) { Write-Error 'Cannot find Static-section close / Temp-section open anchor'; exit 1 }

    $warningNoPd = @"
    <Member Name="Warning_No_PD" Datatype="Array[1..12] of Int">
      <AttributeList>
        <BooleanAttribute Name="ExternalAccessible" SystemDefined="true">false</BooleanAttribute>
        <BooleanAttribute Name="ExternalVisible" SystemDefined="true">false</BooleanAttribute>
        <BooleanAttribute Name="ExternalWritable" SystemDefined="true">false</BooleanAttribute>
      </AttributeList>
    </Member>
${NL}
"@
    $xml = $xml.Insert($found1.pos, $warningNoPd)
    Write-Host '  [OK] Inserted Warning_No_PD Array[1..12] of Int into Static section'
}

# ═══════════════════════════════════════════════════════════════════════════════
# 2.  plantIdentifierEmpty : Bool
# ═══════════════════════════════════════════════════════════════════════════════
if ($xml.Contains('plantIdentifierEmpty')) {
    Write-Host '  [SKIP] plantIdentifierEmpty already present'
} else {
    $anchor2 = @"
      <Member Name="internalAlarmPdNoChange" Datatype="Bool">
        <StartValue>false</StartValue>
      </Member>
"@
    $found2 = Find-Anchor $xml $anchor2
    if ($null -eq $found2) { Write-Error 'Cannot find internalAlarmPdNoChange member anchor'; exit 1 }

    $plantIdEmpty = @"
      <Member Name="plantIdentifierEmpty" Datatype="Bool">
        <StartValue>false</StartValue>
      </Member>
"@
    $insertAt2 = $found2.pos + $found2.len
    $xml = $xml.Insert($insertAt2, "${NL}${plantIdEmpty}")
    Write-Host '  [OK] Inserted plantIdentifierEmpty Bool into aux struct'
}

# ═══════════════════════════════════════════════════════════════════════════════
# 3.  <Supervisions> XML block
# ═══════════════════════════════════════════════════════════════════════════════
if ($xml.Contains('<Supervisions>')) {
    Write-Host '  [SKIP] Supervisions block already present'
} else {
    $anchor3 = '<SetENOAutomatically>false</SetENOAutomatically>'
    $found3  = Find-Anchor $xml $anchor3
    if ($null -eq $found3) { Write-Error 'Cannot find SetENOAutomatically anchor'; exit 1 }

    # ─────────────────────────────────────────────────────────────────────────
    # Helper: Operand supervision with inline text
    # Text uses @5%s@ = AV#2 = #plantidentifier
    # No text list lookup - description is embedded directly in SpecificFieldText
    # Conditions:
    #   - alarms (Cat=1): Cond1=#enableBlock=true, Cond2=#statHideAlarmMessagesPD=false
    #   - safetyNOK: no conditions (safety must always fire regardless of block state)
    #   - warnings (Cat=2): Cond1=#enableBlock=true where applicable, else empty
    # ─────────────────────────────────────────────────────────────────────────
    function OperandSup {
        param(
            [int]   $Num,
            [string]$Operand,
            [string]$Status,
            [int]   $Cat,
            [int]   $Sub1,
            [int]   $PdSlot,
            [string]$InlineText,
            [string]$Cond1 = '',
            [string]$Cond1Status = 'true',
            [string]$Cond2 = '',
            [string]$Cond2Status = 'true',
            [string]$Cond3 = '',
            [string]$Cond3Status = 'true'
        )
        return @"
  <BlockTypeSupervision Number="$Num" Type="Operand">
    <SupervisedOperand Name="#$Operand" />
    <SupervisedStatus>$Status</SupervisedStatus>
    <DelayOperand Name="T#0ms" />
    <Conditions>
      <Condition>
        <ConditionOperand Number="1" Name="$Cond1" />
        <TriggeringStatus>$Cond1Status</TriggeringStatus>
      </Condition>
      <Condition>
        <ConditionOperand Number="2" Name="$Cond2" />
        <TriggeringStatus>$Cond2Status</TriggeringStatus>
      </Condition>
      <Condition>
        <ConditionOperand Number="3" Name="$Cond3" />
        <TriggeringStatus>$Cond3Status</TriggeringStatus>
      </Condition>
    </Conditions>
    <CategoryNumber>$Cat</CategoryNumber>
    <SubCategory1Number>$Sub1</SubCategory1Number>
    <SubCategory2Number>7</SubCategory2Number>
    <SpecificField>
      <AssociatedValues>
        <AssociatedValue>
          <AssociatedValueOperand Number="1" Name="#Warning_No_PD[$PdSlot]" />
        </AssociatedValue>
        <AssociatedValue>
          <AssociatedValueOperand Number="2" Name="#plantidentifier" />
        </AssociatedValue>
      </AssociatedValues>
      <SpecificFieldText>
        <MultiLanguageText Lang="en-US">$InlineText</MultiLanguageText>
      </SpecificFieldText>
    </SpecificField>
  </BlockTypeSupervision>
"@
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Helper: MessageError supervision (Kistler alarm number passthrough)
    # AV#1 = alarm number (statAlarmNoPD / statInternalAlarmNoPD)
    # AV#2 = plantidentifier
    # Inline text shows plant ID + fixed label; ProDiag detail shows alarm number
    # ─────────────────────────────────────────────────────────────────────────
    function MsgErrorSup {
        param(
            [int]   $Num,
            [string]$Cond1,
            [string]$Cond1Status,
            [string]$Cond2 = '',
            [string]$Cond2Status = 'true',
            [string]$Cond3,
            [string]$Cond3Status,
            [string]$AV1
        )
        return @"
  <BlockTypeSupervision Number="$Num" Type="MessageError">
    <SupervisedOperand Name="#GeneralAlarm" />
    <SupervisedStatus>true</SupervisedStatus>
    <DelayOperand Name="T#0ms" />
    <Conditions>
      <Condition>
        <ConditionOperand Number="1" Name="$Cond1" />
        <TriggeringStatus>$Cond1Status</TriggeringStatus>
      </Condition>
      <Condition>
        <ConditionOperand Number="2" Name="$Cond2" />
        <TriggeringStatus>$Cond2Status</TriggeringStatus>
      </Condition>
      <Condition>
        <ConditionOperand Number="3" Name="$Cond3" />
        <TriggeringStatus>$Cond3Status</TriggeringStatus>
      </Condition>
    </Conditions>
    <CategoryNumber>1</CategoryNumber>
    <SubCategory1Number>1</SubCategory1Number>
    <SubCategory2Number>7</SubCategory2Number>
    <SpecificField>
      <AssociatedValues>
        <AssociatedValue>
          <AssociatedValueOperand Number="1" Name="#$AV1" />
        </AssociatedValue>
        <AssociatedValue>
          <AssociatedValueOperand Number="2" Name="#plantidentifier" />
        </AssociatedValue>
      </AssociatedValues>
      <SpecificFieldText>
        <MultiLanguageText Lang="en-US">@5%s@: Kistler device alarm</MultiLanguageText>
      </SpecificFieldText>
    </SpecificField>
  </BlockTypeSupervision>
"@
    }

    # ─────────────────────────────────────────────────────────────────────────
    # ALARMS  Cat=1 / Sub1=2   (6 supervisions, PD slots 1..6)
    # Conditions: #enableBlock=TRUE + #statHideAlarmMessagesPD=FALSE
    # Exception: safetyNOK has NO conditions - must always fire
    # ─────────────────────────────────────────────────────────────────────────
    $s06 = OperandSup 6  'stateAlarm.hardwareNOK'       'true' 1 2 1 `
               '@5%s@: Hardware fault' `
               '#enableBlock' 'true' '#statHideAlarmMessagesPD' 'false'

    $s08 = OperandSup 8  'stateAlarm.safetyNOK'         'true' 1 2 2 `
               '@5%s@: Safety circuit open'
               # no conditions - safety must always fire

    $s09 = OperandSup 9  'stateAlarm.driveenabledNOK'   'true' 1 2 3 `
               '@5%s@: Drive not enabled' `
               '#enableBlock' 'true' '#statHideAlarmMessagesPD' 'false'

    $s10 = OperandSup 10 'stateAlarm.transmissionFault' 'true' 1 2 4 `
               '@5%s@: Kistler comm fault' `
               '#enableBlock' 'true' '#statHideAlarmMessagesPD' 'false'

    $s12 = OperandSup 12 'stateAlarm.timerMonitorRunSequence' 'true' 1 2 5 `
               '@5%s@: Press cycle timeout' `
               '#enableBlock' 'true' '#statHideAlarmMessagesPD' 'false'

    $s18 = OperandSup 18 'stateAlarm.alarm'             'true' 1 2 6 `
               '@5%s@: Kistler alarm active' `
               '#enableBlock' 'true' '#statHideAlarmMessagesPD' 'false'

    # ─────────────────────────────────────────────────────────────────────────
    # WARNINGS  Cat=2   (6 supervisions, PD slots 7..12)
    #
    # #20  enableBlock=FALSE    - no conditions (we ARE watching enableBlock)
    # #22  plantIdentifierEmpty - Cond1: #enableBlock=TRUE
    # #24  serialnumbermismatch - Cond1: #enableBlock=TRUE
    # #26  remoteControlNotActive - Cond1: #enableBlock=TRUE
    # #27  noContinueWaitCommand  - Cond1: #enableBlock=TRUE
    # #32  smesActive           - no conditions (safety state, always visible)
    # ─────────────────────────────────────────────────────────────────────────
    $s20 = OperandSup 20 'enableBlock'                       'false' 2 4  7 `
               '@5%s@: Block disabled'
               # no conditions - cannot condition on enableBlock when watching it

    $s22 = OperandSup 22 'aux.plantIdentifierEmpty'          'true'  2 4  8 `
               '@5%s@: Plant ID not configured' `
               '#enableBlock' 'true'

    $s24 = OperandSup 24 'stateAlarm.serialnumbermismatch'   'true'  2 3  9 `
               '@5%s@: Serial number mismatch' `
               '#enableBlock' 'true'

    $s26 = OperandSup 26 'stateAlarm.remoteControlNotActive' 'true'  2 4 10 `
               '@5%s@: Remote control inactive' `
               '#enableBlock' 'true'

    $s27 = OperandSup 27 'stateAlarm.noContinueWaitCommand'  'true'  2 3 11 `
               '@5%s@: Waiting for continue command' `
               '#enableBlock' 'true'

    $s32 = OperandSup 32 'stateAlarm.smesActive'             'true'  2 3 12 `
               '@5%s@: Safety mode active (SMES)'
               # no conditions - safety mode state is always relevant

    # ─────────────────────────────────────────────────────────────────────────
    # MESSAGE ERRORS  Cat=1 / Sub1=1  (2 supervisions, Kistler alarm channel)
    # Cond1: #statHideAlarmMessagesPD=FALSE
    # Cond3: no-change guard (prevents re-trigger on same scan)
    # ─────────────────────────────────────────────────────────────────────────
    $s36 = MsgErrorSup 36 `
               '#statHideAlarmMessagesPD' 'false' `
               '' 'true' `
               '#aux.alarmPdNoChange' 'true' `
               'statAlarmNoPD'

    $s38 = MsgErrorSup 38 `
               '#statHideAlarmMessagesPD' 'false' `
               '' 'true' `
               '#aux.internalAlarmPdNoChange' 'true' `
               'statInternalAlarmNoPD'

    $supervisionsBlock = @"

      <Supervisions><BlockTypeSupervisions xmlns="http://www.siemens.com/automation/Openness/SW/BlockTypeSupervisions/v3">
$s06$s08$s09$s10$s12$s18$s20$s22$s24$s26$s27$s32$s36$s38</BlockTypeSupervisions></Supervisions>
"@

    $insertAt3 = $found3.pos + $found3.len
    $xml = $xml.Insert($insertAt3, $supervisionsBlock)
    Write-Host '  [OK] Inserted Supervisions block (14 supervisions: 6 alarms + 6 warnings + 2 MessageErrors)'
}

# ═══════════════════════════════════════════════════════════════════════════════
# Write output
# ═══════════════════════════════════════════════════════════════════════════════
[System.IO.File]::WriteAllText($outFile, $xml, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Output: $outFile"
Write-Host ""
Write-Host "Supervision summary:"
Write-Host "  ALARMS  (Cat=1, Sub2=7, inline text, conditions: enableBlock + hideAlarm)"
Write-Host "    #6  stateAlarm.hardwareNOK        -> '@5%s@: Hardware fault'"
Write-Host "    #8  stateAlarm.safetyNOK           -> '@5%s@: Safety circuit open'  [no conditions]"
Write-Host "    #9  stateAlarm.driveenabledNOK     -> '@5%s@: Drive not enabled'"
Write-Host "    #10 stateAlarm.transmissionFault   -> '@5%s@: Kistler comm fault'"
Write-Host "    #12 stateAlarm.timerMonitorRunSeq  -> '@5%s@: Press cycle timeout'"
Write-Host "    #18 stateAlarm.alarm               -> '@5%s@: Kistler alarm active'"
Write-Host ""
Write-Host "  WARNINGS (Cat=2, Sub2=7, inline text, condition: enableBlock where applicable)"
Write-Host "    #20 enableBlock=FALSE              -> '@5%s@: Block disabled'          [no conditions]"
Write-Host "    #22 aux.plantIdentifierEmpty       -> '@5%s@: Plant ID not configured'"
Write-Host "    #24 stateAlarm.serialnumbermismatch-> '@5%s@: Serial number mismatch'"
Write-Host "    #26 stateAlarm.remoteControlNotActive -> '@5%s@: Remote control inactive'"
Write-Host "    #27 stateAlarm.noContinueWaitCommand  -> '@5%s@: Waiting for continue command'"
Write-Host "    #32 stateAlarm.smesActive          -> '@5%s@: Safety mode active (SMES)' [no conditions]"
Write-Host ""
Write-Host "  MESSAGE ERRORS (Cat=1, Sub1=1, Sub2=7, Kistler alarm channel passthrough)"
Write-Host "    #36 GeneralAlarm / statAlarmNoPD          -> '@5%s@: Kistler device alarm'"
Write-Host "    #38 GeneralAlarm / statInternalAlarmNoPD  -> '@5%s@: Kistler device alarm'"
Write-Host ""
Write-Host "NEXT STEPS:"
Write-Host "  1. Run: release_library_type LSicar_KistlerPress v0.0.8"
Write-Host "  2. In TIA Portal ProDiag network (SCL):"
Write-Host "       aux.plantIdentifierEmpty := (plantidentifier = WSTRING#'');"
