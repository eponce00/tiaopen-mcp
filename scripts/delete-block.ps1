param(
    [Parameter(Mandatory)][string]$BlockName,
    [string]$ProjectMatch = "Testing_Playground"
)

# Deletes a single PLC block by name and outputs the result as JSON.
# Output: { "BlockName": "FC_Old", "Deleted": true }
#
# Exit code 0 = success (deleted or not found), 1 = error
#
# Usage:
#   .\scripts\delete-block.ps1 -BlockName FC_Old
#   .\scripts\delete-block.ps1 -BlockName FC_Old -ProjectMatch MyProject

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

# ── Find and delete ───────────────────────────────────────────────────────────
$block = $plcSw.BlockGroup.Blocks | Where-Object { $_.Name -eq $BlockName }

if (-not $block) {
    @{ BlockName = $BlockName; Deleted = $false; Reason = "Block not found" } |
        ConvertTo-Json -Compress
    exit 0
}

$block.Delete()

@{ BlockName = $BlockName; Deleted = $true } | ConvertTo-Json -Compress
