# test-kistler-final.ps1
# Comprehensive unit tests for _Kistler_Press_01:
#   - Every named item exists
#   - Every text label has descriptive content (not "Text" placeholder)
#   - Every dynamization is bound to correct path per §19 FB ground truth
#   - Every button has correct event handlers writing to correct move bits
#   - IOField items have correct IOFieldType (Output for read-only, InputOutput for editable)
#   - LED bit-extract bindings have correct ConditionType=Singlebit + bit position
$ErrorActionPreference = 'Stop'
[System.Reflection.Assembly]::LoadFrom("C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll") | Out-Null
$tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal = $tia.Attach()
$project = $portal.LocalSessions[0].Project
$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
function Get-Sw($di) { $m = $di.GetType().GetMethod('GetService').MakeGenericMethod($swT); $m.Invoke($di, $null) }
function Walk($items) { foreach ($it in $items) { try { $svc = Get-Sw $it; if ($svc -and $svc.Software -and $svc.Software.GetType().FullName -match 'HmiUnified') { return $svc.Software } } catch {}; if ($it.DeviceItems) { $r = Walk $it.DeviceItems; if ($r) { return $r } } }; return $null }
$hmiSw = $null; foreach ($d in $project.Devices) { $hmiSw = Walk $d.DeviceItems; if ($hmiSw) { break } }
$null = $hmiSw.Screens.Count
$screen = $hmiSw.Screens.Find('_Kistler_Press_01')
if (-not $screen) { throw "screen not found" }
$RootTag = 'MVterminalPressKistler'

$tests = New-Object System.Collections.ArrayList
function Test([string]$name, [bool]$pass, [string]$detail = '') {
    [void]$tests.Add([pscustomobject]@{ Name = $name; Pass = $pass; Detail = $detail })
}
function Get-Item([string]$n) { foreach ($i in $screen.ScreenItems) { if ($i.Name -eq $n) { return $i } }; return $null }
function Get-PlainText($it) {
    try {
        $mlt = $it.Text
        foreach ($mi in $mlt.Items) {
            $t = $mi.GetAttribute('Text')
            if ($t) { return ($t -replace '<[^>]+>','').Trim() }
        }
    } catch {}
    return $null
}
function Get-Dyn($it, [string]$prop) {
    foreach ($d in $it.Dynamizations) { if ($d.PropertyName -eq $prop) { return $d } }
    return $null
}

# -------- §1: Every named item exists --------
$expectedItems = @(
    'hdr_bg','hdr_accent','hdr_title','hdr_subtitle',
    'plant_label','plant_value','state_badge','state_text','unit_box','unit_label','unit_value',
    'status_card','status_hdr_bg','status_header',
    'led_ready','led_drive_en','led_auto','led_standstill','led_at_home','led_at_ref','led_wait_req',
    'led_seq_end','led_ok_total','led_nok_total','led_smes','led_safety_ok',
    'led_ready_label','led_drive_en_label','led_auto_label','led_standstill_label',
    'led_at_home_label','led_at_ref_label','led_wait_req_label','led_seq_end_label',
    'led_ok_total_label','led_nok_total_label','led_smes_label','led_safety_ok_label',
    'alarm_card','alarm_hdr_bg','alarm_header',
    'alm_hw','alm_tx','alm_drive_nok','alm_safety','alm_cycle_to','alm_wait_miss','alm_remote','alm_serial',
    'alm_hw_label','alm_tx_label','alm_drive_nok_label','alm_safety_label',
    'alm_cycle_to_label','alm_wait_miss_label','alm_remote_label','alm_serial_label',
    'fd_card','fd_hdr_bg','fd_header',
    'pv_force_lbl1','pv_force_unit','pv_force',
    'pv_disp_lbl1','pv_disp_unit','pv_disp',
    'pv_grad_lbl1','pv_grad_unit','pv_grad',
    'fd_plot','fd_plot_note',
    'xmin_lbl','xmin_val','xmax_lbl','xmax_val','ymin_lbl','ymin_val','ymax_lbl','ymax_val',
    'ctrl_card','ctrl_hdr_bg','ctrl_header',
    'btn_run','btn_home','btn_ref','btn_jog_plus','btn_jog_minus','btn_continue','btn_ack_fault','btn_remote',
    'sp_divider','sp_header',
    'jog_speed_label','jog_speed_input','max_force_label','max_force_input',
    'program_header','mp_label','mp_input','seq_label','seq_input','page_label','page_input',
    'op_hint',
    'eo_card','eo_hdr_bg','eo_header',
    'echo_card','echo_hdr_bg','echo_header',
    'seq_end_led','seq_end_label','footer'
)
foreach ($n in $expectedItems) {
    $it = Get-Item $n
    Test "item '$n' exists" ($it -ne $null) ''
}

