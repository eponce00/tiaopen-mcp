param(
    [Parameter(Mandatory)][string]$SclPath,
    [string]$ProjectMatch = "Testing_Playground",
    [switch]$SkipCompile
)

# Imports a plain .scl ExternalSource file into TIA Portal, generates block(s) from it,
# optionally compiles the PLC, and outputs a JSON result.
#
# The .scl file must contain a complete block declaration, e.g.:
#
#   FUNCTION_BLOCK "FB_MyBlock"
#   { S7_Optimized_Access := 'TRUE' }
#   VAR_INPUT
#     Enable : Bool;
#   END_VAR
#   VAR_OUTPUT
#     Done : Bool;
#   END_VAR
#   VAR
#     State : Int;
#   END_VAR
#   BEGIN
#     State := 0;
#   END_FUNCTION_BLOCK
#
# Output JSON:
#   { "Imported": true, "Generated": true, "Compiled": true,
#     "State": "Success", "Errors": 0, "Warnings": 0,
#     "Messages": [ { "State": "Error", "Path": "...", "Description": "..." } ] }
#
# Usage:
#   .\scripts\import-scl.ps1 -SclPath .\tmp\FB_KistlerNC.scl
#   .\scripts\import-scl.ps1 -SclPath .\tmp\FB_KistlerNC.scl -SkipCompile

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

function Flatten-CompileMsg($msg, $blockName) {
    $mt    = $msg.GetType()
    $st    = try { $mt.GetProperty("State").GetValue($msg, $null).ToString() } catch { "Unknown" }
    $desc  = try { $mt.GetProperty("Description").GetValue($msg, $null) } catch { $null }
    $path  = try { $mt.GetProperty("Path").GetValue($msg, $null) } catch { $null }
    $kids  = try { $mt.GetProperty("Messages").GetValue($msg, $null) } catch { $null }
    $result = @()
    if ($desc -and $desc.ToString().Trim() -ne '') {
        $result += [ordered]@{
            State       = $st
            Block       = $blockName
            Path        = if ($path) { $path.ToString() } else { $null }
            Description = $desc.ToString()
        }
    }
    if ($kids) { foreach ($child in $kids) { $result += Flatten-CompileMsg $child $blockName } }
    return $result
}

# Resolve path before attaching to TIA
$resolvedScl = [System.IO.Path]::GetFullPath($SclPath)
if (-not (Test-Path $resolvedScl)) {
    Write-Error "SCL file not found: $resolvedScl"
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

    $result = [ordered]@{
        Imported  = $false
        Generated = $false
        Compiled  = $false
        State     = $null
        Errors    = 0
        Warnings  = 0
        Messages  = @()
    }

    # ── Import ExternalSource ────────────────────────────────────────────────
    $sourceName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedScl)

    # Remove existing ExternalSource with same name if present
    $existing = $plc.ExternalSourceGroup.ExternalSources |
        Where-Object { $_.Name -eq $sourceName } |
        Select-Object -First 1
    if ($existing) { $existing.Delete() }

    $extSource = $plc.ExternalSourceGroup.ExternalSources.CreateFromFile($sourceName, $resolvedScl)
    $result.Imported = $true

    # ── Generate blocks from ExternalSource ─────────────────────────────────
    $extSource.GenerateBlocksFromSource()
    $result.Generated = $true

    # ── Optionally compile ───────────────────────────────────────────────────
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
            $p = try { $msg.GetType().GetProperty("Path").GetValue($msg, $null) } catch { $null }
            $blockName = if ($p) { $p.ToString() } else { "PLC" }
            $flat = Flatten-CompileMsg $msg $blockName
            foreach ($f in $flat) {
                if ($f.State -eq "Error")   { $errCount++ }
                if ($f.State -eq "Warning") { $wrnCount++ }
                $msgList += $f
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
