# test-kistler-mapping.ps1
# Unit tests: verify every LED and button on _Kistler_Press_01 maps to the
# correct field/bit of LDrive_typeKistlerHmi per memory section 6 and 8.
#
# What's checked per LED:
#   1. Element exists
#   2. Has a TagDynamization on BackColor (or Visible for end_led)
#   3. Dynamization Tag path matches expected field
#   4. The label-text matches expected human-readable name
#   5. The bit-annotation text matches expected "<field>.x<bit>" string
#
# What's checked per button:
#   1. Element exists
#   2. EventHandlers exist for expected event types
#   3. ScriptCode references "MVterminalPressKistler.move"
#   4. The bitmask in OR/AND/XOR equals 2^<expected bit>

$ErrorActionPreference = 'Stop'
[System.Reflection.Assembly]::LoadFrom("C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll") | Out-Null
$tia = [Siemens.Engineering.TiaPortal]::GetProcesses() | Select-Object -First 1
$portal  = $tia.Attach()
$project = $portal.LocalSessions[0].Project
$swT = [Siemens.Engineering.HW.Features.SoftwareContainer]
function Get-Sw($di) { $m = $di.GetType().GetMethod('GetService').MakeGenericMethod($swT); $m.Invoke($di, $null) }
function Walk($items) {
    foreach ($it in $items) { try { $svc = Get-Sw $it; if ($svc -and $svc.Software -and $svc.Software.GetType().FullName -match 'HmiUnified') { return $svc.Software } } catch {}; if ($it.DeviceItems) { $r = Walk $it.DeviceItems; if ($r) { return $r } } }
    return $null
}
$hmiSw = $null; foreach ($d in $project.Devices) { $hmiSw = Walk $d.DeviceItems; if ($hmiSw) { break } }
$null = $hmiSw.Screens.Count
$screen = $hmiSw.Screens.Find('_Kistler_Press_01')
if (-not $screen) { throw "Screen not found" }

$RootTag = 'MVterminalPressKistler'

# Canonical expectations from kistler_final.md sections 6 + 8
$expectedStatus = @(
    @{ Idx=1;  Lbl='Ready';         Field='receive.status'; Bit=2  },
    @{ Idx=2;  Lbl='OK Total';      Field='receive.status'; Bit=8  },
    @{ Idx=3;  Lbl='NOK Total';     Field='receive.status'; Bit=9  },
    @{ Idx=4;  Lbl='Drive Enabled'; Field='receive.status'; Bit=1  },
    @{ Idx=5;  Lbl='At Home Pos';   Field='receive.status'; Bit=5  },
    @{ Idx=6;  Lbl='At Reference';  Field='receive.status'; Bit=4  },
    @{ Idx=7;  Lbl='Standstill';    Field='receive.status'; Bit=6  },
    @{ Idx=8;  Lbl='Sequence End';  Field='receive.status'; Bit=12 },
    @{ Idx=9;  Lbl='Wait Request';  Field='receive.status'; Bit=3  },
    @{ Idx=10; Lbl='Kistler Auto';  Field='receive.status'; Bit=0  },
    @{ Idx=11; Lbl='SMES Active';   Field='receive.status'; Bit=13 },
    @{ Idx=12; Lbl='Safety OK';     Field='state';          Bit=2  }
)
$expectedAlarm = @(
    @{ Idx=1; Lbl='Hardware NOK';      Field='alarm'; Bit=1  },
    @{ Idx=2; Lbl='TX Fault';          Field='alarm'; Bit=2  },
    @{ Idx=3; Lbl='Drive Enable NOK';  Field='alarm'; Bit=3  },
    @{ Idx=4; Lbl='Safety NOK';        Field='alarm'; Bit=13 },
    @{ Idx=5; Lbl='Cycle Timeout';     Field='alarm'; Bit=6  },
    @{ Idx=6; Lbl='Wait Cmd Missing';  Field='alarm'; Bit=9  },
    @{ Idx=7; Lbl='Remote Inactive';   Field='alarm'; Bit=16 },
    @{ Idx=8; Lbl='Serial Mismatch';   Field='alarm'; Bit=17 }
)
$expectedButtons = @(
    @{ Name='btn_Run';      Bits=@(1);     Mode='Hold'   },
    @{ Name='btn_AckAdmin'; Bits=@(9);     Mode='Hold'   },
    @{ Name='btn_Home';     Bits=@(2);     Mode='Hold'   },
    @{ Name='btn_Ref';      Bits=@(8);     Mode='Hold'   },
    @{ Name='btn_Remote';   Bits=@(0);     Mode='Toggle' },
    @{ Name='btn_ContWait'; Bits=@(10,11); Mode='Hold'   },
    @{ Name='btn_JogPlus';  Bits=@(14);    Mode='Hold'   },
    @{ Name='btn_JogMinus'; Bits=@(15);    Mode='Hold'   }
)

