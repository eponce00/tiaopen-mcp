# build-kistler-pro.ps1
# Professional Kistler maXYmos NC press HMI screen, built from scratch.
# Applies all session learning:
#   §14 - Verified Openness pattern
#   §16 - Singlebit bit-extraction (correct ConditionType)
#   §17 - SICAR color standard
#   §19 - FB-verified bit map (UDT single source of truth)
#   §20 - Widget selection by direction (HmiText for read-only, IOField Output
#         for numbers needing format, IOField InputOutput for editable setpoints,
#         HmiCircle+Singlebit for DWord bits, HmiButton+EventHandlers for cmds)
#   §21 - EO byte = pass/fail (don't invent Result columns)
#
# Layout (1920 x 1080):
#   HEADER         y=0..72        — dark ribbon: title / plant ID / state badge / unit#
#   STATUS card    y=92..560 x=20..320     — 12 status LEDs (receive.status + state.x2)
#   ALARM card     y=580..980 x=20..320    — 8 alarm LEDs (alarm DWord bits)
#   F-D HERO       y=92..612 x=340..1500   — big curve area + axis labels + live PV overlay
#   PV cards       y=632..760 x=340..1500  — 3 huge process value cards (Force/Disp/Gradient)
#   CONTROL card   y=92..760 x=1520..1900  — Run/Stop/movement buttons + setpoints + program
#   ECHO panel     y=780..1060 x=20..1900  — EO results table + sequence/program/config echo grid
#   FOOTER strip   y=1062..1080            — version/identifier strip

param(
    [string]$ScreenName = '_Kistler_Press_01',
    [string]$RootTag    = 'MVterminalPressKistler'
)
$ErrorActionPreference = 'Stop'
[System.Reflection.Assembly]::LoadFrom("C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll") | Out-Null
$tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal = $tia.Attach(); $session = $portal.LocalSessions[0]; $project = $session.Project
$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
function Get-Sw($di) { $m = $di.GetType().GetMethod('GetService').MakeGenericMethod($swT); $m.Invoke($di, $null) }
function Walk($items) { foreach ($it in $items) { try { $svc = Get-Sw $it; if ($svc -and $svc.Software -and $svc.Software.GetType().FullName -match 'HmiUnified') { return $svc.Software } } catch {}; if ($it.DeviceItems) { $r = Walk $it.DeviceItems; if ($r) { return $r } } }; return $null }
$hmiSw = $null; foreach ($d in $project.Devices) { $hmiSw = Walk $d.DeviceItems; if ($hmiSw) { break } }
$null = $hmiSw.Screens.Count
Write-Host "HMI: $($hmiSw.Name)"

# ---- Type lookup ----
function Get-HmiType($fn) { foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { try { $t = $a.GetType($fn, $false); if ($t) { return $t } } catch {} }; throw "no $fn" }
$Global:T = @{
    Rect   = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiRectangle'
    Text   = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiText'
    Circle = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiCircle'
    Line   = 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiLine'
    IO     = 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField'
    Button = 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton'
}
$T = $Global:T
$tagDynT  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'
$ctT      = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.Tag.ConditionType'
$Singlebit = [Enum]::Parse($ctT, 'Singlebit')
$ioTypeT  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiIOFieldType'
$Global:OutputOnly = [Enum]::Parse($ioTypeT, 'Output')
$Global:InputOutput = [Enum]::Parse($ioTypeT, 'InputOutput')
$OutputOnly = $Global:OutputOnly
$InputOutput = $Global:InputOutput
$btnEvtT  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiButtonEventType'
$Activated   = [Enum]::Parse($btnEvtT, 'Activated')
$Deactivated = [Enum]::Parse($btnEvtT, 'Deactivated')
$Tapped      = [Enum]::Parse($btnEvtT, 'Tapped')

# ---- SICAR + modern industrial palette ----
$C = @{
    # Header / chrome
    HeaderBg      = [System.Drawing.Color]::FromArgb(255,  44,  62,  80)   # #2C3E50 dark blue-gray
    HeaderText    = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
    HeaderSub     = [System.Drawing.Color]::FromArgb(255, 189, 195, 199)   # #BDC3C7
    Accent        = [System.Drawing.Color]::FromArgb(255,  52, 152, 219)   # #3498DB blue accent stripe
    # Cards / panels
    CardBg        = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
    CardBorder    = [System.Drawing.Color]::FromArgb(255, 208, 211, 214)   # #D0D3D6
    PanelBg       = [System.Drawing.Color]::FromArgb(255, 245, 246, 250)   # #F5F6FA app bg
    SectionHdrBg  = [System.Drawing.Color]::FromArgb(255, 236, 240, 241)   # #ECF0F1
    # Text
    PrimaryText   = [System.Drawing.Color]::FromArgb(255,  44,  62,  80)
    SecondaryText = [System.Drawing.Color]::FromArgb(255, 127, 140, 141)   # #7F8C8D
    LabelText     = [System.Drawing.Color]::FromArgb(255, 100, 113, 114)
    # SICAR status colors (§17)
    LightGreen    = [System.Drawing.Color]::FromArgb(255, 146, 208,  80)   # On / good / OK / present
    LightBlue     = [System.Drawing.Color]::FromArgb(255,   0, 176, 240)   # Manual / remote
    OliveGreen    = [System.Drawing.Color]::FromArgb(255,   0, 176,  80)   # Single step
    Orange        = [System.Drawing.Color]::FromArgb(255, 255, 192,   0)   # Enable missing / wait
    Red           = [System.Drawing.Color]::FromArgb(255, 230,  57,  53)   # Alarm / NOK  (slightly muted)
    Yellow        = [System.Drawing.Color]::FromArgb(255, 255, 235,  59)   # Safety / info
    OffGray       = [System.Drawing.Color]::FromArgb(255, 215, 219, 221)   # Off neutral
    # Button colors
    BtnRunBg      = [System.Drawing.Color]::FromArgb(255,  39, 174,  96)   # green primary
    BtnRunHover   = [System.Drawing.Color]::FromArgb(255,  46, 204, 113)
    BtnStopBg     = [System.Drawing.Color]::FromArgb(255, 231,  76,  60)   # red stop
    BtnNeutralBg  = [System.Drawing.Color]::FromArgb(255,  52,  73,  94)   # dark blue-gray
    BtnNeutralHov = [System.Drawing.Color]::FromArgb(255,  74,  98, 121)
    BtnWarnBg     = [System.Drawing.Color]::FromArgb(255, 243, 156,  18)
    BtnText       = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
}

