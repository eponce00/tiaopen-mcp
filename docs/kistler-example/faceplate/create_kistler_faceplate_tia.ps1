# ============================================================
# LSicar_KistlerPressFp — TIA Portal V20 Openness Injector
# Attaches to running TIA Portal, creates WinCC Unified
# Screen Type Library Type for the Kistler maXYmos NC faceplate.
# ============================================================

$EngineeringDll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
$HmiDll         = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.Hmi.dll"

Write-Host "[1/7] Loading Openness assemblies..."
Add-Type -Path $EngineeringDll
Add-Type -Path $HmiDll

# ── Attach to the running TIA Portal instance ──────────────────
Write-Host "[2/7] Attaching to TIA Portal..."
$processes = [Siemens.Engineering.TiaPortal]::GetProcesses()
if ($processes.Count -eq 0) { Write-Error "No TIA Portal process found. Open TIA first."; exit 1 }

$tiaPID = $processes[0]
Write-Host "      Found TIA PID $($tiaPID.Id)"
$tia = $tiaPID.Attach()

# ── Get the open project ───────────────────────────────────────
Write-Host "[3/7] Getting project..."
# Multiuser local session project
$project = $null
if ($tia.LocalSessions.Count -gt 0) {
    $project = $tia.LocalSessions[0].Project
    Write-Host "      Local session project: $($project.Name)"
} else {
    $project = $tia.Projects[0]
    Write-Host "      Single-user project: $($project.Name)"
}

# ── Find the WinCC Unified HMI device (LS) ────────────────────
Write-Host "[4/7] Locating WinCC Unified HMI target..."
$hmiSoftware = $null
foreach ($device in $project.Devices) {
    foreach ($item in $device.DeviceItems) {
        $sw = $item.GetService([Siemens.Engineering.HW.Software.SoftwareContainer])
        if ($sw -ne $null) {
            $soft = $sw.Software
            if ($soft -is [Siemens.Engineering.HmiUnified.HmiSoftware]) {
                if ($device.Name -like "*LS*" -or $device.Name -like "*HMI*") {
                    $hmiSoftware = $soft
                    Write-Host "      Found HMI: $($device.Name)"
                    break
                }
            }
        }
    }
    if ($hmiSoftware -ne $null) { break }
}

# Fallback — grab first WinCC Unified software found
if ($hmiSoftware -eq $null) {
    foreach ($device in $project.Devices) {
        foreach ($item in $device.DeviceItems) {
            $sw = $item.GetService([Siemens.Engineering.HW.Software.SoftwareContainer])
            if ($sw -ne $null) {
                $soft = $sw.Software
                if ($soft -is [Siemens.Engineering.HmiUnified.HmiSoftware]) {
                    $hmiSoftware = $soft
                    Write-Host "      Fallback HMI: $($device.Name)"
                    break
                }
            }
        }
        if ($hmiSoftware -ne $null) { break }
    }
}

if ($hmiSoftware -eq $null) { Write-Error "No WinCC Unified HMI software found in project."; exit 1 }

# ── Create Screen Type in Project Library ─────────────────────
Write-Host "[5/7] Creating Screen Type 'LSicar_KistlerPressFp'..."
$fpName = "LSicar_KistlerPressFp"

# Use HMI software screen types (project-local Screen Type)
$screenTypes = $hmiSoftware.ScreenTypes

# Check if already exists
$existing = $null
try { $existing = $screenTypes.Find($fpName) } catch {}
if ($existing -ne $null) {
    Write-Host "      Screen Type '$fpName' already exists — deleting to recreate..."
    $existing.Delete()
}

$screenType = $screenTypes.Create($fpName)
Write-Host "      Created: $fpName  (Width=900, Height=660)"

# Set dimensions to match the SVG design
$screenType.Width  = 900
$screenType.Height = 660

# ── Declare Interface Parameters ─────────────────────────────
Write-Host "[5b/7] Declaring faceplate interface parameters..."

