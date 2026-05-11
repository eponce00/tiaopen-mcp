# build-kistler-screen.ps1
# Builds a complete Kistler maXYmos NC press screen via TIA Openness on a
# WinCC Unified HMI. Layout follows the LSicar_KistlerPressFp design from
# memory: status LEDs from receive.status, alarm LEDs from alarm DWord,
# F-D area, process value gauges, control buttons, setpoints, program
# selection, and sequence/echo footer.
#
# Bindings: each visual element is wired to an HMI tag by name. Tag names
# follow "<TagPrefix><FieldShortName>". If a tag does not yet exist, the
# binding is logged and skipped (visual still builds). The script reports
# a manifest of all expected tag names at the end so you can pre-create
# them in the HMI tag table.
#
# Usage:
#   .\build-kistler-screen.ps1
#   .\build-kistler-screen.ps1 -HmiName '+TOOL01-HMI01' -ScreenName '_Kistler_Press_01' -TagPrefix 'Kistler1_'

param(
    [string]$HmiName     = '',                       # blank = first HmiUnified found
    [string]$ScreenName  = '_Kistler_Press_01',
    [string]$TagPrefix   = 'Kistler1_',
    [int]   $Width       = 1920,
    [int]   $Height      = 1080
)

$ErrorActionPreference = 'Stop'

# ---- Attach -----------------------------------------------------------
$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null
$asm = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Siemens.Engineering' } | Select-Object -First 1

$tia     = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal  = $tia.Attach()
$session = $portal.LocalSessions[0]
$project = $session.Project
Write-Host "Project: $($project.Name)"

# ---- HmiSoftware -------------------------------------------------------
$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
function Get-Sw($di) {
    $m = $di.GetType().GetMethod('GetService').MakeGenericMethod($swT)
    return $m.Invoke($di, $null)
}
function Walk($items) {
    foreach ($it in $items) {
        try {
            $svc = Get-Sw $it
            if ($svc -and $svc.Software -and $svc.Software.GetType().FullName -match 'HmiUnified') {
                if (-not $HmiName -or $it.Name -like "*$HmiName*") {
                    return @{ Sw = $svc.Software; Name = $it.Name }
                }
            }
        } catch {}
        if ($it.DeviceItems) { $r = Walk $it.DeviceItems; if ($r) { return $r } }
    }
    return $null
}
$hmi = $null
foreach ($d in $project.Devices) { $hmi = Walk $d.DeviceItems; if ($hmi) { break } }
if (-not $hmi) { throw "No HmiUnified software found" }
$hmiSw = $hmi.Sw
Write-Host "HMI: $($hmi.Name)"
$null = $hmiSw.Screens.Count   # force HMI assemblies to load

# ---- Helpers -----------------------------------------------------------
function Get-HmiType([string]$fullName) {
    foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) {
        try { $t = $a.GetType($fullName, $false); if ($t) { return $t } } catch {}
    }
    throw "HMI type not found: $fullName"
}
function New-Item2([object]$comp, [string]$typeFullName, [string]$name) {
    $t = Get-HmiType $typeFullName
    $createGen = $comp.GetType().GetMethods() | Where-Object {
        $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1
    } | Select-Object -First 1
    if (-not $createGen) { throw "No Create<T>(string) on $($comp.GetType().Name)" }
    $m = $createGen.MakeGenericMethod($t)
    try {
        return $m.Invoke($comp, @($name))
    } catch {
        $inner = $_.Exception.InnerException
        $msg = if ($inner) { $inner.Message } else { $_.Exception.Message }
        throw "Create '$name' (type $($t.Name)) failed: $($msg.Split([char]10)[0])"
    }
}
function Set-MultilingualText([object]$item, [string]$propName, [string]$plain) {
    $prop = $item.GetType().GetProperty($propName)
    if (-not $prop) { return }
    $mlt = $prop.GetValue($item)
    if (-not $mlt) { return }
    $xml = "<body><p>$plain</p></body>"
    foreach ($mli in $mlt.Items) {
        try { $mli.SetAttribute('Text', $xml) } catch {}
    }
}
function Place-Item([object]$item, [int]$left, [int]$top, [int]$width, [int]$height) {
    $t = $item.GetType()
    if ($t.GetProperty('Left')) {
        $item.Left = $left
        $item.Top  = $top
        $item.Width  = [uint32]$width
        $item.Height = [uint32]$height
    } elseif ($t.GetProperty('CenterX')) {
        $item.CenterX = $left + [int]($width/2)
        $item.CenterY = $top  + [int]($height/2)
        $r = [int]([Math]::Min($width, $height) / 2)
        $item.Radius  = [uint32]$r
    } elseif ($t.GetProperty('Point1')) {
        # HmiLine uses two points
        $p1 = $item.Point1; $p2 = $item.Point2
        $p1.X = $left;          $p1.Y = $top + [int]($height/2)
        $p2.X = $left + $width; $p2.Y = $top + [int]($height/2)
    }
}
function Bind-Tag([object]$item, [string]$propertyName, [string]$tagName) {
    if (-not $tagName) { return @{ Ok=$false; Tag=$null; Reason='no tag' } }
    if ($script:tagSet -notcontains $tagName) {
        return @{ Ok=$false; Tag=$tagName; Reason='tag does not exist in HMI' }
    }
    try {
        $tagDynT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'
        $createGen = $item.Dynamizations.GetType().GetMethods() | Where-Object {
            $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition
        } | Select-Object -First 1
        $m = $createGen.MakeGenericMethod($tagDynT)
        $dyn = $m.Invoke($item.Dynamizations, @($propertyName))
        $dyn.SetAttribute('Tag', $tagName)
        return @{ Ok=$true; Tag=$tagName; Reason='bound' }
    } catch {
        return @{ Ok=$false; Tag=$tagName; Reason="bind failed: $($_.Exception.Message)" }
    }
}

