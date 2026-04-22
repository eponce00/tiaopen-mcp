param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Reports high-level TIA Portal process/session status for troubleshooting.

$ErrorActionPreference = "Stop"

$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

$result = [ordered]@{
    State        = "Success"
    ProjectMatch = $ProjectMatch
    TimestampUtc = [DateTime]::UtcNow.ToString("o")
    Processes    = @()
}

try {
    $processes = [Siemens.Engineering.TiaPortal]::GetProcesses()
    foreach ($p in $processes) {
        $wp = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        $title = if ($wp) { $wp.MainWindowTitle } else { $null }
        $entry = [ordered]@{
            Id         = $p.Id
            Mode       = $p.Mode.ToString()
            Window     = $title
            IsMatch    = if ($title) { [bool]($title -match $ProjectMatch) } else { $false }
            Projects   = @()
            Attachable = $false
            Error      = $null
        }

        try {
            $tia = $p.Attach()
            $entry.Attachable = $true
            foreach ($proj in $tia.Projects) {
                $entry.Projects += [ordered]@{
                    Name = $proj.Name
                    Path = try { if ($proj.Path) { $proj.Path.FullName } else { $null } } catch { $null }
                }
            }
            $tia.Dispose()
        } catch {
            $entry.Error = $_.Exception.Message
        }

        $result.Processes += $entry
    }
} catch {
    $result.State = "Error"
    $result.Processes = @()
    $result.Error = $_.Exception.Message
}

$result | ConvertTo-Json -Depth 8
