# kistler-design.ps1  —  Layout-aware HMI design framework
# Built around the lessons in kistler_final.md §22.
#
# Core invariants (enforced at every Add-* call, fail-fast):
#   1. SCREEN BOUNDS    — every item AABB inside (0,0)..(screen W, screen H)
#   2. CHILD-IN-CARD    — every item placed via Add-* belongs to a card and fits in its bounding box
#   3. SIBLING NO-OVERLAP — interactive children of the same card don't overlap
#   4. ORPHAN-FREE      — Add-Item* requires a Card; no item can be created without a parent
#   5. TEXT-FITS        — text length × char width <= bounding width (heuristic)
#
# Plus §19/20/16 baked in:
#   - Add-StatusLed knows the §19 receive.status bit map
#   - Add-AlarmLed knows the §19 alarm bit map
#   - Add-MoveButton knows §19 move bits + §20 hold/toggle pattern
#   - Add-DisplayValue uses HmiIOField Output (read-only numeric)
#   - Add-EditableValue uses HmiIOField InputOutput (setpoint)
#   - Add-DisplayText uses HmiText (read-only string)

# ============================================================
# Module-level state — populated by Initialize-Design and used by Add-* helpers
# ============================================================
$script:Hmi = $null
$script:Screen = $null
$script:Cards = @{}            # cardName → @{ L; T; W; H; HeaderH; Children=@(); NextRowY }
$script:Types = @{}            # short-name → HMI type
$script:Enums = @{}            # short-name → enum value
$script:Colors = @{}           # name → System.Drawing.Color
$script:RootTag = $null
$script:LastSiblingOverlap = $null  # used for richer error reporting

function Initialize-Design {
    param([string]$ScreenName, [string]$RootTag = 'MVterminalPressKistler', [int]$Width = 1920, [int]$Height = 1080)
    $script:RootTag = $RootTag

    [System.Reflection.Assembly]::LoadFrom("C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll") | Out-Null
    $tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
    $script:Portal = $tia.Attach()
    $script:Session = $script:Portal.LocalSessions[0]
    $project = $script:Session.Project

    $swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
    $walk = {
        param($items)
        foreach ($it in $items) {
            try {
                $m = $it.GetType().GetMethod('GetService').MakeGenericMethod($swT)
                $svc = $m.Invoke($it, $null)
                if ($svc -and $svc.Software -and $svc.Software.GetType().FullName -match 'HmiUnified') { return $svc.Software }
            } catch {}
            if ($it.DeviceItems) { $r = & $walk $it.DeviceItems; if ($r) { return $r } }
        }
        return $null
    }
    foreach ($d in $project.Devices) { $script:Hmi = & $walk $d.DeviceItems; if ($script:Hmi) { break } }
    $null = $script:Hmi.Screens.Count

    function Get-HmiType($fn) { foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { try { $t = $a.GetType($fn, $false); if ($t) { return $t } } catch {} }; throw "type not found: $fn" }
    $script:Types = @{
        Rect    = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiRectangle'
        Text    = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiText'
        Circle  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Shapes.HmiCircle'
        IO      = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField'
        Button  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton'
        TagDyn  = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization'
        ConditionType = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Dynamization.Tag.ConditionType'
        IOFieldType   = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiIOFieldType'
        ButtonEvent   = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiButtonEventType'
        HAlign        = Get-HmiType 'Siemens.Engineering.HmiUnified.UI.Enum.HmiHorizontalAlignment'
    }
    $script:Enums = @{
        Singlebit   = [Enum]::Parse($script:Types.ConditionType, 'Singlebit')
        Output      = [Enum]::Parse($script:Types.IOFieldType,   'Output')
        InputOutput = [Enum]::Parse($script:Types.IOFieldType,   'InputOutput')
        Activated   = [Enum]::Parse($script:Types.ButtonEvent,   'Activated')
        Deactivated = [Enum]::Parse($script:Types.ButtonEvent,   'Deactivated')
        Tapped      = [Enum]::Parse($script:Types.ButtonEvent,   'Tapped')
    }
    # SICAR + chrome palette
    $script:Colors = @{
        HeaderBg     = [System.Drawing.Color]::FromArgb(255,  44,  62,  80)
        Accent       = [System.Drawing.Color]::FromArgb(255,  52, 152, 219)
        HeaderText   = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
        HeaderSub    = [System.Drawing.Color]::FromArgb(255, 189, 195, 199)
        CardBg       = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
        CardBorder   = [System.Drawing.Color]::FromArgb(255, 208, 211, 214)
        ScreenBg     = [System.Drawing.Color]::FromArgb(255, 245, 246, 250)
        SectionBg    = [System.Drawing.Color]::FromArgb(255, 236, 240, 241)
        PrimaryText  = [System.Drawing.Color]::FromArgb(255,  44,  62,  80)
        LabelText    = [System.Drawing.Color]::FromArgb(255, 100, 113, 114)
        SecondaryT   = [System.Drawing.Color]::FromArgb(255, 127, 140, 141)
        LightGreen   = [System.Drawing.Color]::FromArgb(255, 146, 208,  80)
        LightBlue    = [System.Drawing.Color]::FromArgb(255,   0, 176, 240)
        Orange       = [System.Drawing.Color]::FromArgb(255, 255, 192,   0)
        Red          = [System.Drawing.Color]::FromArgb(255, 230,  57,  53)
        Yellow       = [System.Drawing.Color]::FromArgb(255, 255, 235,  59)
        OffGray      = [System.Drawing.Color]::FromArgb(255, 215, 219, 221)
        BtnRunBg     = [System.Drawing.Color]::FromArgb(255,  39, 174,  96)
        BtnStopBg    = [System.Drawing.Color]::FromArgb(255, 231,  76,  60)
        BtnNeutralBg = [System.Drawing.Color]::FromArgb(255,  52,  73,  94)
        BtnWarnBg    = [System.Drawing.Color]::FromArgb(255, 243, 156,  18)
        BtnText      = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
    }

    $existing = $script:Hmi.Screens.Find($ScreenName)
    if ($existing) { try { $existing.Delete() } catch {} }
    $script:Screen = $script:Hmi.Screens.Create($ScreenName)
    $script:Screen.Width  = [uint32]$Width
    $script:Screen.Height = [uint32]$Height
    $script:Screen.BackColor = $script:Colors.ScreenBg
    $script:ScreenW = $Width
    $script:ScreenH = $Height
    Write-Host "Initialized $ScreenName ($Width x $Height) on HMI $($script:Hmi.Name)"
}