# -------- §2: Every text item has descriptive content (NOT default "Text") --------
foreach ($it in $screen.ScreenItems) {
    $tn = $it.GetType().Name
    if ($tn -in @('HmiText')) {
        $txt = Get-PlainText $it
        # Static text MUST not be the default placeholder "Text"
        # (HmiText items with TagDynamization on Text show "Text" because TIA reads template)
        $hasDyn = $false
        foreach ($d in $it.Dynamizations) { if ($d.PropertyName -eq 'Text') { $hasDyn = $true; break } }
        if (-not $hasDyn) {
            Test "text '$($it.Name)' is descriptive (not default placeholder)" ($txt -ne 'Text' -and $txt -ne '' -and $txt -ne $null) "actual='$txt'"
        }
    }
}

# -------- §3: Every LED bit-extract is bound correctly per §19 --------
# Format: itemName => @{Path; ExpectedBit}
$ledBits = @{
    'led_ready'      = @{ Path = "$RootTag.receive.status"; Bit = 2  }
    'led_drive_en'   = @{ Path = "$RootTag.receive.status"; Bit = 1  }
    'led_auto'       = @{ Path = "$RootTag.receive.status"; Bit = 0  }
    'led_standstill' = @{ Path = "$RootTag.receive.status"; Bit = 6  }
    'led_at_home'    = @{ Path = "$RootTag.receive.status"; Bit = 5  }
    'led_at_ref'     = @{ Path = "$RootTag.receive.status"; Bit = 4  }
    'led_wait_req'   = @{ Path = "$RootTag.receive.status"; Bit = 3  }
    'led_seq_end'    = @{ Path = "$RootTag.receive.status"; Bit = 12 }
    'led_ok_total'   = @{ Path = "$RootTag.receive.status"; Bit = 8  }
    'led_nok_total'  = @{ Path = "$RootTag.receive.status"; Bit = 9  }
    'led_smes'       = @{ Path = "$RootTag.receive.status"; Bit = 13 }
    'led_safety_ok'  = @{ Path = "$RootTag.state";          Bit = 2  }
    'alm_hw'         = @{ Path = "$RootTag.alarm";          Bit = 1  }
    'alm_tx'         = @{ Path = "$RootTag.alarm";          Bit = 2  }
    'alm_drive_nok'  = @{ Path = "$RootTag.alarm";          Bit = 3  }
    'alm_safety'     = @{ Path = "$RootTag.alarm";          Bit = 13 }
    'alm_cycle_to'   = @{ Path = "$RootTag.alarm";          Bit = 6  }
    'alm_wait_miss'  = @{ Path = "$RootTag.alarm";          Bit = 9  }
    'alm_remote'     = @{ Path = "$RootTag.alarm";          Bit = 16 }
    'alm_serial'     = @{ Path = "$RootTag.alarm";          Bit = 17 }
}
foreach ($n in $ledBits.Keys) {
    $exp = $ledBits[$n]
    $it = Get-Item $n; if (-not $it) { continue }
    $dyn = Get-Dyn $it 'BackColor'
    Test "$n has BackColor dynamization" ($dyn -ne $null) ''
    if ($dyn) {
        $actualPath = $dyn.GetAttribute('Tag')
        Test "$n bound to $($exp.Path)" ($actualPath -eq $exp.Path) "actual=$actualPath"
        $mt = $dyn.ValueConverter.MappingTable
        Test "$n ConditionType=Singlebit" ($mt.GetAttribute('ConditionType') -eq 'Singlebit') "actual=$($mt.GetAttribute('ConditionType'))"
        $entries = @($mt.Entries)
        if ($entries.Count -ge 2) {
            $cond = [int]$entries[1].Condition
            $actualBit = if ($cond -gt 0) { [int]([Math]::Log($cond, 2)) } else { -1 }
            Test "$n targets bit $($exp.Bit)" ($actualBit -eq $exp.Bit) "actual=$actualBit (Cond=$cond)"
        }
    }
}

