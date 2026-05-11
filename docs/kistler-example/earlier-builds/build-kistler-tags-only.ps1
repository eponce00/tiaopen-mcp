# build-kistler-tags-only.ps1
# Every binding is a TagDynamization pointing at a path in MVterminalPressKistler.
# Bit-extract LEDs/buttons bind to the whole DWord field (not the bit) -
# you wire bit-display via the editor's analog/discrete conversion later.

param(
    [string]$ScreenName = '_Kistler_Press_01',
    [string]$RootTag    = 'MVterminalPressKistler',
    [int]   $Width      = 1920,
    [int]   $Height     = 1080
)

$ErrorActionPreference = 'Stop'
[System.Reflection.Assembly]::LoadFrom("C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll") | Out-Null
$tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal  = $tia.Attach()
$session = $portal.LocalSessions[0]
$project = $session.Project

$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
function Get-Sw($di) { $m = $di.GetType().GetMethod('GetService').MakeGenericMethod($swT); return $m.Invoke($di, $null) }
function Walk($items) {
    foreach ($it in $items) { try { $svc = Get-Sw $it; if ($svc -and $svc.Software -and $svc.Software.GetType().FullName -match 'HmiUnified') { return $svc.Software } } catch {}; if ($it.DeviceItems) { $r = Walk $it.DeviceItems; if ($r) { return $r } } }
    return $null
}
$hmiSw = $null
foreach ($d in $project.Devices) { $hmiSw = Walk $d.DeviceItems; if ($hmiSw) { break } }
$null = $hmiSw.Screens.Count
Write-Host "HMI: $($hmiSw.Name)"

$rootTagObj = $hmiSw.Tags.Find($RootTag)
if (-not $rootTagObj) { throw "Root tag '$RootTag' not found" }
Write-Host "Root: $RootTag (DataType=$($rootTagObj.DataType))"

function Get-HmiType([string]$fn) { foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { try { $t = $a.GetType($fn, $false); if ($t) { return $t } } catch {} }; throw "no $fn" }
function NewItem([object]$comp, [string]$tName, [string]$name) {
    $t = Get-HmiType $tName
    $cg = $comp.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    return $cg.MakeGenericMethod($t).Invoke($comp, @($name))
}
function Place([object]$item, [int]$L, [int]$T, [int]$W, [int]$H) {
    $tt = $item.GetType()
    if ($tt.GetProperty('Left'))    { $item.Left=$L; $item.Top=$T; $item.Width=[uint32]$W; $item.Height=[uint32]$H }
    elseif ($tt.GetProperty('CenterX')) { $item.CenterX=$L+[int]($W/2); $item.CenterY=$T+[int]($H/2); $item.Radius=[uint32]([int]([Math]::Min($W,$H)/2)) }
    elseif ($tt.GetProperty('Point1')) { $p1=$item.Point1;$p2=$item.Point2; $p1.X=$L;$p1.Y=$T+[int]($H/2);$p2.X=$L+$W;$p2.Y=$T+[int]($H/2) }
}
function SetText([object]$item, [string]$prop, [string]$plain) {
    $p = $item.GetType().GetProperty($prop); if (-not $p) { return }
    $mlt = $p.GetValue($item); if (-not $mlt) { return }
    $xml = "<body><p>$plain</p></body>"
    foreach ($mli in $mlt.Items) { try { $mli.SetAttribute('Text', $xml) } catch {} }
}

$tagDynT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'
$results = New-Object System.Collections.ArrayList
function Bind([object]$item, [string]$prop, [string]$path) {
    $full = "$RootTag.$path"
    try {
        $cg = $item.Dynamizations.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
        $d  = $cg.MakeGenericMethod($tagDynT).Invoke($item.Dynamizations, @($prop))
        $d.SetAttribute('Tag', $full)
        [void]$results.Add([pscustomobject]@{ Item=$item.Name; Prop=$prop; Path=$full; Ok=$true })
    } catch {
        $i = $_.Exception.InnerException; $m = if ($i) { $i.Message } else { $_.Exception.Message }
        [void]$results.Add([pscustomobject]@{ Item=$item.Name; Prop=$prop; Path=$full; Ok=$false; Err=$m.Split([char]10)[0] })
    }
}

# ---- create screen ----
$existing = $hmiSw.Screens.Find($ScreenName); if ($existing) { try { $existing.Delete() } catch {} ; Write-Host "Deleted $ScreenName" }
$screen = $hmiSw.Screens.Create($ScreenName)
$screen.Width = [uint32]$Width; $screen.Height = [uint32]$Height
Write-Host "Created $ScreenName ($Width x $Height)"

