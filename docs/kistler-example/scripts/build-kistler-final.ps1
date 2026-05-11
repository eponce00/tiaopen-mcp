# build-kistler-final.ps1
# Operator-friendly Kistler maXYmos NC HMI screen — clean rewrite.
# Critical fixes from prior attempt:
#   1. SetText uses plain <body><p>...</p></body> (NO inline CSS - TIA rejects it)
#   2. Font size/weight set via Font part attributes separately
#   3. No bit annotations (engineer noise)
#   4. Every label is descriptive operator language
#   5. All numerics use HmiIOField with IOFieldType=Output + OutputFormat
#   6. Editable setpoints/program use HmiIOField InputOutput
#   7. Plant identifier (string) uses HmiText
#   8. LED + button echo bits use HmiCircle/HmiButton with Singlebit mapping
#   9. Buttons have Activated/Deactivated press-hold scripts to .move bits

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
function Get-HmiType([string]$fn) { foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { try { $t = $a.GetType($fn, $false); if ($t) { return $t } } catch {} }; throw "no $fn" }
$TRect    = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiRectangle'
$TText    = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiText'
$TCircle  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiCircle'
$TLine    = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiLine'
$TIO      = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField'
$TButton  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton'
$TagDynT  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'
$CTT      = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.Tag.ConditionType'
$Singlebit= [Enum]::Parse($CTT, 'Singlebit')
$IOTypeT  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiIOFieldType'
$IOOutput = [Enum]::Parse($IOTypeT, 'Output')
$IOInputOutput = [Enum]::Parse($IOTypeT, 'InputOutput')
$BtnEvtT  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiButtonEventType'
$Activated   = [Enum]::Parse($BtnEvtT, 'Activated')
$Deactivated = [Enum]::Parse($BtnEvtT, 'Deactivated')
$Tapped      = [Enum]::Parse($BtnEvtT, 'Tapped')
$HAlignT  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiHorizontalAlignment'

# ---- Color palette (SICAR + modern industrial chrome) ----
$HeaderBg    = [System.Drawing.Color]::FromArgb(255,  44,  62,  80)
$Accent      = [System.Drawing.Color]::FromArgb(255,  52, 152, 219)
$HeaderText  = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$HeaderSub   = [System.Drawing.Color]::FromArgb(255, 189, 195, 199)
$CardBg      = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$CardBorder  = [System.Drawing.Color]::FromArgb(255, 208, 211, 214)
$PanelBg     = [System.Drawing.Color]::FromArgb(255, 245, 246, 250)
$SectionBg   = [System.Drawing.Color]::FromArgb(255, 236, 240, 241)
$PrimaryText = [System.Drawing.Color]::FromArgb(255,  44,  62,  80)
$LabelText   = [System.Drawing.Color]::FromArgb(255, 100, 113, 114)
$SecondaryT  = [System.Drawing.Color]::FromArgb(255, 127, 140, 141)
$SicGreen    = [System.Drawing.Color]::FromArgb(255, 146, 208,  80)
$SicLBlue    = [System.Drawing.Color]::FromArgb(255,   0, 176, 240)
$SicOrange   = [System.Drawing.Color]::FromArgb(255, 255, 192,   0)
$SicRed      = [System.Drawing.Color]::FromArgb(255, 230,  57,  53)
$SicYellow   = [System.Drawing.Color]::FromArgb(255, 255, 235,  59)
$OffGray     = [System.Drawing.Color]::FromArgb(255, 215, 219, 221)
$BtnRunBg    = [System.Drawing.Color]::FromArgb(255,  39, 174,  96)
$BtnStopBg   = [System.Drawing.Color]::FromArgb(255, 231,  76,  60)
$BtnNeutralBg= [System.Drawing.Color]::FromArgb(255,  52,  73,  94)
$BtnWarnBg   = [System.Drawing.Color]::FromArgb(255, 243, 156,  18)
$BtnText     = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)

# ---- Helper: generic Create<T>(name) ----
function NewItem($comp, $type, $name) {
    if (-not $comp) { throw "NewItem: composition is null" }
    $cg = $comp.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    return $cg.MakeGenericMethod($type).Invoke($comp, @($name))
}

# ---- Set text (canonical: plain <body><p>...</p></body>, NO inline CSS) ----
# Font size/weight set separately via Font part.
function SetItemText($it, [string]$plain, [int]$fontSize = 0, [string]$fontWeight = $null, $foreColor = $null, [string]$halign = $null) {
    $textProp = $it.GetType().GetProperty('Text')
    if ($textProp) {
        $mlt = $textProp.GetValue($it)
        if ($mlt) {
            $xml = "<body><p>$plain</p></body>"
            foreach ($mi in $mlt.Items) {
                try { $mi.SetAttribute('Text', $xml) } catch {}
            }
        }
    }
    if ($fontSize -gt 0 -or $fontWeight) {
        $fp = $it.GetType().GetProperty('Font')
        if ($fp) {
            $f = $fp.GetValue($it)
            if ($f) {
                if ($fontSize -gt 0) { try { $f.SetAttribute('Size', [byte]$fontSize) } catch {} }
                if ($fontWeight)     { try { $f.SetAttribute('Weight', $fontWeight) } catch {} }
            }
        }
    }
    if ($foreColor) {
        $fcp = $it.GetType().GetProperty('ForeColor')
        if ($fcp -and $fcp.CanWrite) { $fcp.SetValue($it, $foreColor) }
    }
    if ($halign) {
        $hap = $it.GetType().GetProperty('HorizontalTextAlignment')
        if ($hap -and $hap.CanWrite) {
            try { $hap.SetValue($it, [Enum]::Parse($HAlignT, $halign)) } catch {}
        }
    }
}