# -------- §4: Button click handlers — move bit writes --------
$btnMove = @{
    'btn_run'        = @{ Bits=@(1);     Mode='Hold'   }
    'btn_home'       = @{ Bits=@(2);     Mode='Hold'   }
    'btn_ref'        = @{ Bits=@(8);     Mode='Hold'   }
    'btn_jog_plus'   = @{ Bits=@(14);    Mode='Hold'   }
    'btn_jog_minus'  = @{ Bits=@(15);    Mode='Hold'   }
    'btn_continue'   = @{ Bits=@(10,11); Mode='Hold'   }
    'btn_ack_fault'  = @{ Bits=@(9);     Mode='Hold'   }
    'btn_remote'     = @{ Bits=@(0);     Mode='Toggle' }
}
foreach ($n in $btnMove.Keys) {
    $exp = $btnMove[$n]
    $btn = Get-Item $n; if (-not $btn) { continue }
    $expectedMask = 0; foreach ($b in $exp.Bits) { $expectedMask = $expectedMask -bor ([int][Math]::Pow(2, $b)) }
    $handlers = @($btn.EventHandlers)
    if ($exp.Mode -eq 'Toggle') {
        $h = $handlers | Where-Object { "$($_.EventType)" -eq 'Tapped' } | Select-Object -First 1
        Test "$n has Tapped handler (toggle)" ($h -ne $null) ''
        if ($h) {
            $code = $h.Script.GetAttribute('ScriptCode')
            Test "$n script writes to .move"  ($code -match [regex]::Escape("$RootTag.move")) ''
            Test "$n XORs mask $expectedMask" ($code -match "\^\s*$expectedMask\b") "code=$code"
        }
    } else {
        $hAct  = $handlers | Where-Object { "$($_.EventType)" -eq 'Activated' }   | Select-Object -First 1
        $hDe   = $handlers | Where-Object { "$($_.EventType)" -eq 'Deactivated' } | Select-Object -First 1
        Test "$n has Activated handler" ($hAct -ne $null) ''
        Test "$n has Deactivated handler" ($hDe -ne $null) ''
        if ($hAct) {
            $code = $hAct.Script.GetAttribute('ScriptCode')
            Test "$n Activated writes to .move"  ($code -match [regex]::Escape("$RootTag.move")) ''
            Test "$n Activated ORs mask $expectedMask" ($code -match "\|\s*$expectedMask\b") "code=$code"
        }
        if ($hDe) {
            $code = $hDe.Script.GetAttribute('ScriptCode')
            Test "$n Deactivated ANDs ~$expectedMask" ($code -match "&\s*~$expectedMask\b") "code=$code"
        }
    }
}