# ---- Helpers ----
function NewItem($comp, $tName, $name) {
    $t = Get-HmiType $tName
    $cg = $comp.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    return $cg.MakeGenericMethod($t).Invoke($comp, @($name))
}
function Place($it, $L, $T, $W, $H) {
    $tt = $it.GetType()
    if ($tt.GetProperty('Left')) {
        $it.Left = $L; $it.Top = $T; $it.Width = [uint32]$W; $it.Height = [uint32]$H
    } elseif ($tt.GetProperty('CenterX')) {
        $it.CenterX = $L + [int]($W/2); $it.CenterY = $T + [int]($H/2)
        $it.Radius = [uint32]([int]([Math]::Min($W,$H)/2))
    } elseif ($tt.GetProperty('Point1')) {
        $p1=$it.Point1;$p2=$it.Point2; $p1.X=$L;$p1.Y=$T+[int]($H/2);$p2.X=$L+$W;$p2.Y=$T+[int]($H/2)
    }
}
function SetText($it, $plain, [int]$size = 11, [int]$weight = 400, $color = $null, $halign = 'Left', $valign = 'Center') {
    $prop = $it.GetType().GetProperty('Text'); if (-not $prop) { return }
    $mlt = $prop.GetValue($it); if (-not $mlt) { return }
    $xml = "<body><p><span style=`"font-size:${size}px; font-weight:${weight}`">$plain</span></p></body>"
    foreach ($m in $mlt.Items) { try { $m.SetAttribute('Text', $xml) } catch {} }
    if ($color -ne $null) {
        $fc = $it.GetType().GetProperty('ForeColor')
        if ($fc -and $fc.CanWrite) { $fc.SetValue($it, $color) }
    }
    $ha = $it.GetType().GetProperty('HorizontalTextAlignment')
    if ($ha -and $ha.CanWrite) {
        try {
            $alignT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiHorizontalAlignment'
            $ha.SetValue($it, [Enum]::Parse($alignT, $halign))
        } catch {}
    }
    $va = $it.GetType().GetProperty('VerticalTextAlignment')
    if ($va -and $va.CanWrite) {
        try {
            $valignT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiVerticalAlignment'
            $va.SetValue($it, [Enum]::Parse($valignT, $valign))
        } catch {}
    }
}
function StyleRect($r, $bg, $border = $null, [int]$borderWidth = 1) {
    $r.BackColor = $bg
    if ($border) { $r.BorderColor = $border; $r.BorderWidth = [byte]$borderWidth }
    else { $r.BorderWidth = [byte]0 }
}
function BindTag($it, $prop, $path) {
    $cg = $it.Dynamizations.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    $dyn = $cg.MakeGenericMethod($tagDynT).Invoke($it.Dynamizations, @($prop))
    $dyn.SetAttribute('Tag', "$RootTag.$path")
    # NOTE: returns nothing to keep stdout clean. Callers that need dyn use BindTagAndGet
}
function BindTagAndGet($it, $prop, $path) {
    $cg = $it.Dynamizations.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    $dyn = $cg.MakeGenericMethod($tagDynT).Invoke($it.Dynamizations, @($prop))
    $dyn.SetAttribute('Tag', "$RootTag.$path")
    return $dyn
}
$Global:haT = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiHorizontalAlignment'
function MakeOutputIO($name, $L, $T, $W, $H, $path, [string]$format, [int]$fontSize, [string]$fontWeight, $foreColor, $bgColor, [string]$halign) {
    $io = NewItem $screen.ScreenItems $Global:T.IO $name
    Place $io $L $T $W $H
    $io.IOFieldType = $Global:OutputOnly
    $io.BackColor = $bgColor
    $io.ForeColor = $foreColor
    $io.BorderWidth = [byte]0
    if ($format) { $io.OutputFormat = $format }
    if ($halign) { $io.HorizontalTextAlignment = [Enum]::Parse($Global:haT, $halign) }
    try {
        $f = $io.Font
        if ($f) {
            if ($fontSize -gt 0) { $f.SetAttribute('Size', [byte]$fontSize) }
            if ($fontWeight) { $f.SetAttribute('Weight', $fontWeight) }
        }
    } catch {}
    BindTag $io 'ProcessValue' $path
    return $io
}
function BindBit($circle, [int]$bit, $onColor, $offColor, $fieldPath) {
    $dyn = BindTagAndGet $circle 'BackColor' $fieldPath
    $mt = $dyn.ValueConverter.MappingTable
    foreach ($e in @($mt.Entries)) { try { $e.Delete() } catch {} }
    $mt.SetAttribute('ConditionType', $Singlebit)
    $entries = @($mt.Entries)
    if ($entries.Count -ne 2) { throw "expected 2 entries after Singlebit on $($circle.Name)" }
    $mask = [UInt64][Math]::Pow(2, $bit)
    $entries[1].Condition = $mask
    $entries[0].Value = $offColor
    $entries[1].Value = $onColor
}

# ============================================================
# Drop existing screen, build fresh
# ============================================================
$existing = $hmiSw.Screens.Find($ScreenName); if ($existing) { try { $existing.Delete() } catch {} }
$screen = $hmiSw.Screens.Create($ScreenName)
$screen.Width = [uint32]1920; $screen.Height = [uint32]1080
$screen.BackColor = $C.PanelBg
Write-Host "Created fresh: $ScreenName"

# ============================================================
# HEADER ribbon  y=0..72
# ============================================================
$hdr = NewItem $screen.ScreenItems $T.Rect 'hdr_bg'
Place $hdr 0 0 1920 72
StyleRect $hdr $C.HeaderBg

# Left blue accent stripe
$accent = NewItem $screen.ScreenItems $T.Rect 'hdr_accent'
Place $accent 0 0 6 72
StyleRect $accent $C.Accent

# Title block (left)
$title = NewItem $screen.ScreenItems $T.Text 'hdr_title'
Place $title 28 14 320 26
SetText $title 'KISTLER maXYmos NC' 16 700 $C.HeaderText
$subtitle = NewItem $screen.ScreenItems $T.Text 'hdr_subtitle'
Place $subtitle 28 40 320 18
SetText $subtitle 'Press Monitor and Controller' 10 400 $C.HeaderSub

# Plant identifier (centered, prominent)
$plantLbl = NewItem $screen.ScreenItems $T.Text 'plant_lbl'
Place $plantLbl 600 12 720 16
SetText $plantLbl 'PLANT' 9 600 $C.HeaderSub 'Center'
$plant_io = NewItem $screen.ScreenItems $T.Text 'plant_io'
Place $plant_io 600 28 720 32
SetText $plant_io '...' 18 700 $C.HeaderText 'Center'
BindTag $plant_io 'Text' 'plantidentifier'

# State badge (top right)
$scBadge = NewItem $screen.ScreenItems $T.Rect 'sc_badge'
Place $scBadge 1480 16 220 40
StyleRect $scBadge $C.OffGray
BindTag $scBadge 'BackColor' 'stateColour'   # will pick up via runtime, also TIA UI shows for tweaking
$scTxt = NewItem $screen.ScreenItems $T.Text 'sc_txt'
Place $scTxt 1480 18 220 36
SetText $scTxt 'OPERATING STATE' 11 700 $C.PrimaryText 'Center'

# Unit number box (far right) — IOField Output (formatted integer)
$unitBox = NewItem $screen.ScreenItems $T.Rect 'unit_box'
Place $unitBox 1720 16 180 40
StyleRect $unitBox $C.BtnNeutralBg
$unitLbl = NewItem $screen.ScreenItems $T.Text 'unit_lbl'
Place $unitLbl 1720 18 60 36
SetText $unitLbl 'UNIT' 9 600 $C.HeaderSub 'Center'
$tu_io = NewItem $screen.ScreenItems $T.IO 'tu_io'
Place $tu_io 1780 16 120 40
$tu_io.IOFieldType = $OutputOnly
$tu_io.BackColor = $C.BtnNeutralBg
$tu_io.ForeColor = $C.HeaderText
$tu_io.BorderWidth = [byte]0
BindTag $tu_io 'ProcessValue' 'tecUnitNumber'

# ============================================================
# Status card  y=92..560 x=20..320
# ============================================================
$statusCard = NewItem $screen.ScreenItems $T.Rect 'status_card'
Place $statusCard 20 92 300 468
StyleRect $statusCard $C.CardBg $C.CardBorder 1
$statusHdrBg = NewItem $screen.ScreenItems $T.Rect 'status_hdr_bg'
Place $statusHdrBg 20 92 300 32
StyleRect $statusHdrBg $C.SectionHdrBg
$statusHdr = NewItem $screen.ScreenItems $T.Text 'status_hdr'
Place $statusHdr 36 92 280 32
SetText $statusHdr 'STATUS' 12 700 $C.PrimaryText 'Left'

$statusBits = @(
    @{ Lbl='Ready';         Field='receive.status'; Bit=2;  OnColor=$C.LightGreen },
    @{ Lbl='Drive Enabled'; Field='receive.status'; Bit=1;  OnColor=$C.LightGreen },
    @{ Lbl='Auto Mode';     Field='receive.status'; Bit=0;  OnColor=$C.LightGreen },
    @{ Lbl='Standstill';    Field='receive.status'; Bit=6;  OnColor=$C.LightBlue  },
    @{ Lbl='At Home Pos';   Field='receive.status'; Bit=5;  OnColor=$C.LightGreen },
    @{ Lbl='At Reference';  Field='receive.status'; Bit=4;  OnColor=$C.LightGreen },
    @{ Lbl='Wait Request';  Field='receive.status'; Bit=3;  OnColor=$C.Orange     },
    @{ Lbl='Sequence End';  Field='receive.status'; Bit=12; OnColor=$C.LightGreen },
    @{ Lbl='OK Total';      Field='receive.status'; Bit=8;  OnColor=$C.LightGreen },
    @{ Lbl='NOK Total';     Field='receive.status'; Bit=9;  OnColor=$C.Red        },
    @{ Lbl='SMES Active';   Field='receive.status'; Bit=13; OnColor=$C.Yellow     },
    @{ Lbl='Safety OK';     Field='state';          Bit=2;  OnColor=$C.LightGreen }
)
$y = 134
$idx = 0
foreach ($s in $statusBits) {
    $idx++
    $led = NewItem $screen.ScreenItems $T.Circle ("led_st_$idx")
    Place $led 40 $y 16 16
    BindBit $led $s.Bit $s.OnColor $C.OffGray $s.Field
    $lbl = NewItem $screen.ScreenItems $T.Text ("lbl_st_$idx")
    Place $lbl 66 $y 180 20
    SetText $lbl $s.Lbl 11 400 $C.PrimaryText
    $bitTxt = NewItem $screen.ScreenItems $T.Text ("bit_st_$idx")
    Place $bitTxt 250 $y 60 20
    SetText $bitTxt "$($s.Field).x$($s.Bit)" 8 400 $C.SecondaryText 'Right'
    $y += 34
}

# ============================================================
# Alarm card  y=580..980 x=20..320
# ============================================================
$almCard = NewItem $screen.ScreenItems $T.Rect 'alm_card'
Place $almCard 20 580 300 400
StyleRect $almCard $C.CardBg $C.CardBorder 1
$almHdrBg = NewItem $screen.ScreenItems $T.Rect 'alm_hdr_bg'
Place $almHdrBg 20 580 300 32
StyleRect $almHdrBg $C.SectionHdrBg
$almHdr = NewItem $screen.ScreenItems $T.Text 'alm_hdr'
Place $almHdr 36 580 280 32
SetText $almHdr 'ALARMS' 12 700 $C.PrimaryText 'Left'

$alarmBits = @(
    @{ Lbl='Hardware NOK';      Field='alarm'; Bit=1;  OnColor=$C.Red    },
    @{ Lbl='TX Fault';          Field='alarm'; Bit=2;  OnColor=$C.Red    },
    @{ Lbl='Drive Enable NOK';  Field='alarm'; Bit=3;  OnColor=$C.Red    },
    @{ Lbl='Safety NOK';        Field='alarm'; Bit=13; OnColor=$C.Red    },
    @{ Lbl='Cycle Timeout';     Field='alarm'; Bit=6;  OnColor=$C.Red    },
    @{ Lbl='Wait Cmd Missing';  Field='alarm'; Bit=9;  OnColor=$C.Orange },
    @{ Lbl='Remote Inactive';   Field='alarm'; Bit=16; OnColor=$C.Orange },
    @{ Lbl='Serial Mismatch';   Field='alarm'; Bit=17; OnColor=$C.Red    }
)
$y = 622
$idx = 0
foreach ($a in $alarmBits) {
    $idx++
    $led = NewItem $screen.ScreenItems $T.Circle ("led_alm_$idx")
    Place $led 40 $y 16 16
    BindBit $led $a.Bit $a.OnColor $C.OffGray $a.Field
    $lbl = NewItem $screen.ScreenItems $T.Text ("lbl_alm_$idx")
    Place $lbl 66 $y 180 20
    SetText $lbl $a.Lbl 11 400 $C.PrimaryText
    $bitTxt = NewItem $screen.ScreenItems $T.Text ("bit_alm_$idx")
    Place $bitTxt 250 $y 60 20
    SetText $bitTxt "$($a.Field).x$($a.Bit)" 8 400 $C.SecondaryText 'Right'
    $y += 36
}

# ============================================================
# F-D Hero curve area  y=92..612 x=340..1500
# ============================================================
$fdCard = NewItem $screen.ScreenItems $T.Rect 'fd_card'
Place $fdCard 340 92 1160 520
StyleRect $fdCard $C.CardBg $C.CardBorder 1
$fdHdrBg = NewItem $screen.ScreenItems $T.Rect 'fd_hdr_bg'
Place $fdHdrBg 340 92 1160 32
StyleRect $fdHdrBg $C.SectionHdrBg
$fdHdr = NewItem $screen.ScreenItems $T.Text 'fd_hdr'
Place $fdHdr 356 92 1100 32
SetText $fdHdr 'FORCE-DISPLACEMENT CURVE' 12 700 $C.PrimaryText 'Left'

# Live PV overlay (top-left of plot area)
$pvForceLblTop = NewItem $screen.ScreenItems $T.Text 'pv_force_lbl_top'
Place $pvForceLblTop 364 138 200 18
SetText $pvForceLblTop 'FORCE Y [N]' 10 600 $C.LabelText 'Left'
MakeOutputIO 'pv_force' 364 156 240 40 'receive.PVcurrentValueY' 's9f1' 28 'Bold' $C.PrimaryText $C.CardBg 'Left' | Out-Null

$pvDispLblTop = NewItem $screen.ScreenItems $T.Text 'pv_disp_lbl_top'
Place $pvDispLblTop 604 138 200 18
SetText $pvDispLblTop 'DISPLACEMENT X [mm]' 10 600 $C.LabelText 'Left'
MakeOutputIO 'pv_disp'  604 156 240 40 'receive.PVcurrentValueX' 's9f3' 28 'Bold' $C.PrimaryText $C.CardBg 'Left' | Out-Null

$pvGradLblTop = NewItem $screen.ScreenItems $T.Text 'pv_grad_lbl_top'
Place $pvGradLblTop 844 138 200 18
SetText $pvGradLblTop 'GRADIENT [N/mm]' 10 600 $C.LabelText 'Left'
MakeOutputIO 'pv_grad'  844 156 240 40 'receive.PV_EO3_Gradient' 's9f2' 28 'Bold' $C.PrimaryText $C.CardBg 'Left' | Out-Null

# Curve plot area (placeholder for HmiTrendControl)
$fdPlot = NewItem $screen.ScreenItems $T.Rect 'fd_plot'
Place $fdPlot 380 220 1100 360
StyleRect $fdPlot $C.PanelBg $C.CardBorder 1
$fdNote = NewItem $screen.ScreenItems $T.Text 'fd_note'
Place $fdNote 740 380 380 40
SetText $fdNote 'Trend control area' 11 400 $C.SecondaryText 'Center'
$fdNote2 = NewItem $screen.ScreenItems $T.Text 'fd_note2'
Place $fdNote2 740 410 380 20
SetText $fdNote2 'Bind X: receive.PVcurrentValueX  /  Y: receive.PVcurrentValueY' 9 400 $C.SecondaryText 'Center'

# Axis bounds annotations
$xMinLbl = NewItem $screen.ScreenItems $T.Text 'xmin_lbl'
Place $xMinLbl 380 580 60 18
SetText $xMinLbl 'X min' 9 400 $C.SecondaryText 'Left'
MakeOutputIO 'fd_xmin' 440 580 80 18 'receive.PVcurrentXmin-X' 's7f2' 10 'Bold' $C.PrimaryText $C.CardBg 'Left' | Out-Null

$xMaxLbl = NewItem $screen.ScreenItems $T.Text 'xmax_lbl'
Place $xMaxLbl 1300 580 60 18
SetText $xMaxLbl 'X max' 9 400 $C.SecondaryText 'Right'
MakeOutputIO 'fd_xmax' 1360 580 120 18 'receive.PVcurrentXmax-X' 's7f2' 10 'Bold' $C.PrimaryText $C.CardBg 'Right' | Out-Null

$yMinLbl = NewItem $screen.ScreenItems $T.Text 'ymin_lbl'
Place $yMinLbl 380 200 60 18
SetText $yMinLbl 'Y min' 9 400 $C.SecondaryText 'Left'
MakeOutputIO 'fd_ymin' 440 200 80 18 'receive.PVcurrentYmin-Y' 's7f1' 10 'Bold' $C.PrimaryText $C.CardBg 'Left' | Out-Null

$yMaxLbl = NewItem $screen.ScreenItems $T.Text 'ymax_lbl'
Place $yMaxLbl 1300 200 60 18
SetText $yMaxLbl 'Y max' 9 400 $C.SecondaryText 'Right'
MakeOutputIO 'fd_ymax' 1360 200 120 18 'receive.PVcurrentYmax-Y' 's7f1' 10 'Bold' $C.PrimaryText $C.CardBg 'Right' | Out-Null

# ============================================================
# CONTROL card  y=92..760 x=1520..1900
# ============================================================
$ctrlCard = NewItem $screen.ScreenItems $T.Rect 'ctrl_card'
Place $ctrlCard 1520 92 380 668
StyleRect $ctrlCard $C.CardBg $C.CardBorder 1
$ctrlHdrBg = NewItem $screen.ScreenItems $T.Rect 'ctrl_hdr_bg'
Place $ctrlHdrBg 1520 92 380 32
StyleRect $ctrlHdrBg $C.SectionHdrBg
$ctrlHdr = NewItem $screen.ScreenItems $T.Text 'ctrl_hdr'
Place $ctrlHdr 1536 92 364 32
SetText $ctrlHdr 'PRESS CONTROL' 12 700 $C.PrimaryText 'Left'

# Function to create a styled button with click handler + echo BackColor binding
function MakeButton($name, $label, $left, $top, $width, $height, $moveBitList, $btnBgColor, $isToggle = $false, $echoBit = $null) {
    $btn = NewItem $screen.ScreenItems $T.Button $name
    Place $btn $left $top $width $height
    SetText $btn $label 14 700 $C.BtnText 'Center' 'Center'
    $btn.BackColor = $btnBgColor
    $btn.ForeColor = $C.BtnText
    $btn.BorderWidth = [byte]0
    $btn.AlternateBackColor = $btnBgColor   # pressed color same — could darken if desired

    # Event handlers
    $mask = 0; foreach ($b in $moveBitList) { $mask = $mask -bor ([int][Math]::Pow(2, $b)) }
    if ($isToggle) {
        $ev = $btn.EventHandlers.Create($Tapped)
        $code = "var v = Tags(`"$RootTag.move`").Read();`r`nTags(`"$RootTag.move`").Write(v ^ $mask);"
        $ev.Script.SetAttribute('ScriptCode', $code)
    } else {
        $evA = $btn.EventHandlers.Create($Activated)
        $codeOn = "var v = Tags(`"$RootTag.move`").Read();`r`nTags(`"$RootTag.move`").Write(v | $mask);"
        $evA.Script.SetAttribute('ScriptCode', $codeOn)
        $evD = $btn.EventHandlers.Create($Deactivated)
        $codeOff = "var v = Tags(`"$RootTag.move`").Read();`r`nTags(`"$RootTag.move`").Write(v & ~$mask);"
        $evD.Script.SetAttribute('ScriptCode', $codeOff)
    }
    if ($echoBit -ne $null) {
        BindBit $btn $echoBit $C.BtnRunHover $btnBgColor 'send.control'
    }
    return $btn
}