# ---- Place item ----
function Place($it, [int]$L, [int]$T, [int]$W, [int]$H) {
    $tt = $it.GetType()
    if ($tt.GetProperty('Left')) {
        $it.Left = $L; $it.Top = $T; $it.Width = [uint32]$W; $it.Height = [uint32]$H
    } elseif ($tt.GetProperty('CenterX')) {
        $it.CenterX = $L + [int]($W/2); $it.CenterY = $T + [int]($H/2)
        $it.Radius = [uint32]([int]([Math]::Min($W,$H)/2))
    } elseif ($tt.GetProperty('Point1')) {
        $p1 = $it.Point1; $p2 = $it.Point2
        $p1.X = $L; $p1.Y = $T + [int]($H/2); $p2.X = $L + $W; $p2.Y = $T + [int]($H/2)
    }
}

# ---- Style rectangle ----
function StyleRect {
    param(
        [Parameter(Mandatory=$true, Position=0)] $rect,
        [Parameter(Mandatory=$true, Position=1)] [System.Drawing.Color] $background,
        [Parameter(Mandatory=$false, Position=2)] [System.Drawing.Color] $border,
        [Parameter(Mandatory=$false, Position=3)] [int] $borderWidth = 1
    )
    $rect.BackColor = $background
    if ($border) { $rect.BorderColor = $border; $rect.BorderWidth = [byte]$borderWidth }
    else         { $rect.BorderWidth = [byte]0 }
}

# ---- Bind a tag dynamization ----
function BindTag($it, [string]$prop, [string]$path) {
    $cg = $it.Dynamizations.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    $dyn = $cg.MakeGenericMethod($TagDynT).Invoke($it.Dynamizations, @($prop))
    $dyn.SetAttribute('Tag', "$RootTag.$path")
}
function BindTagAndGet($it, [string]$prop, [string]$path) {
    $cg = $it.Dynamizations.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    $dyn = $cg.MakeGenericMethod($TagDynT).Invoke($it.Dynamizations, @($prop))
    $dyn.SetAttribute('Tag', "$RootTag.$path")
    return $dyn
}

# ---- Bit extraction (Singlebit) for HmiCircle BackColor ----
function BindBitColor($it, [int]$bit, $onColor, $offColor, [string]$fieldPath) {
    $dyn = BindTagAndGet $it 'BackColor' $fieldPath
    $mt = $dyn.ValueConverter.MappingTable
    foreach ($e in @($mt.Entries)) { try { $e.Delete() } catch {} }
    $mt.SetAttribute('ConditionType', $Singlebit)
    $entries = @($mt.Entries)
    if ($entries.Count -ne 2) { throw "expected 2 entries, got $($entries.Count) on $($it.Name)" }
    $entries[1].Condition = [UInt64]([Math]::Pow(2, $bit))
    $entries[0].Value = $offColor
    $entries[1].Value = $onColor
}

# ---- Create read-only numeric display (HmiIOField Output) ----
function MakeOutputField([string]$name, [int]$L, [int]$T, [int]$W, [int]$H, [string]$path, [string]$fmt, [int]$fontSize, [string]$halign, $foreColor, $bgColor) {
    $io = NewItem $screen.ScreenItems $TIO $name
    Place $io $L $T $W $H
    $io.IOFieldType = $IOOutput
    $io.BackColor = $bgColor
    $io.ForeColor = $foreColor
    $io.BorderWidth = [byte]0
    if ($fmt) { $io.OutputFormat = $fmt }
    if ($halign) {
        try { $io.HorizontalTextAlignment = [Enum]::Parse($HAlignT, $halign) } catch {}
    }
    if ($fontSize -gt 0) {
        try {
            $f = $io.Font
            if ($f) { $f.SetAttribute('Size', [byte]$fontSize) }
        } catch {}
    }
    BindTag $io 'ProcessValue' $path
}

# ---- Create editable numeric input (HmiIOField InputOutput) ----
function MakeInputField([string]$name, [int]$L, [int]$T, [int]$W, [int]$H, [string]$path, [string]$fmt, [int]$fontSize) {
    $io = NewItem $screen.ScreenItems $TIO $name
    Place $io $L $T $W $H
    $io.IOFieldType = $IOInputOutput
    if ($fmt) { $io.OutputFormat = $fmt }
    try {
        $f = $io.Font
        if ($f -and $fontSize -gt 0) { $f.SetAttribute('Size', [byte]$fontSize) }
    } catch {}
    BindTag $io 'ProcessValue' $path
}