# Pre-load existing HMI tag names for fast lookup
$script:tagSet = @{}
foreach ($t in $hmiSw.Tags) { $script:tagSet[$t.Name] = $true }
Write-Host "Existing HMI tags: $($script:tagSet.Count)"

# ---- Drop existing probe screen ---------------------------------------
$existing = $hmiSw.Screens.Find($ScreenName)
if ($existing) { try { $existing.Delete() } catch {} ; Write-Host "Deleted existing $ScreenName" }

# ---- Create screen -----------------------------------------------------
$screen = $hmiSw.Screens.Create($ScreenName)
$screen.Width  = [uint32]$Width
$screen.Height = [uint32]$Height
Write-Host "Created screen: $ScreenName ($Width x $Height)"

# Type fullnames (cached)
$T = @{
    Rect    = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiRectangle'
    Text    = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiText'
    Circle  = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiCircle'
    Line    = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiLine'
    IOField = 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField'
    Button  = 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton'
    Gauge   = 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiGauge'
}

# ---- Tracking ----------------------------------------------------------
$bindings = @()
$idCount  = 0
function Get-Id { $script:idCount++; return $script:idCount }

# ============================================================
# HEADER (y 0..80)
# ============================================================
$hdr = New-Item2 $screen.ScreenItems $T.Rect ('hdr_bg')
$hdr.Left = 0; $hdr.Top = 0; $hdr.Width = [uint32]$Width; $hdr.Height = [uint32]80

$hdrAccent = New-Item2 $screen.ScreenItems $T.Rect ('hdr_accent')
$hdrAccent.Left = 0; $hdrAccent.Top = 0; $hdrAccent.Width = [uint32]8; $hdrAccent.Height = [uint32]80

$hdrTitle = New-Item2 $screen.ScreenItems $T.Text ('hdr_title')
$hdrTitle.Left = 24; $hdrTitle.Top = 14; $hdrTitle.Width = [uint32]400; $hdrTitle.Height = [uint32]28
Set-MultilingualText $hdrTitle 'Text' 'KISTLER maXYmos NC'

$hdrSub = New-Item2 $screen.ScreenItems $T.Text ('hdr_subtitle')
$hdrSub.Left = 24; $hdrSub.Top = 44; $hdrSub.Width = [uint32]400; $hdrSub.Height = [uint32]22
Set-MultilingualText $hdrSub 'Text' 'Press Controller'

# Plant identifier (bound)
$plantBox = New-Item2 $screen.ScreenItems $T.Rect ('plant_box')
$plantBox.Left = 480; $plantBox.Top = 24; $plantBox.Width = [uint32]320; $plantBox.Height = [uint32]36
$plantTxt = New-Item2 $screen.ScreenItems $T.Text ('plant_text')
$plantTxt.Left = 488; $plantTxt.Top = 32; $plantTxt.Width = [uint32]300; $plantTxt.Height = [uint32]22
Set-MultilingualText $plantTxt 'Text' 'Plant Identifier'
$bindings += Bind-Tag $plantTxt 'Text' "$($TagPrefix)PlantId"

# tecUnit number
$tuLbl = New-Item2 $screen.ScreenItems $T.Text ('tu_lbl')
$tuLbl.Left = 1780; $tuLbl.Top = 18; $tuLbl.Width = [uint32]50; $tuLbl.Height = [uint32]18
Set-MultilingualText $tuLbl 'Text' 'Unit #'
$tuBox = New-Item2 $screen.ScreenItems $T.IOField ('tu_io')
$tuBox.Left = 1840; $tuBox.Top = 16; $tuBox.Width = [uint32]60; $tuBox.Height = [uint32]50
$bindings += Bind-Tag $tuBox 'ProcessValue' "$($TagPrefix)TecUnit"

# State colour badge (bound)
$scBadge = New-Item2 $screen.ScreenItems $T.Rect ('sc_badge')
$scBadge.Left = 1620; $scBadge.Top = 22; $scBadge.Width = [uint32]140; $scBadge.Height = [uint32]40
$scTxt = New-Item2 $screen.ScreenItems $T.Text ('sc_text')
$scTxt.Left = 1620; $scTxt.Top = 32; $scTxt.Width = [uint32]140; $scTxt.Height = [uint32]22
Set-MultilingualText $scTxt 'Text' 'STATE'
$bindings += Bind-Tag $scTxt 'Text' "$($TagPrefix)StateColour"