# Test machinery
$tests = New-Object System.Collections.ArrayList
function Test([string]$name, [bool]$pass, [string]$detail) {
    [void]$tests.Add([pscustomobject]@{ Name=$name; Pass=$pass; Detail=$detail })
}
function Get-Item([string]$name) { foreach ($it in $screen.ScreenItems) { if ($it.Name -eq $name) { return $it } }; return $null }
function Get-PlainText([object]$item) {
    if (-not $item) { return $null }
    try {
        $mlt = $item.Text
        foreach ($mli in $mlt.Items) {
            $txt = $mli.GetAttribute('Text')
            if ($txt) {
                $stripped = ($txt -replace '<[^>]+>','').Trim()
                if ($stripped) { return $stripped }
            }
        }
    } catch {}
    return $null
}
function Get-TagDyn([object]$item, [string]$prop) {
    foreach ($d in $item.Dynamizations) {
        if ($d.PropertyName -eq $prop -and $d.GetType().Name -eq 'TagDynamization') { return $d }
    }
    return $null
}

# -------- LED tests --------
Write-Host "=== Status LEDs ==="
foreach ($e in $expectedStatus) {
    $ledName  = "led_st_$($e.Idx)"
    $labelNm  = "lbl_st_$($e.Idx)"
    $bitNm    = "bit_st_$($e.Idx)"
    $expectedTag = "$RootTag.$($e.Field)"
    $expectedBitText = "$($e.Field).x$($e.Bit)"

    $led = Get-Item $ledName
    Test "$ledName exists" ($null -ne $led) ""
    if (-not $led) { continue }

    $dyn = Get-TagDyn $led 'BackColor'
    Test "$ledName has TagDynamization on BackColor" ($null -ne $dyn) ""
    if ($dyn) {
        $actual = $dyn.GetAttribute('Tag')
        Test "$ledName Tag = $expectedTag" ($actual -eq $expectedTag) "actual=$actual"
    }

    $lbl = Get-Item $labelNm
    $lblText = Get-PlainText $lbl
    Test "$labelNm text = '$($e.Lbl)'" ($lblText -eq $e.Lbl) "actual='$lblText'"

    $bit = Get-Item $bitNm
    $bitText = Get-PlainText $bit
    Test "$bitNm text = '$expectedBitText'" ($bitText -eq $expectedBitText) "actual='$bitText'"
}

Write-Host "`n=== Alarm LEDs ==="
foreach ($e in $expectedAlarm) {
    $ledName = "led_alm_$($e.Idx)"
    $labelNm = "lbl_alm_$($e.Idx)"
    $bitNm   = "bit_alm_$($e.Idx)"
    $expectedTag = "$RootTag.$($e.Field)"
    $expectedBitText = "$($e.Field).x$($e.Bit)"

    $led = Get-Item $ledName
    Test "$ledName exists" ($null -ne $led) ""
    if (-not $led) { continue }

    $dyn = Get-TagDyn $led 'BackColor'
    Test "$ledName has TagDynamization on BackColor" ($null -ne $dyn) ""
    if ($dyn) {
        $actual = $dyn.GetAttribute('Tag')
        Test "$ledName Tag = $expectedTag" ($actual -eq $expectedTag) "actual=$actual"
    }

    $lbl = Get-Item $labelNm
    $lblText = Get-PlainText $lbl
    Test "$labelNm text = '$($e.Lbl)'" ($lblText -eq $e.Lbl) "actual='$lblText'"

    $bit = Get-Item $bitNm
    $bitText = Get-PlainText $bit
    Test "$bitNm text = '$expectedBitText'" ($bitText -eq $expectedBitText) "actual='$bitText'"
}

