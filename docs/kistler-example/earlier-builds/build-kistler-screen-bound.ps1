# build-kistler-screen-bound.ps1
# Builds Kistler screen and binds every element to paths inside the
# structured HMI tag of type LDrive_typeKistlerHmi.
#
# Default RootTag: MVterminalPressKistler
#   (DataType=LDrive_typeKistlerHmi, points at the FB's interfaceHmi[0])
#
# Bit-access uses ".%X<n>" notation. If TIA rejects that on the dynamization,
# we fall back to binding the whole DWord and the user can add expression
# converters in the editor.

param(
    [string]$HmiName    = '',
    [string]$ScreenName = '_Kistler_Press_01',
    [string]$RootTag    = 'MVterminalPressKistler',
    [int]   $Width      = 1920,
    [int]   $Height     = 1080
)

$ErrorActionPreference = 'Stop'

$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null
$tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal  = $tia.Attach()
$session = $portal.LocalSessions[0]
$project = $session.Project
Write-Host "Project: $($project.Name)"

$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
function Get-Sw($di) { $m = $di.GetType().GetMethod('GetService').MakeGenericMethod($swT); return $m.Invoke($di, $null) }
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
if (-not $hmi) { throw "No HmiUnified found" }
$hmiSw = $hmi.Sw
$null = $hmiSw.Screens.Count
Write-Host "HMI: $($hmi.Name)"

# Verify root tag exists
$rootTagObj = $hmiSw.Tags.Find($RootTag)
if (-not $rootTagObj) {
    throw "Root tag '$RootTag' not found in HMI '$($hmi.Name)'. Run probe-station1-tags.ps1 to list available."
}
Write-Host "Root tag: $RootTag (DataType=$($rootTagObj.DataType))"

# ---- Helpers ----------------------------------------------------------
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
    $m = $createGen.MakeGenericMethod($t)
    try { return $m.Invoke($comp, @($name)) }
    catch {
        $inner = $_.Exception.InnerException
        $msg = if ($inner) { $inner.Message } else { $_.Exception.Message }
        throw "Create '$name' (type $($t.Name)) failed: $($msg.Split([char]10)[0])"
    }
}
function Place-Item([object]$item, [int]$left, [int]$top, [int]$width, [int]$height) {
    $t = $item.GetType()
    if ($t.GetProperty('Left')) {
        $item.Left = $left; $item.Top = $top
        $item.Width = [uint32]$width; $item.Height = [uint32]$height
    } elseif ($t.GetProperty('CenterX')) {
        $item.CenterX = $left + [int]($width/2)
        $item.CenterY = $top  + [int]($height/2)
        $r = [int]([Math]::Min($width, $height) / 2)
        $item.Radius = [uint32]$r
    } elseif ($t.GetProperty('Point1')) {
        $p1 = $item.Point1; $p2 = $item.Point2
        $p1.X = $left;          $p1.Y = $top + [int]($height/2)
        $p2.X = $left + $width; $p2.Y = $top + [int]($height/2)
    }
}
function Set-MultilingualText([object]$item, [string]$propName, [string]$plain) {
    $prop = $item.GetType().GetProperty($propName)
    if (-not $prop) { return }
    $mlt = $prop.GetValue($item)
    if (-not $mlt) { return }
    $xml = "<body><p>$plain</p></body>"
    foreach ($mli in $mlt.Items) { try { $mli.SetAttribute('Text', $xml) } catch {} }
}

$tagDynT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'

function Bind-Path([object]$item, [string]$propertyName, [string]$path) {
    if (-not $path) { return @{ Ok=$false; Path=$null; Reason='no path' } }
    $fullTag = "$RootTag.$path"
    try {
        $createGen = $item.Dynamizations.GetType().GetMethods() | Where-Object {
            $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition
        } | Select-Object -First 1
        $m = $createGen.MakeGenericMethod($tagDynT)
        $dyn = $m.Invoke($item.Dynamizations, @($propertyName))
        $dyn.SetAttribute('Tag', $fullTag)
        return @{ Ok=$true; Path=$fullTag; Reason='bound' }
    } catch {
        $inner = $_.Exception.InnerException
        $msg = if ($inner) { $inner.Message } else { $_.Exception.Message }
        return @{ Ok=$false; Path=$fullTag; Reason="bind failed: $($msg.Split([char]10)[0])" }
    }
}