# ============================================================
# LEFT PANEL — STATUS (x 20..280, y 100..560)
# ============================================================
$statusPanel = New-Item2 $screen.ScreenItems $T.Rect ('status_panel')
$statusPanel.Left = 20; $statusPanel.Top = 100; $statusPanel.Width = [uint32]260; $statusPanel.Height = [uint32]460

$statusHdr = New-Item2 $screen.ScreenItems $T.Text ('status_hdr')
$statusHdr.Left = 20; $statusHdr.Top = 110; $statusHdr.Width = [uint32]260; $statusHdr.Height = [uint32]20
Set-MultilingualText $statusHdr 'Text' 'STATUS'

$statusBits = @(
    @{ Name='Ready';         Bit='rx.sts.x2';  Tag="$($TagPrefix)Ready" },
    @{ Name='OK Total';      Bit='rx.sts.x8';  Tag="$($TagPrefix)OkTotal" },
    @{ Name='NOK Total';     Bit='rx.sts.x9';  Tag="$($TagPrefix)NokTotal" },
    @{ Name='Drive Enabled'; Bit='rx.sts.x1';  Tag="$($TagPrefix)DriveEnabled" },
    @{ Name='At Home Pos';   Bit='rx.sts.x5';  Tag="$($TagPrefix)HomePos" },
    @{ Name='At Reference';  Bit='rx.sts.x4';  Tag="$($TagPrefix)RefPos" },
    @{ Name='Standstill';    Bit='rx.sts.x6';  Tag="$($TagPrefix)Standstill" },
    @{ Name='Sequence End';  Bit='rx.sts.x12'; Tag="$($TagPrefix)SeqEnd" },
    @{ Name='Wait Request';  Bit='rx.sts.x3';  Tag="$($TagPrefix)WaitRequest" },
    @{ Name='Kistler Auto';  Bit='rx.sts.x0';  Tag="$($TagPrefix)KistlerAuto" },
    @{ Name='SMES Active';   Bit='rx.sts.x13'; Tag="$($TagPrefix)SmesActive" },
    @{ Name='Safety OK';     Bit='state.x2';   Tag="$($TagPrefix)SafetyOK" }
)
$y = 140
$idx = 0
foreach ($s in $statusBits) {
    $idx++
    $led = New-Item2 $screen.ScreenItems $T.Circle ("led_st_$idx")
    Place-Item $led 36 $y 18 18
    $bindings += Bind-Tag $led 'BackColor' $s.Tag

    $lbl = New-Item2 $screen.ScreenItems $T.Text ("lbl_st_$idx")
    $lbl.Left = 64; $lbl.Top = $y; $lbl.Width = [uint32]160; $lbl.Height = [uint32]20
    Set-MultilingualText $lbl 'Text' $s.Name

    $bitLbl = New-Item2 $screen.ScreenItems $T.Text ("bit_st_$idx")
    $bitLbl.Left = 220; $bitLbl.Top = 0 + $y; $bitLbl.Width = [uint32]60; $bitLbl.Height = [uint32]18
    Set-MultilingualText $bitLbl 'Text' $s.Bit

    $y += 24
}

# ============================================================
# LEFT PANEL — ALARMS (x 20..280, y 580..980)
# ============================================================
$almPanel = New-Item2 $screen.ScreenItems $T.Rect ('alm_panel')
$almPanel.Left = 20; $almPanel.Top = 580; $almPanel.Width = [uint32]260; $almPanel.Height = [uint32]400

$almHdr = New-Item2 $screen.ScreenItems $T.Text ('alm_hdr')
$almHdr.Left = 20; $almHdr.Top = 590; $almHdr.Width = [uint32]260; $almHdr.Height = [uint32]20
Set-MultilingualText $almHdr 'Text' 'ALARMS'

$almBits = @(
    @{ Name='Hardware NOK';      Bit='alm.x1';  Tag="$($TagPrefix)AlmHardware" },
    @{ Name='TX Fault';          Bit='alm.x2';  Tag="$($TagPrefix)AlmTxFault" },
    @{ Name='Drive Enable NOK';  Bit='alm.x3';  Tag="$($TagPrefix)AlmDriveEnable" },
    @{ Name='Safety NOK';        Bit='alm.x13'; Tag="$($TagPrefix)AlmSafety" },
    @{ Name='Cycle Timeout';     Bit='alm.x6';  Tag="$($TagPrefix)AlmCycleTimeout" },
    @{ Name='Wait Cmd Missing';  Bit='alm.x9';  Tag="$($TagPrefix)AlmWaitMissing" },
    @{ Name='Remote Inactive';   Bit='alm.x16'; Tag="$($TagPrefix)AlmRemoteInactive" },
    @{ Name='Serial Mismatch';   Bit='alm.x17'; Tag="$($TagPrefix)AlmSerialMismatch" }
)
$y = 620
$idx = 0
foreach ($a in $almBits) {
    $idx++
    $led = New-Item2 $screen.ScreenItems $T.Circle ("led_alm_$idx")
    Place-Item $led 36 $y 18 18
    $bindings += Bind-Tag $led 'BackColor' $a.Tag

    $lbl = New-Item2 $screen.ScreenItems $T.Text ("lbl_alm_$idx")
    $lbl.Left = 64; $lbl.Top = $y; $lbl.Width = [uint32]160; $lbl.Height = [uint32]20
    Set-MultilingualText $lbl 'Text' $a.Name

    $bitLbl = New-Item2 $screen.ScreenItems $T.Text ("bit_alm_$idx")
    $bitLbl.Left = 220; $bitLbl.Top = $y; $bitLbl.Width = [uint32]60; $bitLbl.Height = [uint32]18
    Set-MultilingualText $bitLbl 'Text' $a.Bit

    $y += 32
}