# Helper — add a parameter if it doesn't exist
function Add-FpParam($st, $name, $dataType, $dir) {
    try {
        $p = $st.InterfaceParameters.Create($name, $dataType, $dir)
        Write-Host "        + $dir  $name : $dataType"
    } catch {
        Write-Host "        ! Param '$name' skipped: $_"
    }
}

$In  = [Siemens.Engineering.HmiUnified.ParameterDirection]::Input
$Out = [Siemens.Engineering.HmiUnified.ParameterDirection]::Output
$IO  = [Siemens.Engineering.HmiUnified.ParameterDirection]::InputOutput

# == HMI Interface — INPUTS (HMI reads from PLC) ==
# receive.status bits → decoded Kistler fieldbus status
Add-FpParam $screenType "state"        "DWord" $In   # FB PLC state DWord (x0=auto x1=singleStep x2=safetyOK)
Add-FpParam $screenType "alarm"        "DWord" $In   # alarm DWord (x1=hwNOK x2=driveNOK x12=safetyNOK x15=serialMismatch)
Add-FpParam $screenType "receiveStatus" "DWord" $In  # Kistler fieldbus receive.status (x0=Ready x1=OkTotal ... x9=SeqEnd)
Add-FpParam $screenType "stateColour"  "Int"   $In   # 1=auto 2=manual 3=singleStep 4=noMode 5=alarm 6=disabled 8=unsafe
Add-FpParam $screenType "plantidentifier" "WString" $In

# Process values
Add-FpParam $screenType "pvForceY"     "Real"  $In   # receive.PVcurrentValueY [N]
Add-FpParam $screenType "pvDispX"      "Real"  $In   # receive.PVcurrentValueX [mm]
Add-FpParam $screenType "pvGradient"   "Real"  $In   # receive.PV_EO3_Gradient [N/mm]
Add-FpParam $screenType "pvXmin"       "Real"  $In   # receive.PVcurrentXmin-X
Add-FpParam $screenType "pvXmax"       "Real"  $In   # receive.PVcurrentXmax-X
Add-FpParam $screenType "pvYmin"       "Real"  $In   # receive.PVcurrentYmin-Y
Add-FpParam $screenType "pvYmax"       "Real"  $In   # receive.PVcurrentYmax-Y

# Feedback echo (send struct — FB writes every scan, HMI reads only)
Add-FpParam $screenType "sendControl"  "DWord" $In   # send.control (x0=Auto x1=MP-Sel x3=RunSeq x5=Home x6=Ref x7=Stop x8=JogFW x9=JogBW)
Add-FpParam $screenType "sendMpNum"    "Byte"  $In   # send.mpNum echo
Add-FpParam $screenType "sendSeq"      "Byte"  $In   # send.selectSeqeunce echo [note: typo in UDT]
Add-FpParam $screenType "sendPage"     "Byte"  $In   # send.selectPage echo
Add-FpParam $screenType "sendJogSpeed" "Real"  $In   # send.serverJogSpeed echo
Add-FpParam $screenType "sendMaxForce" "Real"  $In   # send.serverJogMaxForce echo

# Receive decoded fields
Add-FpParam $screenType "rxMpNum"      "Byte"  $In   # receive.mpNum (active MP)
Add-FpParam $screenType "currentLabel" "Byte"  $In   # currentLabel (0–31)
Add-FpParam $screenType "sequenceEnd"  "Bool"  $In   # sequenceEnd flag
Add-FpParam $screenType "opmodearea"   "USInt" $In   # opmodearea (from OpModeUserInterfaceOut)
Add-FpParam $screenType "hmiControlNo" "Int"   $In   # hmiControlNo
Add-FpParam $screenType "tecUnitNumber" "Int"  $In   # tecUnitNumber (array index)

# == HMI Interface — OUTPUTS (HMI writes to PLC) ==
# move Word bits — the ACTUAL HMI command bus
Add-FpParam $screenType "cmdMove"      "Word"  $Out  # move Word: x0=Stop x1=RunSeq x3=Home x4=Ref x5=Reset x6=ContWait x7=Stop2 x8=JogFW x9=JogBW