# ---- Drop and create screen -------------------------------------------
$existing = $hmiSw.Screens.Find($ScreenName)
if ($existing) { try { $existing.Delete() } catch {} ; Write-Host "Deleted existing $ScreenName" }
$screen = $hmiSw.Screens.Create($ScreenName)
$screen.Width = [uint32]$Width; $screen.Height = [uint32]$Height
Write-Host "Created screen: $ScreenName ($Width x $Height)"

$T = @{
    Rect    = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiRectangle'
    Text    = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiText'
    Circle  = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiCircle'
    Line    = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiLine'
    IOField = 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField'
    Button  = 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton'
}
$bindings = @()

# ============== HEADER ==============
$hdr = New-Item2 $screen.ScreenItems $T.Rect 'hdr_bg'
Place-Item $hdr 0 0 $Width 80
$hdrAccent = New-Item2 $screen.ScreenItems $T.Rect 'hdr_accent'
Place-Item $hdrAccent 0 0 8 80

$hdrTitle = New-Item2 $screen.ScreenItems $T.Text 'hdr_title'
Place-Item $hdrTitle 24 14 400 28
Set-MultilingualText $hdrTitle 'Text' 'KISTLER maXYmos NC'

$hdrSub = New-Item2 $screen.ScreenItems $T.Text 'hdr_subtitle'
Place-Item $hdrSub 24 44 400 22
Set-MultilingualText $hdrSub 'Text' 'Press Controller'

$plantBox = New-Item2 $screen.ScreenItems $T.Rect 'plant_box'
Place-Item $plantBox 480 24 320 36
$plantIo = New-Item2 $screen.ScreenItems $T.IOField 'plant_io'
Place-Item $plantIo 488 28 300 30
$bindings += Bind-Path $plantIo 'ProcessValue' 'plantidentifier'

$tuLbl = New-Item2 $screen.ScreenItems $T.Text 'tu_lbl'
Place-Item $tuLbl 1780 18 50 18
Set-MultilingualText $tuLbl 'Text' 'Unit #'
$tuIo = New-Item2 $screen.ScreenItems $T.IOField 'tu_io'
Place-Item $tuIo 1840 16 60 50
$bindings += Bind-Path $tuIo 'ProcessValue' 'tecUnitNumber'

$scBadge = New-Item2 $screen.ScreenItems $T.Rect 'sc_badge'
Place-Item $scBadge 1620 22 140 40
$bindings += Bind-Path $scBadge 'BackColor' 'stateColour'

# ============== STATUS LEDS ==============
$statusPanel = New-Item2 $screen.ScreenItems $T.Rect 'status_panel'
Place-Item $statusPanel 20 100 260 460
$statusHdr = New-Item2 $screen.ScreenItems $T.Text 'status_hdr'
Place-Item $statusHdr 20 110 260 20
Set-MultilingualText $statusHdr 'Text' 'STATUS'

# Bind to .%X<n> bit syntax. If TIA rejects, the binding is logged as failed
# and you can wire individual Bool tags later.
$statusBits = @(
    @{ Name='Ready';         Path='receive.status.%X2';  Bit='rx.sts.x2' },
    @{ Name='OK Total';      Path='receive.status.%X8';  Bit='rx.sts.x8' },
    @{ Name='NOK Total';     Path='receive.status.%X9';  Bit='rx.sts.x9' },
    @{ Name='Drive Enabled'; Path='receive.status.%X1';  Bit='rx.sts.x1' },
    @{ Name='At Home Pos';   Path='receive.status.%X5';  Bit='rx.sts.x5' },
    @{ Name='At Reference';  Path='receive.status.%X4';  Bit='rx.sts.x4' },
    @{ Name='Standstill';    Path='receive.status.%X6';  Bit='rx.sts.x6' },
    @{ Name='Sequence End';  Path='receive.status.%X12'; Bit='rx.sts.x12' },
    @{ Name='Wait Request';  Path='receive.status.%X3';  Bit='rx.sts.x3' },
    @{ Name='Kistler Auto';  Path='receive.status.%X0';  Bit='rx.sts.x0' },
    @{ Name='SMES Active';   Path='receive.status.%X13'; Bit='rx.sts.x13' },
    @{ Name='Safety OK';     Path='state.%X2';           Bit='state.x2' }
)
$y = 140
$idx = 0
foreach ($s in $statusBits) {
    $idx++
    $led = New-Item2 $screen.ScreenItems $T.Circle ("led_st_$idx")
    Place-Item $led 36 $y 18 18
    $bindings += Bind-Path $led 'Visible' $s.Path

    $lbl = New-Item2 $screen.ScreenItems $T.Text ("lbl_st_$idx")
    Place-Item $lbl 64 $y 160 20
    Set-MultilingualText $lbl 'Text' $s.Name

    $bitLbl = New-Item2 $screen.ScreenItems $T.Text ("bit_st_$idx")
    Place-Item $bitLbl 220 $y 60 18
    Set-MultilingualText $bitLbl 'Text' $s.Bit
    $y += 24
}