# ============================================================
# CENTRE TOP — F-D AREA placeholder (x 300..1240, y 100..560)
# Real app: drop an HmiTrendControl here, bound to pvForceY/pvDispX
# ============================================================
$fdBg = New-Item2 $screen.ScreenItems $T.Rect ('fd_bg')
$fdBg.Left = 300; $fdBg.Top = 100; $fdBg.Width = [uint32]940; $fdBg.Height = [uint32]460

$fdHdr = New-Item2 $screen.ScreenItems $T.Text ('fd_hdr')
$fdHdr.Left = 320; $fdHdr.Top = 110; $fdHdr.Width = [uint32]400; $fdHdr.Height = [uint32]22
Set-MultilingualText $fdHdr 'Text' 'FORCE-DISPLACEMENT CURVE'

# Axis labels
$xAxis = New-Item2 $screen.ScreenItems $T.Text ('fd_xaxis')
$xAxis.Left = 700; $xAxis.Top = 530; $xAxis.Width = [uint32]300; $xAxis.Height = [uint32]20
Set-MultilingualText $xAxis 'Text' 'Displacement X [mm]'

$yAxis = New-Item2 $screen.ScreenItems $T.Text ('fd_yaxis')
$yAxis.Left = 312; $yAxis.Top = 320; $yAxis.Width = [uint32]100; $yAxis.Height = [uint32]20
Set-MultilingualText $yAxis 'Text' 'Force Y [N]'

# Bound axis bounds
$xMin = New-Item2 $screen.ScreenItems $T.IOField ('fd_xmin')
$xMin.Left = 340; $xMin.Top = 510; $xMin.Width = [uint32]100; $xMin.Height = [uint32]24
$bindings += Bind-Tag $xMin 'ProcessValue' "$($TagPrefix)Xmin"
$xMax = New-Item2 $screen.ScreenItems $T.IOField ('fd_xmax')
$xMax.Left = 1100; $xMax.Top = 510; $xMax.Width = [uint32]100; $xMax.Height = [uint32]24
$bindings += Bind-Tag $xMax 'ProcessValue' "$($TagPrefix)Xmax"
$yMin = New-Item2 $screen.ScreenItems $T.IOField ('fd_ymin')
$yMin.Left = 340; $yMin.Top = 480; $yMin.Width = [uint32]100; $yMin.Height = [uint32]24
$bindings += Bind-Tag $yMin 'ProcessValue' "$($TagPrefix)Ymin"
$yMax = New-Item2 $screen.ScreenItems $T.IOField ('fd_ymax')
$yMax.Left = 340; $yMax.Top = 140; $yMax.Width = [uint32]100; $yMax.Height = [uint32]24
$bindings += Bind-Tag $yMax 'ProcessValue' "$($TagPrefix)Ymax"

# Centre note
$fdNote = New-Item2 $screen.ScreenItems $T.Text ('fd_note')
$fdNote.Left = 600; $fdNote.Top = 320; $fdNote.Width = [uint32]400; $fdNote.Height = [uint32]20
Set-MultilingualText $fdNote 'Text' 'Trend control (X=Disp, Y=Force) place here'

# ============================================================
# CENTRE BOTTOM — PROCESS VALUE GAUGES (x 300..1240, y 580..720)
# ============================================================
$pvPanel = New-Item2 $screen.ScreenItems $T.Rect ('pv_panel')
$pvPanel.Left = 300; $pvPanel.Top = 580; $pvPanel.Width = [uint32]940; $pvPanel.Height = [uint32]140

$pvHdr = New-Item2 $screen.ScreenItems $T.Text ('pv_hdr')
$pvHdr.Left = 300; $pvHdr.Top = 590; $pvHdr.Width = [uint32]940; $pvHdr.Height = [uint32]22
Set-MultilingualText $pvHdr 'Text' 'PROCESS VALUES'

# Force
$pvForceLbl = New-Item2 $screen.ScreenItems $T.Text ('pv_force_lbl')
$pvForceLbl.Left = 320; $pvForceLbl.Top = 620; $pvForceLbl.Width = [uint32]280; $pvForceLbl.Height = [uint32]20
Set-MultilingualText $pvForceLbl 'Text' 'Force Y [N]'
$pvForce = New-Item2 $screen.ScreenItems $T.IOField ('pv_force')
$pvForce.Left = 320; $pvForce.Top = 644; $pvForce.Width = [uint32]280; $pvForce.Height = [uint32]60
$bindings += Bind-Tag $pvForce 'ProcessValue' "$($TagPrefix)Force"

