param(
    [Parameter(Mandatory)][string]$Template,
    [Parameter(Mandatory)][string]$BlockName,
    [string]$BlockNumber     = "100",
    [string]$BlockType       = "SW.Blocks.FC",
    [string]$NetworkTitle    = "Network 1",
    [string]$InputArea       = "Input",
    [string]$InputBitOffset  = "0",
    [string]$OutputArea      = "Output",
    [string]$OutputBitOffset = "0",
    [string]$SclBody         = "",
    # TON / timer tokens
    [string]$EnableArea      = "Input",
    [string]$EnableBitOffset = "0",
    [string]$DoneArea        = "Output",
    [string]$DoneBitOffset   = "0",
    [string]$PresetTime      = "T#5S",
    [string]$TimerDB         = "IEC_Timer_0_DB",
    # MOVE / comparison tokens
    [string]$SrcArea         = "Input",
    [string]$SrcBitOffset    = "0",
    [string]$DstArea         = "Output",
    [string]$DstBitOffset    = "0",
    [string]$DataType        = "Int",
    # Parallel-or tokens
    [string]$Input1Area      = "Input",
    [string]$Input1BitOffset = "0",
    [string]$Input2Area      = "Input",
    [string]$Input2BitOffset = "1",
    [string]$Output2Area     = "Output",
    [string]$Output2BitOffset = "1",
    # Compare tokens
    [string]$In1Area         = "Input",
    [string]$In1BitOffset    = "0",
    [string]$In1Type         = "Int",
    [string]$In2Area         = "Input",
    [string]$In2BitOffset    = "2",
    [string]$In2Type         = "Int",
    # SCL if-then tokens (legacy single-token approach, kept for compatibility)
    [string]$SclCondition    = "TRUE",
    [string]$SclThen         = ";",
    [string]$SclElse         = ";",
    # SCL if-then structured tokens (GlobalVariable + LiteralConstant approach)
    [string]$ConditionTag    = "Tag_1",
    [string]$OutputTag       = "Tag_2",
    [string]$ThenValue       = "TRUE",
    [string]$ElseValue       = "FALSE",
    # FBD/LAD block call tokens
    [string]$FbName          = "FB_Simple",
    [string]$InstanceDB      = "DB_Simple",
    [string]$CalleeFc        = "FC_Target",
    # CTU counter tokens
    [string]$CounterDB       = "IEC_Counter_0_DB",
    # Calculate tokens
    [string]$CalcEquation    = "IN1 + IN2",
    [string]$ProjectMatch    = "Testing_Playground",
    [switch]$SkipCompile,
    [switch]$DryRun          # Print resolved XML to stdout, do not import
)

# Instantiates a template from the templates/ folder, substitutes tokens,
# optionally imports it into TIA Portal, and reports compile result as JSON.
#
# -Template  : relative or absolute path to a template XML (e.g. templates\lad\contact-coil.xml)
# -DryRun    : print resolved XML to stdout without touching TIA
#
# Available tokens in templates:
#   {{BLOCK_NAME}}, {{BLOCK_NUMBER}}, {{BLOCK_TYPE}}, {{NETWORK_TITLE}},
#   {{INPUT_AREA}}, {{INPUT_BITOFFSET}}, {{OUTPUT_AREA}}, {{OUTPUT_BITOFFSET}},
#   {{SCL_BODY}}
#
# Usage examples:
#   .\scripts\new-block.ps1 -Template templates\lad\contact-coil.xml `
#       -BlockName FC_RunMotor -BlockNumber 200 -BlockType SW.Blocks.FC `
#       -InputArea Input -InputBitOffset 8 -OutputArea Output -OutputBitOffset 8
#
#   .\scripts\new-block.ps1 -Template templates\scl\fc-skeleton.xml `
#       -BlockName FC_Calc -BlockNumber 201 -SclBody ";" -DryRun

$ErrorActionPreference = "Stop"

# ── Resolve template ─────────────────────────────────────────────────────────
$templatePath = [System.IO.Path]::GetFullPath($Template)
if (-not (Test-Path $templatePath)) {
    Write-Error "Template not found: $templatePath"
    exit 1
}