# ---- Make button with click handler + echo color ----
function MakeButton([string]$name, [string]$label, [int]$L, [int]$T, [int]$W, [int]$H, [int[]]$moveBits, $bgColor, $hoverColor, [bool]$isToggle, [int]$echoBit) {
    $btn = NewItem $screen.ScreenItems $TButton $name
    Place $btn $L $T $W $H
    SetItemText $btn $label 14 'Bold' $BtnText 'Center'
    $btn.BackColor = $bgColor
    $btn.ForeColor = $BtnText
    $btn.BorderWidth = [byte]0
    if ($hoverColor) { $btn.AlternateBackColor = $hoverColor }
    $mask = 0; foreach ($b in $moveBits) { $mask = $mask -bor ([int][Math]::Pow(2, $b)) }
    if ($isToggle) {
        $ev = $btn.EventHandlers.Create($Tapped)
        $ev.Script.SetAttribute('ScriptCode', "var v = Tags(`"$RootTag.move`").Read();`r`nTags(`"$RootTag.move`").Write(v ^ $mask);")
    } else {
        $evA = $btn.EventHandlers.Create($Activated)
        $evA.Script.SetAttribute('ScriptCode', "var v = Tags(`"$RootTag.move`").Read();`r`nTags(`"$RootTag.move`").Write(v | $mask);")
        $evD = $btn.EventHandlers.Create($Deactivated)
        $evD.Script.SetAttribute('ScriptCode', "var v = Tags(`"$RootTag.move`").Read();`r`nTags(`"$RootTag.move`").Write(v & ~$mask);")
    }
    if ($echoBit -ge 0) {
        BindBitColor $btn $echoBit $hoverColor $bgColor 'send.control'
    }
}

# ============================================================
# DROP + CREATE SCREEN
# ============================================================
$existing = $hmiSw.Screens.Find($ScreenName); if ($existing) { try { $existing.Delete() } catch {} }
$screen = $hmiSw.Screens.Create($ScreenName)
$screen.Width = [uint32]1920; $screen.Height = [uint32]1080
$screen.BackColor = $PanelBg
Write-Host "Created fresh screen: $ScreenName"

# ============================================================
# HEADER ribbon y=0..72
# ============================================================
$hdrBg = NewItem $screen.ScreenItems $TRect 'hdr_bg'
Place $hdrBg 0 0 1920 72; StyleRect $hdrBg $HeaderBg
$accentRect = NewItem $screen.ScreenItems $TRect 'hdr_accent'
Place $accentRect 0 0 6 72
StyleRect $accentRect $Accent

$hdrTitle = NewItem $screen.ScreenItems $TText 'hdr_title'
Place $hdrTitle 28 12 340 28
SetItemText $hdrTitle 'KISTLER maXYmos NC' 16 'Bold' $HeaderText 'Left'

$hdrSub = NewItem $screen.ScreenItems $TText 'hdr_subtitle'
Place $hdrSub 28 42 340 20
SetItemText $hdrSub 'Press Monitor and Controller' 10 'Regular' $HeaderSub 'Left'

# Plant identifier section (centered)
$plantLabel = NewItem $screen.ScreenItems $TText 'plant_label'
Place $plantLabel 600 10 720 16
SetItemText $plantLabel 'PLANT' 9 'Bold' $HeaderSub 'Center'

$plantValue = NewItem $screen.ScreenItems $TText 'plant_value'
Place $plantValue 600 28 720 36
SetItemText $plantValue '...' 18 'Bold' $HeaderText 'Center'
BindTag $plantValue 'Text' 'plantidentifier'

# State badge (right of plant)
$stateBadge = NewItem $screen.ScreenItems $TRect 'state_badge'
Place $stateBadge 1480 16 220 40; StyleRect $stateBadge $OffGray
BindTag $stateBadge 'BackColor' 'stateColour'
$stateText = NewItem $screen.ScreenItems $TText 'state_text'
Place $stateText 1480 18 220 36
SetItemText $stateText 'OPERATING STATE' 11 'Bold' $PrimaryText 'Center'

# Unit number (far right)
$unitBox = NewItem $screen.ScreenItems $TRect 'unit_box'
Place $unitBox 1720 16 180 40; StyleRect $unitBox $BtnNeutralBg
$unitLabel = NewItem $screen.ScreenItems $TText 'unit_label'
Place $unitLabel 1726 18 50 36
SetItemText $unitLabel 'UNIT' 9 'Bold' $HeaderSub 'Left'
MakeOutputField 'unit_value' 1786 16 110 40 'tecUnitNumber' 's3' 22 'Right' $HeaderText $BtnNeutralBg

# ============================================================
# STATUS card y=92..560 x=20..320
# ============================================================
$statusCard = NewItem $screen.ScreenItems $TRect 'status_card'
Place $statusCard 20 92 300 468; StyleRect $statusCard $CardBg $CardBorder 1
$statusHdrBg = NewItem $screen.ScreenItems $TRect 'status_hdr_bg'
Place $statusHdrBg 20 92 300 32; StyleRect $statusHdrBg $SectionBg
$statusHdr = NewItem $screen.ScreenItems $TText 'status_header'
Place $statusHdr 36 96 280 28
SetItemText $statusHdr 'PRESS STATUS' 12 'Bold' $PrimaryText 'Left'