Write-Host "`n=== Sequence End LED ==="
$endLed = Get-Item 'end_led'
Test "end_led exists" ($null -ne $endLed) ""
if ($endLed) {
    $dyn = Get-TagDyn $endLed 'Visible'
    Test "end_led has TagDynamization on Visible" ($null -ne $dyn) ""
    if ($dyn) {
        $actual = $dyn.GetAttribute('Tag')
        $expected = "$RootTag.sequenceEnd"
        Test "end_led Tag = $expected" ($actual -eq $expected) "actual=$actual"
    }
}

# -------- Button tests --------
Write-Host "`n=== Button event handlers ==="
foreach ($eb in $expectedButtons) {
    $btn = Get-Item $eb.Name
    Test "$($eb.Name) exists" ($null -ne $btn) ""
    if (-not $btn) { continue }

    $expectedMask = 0; foreach ($b in $eb.Bits) { $expectedMask = $expectedMask -bor ([int][Math]::Pow(2, $b)) }
    $bitsStr = ($eb.Bits -join '+')

    $handlers = @($btn.EventHandlers)
    if ($eb.Mode -eq 'Toggle') {
        Test "$($eb.Name) has Tapped handler (toggle mode)" ($handlers.Count -ge 1) "handlers=$($handlers.Count)"
        if ($handlers.Count -ge 1) {
            $h = $handlers | Where-Object { "$($_.EventType)" -eq 'Tapped' } | Select-Object -First 1
            Test "$($eb.Name) has Tapped event" ($null -ne $h) ""
            if ($h) {
                $code = $h.Script.GetAttribute('ScriptCode')
                $hasMove   = $code -match [regex]::Escape("$RootTag.move")
                $hasXor    = $code -match '\^\s*1\b'
                Test "$($eb.Name) Tapped script writes to $RootTag.move" $hasMove ""
                Test "$($eb.Name) Tapped script XORs bit $bitsStr (mask=$expectedMask)" $hasXor "code='$($code -replace [char]10, '\n' -replace [char]13, '')'"
            }
        }
    } else {
        # Hold mode: expect Activated (set bit) + Deactivated (clear bit)
        $hAct  = $handlers | Where-Object { "$($_.EventType)" -eq 'Activated' }   | Select-Object -First 1
        $hDeact= $handlers | Where-Object { "$($_.EventType)" -eq 'Deactivated' } | Select-Object -First 1
        Test "$($eb.Name) has Activated handler"   ($null -ne $hAct)   ""
        Test "$($eb.Name) has Deactivated handler" ($null -ne $hDeact) ""
        if ($hAct) {
            $code = $hAct.Script.GetAttribute('ScriptCode')
            $hasMove = $code -match [regex]::Escape("$RootTag.move")
            $hasOrMask = $code -match "\|\s*$expectedMask\b"
            Test "$($eb.Name) Activated script writes to $RootTag.move" $hasMove ""
            Test "$($eb.Name) Activated script ORs mask=$expectedMask (bits $bitsStr)" $hasOrMask "code='$($code -replace [char]10, '\n' -replace [char]13, '')'"
        }
        if ($hDeact) {
            $code = $hDeact.Script.GetAttribute('ScriptCode')
            $hasMove = $code -match [regex]::Escape("$RootTag.move")
            $hasAndNot = $code -match "&\s*~$expectedMask\b"
            Test "$($eb.Name) Deactivated script writes to $RootTag.move" $hasMove ""
            Test "$($eb.Name) Deactivated script ANDs ~$expectedMask (clears bits $bitsStr)" $hasAndNot "code='$($code -replace [char]10, '\n' -replace [char]13, '')'"
        }
    }
}

