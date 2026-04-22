param(
    [string]$ProjectMatch = "Testing_Playground"
)

# Compiles the PLC software and outputs a JSON result.
# Output: { "State": "Success", "Errors": 0, "Warnings": 0,
#           "Messages": [ { "State": "Error", "Path": "PLC_1/Main", "Description": "..." } ] }
#
# Exit code 0 = compile succeeded (State == Success or Warning)
# Exit code 1 = compile failed or script error

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

    $compileType   = [Siemens.Engineering.Compiler.ICompilable]
    $compiler      = Invoke-GenericGetService $plc $compileType
    if (-not $compiler) { Write-Error "ICompilable service not found on PlcSoftware."; exit 1 }

    # ── Step 1: compile individual blocks first to capture per-block errors ──
    $blockMsgList = @()
    $blockErrCount = 0

    # Recursively flatten a compile message tree into a list
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
        if ($kids) {
            foreach ($child in $kids) {
                $result += Flatten-CompileMsg $child $blockName
            }
        }
        return $result
    }

    foreach ($block in $plc.BlockGroup.Blocks) {
        $blockCompiler = Invoke-GenericGetService $block $compileType
        if (-not $blockCompiler) { continue }
        try {
            $br      = $blockCompiler.GetType().GetMethod("Compile").Invoke($blockCompiler, $null)
            $brType  = $br.GetType()
            $brState = $brType.GetProperty("State").GetValue($br, $null).ToString()
            if ($brState -eq "Error") {
                $brMsgs = $brType.GetProperty("Messages").GetValue($br, $null)
                foreach ($bm in $brMsgs) {
                    $flat = Flatten-CompileMsg $bm $block.Name
                    foreach ($f in $flat) {
                        if ($f.State -eq "Error") { $blockErrCount++ }
                        $blockMsgList += $f
                    }
                }
            }
        } catch { $blockMsgList += [ordered]@{ State="Error"; Block=$block.Name; Path=$null; Description="Script error: $_" } }
    }

    # ── Step 2: full PLC compile for final state/summary ──
    $compileResult = $compiler.GetType().GetMethod("Compile").Invoke($compiler, $null)
    $resultType    = $compileResult.GetType()

    $state    = $resultType.GetProperty("State").GetValue($compileResult, $null).ToString()
    $messages = $resultType.GetProperty("Messages").GetValue($compileResult, $null)

    $msgList  = @()
    $errCount = 0
    $wrnCount = 0
    foreach ($msg in $messages) {
        $mt      = $msg.GetType()
        $mState  = $mt.GetProperty("State").GetValue($msg, $null).ToString()
        $mPath   = $mt.GetProperty("Path").GetValue($msg, $null)
        $mDesc   = $mt.GetProperty("Description").GetValue($msg, $null)

        if ($mState -eq "Error")   { $errCount++ }
        if ($mState -eq "Warning") { $wrnCount++ }

        if ($mDesc) {   # skip empty informational rows
            $msgList += [ordered]@{
                State       = $mState
                Path        = if ($mPath) { $mPath.ToString() } else { $null }
                Description = $mDesc.ToString()
            }
        }
    }

    # Merge per-block errors at the front when present
    if ($blockMsgList.Count -gt 0) {
        $msgList = $blockMsgList + $msgList
        $errCount = [Math]::Max($errCount, $blockErrCount)
    }

    [ordered]@{
        State    = $state
        Errors   = $errCount
        Warnings = $wrnCount
        Messages = $msgList
    } | ConvertTo-Json -Depth 5

    if ($state -eq "Error") { exit 1 }
} finally {
    $tia.Dispose()
}