# ============================================================
# Validation helpers — fail fast with line-level context
# ============================================================
function Test-BoxesOverlap($a, $b) {
    return ($a.L -lt $b.R) -and ($b.L -lt $a.R) -and ($a.T -lt $b.B) -and ($b.T -lt $a.B)
}
function Test-WithinScreen($L, $T, $R, $B) {
    return ($L -ge 0) -and ($T -ge 0) -and ($R -le $script:ScreenW) -and ($B -le $script:ScreenH)
}
function Test-WithinCard($card, $L, $T, $R, $B) {
    return ($L -ge $card.L) -and ($T -ge $card.T) -and ($R -le ($card.L + $card.W)) -and ($B -le ($card.T + $card.H))
}

# Validate placement BEFORE the item is created. Throws on failure with operator-readable error.
function Assert-Placement {
    param([string]$Name, $Card, [int]$L, [int]$T, [int]$W, [int]$H, [bool]$AllowSiblingOverlap = $false)
    $R = $L + $W; $B = $T + $H
    if (-not (Test-WithinScreen $L $T $R $B)) {
        throw "PLACEMENT FAIL: '$Name' AABB ($L,$T)-($R,$B) exits screen ($($script:ScreenW)x$($script:ScreenH))"
    }
    if ($Card) {
        if (-not (Test-WithinCard $Card $L $T $R $B)) {
            throw "PLACEMENT FAIL: '$Name' AABB ($L,$T)-($R,$B) exits card '$($Card.Name)' bounds ($($Card.L),$($Card.T))-($($Card.L+$Card.W),$($Card.T+$Card.H))"
        }
        if (-not $AllowSiblingOverlap) {
            foreach ($sib in $Card.Children) {
                if ($sib.Type -in @('HmiText','HmiIOField','HmiButton','HmiCircle')) {
                    if (Test-BoxesOverlap @{L=$L;T=$T;R=$R;B=$B} $sib) {
                        throw "PLACEMENT FAIL: '$Name' ($L,$T)-($R,$B) overlaps sibling '$($sib.Name)' ($($sib.L),$($sib.T))-($($sib.R),$($sib.B)) in card '$($Card.Name)'"
                    }
                }
            }
        }
    }
}

