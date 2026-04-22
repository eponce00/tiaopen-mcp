param(
    [Parameter(Mandatory)][string]$SourceDB,       # e.g. "DB_Timer_Fast"
    [Parameter(Mandatory)][string]$TargetDB,       # e.g. "DB_Timer_Slow"
    [string]$ProjectMatch = "Testing_Playground"
)

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

# Recursively search block groups for a named block
function Find-BlockInGroup {
    param($Group, [string]$Name)
    foreach ($b in $Group.Blocks) {
        if ($b.Name -eq $Name) { return $b }
    }
    foreach ($g in $Group.Groups) {
        $found = Find-BlockInGroup $g $Name
        if ($found) { return $found }
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

    # Check if target already exists
    $existing = $plc.BlockGroup.Blocks | Where-Object { $_.Name -eq $TargetDB } | Select-Object -First 1
    if ($existing) {
        [pscustomobject]@{ TargetDB=$TargetDB; Created=$false; Note="Already exists" } | ConvertTo-Json
        exit 0
    }

    # Find source in user block group first, then system groups
    $srcBlock = Find-BlockInGroup $plc.BlockGroup $SourceDB
    if (-not $srcBlock) {
        # Try SystemBlockGroups
        $sbg = $plc.GetType().GetProperty("SystemBlockGroups")
        if ($sbg) {
            $groups = $sbg.GetValue($plc, $null)
            foreach ($g in $groups) {
                $srcBlock = Find-BlockInGroup $g $SourceDB
                if ($srcBlock) { break }
            }
        }
    }
    if (-not $srcBlock) { Write-Error "Source block '$SourceDB' not found in any block group."; exit 1 }

    # Export to temp file
    $tmpPath = [System.IO.Path]::GetTempFileName() + ".xml"
    $exportSvc = Invoke-GenericGetService $srcBlock ([Siemens.Engineering.IExportable])
    if (-not $exportSvc) {
        # Try direct Export method
        $srcBlock.GetType().GetMethod("Export").Invoke($srcBlock, @([System.IO.FileInfo]$tmpPath, [Siemens.Engineering.ExportOptions]::WithDefaults))
    } else {
        $exportSvc.Export([System.IO.FileInfo]$tmpPath, [Siemens.Engineering.ExportOptions]::WithDefaults)
    }

    # Read, rename, and write back
    $xml = [System.IO.File]::ReadAllText($tmpPath)
    $xml = $xml -replace ([System.Text.RegularExpressions.Regex]::Escape($SourceDB)), $TargetDB

    $newTmpPath = [System.IO.Path]::GetTempFileName() + ".xml"
    [System.IO.File]::WriteAllText($newTmpPath, $xml, [System.Text.Encoding]::UTF8)

    # Import
    $plc.BlockGroup.Blocks.Import([System.IO.FileInfo]$newTmpPath, [Siemens.Engineering.ImportOptions]::Override)

    Remove-Item $tmpPath -ErrorAction SilentlyContinue
    Remove-Item $newTmpPath -ErrorAction SilentlyContinue

    [pscustomobject]@{ TargetDB=$TargetDB; Created=$true } | ConvertTo-Json
} finally {
    if ($tia) { $tia.Dispose() }
}