$T = @{
    Rect=  'Siemens.Engineering.HmiUnified.UI.Shapes.HmiRectangle'
    Text=  'Siemens.Engineering.HmiUnified.UI.Shapes.HmiText'
    Circle='Siemens.Engineering.HmiUnified.UI.Shapes.HmiCircle'
    Line=  'Siemens.Engineering.HmiUnified.UI.Shapes.HmiLine'
    IO=    'Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField'
    Button='Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton'
}

# HEADER
$it = NewItem $screen.ScreenItems $T.Rect 'hdr_bg';      Place $it 0 0 $Width 80
$it = NewItem $screen.ScreenItems $T.Rect 'hdr_accent';  Place $it 0 0 8 80
$it = NewItem $screen.ScreenItems $T.Text 'hdr_title';   Place $it 24 14 400 28; SetText $it 'Text' 'KISTLER maXYmos NC'
$it = NewItem $screen.ScreenItems $T.Text 'hdr_subtitle';Place $it 24 44 400 22; SetText $it 'Text' 'Press Controller'

$it = NewItem $screen.ScreenItems $T.Rect 'plant_box'; Place $it 480 24 320 36
$plantIo = NewItem $screen.ScreenItems $T.IO 'plant_io';  Place $plantIo 488 28 300 30
Bind $plantIo 'ProcessValue' 'plantidentifier'

$it = NewItem $screen.ScreenItems $T.Text 'tu_lbl'; Place $it 1780 18 50 18; SetText $it 'Text' 'Unit #'
$tuIo = NewItem $screen.ScreenItems $T.IO 'tu_io';  Place $tuIo 1840 16 60 50
Bind $tuIo 'ProcessValue' 'tecUnitNumber'

$scBadge = NewItem $screen.ScreenItems $T.Rect 'sc_badge'; Place $scBadge 1620 22 140 40
Bind $scBadge 'BackColor' 'stateColour'

# STATUS PANEL  (LEDs bound to whole DWord; bit-display can be added in editor)
$it = NewItem $screen.ScreenItems $T.Rect 'status_panel'; Place $it 20 100 260 460
$it = NewItem $screen.ScreenItems $T.Text 'status_hdr';   Place $it 20 110 260 20; SetText $it 'Text' 'STATUS'

$statusBits = @(
    @{ Lbl='Ready';         Field='receive.status'; BitName='x2'  },
    @{ Lbl='OK Total';      Field='receive.status'; BitName='x8'  },
    @{ Lbl='NOK Total';     Field='receive.status'; BitName='x9'  },
    @{ Lbl='Drive Enabled'; Field='receive.status'; BitName='x1'  },
    @{ Lbl='At Home Pos';   Field='receive.status'; BitName='x5'  },
    @{ Lbl='At Reference';  Field='receive.status'; BitName='x4'  },
    @{ Lbl='Standstill';    Field='receive.status'; BitName='x6'  },
    @{ Lbl='Sequence End';  Field='receive.status'; BitName='x12' },
    @{ Lbl='Wait Request';  Field='receive.status'; BitName='x3'  },
    @{ Lbl='Kistler Auto';  Field='receive.status'; BitName='x0'  },
    @{ Lbl='SMES Active';   Field='receive.status'; BitName='x13' },
    @{ Lbl='Safety OK';     Field='state';          BitName='x2'  }
)
$y = 140; $i = 0
foreach ($s in $statusBits) {
    $i++
    $led = NewItem $screen.ScreenItems $T.Circle ("led_st_$i"); Place $led 36 $y 18 18
    Bind $led 'BackColor' $s.Field
    $lbl = NewItem $screen.ScreenItems $T.Text ("lbl_st_$i"); Place $lbl 64 $y 160 20; SetText $lbl 'Text' $s.Lbl
    $bit = NewItem $screen.ScreenItems $T.Text ("bit_st_$i"); Place $bit 220 $y 60 18; SetText $bit 'Text' "$($s.Field).$($s.BitName)"
    $y += 24
}

# ALARM PANEL
$it = NewItem $screen.ScreenItems $T.Rect 'alm_panel'; Place $it 20 580 260 400
$it = NewItem $screen.ScreenItems $T.Text 'alm_hdr';   Place $it 20 590 260 20; SetText $it 'Text' 'ALARMS'