# ============== ALARM LEDS ==============
$almPanel = New-Item2 $screen.ScreenItems $T.Rect 'alm_panel'
Place-Item $almPanel 20 580 260 400
$almHdr = New-Item2 $screen.ScreenItems $T.Text 'alm_hdr'
Place-Item $almHdr 20 590 260 20
Set-MultilingualText $almHdr 'Text' 'ALARMS'

$almBits = @(
    @{ Name='Hardware NOK';      Path='alarm.%X1';  Bit='alm.x1' },
    @{ Name='TX Fault';          Path='alarm.%X2';  Bit='alm.x2' },
    @{ Name='Drive Enable NOK';  Path='alarm.%X3';  Bit='alm.x3' },
    @{ Name='Safety NOK';        Path='alarm.%X13'; Bit='alm.x13' },
    @{ Name='Cycle Timeout';     Path='alarm.%X6';  Bit='alm.x6' },
    @{ Name='Wait Cmd Missing';  Path='alarm.%X9';  Bit='alm.x9' },
    @{ Name='Remote Inactive';   Path='alarm.%X16'; Bit='alm.x16' },
    @{ Name='Serial Mismatch';   Path='alarm.%X17'; Bit='alm.x17' }
)
$y = 620
$idx = 0
foreach ($a in $almBits) {
    $idx++
    $led = New-Item2 $screen.ScreenItems $T.Circle ("led_alm_$idx")
    Place-Item $led 36 $y 18 18
    $bindings += Bind-Path $led 'Visible' $a.Path

    $lbl = New-Item2 $screen.ScreenItems $T.Text ("lbl_alm_$idx")
    Place-Item $lbl 64 $y 160 20
    Set-MultilingualText $lbl 'Text' $a.Name

    $bitLbl = New-Item2 $screen.ScreenItems $T.Text ("bit_alm_$idx")
    Place-Item $bitLbl 220 $y 60 18
    Set-MultilingualText $bitLbl 'Text' $a.Bit
    $y += 32
}

# ============== F-D AREA ==============
$fdBg = New-Item2 $screen.ScreenItems $T.Rect 'fd_bg'
Place-Item $fdBg 300 100 940 460
$fdHdr = New-Item2 $screen.ScreenItems $T.Text 'fd_hdr'
Place-Item $fdHdr 320 110 400 22
Set-MultilingualText $fdHdr 'Text' 'FORCE-DISPLACEMENT CURVE'

$xAxis = New-Item2 $screen.ScreenItems $T.Text 'fd_xaxis'
Place-Item $xAxis 700 530 300 20
Set-MultilingualText $xAxis 'Text' 'Displacement X [mm]'
$yAxis = New-Item2 $screen.ScreenItems $T.Text 'fd_yaxis'
Place-Item $yAxis 312 320 100 20
Set-MultilingualText $yAxis 'Text' 'Force Y [N]'

$xMin = New-Item2 $screen.ScreenItems $T.IOField 'fd_xmin'
Place-Item $xMin 340 510 100 24
$bindings += Bind-Path $xMin 'ProcessValue' 'receive.PVcurrentXmin-X'
$xMax = New-Item2 $screen.ScreenItems $T.IOField 'fd_xmax'
Place-Item $xMax 1100 510 100 24
$bindings += Bind-Path $xMax 'ProcessValue' 'receive.PVcurrentXmax-X'
$yMin = New-Item2 $screen.ScreenItems $T.IOField 'fd_ymin'
Place-Item $yMin 340 480 100 24
$bindings += Bind-Path $yMin 'ProcessValue' 'receive.PVcurrentYmin-Y'
$yMax = New-Item2 $screen.ScreenItems $T.IOField 'fd_ymax'
Place-Item $yMax 340 140 100 24
$bindings += Bind-Path $yMax 'ProcessValue' 'receive.PVcurrentYmax-Y'

