param(
    [Parameter(Mandatory)][string]$TableName,
    [string]$ProjectMatch = "Testing_Playground"
)

# Creates a new user-defined PLC tag table.
# Output: { "TableName": "MyTable", "Created": true }
#         { "TableName": "MyTable", "Created": false, "Reason": "already exists" }
#
# Usage:
#   .\scripts\new-tag-table.ps1 -TableName Conveyor_Tags
#   .\scripts\new-tag-table.ps1 -TableName Safety_Tags -ProjectMatch MyProject

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

    # Check if table already exists using .Find()
    $existing = $plc.TagTableGroup.TagTables.Find($TableName)
    if ($existing) {
        [ordered]@{ TableName = $TableName; Created = $false; Reason = "already exists" } | ConvertTo-Json -Depth 2
        exit 0
    }

    $plc.TagTableGroup.TagTables.Create($TableName) | Out-Null

    [ordered]@{ TableName = $TableName; Created = $true } | ConvertTo-Json -Depth 2

} finally {
    if ($tia) { try { $tia.Dispose() } catch {} }
}
