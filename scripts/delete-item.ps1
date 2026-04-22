param(
    [Parameter(Mandatory)][string]$BlockName,
    [string]$ProjectMatch = "Testing_Playground"
)

# Deletes a PLC block (FB/FC/OB/DB) or PLC data type (UDT) by name.
# Searches recursively through all Program Block groups first, then PLC data type groups.
# Output: { "BlockName": "FC_Old", "Deleted": true, "Kind": "Block"|"DataType" }
#
# Exit code 0 = success (deleted or not found), 1 = error
#
# Usage:
#   .\scripts\delete-item.ps1 -BlockName FC_Old
#   .\scripts\delete-item.ps1 -BlockName UDT_Foo -ProjectMatch MyProject

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

# ── Attach ────────────────────────────────────────────────────────────────────
$tiaProcess = $null
foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
    if ($p.Mode -ne [Siemens.Engineering.TiaPortalMode]::WithUserInterface) { continue }
    $wp = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ($wp.MainWindowTitle -match $ProjectMatch) { $tiaProcess = $p; break }
}
if (-not $tiaProcess) { Write-Error "No UI TIA process matching '$ProjectMatch' found."; exit 1 }

$tia = $tiaProcess.Attach()
$project = $tia.Projects | Where-Object { $_.Name -match $ProjectMatch } | Select-Object -First 1
if (-not $project) { $project = $tia.Projects[0] }

$plcSw = Find-PlcSoftware $project
if (-not $plcSw) { Write-Error "Could not find PlcSoftware."; exit 1 }

# ── Helpers ───────────────────────────────────────────────────────────────────
function Find-Block {
    param($Group, [string]$Name)
    foreach ($b in $Group.Blocks) { if ($b.Name -eq $Name) { return $b } }
    foreach ($g in $Group.Groups) { $r = Find-Block $g $Name; if ($r) { return $r } }
    return $null
}

function Find-DataType {
    param($Group, [string]$Name)
    foreach ($t in $Group.Types) { if ($t.Name -eq $Name) { return $t } }
    foreach ($g in $Group.Groups) { $r = Find-DataType $g $Name; if ($r) { return $r } }
    return $null
}

# ── Find and delete ───────────────────────────────────────────────────────────
$item = Find-Block $plcSw.BlockGroup $BlockName
$kind = "Block"

if (-not $item) {
    $item = Find-DataType $plcSw.TypeGroup $BlockName
    $kind = "DataType"
}

if (-not $item) {
    @{ BlockName = $BlockName; Deleted = $false; Reason = "Block not found" } |
        ConvertTo-Json -Compress
    exit 0
}

$item.Delete()

@{ BlockName = $BlockName; Deleted = $true; Kind = $kind } | ConvertTo-Json -Compress