# -------- §5: Direct tag bindings (no bit extract) --------
$directBindings = @{
    'plant_value'       = @{ Prop='Text';         Path="$RootTag.plantidentifier" }
    'state_badge'       = @{ Prop='BackColor';    Path="$RootTag.stateColour" }
    'unit_value'        = @{ Prop='ProcessValue'; Path="$RootTag.tecUnitNumber" }
    'pv_force'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PVcurrentValueY" }
    'pv_disp'           = @{ Prop='ProcessValue'; Path="$RootTag.receive.PVcurrentValueX" }
    'pv_grad'           = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_EO3_Gradient" }
    'xmin_val'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PVcurrentXmin-X" }
    'xmax_val'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PVcurrentXmax-X" }
    'ymin_val'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PVcurrentYmin-Y" }
    'ymax_val'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PVcurrentYmax-Y" }
    'jog_speed_input'   = @{ Prop='ProcessValue'; Path="$RootTag.serverJogSpeedSet" }
    'max_force_input'   = @{ Prop='ProcessValue'; Path="$RootTag.serverJogMaxForceSet" }
    'mp_input'          = @{ Prop='ProcessValue'; Path="$RootTag.manualSelectMpNum" }
    'seq_input'         = @{ Prop='ProcessValue'; Path="$RootTag.selectSequenceSet" }
    'page_input'        = @{ Prop='ProcessValue'; Path="$RootTag.selectPageSet" }
    'eo1_real'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_EO1_Force" }
    'eo2_real'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_EO2_Distance" }
    'eo3_real'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_EO3_Gradient" }
    'eo4_byte'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_E04_Nopass" }
    'eo5_byte'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_E05_Unibox" }
    'eo6_byte'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_E06_Envelope" }
    'eo7_real'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_Real_EO7" }
    'eo7_byte'          = @{ Prop='ProcessValue'; Path="$RootTag.receive.PV_Byte_E07" }
    'echo_act_val_1'    = @{ Prop='ProcessValue'; Path="$RootTag.receive.mpNum" }
    'echo_act_val_2'    = @{ Prop='ProcessValue'; Path="$RootTag.receive.selectPage" }
    'echo_act_val_3'    = @{ Prop='ProcessValue'; Path="$RootTag.receive.selectSequence" }
    'echo_act_val_4'    = @{ Prop='ProcessValue'; Path="$RootTag.receive.serverJogSpeed" }
    'echo_act_val_5'    = @{ Prop='ProcessValue'; Path="$RootTag.receive.serverJogMaxForce" }
    'echo_snt_val_1'    = @{ Prop='ProcessValue'; Path="$RootTag.send.mpNum" }
    'echo_snt_val_2'    = @{ Prop='ProcessValue'; Path="$RootTag.send.selectPage" }
    'echo_snt_val_3'    = @{ Prop='ProcessValue'; Path="$RootTag.send.selectSeqeunce" }
    'echo_snt_val_4'    = @{ Prop='ProcessValue'; Path="$RootTag.send.serverJogSpeed" }
    'echo_snt_val_5'    = @{ Prop='ProcessValue'; Path="$RootTag.send.serverJogMaxForce" }
    'echo_meta_val_1'   = @{ Prop='ProcessValue'; Path="$RootTag.currentLabel" }
    'echo_meta_val_2'   = @{ Prop='ProcessValue'; Path="$RootTag.opmodearea" }
    'echo_meta_val_3'   = @{ Prop='ProcessValue'; Path="$RootTag.hmiControlNo" }
    'echo_meta_val_4'   = @{ Prop='ProcessValue'; Path="$RootTag.receive.cfgMpNum" }
    'echo_meta_val_5'   = @{ Prop='ProcessValue'; Path="$RootTag.receive.cfgLength" }
    'seq_end_led'       = @{ Prop='Visible';      Path="$RootTag.sequenceEnd" }
}
foreach ($n in $directBindings.Keys) {
    $exp = $directBindings[$n]
    $it = Get-Item $n; if (-not $it) { continue }
    $dyn = Get-Dyn $it $exp.Prop
    Test "$n has $($exp.Prop) dynamization" ($dyn -ne $null) ''
    if ($dyn) {
        $actual = $dyn.GetAttribute('Tag')
        Test "$n bound to $($exp.Path)" ($actual -eq $exp.Path) "actual=$actual"
    }
}

