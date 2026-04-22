param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Outputs a JSON array of tag tables and groups in the PLC tag tree.
# Each entry:
#   { "Kind":"DefaultTable"|"Table"|"Group", "Name":"...", "Path":"...", "Parent":"..." }

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
    $containerType = [Siemens.Engineering.HW.Features.SoftwareContainer]
    foreach ($device in $Project.Devices) {
        $result = Search-Items $device.DeviceItems $containerType
        if ($result) { return $result }
    }
    return $null
}

function Search-Items {
    param($Items, [Type]$ContainerType)
    foreach ($item in $Items) {
        $svc = Invoke-GenericGetService -Instance $item -ServiceType $ContainerType
        if ($svc -and $svc.Software -is [Siemens.Engineering.SW.PlcSoftware]) { return $svc.Software }
        $nested = Search-Items $item.DeviceItems $ContainerType
        if ($nested) { return $nested }
    }
    return $null
}

function Collect-TagTables {
    param($TagTableGroup, [string]$GroupPath = "")
    $results = @()

    # Group node itself (skip root)
    if ($GroupPath) {
        $name = if ($TagTableGroup.Name) { $TagTableGroup.Name } else { $GroupPath }
        $parent = if ($GroupPath.Contains('/')) { $GroupPath.Substring(0, $GroupPath.LastIndexOf('/')) } else { "/" }
        $results += [ordered]@{
            Kind   = "Group"
            Name   = $name
            Path   = $GroupPath
            Parent = $parent
        }
    }

    # Default tag table exists on the root tag table group only
    if (-not $GroupPath) {
        try {
            $default = $TagTableGroup.GetType().GetProperty("DefaultTagTable").GetValue($TagTableGroup, $null)
            if ($default) {
                $results += [ordered]@{
                    Kind   = "DefaultTable"
                    Name   = $default.Name
                    Path   = if ($default.Name) { $default.Name } else { "Default tag table" }
                    Parent = "/"
                }
            }
        } catch {}
    }

    # Tables in this group
    try {
        foreach ($table in $TagTableGroup.TagTables) {
            $tablePath = if ($GroupPath) { "$GroupPath/$($table.Name)" } else { $table.Name }
            $results += [ordered]@{
                Kind   = "Table"
                Name   = $table.Name
                Path   = $tablePath
                Parent = if ($GroupPath) { $GroupPath } else { "/" }
            }
        }
    } catch {}

    # Recurse child groups
    try {
        foreach ($group in $TagTableGroup.Groups) {
            $childPath = if ($GroupPath) { "$GroupPath/$($group.Name)" } else { $group.Name }
            $results += Collect-TagTables -TagTableGroup $group -GroupPath $childPath
        }
    } catch {}

    return $results
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
    if (-not $project) { Write-Error "No project found."; exit 1 }

    $plc = Find-PlcSoftware -Project $project
    if (-not $plc) { Write-Error "PlcSoftware not found in project."; exit 1 }

    $tables = Collect-TagTables -TagTableGroup $plc.TagTableGroup
    @($tables) | ConvertTo-Json -Depth 6
} finally {
    $tia.Dispose()
}
