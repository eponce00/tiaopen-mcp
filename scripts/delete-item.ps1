param(
    [Parameter(Mandatory)][string]$Name,
    [ValidateSet("Auto", "Block", "DataType", "Tag", "TagTable")][string]$Kind = "Auto",
    [string]$ProjectMatch = "Testing_Playground"
)

# Surgical delete of any named item from the open TIA Portal project.
# Supported kinds:
#   Block     - PLC blocks (FB/FC/OB/DB), searched recursively under Program Blocks.
#   DataType  - User PLC data types (UDT), searched recursively under PLC data types.
#   Tag       - PLC tags, searched across all tag tables (recursively through groups).
#   TagTable  - User-defined tag tables (the default tag table is protected).
#   Auto      - Tries Block, then DataType, then Tag, then TagTable. Returns the first match.
#
# Output (JSON, one line):
#   { "Name": "...", "Deleted": true|false, "Kind": "Block"|"DataType"|"Tag"|"TagTable"|null,
#     "Container": "..."|null, "Reason": "..."|null }
#
# Exit code 0 = command ran (whether item was found or not), 1 = error.

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

function Find-PlcSoftware {
    param($Project)
    $ct = [Siemens.Engineering.HW.Features.SoftwareContainer]
    foreach ($device in $Project.Devices) {
        $r = Search-Items $device.DeviceItems $ct
        if ($r) { return $r }
    }
    return $null
}

function Find-Block {
    param($Group, [string]$Name)
    foreach ($b in $Group.Blocks) { if ($b.Name -eq $Name) { return $b } }
    foreach ($g in $Group.Groups) { $r = Find-Block $g $Name; if ($r) { return $r } }
    return $null
}

function Find-DataType {
    param($Group, [string]$Name)
    foreach ($t in $Group.Types) { if ($t.Name -eq $Name) { return $t } }
    foreach ($g in $Group.Groups) { $r = Find-DataType $g $Name; if ($r) { return $r } }
    return $null
}

function Find-Tag {
    param($Group, [string]$Name)
    foreach ($table in $Group.TagTables) {
        $tag = $table.Tags.Find($Name)
        if ($tag) { return @{ Tag = $tag; Table = $table.Name } }
    }
    foreach ($sub in $Group.Groups) {
        $r = Find-Tag -Group $sub -Name $Name
        if ($r) { return $r }
    }
    return $null
}

function Find-TagTable {
    # The first tag table in the root group is the default ("Default tag table") and cannot be deleted.
    param($RootGroup, [string]$Name)
    $i = 0
    foreach ($table in $RootGroup.TagTables) {
        if ($table.Name -eq $Name) {
            return @{ Table = $table; Group = "<root>"; IsDefault = ($i -eq 0) }
        }
        $i++
    }
    foreach ($sub in $RootGroup.Groups) {
        foreach ($table in $sub.TagTables) {
            if ($table.Name -eq $Name) {
                return @{ Table = $table; Group = $sub.Name; IsDefault = $false }
            }
        }
    }
    return $null
}

# ── Attach ────────────────────────────────────────────────────────────────────
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
    $plcSw = Find-PlcSoftware $project
    if (-not $plcSw) { Write-Error "Could not find PlcSoftware."; exit 1 }

    $kindsToTry = if ($Kind -eq "Auto") { @("Block", "DataType", "Tag", "TagTable") } else { @($Kind) }

    foreach ($k in $kindsToTry) {
        switch ($k) {
            "Block" {
                $b = Find-Block $plcSw.BlockGroup $Name
                if ($b) {
                    $b.Delete()
                    @{ Name = $Name; Deleted = $true; Kind = "Block"; Container = $null; Reason = $null } | ConvertTo-Json -Compress
                    exit 0
                }
            }
            "DataType" {
                $t = Find-DataType $plcSw.TypeGroup $Name
                if ($t) {
                    $t.Delete()
                    @{ Name = $Name; Deleted = $true; Kind = "DataType"; Container = $null; Reason = $null } | ConvertTo-Json -Compress
                    exit 0
                }
            }
            "Tag" {
                $r = Find-Tag -Group $plcSw.TagTableGroup -Name $Name
                if ($r) {
                    $r.Tag.Delete()
                    @{ Name = $Name; Deleted = $true; Kind = "Tag"; Container = $r.Table; Reason = $null } | ConvertTo-Json -Compress
                    exit 0
                }
            }
            "TagTable" {
                $r = Find-TagTable -RootGroup $plcSw.TagTableGroup -Name $Name
                if ($r) {
                    if ($r.IsDefault) {
                        @{ Name = $Name; Deleted = $false; Kind = "TagTable"; Container = $r.Group; Reason = "Default tag table cannot be deleted" } | ConvertTo-Json -Compress
                        exit 0
                    }
                    $r.Table.Delete()
                    @{ Name = $Name; Deleted = $true; Kind = "TagTable"; Container = $r.Group; Reason = $null } | ConvertTo-Json -Compress
                    exit 0
                }
            }
        }
    }

    @{ Name = $Name; Deleted = $false; Kind = $null; Container = $null; Reason = "Not found (searched: $($kindsToTry -join ', '))" } | ConvertTo-Json -Compress
} finally {
    $tia.Dispose()
}