# -------- §6: IOField mode correctness --------
$readOnlyIOs   = @('unit_value','pv_force','pv_disp','pv_grad','xmin_val','xmax_val','ymin_val','ymax_val',
                   'eo1_real','eo2_real','eo3_real','eo4_byte','eo5_byte','eo6_byte','eo7_real','eo7_byte',
                   'echo_act_val_1','echo_act_val_2','echo_act_val_3','echo_act_val_4','echo_act_val_5',
                   'echo_snt_val_1','echo_snt_val_2','echo_snt_val_3','echo_snt_val_4','echo_snt_val_5',
                   'echo_meta_val_1','echo_meta_val_2','echo_meta_val_3','echo_meta_val_4','echo_meta_val_5')
$editableIOs   = @('jog_speed_input','max_force_input','mp_input','seq_input','page_input')
foreach ($n in $readOnlyIOs) {
    $it = Get-Item $n
    if ($it) {
        Test "$n is HmiIOField" ($it.GetType().Name -eq 'HmiIOField') "actual=$($it.GetType().Name)"
        if ($it.GetType().Name -eq 'HmiIOField') {
            Test "$n IOFieldType=Output (read-only)" ("$($it.IOFieldType)" -eq 'Output') "actual=$($it.IOFieldType)"
        }
    }
}
foreach ($n in $editableIOs) {
    $it = Get-Item $n
    if ($it) {
        Test "$n is HmiIOField" ($it.GetType().Name -eq 'HmiIOField') "actual=$($it.GetType().Name)"
        if ($it.GetType().Name -eq 'HmiIOField') {
            Test "$n IOFieldType=InputOutput (editable)" ("$($it.IOFieldType)" -eq 'InputOutput') "actual=$($it.IOFieldType)"
        }
    }
}

# -------- §7: LAYOUT correctness (TIA-programmer style checks) --------
# Build a list of all items with their bounding boxes.
$rects = @()
foreach ($it in $screen.ScreenItems) {
    $tn = $it.GetType().Name
    try {
        if ($tn -eq 'HmiCircle') {
            $cx = $it.CenterX; $cy = $it.CenterY; $r = $it.Radius
            $rects += [pscustomobject]@{ Name=$it.Name; Type=$tn; L=($cx-$r); T=($cy-$r); R=($cx+$r); B=($cy+$r) }
        } else {
            $L = $it.Left; $T = $it.Top
            $W = if ($it.Width) { $it.Width } else { 0 }
            $H = if ($it.Height) { $it.Height } else { 0 }
            $rects += [pscustomobject]@{ Name=$it.Name; Type=$tn; L=$L; T=$T; R=($L+$W); B=($T+$H) }
        }
    } catch {}
}

# Layout 1: every item within screen 0,0 to 1920,1080
foreach ($r in $rects) {
    $within = ($r.L -ge 0) -and ($r.T -ge 0) -and ($r.R -le 1920) -and ($r.B -le 1080)
    Test "layout: $($r.Name) inside screen bounds" $within "L=$($r.L) T=$($r.T) R=$($r.R) B=$($r.B)"
}

# Layout 2: top-level cards (background panels) must not overlap each other
$topCards = @('hdr_bg','status_card','alarm_card','fd_card','ctrl_card','eo_card','echo_card')
$topRects = $rects | Where-Object { $topCards -contains $_.Name }
for ($i = 0; $i -lt $topRects.Count; $i++) {
    for ($j = $i+1; $j -lt $topRects.Count; $j++) {
        $a = $topRects[$i]; $b = $topRects[$j]
        $overlap = ($a.L -lt $b.R) -and ($b.L -lt $a.R) -and ($a.T -lt $b.B) -and ($b.T -lt $a.B)
        Test "layout: $($a.Name) does not overlap $($b.Name)" (-not $overlap) "$($a.Name)=($($a.L),$($a.T))-($($a.R),$($a.B))  vs $($b.Name)=($($b.L),$($b.T))-($($b.R),$($b.B))"
    }
}

