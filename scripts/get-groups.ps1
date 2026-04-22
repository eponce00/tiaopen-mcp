param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Outputs Program Blocks and PLC data types group trees as JSON.
#
# Shape:
# {
#   "ProgramBlocks": [ { "Path": "/", "Name": "/", "Parent": null }, ... ],
#   "PlcDataTypes":  [ { "Path": "/", "Name": "/", "Parent": null }, ... ]
# }

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

function Collect-Groups {
    param($Group, [string]$GroupPath = "")
    $results = @()
    foreach ($sub in $Group.Groups) {
        $subPath = if ($GroupPath) { "$GroupPath/$($sub.Name)" } else { $sub.Name }
        $parentPath = if ($GroupPath) { $GroupPath } else { "/" }
        $results += [ordered]@{
            Path   = $subPath
            Name   = $sub.Name
            Parent = $parentPath
        }
        $results += Collect-Groups -Group $sub -GroupPath $subPath
    }
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

    $programGroups = @([ordered]@{ Path = "/"; Name = "/"; Parent = $null })
    $programGroups += Collect-Groups -Group $plc.BlockGroup

    $typeGroups = @([ordered]@{ Path = "/"; Name = "/"; Parent = $null })
    $typeGroups += Collect-Groups -Group $plc.TypeGroup

    [ordered]@{
        ProgramBlocks = $programGroups
        PlcDataTypes  = $typeGroups
    } | ConvertTo-Json -Depth 6
} finally {
    $tia.Dispose()
}
