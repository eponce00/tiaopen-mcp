param(
    [Parameter(Mandatory)][string]$XmlPath,
    [string]$ProjectMatch = "Testing_Playground",
    [switch]$SkipCompile
)

# Imports a block XML file into the PLC, optionally compiles, and outputs a JSON result.
# Output:
#   { "Imported": true, "Compiled": true, "State": "Success", "Errors": 0, "Warnings": 0,
#     "Messages": [ { "State": "Error", "Path": "...", "Description": "..." } ] }
#
# Exit code 0 = import (and optional compile) succeeded
# Exit code 1 = any failure
#
# Usage:
#   .\scripts\write-block.ps1 -XmlPath .\tmp\Main.xml
#   .\scripts\write-block.ps1 -XmlPath .\tmp\Main.xml -SkipCompile

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

# Resolve and validate path before attaching to TIA
$resolvedXml = [System.IO.Path]::GetFullPath($XmlPath)
if (-not (Test-Path $resolvedXml)) {
    Write-Error "XML file not found: $resolvedXml"
    exit 1
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

    # Import
    $fileInfo     = [System.IO.FileInfo]::new($resolvedXml)
    $importOption = [Siemens.Engineering.ImportOptions]::Override
    $plc.BlockGroup.Blocks.Import($fileInfo, $importOption) | Out-Null

    $result = [ordered]@{ Imported = $true; Compiled = $false; State = $null; Errors = 0; Warnings = 0; Messages = @() }

    if (-not $SkipCompile) {
        $compileType   = [Siemens.Engineering.Compiler.ICompilable]
        $compiler      = Invoke-GenericGetService $plc $compileType
        if (-not $compiler) { Write-Error "ICompilable service not found on PlcSoftware."; exit 1 }

        $compileResult = $compiler.GetType().GetMethod("Compile").Invoke($compiler, $null)
        $rt            = $compileResult.GetType()
        $state         = $rt.GetProperty("State").GetValue($compileResult, $null).ToString()
        $messages      = $rt.GetProperty("Messages").GetValue($compileResult, $null)

        $msgList  = @()
        $errCount = 0
        $wrnCount = 0
        foreach ($msg in $messages) {
            $mt     = $msg.GetType()
            $mState = $mt.GetProperty("State").GetValue($msg, $null).ToString()
            $mPath  = $mt.GetProperty("Path").GetValue($msg, $null)
            $mDesc  = $mt.GetProperty("Description").GetValue($msg, $null)
            if ($mState -eq "Error")   { $errCount++ }
            if ($mState -eq "Warning") { $wrnCount++ }
            if ($mDesc) {
                $msgList += [ordered]@{
                    State       = $mState
                    Path        = if ($mPath) { $mPath.ToString() } else { $null }
                    Description = $mDesc.ToString()
                }
            }
        }

        $result.Compiled = $true
        $result.State    = $state
        $result.Errors   = $errCount
        $result.Warnings = $wrnCount
        $result.Messages = $msgList
    }

    $result | ConvertTo-Json -Depth 5

    if ($result.State -eq "Error") { exit 1 }
} finally {
    $tia.Dispose()
}