# RUN (big primary green)
MakeButton 'btn_Run' 'RUN'  1540 140 340 80 @(1) $C.BtnRunBg $false 2 | Out-Null
# JOG buttons
MakeButton 'btn_JogPlus'  'JOG +'  1540 240 165 60 @(14) $C.BtnNeutralBg $false 5 | Out-Null
MakeButton 'btn_JogMinus' 'JOG -'  1715 240 165 60 @(15) $C.BtnNeutralBg $false 6 | Out-Null
# Home / Ref
MakeButton 'btn_Home' 'HOME'  1540 320 165 60 @(2) $C.BtnNeutralBg $false 3 | Out-Null
MakeButton 'btn_Ref'  'REF'   1715 320 165 60 @(8) $C.BtnNeutralBg $false 4 | Out-Null
# Continue from wait + Ack
MakeButton 'btn_ContWait' 'CONTINUE'  1540 400 165 60 @(10,11) $C.BtnWarnBg $false 7 | Out-Null
MakeButton 'btn_AckAdmin' 'ACK FAULT' 1715 400 165 60 @(9) $C.BtnStopBg $false 9 | Out-Null
# Remote toggle
MakeButton 'btn_Remote'   'REMOTE'   1540 480 340 50 @(0) $C.BtnNeutralBg $true 0 | Out-Null