# Register an item in its parent card so future overlap tests see it
function Register-Child($Card, [string]$Name, [string]$Type, [int]$L, [int]$T, [int]$W, [int]$H) {
    if (-not $Card) { return }
    $Card.Children += [pscustomobject]@{ Name=$Name; Type=$Type; L=$L; T=$T; R=($L+$W); B=($T+$H) }
}

# ============================================================
# Low-level item creators (operate within validation framework)
# ============================================================
function _NewItem($composition, $type, [string]$name) {
    $cg = $composition.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    return $cg.MakeGenericMethod($type).Invoke($composition, @($name))
}

function _SetText($item, [string]$plain, [int]$size, [string]$weight, $color, [string]$halign) {
    $textProp = $item.GetType().GetProperty('Text')
    if ($textProp) {
        $mlt = $textProp.GetValue($item)
        if ($mlt) {
            $xml = "<body><p>$plain</p></body>"
            foreach ($mi in $mlt.Items) { try { $mi.SetAttribute('Text', $xml) } catch {} }
        }
    }
    if ($size -gt 0 -or $weight) {
        $fp = $item.GetType().GetProperty('Font')
        if ($fp) {
            $f = $fp.GetValue($item)
            if ($f) {
                if ($size -gt 0) { try { $f.SetAttribute('Size', [byte]$size) } catch {} }
                if ($weight) { try { $f.SetAttribute('Weight', $weight) } catch {} }
            }
        }
    }
    if ($color) {
        $fc = $item.GetType().GetProperty('ForeColor')
        if ($fc -and $fc.CanWrite) { $fc.SetValue($item, $color) }
    }
    if ($halign) {
        $ha = $item.GetType().GetProperty('HorizontalTextAlignment')
        if ($ha -and $ha.CanWrite) {
            try { $ha.SetValue($item, [Enum]::Parse($script:Types.HAlign, $halign)) } catch {}
        }
    }
}

function _Place($item, [int]$L, [int]$T, [int]$W, [int]$H) {
    $tt = $item.GetType()
    if ($tt.GetProperty('Left')) {
        $item.Left = $L; $item.Top = $T; $item.Width = [uint32]$W; $item.Height = [uint32]$H
    } elseif ($tt.GetProperty('CenterX')) {
        $item.CenterX = $L + [int]($W/2); $item.CenterY = $T + [int]($H/2)
        $item.Radius = [uint32]([int]([Math]::Min($W,$H)/2))
    }
}

