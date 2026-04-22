param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$DataType,
    [string]$Address      = "",
    [string]$Comment      = "",
    [string]$TableName    = "",    # empty = Default tag table; otherwise name of user tag table
    [string]$ProjectMatch = "Testing_Playground"
)

# Creates a PLC tag in the default (or named) tag table and outputs the result as JSON.
# Output: { "Table": "Default tag table", "Name": "Motor_Run", "DataType": "Bool",
#            "Address": "%Q1.0", "Comment": "...", "Created": true }
#
# Exit code 0 = success, 1 = error
#
# Address rules:
#   Bool tags : %Ix.b, %Qx.b, %Mx.b  where b is 0..7 (NOT 8 or higher)
#   Word tags : %IWx, %QWx, %MWx  (byte-aligned word address)
#   Leave Address empty for an unassigned tag.
#
# Usage:
#   .\scripts\add-tag.ps1 -Name Motor_Run -DataType Bool -Address "%Q1.0"
#   .\scripts\add-tag.ps1 -Name Setpoint  -DataType Int  -Address "%MW10" -TableName MyTable
#   .\scripts\add-tag.ps1 -Name Calc_Result -DataType Real

$ErrorActionPreference = "Stop"

# ── Address validation ────────────────────────────────────────────────────────
if ($Address) {
    # Validate bit address: bit number must be 0-7
    if ($Address -match '^%[IQM](\d+)\.(\d+)$') {
        $bitNum = [int]$Matches[2]
        if ($bitNum -gt 7) {
            Write-Error "Invalid address '$Address': bit number $bitNum is out of range. Bits must be 0-7. For the next byte use byte+1, e.g. '%Q1.0' instead of '%Q0.8'."
            exit 1
        }
    }
}

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

function Set-TagProperty {
    param($Tag, [string]$PropName, $Value)
    $Tag.GetType().GetProperty($PropName).SetValue($Tag, $Value, $null)
}

function Set-MultilingualText {
    param($Tag, [string]$PropName, [string]$Text)
    try {
        $ml    = $Tag.GetType().GetProperty($PropName).GetValue($Tag, $null)
        $items = $ml.GetType().GetProperty("Items").GetValue($ml, $null)
        if ($items.Count -gt 0) {
            $item = $items[0]
            $item.GetType().GetProperty("Text").SetValue($item, $Text, $null)
        }
    } catch {}
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
    $plc = Find-PlcSoftware -Project $project
    if (-not $plc) { Write-Error "PlcSoftware not found."; exit 1 }

    # Resolve target tag table
    $targetTable   = $null
    $resolvedTable = "Default tag table"

    if ($TableName) {
        # Use .Find() — piping Openness collections through Where-Object is unreliable
        $targetTable = $plc.TagTableGroup.TagTables.Find($TableName)
        if (-not $targetTable) { Write-Error "Tag table '$TableName' not found."; exit 1 }
        $resolvedTable = $TableName
    } else {
        # Default tag table is TagTables[0]
        $targetTable = $plc.TagTableGroup.TagTables[0]
        if (-not $targetTable) { Write-Error "Default tag table not found."; exit 1 }
    }

    # Check for duplicate name
    $existing = $targetTable.Tags | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($existing) { Write-Error "Tag '$Name' already exists in table '$resolvedTable'."; exit 1 }

    # Create tag
    $tag = $targetTable.Tags.Create($Name)

    # Set DataType
    try { Set-TagProperty $tag "DataTypeName" $DataType } catch {}

    # Set LogicalAddress
    try { Set-TagProperty $tag "LogicalAddress" $Address } catch {}

    # Set Comment (MultilingualText)
    if ($Comment) { Set-MultilingualText $tag "Comment" $Comment }

    # Read back to confirm
    $readType    = $tag.GetType().GetProperty("DataTypeName").GetValue($tag, $null)
    $readAddress = $tag.GetType().GetProperty("LogicalAddress").GetValue($tag, $null)

    [ordered]@{
        Table    = $resolvedTable
        Name     = $tag.Name
        DataType = if ($readType)    { $readType.ToString()    } else { $DataType }
        Address  = if ($readAddress) { $readAddress.ToString() } else { $Address }
        Comment  = $Comment
        Created  = $true
    } | ConvertTo-Json -Depth 3

} finally {
    $tia.Dispose()
}
