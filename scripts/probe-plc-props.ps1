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

$tiaProcess = $null
foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
    if ($p.Mode -ne [Siemens.Engineering.TiaPortalMode]::WithUserInterface) { continue }
    $tiaProcess = $p; break
}
$tia = $tiaProcess.Attach()
try {
    $project = $tia.Projects[0]
    $ct = [Siemens.Engineering.HW.Features.SoftwareContainer]
    $plc = $null
    foreach ($dev in $project.Devices) {
        foreach ($item in $dev.DeviceItems) {
            $svc = Invoke-GenericGetService $item $ct
            if ($svc -and $svc.Software -is [Siemens.Engineering.SW.PlcSoftware]) { $plc = $svc.Software; break }
        }
        if ($plc) { break }
    }

    # List all props on plc
    $plc.GetType().GetProperties() | Where-Object { $_.Name -match "Group|Block|System" } | Select-Object -ExpandProperty Name
} finally {
    $tia.Dispose()
}