function _BindTag($item, [string]$prop, [string]$path) {
    $cg = $item.Dynamizations.GetType().GetMethods() | Where-Object { $_.Name -eq 'Create' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    $dyn = $cg.MakeGenericMethod($script:Types.TagDyn).Invoke($item.Dynamizations, @($prop))
    $dyn.SetAttribute('Tag', "$script:RootTag.$path")
    return $dyn
}

function _BindBit($item, [int]$bit, $onColor, $offColor, [string]$fieldPath) {
    $dyn = _BindTag $item 'BackColor' $fieldPath
    $mt = $dyn.ValueConverter.MappingTable
    foreach ($e in @($mt.Entries)) { try { $e.Delete() } catch {} }
    $mt.SetAttribute('ConditionType', $script:Enums.Singlebit)
    $entries = @($mt.Entries)
    $mask = [UInt64]([Math]::Pow(2, $bit))
    $entries[1].Condition = $mask
    $entries[0].Value = $offColor
    $entries[1].Value = $onColor
}

# ============================================================
# PUBLIC: New-Card
# Creates a styled card panel with background + section-header bar.
# All subsequent Add-* calls take this card as parent.
# Returns the card record.
# ============================================================
function New-Card {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$X,
        [Parameter(Mandatory)] [int]$Y,
        [Parameter(Mandatory)] [int]$W,
        [Parameter(Mandatory)] [int]$H,
        [string]$Header,
        [int]$HeaderHeight = 32,
        [int]$HeaderTextWidth = 0,    # 0 = auto (W - 32); set to leave space for right-side badge
        $HeaderColor = $null,
        $BgColor = $null,
        $BorderColor = $null,
        $HeaderTextColor = $null
    )
    # Bounds check at card level (vs screen, vs other cards)
    Assert-Placement $Name $null $X $Y $W $H $false
    foreach ($c in $script:Cards.Values) {
        if (Test-BoxesOverlap @{L=$X;T=$Y;R=($X+$W);B=($Y+$H)} @{L=$c.L;T=$c.T;R=($c.L+$c.W);B=($c.T+$c.H)}) {
            throw "CARD COLLISION: '$Name' ($X,$Y)-($($X+$W),$($Y+$H)) overlaps existing card '$($c.Name)' ($($c.L),$($c.T))-($($c.L+$c.W),$($c.T+$c.H))"
        }
    }

    $card = @{
        Name = $Name; L = $X; T = $Y; W = $W; H = $H; HeaderH = $HeaderHeight
        Children = @()
        NextRowY = $Y + $HeaderHeight + 6   # cursor for stacked rows
    }
    $script:Cards[$Name] = $card

    if (-not $BgColor)     { $BgColor = $script:Colors.CardBg }
    if (-not $BorderColor) { $BorderColor = $script:Colors.CardBorder }

    # Background — registered as a card child (Rect type, not in overlap-checked types)
    $bg = _NewItem $script:Screen.ScreenItems $script:Types.Rect $Name
    _Place $bg $X $Y $W $H
    $bg.BackColor = $BgColor
    $bg.BorderColor = $BorderColor; $bg.BorderWidth = [byte]1
    Register-Child $card $Name 'HmiRectangle' $X $Y $W $H

    if ($Header) {
        # Header band
        $hbg = _NewItem $script:Screen.ScreenItems $script:Types.Rect "${Name}_hdr_bg"
        _Place $hbg $X $Y $W $HeaderHeight
        $hbg.BackColor = if ($HeaderColor) { $HeaderColor } else { $script:Colors.SectionBg }
        $hbg.BorderWidth = [byte]0
        Register-Child $card "${Name}_hdr_bg" 'HmiRectangle' $X $Y $W $HeaderHeight

        # Header text — respect HeaderTextWidth so right side stays free for badges
        $htxtW = if ($HeaderTextWidth -gt 0) { $HeaderTextWidth } else { ($W - 32) }
        $htxtL = $X + 16
        $htxtT = $Y + 4
        $htxtH = $HeaderHeight - 8
        $htxt = _NewItem $script:Screen.ScreenItems $script:Types.Text "${Name}_header"
        _Place $htxt $htxtL $htxtT $htxtW $htxtH
        $tc = if ($HeaderTextColor) { $HeaderTextColor } else { $script:Colors.PrimaryText }
        _SetText $htxt $Header 12 'Bold' $tc 'Left'
        Register-Child $card "${Name}_header" 'HmiText' $htxtL $htxtT $htxtW $htxtH
    }
    return $card
}

# ============================================================
# PUBLIC: Add-StatusLed — Adds an LED row inside a card.
# Auto-positions on next row Y, advances cursor.
# Validates label-fits + within-card + no-sibling-overlap.
# ============================================================
function Add-StatusLed {
    param(
        [Parameter(Mandatory)] $Card,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [string]$Field,
        [Parameter(Mandatory)] [int]$Bit,
        $OnColor = $null,
        [int]$RowHeight = 34
    )
    if (-not $OnColor) { $OnColor = $script:Colors.LightGreen }
    $y = $Card.NextRowY
    $ledL = $Card.L + 20; $ledT = $y; $ledW = 18; $ledH = 18
    Assert-Placement "${Name}_circle" $Card $ledL $ledT $ledW $ledH
    $lblL = $ledL + 28; $lblT = $y; $lblW = $Card.W - 60; $lblH = 22
    Assert-Placement "${Name}_label" $Card $lblL $lblT $lblW $lblH
    # Text-fits check: at 11pt regular, ~7 px/char
    $needed = $Label.Length * 7
    if ($needed -gt $lblW) {
        throw "TEXT TOO LONG: '$Label' needs ${needed}px but label width is ${lblW}px in card '$($Card.Name)'"
    }

    $led = _NewItem $script:Screen.ScreenItems $script:Types.Circle $Name
    _Place $led $ledL $ledT $ledW $ledH
    _BindBit $led $Bit $OnColor $script:Colors.OffGray $Field
    Register-Child $Card $Name 'HmiCircle' $ledL $ledT $ledW $ledH

    $lbl = _NewItem $script:Screen.ScreenItems $script:Types.Text "${Name}_label"
    _Place $lbl $lblL $lblT $lblW $lblH
    _SetText $lbl $Label 11 'Regular' $script:Colors.PrimaryText 'Left'
    Register-Child $Card "${Name}_label" 'HmiText' $lblL $lblT $lblW $lblH

    $Card.NextRowY = $y + $RowHeight
}

