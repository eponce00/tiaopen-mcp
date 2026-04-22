param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Outputs a JSON array of all blocks in the PLC software top-level block group.
# Each entry: { "Name": "Main", "Type": "OB", "Language": "LAD", "Number": 1, "IsConsistent": true }
#
# Usage:
#   .\scripts\get-blocks.ps1 -ProjectMatch "MyProject"
#   .\scripts\get-blocks.ps1 | ConvertFrom-Json

$ErrorActionPreference = "Stop"

$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

# ── helpers ─────────────────────────────────────────────────────────────────

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

function Get-BlockProperty {
    param($Block, [string]$Name)
    try { return $Block.GetType().GetProperty($Name).GetValue($Block, $null) } catch { return $null }
}

function Collect-Blocks {
    param($Group, [string]$GroupPath = "")
    $results = @()

    foreach ($block in $Group.Blocks) {
        $typeName  = $block.GetType().Name                              # OB, FC, FB, GlobalDB, etc.
        $lang      = Get-BlockProperty $block "ProgrammingLanguage"
        $number    = Get-BlockProperty $block "Number"
        $consistent = Get-BlockProperty $block "IsConsistent"

        $results += [ordered]@{
            Name         = $block.Name
            Type         = $typeName
            Language     = if ($lang)       { $lang.ToString() }      else { $null }
            Number       = if ($number)     { [int]$number }           else { $null }
            IsConsistent = if ($null -ne $consistent) { [bool]$consistent } else { $null }
            Group        = if ($GroupPath)  { $GroupPath }             else { "/"  }
        }
    }

    foreach ($sub in $Group.Groups) {
        $subPath = if ($GroupPath) { "$GroupPath/$($sub.Name)" } else { $sub.Name }
        $results += Collect-Blocks -Group $sub -GroupPath $subPath
    }

    return $results
}

# ── main ─────────────────────────────────────────────────────────────────────

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

    $blocks = Collect-Blocks -Group $plc.BlockGroup
    $blocks | ConvertTo-Json -Depth 5
} finally {
    $tia.Dispose()
}