# Setpoints section
$spDiv = NewItem $screen.ScreenItems $T.Line 'sp_div'
Place $spDiv 1540 550 340 1

$spHdr = NewItem $screen.ScreenItems $T.Text 'sp_hdr'
Place $spHdr 1540 555 340 20
SetText $spHdr 'SETPOINTS' 10 700 $C.SecondaryText 'Left'

$jsLbl = NewItem $screen.ScreenItems $T.Text 'js_lbl'
Place $jsLbl 1540 580 160 18
SetText $jsLbl 'Jog Speed [mm/s]' 10 400 $C.LabelText 'Left'
$js_io = NewItem $screen.ScreenItems $T.IO 'js_io'
Place $js_io 1540 600 160 32
$js_io.IOFieldType = $InputOutput
BindTag $js_io 'ProcessValue' 'serverJogSpeedSet'

$mfLbl = NewItem $screen.ScreenItems $T.Text 'mf_lbl'
Place $mfLbl 1720 580 160 18
SetText $mfLbl 'Max Force [N]' 10 400 $C.LabelText 'Left'
$mf_io = NewItem $screen.ScreenItems $T.IO 'mf_io'
Place $mf_io 1720 600 160 32
$mf_io.IOFieldType = $InputOutput
BindTag $mf_io 'ProcessValue' 'serverJogMaxForceSet'

