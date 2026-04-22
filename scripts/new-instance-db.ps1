param(
    [Parameter(Mandatory)][string]$DBName,        # Name for the new instance DB, e.g. "IEC_Timer_1_DB"
    [Parameter(Mandatory)][string]$FBName,         # FB to create instance of, e.g. "TON" or "MyFB"
    [int]$DBNumber            = 0,                 # 0 = auto-assign
    [switch]$AutoNumber,                           # If set, let TIA pick the DB number
    [string]$ProjectMatch     = "Testing_Playground"
)

# Creates an instance DB for a USER-DEFINED FB using the Openness CreateInstanceDB API.
# NOTE: This does NOT work for system/library FBs like TON, TOF, CTU, CTD.
#   Those DBs are managed internally by TIA and must be created by placing the instruction
#   in the UI first. They do not appear in the normal block group enumeration.
#   Only use this script for FBs you created yourself in the project.
#
# Reference: TIA Portal Openness Manual section 6.4.1.17 "Creating Instance DB"
#   plc.BlockGroup.Blocks.CreateInstanceDB("ConveyerDB", true, 5, "Conveyer_SCL_Block");
#   Parameters: (name, autoNumber, number, fbName)
#
# Output: { "DBName": "...", "FBName": "...", "DBNumber": 0, "Created": true }
#
# Usage:
#   .\scripts\new-instance-db.ps1 -DBName IEC_Timer_1_DB -FBName TON
#   .\scripts\new-instance-db.ps1 -DBName MyMotor_DB -FBName FB_Motor -DBNumber 300

$ErrorActionPreference = "Stop"

$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

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

    # Check if DB already exists
    $existing = $plc.BlockGroup.Blocks | Where-Object { $_.Name -eq $DBName } | Select-Object -First 1
    if ($existing) {
        [pscustomobject]@{
            DBName    = $DBName
            FBName    = $FBName
            DBNumber  = $existing.Number
            Created   = $false
            Note      = "Already exists"
        } | ConvertTo-Json
        exit 0
    }

    $useAutoNumber = $AutoNumber.IsPresent -or ($DBNumber -eq 0)
    $numberToUse   = if ($useAutoNumber) { 1 } else { $DBNumber }

    # CreateInstanceDB(name, autoNumber, number, fbName)
    $db = $plc.BlockGroup.Blocks.CreateInstanceDB($DBName, $useAutoNumber, $numberToUse, $FBName)

    [pscustomobject]@{
        DBName   = $DBName
        FBName   = $FBName
        DBNumber = $db.Number
        Created  = $true
    } | ConvertTo-Json

} finally {
    if ($tia) { $tia.Dispose() }
}