# Disp
$pvDispLbl = New-Item2 $screen.ScreenItems $T.Text ('pv_disp_lbl')
$pvDispLbl.Left = 620; $pvDispLbl.Top = 620; $pvDispLbl.Width = [uint32]280; $pvDispLbl.Height = [uint32]20
Set-MultilingualText $pvDispLbl 'Text' 'Displacement X [mm]'
$pvDisp = New-Item2 $screen.ScreenItems $T.IOField ('pv_disp')
$pvDisp.Left = 620; $pvDisp.Top = 644; $pvDisp.Width = [uint32]280; $pvDisp.Height = [uint32]60
$bindings += Bind-Tag $pvDisp 'ProcessValue' "$($TagPrefix)Disp"

# Gradient
$pvGradLbl = New-Item2 $screen.ScreenItems $T.Text ('pv_grad_lbl')
$pvGradLbl.Left = 920; $pvGradLbl.Top = 620; $pvGradLbl.Width = [uint32]300; $pvGradLbl.Height = [uint32]20
Set-MultilingualText $pvGradLbl 'Text' 'Gradient [N/mm]'
$pvGrad = New-Item2 $screen.ScreenItems $T.IOField ('pv_grad')
$pvGrad.Left = 920; $pvGrad.Top = 644; $pvGrad.Width = [uint32]300; $pvGrad.Height = [uint32]60
$bindings += Bind-Tag $pvGrad 'ProcessValue' "$($TagPrefix)Gradient"

# ============================================================
# RIGHT PANEL — CONTROLS (x 1260..1900, y 100..560)
# ============================================================
$ctrlPanel = New-Item2 $screen.ScreenItems $T.Rect ('ctrl_panel')
$ctrlPanel.Left = 1260; $ctrlPanel.Top = 100; $ctrlPanel.Width = [uint32]640; $ctrlPanel.Height = [uint32]460

$ctrlHdr = New-Item2 $screen.ScreenItems $T.Text ('ctrl_hdr')
$ctrlHdr.Left = 1260; $ctrlHdr.Top = 110; $ctrlHdr.Width = [uint32]640; $ctrlHdr.Height = [uint32]22
Set-MultilingualText $ctrlHdr 'Text' 'CONTROLS  (writes to interfaceHmi.move bits)'

$buttons = @(
    @{ Name='RUN';        Bit='cmdMove.x1';   Width=200; Height=60; Col=0; Row=0 },
    @{ Name='ACK ADMIN';  Bit='cmdMove.x9';   Width=200; Height=60; Col=2; Row=0 },
    @{ Name='HOME';       Bit='cmdMove.x2';   Width=140; Height=50; Col=0; Row=1 },
    @{ Name='REF';        Bit='cmdMove.x8';   Width=140; Height=50; Col=1; Row=1 },
    @{ Name='REMOTE';     Bit='cmdMove.x0';   Width=140; Height=50; Col=2; Row=1 },
    @{ Name='CONT WAIT';  Bit='cmdMove.x10';  Width=140; Height=50; Col=0; Row=2 },
    @{ Name='JOG +';      Id='JogPlus';   Bit='cmdMove.x14';  Width=140; Height=50; Col=1; Row=2 },
    @{ Name='JOG -';      Id='JogMinus';  Bit='cmdMove.x15';  Width=140; Height=50; Col=2; Row=2 }
)

# Layout: column starts at 1280, gap 10, row gap 10
$colX = @(1280, 1430, 1580)
$rowY = @(140, 220, 290)
foreach ($b in $buttons) {
    $idName = if ($b.Id) { $b.Id } else { ($b.Name -replace '\W','') }
    $btn = New-Item2 $screen.ScreenItems $T.Button ("btn_$idName")
    $btn.Left   = $colX[$b.Col]
    $btn.Top    = $rowY[$b.Row]
    $btn.Width  = [uint32]$b.Width
    $btn.Height = [uint32]$b.Height
    Set-MultilingualText $btn 'Text' $b.Name
}

# Setpoints divider
$spLine = New-Item2 $screen.ScreenItems $T.Line ('sp_div')
Place-Item $spLine 1280 360 600 2

$spHdr = New-Item2 $screen.ScreenItems $T.Text ('sp_hdr')
$spHdr.Left = 1280; $spHdr.Top = 370; $spHdr.Width = [uint32]600; $spHdr.Height = [uint32]20
Set-MultilingualText $spHdr 'Text' 'SETPOINTS  (HMI to fieldbus)'

# Jog speed
$jsLbl = New-Item2 $screen.ScreenItems $T.Text ('js_lbl')
$jsLbl.Left = 1280; $jsLbl.Top = 400; $jsLbl.Width = [uint32]200; $jsLbl.Height = [uint32]20
Set-MultilingualText $jsLbl 'Text' 'Jog Speed [mm/s]'
$js = New-Item2 $screen.ScreenItems $T.IOField ('js_io')
$js.Left = 1280; $js.Top = 424; $js.Width = [uint32]200; $js.Height = [uint32]40
$bindings += Bind-Tag $js 'ProcessValue' "$($TagPrefix)JogSpeedSet"