# Layout 3: rough text-fits-container check for known long labels
# Heuristic: at 11pt regular, ~7 pixels per char; at 10pt ~6 px; at 9pt ~5.5 px
function FitsWidth($it, $charWidth) {
    $txt = Get-PlainText $it
    if (-not $txt) { return $true }
    $W = if ($it.Width) { $it.Width } else { 0 }
    $needed = $txt.Length * $charWidth
    return $needed -le $W
}
$labelChecks = @(
    @{ Name='led_standstill_label';   CharWidth=7 },
    @{ Name='led_drive_en_label';     CharWidth=7 },
    @{ Name='led_at_home_label';      CharWidth=7 },
    @{ Name='alm_wait_miss_label';    CharWidth=7 },
    @{ Name='alm_remote_label';       CharWidth=7 },
    @{ Name='alm_serial_label';       CharWidth=7 },
    @{ Name='op_hint';                CharWidth=5 }
)
foreach ($c in $labelChecks) {
    $it = Get-Item $c.Name
    if ($it) {
        $txt = Get-PlainText $it
        $w = if ($it.Width) { $it.Width } else { 0 }
        $needed = if ($txt) { $txt.Length * $c.CharWidth } else { 0 }
        Test "layout: '$($c.Name)' text fits ($txt = $($txt.Length) chars × $($c.CharWidth)px = $needed ≤ $w)" ($needed -le $w) ""
    }
}

# Layout 4: children of cards must be within card bounds
$cardChildren = @{
    'status_card' = @('led_ready','led_drive_en','led_auto','led_standstill','led_at_home','led_at_ref','led_wait_req','led_seq_end','led_ok_total','led_nok_total','led_smes','led_safety_ok','status_header')
    'alarm_card'  = @('alm_hw','alm_tx','alm_drive_nok','alm_safety','alm_cycle_to','alm_wait_miss','alm_remote','alm_serial','alarm_header')
    'fd_card'     = @('pv_force','pv_disp','pv_grad','fd_plot','fd_header','xmin_val','xmax_val','ymin_val','ymax_val')
    'ctrl_card'   = @('btn_run','btn_home','btn_ref','btn_jog_plus','btn_jog_minus','btn_continue','btn_ack_fault','btn_remote','jog_speed_input','max_force_input','mp_input','seq_input','page_input','ctrl_header','op_hint')
    'eo_card'     = @('eo_header','eo1_real','eo2_real','eo3_real','eo4_byte','eo5_byte','eo6_byte','eo7_real','eo7_byte','eo8_real','eo8_byte','eo9_real','eo9_byte','eo10_real','eo10_byte')
    'echo_card'   = @('echo_header','echo_act_val_1','echo_act_val_2','echo_act_val_3','echo_act_val_4','echo_act_val_5','echo_snt_val_1','echo_snt_val_2','echo_snt_val_3','echo_snt_val_4','echo_snt_val_5','echo_meta_val_1','echo_meta_val_2','echo_meta_val_3','echo_meta_val_4','echo_meta_val_5','seq_end_led','seq_end_label','echo_meta_header')
    'hdr_bg'      = @('hdr_accent','hdr_title','hdr_subtitle','plant_label','plant_value','state_badge','state_text','unit_box','unit_label','unit_value')
}
foreach ($card in $cardChildren.Keys) {
    $cardR = $rects | Where-Object { $_.Name -eq $card } | Select-Object -First 1
    if (-not $cardR) { continue }
    foreach ($childName in $cardChildren[$card]) {
        $cr = $rects | Where-Object { $_.Name -eq $childName } | Select-Object -First 1
        if (-not $cr) { continue }
        $inside = ($cr.L -ge $cardR.L) -and ($cr.T -ge $cardR.T) -and ($cr.R -le $cardR.R) -and ($cr.B -le $cardR.B)
        Test "layout: '$childName' fits inside '$card'" $inside "child=($($cr.L),$($cr.T))-($($cr.R),$($cr.B)) card=($($cardR.L),$($cardR.T))-($($cardR.R),$($cardR.B))"
    }
}

# Layout 5: ORPHAN DETECTOR — every interactive item (Text/IO/Button/Circle/Line)
# must belong to a known card or be explicitly whitelisted (e.g. footer at screen bottom)
$cardBackgrounds = @('hdr_bg','status_card','alarm_card','fd_card','ctrl_card','eo_card','echo_card',
                     'status_hdr_bg','alarm_hdr_bg','fd_hdr_bg','ctrl_hdr_bg','eo_hdr_bg','echo_hdr_bg')
