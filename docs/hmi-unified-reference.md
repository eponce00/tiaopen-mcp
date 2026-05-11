# HMI Unified (WinCC Unified) — Openness API Reference

This document captures verified patterns for automating **WinCC Unified** HMI screens via the TIA Portal Openness API (V20). All findings were discovered through live testing against a real project.

> **Scope:** This covers the `HmiSoftware` API (RT Unified / WinCC Unified), NOT the older `HmiTarget` API for Comfort Panels.

---

## Table of Contents

1. [Type Namespaces](#1-type-namespaces)
2. [Finding HmiSoftware](#2-finding-hmisoftware)
3. [Connections](#3-connections)
4. [Tags](#4-tags)
5. [Screens](#5-screens)
6. [Screen Items](#6-screen-items)
7. [Text and MultilingualText](#7-text-and-multilingualtext)
8. [Events (Button Press, etc.)](#8-events-button-press-etc)
9. [Dynamizations (Tag Bindings)](#9-dynamizations-tag-bindings)
10. [Runtime Settings](#10-runtime-settings)
11. [Property Quick Reference](#11-property-quick-reference)
12. [Known Limitations](#12-known-limitations)

---

## 1. Type Namespaces

The Openness manual references `Siemens.Engineering.HmiUnified.ModernUI.*`, but the **actual runtime types** in V20 live under `Siemens.Engineering.HmiUnified.UI`:

| Item Type | Actual Runtime Type |
|---|---|
| Text | `Siemens.Engineering.HmiUnified.UI.Shapes.HmiText` |
| Button | `Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton` |
| IO Field | `Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField` |
| Event Handler | `Siemens.Engineering.HmiUnified.UI.Events.HmiButtonEventHandler` |
| Dynamization | `Siemens.Engineering.HmiUnified.UI.Dynamization.TagDynamization` |

**Resolve via assembly:**
```powershell
$asm = [System.Reflection.Assembly]::LoadFrom($dllCore)
$typeHmiText    = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Shapes.HmiText')
$typeHmiButton  = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton')
$typeHmiIOField = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField')
```

---

## 2. Finding HmiSoftware

Same device-tree walk as `PlcSoftware`, cast to `[Siemens.Engineering.HmiUnified.HmiSoftware]`:

```powershell
$hmiSoftware = $null
function Walk($items) {
    foreach ($item in $items) {
        $svc = Invoke-GenericGetService $item ([Siemens.Engineering.HW.Features.SoftwareContainer])
        if ($svc -and $svc.Software -is [Siemens.Engineering.HmiUnified.HmiSoftware]) {
            $script:hmiSoftware = $svc.Software
        }
        if ($item.DeviceItems -and $item.DeviceItems.Count -gt 0) { Walk $item.DeviceItems }
    }
}
foreach ($device in $project.Devices) { Walk $device.DeviceItems }
```

---

## 3. Connections

### Create
```powershell
$conn = $hmiSoftware.Connections.Create("HMI_Connection_1")
```

### Connection Properties
| Property | Type | Writable | Notes |
|---|---|---|---|
| `Name` | String | Yes | |
| `CommunicationDriver` | String | Yes | e.g. `"SIMATIC S7 300/400"` |
| `DisabledAtStartup` | Boolean | Yes | Default: `True` |
| `InitialAddress` | String | Yes | Full connection config string |
| `Partner` | String | **No** | Read-only; derived from driver config |
| `Station` | String | **No** | Read-only |
| `DriverProperties` | Collection | Yes | 10 properties (IP, rack, slot, etc.) |

### DriverProperties
Access individual driver properties via the `DriverProperties` collection:
```powershell
foreach ($dp in $conn.DriverProperties) {
    Write-Host "$($dp.Name) = $($dp.Value)"
}
```

Typical properties found:
- Host IP address
- Access point (e.g. `S7ONLINE`)
- PLC IP address
- PLC Rack
- PLC Slot
- PLC Expansion Slot
- Cyclic operation flag

### Connection is a STRING on tags
The `Connection` property on `HmiTag` is a **String**, not an object reference:
```powershell
$tag.Connection = "HMI_Connection_1"   # Works
$tag.Connection = $conn                # FAILS — type mismatch
```

---

## 4. Tags

### Tag Table
```powershell
$hmiTagTable = $hmiSoftware.TagTables.Create("MotorVFD")
```

### Create Tag
```powershell
$hmiTag = $hmiTagTable.Tags.Create("Motor_Start")
```

### Tag Properties
| Property | Type | Writable | Notes |
|---|---|---|---|
| `Name` | String | Read-only | |
| `DataType` | String | Yes | e.g. `"Bool"`, `"Int"`, `"Real"` |
| `Connection` | String | Yes | Set to connection name: `"HMI_Connection_1"` |
| `Scope` | HmiTagScope | Yes | `System` (0) or `Session` (1) |
| `TagType` | String | Read-only | `"Simple"` |
| `AccessMode` | String | Read-only | `"SymbolicAccess"` |
| `AcquisitionCycle` | String | Read-only | `"T1s"` |
| `AcquisitionMode` | String | Read-only | `"CyclicOnUse"` |
| `Address` | String | **No** | Disabled for external tags |
| `PlcTag` | String | Yes | PLC tag path; **validates against PLC** |
| `PlcName` | String | Read-only | |
| `HmiDataType` | String | Read-only | HMI-side data type |
| `HmiStartValue` | Int32 | Read-only | 0 |
| `HmiEndValue` | Int32 | Read-only | 100 |
| `PlcStartValue` | Int32 | Read-only | 0 |
| `PlcEndValue` | Int32 | Read-only | 10 |
| `LinearScaling` | Boolean | Yes | |
| `Persistent` | Boolean | Yes | |
| `Comment` | MultilingualText | Yes | XML-wrapped text |
| `SubstituteValue` | Object | Yes | Fallback value config |

### Setting `PlcTag`
```powershell
$tag.PlcTag = "MotorVFD.Motor_Start"
```
**Important:** This validates that the PLC tag exists. If the connection is not properly configured or the tag does not exist in the PLC, it throws: `"The controller tag MotorVFD.Motor_Start was not found."`

### Tag Scope Enum
```
System  = 0
Session = 1
```

---

## 5. Screens

### Create
```powershell
$screen = $hmiSoftware.Screens.Create("MotorControl")
$screen.Width  = [uint32]1280
$screen.Height = [uint32]800
```

**Note:** Width/Height require `[uint32]`, not `[int32]`.

### Find / Delete
```powershell
$screen = $hmiSoftware.Screens.Find("MotorControl")
$screen.Delete()
```

---

## 6. Screen Items

### Generic Create via Reflection
`ScreenItems.Create<T>()` is overloaded. Disambiguate by filtering for the generic method definition:

```powershell
function Invoke-GenericCreate($composition, $type, $name) {
    $createMethod = $composition.GetType().GetMethods() |
        Where-Object { $_.Name -eq "Create" -and $_.IsGenericMethodDefinition } |
        Select-Object -First 1
    $generic = $createMethod.MakeGenericMethod($type)
    return $generic.Invoke($composition, @($name))
}

$btn = Invoke-GenericCreate $screen.ScreenItems $typeHmiButton "Btn_Start"
$btn.Left   = 50
$btn.Top    = 100
$btn.Width  = [uint32]150
$btn.Height = [uint32]60
```

### Common Item Properties
| Property | Type | Writable | Notes |
|---|---|---|---|
| `Name` | String | Read-only | Set at creation time |
| `Left` | Int32 | Yes | |
| `Top` | Int32 | Yes | |
| `Width` | UInt32 | Yes | Must cast to `[uint32]` |
| `Height` | UInt32 | Yes | Must cast to `[uint32]` |
| `Visible` | Boolean | Yes | |
| `Enabled` | Boolean | Yes | |
| `Opacity` | Single | Yes | 0.0–1.0 |
| `RotationAngle` | Int16 | Yes | |
| `TabIndex` | UInt16 | Yes | |
| `ToolTipText` | MultilingualText | Yes | XML-wrapped |

### Button-Specific Properties
| Property | Type | Writable | Notes |
|---|---|---|---|
| `Text` | MultilingualText | Yes | Normal state text |
| `AlternateText` | MultilingualText | Yes | Pressed state text |
| `BackColor` | Color | Yes | Default background |
| `AlternateBackColor` | Color | Yes | Pressed background |
| `BorderColor` | Color | Yes | |
| `BorderWidth` | Byte | Yes | |
| `ForeColor` | Color | Yes | Text color |
| `Graphic` | String | Yes | Image resource path |
| `AlternateGraphic` | String | Yes | Pressed image |
| `HotKey` | UInt16 | Yes | Keyboard shortcut |
| `EventHandlers` | HmiButtonEventHandlerComposition | Yes | Add press events |
| `Dynamizations` | DynamizationBaseComposition | Yes | Tag bindings |

### IO Field-Specific Properties
| Property | Type | Writable | Notes |
|---|---|---|---|
| `ProcessValue` | String | Yes | Initial value |
| `InputBehavior` | HmiInputBehaviorPart | Yes | Input mode config |
| `OutputFormat` | String | Yes | Display format |
| `EventHandlers` | HmiIOFieldEventHandlerComposition | Yes | Events |
| `Dynamizations` | DynamizationBaseComposition | Yes | Tag bindings |

---

## 7. Text and MultilingualText

HMI Unified `Text` properties are **MultilingualText**, not plain strings. Must be XML-wrapped:

```powershell
function Set-XmlText($item, $plainText) {
    $textProp = $item.GetType().GetProperty("Text")
    $mlt = $textProp.GetValue($item, $null)
    $mlt.Items[0].Text = "<body><p>$plainText</p></body>"
}

Set-XmlText $btn "START"
```

**Plain strings fail** with: `"The argument 'text' has an invalid format."`

### MultilingualTextItem Properties
| Property | Type | Notes |
|---|---|---|
| `Culture` | String | Language culture code (e.g. `""` for default) |
| `Text` | String | XML-wrapped content |

---

## 8. Events (Button Press, etc.)

### Button Event Types
```
None          = 0
Activated     = 1000   # Press/click
Deactivated   = 1001
Tapped        = 1003
KeyDown       = 1006
KeyUp         = 1007
Down          = 1008   # Mouse down
Up            = 1010   # Mouse up
ContextTapped = 1011
```

### Create Event Handler
```powershell
$btnEventType = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Enum.HmiButtonEventType')
$activatedValue = [Enum]::Parse($btnEventType, "Activated")
$ev = $btn.EventHandlers.Create($activatedValue)
```

### Event Handler Properties
| Property | Type | Writable | Notes |
|---|---|---|---|
| `EventType` | HmiButtonEventType | Read-only | The event that triggered this handler |
| `Script` | IHmiScript | Yes | Script assigned to this event |

**Note:** There is **no** `SystemFunction` property on Unified event handlers. Actions are implemented via `Script` (VBScript/C# script modules).

### IO Field Event Types
Same as Button but without `Down` and `Up`:
```
None, Activated, Deactivated, Tapped, KeyDown, KeyUp, ContextTapped
```

---

## 9. Dynamizations (Tag Bindings)

### What Dynamizations Are
Dynamizations bind a screen item property to an HMI tag value at runtime. For example, binding a button's `Visible` property to a Bool tag.

### Create Dynamization
```powershell
$dyn = $item.Dynamizations.Create("PropertyName")
```

**Parameter:** The property name to dynamize (e.g. `"Visible"`, `"ProcessValue"`, `"BackColor"`).

### Dynamization Properties
| Property | Type | Writable | Notes |
|---|---|---|---|
| `DynamizationType` | String | Read-only | `"Tag"` |
| `PropertyName` | String | Read-only | The property being dynamized |
| `Tag` | HmiTag | Yes | The tag to bind |
| `ReadOnly` | Boolean | Read-only | |
| `UseIndirectAddressing` | Boolean | Yes | |

### Bind Tag to Item Property
```powershell
$dyn = $ioSet.Dynamizations.Create("ProcessValue")
$dyn.Tag = $hmiTag   # $hmiTag is an HmiTag object
```

### Pre-existing Dynamizations
Some items may already have a default dynamization (e.g. `Graphic` on buttons). Check `$item.Dynamizations.Count` before creating new ones.

---

## 10. Runtime Settings

### Access
```powershell
$rs = $hmiSoftware.RuntimeSettings
```

### Writable Properties
| Property | Type | Notes |
|---|---|---|
| `StartScreen` | String | Name of screen shown on startup |
| `ScreenResolution` | String | e.g. `"SR_1280X800"` |
| `GMPEnabled` | Boolean | GMP mode |
| `BitSelection` | Boolean | |
| `AutoLogOffURL` | String | |

### Language and Fonts
```powershell
$lang = $rs.LanguageAndFonts[0]
$lang.Enable = $true
$lang.EnableForLogging = $true
```

---

## 11. Property Quick Reference

### HmiSoftware Properties
| Property | Collection? | Notes |
|---|---|---|
| `Screens` | Yes | HmiScreenComposition |
| `ScreenGroups` | Yes | HmiScreenGroupComposition |
| `TagTables` | Yes | HmiTagTableComposition |
| `Tags` | Yes | HmiTagComposition (all tags across tables) |
| `Connections` | Yes | HmiConnectionComposition |
| `AlarmClasses` | Yes | HmiAlarmClassComposition |
| `AnalogAlarms` | Yes | HmiAnalogAlarmComposition |
| `DiscreteAlarms` | Yes | HmiDiscreteAlarmComposition |
| `DataLogs` | Yes | HmiDataLogComposition |
| `AlarmLogs` | Yes | HmiAlarmLogComposition |
| `SystemTags` | Yes | HmiSystemTagComposition |
| `RuntimeSettings` | No | HmiRuntimeSetting |
| `Scripts` | Yes | HmiScriptModuleComposition |

### Key Differences from Classic HmiTarget
| Feature | Classic (`HmiTarget`) | Unified (`HmiSoftware`) |
|---|---|---|
| Tag tables | `TagFolder.TagTables` | `TagTables` |
| Tags | `TagFolder.TagTables[].Tags` | `TagTables[].Tags` or `Tags` |
| Connections | `Connections` | `Connections` |
| Screens | `ScreenFolder.Screens` | `Screens` |
| Screen items | `ScreenItems` | `ScreenItems` |
| Runtime settings | N/A | `RuntimeSettings` |
| Events | `EventHandlers` | `EventHandlers` (different enum values) |
| Dynamizations | N/A | `Dynamizations` |

---

## 12. Known Limitations

1. **`Partner` on connection is read-only** — cannot set the PLC partner name programmatically; it's derived from `DriverProperties`.
2. **`PlcTag` setter validates against PLC** — fails if the tag path doesn't exist in the connected PLC.
3. **`Address` on tag is read-only** for external tags — disabled field.
4. **Event actions use Scripts, not SystemFunctions** — Unified does not expose the old `SystemFunction` API.
5. **Connection must be created before tag linkage** — tags validate against the connection at assignment time.
6. **Text must be XML-wrapped** — plain strings are rejected with invalid format error.
7. **Width/Height require `[uint32]`** — `[int32]` causes type conversion error.
8. **Type namespaces differ from manual** — actual runtime types are under `UI.Shapes`/`UI.Widgets`, not `ModernUI`.
9. **Bit-access in tag paths rejected** — `.%X<n>`, `.X<n>`, `[n]` all fail. Bind whole DWord, extract bits via `MappingTable.ConditionType=Singlebit`.
10. **`HmiCircle` geometry uses `CenterX`/`CenterY`/`Radius`** — `Left`/`Top`/`Width`/`Height` don't exist on circles.
11. **`HmiLine.Point1`/`Point2` return value-type structs** — mutations on the returned Point don't persist. Use a thin `HmiRectangle` instead.
12. **Font properties via `SetAttribute`** — `Size` requires `[byte]`; `Weight` is a string enum (`'Regular'`/`'Bold'`).
13. **HMI compile lives on the parent device** — `HmiSoftware.GetService<ICompilable>()` returns null. Walk up `Parent` until the call returns non-null.
14. **Multi-user save** — call `$session.Save()`, not `$project.Save()`.

---

## 13. Widget selection by data direction (canonical rule)

> **"If the operator types into it, it's an `HmiIOField` (`InputOutput`). Otherwise it's an `HmiText`."**

| Direction | Data type | Widget | Property to bind |
|---|---|---|---|
| FB -> HMI string | any | `HmiText` | `Text` |
| FB -> HMI number | any | `HmiText` | `Text` (runtime stringifies the value) |
| FB -> HMI single bit of DWord | bit-of-DWord | `HmiCircle` | `BackColor` with `MappingTable.ConditionType=Singlebit`, mask=`2^bit` as `UInt64`, two entries (off/on) |
| FB -> HMI standalone Bool | Bool | `HmiCircle` | `Visible` or `BackColor` |
| HMI -> FB number (setpoint) | Real/Int | `HmiIOField InputOutput` | `ProcessValue` to the *Set tag |
| HMI -> FB bit command | bit-of-DWord | `HmiButton` | `EventHandlers.Create(Activated/Deactivated)` for hold or `Tapped` for toggle; script reads/writes the DWord with the bit mask |

**Why never `HmiIOField IOFieldType=Output` for read-only values:** even in Output mode the widget still renders as a boxed input control. That's misleading on FB-owned values. `HmiText` is the right call for any value the operator can't change.

---

## 14. Layout-aware design pattern (build proactively, validate at end)

A simple-but-effective pattern for non-trivial screens (verified on a 200-item Kistler maXYmos NC console):

1. **Track every card and its children in PS-side data structures** (not just in TIA's screen tree). On every `Add-*` helper:
   - Compute the AABB
   - Assert it fits the screen
   - Assert it fits inside the parent card
   - Assert it doesn't overlap any interactive sibling already in the card (`HmiText`, `HmiIOField`, `HmiButton`, `HmiCircle` -- exclude `HmiRectangle` so card backgrounds don't poison the test)
   - Only then create the TIA item and register it as a child of the card

2. **Before save, run a self-check pass** over the tracked structures: screen-bounds, card-card overlap, child-in-card, sibling overlap, orphan detector (every screen item must be registered to a card -- catches off-helper `Create` calls that forgot to register).

3. **If self-check fails, abort before save** -- never let TIA see a broken layout.

This converts a 30-second build-test-fix cycle into a sub-100 ms fail-at-the-offending-line. See `docs/lessons-learned.md` §43 for the rationale and the reference framework structure.

---

## 15. Common bind recipes (copy-paste)

### Bit-of-DWord -> circle BackColor (Singlebit mapping)
```powershell
$dyn = $circle.Dynamizations.Create('BackColor')   # via reflected generic helper
$dyn.SetAttribute('Tag', 'RootTag.someDword')
$mt = $dyn.ValueConverter.MappingTable
foreach ($e in @($mt.Entries)) { try { $e.Delete() } catch {} }
$mt.SetAttribute('ConditionType', 'Singlebit')
$entries = @($mt.Entries)           # 2 default entries
$entries[1].Condition = [UInt64]([Math]::Pow(2, $bit))
$entries[0].Value = $offColor
$entries[1].Value = $onColor
```

### Hold-style button on a DWord command bit
```powershell
$evA = $btn.EventHandlers.Create([Enum]::Parse([...HmiButtonEventType], 'Activated'))
$evA.Script.SetAttribute('ScriptCode',
    "var v = Tags(`"RootTag.move`").Read();`r`nTags(`"RootTag.move`").Write(v | $mask);")
$evD = $btn.EventHandlers.Create([Enum]::Parse([...HmiButtonEventType], 'Deactivated'))
$evD.Script.SetAttribute('ScriptCode',
    "var v = Tags(`"RootTag.move`").Read();`r`nTags(`"RootTag.move`").Write(v & ~$mask);")
```

### Read-only value display (FB -> HMI)
```powershell
$t = _NewItem $screen.ScreenItems $typeHmiText 'plant_value'
_Place $t 600 26 720 36
$t.Text.Items[0].SetAttribute('Text', '<body><p>...</p></body>')
$t.Font.SetAttribute('Size',   [byte]18)
$t.Font.SetAttribute('Weight', 'Bold')
$dyn = $t.Dynamizations.Create('Text')   # via reflected generic helper
$dyn.SetAttribute('Tag', 'RootTag.plantidentifier')
```

---

*Document version: 2026-05-11*
*Verified against: TIA Portal V20 Update 4, WinCC Unified Comfort Panel (Kistler maXYmos NC console build)*
