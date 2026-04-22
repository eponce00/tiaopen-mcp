param([string]$ProjectMatch = "Testing_Playground")

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
if (-not $tiaProcess) { Write-Error "No TIA process found."; exit 1 }

$tia = $tiaProcess.Attach()
try {
    $project = $tia.Projects | Where-Object { $_.Name -match $ProjectMatch } | Select-Object -First 1
    if (-not $project) { $project = $tia.Projects[0] }

    $plc = Find-PlcSoftware -Project $project
    if (-not $plc) { Write-Error "PlcSoftware not found."; exit 1 }

    # TagTables[0] = Default tag table (cannot be deleted, only clear its tags)
    # TagTables[1..n] = user-defined tables (delete the whole table)
    $count = $plc.TagTableGroup.TagTables.Count
    Write-Host "Found $count tag table(s)"

    for ($i = 0; $i -lt $count; $i++) {
        $table = $plc.TagTableGroup.TagTables[$i]
        $tableName = $table.Name
        if ($i -eq 0) {
            # Default table — delete all tags inside it
            $tagNames = @()
            $tagCount = $table.Tags.Count
            for ($j = 0; $j -lt $tagCount; $j++) { $tagNames += $table.Tags[$j].Name }
            foreach ($n in $tagNames) {
                $tag = $table.Tags.Find($n)
                if ($tag) { $tag.Delete(); Write-Host "Deleted tag '$n' from '$tableName'" }
            }
        }
    }

    # Now delete user-defined tables (collect names first, then delete)
    $userTableNames = @()
    $count2 = $plc.TagTableGroup.TagTables.Count
    for ($i = 1; $i -lt $count2; $i++) { $userTableNames += $plc.TagTableGroup.TagTables[$i].Name }
    foreach ($tn in $userTableNames) {
        $t = $plc.TagTableGroup.TagTables.Find($tn)
        if ($t) { $t.Delete(); Write-Host "Deleted table '$tn'" }
    }

    Write-Host "Done."
} finally {
    $tia.Dispose()
}