# -------- Other tag-bound elements (all remaining 22 bindings) --------
Write-Host "`n=== Header / PVs / Setpoints / Program / Echo bar ==="
$otherBindings = @(
    # Header
    @{ Item='plant_io'; Prop='ProcessValue'; Path='plantidentifier' },
    @{ Item='tu_io';    Prop='ProcessValue'; Path='tecUnitNumber'   },
    @{ Item='sc_badge'; Prop='BackColor';    Path='stateColour'     },
    # F-D axis bounds
    @{ Item='fd_xmin';  Prop='ProcessValue'; Path='receive.PVcurrentXmin-X' },
    @{ Item='fd_xmax';  Prop='ProcessValue'; Path='receive.PVcurrentXmax-X' },
    @{ Item='fd_ymin';  Prop='ProcessValue'; Path='receive.PVcurrentYmin-Y' },
    @{ Item='fd_ymax';  Prop='ProcessValue'; Path='receive.PVcurrentYmax-Y' },
    # Process values
    @{ Item='pv_force'; Prop='ProcessValue'; Path='receive.PVcurrentValueY' },
    @{ Item='pv_disp';  Prop='ProcessValue'; Path='receive.PVcurrentValueX' },
    @{ Item='pv_grad';  Prop='ProcessValue'; Path='receive.PV_EO3_Gradient' },
    # Setpoints
    @{ Item='js_io';    Prop='ProcessValue'; Path='serverJogSpeedSet'    },
    @{ Item='mf_io';    Prop='ProcessValue'; Path='serverJogMaxForceSet' },
    # Program selection
    @{ Item='mp_io';    Prop='ProcessValue'; Path='manualSelectMpNum'  },
    @{ Item='seq_io';   Prop='ProcessValue'; Path='selectSequenceSet'  },
    @{ Item='pg_io';    Prop='ProcessValue'; Path='selectPageSet'      },
    # Echo bar
    @{ Item='a_mp_io';  Prop='ProcessValue'; Path='receive.mpNum'        },
    @{ Item='a_seq_io'; Prop='ProcessValue'; Path='send.selectSeqeunce'  },  # UDT typo - intentional
    @{ Item='a_pg_io';  Prop='ProcessValue'; Path='send.selectPage'      },
    @{ Item='lbl_io';   Prop='ProcessValue'; Path='currentLabel'         },
    @{ Item='om_io';    Prop='ProcessValue'; Path='opmodearea'           },
    @{ Item='cn_io';    Prop='ProcessValue'; Path='hmiControlNo'         }
)
foreach ($b in $otherBindings) {
    $expectedTag = "$RootTag.$($b.Path)"
    $item = Get-Item $b.Item
    Test "$($b.Item) exists" ($null -ne $item) ""
    if (-not $item) { continue }
    $dyn = Get-TagDyn $item $b.Prop
    Test "$($b.Item) has TagDynamization on $($b.Prop)" ($null -ne $dyn) ""
    if ($dyn) {
        $actual = $dyn.GetAttribute('Tag')
        Test "$($b.Item).$($b.Prop) Tag = $expectedTag" ($actual -eq $expectedTag) "actual=$actual"
    }
}

# -------- Coverage sanity: total binding count should be exactly 50 --------
Write-Host "`n=== Coverage ==="
$allDyns = 0
foreach ($it in $screen.ScreenItems) { $allDyns += $it.Dynamizations.Count }
Test "Total dynamizations on screen = 50" ($allDyns -eq 50) "actual=$allDyns"

# Every dynamization should point at MVterminalPressKistler.* (no rogue tags)
$badTags = @()
foreach ($it in $screen.ScreenItems) {
    foreach ($d in $it.Dynamizations) {
        if ($d.GetType().Name -eq 'TagDynamization') {
            $t = $d.GetAttribute('Tag')
            if ($t -notmatch "^$RootTag\.") { $badTags += "$($it.Name).$($d.PropertyName) -> $t" }
        }
    }
}
Test "All TagDynamizations point at $RootTag.*" ($badTags.Count -eq 0) ($badTags -join '; ')

# -------- Summary --------
$passed = $tests | Where-Object Pass
$failed = $tests | Where-Object { -not $_.Pass }

Write-Host ""
Write-Host "================================================="
Write-Host "  RESULTS: $($passed.Count) passed / $($failed.Count) failed / $($tests.Count) total"
Write-Host "================================================="

if ($failed.Count -gt 0) {
    Write-Host "`nFAILURES:" -ForegroundColor Red
    foreach ($f in $failed) { Write-Host "  X $($f.Name)  $($f.Detail)" }
}
Write-Host ""