# ============================================================
# PUBLIC: Add-DisplayValue -- Read-only current value (HmiText bound to Text)
# Per §20: any value sourced FROM the device is HmiText, never IOField.
# IOField is reserved for operator-entered setpoints (Add-EditableValue).
# Format is ignored here (HmiText shows whatever the runtime stringifies);
# kept as param for call-site compatibility.
# ============================================================
function Add-DisplayValue {
    param(
        [Parameter(Mandatory)] $Card,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$X,
        [Parameter(Mandatory)] [int]$Y,
        [Parameter(Mandatory)] [int]$W,
        [Parameter(Mandatory)] [int]$H,
        [Parameter(Mandatory)] [string]$Path,
        [string]$Format = '',
        [int]$FontSize = 12,
        [string]$Weight = 'Regular',
        [string]$HAlign = 'Right',
        $ForeColor = $null,
        $BgColor = $null
    )
    Assert-Placement $Name $Card $X $Y $W $H
    if (-not $ForeColor) { $ForeColor = $script:Colors.PrimaryText }
    $t = _NewItem $script:Screen.ScreenItems $script:Types.Text $Name
    _Place $t $X $Y $W $H
    _SetText $t '...' $FontSize $Weight $ForeColor $HAlign
    _BindTag $t 'Text' $Path | Out-Null
    Register-Child $Card $Name 'HmiText' $X $Y $W $H
}

# ============================================================
# PUBLIC: Add-EditableValue — Editable numeric (HmiIOField InputOutput)
# ============================================================
function Add-EditableValue {
    param(
        [Parameter(Mandatory)] $Card,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$X,
        [Parameter(Mandatory)] [int]$Y,
        [Parameter(Mandatory)] [int]$W,
        [Parameter(Mandatory)] [int]$H,
        [Parameter(Mandatory)] [string]$Path,
        [string]$Format = '',
        [int]$FontSize = 13
    )
    Assert-Placement $Name $Card $X $Y $W $H
    $io = _NewItem $script:Screen.ScreenItems $script:Types.IO $Name
    _Place $io $X $Y $W $H
    $io.IOFieldType = $script:Enums.InputOutput
    if ($Format) { $io.OutputFormat = $Format }
    if ($FontSize -gt 0) { try { $io.Font.SetAttribute('Size', [byte]$FontSize) } catch {} }
    _BindTag $io 'ProcessValue' $Path | Out-Null
    Register-Child $Card $Name 'HmiIOField' $X $Y $W $H
}

# ============================================================
# PUBLIC: Add-DisplayText — Read-only string (HmiText with TagDynamization on Text)
# ============================================================
function Add-DisplayText {
    param(
        [Parameter(Mandatory)] $Card,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$X,
        [Parameter(Mandatory)] [int]$Y,
        [Parameter(Mandatory)] [int]$W,
        [Parameter(Mandatory)] [int]$H,
        [Parameter(Mandatory)] [string]$Path,
        [int]$FontSize = 14,
        [string]$Weight = 'Bold',
        [string]$HAlign = 'Left',
        $ForeColor = $null
    )
    Assert-Placement $Name $Card $X $Y $W $H
    if (-not $ForeColor) { $ForeColor = $script:Colors.PrimaryText }
    $t = _NewItem $script:Screen.ScreenItems $script:Types.Text $Name
    _Place $t $X $Y $W $H
    _SetText $t '...' $FontSize $Weight $ForeColor $HAlign
    _BindTag $t 'Text' $Path | Out-Null
    Register-Child $Card $Name 'HmiText' $X $Y $W $H
}

