$ErrorActionPreference = "Stop"
$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

$tia = ([Siemens.Engineering.TiaPortal]::GetProcesses())[0].Attach()
$project = ($tia.LocalSessions | Where-Object { $_.Project -ne $null } | Select-Object -First 1).Project
$lib = $project.ProjectLibrary

# Probe MasterCopyFolder/Kistler
$mcf = $lib.MasterCopyFolder
$kistlerMC = $mcf.Folders | Where-Object { $_.Name -eq "Kistler" }
Write-Host "Kistler MasterCopy folder: $($kistlerMC.GetType().FullName)"
Write-Host "Properties:"
$kistlerMC.GetType().GetProperties() | ForEach-Object { Write-Host "  $($_.Name) : $($_.PropertyType.Name)" }
Write-Host "MasterCopies:"
foreach ($mc in $kistlerMC.MasterCopies) {
    Write-Host "  $($mc.Name) [$($mc.GetType().Name)]"
}
Write-Host "Subfolders:"
foreach ($f in $kistlerMC.Folders) {
    Write-Host "  $($f.Name)"
    foreach ($mc in $f.MasterCopies) { Write-Host "    MC: $($mc.Name)" }
}

# Also check if any existing HMI Library Type exists we can export as template
Write-Host "`n=== All Types_HMI subtypes ==="
$lsicar = $lib.TypeFolder.Folders | Where-Object { $_.Name -eq "LSicar" }
$hmiF   = $lsicar.Folders | Where-Object { $_.Name -eq "Types_HMI" }
foreach ($subfolder in $hmiF.Folders) {
    $cnt = @($subfolder.Types).Count
    Write-Host "  $($subfolder.Name): $cnt types"
    foreach ($t in $subfolder.Types) { Write-Host "    -> $($t.Name)" }
}