$almBits = @(
    @{ Lbl='Hardware NOK';      Field='alarm'; BitName='x1'  },
    @{ Lbl='TX Fault';          Field='alarm'; BitName='x2'  },
    @{ Lbl='Drive Enable NOK';  Field='alarm'; BitName='x3'  },
    @{ Lbl='Safety NOK';        Field='alarm'; BitName='x13' },
    @{ Lbl='Cycle Timeout';     Field='alarm'; BitName='x6'  },
    @{ Lbl='Wait Cmd Missing';  Field='alarm'; BitName='x9'  },
    @{ Lbl='Remote Inactive';   Field='alarm'; BitName='x16' },
    @{ Lbl='Serial Mismatch';   Field='alarm'; BitName='x17' }
)
$y = 620; $i = 0
foreach ($a in $almBits) {
    $i++
    $led = NewItem $screen.ScreenItems $T.Circle ("led_alm_$i"); Place $led 36 $y 18 18
    Bind $led 'BackColor' $a.Field
    $lbl = NewItem $screen.ScreenItems $T.Text ("lbl_alm_$i"); Place $lbl 64 $y 160 20; SetText $lbl 'Text' $a.Lbl
    $bit = NewItem $screen.ScreenItems $T.Text ("bit_alm_$i"); Place $bit 220 $y 60 18; SetText $bit 'Text' "$($a.Field).$($a.BitName)"
    $y += 32
}

# F-D AREA
$it = NewItem $screen.ScreenItems $T.Rect 'fd_bg'; Place $it 300 100 940 460
$it = NewItem $screen.ScreenItems $T.Text 'fd_hdr'; Place $it 320 110 400 22; SetText $it 'Text' 'FORCE-DISPLACEMENT CURVE'
$it = NewItem $screen.ScreenItems $T.Text 'fd_xaxis'; Place $it 700 530 300 20; SetText $it 'Text' 'Displacement X [mm]'
$it = NewItem $screen.ScreenItems $T.Text 'fd_yaxis'; Place $it 312 320 100 20; SetText $it 'Text' 'Force Y [N]'

$xMin = NewItem $screen.ScreenItems $T.IO 'fd_xmin'; Place $xMin 340 510 100 24
Bind $xMin 'ProcessValue' 'receive.PVcurrentXmin-X'
$xMax = NewItem $screen.ScreenItems $T.IO 'fd_xmax'; Place $xMax 1100 510 100 24
Bind $xMax 'ProcessValue' 'receive.PVcurrentXmax-X'
$yMin = NewItem $screen.ScreenItems $T.IO 'fd_ymin'; Place $yMin 340 480 100 24
Bind $yMin 'ProcessValue' 'receive.PVcurrentYmin-Y'
$yMax = NewItem $screen.ScreenItems $T.IO 'fd_ymax'; Place $yMax 340 140 100 24
Bind $yMax 'ProcessValue' 'receive.PVcurrentYmax-Y'

$it = NewItem $screen.ScreenItems $T.Text 'fd_note'; Place $it 600 320 400 20; SetText $it 'Text' 'Trend control here (X=Disp, Y=Force)'

# PROCESS VALUES
$it = NewItem $screen.ScreenItems $T.Rect 'pv_panel'; Place $it 300 580 940 140
$it = NewItem $screen.ScreenItems $T.Text 'pv_hdr';   Place $it 300 590 940 22; SetText $it 'Text' 'PROCESS VALUES'

$it = NewItem $screen.ScreenItems $T.Text 'pv_force_lbl'; Place $it 320 620 280 20; SetText $it 'Text' 'Force Y [N]'
$pvForce = NewItem $screen.ScreenItems $T.IO 'pv_force'; Place $pvForce 320 644 280 60
Bind $pvForce 'ProcessValue' 'receive.PVcurrentValueY'

$it = NewItem $screen.ScreenItems $T.Text 'pv_disp_lbl'; Place $it 620 620 280 20; SetText $it 'Text' 'Displacement X [mm]'
$pvDisp = NewItem $screen.ScreenItems $T.IO 'pv_disp'; Place $pvDisp 620 644 280 60
Bind $pvDisp 'ProcessValue' 'receive.PVcurrentValueX'

$it = NewItem $screen.ScreenItems $T.Text 'pv_grad_lbl'; Place $it 920 620 300 20; SetText $it 'Text' 'Gradient [N/mm]'
$pvGrad = NewItem $screen.ScreenItems $T.IO 'pv_grad'; Place $pvGrad 920 644 300 60
Bind $pvGrad 'ProcessValue' 'receive.PV_EO3_Gradient'

