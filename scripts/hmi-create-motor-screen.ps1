#Requires -Version 5.1
<#
.SYNOPSIS
    Create a Motor VFD control screen via TIA Portal Openness (HMI Unified).

.DESCRIPTION
    This script demonstrates the first verified end-to-end HMI Unified automation:
    1. Attach to a running TIA Portal Local Session.
    2. Create PLC tags in a new tag table.
    3. Create an HMI connection and HMI tags (best-effort external linkage).
    4. Create a new HMI screen with Buttons, Text labels, and I/O Fields.
    5. Set screen item text using the required XML-wrapped format.

.NOTES
    Verified on TIA Portal V20 with WinCC Unified Comfort Panel.
    Type paths reflect the actual V20 assembly namespace
    (Siemens.Engineering.HmiUnified.UI.*), NOT the older ModernUI namespace
    referenced in some manual editions.
#>

$ErrorActionPreference = 'Stop'

# =============================================================================
# 0. LOAD DLLs
# =============================================================================
$dllCore = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
$dllHmi  = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.Hmi.dll"

[System.Reflection.Assembly]::LoadFrom($dllCore) | Out-Null
[System.Reflection.Assembly]::LoadFrom($dllHmi)  | Out-Null
$asm = [System.Reflection.Assembly]::LoadFrom($dllCore)
Write-Host "[OK] DLLs loaded" -ForegroundColor Green

# =============================================================================
# Helpers
# =============================================================================
function Invoke-GenericGetService($target, $type) {
    $gsMethod = $target.GetType().GetMethods() |
        Where-Object { $_.Name -eq "GetService" -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 0 } |
        Select-Object -First 1
    if (-not $gsMethod) { return $null }
    try { return $gsMethod.MakeGenericMethod($type).Invoke($target, $null) } catch { return $null }
}

function Invoke-GenericCreate($composition, $type, $name) {
    $createMethod = $composition.GetType().GetMethods() |
        Where-Object { $_.Name -eq "Create" -and $_.IsGenericMethodDefinition } |
        Select-Object -First 1
    if (-not $createMethod) { throw "Generic Create method not found on $($composition.GetType().Name)" }
    $generic = $createMethod.MakeGenericMethod($type)
    return $generic.Invoke($composition, @($name))
}

function Set-XmlText($item, $plainText) {
    try {
        $textProp = $item.GetType().GetProperty("Text")
        if (-not $textProp) { return $false }
        $mlt = $textProp.GetValue($item, $null)
        if ($mlt -and $mlt.Items -and $mlt.Items.Count -gt 0) {
            $mlt.Items[0].Text = "<body><p>$plainText</p></body>"
            return $true
        }
    } catch {
        Write-Warning "Could not set text on $($item.Name): $($_.Exception.InnerException.Message)"
    }
    return $false
}

function Set-Property($obj, $name, $value) {
    try {
        $prop = $obj.GetType().GetProperty($name)
        if ($prop -and $prop.CanWrite) {
            $prop.SetValue($obj, $value, $null)
            return $true
        }
    } catch {
        Write-Warning "Failed to set $name on $($obj.GetType().Name): $($_.Exception.InnerException.Message)"
    }
    return $false
}

# =============================================================================
# 1. ATTACH TO TIA PORTAL (prefer UI process)
# =============================================================================
$processes = [Siemens.Engineering.TiaPortal]::GetProcesses()
$tiaProcess = $null
foreach ($p in $processes) {
    if ($p.Mode -eq [Siemens.Engineering.TiaPortalMode]::WithUserInterface) {
        $winProc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if ($winProc -and $winProc.MainWindowTitle.Trim().Length -gt 0) { $tiaProcess = $p; break }
    }
}
if (-not $tiaProcess) { $tiaProcess = $processes[0] }

Write-Host "Attaching to PID=$($tiaProcess.Id)..." -ForegroundColor Cyan
$tia = $tiaProcess.Attach()

# Local Session projects do not appear in tia.Projects
$project = $tia.LocalSessions[0].Project
Write-Host "[OK] Project: $($project.Name)" -ForegroundColor Green

# =============================================================================
# 2. FIND PLC AND HMI SOFTWARE
# =============================================================================
$plcSoftware = $null
$hmiSoftware = $null

