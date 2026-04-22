param(
    [Parameter(Mandatory)][string]$Action,    # create_block_group | create_type_group | move_block | move_type
    [Parameter(Mandatory)][string]$GroupPath, # e.g. "Kistler NC" or "Kistler NC/Helpers"
    [string]$BlockName,                       # required for move_block / move_type
    [string]$ProjectMatch = "Testing_Playground"
)

# Manages Program Blocks groups and PLC data type groups via TIA Portal Openness.
#
# Actions:
#   create_block_group - creates a group (and any missing parent groups) under Program Blocks
#   create_type_group  - creates a group (and any missing parent groups) under PLC data types
#   move_block         - moves a Program Blocks item (FB/FC/DB/OB) into the specified group path
#   move_type          - moves a PLC data type (UDT) into the specified group path
#
# GroupPath uses "/" as separator, e.g. "bdtronic B1000/UDTs"
#
# Output JSON:
#   { "Action": "...", "GroupPath": "...", "BlockName": "...",
#     "State": "Success"|"Error", "Message": "..." }

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

# Ensure a nested group path exists under a root BlockGroup, creating missing levels.
# Returns the deepest group.
function Ensure-GroupPath {
    param($RootGroup, [string[]]$Parts)
    $current = $RootGroup
    foreach ($part in $Parts) {
        $child = $current.Groups | Where-Object { $_.Name -eq $part } | Select-Object -First 1
        if (-not $child) {
            $child = $current.Groups.Create($part)
        }
        $current = $child
    }
    return $current
}

# Find a block by name in BlockGroup tree (FBs, FCs, DBs)
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

# Find a UDT by name in TypeGroup tree
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

$result = [ordered]@{
    Action    = $Action
    GroupPath = $GroupPath
    BlockName = $BlockName
    State     = "Error"
    Message   = ""
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

    $parts = $GroupPath -split '/' | Where-Object { $_ -ne '' }

    switch ($Action) {
        "create_block_group" {
            $group = Ensure-GroupPath -RootGroup $plc.BlockGroup -Parts $parts
            $result.State   = "Success"
            $result.Message = "Program Blocks group '$GroupPath' ready."
        }
        "create_type_group" {
            $group = Ensure-GroupPath -RootGroup $plc.TypeGroup -Parts $parts
            $result.State   = "Success"
            $result.Message = "PLC data type group '$GroupPath' ready."
        }
        "move_block" {
            if (-not $BlockName) { throw "BlockName is required for move_block action." }
            $tempXml = [System.IO.Path]::Combine($env:TEMP, ("{0}-{1}.xml" -f $BlockName, [guid]::NewGuid().ToString('N')))
            $targetGroup = Ensure-GroupPath -RootGroup $plc.BlockGroup -Parts $parts
            $block = Find-BlockInGroup -Group $plc.BlockGroup -Name $BlockName
            if (-not $block) { throw "Program Blocks item '$BlockName' not found in BlockGroup." }

            # Check if block is already in the target group (parent comparison)
            $blockParent = $block.Parent
            if ($blockParent -eq $targetGroup) {
                $result.State   = "Success"
                $result.Message = "Block '$BlockName' is already in '$GroupPath'."
                break
            }

            # Export block to temp XML
            $exportOpts = [Siemens.Engineering.ExportOptions]::WithDefaults
            $block.Export([System.IO.FileInfo]$tempXml, $exportOpts)

            # Delete original
            $block.Delete()

            # Import into target group
            $importOpts = [Siemens.Engineering.ImportOptions]::Override
            $targetGroup.Blocks.Import([System.IO.FileInfo]$tempXml, $importOpts) | Out-Null

            # Clean up temp file
            if (Test-Path $tempXml) { Remove-Item $tempXml -Force }

            $result.State   = "Success"
            $result.Message = "Block '$BlockName' moved to '$GroupPath'."
        }
        "move_type" {
            if (-not $BlockName) { throw "BlockName is required for move_type action." }

            $tempXml = [System.IO.Path]::Combine($env:TEMP, ("{0}-{1}.xml" -f $BlockName, [guid]::NewGuid().ToString('N')))
            $targetGroup = Ensure-GroupPath -RootGroup $plc.TypeGroup -Parts $parts
            $block = Find-TypeInGroup -Group $plc.TypeGroup -Name $BlockName
            if (-not $block) { throw "PLC data type '$BlockName' not found in TypeGroup." }

            $blockParent = $block.Parent
            if ($blockParent -eq $targetGroup) {
                $result.State   = "Success"
                $result.Message = "PLC data type '$BlockName' is already in '$GroupPath'."
                break
            }

            $exportOpts = [Siemens.Engineering.ExportOptions]::WithDefaults
            $block.Export([System.IO.FileInfo]$tempXml, $exportOpts)
            $block.Delete()

            $importOpts = [Siemens.Engineering.ImportOptions]::Override
            $targetGroup.Types.Import([System.IO.FileInfo]$tempXml, $importOpts) | Out-Null

            if (Test-Path $tempXml) { Remove-Item $tempXml -Force }

            $result.State   = "Success"
            $result.Message = "PLC data type '$BlockName' moved to '$GroupPath'."
        }
        default {
            throw "Unknown action '$Action'. Use create_block_group, create_type_group, move_block, or move_type."
        }
    }
} catch {
    $result.State   = "Error"
    $result.Message = $_.Exception.Message
}

$result | ConvertTo-Json -Depth 4
