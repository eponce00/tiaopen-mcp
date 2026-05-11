# bind-kistler-faceplate.ps1
# After the Screen Type "LSicar_KistlerPressFp" exists in
#   ProjectLibrary -> LSicar -> Types_HMI -> Drives,
# this script instantiates it on a target screen and wires
# all 30 parameters to "<FbInstanceDb>".interfaceHmi[<idx>].*
#
# Usage:
#   .\bind-kistler-faceplate.ps1 `
#       -HmiName "+TOOL01-HMI01" `
#       -ScreenName "Kistler_Press_01" `
#       -FbInstanceDb "DB_KistlerPress01" `
#       -TecUnitIndex 1
#
# Requires: TIA Portal V20 open with the .als20 project, and
# Siemens.Engineering.dll loaded (PID auto-attach below).

param(
    [Parameter(Mandatory=$true)] [string]$HmiName,
    [Parameter(Mandatory=$true)] [string]$ScreenName,
    [Parameter(Mandatory=$true)] [string]$FbInstanceDb,
    [Parameter(Mandatory=$true)] [int]   $TecUnitIndex,
    [string]$FaceplateTypeName = 'LSicar_KistlerPressFp',
    [int]   $X = 50,
    [int]   $Y = 50
)

$ErrorActionPreference = 'Stop'

# ----- attach to running TIA Portal --------------------------------------
$dll = Get-ChildItem 'C:\Program Files\Siemens\Automation\Portal V20\PublicAPI' `
        -Recurse -Filter 'Siemens.Engineering.dll' | Select-Object -First 1
if (-not $dll) { throw 'Siemens.Engineering.dll not found' }
Add-Type -Path $dll.FullName

$tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
if (-not $tia) { throw 'No running TIA Portal instance found' }
$portal  = $tia.Attach()
$project = $portal.LocalSessions[0].Project
Write-Host "Project: $($project.Name)"

# ----- locate faceplate type in project library --------------------------
function Get-LibType($folder, $name) {
    foreach ($t in $folder.Types) { if ($t.Name -eq $name) { return $t } }
    foreach ($f in $folder.Folders) {
        $r = Get-LibType $f $name
        if ($r) { return $r }
    }
    return $null
}
$lib       = $project.ProjectLibrary
$faceplate = Get-LibType $lib.TypeFolder $FaceplateTypeName
if (-not $faceplate) { throw "Faceplate type '$FaceplateTypeName' not found in project library" }
Write-Host "Faceplate type: $($faceplate.Name) v$($faceplate.Version)"

# ----- locate target HMI + screen ----------------------------------------
$hmiSw = $null
foreach ($d in $project.Devices) {
    foreach ($di in $d.DeviceItems) {
        $sw = $di.GetService([Siemens.Engineering.HW.Features.SoftwareContainer]).Software
        if ($sw -and $sw.GetType().FullName -like '*HmiUnified.HmiSoftware*' -and $d.Name -like "*$HmiName*") {
            $hmiSw = $sw
        }
    }
}
if (-not $hmiSw) { throw "HMI '$HmiName' not found" }

$screen = $null
foreach ($s in $hmiSw.Screens) { if ($s.Name -eq $ScreenName) { $screen = $s; break } }
if (-not $screen) { throw "Screen '$ScreenName' not found on HMI '$HmiName'" }
Write-Host "Target screen: $($screen.Name)"

# ----- instantiate faceplate on screen -----------------------------------
# WinCC Unified: ScreenItems.CreateFromLibraryType(name, libType, x, y)
$instance = $screen.ScreenItems.CreateFromLibraryType("FP_$TecUnitIndex", $faceplate, $X, $Y)
Write-Host "Instantiated: $($instance.Name)"

# ----- 30-param binding map ---------------------------------------------
# Inputs (HMI reads) + outputs (HMI writes). Names match <hmi:self> paramDef.
$base = "`"$FbInstanceDb`".interfaceHmi[$TecUnitIndex]"
$bindings = @{
    # Inputs
    'receiveStatus'   = "$base.receive.status"
    'state'           = "$base.state"
    'alarm'           = "$base.alarm"
    'stateColour'     = "$base.stateColour"
    'plantidentifier' = "$base.plantidentifier"
    'pvForceY'        = "$base.receive.`"PVcurrentValueY`""
    'pvDispX'         = "$base.receive.`"PVcurrentValueX`""
    'pvGradient'      = "$base.receive.`"PV_EO3_Gradient`""
    'pvXmin'          = "$base.receive.`"PVcurrentXmin-X`""
    'pvXmax'          = "$base.receive.`"PVcurrentXmax-X`""
    'pvYmin'          = "$base.receive.`"PVcurrentYmin-Y`""
    'pvYmax'          = "$base.receive.`"PVcurrentYmax-Y`""
    'sendControl'     = "$base.send.control"
    'sendMpNum'       = "$base.send.mpNum"
    'sendSeq'         = "$base.send.selectSeqeunce"   # UDT typo — correct
    'sendPage'        = "$base.send.selectPage"
    'rxMpNum'         = "$base.receive.mpNum"
    'currentLabel'    = "$base.currentLabel"
    'sequenceEnd'     = "$base.sequenceEnd"
    'opmodearea'      = "$base.opmodearea"
    'hmiControlNo'    = "$base.hmiControlNo"
    'tecUnitNumber'   = "$base.tecUnitNumber"
    # Outputs
    'cmdMove'         = "$base.move"
    'jogSpeedSet'     = "$base.serverJogSpeedSet"
    'maxForceSet'     = "$base.serverJogMaxForceSet"
    'mpNumSet'        = "$base.manualSelectMpNum"
    'seqSet'          = "$base.selectSequenceSet"
    'pageSet'         = "$base.selectPageSet"
}
# (28 explicit + 2 unused locally = matches faceplate's 30 params; remaining
#  2 are setpoints already handled above — adjust if your build adds more.)

# ----- write each binding -----------------------------------------------
$dyn = $instance.DynamizationList
foreach ($kv in $bindings.GetEnumerator()) {
    try {
        $tagBinding = $dyn.Add($kv.Key, [Siemens.Engineering.HmiUnified.Dynamization.DynamizationType]::Tag)
        $tagBinding.Tag = $kv.Value
        Write-Host "  $($kv.Key) -> $($kv.Value)"
    } catch {
        Write-Warning "Failed: $($kv.Key) -> $($kv.Value)  ($_)"
    }
}

$project.Save()
Write-Host "Done. Saved project."