$fdNote = New-Item2 $screen.ScreenItems $T.Text 'fd_note'
Place-Item $fdNote 600 320 400 20
Set-MultilingualText $fdNote 'Text' 'Trend control (X=Disp, Y=Force) place here'

# ============== PROCESS VALUES ==============
$pvPanel = New-Item2 $screen.ScreenItems $T.Rect 'pv_panel'
Place-Item $pvPanel 300 580 940 140
$pvHdr = New-Item2 $screen.ScreenItems $T.Text 'pv_hdr'
Place-Item $pvHdr 300 590 940 22
Set-MultilingualText $pvHdr 'Text' 'PROCESS VALUES'

$pvForceLbl = New-Item2 $screen.ScreenItems $T.Text 'pv_force_lbl'
Place-Item $pvForceLbl 320 620 280 20
Set-MultilingualText $pvForceLbl 'Text' 'Force Y [N]'
$pvForce = New-Item2 $screen.ScreenItems $T.IOField 'pv_force'
Place-Item $pvForce 320 644 280 60
$bindings += Bind-Path $pvForce 'ProcessValue' 'receive.PVcurrentValueY'

$pvDispLbl = New-Item2 $screen.ScreenItems $T.Text 'pv_disp_lbl'
Place-Item $pvDispLbl 620 620 280 20
Set-MultilingualText $pvDispLbl 'Text' 'Displacement X [mm]'
$pvDisp = New-Item2 $screen.ScreenItems $T.IOField 'pv_disp'
Place-Item $pvDisp 620 644 280 60
$bindings += Bind-Path $pvDisp 'ProcessValue' 'receive.PVcurrentValueX'

$pvGradLbl = New-Item2 $screen.ScreenItems $T.Text 'pv_grad_lbl'
Place-Item $pvGradLbl 920 620 300 20
Set-MultilingualText $pvGradLbl 'Text' 'Gradient [N/mm]'
$pvGrad = New-Item2 $screen.ScreenItems $T.IOField 'pv_grad'
Place-Item $pvGrad 920 644 300 60
$bindings += Bind-Path $pvGrad 'ProcessValue' 'receive.PV_EO3_Gradient'

# ============== CONTROLS ==============
$ctrlPanel = New-Item2 $screen.ScreenItems $T.Rect 'ctrl_panel'
Place-Item $ctrlPanel 1260 100 640 460
$ctrlHdr = New-Item2 $screen.ScreenItems $T.Text 'ctrl_hdr'
Place-Item $ctrlHdr 1260 110 640 22
Set-MultilingualText $ctrlHdr 'Text' 'CONTROLS  (writes to interfaceHmi.move bits)'

# Buttons: visible on screen; click-to-write requires script handlers
# beyond Openness scope. Visual feedback is bound to send.control echo bits.
$buttons = @(
    @{ Name='RUN';       Id='Run';       FbBit='send.control.%X2'; Width=200; Height=60; Col=0; Row=0 },
    @{ Name='ACK ADMIN'; Id='AckAdmin';  FbBit='send.control.%X9'; Width=200; Height=60; Col=2; Row=0 },
    @{ Name='HOME';      Id='Home';      FbBit='send.control.%X3'; Width=140; Height=50; Col=0; Row=1 },
    @{ Name='REF';       Id='Ref';       FbBit='send.control.%X4'; Width=140; Height=50; Col=1; Row=1 },
    @{ Name='REMOTE';    Id='Remote';    FbBit='send.control.%X0'; Width=140; Height=50; Col=2; Row=1 },
    @{ Name='CONT WAIT'; Id='ContWait';  FbBit='send.control.%X7'; Width=140; Height=50; Col=0; Row=2 },
    @{ Name='JOG +';     Id='JogPlus';   FbBit='send.control.%X5'; Width=140; Height=50; Col=1; Row=2 },
    @{ Name='JOG -';     Id='JogMinus';  FbBit='send.control.%X6'; Width=140; Height=50; Col=2; Row=2 }
)
$colX = @(1280, 1430, 1580)
$rowY = @(140, 220, 290)
foreach ($b in $buttons) {
    $btn = New-Item2 $screen.ScreenItems $T.Button ("btn_$($b.Id)")
    Place-Item $btn $colX[$b.Col] $rowY[$b.Row] $b.Width $b.Height
    Set-MultilingualText $btn 'Text' $b.Name
    # Bind BackColor to send.control echo so user can SEE which command is active
    $bindings += Bind-Path $btn 'BackColor' $b.FbBit
}