# CONTROLS  (button BackColor bound to send.control whole DWord)
$it = NewItem $screen.ScreenItems $T.Rect 'ctrl_panel'; Place $it 1260 100 640 460
$it = NewItem $screen.ScreenItems $T.Text 'ctrl_hdr';   Place $it 1260 110 640 22; SetText $it 'Text' 'CONTROLS  (writes to interfaceHmi.move bits)'

$buttons = @(
    @{ Lbl='RUN';       Id='Run';      W=200; H=60; Col=0; Row=0 },
    @{ Lbl='ACK ADMIN'; Id='AckAdmin'; W=200; H=60; Col=2; Row=0 },
    @{ Lbl='HOME';      Id='Home';     W=140; H=50; Col=0; Row=1 },
    @{ Lbl='REF';       Id='Ref';      W=140; H=50; Col=1; Row=1 },
    @{ Lbl='REMOTE';    Id='Remote';   W=140; H=50; Col=2; Row=1 },
    @{ Lbl='CONT WAIT'; Id='ContWait'; W=140; H=50; Col=0; Row=2 },
    @{ Lbl='JOG +';     Id='JogPlus';  W=140; H=50; Col=1; Row=2 },
    @{ Lbl='JOG -';     Id='JogMinus'; W=140; H=50; Col=2; Row=2 }
)
$colX = @(1280, 1430, 1580); $rowY = @(140, 220, 290)
foreach ($b in $buttons) {
    $btn = NewItem $screen.ScreenItems $T.Button "btn_$($b.Id)"
    Place $btn $colX[$b.Col] $rowY[$b.Row] $b.W $b.H
    SetText $btn 'Text' $b.Lbl
    Bind $btn 'BackColor' 'send.control'
}

$it = NewItem $screen.ScreenItems $T.Line 'sp_div'; Place $it 1280 360 600 2
$it = NewItem $screen.ScreenItems $T.Text 'sp_hdr'; Place $it 1280 370 600 20; SetText $it 'Text' 'SETPOINTS'

$it = NewItem $screen.ScreenItems $T.Text 'js_lbl'; Place $it 1280 400 200 20; SetText $it 'Text' 'Jog Speed [mm/s]'
$js = NewItem $screen.ScreenItems $T.IO 'js_io'; Place $js 1280 424 200 40
Bind $js 'ProcessValue' 'serverJogSpeedSet'

$it = NewItem $screen.ScreenItems $T.Text 'mf_lbl'; Place $it 1500 400 200 20; SetText $it 'Text' 'Max Force [N]'
$mf = NewItem $screen.ScreenItems $T.IO 'mf_io'; Place $mf 1500 424 200 40
Bind $mf 'ProcessValue' 'serverJogMaxForceSet'

# PROGRAM
$it = NewItem $screen.ScreenItems $T.Rect 'prog_panel'; Place $it 1260 580 640 140
$it = NewItem $screen.ScreenItems $T.Text 'prog_hdr';   Place $it 1260 590 640 22; SetText $it 'Text' 'PROGRAM SELECTION'

$it = NewItem $screen.ScreenItems $T.Text 'mp_lbl'; Place $it 1280 620 180 20; SetText $it 'Text' 'MP (0..127)'
$mp = NewItem $screen.ScreenItems $T.IO 'mp_io'; Place $mp 1280 644 180 50
Bind $mp 'ProcessValue' 'manualSelectMpNum'

$it = NewItem $screen.ScreenItems $T.Text 'seq_lbl'; Place $it 1480 620 180 20; SetText $it 'Text' 'Sequence (0..3)'
$seq = NewItem $screen.ScreenItems $T.IO 'seq_io'; Place $seq 1480 644 180 50
Bind $seq 'ProcessValue' 'selectSequenceSet'

$it = NewItem $screen.ScreenItems $T.Text 'pg_lbl'; Place $it 1680 620 180 20; SetText $it 'Text' 'Page (0..7)'
$pg = NewItem $screen.ScreenItems $T.IO 'pg_io'; Place $pg 1680 644 180 50
Bind $pg 'ProcessValue' 'selectPageSet'

# ECHO BAR
$it = NewItem $screen.ScreenItems $T.Rect 'ft_panel'; Place $it 20 740 1880 320
$it = NewItem $screen.ScreenItems $T.Text 'ft_hdr';   Place $it 20 750 1880 22; SetText $it 'Text' 'SEQUENCE / PROGRAM ECHO'