# Max force
$mfLbl = New-Item2 $screen.ScreenItems $T.Text ('mf_lbl')
$mfLbl.Left = 1500; $mfLbl.Top = 400; $mfLbl.Width = [uint32]200; $mfLbl.Height = [uint32]20
Set-MultilingualText $mfLbl 'Text' 'Max Force [N]'
$mf = New-Item2 $screen.ScreenItems $T.IOField ('mf_io')
$mf.Left = 1500; $mf.Top = 424; $mf.Width = [uint32]200; $mf.Height = [uint32]40
$bindings += Bind-Tag $mf 'ProcessValue' "$($TagPrefix)MaxForceSet"

# ============================================================
# RIGHT BOTTOM — PROGRAM SELECTION (x 1260..1900, y 580..720)
# ============================================================
$progPanel = New-Item2 $screen.ScreenItems $T.Rect ('prog_panel')
$progPanel.Left = 1260; $progPanel.Top = 580; $progPanel.Width = [uint32]640; $progPanel.Height = [uint32]140

$progHdr = New-Item2 $screen.ScreenItems $T.Text ('prog_hdr')
$progHdr.Left = 1260; $progHdr.Top = 590; $progHdr.Width = [uint32]640; $progHdr.Height = [uint32]22
Set-MultilingualText $progHdr 'Text' 'PROGRAM SELECTION'

$mpLbl = New-Item2 $screen.ScreenItems $T.Text ('mp_lbl')
$mpLbl.Left = 1280; $mpLbl.Top = 620; $mpLbl.Width = [uint32]180; $mpLbl.Height = [uint32]20
Set-MultilingualText $mpLbl 'Text' 'MP (0..127)'
$mp = New-Item2 $screen.ScreenItems $T.IOField ('mp_io')
$mp.Left = 1280; $mp.Top = 644; $mp.Width = [uint32]180; $mp.Height = [uint32]50
$bindings += Bind-Tag $mp 'ProcessValue' "$($TagPrefix)MpNumSet"

$seqLbl = New-Item2 $screen.ScreenItems $T.Text ('seq_lbl')
$seqLbl.Left = 1480; $seqLbl.Top = 620; $seqLbl.Width = [uint32]180; $seqLbl.Height = [uint32]20
Set-MultilingualText $seqLbl 'Text' 'Sequence (0..3)'
$seq = New-Item2 $screen.ScreenItems $T.IOField ('seq_io')
$seq.Left = 1480; $seq.Top = 644; $seq.Width = [uint32]180; $seq.Height = [uint32]50
$bindings += Bind-Tag $seq 'ProcessValue' "$($TagPrefix)SeqSet"

$pgLbl = New-Item2 $screen.ScreenItems $T.Text ('pg_lbl')
$pgLbl.Left = 1680; $pgLbl.Top = 620; $pgLbl.Width = [uint32]180; $pgLbl.Height = [uint32]20
Set-MultilingualText $pgLbl 'Text' 'Page (0..7)'
$pg = New-Item2 $screen.ScreenItems $T.IOField ('pg_io')
$pg.Left = 1680; $pg.Top = 644; $pg.Width = [uint32]180; $pg.Height = [uint32]50
$bindings += Bind-Tag $pg 'ProcessValue' "$($TagPrefix)PageSet"

# ============================================================
# BOTTOM — SEQUENCE / ECHO STATUS BAR (y 740..1060)
# ============================================================
$ftPanel = New-Item2 $screen.ScreenItems $T.Rect ('ft_panel')
$ftPanel.Left = 20; $ftPanel.Top = 740; $ftPanel.Width = [uint32]1880; $ftPanel.Height = [uint32]320

$ftHdr = New-Item2 $screen.ScreenItems $T.Text ('ft_hdr')
$ftHdr.Left = 20; $ftHdr.Top = 750; $ftHdr.Width = [uint32]1880; $ftHdr.Height = [uint32]22
Set-MultilingualText $ftHdr 'Text' 'SEQUENCE / PROGRAM ECHO'

# Active MP
$activeMpLbl = New-Item2 $screen.ScreenItems $T.Text ('a_mp_lbl')
$activeMpLbl.Left = 40; $activeMpLbl.Top = 790; $activeMpLbl.Width = [uint32]120; $activeMpLbl.Height = [uint32]20
Set-MultilingualText $activeMpLbl 'Text' 'Active MP'
$activeMp = New-Item2 $screen.ScreenItems $T.IOField ('a_mp_io')
$activeMp.Left = 40; $activeMp.Top = 814; $activeMp.Width = [uint32]120; $activeMp.Height = [uint32]50
$bindings += Bind-Tag $activeMp 'ProcessValue' "$($TagPrefix)RxMpNum"

