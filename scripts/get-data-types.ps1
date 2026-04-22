param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Outputs a JSON array of all PLC data types in the PLC software type tree.
# Each entry: { "Name": "UDT_KistlerNC_Cmd", "Type": "PlcStruct", "IsConsistent": true, "Group": "/" }

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

function Get-TypeProperty {
    param($PlcType, [string]$Name)
    try { return $PlcType.GetType().GetProperty($Name).GetValue($PlcType, $null) } catch { return $null }
}

function Collect-Types {
    param($Group, [string]$GroupPath = "")
    $results = @()

    foreach ($plcType in $Group.Types) {
        $typeName = $plcType.GetType().Name
        $consistent = Get-TypeProperty $plcType "IsConsistent"

        $results += [ordered]@{
            Name         = $plcType.Name
            Type         = $typeName
            IsConsistent = if ($null -ne $consistent) { [bool]$consistent } else { $null }
            Group        = if ($GroupPath) { $GroupPath } else { "/" }
        }
    }

    foreach ($sub in $Group.Groups) {
        $subPath = if ($GroupPath) { "$GroupPath/$($sub.Name)" } else { $sub.Name }
        $results += Collect-Types -Group $sub -GroupPath $subPath
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

    $types = Collect-Types -Group $plc.TypeGroup
    $types | ConvertTo-Json -Depth 5
} finally {
    $tia.Dispose()
}