# Each row: LED + descriptive label. NO bit annotations.
$statusBits = @(
    @{ Name='led_ready';        Label='Ready';            Field='receive.status'; Bit=2;  On=$SicGreen },
    @{ Name='led_drive_en';     Label='Drive Enabled';    Field='receive.status'; Bit=1;  On=$SicGreen },
    @{ Name='led_auto';         Label='Automatic Mode';   Field='receive.status'; Bit=0;  On=$SicGreen },
    @{ Name='led_standstill';   Label='At Standstill';    Field='receive.status'; Bit=6;  On=$SicLBlue  },
    @{ Name='led_at_home';      Label='At Home Position'; Field='receive.status'; Bit=5;  On=$SicGreen },
    @{ Name='led_at_ref';       Label='At Reference';     Field='receive.status'; Bit=4;  On=$SicGreen },
    @{ Name='led_wait_req';     Label='Waiting (Continue)';Field='receive.status'; Bit=3; On=$SicOrange },
    @{ Name='led_seq_end';      Label='Sequence Complete';Field='receive.status'; Bit=12; On=$SicGreen },
    @{ Name='led_ok_total';     Label='Result OK';        Field='receive.status'; Bit=8;  On=$SicGreen },
    @{ Name='led_nok_total';    Label='Result NOK';       Field='receive.status'; Bit=9;  On=$SicRed    },
    @{ Name='led_smes';         Label='Safe Mode Active'; Field='receive.status'; Bit=13; On=$SicYellow },
    @{ Name='led_safety_ok';    Label='Safety OK';        Field='state';          Bit=2;  On=$SicGreen }
)
$y = 134
foreach ($s in $statusBits) {
    $led = NewItem $screen.ScreenItems $TCircle $s.Name
    Place $led 40 $y 18 18
    BindBitColor $led $s.Bit $s.On $OffGray $s.Field
    $lbl = NewItem $screen.ScreenItems $TText "$($s.Name)_label"
    Place $lbl 68 $y 240 22
    SetItemText $lbl $s.Label 11 'Regular' $PrimaryText 'Left'
    $y += 34
}

# ============================================================
# ALARM card y=580..1058 x=20..320 (extended to fill left rail to bottom)
# ============================================================
$alarmCard = NewItem $screen.ScreenItems $TRect 'alarm_card'
Place $alarmCard 20 580 300 478; StyleRect $alarmCard $CardBg $CardBorder 1
$alarmHdrBg = NewItem $screen.ScreenItems $TRect 'alarm_hdr_bg'
Place $alarmHdrBg 20 580 300 32; StyleRect $alarmHdrBg $SectionBg
$alarmHdr = NewItem $screen.ScreenItems $TText 'alarm_header'
Place $alarmHdr 36 584 280 28
SetItemText $alarmHdr 'ACTIVE ALARMS' 12 'Bold' $SicRed 'Left'

$alarmBits = @(
    @{ Name='alm_hw';        Label='Hardware Fault';        Field='alarm'; Bit=1;  On=$SicRed    },
    @{ Name='alm_tx';        Label='Fieldbus TX Fault';     Field='alarm'; Bit=2;  On=$SicRed    },
    @{ Name='alm_drive_nok'; Label='Drive Not Enabled';     Field='alarm'; Bit=3;  On=$SicRed    },
    @{ Name='alm_safety';    Label='Safety Circuit Open';   Field='alarm'; Bit=13; On=$SicRed    },
    @{ Name='alm_cycle_to';  Label='Cycle Timeout';         Field='alarm'; Bit=6;  On=$SicRed    },
    @{ Name='alm_wait_miss'; Label='Continue Command Missing';Field='alarm'; Bit=9; On=$SicOrange },
    @{ Name='alm_remote';    Label='Remote Control Inactive';Field='alarm'; Bit=16; On=$SicOrange },
    @{ Name='alm_serial';    Label='Serial Number Mismatch';Field='alarm'; Bit=17; On=$SicRed    }
)
$y = 622
foreach ($a in $alarmBits) {
    $led = NewItem $screen.ScreenItems $TCircle $a.Name
    Place $led 40 $y 18 18
    BindBitColor $led $a.Bit $a.On $OffGray $a.Field
    $lbl = NewItem $screen.ScreenItems $TText "$($a.Name)_label"
    Place $lbl 68 $y 240 22
    SetItemText $lbl $a.Label 11 'Regular' $PrimaryText 'Left'
    $y += 38
}