function Walk-DeviceItems($items) {
    foreach ($item in $items) {
        $svc = Invoke-GenericGetService $item ([Siemens.Engineering.HW.Features.SoftwareContainer])
        if ($svc -and $svc.Software) {
            $sw = $svc.Software
            if ($sw -is [Siemens.Engineering.SW.PlcSoftware]) { $script:plcSoftware = $sw }
            if ($sw -is [Siemens.Engineering.HmiUnified.HmiSoftware]) { $script:hmiSoftware = $sw }
        }
        if ($item.DeviceItems -and $item.DeviceItems.Count -gt 0) { Walk-DeviceItems $item.DeviceItems }
    }
}
foreach ($device in $project.Devices) { Walk-DeviceItems $device.DeviceItems }

if (-not $plcSoftware) { throw "PLC not found in project" }
if (-not $hmiSoftware) { throw "HMI Unified not found in project" }

Write-Host "PLC: $($plcSoftware.Name)" -ForegroundColor Cyan
Write-Host "HMI: $($hmiSoftware.Name)" -ForegroundColor Cyan

# =============================================================================
# 3. CREATE PLC TAGS
# =============================================================================
Write-Host "`n=== PLC TAGS ===" -ForegroundColor Yellow

$plcTagTableName = "MotorVFD"
$plcTagTable = $plcSoftware.TagTableGroup.TagTables.Find($plcTagTableName)
if (-not $plcTagTable) {
    $plcTagTable = $plcSoftware.TagTableGroup.TagTables.Create($plcTagTableName)
    Write-Host "Created PLC tag table: $plcTagTableName" -ForegroundColor Green
} else {
    Write-Host "PLC tag table already exists: $plcTagTableName" -ForegroundColor Gray
}

$plcTagsToCreate = @(
    @{ Name="Motor_Start";        DataType="Bool";  Address="" },
    @{ Name="Motor_Stop";         DataType="Bool";  Address="" },
    @{ Name="Motor_Running";      DataType="Bool";  Address="" },
    @{ Name="Motor_Fault";        DataType="Bool";  Address="" },
    @{ Name="Motor_SpeedSetpoint";DataType="Real";  Address="" },
    @{ Name="Motor_ActualSpeed";  DataType="Real";  Address="" }
)

foreach ($tagInfo in $plcTagsToCreate) {
    $existing = $plcTagTable.Tags.Find($tagInfo.Name)
    if (-not $existing) {
        $plcTagTable.Tags.Create($tagInfo.Name, $tagInfo.DataType, $tagInfo.Address) | Out-Null
        Write-Host "  Created PLC tag: $($tagInfo.Name) ($($tagInfo.DataType))" -ForegroundColor Green
    } else {
        Write-Host "  PLC tag exists: $($tagInfo.Name)" -ForegroundColor Gray
    }
}

# =============================================================================
# 4. CREATE HMI CONNECTION (if none exists)
# =============================================================================
Write-Host "`n=== HMI CONNECTION ===" -ForegroundColor Yellow

$conn = $hmiSoftware.Connections | Select-Object -First 1
if (-not $conn) {
    try {
        $conn = $hmiSoftware.Connections.Create("HMI_Connection_1")
        Write-Host "Created connection: $($conn.Name)" -ForegroundColor Green
    } catch {
        Write-Warning "Could not create HMI connection: $_"
    }
} else {
    Write-Host "Using existing connection: $($conn.Name)" -ForegroundColor Gray
}

# =============================================================================
# 5. CREATE HMI TAGS (best-effort external linkage)
# =============================================================================
Write-Host "`n=== HMI TAGS ===" -ForegroundColor Yellow

$hmiTagTableName = "MotorVFD"
$hmiTagTable = $hmiSoftware.TagTables.Find($hmiTagTableName)
if (-not $hmiTagTable) {
    $hmiTagTable = $hmiSoftware.TagTables.Create($hmiTagTableName)
    Write-Host "Created HMI tag table: $hmiTagTableName" -ForegroundColor Green
} else {
    Write-Host "HMI tag table exists: $hmiTagTableName" -ForegroundColor Gray
}

foreach ($tagInfo in $plcTagsToCreate) {
    $existing = $hmiTagTable.Tags.Find($tagInfo.Name)
    if (-not $existing) {
        $hmiTag = $hmiTagTable.Tags.Create($tagInfo.Name)
        Write-Host "  Created HMI tag: $($tagInfo.Name)" -ForegroundColor Green

        if ($conn) {
            $connProp = $hmiTag.GetType().GetProperty("Connection")
            if ($connProp -and $connProp.CanWrite) {
                try { $connProp.SetValue($hmiTag, $conn, $null) } catch {}
            }
        }
        $addrNames = @("TagAddress","Address","PlcTag")
        foreach ($an in $addrNames) {
            $ap = $hmiTag.GetType().GetProperty($an)
            if ($ap -and $ap.CanWrite) {
                try {
                    $ap.SetValue($hmiTag, "$plcTagTableName.$($tagInfo.Name)", $null)
                    break
                } catch {}
            }
        }
    } else {
        Write-Host "  HMI tag exists: $($tagInfo.Name)" -ForegroundColor Gray
    }
}