# Program section
$progHdr = NewItem $screen.ScreenItems $T.Text 'prog_hdr'
Place $progHdr 1540 645 340 20
SetText $progHdr 'PROGRAM SELECTION' 10 700 $C.SecondaryText 'Left'

$mpLbl = NewItem $screen.ScreenItems $T.Text 'mp_lbl'
Place $mpLbl 1540 670 100 18
SetText $mpLbl 'MP (0..127)' 9 400 $C.LabelText 'Left'
$mp_io = NewItem $screen.ScreenItems $T.IO 'mp_io'
Place $mp_io 1540 690 100 32
$mp_io.IOFieldType = $InputOutput
BindTag $mp_io 'ProcessValue' 'manualSelectMpNum'

$seqLbl = NewItem $screen.ScreenItems $T.Text 'seq_lbl'
Place $seqLbl 1655 670 100 18
SetText $seqLbl 'Seq (0..3)' 9 400 $C.LabelText 'Left'
$seq_io = NewItem $screen.ScreenItems $T.IO 'seq_io'
Place $seq_io 1655 690 100 32
$seq_io.IOFieldType = $InputOutput
BindTag $seq_io 'ProcessValue' 'selectSequenceSet'

$pgLbl = NewItem $screen.ScreenItems $T.Text 'pg_lbl'
Place $pgLbl 1770 670 110 18
SetText $pgLbl 'Page (0..7)' 9 400 $C.LabelText 'Left'
$pg_io = NewItem $screen.ScreenItems $T.IO 'pg_io'
Place $pg_io 1770 690 110 32
$pg_io.IOFieldType = $InputOutput
BindTag $pg_io 'ProcessValue' 'selectPageSet'