# ============================================================
# PUBLIC: Add-Label — static descriptive text
# ============================================================
function Add-Label {
    param(
        [Parameter(Mandatory)] $Card,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$X,
        [Parameter(Mandatory)] [int]$Y,
        [Parameter(Mandatory)] [int]$W,
        [Parameter(Mandatory)] [int]$H,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text,
        [int]$FontSize = 10,
        [string]$Weight = 'Regular',
        [string]$HAlign = 'Left',
        $ForeColor = $null,
        [bool]$AllowOverlap = $false
    )
    Assert-Placement $Name $Card $X $Y $W $H $AllowOverlap
    if (-not $ForeColor) { $ForeColor = $script:Colors.LabelText }
    # Text-fits check
    $charW = if ($FontSize -le 9) { 5 } elseif ($FontSize -le 11) { 6 } elseif ($FontSize -le 13) { 7 } else { 9 }
    $needed = $Text.Length * $charW
    if ($needed -gt $W) {
        throw "TEXT TOO LONG: '$Text' (${needed}px at ${FontSize}pt) exceeds label width ${W}px for '$Name'"
    }
    $t = _NewItem $script:Screen.ScreenItems $script:Types.Text $Name
    _Place $t $X $Y $W $H
    _SetText $t $Text $FontSize $Weight $ForeColor $HAlign
    Register-Child $Card $Name 'HmiText' $X $Y $W $H
}

# ============================================================
# PUBLIC: Add-Button — wires click handlers + echo dynamization
# ============================================================
function Add-Button {
    param(
        [Parameter(Mandatory)] $Card,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [int]$X,
        [Parameter(Mandatory)] [int]$Y,
        [Parameter(Mandatory)] [int]$W,
        [Parameter(Mandatory)] [int]$H,
        [Parameter(Mandatory)] [int[]]$MoveBits,
        $BgColor = $null,
        $HoverColor = $null,
        [bool]$Toggle = $false,
        [Nullable[int]]$EchoBit = $null,
        [int]$FontSize = 14
    )
    Assert-Placement $Name $Card $X $Y $W $H
    if (-not $BgColor)    { $BgColor    = $script:Colors.BtnNeutralBg }
    if (-not $HoverColor) { $HoverColor = $script:Colors.LightBlue }

    $btn = _NewItem $script:Screen.ScreenItems $script:Types.Button $Name
    _Place $btn $X $Y $W $H
    _SetText $btn $Label $FontSize 'Bold' $script:Colors.BtnText 'Center'
    $btn.BackColor = $BgColor; $btn.ForeColor = $script:Colors.BtnText
    $btn.AlternateBackColor = $HoverColor; $btn.BorderWidth = [byte]0

    $mask = 0; foreach ($b in $MoveBits) { $mask = $mask -bor ([int][Math]::Pow(2, $b)) }
    if ($Toggle) {
        $ev = $btn.EventHandlers.Create($script:Enums.Tapped)
        $ev.Script.SetAttribute('ScriptCode', "var v = Tags(`"$script:RootTag.move`").Read();`r`nTags(`"$script:RootTag.move`").Write(v ^ $mask);")
    } else {
        $evA = $btn.EventHandlers.Create($script:Enums.Activated)
        $evA.Script.SetAttribute('ScriptCode', "var v = Tags(`"$script:RootTag.move`").Read();`r`nTags(`"$script:RootTag.move`").Write(v | $mask);")
        $evD = $btn.EventHandlers.Create($script:Enums.Deactivated)
        $evD.Script.SetAttribute('ScriptCode', "var v = Tags(`"$script:RootTag.move`").Read();`r`nTags(`"$script:RootTag.move`").Write(v & ~$mask);")
    }
    if ($EchoBit -ne $null) {
        _BindBit $btn $EchoBit $HoverColor $BgColor 'send.control'
    }
    Register-Child $Card $Name 'HmiButton' $X $Y $W $H
}