# ============================================================
# F-D Hero curve area y=92..612 x=340..1500
# ============================================================
$fdCard = NewItem $screen.ScreenItems $TRect 'fd_card'
Place $fdCard 340 92 1160 520; StyleRect $fdCard $CardBg $CardBorder 1
$fdHdrBg = NewItem $screen.ScreenItems $TRect 'fd_hdr_bg'
Place $fdHdrBg 340 92 1160 32; StyleRect $fdHdrBg $SectionBg
$fdHdr = NewItem $screen.ScreenItems $TText 'fd_header'
Place $fdHdr 356 96 1100 28
SetItemText $fdHdr 'FORCE-DISPLACEMENT CURVE' 12 'Bold' $PrimaryText 'Left'

# Live PV overlay top of card — three big cards side by side
$pvLabels = @(
    @{ Label='Force Y';        Unit='[N]';    Path='receive.PVcurrentValueY'; Fmt='s9f1'; Name='pv_force'; X=360 },
    @{ Label='Displacement X'; Unit='[mm]';   Path='receive.PVcurrentValueX'; Fmt='s9f3'; Name='pv_disp';  X=720 },
    @{ Label='Gradient';       Unit='[N/mm]'; Path='receive.PV_EO3_Gradient'; Fmt='s9f2'; Name='pv_grad';  X=1080 }
)
foreach ($pv in $pvLabels) {
    $lbl1 = NewItem $screen.ScreenItems $TText "$($pv.Name)_lbl1"
    Place $lbl1 $pv.X 134 105 18
    SetItemText $lbl1 $pv.Label 10 'Bold' $LabelText 'Left'
    $lbl2 = NewItem $screen.ScreenItems $TText "$($pv.Name)_unit"
    Place $lbl2 ($pv.X+110) 134 100 18
    SetItemText $lbl2 $pv.Unit 10 'Regular' $SecondaryT 'Left'
    MakeOutputField $pv.Name $pv.X 154 320 44 $pv.Path $pv.Fmt 28 'Left' $PrimaryText $CardBg
}

# Trend control placeholder
$fdPlot = NewItem $screen.ScreenItems $TRect 'fd_plot'
Place $fdPlot 380 220 1100 360; StyleRect $fdPlot $PanelBg $CardBorder 1
$fdNote1 = NewItem $screen.ScreenItems $TText 'fd_plot_note'
Place $fdNote1 380 380 1100 24
SetItemText $fdNote1 'Force / Displacement Trend (add HmiTrendControl here in TIA editor)' 11 'Regular' $SecondaryT 'Center'

# Axis bound annotations (small, at corners)
$xMinL = NewItem $screen.ScreenItems $TText 'xmin_lbl'; Place $xMinL 380 590 90 18
SetItemText $xMinL 'X min [mm]' 9 'Regular' $SecondaryT 'Left'
MakeOutputField 'xmin_val' 470 590 80 18 'receive.PVcurrentXmin-X' 's7f2' 10 'Left' $PrimaryText $CardBg

$xMaxL = NewItem $screen.ScreenItems $TText 'xmax_lbl'; Place $xMaxL 1310 590 80 18
SetItemText $xMaxL 'X max [mm]' 9 'Regular' $SecondaryT 'Right'
MakeOutputField 'xmax_val' 1392 590 88 18 'receive.PVcurrentXmax-X' 's7f2' 10 'Right' $PrimaryText $CardBg

$yMinL = NewItem $screen.ScreenItems $TText 'ymin_lbl'; Place $yMinL 380 200 90 18
SetItemText $yMinL 'Y min [N]' 9 'Regular' $SecondaryT 'Left'
MakeOutputField 'ymin_val' 470 200 80 18 'receive.PVcurrentYmin-Y' 's7f1' 10 'Left' $PrimaryText $CardBg

$yMaxL = NewItem $screen.ScreenItems $TText 'ymax_lbl'; Place $yMaxL 1310 200 80 18
SetItemText $yMaxL 'Y max [N]' 9 'Regular' $SecondaryT 'Right'
MakeOutputField 'ymax_val' 1392 200 88 18 'receive.PVcurrentYmax-Y' 's7f1' 10 'Right' $PrimaryText $CardBg

# ============================================================
# PRESS CONTROL card y=92..760 x=1520..1900
# ============================================================
$ctrlCard = NewItem $screen.ScreenItems $TRect 'ctrl_card'
Place $ctrlCard 1520 92 380 668; StyleRect $ctrlCard $CardBg $CardBorder 1
$ctrlHdrBg = NewItem $screen.ScreenItems $TRect 'ctrl_hdr_bg'
Place $ctrlHdrBg 1520 92 380 32; StyleRect $ctrlHdrBg $SectionBg
$ctrlHdr = NewItem $screen.ScreenItems $TText 'ctrl_header'
Place $ctrlHdr 1536 96 364 28
SetItemText $ctrlHdr 'PRESS CONTROL' 12 'Bold' $PrimaryText 'Left'

# Big primary RUN button
MakeButton 'btn_run' 'START SEQUENCE' 1540 140 340 80 @(1) $BtnRunBg $SicGreen $false 2

# Movement row
MakeButton 'btn_home'     'HOME'      1540 240 165 60 @(2)  $BtnNeutralBg $SicLBlue $false 3
MakeButton 'btn_ref'      'REFERENCE' 1715 240 165 60 @(8)  $BtnNeutralBg $SicLBlue $false 4