$it = NewItem $screen.ScreenItems $T.Text 'a_mp_lbl'; Place $it 40 790 120 20; SetText $it 'Text' 'Active MP'
$ami = NewItem $screen.ScreenItems $T.IO 'a_mp_io';   Place $ami 40 814 120 50
Bind $ami 'ProcessValue' 'receive.mpNum'

$it = NewItem $screen.ScreenItems $T.Text 'a_seq_lbl'; Place $it 180 790 120 20; SetText $it 'Text' 'Active Seq'
$asi = NewItem $screen.ScreenItems $T.IO 'a_seq_io';   Place $asi 180 814 120 50
Bind $asi 'ProcessValue' 'send.selectSeqeunce'

$it = NewItem $screen.ScreenItems $T.Text 'a_pg_lbl'; Place $it 320 790 120 20; SetText $it 'Text' 'Page'
$api = NewItem $screen.ScreenItems $T.IO 'a_pg_io';   Place $api 320 814 120 50
Bind $api 'ProcessValue' 'send.selectPage'

$it = NewItem $screen.ScreenItems $T.Text 'lbl_lbl'; Place $it 460 790 160 20; SetText $it 'Text' 'Sequence Label'
$lbi = NewItem $screen.ScreenItems $T.IO 'lbl_io';   Place $lbi 460 814 160 50
Bind $lbi 'ProcessValue' 'currentLabel'

$endLed = NewItem $screen.ScreenItems $T.Circle 'end_led'; Place $endLed 660 814 28 28
Bind $endLed 'Visible' 'sequenceEnd'
$it = NewItem $screen.ScreenItems $T.Text 'end_lbl'; Place $it 698 820 100 20; SetText $it 'Text' 'Seq End'

$it = NewItem $screen.ScreenItems $T.Text 'om_lbl'; Place $it 820 790 160 20; SetText $it 'Text' 'Op Mode Area'
$omi = NewItem $screen.ScreenItems $T.IO 'om_io';   Place $omi 820 814 160 50
Bind $omi 'ProcessValue' 'opmodearea'

$it = NewItem $screen.ScreenItems $T.Text 'cn_lbl'; Place $it 1000 790 160 20; SetText $it 'Text' 'HMI Control #'
$cni = NewItem $screen.ScreenItems $T.IO 'cn_io';   Place $cni 1000 814 160 50
Bind $cni 'ProcessValue' 'hmiControlNo'

$it = NewItem $screen.ScreenItems $T.Text 'footer'; Place $it 20 1030 1880 22
SetText $it 'Text' "Kistler maXYmos NC | Bound to $RootTag (LDrive_typeKistlerHmi)"

# Save and compile
Write-Host "`nSaving..."
$session.Save()
Write-Host "Compiling HMI..."

$compT = $null
foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { try { $tt = $a.GetType('Siemens.Engineering.Compiler.ICompilable', $false); if ($tt) { $compT = $tt; break } } catch {} }
$cur = $hmiSw.Parent; $comp = $null
while ($cur -and -not $comp) {
    $gs = $cur.GetType().GetMethods() | Where-Object { $_.Name -eq 'GetService' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    if ($gs) { try { $comp = $gs.MakeGenericMethod($compT).Invoke($cur, $null) } catch {} }
    $cur = $cur.Parent
}
$cr = $comp.Compile()
Write-Host "Compile state: $($cr.State)  Errors=$($cr.ErrorCount)  Warnings=$($cr.WarningCount)"

$bag = New-Object System.Collections.ArrayList
function FlatA($m) { [void]$bag.Add($m); foreach ($s in $m.Messages) { FlatA $s } }
foreach ($m in $cr.Messages) { FlatA $m }
$errs = $bag | Where-Object { $_.State -eq 'Error' -and $_.Description }
if ($errs.Count -gt 0) {
    Write-Host "`n=== Errors ===" -ForegroundColor Red
    foreach ($e in $errs) { Write-Host "  [$($e.Path)] $($e.Description)" }
}

$bound = $results | Where-Object Ok
$failed = $results | Where-Object { -not $_.Ok }
Write-Host ""
Write-Host "================================================="
Write-Host "  $ScreenName  -  Items=$($screen.ScreenItems.Count)  Bindings=$($results.Count) (bound=$($bound.Count) failed=$($failed.Count))"
Write-Host "================================================="
if ($failed.Count) { foreach ($f in $failed) { Write-Host "  FAILED: $($f.Item).$($f.Prop) = $($f.Path) -- $($f.Err)" } }
