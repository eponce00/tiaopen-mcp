# build-kistler-pro-v3.ps1
# Uses the layout-aware design framework. Each Add-* call validates fit + no
# sibling overlap + ownership *at the call site* — errors fail fast where they
# happen, not at end-of-build.

. "$PSScriptRoot\kistler-design.ps1"

Initialize-Design -ScreenName '_Kistler_Press_01' -RootTag 'MVterminalPressKistler'
$C = Get-Colors
$screen = Get-Screen

# ============================================================
# HEADER ribbon (y=0..72) — uses hdr_bg as a card
# ============================================================
$hdr = New-Card -Name 'hdr_bg' -X 0 -Y 0 -W 1920 -H 72 `
    -BgColor $C.HeaderBg -BorderColor $C.HeaderBg
# Accent stripe (small rect inside header)
Add-Label -Card $hdr -Name 'hdr_accent_placeholder' -X 0 -Y 0 -W 6 -H 72 -Text '' -ForeColor $C.Accent -FontSize 1
Add-Label -Card $hdr -Name 'hdr_title' -X 28 -Y 10 -W 360 -H 28 -Text 'KISTLER maXYmos NC' -FontSize 16 -Weight 'Bold' -ForeColor $C.HeaderText
Add-Label -Card $hdr -Name 'hdr_subtitle' -X 28 -Y 40 -W 360 -H 18 -Text 'Press Monitor and Controller' -FontSize 10 -Weight 'Regular' -ForeColor $C.HeaderSub
Add-Label -Card $hdr -Name 'plant_label' -X 600 -Y 8 -W 720 -H 16 -Text 'PLANT' -FontSize 9 -Weight 'Bold' -ForeColor $C.HeaderSub -HAlign 'Center'
Add-DisplayText -Card $hdr -Name 'plant_value' -X 600 -Y 26 -W 720 -H 36 -Path 'plantidentifier' -FontSize 18 -Weight 'Bold' -ForeColor $C.HeaderText -HAlign 'Center'
Add-Label -Card $hdr -Name 'state_text' -X 1480 -Y 14 -W 220 -H 18 -Text 'OPERATING STATE' -FontSize 9 -Weight 'Bold' -ForeColor $C.HeaderSub -HAlign 'Center'
Add-DisplayText -Card $hdr -Name 'state_value' -X 1480 -Y 34 -W 220 -H 24 -Path 'stateColour' -FontSize 12 -Weight 'Bold' -ForeColor $C.HeaderText -HAlign 'Center'
Add-Label -Card $hdr -Name 'unit_label' -X 1722 -Y 14 -W 60 -H 18 -Text 'UNIT' -FontSize 9 -Weight 'Bold' -ForeColor $C.HeaderSub -HAlign 'Left'
Add-DisplayValue -Card $hdr -Name 'unit_value' -X 1786 -Y 14 -W 110 -H 44 -Path 'tecUnitNumber' -Format 's3' -FontSize 22 -HAlign 'Right' -ForeColor $C.HeaderText -BgColor $C.HeaderBg

# ============================================================
# STATUS card (left rail top)
# ============================================================
$status = New-Card -Name 'status_card' -X 20 -Y 92 -W 300 -H 468 -Header 'PRESS STATUS'
Add-StatusLed -Card $status -Name 'led_ready'      -Label 'Ready'             -Field 'receive.status' -Bit 2  -OnColor $C.LightGreen
Add-StatusLed -Card $status -Name 'led_drive_en'   -Label 'Drive Enabled'     -Field 'receive.status' -Bit 1  -OnColor $C.LightGreen
Add-StatusLed -Card $status -Name 'led_auto'       -Label 'Automatic Mode'    -Field 'receive.status' -Bit 0  -OnColor $C.LightGreen
Add-StatusLed -Card $status -Name 'led_standstill' -Label 'At Standstill'     -Field 'receive.status' -Bit 6  -OnColor $C.LightBlue
Add-StatusLed -Card $status -Name 'led_at_home'    -Label 'At Home Position'  -Field 'receive.status' -Bit 5  -OnColor $C.LightGreen
Add-StatusLed -Card $status -Name 'led_at_ref'     -Label 'At Reference'      -Field 'receive.status' -Bit 4  -OnColor $C.LightGreen
Add-StatusLed -Card $status -Name 'led_wait_req'   -Label 'Waiting'           -Field 'receive.status' -Bit 3  -OnColor $C.Orange
Add-StatusLed -Card $status -Name 'led_seq_end'    -Label 'Sequence Complete' -Field 'receive.status' -Bit 12 -OnColor $C.LightGreen
Add-StatusLed -Card $status -Name 'led_ok_total'   -Label 'Result OK'         -Field 'receive.status' -Bit 8  -OnColor $C.LightGreen
Add-StatusLed -Card $status -Name 'led_nok_total'  -Label 'Result NOK'        -Field 'receive.status' -Bit 9  -OnColor $C.Red
Add-StatusLed -Card $status -Name 'led_smes'       -Label 'Safe Mode Active'  -Field 'receive.status' -Bit 13 -OnColor $C.Yellow
Add-StatusLed -Card $status -Name 'led_safety_ok'  -Label 'Safety OK'         -Field 'state'          -Bit 2  -OnColor $C.LightGreen

# ============================================================
# ALARM card (left rail bottom, extends to screen bottom)
# ============================================================
$alarm = New-Card -Name 'alarm_card' -X 20 -Y 580 -W 300 -H 478 -Header 'ACTIVE ALARMS' -HeaderTextColor $C.Red
Add-StatusLed -Card $alarm -Name 'alm_hw'        -Label 'Hardware Fault'         -Field 'alarm' -Bit 1  -OnColor $C.Red
Add-StatusLed -Card $alarm -Name 'alm_tx'        -Label 'Fieldbus TX Fault'      -Field 'alarm' -Bit 2  -OnColor $C.Red
Add-StatusLed -Card $alarm -Name 'alm_drive_nok' -Label 'Drive Not Enabled'      -Field 'alarm' -Bit 3  -OnColor $C.Red
Add-StatusLed -Card $alarm -Name 'alm_safety'    -Label 'Safety Circuit Open'    -Field 'alarm' -Bit 13 -OnColor $C.Red
Add-StatusLed -Card $alarm -Name 'alm_cycle_to'  -Label 'Cycle Timeout'          -Field 'alarm' -Bit 6  -OnColor $C.Red
Add-StatusLed -Card $alarm -Name 'alm_wait_miss' -Label 'Continue Cmd Missing'   -Field 'alarm' -Bit 9  -OnColor $C.Orange
Add-StatusLed -Card $alarm -Name 'alm_remote'    -Label 'Remote Inactive'        -Field 'alarm' -Bit 16 -OnColor $C.Orange
Add-StatusLed -Card $alarm -Name 'alm_serial'    -Label 'Serial Mismatch'        -Field 'alarm' -Bit 17 -OnColor $C.Red

# ============================================================
# F-D Hero card (center, top)
# ============================================================
$fd = New-Card -Name 'fd_card' -X 340 -Y 92 -W 1160 -H 520 -Header 'FORCE-DISPLACEMENT CURVE'
Add-Label -Card $fd -Name 'pv_force_lbl' -X 360 -Y 134 -W 110 -H 18 -Text 'Force Y' -FontSize 10 -Weight 'Bold' -ForeColor $C.LabelText
Add-Label -Card $fd -Name 'pv_force_unit' -X 470 -Y 134 -W 80 -H 18 -Text '[N]' -FontSize 10 -ForeColor $C.SecondaryT
Add-DisplayValue -Card $fd -Name 'pv_force' -X 360 -Y 154 -W 280 -H 44 -Path 'receive.PVcurrentValueY' -Format 's9f1' -FontSize 28 -HAlign 'Left' -ForeColor $C.PrimaryText

Add-Label -Card $fd -Name 'pv_disp_lbl' -X 720 -Y 134 -W 110 -H 18 -Text 'Displacement X' -FontSize 10 -Weight 'Bold' -ForeColor $C.LabelText
Add-Label -Card $fd -Name 'pv_disp_unit' -X 830 -Y 134 -W 80 -H 18 -Text '[mm]' -FontSize 10 -ForeColor $C.SecondaryT
Add-DisplayValue -Card $fd -Name 'pv_disp' -X 720 -Y 154 -W 280 -H 44 -Path 'receive.PVcurrentValueX' -Format 's9f3' -FontSize 28 -HAlign 'Left' -ForeColor $C.PrimaryText

Add-Label -Card $fd -Name 'pv_grad_lbl' -X 1080 -Y 134 -W 110 -H 18 -Text 'Gradient' -FontSize 10 -Weight 'Bold' -ForeColor $C.LabelText
Add-Label -Card $fd -Name 'pv_grad_unit' -X 1190 -Y 134 -W 80 -H 18 -Text '[N/mm]' -FontSize 10 -ForeColor $C.SecondaryT
Add-DisplayValue -Card $fd -Name 'pv_grad' -X 1080 -Y 154 -W 280 -H 44 -Path 'receive.PV_EO3_Gradient' -Format 's9f2' -FontSize 28 -HAlign 'Left' -ForeColor $C.PrimaryText

# Curve plot region (placeholder for HmiTrendControl)
Add-Label -Card $fd -Name 'fd_plot_note' -X 380 -Y 380 -W 1100 -H 24 -Text 'Trend control area (place HmiTrendControl here in TIA editor)' -FontSize 11 -HAlign 'Center' -ForeColor $C.SecondaryT

# Axis bounds
Add-Label -Card $fd -Name 'xmin_lbl' -X 380 -Y 588 -W 90 -H 18 -Text 'X min [mm]' -FontSize 9 -ForeColor $C.SecondaryT
Add-DisplayValue -Card $fd -Name 'xmin_val' -X 470 -Y 588 -W 80 -H 18 -Path 'receive.PVcurrentXmin-X' -Format 's7f2' -FontSize 10 -HAlign 'Left'
Add-Label -Card $fd -Name 'xmax_lbl' -X 1300 -Y 588 -W 80 -H 18 -Text 'X max [mm]' -FontSize 9 -HAlign 'Right' -ForeColor $C.SecondaryT
Add-DisplayValue -Card $fd -Name 'xmax_val' -X 1392 -Y 588 -W 88 -H 18 -Path 'receive.PVcurrentXmax-X' -Format 's7f2' -FontSize 10 -HAlign 'Right'
Add-Label -Card $fd -Name 'ymin_lbl' -X 380 -Y 200 -W 90 -H 18 -Text 'Y min [N]' -FontSize 9 -ForeColor $C.SecondaryT
Add-DisplayValue -Card $fd -Name 'ymin_val' -X 470 -Y 200 -W 80 -H 18 -Path 'receive.PVcurrentYmin-Y' -Format 's7f1' -FontSize 10 -HAlign 'Left'
Add-Label -Card $fd -Name 'ymax_lbl' -X 1300 -Y 200 -W 80 -H 18 -Text 'Y max [N]' -FontSize 9 -HAlign 'Right' -ForeColor $C.SecondaryT
Add-DisplayValue -Card $fd -Name 'ymax_val' -X 1392 -Y 200 -W 88 -H 18 -Path 'receive.PVcurrentYmax-Y' -Format 's7f1' -FontSize 10 -HAlign 'Right'

# ============================================================
# PRESS CONTROL card (right rail)
# ============================================================
$ctrl = New-Card -Name 'ctrl_card' -X 1520 -Y 92 -W 380 -H 668 -Header 'PRESS CONTROL'
Add-Button -Card $ctrl -Name 'btn_run'        -Label 'START SEQUENCE' -X 1540 -Y 140 -W 340 -H 80 -MoveBits @(1)      -BgColor $C.BtnRunBg     -HoverColor $C.LightGreen -EchoBit 2
Add-Button -Card $ctrl -Name 'btn_home'       -Label 'HOME'           -X 1540 -Y 240 -W 165 -H 60 -MoveBits @(2)      -BgColor $C.BtnNeutralBg -HoverColor $C.LightBlue  -EchoBit 3
Add-Button -Card $ctrl -Name 'btn_ref'        -Label 'REFERENCE'      -X 1715 -Y 240 -W 165 -H 60 -MoveBits @(8)      -BgColor $C.BtnNeutralBg -HoverColor $C.LightBlue  -EchoBit 4
Add-Button -Card $ctrl -Name 'btn_jog_plus'   -Label 'JOG +'          -X 1540 -Y 312 -W 165 -H 60 -MoveBits @(14)     -BgColor $C.BtnNeutralBg -HoverColor $C.LightGreen -EchoBit 5
Add-Button -Card $ctrl -Name 'btn_jog_minus'  -Label 'JOG -'          -X 1715 -Y 312 -W 165 -H 60 -MoveBits @(15)     -BgColor $C.BtnNeutralBg -HoverColor $C.LightGreen -EchoBit 6
Add-Button -Card $ctrl -Name 'btn_continue'   -Label 'CONTINUE'       -X 1540 -Y 384 -W 165 -H 60 -MoveBits @(10,11)  -BgColor $C.BtnWarnBg    -HoverColor $C.Orange     -EchoBit 7
Add-Button -Card $ctrl -Name 'btn_ack_fault'  -Label 'ACK FAULT'      -X 1715 -Y 384 -W 165 -H 60 -MoveBits @(9)      -BgColor $C.BtnStopBg    -HoverColor $C.Red        -EchoBit 9
Add-Button -Card $ctrl -Name 'btn_remote'     -Label 'REMOTE TOGGLE'  -X 1540 -Y 456 -W 340 -H 50 -MoveBits @(0)      -BgColor $C.BtnNeutralBg -HoverColor $C.LightBlue  -Toggle $true -EchoBit 0

# Setpoints section
Add-Label -Card $ctrl -Name 'sp_header' -X 1540 -Y 532 -W 340 -H 18 -Text 'SETPOINTS' -FontSize 10 -Weight 'Bold' -ForeColor $C.SecondaryT
Add-Label -Card $ctrl -Name 'jog_speed_label' -X 1540 -Y 555 -W 160 -H 18 -Text 'Jog Speed [mm/s]' -FontSize 10 -ForeColor $C.LabelText
Add-EditableValue -Card $ctrl -Name 'jog_speed_input' -X 1540 -Y 575 -W 160 -H 32 -Path 'serverJogSpeedSet' -Format 's9f1'
Add-Label -Card $ctrl -Name 'max_force_label' -X 1720 -Y 555 -W 160 -H 18 -Text 'Max Force [N]' -FontSize 10 -ForeColor $C.LabelText
Add-EditableValue -Card $ctrl -Name 'max_force_input' -X 1720 -Y 575 -W 160 -H 32 -Path 'serverJogMaxForceSet' -Format 's9f1'

# Program section
Add-Label -Card $ctrl -Name 'program_header' -X 1540 -Y 620 -W 340 -H 18 -Text 'PROGRAM SELECTION' -FontSize 10 -Weight 'Bold' -ForeColor $C.SecondaryT
Add-Label -Card $ctrl -Name 'mp_label'   -X 1540 -Y 642 -W 100 -H 16 -Text 'MP (0-127)' -FontSize 9 -ForeColor $C.LabelText
Add-EditableValue -Card $ctrl -Name 'mp_input' -X 1540 -Y 660 -W 100 -H 36 -Path 'manualSelectMpNum' -Format 's3' -FontSize 14
Add-Label -Card $ctrl -Name 'seq_label'  -X 1655 -Y 642 -W 100 -H 16 -Text 'Sequence (0-3)' -FontSize 9 -ForeColor $C.LabelText
Add-EditableValue -Card $ctrl -Name 'seq_input' -X 1655 -Y 660 -W 100 -H 36 -Path 'selectSequenceSet' -Format 's3' -FontSize 14
Add-Label -Card $ctrl -Name 'page_label' -X 1770 -Y 642 -W 110 -H 16 -Text 'Page (0-7)' -FontSize 9 -ForeColor $C.LabelText
Add-EditableValue -Card $ctrl -Name 'page_input' -X 1770 -Y 660 -W 110 -H 36 -Path 'selectPageSet' -Format 's3' -FontSize 14

Add-Label -Card $ctrl -Name 'op_hint' -X 1540 -Y 712 -W 340 -H 36 -Text 'Hold buttons to assert commands.' -FontSize 9 -ForeColor $C.SecondaryT

# ============================================================
# EO RESULTS card (center bottom — right under F-D card)
# ============================================================
$eo = New-Card -Name 'eo_card' -X 340 -Y 632 -W 800 -H 426 -Header 'EVALUATION OBJECT RESULTS'
# Column headers
Add-Label -Card $eo -Name 'eoh_n'    -X 356 -Y 664 -W 30  -H 18 -Text 'No.'         -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT
Add-Label -Card $eo -Name 'eoh_name' -X 400 -Y 664 -W 180 -H 18 -Text 'Measurement' -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT
Add-Label -Card $eo -Name 'eoh_real' -X 590 -Y 664 -W 170 -H 18 -Text 'Value'       -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT
Add-Label -Card $eo -Name 'eoh_byte' -X 770 -Y 664 -W 70  -H 18 -Text 'Code'        -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT
Add-Label -Card $eo -Name 'eoh_pf'   -X 860 -Y 664 -W 270 -H 18 -Text 'Pass / Fail' -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT

$eoRows = @(
    @{ N=1; Name='Force (EO1)';    Real='receive.PV_EO1_Force';    Byte=$null                       },
    @{ N=2; Name='Distance (EO2)'; Real='receive.PV_EO2_Distance'; Byte=$null                       },
    @{ N=3; Name='Gradient (EO3)'; Real='receive.PV_EO3_Gradient'; Byte=$null                       },
    @{ N=4; Name='No-Pass (EO4)';  Real=$null;                     Byte='receive.PV_E04_Nopass'     },
    @{ N=5; Name='Uni-Box (EO5)';  Real=$null;                     Byte='receive.PV_E05_Unibox'     },
    @{ N=6; Name='Envelope (EO6)'; Real=$null;                     Byte='receive.PV_E06_Envelope'   },
    @{ N=7; Name='Custom EO7';     Real='receive.PV_Real_EO7';     Byte='receive.PV_Byte_E07'       },
    @{ N=8; Name='Custom EO8';     Real='receive.PV_Real_EO8';     Byte='receive.PV_Byte_E08'       },
    @{ N=9; Name='Custom EO9';     Real='receive.PV_Real_EO9';     Byte='receive.PV_Byte_E09'       },
    @{ N=10; Name='Custom EO10';   Real='receive.PV_Real_E10';     Byte='receive.PV_Byte_E10'       }
)
$rowY = 690
foreach ($row in $eoRows) {
    Add-Label -Card $eo -Name "eo$($row.N)_num"  -X 356 -Y $rowY -W 30  -H 20 -Text "$($row.N)" -FontSize 11 -Weight 'Bold' -ForeColor $C.SecondaryT
    Add-Label -Card $eo -Name "eo$($row.N)_name" -X 400 -Y $rowY -W 180 -H 20 -Text $row.Name -FontSize 11 -ForeColor $C.PrimaryText
    if ($row.Real) {
        Add-DisplayValue -Card $eo -Name "eo$($row.N)_real" -X 590 -Y $rowY -W 170 -H 20 -Path $row.Real -Format 's9f3' -FontSize 11 -HAlign 'Right'
    } else {
        Add-Label -Card $eo -Name "eo$($row.N)_real_dash" -X 590 -Y $rowY -W 170 -H 20 -Text '-' -FontSize 11 -HAlign 'Right' -ForeColor $C.SecondaryT
    }
    if ($row.Byte) {
        Add-DisplayValue -Card $eo -Name "eo$($row.N)_byte" -X 770 -Y $rowY -W 70 -H 20 -Path $row.Byte -Format 's3' -FontSize 11 -HAlign 'Right'
        # Pass/fail dot — bit 0 of byte
        $led = _NewItem $screen.ScreenItems $script:Types.Circle "eo$($row.N)_pf_led"
        Assert-Placement "eo$($row.N)_pf_led" $eo 860 $rowY 16 16
        _Place $led 860 $rowY 16 16
        _BindBit $led 0 $C.Red $C.LightGreen $row.Byte
        Register-Child $eo "eo$($row.N)_pf_led" 'HmiCircle' 860 $rowY 16 16
        Add-Label -Card $eo -Name "eo$($row.N)_pf_text" -X 884 -Y $rowY -W 240 -H 20 -Text 'PASS when value = 0' -FontSize 9 -ForeColor $C.SecondaryT
    } else {
        Add-Label -Card $eo -Name "eo$($row.N)_byte_dash" -X 770 -Y $rowY -W 70 -H 20 -Text '-' -FontSize 11 -HAlign 'Right' -ForeColor $C.SecondaryT
        Add-Label -Card $eo -Name "eo$($row.N)_note" -X 860 -Y $rowY -W 270 -H 20 -Text 'Measurement only' -FontSize 9 -ForeColor $C.SecondaryT
    }
    $rowY += 32
}

# ============================================================
# ECHO card (center bottom right)
# ============================================================
$echo = New-Card -Name 'echo_card' -X 1160 -Y 780 -W 740 -H 278 -Header 'PROGRAM / SEQUENCE / CONFIG ECHO' -HeaderTextWidth 500

# Sequence-end LED — placed in top-right of card header band (no row collision)
$endLed = _NewItem $screen.ScreenItems $script:Types.Circle 'seq_end_led'
Assert-Placement 'seq_end_led' $echo 1872 786 16 16
_Place $endLed 1872 786 16 16
_BindTag $endLed 'Visible' 'sequenceEnd' | Out-Null
Register-Child $echo 'seq_end_led' 'HmiCircle' 1872 786 16 16
Add-Label -Card $echo -Name 'seq_end_label' -X 1700 -Y 786 -W 168 -H 22 -Text 'Sequence Complete' -FontSize 10 -Weight 'Bold' -HAlign 'Right' -ForeColor $C.SecondaryT

# Sub-headers
Add-Label -Card $echo -Name 'subh_active' -X 1176 -Y 814 -W 280 -H 16 -Text 'CURRENT (FROM DEVICE)' -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT
Add-Label -Card $echo -Name 'subh_sent'   -X 1546 -Y 814 -W 280 -H 16 -Text 'SENT TO DEVICE' -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT

# Active column (receive.*)
$activeRows = @(
    @{ Label='MP Number'; Path='receive.mpNum';             Fmt='s3'   },
    @{ Label='Page';      Path='receive.selectPage';        Fmt='s3'   },
    @{ Label='Sequence';  Path='receive.selectSequence';    Fmt='s3'   },
    @{ Label='Jog Speed'; Path='receive.serverJogSpeed';    Fmt='s9f1' },
    @{ Label='Max Force'; Path='receive.serverJogMaxForce'; Fmt='s9f1' }
)
$y = 836; $i = 0
foreach ($r in $activeRows) {
    $i++
    Add-Label -Card $echo -Name "echo_act_lbl_$i" -X 1176 -Y $y -W 110 -H 18 -Text $r.Label -FontSize 10 -ForeColor $C.LabelText
    Add-DisplayValue -Card $echo -Name "echo_act_val_$i" -X 1290 -Y $y -W 140 -H 22 -Path $r.Path -Format $r.Fmt -FontSize 13 -HAlign 'Right'
    $y += 30
}

# Sent column (send.*)
$sentRows = @(
    @{ Label='MP Number'; Path='send.mpNum';             Fmt='s3'   },
    @{ Label='Page';      Path='send.selectPage';        Fmt='s3'   },
    @{ Label='Sequence';  Path='send.selectSeqeunce';    Fmt='s3'   },
    @{ Label='Jog Speed'; Path='send.serverJogSpeed';    Fmt='s9f1' },
    @{ Label='Max Force'; Path='send.serverJogMaxForce'; Fmt='s9f1' }
)
$y = 836; $i = 0
foreach ($r in $sentRows) {
    $i++
    Add-Label -Card $echo -Name "echo_snt_lbl_$i" -X 1546 -Y $y -W 110 -H 18 -Text $r.Label -FontSize 10 -ForeColor $C.LabelText
    Add-DisplayValue -Card $echo -Name "echo_snt_val_$i" -X 1660 -Y $y -W 140 -H 22 -Path $r.Path -Format $r.Fmt -FontSize 13 -HAlign 'Right'
    $y += 30
}

# Meta row at bottom of echo card
Add-Label -Card $echo -Name 'echo_meta_header' -X 1176 -Y 994 -W 720 -H 18 -Text 'SEQUENCE / DEVICE INFO' -FontSize 9 -Weight 'Bold' -ForeColor $C.SecondaryT
$metaRow = @(
    @{ Label='Step Label';   Path='currentLabel';        Fmt='s3' },
    @{ Label='Op Mode';      Path='opmodearea';          Fmt='s3' },
    @{ Label='Control #';    Path='hmiControlNo';        Fmt='s5' },
    @{ Label='Cfg MP';       Path='receive.cfgMpNum';    Fmt='s3' },
    @{ Label='Cfg Length';   Path='receive.cfgLength';   Fmt='s3' }
)
$x = 1180; $i = 0
foreach ($r in $metaRow) {
    $i++
    Add-Label -Card $echo -Name "echo_meta_lbl_$i" -X $x -Y 1014 -W 140 -H 16 -Text $r.Label -FontSize 9 -ForeColor $C.LabelText
    Add-DisplayValue -Card $echo -Name "echo_meta_val_$i" -X $x -Y 1032 -W 140 -H 22 -Path $r.Path -Format $r.Fmt -FontSize 12 -HAlign 'Left'
    $x += 140
}

# Run layout self-check BEFORE saving -- catches any rule bypass
$lc = Test-LayoutSelfCheck
if ($lc.Fail -gt 0) {
    Write-Host "Layout self-check FAILED -- aborting save." -ForegroundColor Red
    return
}

# Compile
$result = Save-AndCompile
$d = 0; $e = 0
foreach ($it in $screen.ScreenItems) {
    $d += $it.Dynamizations.Count
    if ($it.GetType().Name -eq 'HmiButton') { $e += @($it.EventHandlers).Count }
}
Write-Host ""
Write-Host "Items: $($screen.ScreenItems.Count)"
Write-Host "Dynamizations: $d"
Write-Host "Button event handlers: $e"
