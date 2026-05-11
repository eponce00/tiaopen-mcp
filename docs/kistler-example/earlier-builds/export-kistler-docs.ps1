$ErrorActionPreference = "Stop"
$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null
$tiaProcess = $null
foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
    if ($p.Mode -ne [Siemens.Engineering.TiaPortalMode]::WithUserInterface) { continue }
    $tiaProcess = $p; break
}
$tia = $tiaProcess.Attach()
try {
    $project = $tia.LocalSessions[0].Project
    function Find-LibraryType { param($Folder,[string]$Name)
        foreach ($t in $Folder.Types) { if ($t.Name -ieq $Name) { return $t } }
        foreach ($sub in $Folder.Folders) { $r = Find-LibraryType $sub $Name; if ($r) { return $r } }
        return $null }
    $libType = Find-LibraryType $project.ProjectLibrary.TypeFolder "LSicar_KistlerPress"
    Write-Host "Versions:"
    foreach ($v in $libType.Versions) { Write-Host "  $($v.VersionNumber) $($v.State) default=$($v.IsDefault)" }
    $ver = $libType.Versions | Where-Object { $_.State.ToString() -eq "Committed" } | Sort-Object { $_.VersionNumber } | Select-Object -Last 1
    Write-Host "Exporting: $($ver.VersionNumber)"
    $expDir = "C:\Users\MudasserWahab\Claude Code\export_kistler_base"
    if (Test-Path $expDir) { Remove-Item $expDir -Recurse -Force }
    New-Item -ItemType Directory -Path $expDir | Out-Null
    $r = $ver.ExportAsDocuments(
        [System.IO.DirectoryInfo]::new($expDir),
        "LSicar_KistlerPress",
        "SimaticMLWithExportOptionsNone",
        [Siemens.Engineering.Library.LibraryExportOptions]::None
    )
    Write-Host "Export: $($r.TransferResultState)"
} finally { $tia.Dispose() }