# Jog row
MakeButton 'btn_jog_plus'  'JOG +'    1540 312 165 60 @(14) $BtnNeutralBg $SicGreen $false 5
MakeButton 'btn_jog_minus' 'JOG -'    1715 312 165 60 @(15) $BtnNeutralBg $SicGreen $false 6

# Action row
MakeButton 'btn_continue'  'CONTINUE' 1540 384 165 60 @(10,11) $BtnWarnBg $SicOrange $false 7
MakeButton 'btn_ack_fault' 'ACK FAULT' 1715 384 165 60 @(9)    $BtnStopBg $SicRed    $false 9

# Remote toggle (full width)
MakeButton 'btn_remote' 'REMOTE CONTROL TOGGLE' 1540 456 340 50 @(0) $BtnNeutralBg $SicLBlue $true 0

# Setpoints section
$spDiv = NewItem $screen.ScreenItems $TRect 'sp_divider'
Place $spDiv 1540 526 340 1
$spDiv.BackColor = $CardBorder; $spDiv.BorderWidth = [byte]0

$spHdr = NewItem $screen.ScreenItems $TText 'sp_header'
Place $spHdr 1540 532 340 18
SetItemText $spHdr 'SETPOINTS' 10 'Bold' $SecondaryT 'Left'

$jogL = NewItem $screen.ScreenItems $TText 'jog_speed_label'
Place $jogL 1540 555 160 18
SetItemText $jogL 'Jog Speed [mm/s]' 10 'Regular' $LabelText 'Left'
MakeInputField 'jog_speed_input' 1540 575 160 32 'serverJogSpeedSet' 's9f1' 13

$mfL = NewItem $screen.ScreenItems $TText 'max_force_label'
Place $mfL 1720 555 160 18
SetItemText $mfL 'Max Force [N]' 10 'Regular' $LabelText 'Left'
MakeInputField 'max_force_input' 1720 575 160 32 'serverJogMaxForceSet' 's9f1' 13

# Program section
$progHdr = NewItem $screen.ScreenItems $TText 'program_header'
Place $progHdr 1540 620 340 18
SetItemText $progHdr 'PROGRAM SELECTION' 10 'Bold' $SecondaryT 'Left'

$mpL = NewItem $screen.ScreenItems $TText 'mp_label'
Place $mpL 1540 642 100 16
SetItemText $mpL 'MP (0-127)' 9 'Regular' $LabelText 'Left'
MakeInputField 'mp_input' 1540 660 100 36 'manualSelectMpNum' 's3' 14

$sqL = NewItem $screen.ScreenItems $TText 'seq_label'
Place $sqL 1655 642 100 16
SetItemText $sqL 'Sequence (0-3)' 9 'Regular' $LabelText 'Left'
MakeInputField 'seq_input' 1655 660 100 36 'selectSequenceSet' 's3' 14

$pgL = NewItem $screen.ScreenItems $TText 'page_label'
Place $pgL 1770 642 110 16
SetItemText $pgL 'Page (0-7)' 9 'Regular' $LabelText 'Left'
MakeInputField 'page_input' 1770 660 110 36 'selectPageSet' 's3' 14

# Operator hint
$opHint = NewItem $screen.ScreenItems $TText 'op_hint'
Place $opHint 1540 712 340 36
SetItemText $opHint 'Hold buttons to assert commands.' 9 'Regular' $SecondaryT 'Left'

# ============================================================
# EO Results card y=780..1058 x=340..1140 (NOT x=20 — must clear left rail's Alarm panel)
# ============================================================
$eoCard = NewItem $screen.ScreenItems $TRect 'eo_card'
Place $eoCard 340 632 800 426; StyleRect $eoCard $CardBg $CardBorder 1
$eoHdrBg = NewItem $screen.ScreenItems $TRect 'eo_hdr_bg'
Place $eoHdrBg 340 632 800 28; StyleRect $eoHdrBg $SectionBg
$eoHdr = NewItem $screen.ScreenItems $TText 'eo_header'
Place $eoHdr 356 635 770 22
SetItemText $eoHdr 'EVALUATION OBJECT RESULTS' 11 'Bold' $PrimaryText 'Left'

# Column headers — repositioned for x=340..1140 card
$colDefs = @(
    @{ Label='No.';        X=356;   W=30  },
    @{ Label='Measurement';X=400;   W=180 },
    @{ Label='Value';      X=590;  W=170 },
    @{ Label='Code';       X=770;  W=70  },
    @{ Label='Pass / Fail';X=860;  W=270 }
)
foreach ($c in $colDefs) {
    $h = NewItem $screen.ScreenItems $TText "eoh_$($c.Label -replace '\W','')"
    Place $h $c.X 664 $c.W 18
    SetItemText $h $c.Label 9 'Bold' $SecondaryT 'Left'
}