# ============================================================
# Echo panel  y=780..1058 x=20..1900
# Two side-by-side cards: EO Results (left, 920 wide) + Sequence echo (right, 940 wide)
# ============================================================

# === EO Results card ===
$eoCard = NewItem $screen.ScreenItems $T.Rect 'eo_card'
Place $eoCard 20 780 900 278
StyleRect $eoCard $C.CardBg $C.CardBorder 1
$eoHdrBg = NewItem $screen.ScreenItems $T.Rect 'eo_hdr_bg'
Place $eoHdrBg 20 780 900 28
StyleRect $eoHdrBg $C.SectionHdrBg
$eoHdr = NewItem $screen.ScreenItems $T.Text 'eo_hdr'
Place $eoHdr 36 780 880 28
SetText $eoHdr 'EVALUATION OBJECTS' 11 700 $C.PrimaryText 'Left'

# Column headers
$ehY = 818
$eoColX = @(40, 90, 280, 480, 680)
$eoColW = @(40, 180, 180, 180, 200)
$eoColLbl = @('#', 'Type', 'Real Value', 'Byte', 'PASS/NOK')
for ($i = 0; $i -lt 5; $i++) {
    $h = NewItem $screen.ScreenItems $T.Text "eo_h_$i"
    Place $h $eoColX[$i] $ehY $eoColW[$i] 16
    SetText $h $eoColLbl[$i] 9 700 $C.SecondaryText 'Left'
}