$xml = Get-Content $templatePath -Raw

# ── XML-escape values that land inside XML attributes (SCL bodies) ───────────
function ConvertTo-XmlAttributeValue([string]$s) {
    $s = $s -replace '&', '&amp;'
    $s = $s -replace '<', '&lt;'
    $s = $s -replace '>', '&gt;'
    $s = $s -replace '"', '&quot;'
    $s = $s -replace "`r`n", '&#10;'
    $s = $s -replace "`n", '&#10;'
    $s = $s -replace "`r", '&#10;'
    return $s
}
$SclBody      = ConvertTo-XmlAttributeValue $SclBody
$SclCondition = ConvertTo-XmlAttributeValue $SclCondition
$SclThen      = ConvertTo-XmlAttributeValue $SclThen
$SclElse      = ConvertTo-XmlAttributeValue $SclElse

# ── Token substitution ───────────────────────────────────────────────────────
$tokens = @{
    '{{BLOCK_NAME}}'       = $BlockName
    '{{BLOCK_NUMBER}}'     = $BlockNumber
    '{{BLOCK_TYPE}}'       = $BlockType
    '{{NETWORK_TITLE}}'    = $NetworkTitle
    '{{INPUT_AREA}}'       = $InputArea
    '{{INPUT_BITOFFSET}}'  = $InputBitOffset
    '{{OUTPUT_AREA}}'      = $OutputArea
    '{{OUTPUT_BITOFFSET}}' = $OutputBitOffset
    '{{SCL_BODY}}'         = $SclBody
    '{{ENABLE_AREA}}'      = $EnableArea
    '{{ENABLE_BITOFFSET}}' = $EnableBitOffset
    '{{DONE_AREA}}'        = $DoneArea
    '{{DONE_BITOFFSET}}'   = $DoneBitOffset
    '{{PRESET_TIME}}'      = $PresetTime
    '{{TIMER_DB}}'         = $TimerDB
    '{{SRC_AREA}}'         = $SrcArea
    '{{SRC_BITOFFSET}}'    = $SrcBitOffset
    '{{DST_AREA}}'         = $DstArea
    '{{DST_BITOFFSET}}'    = $DstBitOffset
    '{{DATA_TYPE}}'        = $DataType
    '{{INPUT1_AREA}}'      = $Input1Area
    '{{INPUT1_BITOFFSET}}' = $Input1BitOffset
    '{{INPUT2_AREA}}'      = $Input2Area
    '{{INPUT2_BITOFFSET}}' = $Input2BitOffset
    '{{OUTPUT2_AREA}}'     = $Output2Area
    '{{OUTPUT2_BITOFFSET}}' = $Output2BitOffset
    '{{IN1_AREA}}'         = $In1Area
    '{{IN1_BITOFFSET}}'    = $In1BitOffset
    '{{IN1_TYPE}}'         = $In1Type
    '{{IN2_AREA}}'         = $In2Area
    '{{IN2_BITOFFSET}}'    = $In2BitOffset
    '{{IN2_TYPE}}'         = $In2Type
    '{{SCL_CONDITION}}'    = $SclCondition
    '{{SCL_THEN}}'         = $SclThen
    '{{SCL_ELSE}}'         = $SclElse
    '{{CONDITION_TAG}}'    = $ConditionTag
    '{{OUTPUT_TAG}}'       = $OutputTag
    '{{THEN_VALUE}}'       = $ThenValue
    '{{ELSE_VALUE}}'       = $ElseValue
    '{{FB_NAME}}'          = $FbName
    '{{INSTANCE_DB}}'      = $InstanceDB
    '{{CALLEE_FC}}'        = $CalleeFc
    '{{COUNTER_DB}}'       = $CounterDB
    '{{CALC_EQUATION}}'    = $CalcEquation
}
foreach ($token in $tokens.Keys) {
    $xml = $xml.Replace($token, $tokens[$token])
}

# ── Dry run ──────────────────────────────────────────────────────────────────
if ($DryRun) {
    Write-Output $xml
    exit 0
}

# ── Write to temp file ───────────────────────────────────────────────────────
$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

$tmpFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.xml'
try {
    [System.IO.File]::WriteAllText($tmpFile, $xml, [System.Text.Encoding]::UTF8)

    # ── Helpers ──────────────────────────────────────────────────────────────
    function Invoke-GenericGetService {
        param($Instance, [Type]$ServiceType)
        $method = $Instance.GetType().GetMethods() |
            Where-Object { $_.Name -eq "GetService" -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 0 } |
            Select-Object -First 1
        if (-not $method) { return $null }
        try { return $method.MakeGenericMethod($ServiceType).Invoke($Instance, $null) } catch { return $null }
    }

    function Find-PlcSoftware {
        param($Project)
        $ct = [Siemens.Engineering.HW.Features.SoftwareContainer]
        foreach ($device in $Project.Devices) {
            $r = Search-Items $device.DeviceItems $ct
            if ($r) { return $r }
        }
        return $null
    }

    function Search-Items {
        param($Items, [Type]$CT)
        foreach ($item in $Items) {
            $svc = Invoke-GenericGetService $item $CT
            if ($svc -and $svc.Software -is [Siemens.Engineering.SW.PlcSoftware]) { return $svc.Software }
            $n = Search-Items $item.DeviceItems $CT
            if ($n) { return $n }
        }
        return $null
    }

    # ── Attach ───────────────────────────────────────────────────────────────
    $tiaProcess = $null
    foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
        if ($p.Mode -ne [Siemens.Engineering.TiaPortalMode]::WithUserInterface) { continue }
        $wp = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if ($wp.MainWindowTitle -match $ProjectMatch) { $tiaProcess = $p; break }
    }
    if (-not $tiaProcess) { Write-Error "No UI TIA process matching '$ProjectMatch' found."; exit 1 }

    $tia = $tiaProcess.Attach()
    try {
        $project = $tia.Projects | Where-Object { $_.Name -match $ProjectMatch } | Select-Object -First 1
        if (-not $project) { $project = $tia.Projects[0] }
        $plc = Find-PlcSoftware -Project $project
        if (-not $plc) { Write-Error "PlcSoftware not found."; exit 1 }

        # ── Import ────────────────────────────────────────────────────────────
        $fileInfo = [System.IO.FileInfo]::new($tmpFile)
        $plc.BlockGroup.Blocks.Import($fileInfo, [Siemens.Engineering.ImportOptions]::Override) | Out-Null

        $result = [ordered]@{ Template = $Template; BlockName = $BlockName; Imported = $true
                               Compiled = $false; State = $null; Errors = 0; Warnings = 0; Messages = @() }

        if (-not $SkipCompile) {
            $compiler = Invoke-GenericGetService $plc ([Siemens.Engineering.Compiler.ICompilable])
            if (-not $compiler) { Write-Error "ICompilable service not found."; exit 1 }

            $cr       = $compiler.GetType().GetMethod("Compile").Invoke($compiler, $null)
            $rt       = $cr.GetType()
            $state    = $rt.GetProperty("State").GetValue($cr, $null).ToString()
            $messages = $rt.GetProperty("Messages").GetValue($cr, $null)

            $msgList  = @(); $errCount = 0; $wrnCount = 0
            foreach ($msg in $messages) {
                $mt     = $msg.GetType()
                $mState = $mt.GetProperty("State").GetValue($msg, $null).ToString()
                $mPath  = $mt.GetProperty("Path").GetValue($msg, $null)
                $mDesc  = $mt.GetProperty("Description").GetValue($msg, $null)
                if ($mState -eq "Error")   { $errCount++ }
                if ($mState -eq "Warning") { $wrnCount++ }
                if ($mDesc) {
                    $msgList += [ordered]@{
                        State = $mState
                        Path  = if ($mPath) { $mPath.ToString() } else { $null }
                        Description = $mDesc.ToString()
                    }
                }
            }
            $result.Compiled = $true
            $result.State    = $state
            $result.Errors   = $errCount
            $result.Warnings = $wrnCount
            $result.Messages = $msgList
        }

        $result | ConvertTo-Json -Depth 5
        if ($result.State -eq "Error") { exit 1 }
    } finally {
        $tia.Dispose()
    }
} finally {
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
}