# =============================================================================
# 6. CREATE HMI SCREEN
# =============================================================================
Write-Host "`n=== HMI SCREEN ===" -ForegroundColor Yellow

$screenName = "MotorControl"
$screen = $hmiSoftware.Screens.Find($screenName)
if ($screen) {
    Write-Host "Screen '$screenName' already exists. Deleting..." -ForegroundColor Yellow
    $screen.Delete()
}

$screen = $hmiSoftware.Screens.Create($screenName)
Write-Host "Created screen: $screenName" -ForegroundColor Green

Set-Property $screen "Width"  ([uint32]1280) | Out-Null
Set-Property $screen "Height" ([uint32]800) | Out-Null

$screenItems = $screen.ScreenItems

# Runtime type references (V20 assembly namespace)
$typeHmiText    = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Shapes.HmiText')
$typeHmiButton  = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton')
$typeHmiIOField = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField')

function Add-ElementItem($type, $name, $left, $top, $width, $height) {
    try {
        $item = Invoke-GenericCreate $screenItems $type $name
        Set-Property $item "Left"   $left   | Out-Null
        Set-Property $item "Top"    $top    | Out-Null
        Set-Property $item "Width"  ([uint32]$width)  | Out-Null
        Set-Property $item "Height" ([uint32]$height) | Out-Null
        return $item
    } catch {
        Write-Warning "Failed to create $name ($($type.Name)): $_"
        return $null
    }
}

# Layout
$items = @(
    @{ Type=$typeHmiText;    Name="Title_MotorVFD"; Left=50;  Top=20;  Width=400; Height=40; Text="Motor VFD Control" },
    @{ Type=$typeHmiButton;  Name="Btn_Start";      Left=50;  Top=100; Width=150; Height=60; Text="START" },
    @{ Type=$typeHmiButton;  Name="Btn_Stop";       Left=220; Top=100; Width=150; Height=60; Text="STOP" },
    @{ Type=$typeHmiText;    Name="Lbl_Setpoint";   Left=50;  Top=200; Width=160; Height=30; Text="Speed Setpoint:" },
    @{ Type=$typeHmiIOField; Name="IO_Setpoint";    Left=220; Top=200; Width=150; Height=30; ProcessValue="0.0" },
    @{ Type=$typeHmiText;    Name="Lbl_Actual";     Left=50;  Top=250; Width=160; Height=30; Text="Actual Speed:" },
    @{ Type=$typeHmiIOField; Name="IO_Actual";      Left=220; Top=250; Width=150; Height=30; ProcessValue="0.0" },
    @{ Type=$typeHmiText;    Name="Lbl_Status";     Left=50;  Top=300; Width=160; Height=30; Text="Status:" },
    @{ Type=$typeHmiIOField; Name="IO_Status";      Left=220; Top=300; Width=150; Height=30; ProcessValue="0" },
    @{ Type=$typeHmiText;    Name="Lbl_Running";    Left=50;  Top=350; Width=160; Height=30; Text="Running:" },
    @{ Type=$typeHmiIOField; Name="IO_Running";     Left=220; Top=350; Width=150; Height=30; ProcessValue="False" }
)

foreach ($def in $items) {
    $item = Add-ElementItem $def.Type $def.Name $def.Left $def.Top $def.Width $def.Height
    if ($item) {
        if ($def.ContainsKey("Text") -and $def.Text) {
            Set-XmlText $item $def.Text | Out-Null
        }
        if ($def.ContainsKey("ProcessValue")) {
            Set-Property $item "ProcessValue" $def.ProcessValue | Out-Null
        }
        Write-Host "  Added $($def.Name)" -ForegroundColor Gray
    }
}

Write-Host "`n[OK] MotorControl screen created with items." -ForegroundColor Green
Write-Host "`nNOTE: To fully link HMI tags to PLC tags, open TIA Portal and:" -ForegroundColor Yellow
Write-Host "  1. Verify HMI connection 'HMI_Connection_1' points to PLC_1." -ForegroundColor Yellow
Write-Host "  2. Check HMI tags in table 'MotorVFD' have correct PLC addresses." -ForegroundColor Yellow
Write-Host "  3. Dynamize screen items to HMI tags via properties/events." -ForegroundColor Yellow
Write-Host "`nDone." -ForegroundColor Green