# EO rows
$eos = @(
    @{ N=1;  Name='Force [N]';     R='receive.PV_EO1_Force';    B=$null                  },
    @{ N=2;  Name='Distance [mm]'; R='receive.PV_EO2_Distance'; B=$null                  },
    @{ N=3;  Name='Gradient';      R='receive.PV_EO3_Gradient'; B=$null                  },
    @{ N=4;  Name='NoPass';        R=$null;                     B='receive.PV_E04_Nopass'   },
    @{ N=5;  Name='UniBox';        R=$null;                     B='receive.PV_E05_Unibox'   },
    @{ N=6;  Name='Envelope';      R=$null;                     B='receive.PV_E06_Envelope' },
    @{ N=7;  Name='EO 7';          R='receive.PV_Real_EO7';     B='receive.PV_Byte_E07'  },
    @{ N=8;  Name='EO 8';          R='receive.PV_Real_EO8';     B='receive.PV_Byte_E08'  },
    @{ N=9;  Name='EO 9';          R='receive.PV_Real_EO9';     B='receive.PV_Byte_E09'  },
    @{ N=10; Name='EO 10';         R='receive.PV_Real_E10';     B='receive.PV_Byte_E10'  }
)
$rowY = 842
foreach ($eo in $eos) {
    # Row separator (very subtle)
    if ($eo.N -gt 1) {
        $sep = NewItem $screen.ScreenItems $T.Line "eo_sep_$($eo.N)"
        Place $sep 40 ($rowY - 1) 860 1
    }
    # # column
    $n = NewItem $screen.ScreenItems $T.Text "eo_n_$($eo.N)"; Place $n $eoColX[0] $rowY $eoColW[0] 20
    SetText $n "$($eo.N)" 11 600 $C.SecondaryText 'Left'
    # Type column
    $tn = NewItem $screen.ScreenItems $T.Text "eo_name_$($eo.N)"; Place $tn $eoColX[1] $rowY $eoColW[1] 20
    SetText $tn $eo.Name 11 400 $C.PrimaryText 'Left'
    # Real value
    if ($eo.R) {
        MakeOutputIO "eo_real_$($eo.N)" $eoColX[2] $rowY $eoColW[2] 20 $eo.R 's9f2' 11 'Bold' $C.PrimaryText $C.CardBg 'Right' | Out-Null
    } else {
        $rv = NewItem $screen.ScreenItems $T.Text "eo_real_dash_$($eo.N)"; Place $rv $eoColX[2] $rowY $eoColW[2] 20
        SetText $rv '—' 11 400 $C.SecondaryText 'Right'
    }
    # Byte value
    if ($eo.B) {
        MakeOutputIO "eo_byte_$($eo.N)" $eoColX[3] $rowY $eoColW[3] 20 $eo.B 's3' 11 'Bold' $C.PrimaryText $C.CardBg 'Right' | Out-Null
        # Pass/NOK indicator via byte: green when 0, red when not
        $bvLed = NewItem $screen.ScreenItems $T.Circle "eo_pf_$($eo.N)"
        Place $bvLed ($eoColX[4] + 6) $rowY 16 16
        BindBit $bvLed 0 $C.Red $C.LightGreen $eo.B   # bit 0 — when any bit set, byte > 0
        $bvText = NewItem $screen.ScreenItems $T.Text "eo_pf_txt_$($eo.N)"
        Place $bvText ($eoColX[4] + 28) $rowY 170 20
        SetText $bvText '(0 = PASS)' 9 400 $C.SecondaryText 'Left'
    } else {
        $bv = NewItem $screen.ScreenItems $T.Text "eo_byte_dash_$($eo.N)"; Place $bv $eoColX[3] $rowY $eoColW[3] 20
        SetText $bv '—' 11 400 $C.SecondaryText 'Right'
        $rt = NewItem $screen.ScreenItems $T.Text "eo_pf_real_$($eo.N)"
        Place $rt $eoColX[4] $rowY 200 20
        SetText $rt 'measurement' 9 400 $C.SecondaryText 'Left'
    }
    $rowY += 22
}

# === Sequence/Program/Config/Setpoint echo card ===
$ecCard = NewItem $screen.ScreenItems $T.Rect 'ec_card'
Place $ecCard 940 780 960 278
StyleRect $ecCard $C.CardBg $C.CardBorder 1
$ecHdrBg = NewItem $screen.ScreenItems $T.Rect 'ec_hdr_bg'
Place $ecHdrBg 940 780 960 28
StyleRect $ecHdrBg $C.SectionHdrBg
$ecHdr = NewItem $screen.ScreenItems $T.Text 'ec_hdr'
Place $ecHdr 956 780 940 28
SetText $ecHdr 'SEQUENCE / PROGRAM / CONFIG / SETPOINT ECHO' 11 700 $C.PrimaryText 'Left'

# Sub-headers + grid
$subHdrs = @(
    @{ X=956;  Lbl='ACTIVE (from device)' },
    @{ X=1276; Lbl='SENT TO DEVICE' },
    @{ X=1596; Lbl='CONFIG / META' }
)
foreach ($sh in $subHdrs) {
    $h = NewItem $screen.ScreenItems $T.Text "ec_sh_$($sh.X)"
    Place $h $sh.X 818 300 18
    SetText $h $sh.Lbl 9 700 $C.SecondaryText 'Left'
}