# EO row definitions (operator-friendly)
$eoRows = @(
    @{ N=1;  Name='Force (EO1)';      Real='receive.PV_EO1_Force';    Byte=$null                       },
    @{ N=2;  Name='Distance (EO2)';   Real='receive.PV_EO2_Distance'; Byte=$null                       },
    @{ N=3;  Name='Gradient (EO3)';   Real='receive.PV_EO3_Gradient'; Byte=$null                       },
    @{ N=4;  Name='No-Pass (EO4)';    Real=$null;                     Byte='receive.PV_E04_Nopass'     },
    @{ N=5;  Name='Uni-Box (EO5)';    Real=$null;                     Byte='receive.PV_E05_Unibox'     },
    @{ N=6;  Name='Envelope (EO6)';   Real=$null;                     Byte='receive.PV_E06_Envelope'   },
    @{ N=7;  Name='Custom EO7';       Real='receive.PV_Real_EO7';     Byte='receive.PV_Byte_E07'       },
    @{ N=8;  Name='Custom EO8';       Real='receive.PV_Real_EO8';     Byte='receive.PV_Byte_E08'       },
    @{ N=9;  Name='Custom EO9';       Real='receive.PV_Real_EO9';     Byte='receive.PV_Byte_E09'       },
    @{ N=10; Name='Custom EO10';      Real='receive.PV_Real_E10';     Byte='receive.PV_Byte_E10'       }
)
$rowY = 690
foreach ($eo in $eoRows) {
    if ($eo.N -gt 1) {
        # Use thin Rectangle as separator (HmiLine renders unreliably with Point1/Point2 defaults)
        $sep = NewItem $screen.ScreenItems $TRect "eo_sep_$($eo.N)"
        Place $sep 350 ($rowY - 1) 780 1
        $sep.BackColor = $CardBorder
        $sep.BorderWidth = [byte]0
    }
    $numTxt = NewItem $screen.ScreenItems $TText "eo$($eo.N)_num"
    Place $numTxt 356 $rowY 30 20
    SetItemText $numTxt "$($eo.N)" 11 'Bold' $SecondaryT 'Left'

    $nameTxt = NewItem $screen.ScreenItems $TText "eo$($eo.N)_name"
    Place $nameTxt 400 $rowY 180 20
    SetItemText $nameTxt $eo.Name 11 'Regular' $PrimaryText 'Left'

    if ($eo.Real) {
        MakeOutputField "eo$($eo.N)_real" 590 $rowY 170 20 $eo.Real 's9f3' 11 'Right' $PrimaryText $CardBg
    } else {
        $dash = NewItem $screen.ScreenItems $TText "eo$($eo.N)_real_dash"
        Place $dash 590 $rowY 170 20
        SetItemText $dash 'n/a' 11 'Regular' $SecondaryT 'Right'
    }

    if ($eo.Byte) {
        MakeOutputField "eo$($eo.N)_byte" 770 $rowY 70 20 $eo.Byte 's3' 11 'Right' $PrimaryText $CardBg
        $ledPF = NewItem $screen.ScreenItems $TCircle "eo$($eo.N)_pf_led"
        Place $ledPF 860 $rowY 16 16
        BindBitColor $ledPF 0 $SicRed $SicGreen $eo.Byte
        $pfText = NewItem $screen.ScreenItems $TText "eo$($eo.N)_pf_text"
        Place $pfText 884 $rowY 246 20
        SetItemText $pfText 'PASS when value = 0' 9 'Regular' $SecondaryT 'Left'
    } else {
        $dash = NewItem $screen.ScreenItems $TText "eo$($eo.N)_byte_dash"
        Place $dash 770 $rowY 70 20
        SetItemText $dash 'n/a' 11 'Regular' $SecondaryT 'Right'
        $note = NewItem $screen.ScreenItems $TText "eo$($eo.N)_note"
        Place $note 860 $rowY 270 20
        SetItemText $note 'Measurement only' 9 'Regular' $SecondaryT 'Left'
    }
    $rowY += 32
}

# ============================================================
# Echo card y=780..1058 x=1160..1900 (right of EO card)
# ============================================================
$ecCard = NewItem $screen.ScreenItems $TRect 'echo_card'
Place $ecCard 1160 780 740 278; StyleRect $ecCard $CardBg $CardBorder 1
$ecHdrBg = NewItem $screen.ScreenItems $TRect 'echo_hdr_bg'
Place $ecHdrBg 1160 780 740 28; StyleRect $ecHdrBg $SectionBg
$ecHdr = NewItem $screen.ScreenItems $TText 'echo_header'
Place $ecHdr 1176 783 500 22
SetItemText $ecHdr 'PROGRAM ECHO  /  SEQUENCE INFO' 11 'Bold' $PrimaryText 'Left'

# 2 column sub-headers (compressed from 3 to 2 since we have less width)
$subHdrs = @(
    @{ X=1176; Label='CURRENT' },
    @{ X=1546; Label='SENT' }
)
foreach ($h in $subHdrs) {
    $t = NewItem $screen.ScreenItems $TText "echo_subh_$($h.X)"
    Place $t $h.X 812 300 16
    SetItemText $t $h.Label 9 'Bold' $SecondaryT 'Left'
}

