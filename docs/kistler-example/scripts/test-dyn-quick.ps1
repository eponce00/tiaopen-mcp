# Quick dynamization audit — flags anomalies, does not fix.

[System.Reflection.Assembly]::LoadFrom("C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll") | Out-Null
$tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal = $tia.Attach()
$session = $portal.LocalSessions[0]
$project = $session.Project

$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
$walk = {
    param($items)
    foreach ($it in $items) {
        try {
            $m = $it.GetType().GetMethod('GetService').MakeGenericMethod($swT)
            $svc = $m.Invoke($it, $null)
            if ($svc -and $svc.Software -and $svc.Software.GetType().FullName -match 'HmiUnified') { return $svc.Software }
        } catch {}
        if ($it.DeviceItems) { $r = & $walk $it.DeviceItems; if ($r) { return $r } }
    }
    return $null
}
$hmi = $null
foreach ($d in $project.Devices) { $hmi = & $walk $d.DeviceItems; if ($hmi) { break } }
$screen = $hmi.Screens.Find('_Kistler_Press_01')

# Expected property per widget+role
$expectedTextProp = @{ HmiText='Text'; HmiIOField='ProcessValue'; HmiCircle='BackColor'; HmiButton='BackColor'; HmiRectangle='BackColor' }

$rows = New-Object System.Collections.ArrayList
$flags = New-Object System.Collections.ArrayList

foreach ($it in $screen.ScreenItems) {
    $tn = $it.GetType().Name
    $dyns = @($it.Dynamizations)
    if ($dyns.Count -eq 0) { continue }
    foreach ($d in $dyns) {
        $row = [pscustomobject]@{
            Item = $it.Name
            Type = $tn
            Prop = $d.PropertyName
            Tag  = $d.GetAttribute('Tag')
            HasMapping = $false
            CondType = ''
            Entries = 0
            Mask = ''
        }
        # Inspect mapping table
        try {
            $mt = $d.ValueConverter.MappingTable
            if ($mt) {
                $row.HasMapping = $true
                $row.CondType = $mt.GetAttribute('ConditionType')
                $entries = @($mt.Entries)
                $row.Entries = $entries.Count
                if ($entries.Count -gt 1) { $row.Mask = "$($entries[1].Condition)" }
            }
        } catch {}
        [void]$rows.Add($row)

        # FLAGS
        if (-not $row.Tag) { [void]$flags.Add("EMPTY TAG: $($it.Name).$($d.PropertyName)") }
        elseif (-not $row.Tag.StartsWith('MVterminalPressKistler.')) { [void]$flags.Add("BAD ROOT: $($it.Name).$($d.PropertyName) -> $($row.Tag)") }
        # Bit-extract sanity: BackColor with mapping should be Singlebit with mask power-of-2
        if ($row.HasMapping -and $row.CondType -eq 'Singlebit') {
            $m = [UInt64]$row.Mask
            if ($m -eq 0 -or (($m -band ($m-1)) -ne 0)) {
                [void]$flags.Add("BAD MASK: $($it.Name).$($d.PropertyName) mask=$m (not 2^n)")
            }
            if ($row.Entries -ne 2) {
                [void]$flags.Add("MAPPING ENTRIES != 2: $($it.Name).$($d.PropertyName) has $($row.Entries)")
            }
        }
        # Widget/property cross-check
        if ($tn -eq 'HmiText' -and $d.PropertyName -ne 'Text' -and -not $row.HasMapping) {
            [void]$flags.Add("HMITEXT WRONG PROP: $($it.Name).$($d.PropertyName) (expected Text)")
        }
        if ($tn -eq 'HmiIOField' -and $d.PropertyName -ne 'ProcessValue') {
            [void]$flags.Add("IOFIELD WRONG PROP: $($it.Name).$($d.PropertyName) (expected ProcessValue)")
        }
    }
}

Write-Host "Dynamizations scanned: $($rows.Count)"
Write-Host ""
Write-Host "BY PROPERTY:"
$rows | Group-Object Prop | Sort-Object Count -Descending | ForEach-Object { Write-Host ("  {0,-15} {1}" -f $_.Name, $_.Count) }
Write-Host ""
Write-Host "BY WIDGET TYPE:"
$rows | Group-Object Type | Sort-Object Count -Descending | ForEach-Object { Write-Host ("  {0,-15} {1}" -f $_.Name, $_.Count) }
Write-Host ""
Write-Host "BIT-EXTRACT (Singlebit) DYNAMIZATIONS:"
$bits = $rows | Where-Object { $_.CondType -eq 'Singlebit' }
Write-Host "  Total: $($bits.Count)"
$bits | Group-Object Tag | Sort-Object Name | ForEach-Object {
    $masks = ($_.Group | ForEach-Object { $_.Mask }) -join ','
    Write-Host ("    {0,-45} bits=[{1}]" -f $_.Name, $masks)
}
Write-Host ""
if ($flags.Count -eq 0) {
    Write-Host "ALL DYNAMIZATIONS LOOK GOOD." -ForegroundColor Green
} else {
    Write-Host "FLAGS ($($flags.Count)):" -ForegroundColor Red
    foreach ($f in $flags) { Write-Host "  $f" -ForegroundColor Red }
}
