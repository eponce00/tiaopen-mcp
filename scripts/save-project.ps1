param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Saves the currently open TIA project.
# Output: { "State": "Success", "Project": "Testing_Playground", "ProjectPath": "...", "Saved": true }
#
# Exit code 0 = success
# Exit code 1 = script error

$ErrorActionPreference = "Stop"

$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

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
    if (-not $project) { $project = $tia.Projects | Select-Object -First 1 }
    if (-not $project) { Write-Error "No open project found in attached TIA process."; exit 1 }

    $project.Save()

    @{
        State = "Success"
        Project = $project.Name
        ProjectPath = if ($project.Path) { $project.Path.FullName } else { $null }
        Saved = $true
    } | ConvertTo-Json -Compress
}
catch {
    Write-Error "Save failed: $($_.Exception.Message)"
    exit 1
}