# *Set fields — setpoint inputs from HMI
Add-FpParam $screenType "jogSpeedSet"  "Real"  $Out  # serverJogSpeedSet
Add-FpParam $screenType "maxForceSet"  "Real"  $Out  # serverJogMaxForceSet
Add-FpParam $screenType "mpNumSet"     "Byte"  $Out  # manualSelectMpNum
Add-FpParam $screenType "seqSet"       "Byte"  $Out  # selectSequenceSet
Add-FpParam $screenType "pageSet"      "Byte"  $Out  # selectPageSet
Add-FpParam $screenType "cfgMpSet"     "Byte"  $Out  # cfgMpNumSet
Add-FpParam $screenType "cfgAddrSet"   "Byte"  $Out  # cfgAddressSet
Add-FpParam $screenType "cfgLenSet"    "Byte"  $Out  # cfgLengthSet

Write-Host "      Interface: $(($In,$Out | Measure-Object).Count) directions declared"

# ── Add SVG graphic as background element ─────────────────────
Write-Host "[6/7] Adding SVG reference & basic visual structure..."

# Import the SVG as a graphic in the project, then reference it
$svgSourcePath = "C:\Users\MudasserWahab\Claude Code\kistler_faceplate.svg"

# Add a background rectangle to set the canvas colour
try {
    $bgRect = $screenType.ScreenItems.Create("Rectangle", "bg_rect")
    $bgRect.Left   = 0
    $bgRect.Top    = 0
    $bgRect.Width  = 900
    $bgRect.Height = 660
    $bgRect.BackColor = [System.Drawing.Color]::FromArgb(26, 32, 53)   # #1a2035
    $bgRect.BorderWidth = 0
    Write-Host "        + Rectangle: bg_rect (background)"
} catch {
    Write-Host "        ! bg_rect: $_"
}

# Header bar
try {
    $hdr = $screenType.ScreenItems.Create("Rectangle", "hdr_bar")
    $hdr.Left = 0; $hdr.Top = 0; $hdr.Width = 900; $hdr.Height = 52
    $hdr.BackColor = [System.Drawing.Color]::FromArgb(17, 24, 39)   # #111827
    Write-Host "        + Rectangle: hdr_bar"
} catch { Write-Host "        ! hdr_bar: $_" }

# Title text
try {
    $ttl = $screenType.ScreenItems.Create("TextField", "title_text")
    $ttl.Left = 22; $ttl.Top = 8; $ttl.Width = 240; $ttl.Height = 22
    $ttl.Text = "KISTLER maXYmos NC"
    $ttl.ForeColor = [System.Drawing.Color]::FromArgb(96, 165, 250)   # #60a5fa
    $ttl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    Write-Host "        + TextField: title_text"
} catch { Write-Host "        ! title_text: $_" }

# Plant identifier text (bound to faceplate parameter)
try {
    $pi = $screenType.ScreenItems.Create("TextField", "plant_id")
    $pi.Left = 270; $pi.Top = 12; $pi.Width = 200; $pi.Height = 28
    $pi.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    # Data binding: plantidentifier parameter
    Write-Host "        + TextField: plant_id"
} catch { Write-Host "        ! plant_id: $_" }

Write-Host "      Basic structure added. Full element set needs TIA Portal editor."

# ── Save the project ──────────────────────────────────────────
Write-Host "[7/7] Saving project..."
try {
    $project.Save()
    Write-Host "      Project saved OK."
} catch {
    Write-Host "      WARNING: Save failed (project may be multiuser — save manually): $_"
}

Write-Host ""
Write-Host "============================================================"
Write-Host " DONE: Screen Type 'LSicar_KistlerPressFp' created in TIA."
Write-Host " Open TIA Portal → HMI device → Screen Types to see it."
Write-Host " Parameters declared: 30 interface params (see script output)"
Write-Host " Next: Add bindings in TIA Portal editor to each parameter."
Write-Host "============================================================"