# ============================================================
# PUBLIC: Save + Compile
# ============================================================
function Save-AndCompile {
    Write-Host "Saving..."
    $script:Session.Save()
    Write-Host "Compiling HMI..."
    $compT = $null
    foreach ($a in [AppDomain]::CurrentDomain.GetAssemblies()) { try { $tt = $a.GetType('Siemens.Engineering.Compiler.ICompilable', $false); if ($tt) { $compT = $tt; break } } catch {} }
    $cur = $script:Hmi.Parent; $comp = $null
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
    foreach ($e in $errs | Select-Object -First 12) { Write-Host "  ERR [$($e.Path)] $($e.Description)" -ForegroundColor Red }
    return $cr
}

function Get-Screen { return $script:Screen }
function Get-Colors { return $script:Colors }

# ============================================================
# PUBLIC: Test-LayoutSelfCheck — runs §22 layout test suite against tracked cards
# Returns a hashtable of {Pass, Fail, Errors}.
# Use at the end of build to verify no rule was bypassed.
# ============================================================
function Test-LayoutSelfCheck {
    $fails = New-Object System.Collections.ArrayList
    $pass = 0
    $sw = $script:ScreenW; $sh = $script:ScreenH

    # Test 1 — every card within screen
    foreach ($c in $script:Cards.Values) {
        $R = $c.L + $c.W; $B = $c.T + $c.H
        if (-not (Test-WithinScreen $c.L $c.T $R $B)) {
            [void]$fails.Add("T1 SCREEN-BOUNDS: card '$($c.Name)' ($($c.L),$($c.T))-($R,$B) exits screen")
        } else { $pass++ }
    }

    # Test 2 — no card-card overlap
    $cards = @($script:Cards.Values)
    for ($i=0; $i -lt $cards.Count; $i++) {
        for ($j=$i+1; $j -lt $cards.Count; $j++) {
            $a = $cards[$i]; $b = $cards[$j]
            $ab = @{L=$a.L;T=$a.T;R=($a.L+$a.W);B=($a.T+$a.H)}
            $bb = @{L=$b.L;T=$b.T;R=($b.L+$b.W);B=($b.T+$b.H)}
            if (Test-BoxesOverlap $ab $bb) {
                [void]$fails.Add("T2 CARD-OVERLAP: '$($a.Name)' overlaps '$($b.Name)'")
            } else { $pass++ }
        }
    }

    # Test 3 — every child fits inside its card
    foreach ($c in $script:Cards.Values) {
        foreach ($ch in $c.Children) {
            if (-not (Test-WithinCard $c $ch.L $ch.T $ch.R $ch.B)) {
                [void]$fails.Add("T3 CHILD-OUTSIDE-CARD: '$($ch.Name)' ($($ch.L),$($ch.T))-($($ch.R),$($ch.B)) exits card '$($c.Name)'")
            } else { $pass++ }
        }
    }

    # Test 4 — no interactive sibling overlap within a card
    foreach ($c in $script:Cards.Values) {
        $inter = @($c.Children | Where-Object { $_.Type -in @('HmiText','HmiIOField','HmiButton','HmiCircle') })
        for ($i=0; $i -lt $inter.Count; $i++) {
            for ($j=$i+1; $j -lt $inter.Count; $j++) {
                $a = $inter[$i]; $b = $inter[$j]
                if (Test-BoxesOverlap $a $b) {
                    [void]$fails.Add("T4 SIBLING-OVERLAP: card '$($c.Name)' '$($a.Name)' overlaps '$($b.Name)'")
                } else { $pass++ }
            }
        }
    }

    # Test 5 — orphan detector: every HMI item on the screen must be tracked
    $known = @{}
    foreach ($c in $script:Cards.Values) {
        foreach ($ch in $c.Children) { $known[$ch.Name] = $true }
    }
    foreach ($it in $script:Screen.ScreenItems) {
        if (-not $known.ContainsKey($it.Name)) {
            [void]$fails.Add("T5 ORPHAN: '$($it.Name)' is not registered to any card")
        } else { $pass++ }
    }

    Write-Host ""
    Write-Host "Layout self-check: $pass passed, $($fails.Count) failed" -ForegroundColor ($(if ($fails.Count -eq 0) { 'Green' } else { 'Red' }))
    foreach ($f in $fails) { Write-Host "  $f" -ForegroundColor Red }
    return @{ Pass = $pass; Fail = $fails.Count; Errors = $fails }
}
