param(
    [Parameter(Mandatory)][string]$BlockName,
    [string]$ProjectMatch = "Testing_Playground",
    [string]$OutputPath   = ""    # if empty, prints XML to stdout
)

# Exports a single block and either writes it to a file or prints it to stdout.
# The agent can pipe this to a file or read it directly as a string.
#
# Usage:
#   .\scripts\read-block.ps1 -BlockName Main
#   .\scripts\read-block.ps1 -BlockName Main -OutputPath .\tmp\Main.xml

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

    function Find-Block {
        param($Group, [string]$Name)
        $b = $Group.Blocks.Find($Name)
        if ($b) { return $b }
        foreach ($sub in $Group.Groups) {
            $b = Find-Block $sub $Name
            if ($b) { return $b }
        }
        return $null
    }

    function Find-Type {
        param($Group, [string]$Name)
        $t = $Group.Types.Find($Name)
        if ($t) { return $t }
        foreach ($sub in $Group.Groups) {
            $t = Find-Type $sub $Name
            if ($t) { return $t }
        }
        return $null
    }

    $block = Find-Block $plc.BlockGroup $BlockName
    if (-not $block) { $block = Find-Type $plc.TypeGroup $BlockName }
    if (-not $block) { Write-Error "Block '$BlockName' not found."; exit 1 }

    if ($OutputPath) {
        $resolved = [System.IO.Path]::GetFullPath($OutputPath)
        if (Test-Path $resolved) { Remove-Item $resolved -Force }
        try {
            $block.Export([System.IO.FileInfo]::new($resolved), [Siemens.Engineering.ExportOptions]::WithDefaults)
        } catch {
            # Fallback: GenerateSource (works for UDTs in online mode)
            $svc = Invoke-GenericGetService $block ([Siemens.Engineering.SW.ExternalSources.IExternalSourceGeneratable])
            if ($svc) { $svc.GenerateSource([System.IO.FileInfo]::new($resolved)) }
            else { throw }
        }
        Write-Host $resolved
    } else {
        $tmp = [System.IO.Path]::GetTempFileName() + ".xml"
        try {
            try {
                $block.Export([System.IO.FileInfo]::new($tmp), [Siemens.Engineering.ExportOptions]::WithDefaults)
                Get-Content $tmp -Raw
            } catch {
                # Fallback: GenerateSource to .scl
                $tmpScl = [System.IO.Path]::GetTempFileName() + ".scl"
                try {
                    $svc = Invoke-GenericGetService $block ([Siemens.Engineering.SW.ExternalSources.IExternalSourceGeneratable])
                    if ($svc) {
                        $svc.GenerateSource([System.IO.FileInfo]::new($tmpScl))
                        Get-Content $tmpScl -Raw
                    } else { throw "GenerateSource not available" }
                } finally {
                    Remove-Item $tmpScl -Force -ErrorAction SilentlyContinue
                }
            }
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
} finally {
    $tia.Dispose()
}
