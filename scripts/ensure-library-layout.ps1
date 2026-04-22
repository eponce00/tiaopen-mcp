param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [switch]$DryRun,
    [string]$ProjectMatch = "Testing_Playground"
)

# Applies a library layout manifest to Program Blocks and PLC data types.
#
# Manifest shape:
# {
#   "program_blocks": [
#     { "block_name": "FB_KistlerNC", "group_path": "Kistler NC" }
#   ],
#   "plc_data_types": [
#     { "type_name": "UDT_KistlerNC_Cmd", "group_path": "Kistler NC" }
#   ]
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

function Ensure-GroupPath {
    param($RootGroup, [string[]]$Parts)
    $current = $RootGroup
    foreach ($part in $Parts) {
        $child = $current.Groups | Where-Object { $_.Name -eq $part } | Select-Object -First 1
        if (-not $child) {
            if ($DryRun) {
                $child = [pscustomobject]@{ Name = $part; Groups = $null }
            } else {
                $child = $current.Groups.Create($part)
            }
        }
        $current = $child
    }
    return $current
}

function Find-BlockInGroup {
    param($Group, [string]$Name)
    $found = $Group.Blocks | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($found) { return $found }
    foreach ($g in $Group.Groups) {
        $f = Find-BlockInGroup $g $Name
        if ($f) { return $f }
    }
    return $null
}

function Find-TypeInGroup {
    param($Group, [string]$Name)
    $found = $Group.Types | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($found) { return $found }
    foreach ($g in $Group.Groups) {
        $f = Find-TypeInGroup $g $Name
        if ($f) { return $f }
    }
    return $null
}

function Move-ProgramBlock {
    param($Plc, [string]$BlockName, [string]$GroupPath)

    $parts = $GroupPath -split '/' | Where-Object { $_ -ne '' }
    $targetGroup = Ensure-GroupPath -RootGroup $Plc.BlockGroup -Parts $parts
    $block = Find-BlockInGroup -Group $Plc.BlockGroup -Name $BlockName
    if (-not $block) {
        return [ordered]@{ Item = $BlockName; Scope = "ProgramBlocks"; Action = "move"; State = "Error"; Message = "Block not found." }
    }

    if ($block.Parent -eq $targetGroup) {
        return [ordered]@{ Item = $BlockName; Scope = "ProgramBlocks"; Action = "none"; State = "Success"; Message = "Already in target group '$GroupPath'." }
    }

    if ($DryRun) {
        return [ordered]@{ Item = $BlockName; Scope = "ProgramBlocks"; Action = "move"; State = "Planned"; Message = "Would move to '$GroupPath'." }
    }

    $tempXml = [System.IO.Path]::Combine($env:TEMP, ("{0}-{1}.xml" -f $BlockName, [guid]::NewGuid().ToString('N')))
    try {
        $exportOpts = [Siemens.Engineering.ExportOptions]::WithDefaults
        $block.Export([System.IO.FileInfo]$tempXml, $exportOpts)
        $block.Delete()

        $importOpts = [Siemens.Engineering.ImportOptions]::Override
        $targetGroup.Blocks.Import([System.IO.FileInfo]$tempXml, $importOpts) | Out-Null

        return [ordered]@{ Item = $BlockName; Scope = "ProgramBlocks"; Action = "move"; State = "Success"; Message = "Moved to '$GroupPath'." }
    } finally {
        if (Test-Path $tempXml) { Remove-Item $tempXml -Force }
    }
}

function Move-PlcType {
    param($Plc, [string]$TypeName, [string]$GroupPath)

    $parts = $GroupPath -split '/' | Where-Object { $_ -ne '' }
    $targetGroup = Ensure-GroupPath -RootGroup $Plc.TypeGroup -Parts $parts
    $typeObj = Find-TypeInGroup -Group $Plc.TypeGroup -Name $TypeName
    if (-not $typeObj) {
        return [ordered]@{ Item = $TypeName; Scope = "PlcDataTypes"; Action = "move"; State = "Error"; Message = "Type not found." }
    }

    if ($typeObj.Parent -eq $targetGroup) {
        return [ordered]@{ Item = $TypeName; Scope = "PlcDataTypes"; Action = "none"; State = "Success"; Message = "Already in target group '$GroupPath'." }
    }

    if ($DryRun) {
        return [ordered]@{ Item = $TypeName; Scope = "PlcDataTypes"; Action = "move"; State = "Planned"; Message = "Would move to '$GroupPath'." }
    }

    $tempXml = [System.IO.Path]::Combine($env:TEMP, ("{0}-{1}.xml" -f $TypeName, [guid]::NewGuid().ToString('N')))
    try {
        $exportOpts = [Siemens.Engineering.ExportOptions]::WithDefaults
        $typeObj.Export([System.IO.FileInfo]$tempXml, $exportOpts)
        $typeObj.Delete()

        $importOpts = [Siemens.Engineering.ImportOptions]::Override
        $targetGroup.Types.Import([System.IO.FileInfo]$tempXml, $importOpts) | Out-Null

        return [ordered]@{ Item = $TypeName; Scope = "PlcDataTypes"; Action = "move"; State = "Success"; Message = "Moved to '$GroupPath'." }
    } finally {
        if (Test-Path $tempXml) { Remove-Item $tempXml -Force }
    }
}

if (-not (Test-Path $ManifestPath)) {
    Write-Error "Manifest file not found: $ManifestPath"
    exit 1
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

$result = [ordered]@{
    DryRun   = [bool]$DryRun
    State    = "Success"
    Applied  = @()
    Errors   = 0
}

try {
    $tiaProcess = $null
    foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
        if ($p.Mode -ne [Siemens.Engineering.TiaPortalMode]::WithUserInterface) { continue }
        $wp = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if ($wp.MainWindowTitle -match $ProjectMatch) { $tiaProcess = $p; break }
    }
    if (-not $tiaProcess) { throw "No UI TIA process matching '$ProjectMatch' found." }

    $tia     = $tiaProcess.Attach()
    $project = $tia.Projects | Where-Object { $_.Name -match $ProjectMatch } | Select-Object -First 1
    if (-not $project) { $project = $tia.Projects[0] }
    $plc = Find-PlcSoftware -Project $project
    if (-not $plc) { throw "PlcSoftware not found." }

    foreach ($entry in @($manifest.program_blocks)) {
        $item = Move-ProgramBlock -Plc $plc -BlockName $entry.block_name -GroupPath $entry.group_path
        if ($item.State -eq "Error") { $result.Errors++ }
        $result.Applied += $item
    }

    foreach ($entry in @($manifest.plc_data_types)) {
        $typeName = if ($entry.type_name) { $entry.type_name } else { $entry.block_name }
        $item = Move-PlcType -Plc $plc -TypeName $typeName -GroupPath $entry.group_path
        if ($item.State -eq "Error") { $result.Errors++ }
        $result.Applied += $item
    }

    if ($result.Errors -gt 0) {
        $result.State = "Error"
    }
} catch {
    $result.State = "Error"
    $result.Errors = [int]$result.Errors + 1
    $result.Applied += [ordered]@{
        Item = "(global)"
        Scope = "(global)"
        Action = "exception"
        State = "Error"
        Message = $_.Exception.Message
    }
}

$result | ConvertTo-Json -Depth 8