# Active (from device) — receive struct
$activeRows = @(
    @{ Label='MP Number';   Path='receive.mpNum';            Fmt='s3'   },
    @{ Label='Page';        Path='receive.selectPage';       Fmt='s3'   },
    @{ Label='Sequence';    Path='receive.selectSequence';   Fmt='s3'   },
    @{ Label='Jog Speed';   Path='receive.serverJogSpeed';   Fmt='s9f1' },
    @{ Label='Max Force';   Path='receive.serverJogMaxForce';Fmt='s9f1' }
)
$y = 834; $i = 0
foreach ($r in $activeRows) {
    $i++
    $l = NewItem $screen.ScreenItems $TText "echo_act_lbl_$i"
    Place $l 1176 $y 110 18
    SetItemText $l $r.Label 10 'Regular' $LabelText 'Left'
    MakeOutputField "echo_act_val_$i" 1300 $y 130 22 $r.Path $r.Fmt 13 'Right' $PrimaryText $CardBg
    $y += 30
}

# Sent (echo of what HMI told FB) — send struct
$sentRows = @(
    @{ Label='MP Number';   Path='send.mpNum';             Fmt='s3'   },
    @{ Label='Page';        Path='send.selectPage';        Fmt='s3'   },
    @{ Label='Sequence';    Path='send.selectSeqeunce';    Fmt='s3'   },
    @{ Label='Jog Speed';   Path='send.serverJogSpeed';    Fmt='s9f1' },
    @{ Label='Max Force';   Path='send.serverJogMaxForce'; Fmt='s9f1' }
)
$y = 834; $i = 0
foreach ($r in $sentRows) {
    $i++
    $l = NewItem $screen.ScreenItems $TText "echo_snt_lbl_$i"
    Place $l 1546 $y 110 18
    SetItemText $l $r.Label 10 'Regular' $LabelText 'Left'
    MakeOutputField "echo_snt_val_$i" 1670 $y 130 22 $r.Path $r.Fmt 13 'Right' $PrimaryText $CardBg
    $y += 30
}

# Sequence info / meta — render as a small footer row inside the echo card
$metaRow = @(
    @{ Label='Step Label';   Path='currentLabel';        Fmt='s3' },
    @{ Label='Op Mode Area'; Path='opmodearea';          Fmt='s3' },
    @{ Label='Control #';    Path='hmiControlNo';        Fmt='s5' },
    @{ Label='Cfg MP';       Path='receive.cfgMpNum';    Fmt='s3' },
    @{ Label='Cfg Length';   Path='receive.cfgLength';   Fmt='s3' }
)
$divY = 988
$metaDiv = NewItem $screen.ScreenItems $TRect 'echo_meta_div'
Place $metaDiv 1180 $divY 700 1
$metaDiv.BackColor = $CardBorder; $metaDiv.BorderWidth = [byte]0

$metaHdr = NewItem $screen.ScreenItems $TText 'echo_meta_header'
Place $metaHdr 1176 994 720 18
SetItemText $metaHdr 'SEQUENCE / DEVICE INFO' 9 'Bold' $SecondaryT 'Left'

$cellW = 140
$x = 1180
$i = 0
foreach ($r in $metaRow) {
    $i++
    $l = NewItem $screen.ScreenItems $TText "echo_meta_lbl_$i"
    Place $l $x 1014 $cellW 16
    SetItemText $l $r.Label 9 'Regular' $LabelText 'Left'
    MakeOutputField "echo_meta_val_$i" $x 1032 $cellW 22 $r.Path $r.Fmt 12 'Left' $PrimaryText $CardBg
    $x += $cellW
}

# Sequence End indicator — placed in the TOP-RIGHT of echo header (above the
# sub-headers), guaranteeing no overlap with the meta footer row.
$endLed = NewItem $screen.ScreenItems $TCircle 'seq_end_led'
Place $endLed 1872 786 16 16
BindTag $endLed 'Visible' 'sequenceEnd'
$endLbl = NewItem $screen.ScreenItems $TText 'seq_end_label'
Place $endLbl 1700 786 168 22
SetItemText $endLbl 'Sequence Complete' 10 'Bold' $SecondaryT 'Right'

# Footer
$footer = NewItem $screen.ScreenItems $TText 'footer'
Place $footer 20 1062 1880 16
SetItemText $footer 'Kistler maXYmos NC press operator screen | All values bound to MVterminalPressKistler' 9 'Regular' $SecondaryT 'Center'

# ============================================================
# Save and compile
# ============================================================
Write-Host "`nSaving..."
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
if ($errs.Count -gt 0) {
    Write-Host ""
    foreach ($e in $errs | Select-Object -First 25) { Write-Host "  ERR [$($e.Path)] $($e.Description)" -ForegroundColor Red }
}

$dynCount = 0; $evtCount = 0
foreach ($it in $screen.ScreenItems) {
    $dynCount += $it.Dynamizations.Count
    if ($it.GetType().Name -eq 'HmiButton') { $evtCount += @($it.EventHandlers).Count }
}
Write-Host ""
Write-Host "Items: $($screen.ScreenItems.Count)"
Write-Host "Dynamizations: $dynCount"
Write-Host "Button event handlers: $evtCount"