$spLine = New-Item2 $screen.ScreenItems $T.Line 'sp_div'
Place-Item $spLine 1280 360 600 2

$spHdr = New-Item2 $screen.ScreenItems $T.Text 'sp_hdr'
Place-Item $spHdr 1280 370 600 20
Set-MultilingualText $spHdr 'Text' 'SETPOINTS'

$jsLbl = New-Item2 $screen.ScreenItems $T.Text 'js_lbl'
Place-Item $jsLbl 1280 400 200 20
Set-MultilingualText $jsLbl 'Text' 'Jog Speed [mm/s]'
$js = New-Item2 $screen.ScreenItems $T.IOField 'js_io'
Place-Item $js 1280 424 200 40
$bindings += Bind-Path $js 'ProcessValue' 'serverJogSpeedSet'

$mfLbl = New-Item2 $screen.ScreenItems $T.Text 'mf_lbl'
Place-Item $mfLbl 1500 400 200 20
Set-MultilingualText $mfLbl 'Text' 'Max Force [N]'
$mf = New-Item2 $screen.ScreenItems $T.IOField 'mf_io'
Place-Item $mf 1500 424 200 40
$bindings += Bind-Path $mf 'ProcessValue' 'serverJogMaxForceSet'

# ============== PROGRAM SELECTION ==============
$progPanel = New-Item2 $screen.ScreenItems $T.Rect 'prog_panel'
Place-Item $progPanel 1260 580 640 140
$progHdr = New-Item2 $screen.ScreenItems $T.Text 'prog_hdr'
Place-Item $progHdr 1260 590 640 22
Set-MultilingualText $progHdr 'Text' 'PROGRAM SELECTION'

$mpLbl = New-Item2 $screen.ScreenItems $T.Text 'mp_lbl'
Place-Item $mpLbl 1280 620 180 20
Set-MultilingualText $mpLbl 'Text' 'MP (0..127)'
$mp = New-Item2 $screen.ScreenItems $T.IOField 'mp_io'
Place-Item $mp 1280 644 180 50
$bindings += Bind-Path $mp 'ProcessValue' 'manualSelectMpNum'

$seqLbl = New-Item2 $screen.ScreenItems $T.Text 'seq_lbl'
Place-Item $seqLbl 1480 620 180 20
Set-MultilingualText $seqLbl 'Text' 'Sequence (0..3)'
$seq = New-Item2 $screen.ScreenItems $T.IOField 'seq_io'
Place-Item $seq 1480 644 180 50
$bindings += Bind-Path $seq 'ProcessValue' 'selectSequenceSet'

$pgLbl = New-Item2 $screen.ScreenItems $T.Text 'pg_lbl'
Place-Item $pgLbl 1680 620 180 20
Set-MultilingualText $pgLbl 'Text' 'Page (0..7)'
$pg = New-Item2 $screen.ScreenItems $T.IOField 'pg_io'
Place-Item $pg 1680 644 180 50
$bindings += Bind-Path $pg 'ProcessValue' 'selectPageSet'

# ============== ECHO BAR ==============
$ftPanel = New-Item2 $screen.ScreenItems $T.Rect 'ft_panel'
Place-Item $ftPanel 20 740 1880 320
$ftHdr = New-Item2 $screen.ScreenItems $T.Text 'ft_hdr'
Place-Item $ftHdr 20 750 1880 22
Set-MultilingualText $ftHdr 'Text' 'SEQUENCE / PROGRAM ECHO'

$activeMpLbl = New-Item2 $screen.ScreenItems $T.Text 'a_mp_lbl'
Place-Item $activeMpLbl 40 790 120 20
Set-MultilingualText $activeMpLbl 'Text' 'Active MP'
$activeMp = New-Item2 $screen.ScreenItems $T.IOField 'a_mp_io'
Place-Item $activeMp 40 814 120 50
$bindings += Bind-Path $activeMp 'ProcessValue' 'receive.mpNum'