$whitelistOrphan = @('footer')   # items that are intentionally outside any card
$registeredChildren = @{}
foreach ($childList in $cardChildren.Values) {
    foreach ($n in $childList) { $registeredChildren[$n] = $true }
}
foreach ($r in $rects) {
    if ($cardBackgrounds -contains $r.Name) { continue }            # cards themselves
    if ($whitelistOrphan -contains $r.Name) { continue }            # known footers etc
    if ($r.Name -like 'eo*_*' -or $r.Name -like 'eoh_*' -or $r.Name -like 'eo_sep_*') { continue }   # eo_card grid children verified separately
    if ($r.Name -like 'echo_*' -or $r.Name -like 'sp_*' -or $r.Name -like 'program_*' -or $r.Name -like 'mp_*' -or $r.Name -like 'seq_*' -or $r.Name -like 'page_*' -or $r.Name -like 'jog_*' -or $r.Name -like 'max_force_*') { continue }
    if ($r.Name -like 'pv_*' -or $r.Name -like 'fd_*' -or $r.Name -like 'xmin_*' -or $r.Name -like 'xmax_*' -or $r.Name -like 'ymin_*' -or $r.Name -like 'ymax_*') { continue }
    if ($r.Name -like '*_label' -or $r.Name -like 'led_*' -or $r.Name -like 'alm_*') { continue }
    if ($r.Name -like 'hdr_*' -or $r.Name -like 'plant_*' -or $r.Name -like 'state_*' -or $r.Name -like 'unit_*') { continue }
    Test "orphan-detector: '$($r.Name)' belongs to a known card" ($registeredChildren.ContainsKey($r.Name)) "type=$($r.Type) at ($($r.L),$($r.T))"
}

# Layout 6: SIBLING OVERLAP — no two interactive items (Text/IO/Button/Circle) should overlap each other.
# Allowed exceptions: a label/icon inside another container's visual rectangle (parent-child relationship)
$interactive = $rects | Where-Object { $_.Type -in @('HmiText','HmiIOField','HmiButton','HmiCircle') }
# Build parent map: for each interactive item, what cards it's a child of (so we can ignore parent overlap)
$itemToCards = @{}
foreach ($card in $cardChildren.Keys) {
    foreach ($child in $cardChildren[$card]) { $itemToCards[$child] = $card }
}
$overlaps = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $interactive.Count; $i++) {
    for ($j = $i+1; $j -lt $interactive.Count; $j++) {
        $a = $interactive[$i]; $b = $interactive[$j]
        $hit = ($a.L -lt $b.R) -and ($b.L -lt $a.R) -and ($a.T -lt $b.B) -and ($b.T -lt $a.B)
        if ($hit) {
            # Allow pair if they're a label-with-icon-circle row (label adjacent, not overlapping much) — generally don't allow
            [void]$overlaps.Add("$($a.Name) ($($a.L),$($a.T))-($($a.R),$($a.B))  vs  $($b.Name) ($($b.L),$($b.T))-($($b.R),$($b.B))")
        }
    }
}
Test "sibling overlap: no two interactive items overlap" ($overlaps.Count -eq 0) ($overlaps -join '; ')

# -------- Summary --------
$pass = $tests | Where-Object Pass
$fail = $tests | Where-Object { -not $_.Pass }
Write-Host ""
Write-Host "================================================="
Write-Host "  TEST RESULTS"
Write-Host "================================================="
Write-Host "  $($pass.Count) passed / $($fail.Count) failed / $($tests.Count) total"
Write-Host ""
if ($fail.Count -gt 0) {
    Write-Host "FAILURES:" -ForegroundColor Red
    foreach ($f in $fail) { Write-Host "  X $($f.Name)  $($f.Detail)" -ForegroundColor Red }
} else {
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
}
