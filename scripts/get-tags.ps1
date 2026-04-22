param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Outputs a JSON array of all entries in the PLC default tag table plus any
# user-defined tag tables.
# Each entry: { "Table": "Default tag table", "Name": "MyTag", "DataType": "Bool",
#               "Address": "%I0.0", "Comment": "..." }
#
# Usage:
#   .\scripts\get-tags.ps1 -ProjectMatch "MyProject"
#   .\scripts\get-tags.ps1 | ConvertFrom-Json

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

function Get-TagProperty {
    param($Tag, [string]$Name)
    try { return $Tag.GetType().GetProperty($Name).GetValue($Tag, $null) } catch { return $null }
}

function Get-MultilingualText {
    param($Value)
    if ($null -eq $Value) { return $null }
    # MultilingualText exposes Items collection; grab the first non-empty entry
    try {
        $items = $Value.GetType().GetProperty("Items").GetValue($Value, $null)
        if ($items) {
            foreach ($item in $items) {
                $text = $item.GetType().GetProperty("Text").GetValue($item, $null)
                if ($text) { return $text }
            }
        }
    } catch {}
    return $Value.ToString()
}

function Collect-Tags {
    param($Table, [string]$TableName)
    $results = @()
    try {
        foreach ($tag in $Table.Tags) {
            $dataType = Get-TagProperty $tag "DataTypeName"
            $address  = Get-TagProperty $tag "LogicalAddress"
            $comment  = Get-MultilingualText (Get-TagProperty $tag "Comment")

            $results += [ordered]@{
                Table    = $TableName
                Name     = $tag.Name
                DataType = if ($dataType) { $dataType.ToString() } else { $null }
                Address  = if ($address)  { $address.ToString()  } else { $null }
                Comment  = $comment
            }
        }
    } catch {}
    return $results
}

function Collect-AllTags {
    param($TagTableGroup)
    $results = @()

    # Default tag table is directly on the PlcSoftware as TagTableGroup.DefaultTagTable
    try {
        $default = $TagTableGroup.GetType().GetProperty("DefaultTagTable").GetValue($TagTableGroup, $null)
        if ($default) { $results += Collect-Tags -Table $default -TableName "Default tag table" }
    } catch {}

    # User-defined tag tables (use .Find() is not needed here; foreach on composition works)
    try {
        $count = $TagTableGroup.TagTables.Count
        for ($i = 0; $i -lt $count; $i++) {
            $table = $TagTableGroup.TagTables[$i]
            $results += Collect-Tags -Table $table -TableName $table.Name
        }
    } catch { foreach ($table in $TagTableGroup.TagTables) { $results += Collect-Tags -Table $table -TableName $table.Name } }

    # Recurse into groups
    try {
        foreach ($group in $TagTableGroup.Groups) {
            $results += Collect-AllTags -TagTableGroup $group
        }
    } catch {}

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

    $tags = Collect-AllTags -TagTableGroup $plc.TagTableGroup
    $tags | ConvertTo-Json -Depth 5
} finally {
    $tia.Dispose()
}