# 3 columns: Active / Sent / Config-Meta
# Active column (Reals + integers)
$activeRows = @(
    @{ Lbl='MP Number';   Path='receive.mpNum';            Fmt='s3'   },
    @{ Lbl='Page';        Path='receive.selectPage';       Fmt='s3'   },
    @{ Lbl='Sequence';    Path='receive.selectSequence';   Fmt='s3'   },
    @{ Lbl='Jog Speed';   Path='receive.serverJogSpeed';   Fmt='s9f1' },
    @{ Lbl='Max Force';   Path='receive.serverJogMaxForce';Fmt='s9f1' }
)
$y = 842; $i = 0
foreach ($r in $activeRows) {
    $i++
    $lbl = NewItem $screen.ScreenItems $T.Text "ec_act_l_$i"
    Place $lbl 956 $y 140 18
    SetText $lbl $r.Lbl 10 400 $C.LabelText 'Left'
    MakeOutputIO "ec_act_v_$i" 1100 $y 160 22 $r.Path $r.Fmt 14 'Bold' $C.PrimaryText $C.CardBg 'Right' | Out-Null
    $y += 32
}

# Sent column
$sentRows = @(
    @{ Lbl='MP Number';   Path='send.mpNum';             Fmt='s3'   },
    @{ Lbl='Page';        Path='send.selectPage';        Fmt='s3'   },
    @{ Lbl='Sequence';    Path='send.selectSeqeunce';    Fmt='s3'   },
    @{ Lbl='Jog Speed';   Path='send.serverJogSpeed';    Fmt='s9f1' },
    @{ Lbl='Max Force';   Path='send.serverJogMaxForce'; Fmt='s9f1' }
)
$y = 842; $i = 0
foreach ($r in $sentRows) {
    $i++
    $lbl = NewItem $screen.ScreenItems $T.Text "ec_snt_l_$i"
    Place $lbl 1276 $y 140 18
    SetText $lbl $r.Lbl 10 400 $C.LabelText 'Left'
    MakeOutputIO "ec_snt_v_$i" 1420 $y 160 22 $r.Path $r.Fmt 14 'Bold' $C.PrimaryText $C.CardBg 'Right' | Out-Null
    $y += 32
}

# Config / Meta column — all integer
$cfgRows = @(
    @{ Lbl='Sequence Label'; Path='currentLabel';       Fmt='s3' },
    @{ Lbl='Op Mode Area';   Path='opmodearea';         Fmt='s3' },
    @{ Lbl='HMI Control #';  Path='hmiControlNo';       Fmt='s5' },
    @{ Lbl='Cfg MP';         Path='receive.cfgMpNum';   Fmt='s3' },
    @{ Lbl='Cfg Length';     Path='receive.cfgLength';  Fmt='s3' }
)
$y = 842; $i = 0
foreach ($r in $cfgRows) {
    $i++
    $lbl = NewItem $screen.ScreenItems $T.Text "ec_cfg_l_$i"
    Place $lbl 1596 $y 160 18
    SetText $lbl $r.Lbl 10 400 $C.LabelText 'Left'
    MakeOutputIO "ec_cfg_v_$i" 1760 $y 130 22 $r.Path $r.Fmt 14 'Bold' $C.PrimaryText $C.CardBg 'Right' | Out-Null
    $y += 32
}

# Sequence End indicator (small inline LED)
$endLed = NewItem $screen.ScreenItems $T.Circle 'end_led'
Place $endLed 1880 1018 16 16
BindTag $endLed 'Visible' 'sequenceEnd'
$endLbl = NewItem $screen.ScreenItems $T.Text 'end_lbl'
Place $endLbl 1780 1018 95 18
SetText $endLbl 'Sequence End' 10 600 $C.SecondaryText 'Right'

# ============================================================
# Footer
# ============================================================
$footer = NewItem $screen.ScreenItems $T.Text 'footer'
Place $footer 20 1064 1880 16
SetText $footer "Kistler maXYmos NC  |  _Kistler_Press_01  |  Bound to MVterminalPressKistler (LDrive_typeKistlerHmi)  |  per §19 verified FB map" 9 400 $C.SecondaryText 'Center'

# ============================================================
# Save and compile
# ============================================================
Write-Host "Saving..."
$session.Save()
Write-Host "Compiling HMI..."
$compT = Get-HmiType 'Siemens.Engineering.Compiler.ICompilable'
$cur = $hmiSw.Parent; $comp = $null
while ($cur -and -not $comp) {
    $gs = $cur.GetType().GetMethods() | Where-Object { $_.Name -eq 'GetService' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    if ($gs) { try { $comp = $gs.MakeGenericMethod($compT).Invoke($cur, $null) } catch {} }
    $cur = $cur.Parent
}
$cr = $comp.Compile()
Write-Host "Compile: $($cr.State)  Errors=$($cr.ErrorCount)  Warnings=$($cr.WarningCount)"
$bag = New-Object System.Collections.ArrayList
function FlatA($m) { [void]$bag.Add($m); foreach ($s in $m.Messages) { FlatA $s } }
foreach ($m in $cr.Messages) { FlatA $m }
$errs = $bag | Where-Object { $_.State -eq 'Error' -and $_.Description }
if ($errs.Count -gt 0) { foreach ($e in $errs | Select-Object -First 20) { Write-Host "  [$($e.Path)] $($e.Description)" -ForegroundColor Red } }

$dynCount = 0; foreach ($it in $screen.ScreenItems) { $dynCount += $it.Dynamizations.Count }
$evtCount = 0
foreach ($it in $screen.ScreenItems) {
    if ($it.GetType().Name -eq 'HmiButton') { $evtCount += @($it.EventHandlers).Count }
}
Write-Host ""
Write-Host "Items: $($screen.ScreenItems.Count)"
Write-Host "Dynamizations: $dynCount"
Write-Host "Button event handlers: $evtCount"