# Active Seq
$activeSeqLbl = New-Item2 $screen.ScreenItems $T.Text ('a_seq_lbl')
$activeSeqLbl.Left = 180; $activeSeqLbl.Top = 790; $activeSeqLbl.Width = [uint32]120; $activeSeqLbl.Height = [uint32]20
Set-MultilingualText $activeSeqLbl 'Text' 'Active Seq'
$activeSeq = New-Item2 $screen.ScreenItems $T.IOField ('a_seq_io')
$activeSeq.Left = 180; $activeSeq.Top = 814; $activeSeq.Width = [uint32]120; $activeSeq.Height = [uint32]50
$bindings += Bind-Tag $activeSeq 'ProcessValue' "$($TagPrefix)SendSeq"

# Active Page
$activePgLbl = New-Item2 $screen.ScreenItems $T.Text ('a_pg_lbl')
$activePgLbl.Left = 320; $activePgLbl.Top = 790; $activePgLbl.Width = [uint32]120; $activePgLbl.Height = [uint32]20
Set-MultilingualText $activePgLbl 'Text' 'Page'
$activePg = New-Item2 $screen.ScreenItems $T.IOField ('a_pg_io')
$activePg.Left = 320; $activePg.Top = 814; $activePg.Width = [uint32]120; $activePg.Height = [uint32]50
$bindings += Bind-Tag $activePg 'ProcessValue' "$($TagPrefix)SendPage"

# Sequence Label (currentLabel 0..31)
$labelLbl = New-Item2 $screen.ScreenItems $T.Text ('lbl_lbl')
$labelLbl.Left = 460; $labelLbl.Top = 790; $labelLbl.Width = [uint32]160; $labelLbl.Height = [uint32]20
Set-MultilingualText $labelLbl 'Text' 'Sequence Label'
$labelIo = New-Item2 $screen.ScreenItems $T.IOField ('lbl_io')
$labelIo.Left = 460; $labelIo.Top = 814; $labelIo.Width = [uint32]160; $labelIo.Height = [uint32]50
$bindings += Bind-Tag $labelIo 'ProcessValue' "$($TagPrefix)CurrentLabel"

# SequenceEnd LED
$endLed = New-Item2 $screen.ScreenItems $T.Circle ('end_led')
Place-Item $endLed 660 814 28 28
$endLbl = New-Item2 $screen.ScreenItems $T.Text ('end_lbl')
$endLbl.Left = 698; $endLbl.Top = 820; $endLbl.Width = [uint32]100; $endLbl.Height = [uint32]20
Set-MultilingualText $endLbl 'Text' 'Seq End'
$bindings += Bind-Tag $endLed 'BackColor' "$($TagPrefix)SequenceEnd"

# Op mode area
$omLbl = New-Item2 $screen.ScreenItems $T.Text ('om_lbl')
$omLbl.Left = 820; $omLbl.Top = 790; $omLbl.Width = [uint32]160; $omLbl.Height = [uint32]20
Set-MultilingualText $omLbl 'Text' 'Op Mode Area'
$omIo = New-Item2 $screen.ScreenItems $T.IOField ('om_io')
$omIo.Left = 820; $omIo.Top = 814; $omIo.Width = [uint32]160; $omIo.Height = [uint32]50
$bindings += Bind-Tag $omIo 'ProcessValue' "$($TagPrefix)Opmodearea"

# HMI control no
$cnLbl = New-Item2 $screen.ScreenItems $T.Text ('cn_lbl')
$cnLbl.Left = 1000; $cnLbl.Top = 790; $cnLbl.Width = [uint32]160; $cnLbl.Height = [uint32]20
Set-MultilingualText $cnLbl 'Text' 'HMI Control #'
$cnIo = New-Item2 $screen.ScreenItems $T.IOField ('cn_io')
$cnIo.Left = 1000; $cnIo.Top = 814; $cnIo.Width = [uint32]160; $cnIo.Height = [uint32]50
$bindings += Bind-Tag $cnIo 'ProcessValue' "$($TagPrefix)HmiControlNo"

# Footer text
$footer = New-Item2 $screen.ScreenItems $T.Text ('footer')
$footer.Left = 20; $footer.Top = 1030; $footer.Width = [uint32]1880; $footer.Height = [uint32]22
Set-MultilingualText $footer 'Text' "Kistler maXYmos NC | Built via Openness | TagPrefix: $TagPrefix"

# ============================================================
# Save
# ============================================================
Write-Host "`nSaving..."
try { $session.Save() ; Write-Host "Saved." } catch { Write-Warning "Save failed: $_" }

# ============================================================
# Report
# ============================================================
$bound   = $bindings | Where-Object { $_.Ok }
$unbound = $bindings | Where-Object { -not $_.Ok }

Write-Host ""
Write-Host "================================================="
Write-Host "  BUILD SUMMARY: $ScreenName"
Write-Host "================================================="
Write-Host "  Items created: $($screen.ScreenItems.Count)"
Write-Host "  Bindings:      $($bindings.Count) total / $($bound.Count) bound / $($unbound.Count) skipped"
Write-Host ""