$activeSeqLbl = New-Item2 $screen.ScreenItems $T.Text 'a_seq_lbl'
Place-Item $activeSeqLbl 180 790 120 20
Set-MultilingualText $activeSeqLbl 'Text' 'Active Seq'
$activeSeq = New-Item2 $screen.ScreenItems $T.IOField 'a_seq_io'
Place-Item $activeSeq 180 814 120 50
$bindings += Bind-Path $activeSeq 'ProcessValue' 'send.selectSeqeunce'

$activePgLbl = New-Item2 $screen.ScreenItems $T.Text 'a_pg_lbl'
Place-Item $activePgLbl 320 790 120 20
Set-MultilingualText $activePgLbl 'Text' 'Page'
$activePg = New-Item2 $screen.ScreenItems $T.IOField 'a_pg_io'
Place-Item $activePg 320 814 120 50
$bindings += Bind-Path $activePg 'ProcessValue' 'send.selectPage'

$labelLbl = New-Item2 $screen.ScreenItems $T.Text 'lbl_lbl'
Place-Item $labelLbl 460 790 160 20
Set-MultilingualText $labelLbl 'Text' 'Sequence Label'
$labelIo = New-Item2 $screen.ScreenItems $T.IOField 'lbl_io'
Place-Item $labelIo 460 814 160 50
$bindings += Bind-Path $labelIo 'ProcessValue' 'currentLabel'

$endLed = New-Item2 $screen.ScreenItems $T.Circle 'end_led'
Place-Item $endLed 660 814 28 28
$bindings += Bind-Path $endLed 'Visible' 'sequenceEnd'
$endLbl = New-Item2 $screen.ScreenItems $T.Text 'end_lbl'
Place-Item $endLbl 698 820 100 20
Set-MultilingualText $endLbl 'Text' 'Seq End'

$omLbl = New-Item2 $screen.ScreenItems $T.Text 'om_lbl'
Place-Item $omLbl 820 790 160 20
Set-MultilingualText $omLbl 'Text' 'Op Mode Area'
$omIo = New-Item2 $screen.ScreenItems $T.IOField 'om_io'
Place-Item $omIo 820 814 160 50
$bindings += Bind-Path $omIo 'ProcessValue' 'opmodearea'

$cnLbl = New-Item2 $screen.ScreenItems $T.Text 'cn_lbl'
Place-Item $cnLbl 1000 790 160 20
Set-MultilingualText $cnLbl 'Text' 'HMI Control #'
$cnIo = New-Item2 $screen.ScreenItems $T.IOField 'cn_io'
Place-Item $cnIo 1000 814 160 50
$bindings += Bind-Path $cnIo 'ProcessValue' 'hmiControlNo'

$footer = New-Item2 $screen.ScreenItems $T.Text 'footer'
Place-Item $footer 20 1030 1880 22
Set-MultilingualText $footer 'Text' "Kistler maXYmos NC | Bound to $RootTag (LDrive_typeKistlerHmi)"

# ============== Save ==============
Write-Host "`nSaving..."
try { $session.Save() ; Write-Host "Saved." } catch { Write-Warning "Save failed: $_" }

# ============== Report ==============
$bound   = $bindings | Where-Object { $_.Ok }
$failed  = $bindings | Where-Object { -not $_.Ok }

Write-Host ""
Write-Host "================================================="
Write-Host "  BUILD SUMMARY: $ScreenName"
Write-Host "================================================="
Write-Host "  Items:    $($screen.ScreenItems.Count)"
Write-Host "  Bindings: $($bindings.Count) total / $($bound.Count) bound / $($failed.Count) failed"
Write-Host "  RootTag:  $RootTag"
Write-Host ""

if ($bound.Count -gt 0) {
    Write-Host "BOUND PATHS:" -ForegroundColor Green
    foreach ($b in $bound) { Write-Host "  $($b.Path)" }
}
if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED BINDINGS (TIA rejected the path):" -ForegroundColor Yellow
    foreach ($f in $failed) { Write-Host "  $($f.Path)`n     reason: $($f.Reason)" }
}
Write-Host ""
Write-Host "Open '$ScreenName' on HMI '$($hmi.Name)' in TIA to view it."
