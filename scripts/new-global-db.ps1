param(
    [Parameter(Mandatory)][string]$DBName,
    [int]$DBNumber        = 0,          # 0 = auto-assign
    [switch]$AutoNumber,                # Let TIA pick the DB number
    [string]$ProjectMatch = "Testing_Playground"
)

# Creates a new global Data Block (DB) in the PLC.
# The block will be empty (optimized memory layout).
# Output: { "DBName": "MyData_DB", "DBNumber": 300, "Created": true }
#
# Usage:
#   .\scripts\new-global-db.ps1 -DBName Process_DB -DBNumber 300
#   .\scripts\new-global-db.ps1 -DBName Process_DB -AutoNumber

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

    # Check for existing block with same name
    $existing = $plc.BlockGroup.Blocks | Where-Object { $_.Name -eq $DBName } | Select-Object -First 1
    if ($existing) {
        [ordered]@{
            DBName   = $DBName
            DBNumber = $existing.Number
            Created  = $false
            Reason   = "block '$DBName' already exists"
        } | ConvertTo-Json -Depth 2
        exit 0
    }

    $useAutoNumber = $AutoNumber.IsPresent -or ($DBNumber -eq 0)
    $db = $plc.BlockGroup.Blocks.CreateGlobalDB($DBName, $useAutoNumber, $DBNumber)

    $actualNumber = try { $db.Number } catch { $DBNumber }

    [ordered]@{
        DBName   = $DBName
        DBNumber = $actualNumber
        Created  = $true
    } | ConvertTo-Json -Depth 2

} finally {
    if ($tia) { try { $tia.Dispose() } catch {} }
}