if ($unbound.Count -gt 0) {
    Write-Host "TAGS NEEDED (create in HMI tag table to wire these up):" -ForegroundColor Yellow
    $unbound | ForEach-Object { $_.Tag } | Sort-Object -Unique | ForEach-Object {
        Write-Host "  - $_"
    }
    Write-Host ""
    Write-Host "Tag-to-FB-field mapping (point HMI tags at these PLC paths):" -ForegroundColor Yellow
    Write-Host '  TagPrefix Ready             -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X2'
    Write-Host '  TagPrefix OkTotal           -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X8'
    Write-Host '  TagPrefix NokTotal          -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X9'
    Write-Host '  TagPrefix DriveEnabled      -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X1'
    Write-Host '  TagPrefix HomePos           -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X5'
    Write-Host '  TagPrefix RefPos            -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X4'
    Write-Host '  TagPrefix Standstill        -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X6'
    Write-Host '  TagPrefix SeqEnd            -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X12'
    Write-Host '  TagPrefix WaitRequest       -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X3'
    Write-Host '  TagPrefix KistlerAuto       -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X0'
    Write-Host '  TagPrefix SmesActive        -> "DB_Kistler1".interfaceHmi[1].receive.status   bit X13'
    Write-Host '  TagPrefix SafetyOK          -> "DB_Kistler1".interfaceHmi[1].state            bit X2'
    Write-Host '  TagPrefix AlmHardware       -> "DB_Kistler1".interfaceHmi[1].alarm            bit X1'
    Write-Host '  TagPrefix AlmTxFault        -> "DB_Kistler1".interfaceHmi[1].alarm            bit X2'
    Write-Host '  TagPrefix AlmDriveEnable    -> "DB_Kistler1".interfaceHmi[1].alarm            bit X3'
    Write-Host '  TagPrefix AlmSafety         -> "DB_Kistler1".interfaceHmi[1].alarm            bit X13'
    Write-Host '  TagPrefix AlmCycleTimeout   -> "DB_Kistler1".interfaceHmi[1].alarm            bit X6'
    Write-Host '  TagPrefix AlmWaitMissing    -> "DB_Kistler1".interfaceHmi[1].alarm            bit X9'
    Write-Host '  TagPrefix AlmRemoteInactive -> "DB_Kistler1".interfaceHmi[1].alarm            bit X16'
    Write-Host '  TagPrefix AlmSerialMismatch -> "DB_Kistler1".interfaceHmi[1].alarm            bit X17'
    Write-Host '  TagPrefix Force             -> "DB_Kistler1".interfaceHmi[1].receive."PVcurrentValueY"'
    Write-Host '  TagPrefix Disp              -> "DB_Kistler1".interfaceHmi[1].receive."PVcurrentValueX"'
    Write-Host '  TagPrefix Gradient          -> "DB_Kistler1".interfaceHmi[1].receive."PV_EO3_Gradient"'
    Write-Host '  TagPrefix Xmin/Xmax/Ymin/Ymax -> receive."PVcurrentXmin-X" etc.'
    Write-Host '  TagPrefix PlantId           -> "DB_Kistler1".interfaceHmi[1].plantidentifier'
    Write-Host '  TagPrefix TecUnit           -> "DB_Kistler1".interfaceHmi[1].tecUnitNumber'
    Write-Host '  TagPrefix StateColour       -> "DB_Kistler1".interfaceHmi[1].stateColour'
    Write-Host '  TagPrefix RxMpNum           -> "DB_Kistler1".interfaceHmi[1].receive.mpNum'
    Write-Host '  TagPrefix CurrentLabel      -> "DB_Kistler1".interfaceHmi[1].currentLabel'
    Write-Host '  TagPrefix SequenceEnd       -> "DB_Kistler1".interfaceHmi[1].sequenceEnd'
    Write-Host '  TagPrefix Opmodearea        -> "DB_Kistler1".interfaceHmi[1].opmodearea'
    Write-Host '  TagPrefix HmiControlNo      -> "DB_Kistler1".interfaceHmi[1].hmiControlNo'
    Write-Host '  TagPrefix MpNumSet          -> "DB_Kistler1".interfaceHmi[1].manualSelectMpNum'
    Write-Host '  TagPrefix SeqSet            -> "DB_Kistler1".interfaceHmi[1].selectSequenceSet'
    Write-Host '  TagPrefix PageSet           -> "DB_Kistler1".interfaceHmi[1].selectPageSet'
    Write-Host '  TagPrefix JogSpeedSet       -> "DB_Kistler1".interfaceHmi[1].serverJogSpeedSet'
    Write-Host '  TagPrefix MaxForceSet       -> "DB_Kistler1".interfaceHmi[1].serverJogMaxForceSet'
    Write-Host '  TagPrefix SendSeq           -> "DB_Kistler1".interfaceHmi[1].send.selectSeqeunce  (typo intentional)'
    Write-Host '  TagPrefix SendPage          -> "DB_Kistler1".interfaceHmi[1].send.selectPage'
}

Write-Host ""
Write-Host "Open '$ScreenName' on HMI '$($hmi.Name)' in TIA to view it."
