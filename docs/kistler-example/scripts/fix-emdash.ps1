# Fix em-dash (encoded as UTF-8 -> CP1252 mojibake "a€"") in HMI labels.
# Replaces only the *_real_dash and *_byte_dash items on _Kistler_Press_01.

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

$replacement = '-'   # plain hyphen, safe in any encoding
$fixed = 0
foreach ($it in $screen.ScreenItems) {
    if ($it.Name -match '_(real|byte)_dash$') {
        $textProp = $it.GetType().GetProperty('Text')
        if ($textProp) {
            $mlt = $textProp.GetValue($it)
            if ($mlt) {
                $xml = "<body><p>$replacement</p></body>"
                foreach ($mi in $mlt.Items) { try { $mi.SetAttribute('Text', $xml) } catch {} }
                $fixed++
                Write-Host "Fixed: $($it.Name)"
            }
        }
    }
}
Write-Host "Total fixed: $fixed"
$session.Save()
Write-Host "Saved."
