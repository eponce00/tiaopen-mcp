# Lessons Learned -- TIA Portal Openness

Hard-won operational lessons from the first end-to-end Openness automation session.
Each item documents a real failure, its root cause, and the resolution.

---

## 1. Windows group membership requires a full sign-in refresh

**What happened:** Added the user to the `Siemens TIA Openness` local group, ran automation immediately, and still got `EngineeringSecurityException`.

**Why:** Windows tokens are captured at login. Adding a group does not update the token of an already-running session.

**Fix:** Sign out and sign back in (or reboot) after adding the user to the group. Verify with `whoami /groups | findstr /i openness` before running any automation.

---

## 2. Openness EXE authorization is hash-based, not just path-based

**What happened:** A custom .NET console tool was authorized once, but every rebuild caused a new `"Do you want to grant access?"` popup even though the path was identical.

**Why:** The TIA Portal whitelist at `HKLM:\SOFTWARE\Siemens\Automation\Openness\20.0\Whitelist\` stores both the path and the file hash. Rebuilding the EXE changes the hash.

**Fix for development:** Use PowerShell 5.1 as the automation host. `powershell.exe` is already trusted and its hash never changes. Build a custom EXE only for deployed/stable tooling, then authorize it once.

---

## 3. Do not call Projects.Open() when TIA already has the project open

**What happened:** Tried to open the `.ap20` file from a new headless `TiaPortal` instance while TIA Portal UI had the same project open. Got an ownership/lock error.

**Why:** TIA Portal owns the project file exclusively. A second process cannot open it.

**Fix:** Use `TiaPortal.GetProcesses()` to find the existing UI process and call `Attach()` on it. Then access `tia.Projects[0]` — the project is already loaded there.

---

## 4. PlcSoftware is not on the project directly — you must walk the device tree

**What happened:** Enumerated `project.Devices` expecting to find `PlcSoftware` directly. It was not there.

**Why:** `PlcSoftware` lives behind a `SoftwareContainer` service on a specific `DeviceItem` (the CPU slot inside a station). You must recurse through `device.DeviceItems` and call `GetService<SoftwareContainer>()` on each item.

**Fix:** See the `Get-PlcSoftware` helper in `docs/openness-patterns.md` (section 3). The key is using reflection to call the generic `GetService<T>()` from PowerShell.

---

## 5. PlcSoftware does not expose a public Compile() method directly

**What happened:** Tried `$plcSoftware.Compile()` — method not found. Tried reflection for a method named `Compile` on the type — not found either.

**Why:** The compile capability is exposed through a service interface `ICompilable`, not directly on `PlcSoftware`.

**Fix:** Call `GetService<ICompilable>()` on the `PlcSoftware` object. The returned object is a `CompileProvider` at runtime and exposes a `Compile()` method. See `docs/openness-patterns.md` section 5.

---

## 6. Block export fails if the block is in an inconsistent state

**What happened:** After importing a block, tried to export it and got:
```text
Inconsistent blocks and PLC data types (UDT) cannot be exported.
```

**Why:** The imported block had not been compiled yet, or the compile failed. TIA marks blocks as inconsistent until a successful compile.

**Fix:** Always compile the PLC software after import and before export. If compile state is `Error`, fix the block XML and retry.

---

## 7. TIA Export will not overwrite an existing file

**What happened:** Called `Export()` to the same output path twice and got:
```text
The export cannot be made because the file already exists.
```

**Why:** By design — TIA does not overwrite.

**Fix:** `Remove-Item $outputPath -Force` before every export call.

---

## 8. A hung import dialog means the XML network content is invalid

**What happened:** Import call started, TIA showed "Importing data... 0% Complete" and never progressed.

**Why:** The XML block content passed structural validation (so TIA started the import) but TIA's internal network builder could not resolve the LAD objects in the `FlgNet` (e.g., `IdentCon` on a `Part` instead of an `Access`).

**Fix:** Cancel the dialog. Fix the XML. The correct operand wire pattern has `IdentCon` on the **Access** side and `NameCon Name="operand"` on the **Part** side — not the other way around. See the verified template in `docs/openness-patterns.md` section 7.

---

## 9. The canonical FlgNet wire structure requires IdentCon on the Access side

**What happened:** Initial guess had `IdentCon` pointing to the `Part` UId in the operand wire. Got the hung import.

**Why:** `IdentCon` is an "identity connection" — it means "this end has no named pin, just an identity". That is the Access/operand side. The instruction pin side always uses `NameCon Name="operand"`.

**Verified correct pattern:**
```xml
<Wire UId="27"><IdentCon UId="21" /><NameCon UId="23" Name="operand" /></Wire>
<!-- UId 21 = Access (operand reference), UId 23 = Part (instruction) -->
```

---

## 10. Working end-to-end flow (verified)

1. Open TIA Portal with the project loaded in the UI (do not use headless mode during development).
2. From PowerShell, load the explicit V20 DLL, find the UI process by title, and call `Attach()`.
3. Find `PlcSoftware` by recursing `DeviceItems` and calling reflected `GetService<SoftwareContainer>()`.
4. Build or modify a block XML file.
5. Call `plcSoftware.BlockGroup.Blocks.Import(fileInfo, ImportOptions.Override)`.
6. Find the compile provider via reflected `GetService<ICompilable>()` and call `Compile()`.
7. Confirm `compileResult.State == Success`.
8. Delete any previous export file, then call `block.Export(fileInfo, ExportOptions.WithDefaults)`.

The working script for this flow is `scripts/import-main.ps1`.

## 11. Normally Closed contact XML — Negated child, not a different Part name

**What happened:** Used `Part Name="ContactNormallyClosed"`. TIA import error: instruction name not found.

**Root cause:** TIA uses a single `Part Name="Contact"` for both NO and NC contacts. Negation is a child element, not a different Part name.

**Fix:** Use `Part Name="Contact"` with `<Negated Name="operand"/>` as a child.

---

## 12. Empty LAD networks cannot be imported

**What happened:** Created a template with `<Parts /><Wires />`. Import failed. Omitting `<Wires>` also failed.

**Root cause:** TIA Portal's runtime rejects empty networks on import even though the XSD schema allows `<Parts minOccurs="0">`. This is a runtime policy, not a schema constraint.

**Fix:** No fix — always include at least one valid instruction (Part + Wires) in every network.

---

## 13. SCL NetworkSource namespace is StructuredText/v2

**What happened:** Tried ST namespaces v4, v3, v5, v1 -- all rejected. v2 gave a different error (product does not support SCL), pointing to a block-level issue.

**Root cause:** TIA Portal V20 SCL NetworkSource uses namespace `StructuredText/v2`. Every other version is invalid. The entire SCL body is a single `<Token Text="..." UId="21" />` element -- not structured XML like LAD/FlgNet.

**Fix:** Use this structure in NetworkSource:
```xml
<NetworkSource><ST xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/StructuredText/v2">
  <Token Text=";&#xD;&#xA;" UId="21" />
</ST></NetworkSource>
```n
The SCL source goes in the `Text` attribute. Append `&#xD;&#xA;` (CRLF) at the end.

---

## 14. Official XSD schemas ship with TIA Portal — use them before resorting to manual export

**What happened:** Spent significant time discovering XML structure by trial-and-error (testing namespace versions, exporting manually created blocks) when the ground-truth schema files were already on disk.

**Root cause:** The Siemens Openness PDF documents the C# API but does not directly link to the schema files. The schemas exist in the TIA installation but are easy to overlook.

**Fix:** Before building any new template or trying to guess XML structure, read the relevant XSD first:

| Language | Schema file (all under `C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Schemas\`) |
|---|---|
| LAD / FBD | `SW.PlcBlocks.LADFBD_v5.xsd` |
| SCL | `SW.PlcBlocks.SCL_v4.xsd` |
| STL | `SW.PlcBlocks.STL_v5.xsd` |
| GRAPH | `SW.PlcBlocks.Graph_v6.xsd` |
| Block interface | `SW.InterfaceSections_v5.xsd` |
| Access / operands | `SW.PlcBlocks.Access_v5.xsd` |

The PDF also mentions these paths in the section **"Structure of an XML file" → "Subschemas"** (search for `LADFBD` in the MD conversion of the Openness PDF).

Key findings from `LADFBD_v5.xsd`:
- `<Wires>` is **optional** on `<FlgNet>` — the empty-network rejection is a TIA runtime policy, not a schema violation
- `<Part>` allowed children: `TemplateValue`, `AutomaticTyped`, `Invisible`, `Negated`, `Comment`
- `<Wire>` allowed children: `Powerrail`, `NameCon`, `IdentCon`, `Openbranch`, `OpenCon`
- `<Negated Name="operand"/>` is schema-confirmed for NC contacts

Key findings from `SCL_v4.xsd`:
- Root element is `<StructuredText>` (not `<ST>`)
- Allowed children: `<Token>`, `<Access>`, `<Parameter>`, `<Text>`, comment elements

---

## 15. TON timer XML — correct Part name, constant scope, and instance DB

**What happened:** First attempt used `Part Name="TON_TIME"`, `Scope="LiteralConstant"`, and `ConstantValue="T#5S"` — all rejected.

**Root cause:** TIA Portal V20 exports reveal the correct structure:
- Part Name is `"TON"` with `Version="1.0"` (not `TON_TIME`)
- PT constant uses `Scope="TypedConstant"` with only `<ConstantValue>` (no `<ConstantType>` element)
- Time value format is `T#500MS` style (the `T#` prefix is correct, but the value must be a valid IEC time literal)
- `<TemplateValue Name="time_type" Type="Type">Time</TemplateValue>` is a required child of the TON Part
- The ET (elapsed time) output pin must be wired to `<OpenCon>` if unused

**Instance DB constraint:** The `<Instance Scope="GlobalVariable">` DB must already exist in the project. TIA auto-creates this DB when a TON is placed via the UI, but programmatic import requires you to reference an existing DB. Use the DB name from an existing TON in the project (e.g. `IEC_Timer_0_DB`).

**Fix:** See `templates/lad/ton-timer.xml` for the correct structure. Pass `-TimerDB IEC_Timer_0_DB` (or any existing timer DB name) to `new-block.ps1`.

---

## 16. MOVE instruction requires `TemplateValue Card` (Cardinality)

**What happened:** Importing `move.xml` failed with `The node 'TemplateValue' with the name 'Card' and the type 'cardinality' is missing at the element 'Move'`.

**Fix:** Add `<TemplateValue Name="Card" Type="Cardinality">1</TemplateValue>` as a child of the Move Part. The value is the number of outputs (1 for a single MOVE destination). Same pattern as TON's `time_type`.

---

## 18. `CreateInstanceDB` only works for user FBs, not system FBs

**What happened:** Calling `CreateInstanceDB("IEC_Timer_1_DB", true, 1, "TON")` throws `Block 'TON' does not exist`. Same for `IEC_TON_TIME_V3` and other guesses.

**Root cause:** The Openness `CreateInstanceDB` API only resolves FBs in the user block group. System/library FBs (TON, TOF, CTU, etc.) are managed by TIA internally and are not accessible this way. Their instance DBs don't appear in `get-blocks.ps1` output either.

**Workaround:** Timer/counter instance DBs must be pre-created by placing the instruction once in the TIA UI. The DB is then reusable by name in all programmatic imports. Use `new-instance-db.ps1` only for your own user FBs.

---

## 17. Parallel OR branches use a dedicated `O` Part — not merged wires

**What happened:** Attempts to connect two Contact `out` pins directly to a Coil `in` failed. Powerrail fan-out to multiple `Contact.in` in one wire was also rejected initially.

**Root cause / correct structure (from ground-truth export):**
- TIA inserts an `O` (OR) function Part: `<Part Name="O" UId="..."><TemplateValue Name="Card" Type="Cardinality">2</TemplateValue></Part>`
- Pins are named `in1`, `in2`, `out`
- The Powerrail wire CAN list multiple `Contact.in` NameCon targets in one wire (fan-out is valid here)
- Each Contact `out` feeds `O.in1` / `O.in2` in separate wires
- `O.out` → `Coil.in`

**Fix:** See `templates/lad/parallel-or.xml`.

---

## 19. SCL XML is fully tokenized — not a single text blob

**What happened:** Tried using `<Token Text="IF %I0.0 THEN ... END_IF;" UId="21"/>` (entire IF block as one Token Text). TIA rejected it with "The token is not supported at the object with UID '21'".

**Root cause:** TIA's SCL `<StructuredText>` is not a free-text container. Every SCL keyword, operator, space, newline, and variable reference must be a separate XML element:
- `<Token Text="IF" />` — keyword or operator
- `<Blank Num="1" />` — spaces
- `<NewLine Num="1" />` — line breaks
- `<Access Scope="GlobalVariable">` with `<Component Name="TagName">` + `<BooleanAttribute Name="HasQuotes">true</BooleanAttribute>` — named tag references
- `<Access Scope="LiteralConstant">` with `<ConstantValue>TRUE</ConstantValue>` — literal values

The only valid single-Token SCL is a lone `<Token Text=";" UId="21"/>` (empty body), which is what `fc-skeleton.xml` uses.

**Also:** SCL does not support absolute addresses (`%I0.0`, `%Q0.0`) as operands. Use global tag names instead.

**Fix:** See `templates/scl/fc-if-then.xml` for the correct tokenized IF/THEN/ELSE structure.

---

## 20. Duplicate block numbers are silently imported but fail to compile

**What happened:** Running `new-block.ps1` multiple times with the same `-BlockNumber` (e.g. all four comparison-variant test blocks created at number 225) imported successfully each time. Compile then reported 4 errors: "There are objects with ambiguous addresses in the program."

**Root cause:** The Openness `Import()` call with `Override` replaces a block by name — not by number. If four different block names all share the same number, TIA stores all four and only detects the conflict at compile time.

**Fix:** Always use a unique block number per block. Blocks sharing a number must be deleted via `Block.Delete()` before compiling.

---

## 21. `Block.Delete()` works via Openness — use `LoadFrom` attach pattern

**What happened:** Needed to delete four duplicate blocks programmatically. First attempt used `Add-Type` + direct `$item.GetService([SoftwareContainer])` — the `GetService` call returned null silently (blocks not found).

**Root cause:** `Add-Type` with the Openness DLL throws a `ReflectionTypeLoadException` (non-fatal, logged as a warning) but also means some types are not loaded. The direct `GetService([Type])` overload resolves the type at runtime and fails silently when the assembly is partially loaded.

**Correct pattern:** Use `[System.Reflection.Assembly]::LoadFrom($dll)` and the reflection-based `Invoke-GenericGetService` helper (same as all other scripts). Then `$block.Delete()` works normally.

**Also confirmed:** `Block.Delete()` is a valid Openness API call and succeeds without error for FC, FB, and DB blocks.

---

## 22. HMI Unified type names differ from the manual

**What happened:** Tried to use `[Siemens.Engineering.HmiUnified.ModernUI.Base.HmiTextBox]`, `[Siemens.Engineering.HmiUnified.ModernUI.Widgets.HmiButton]`, `[Siemens.Engineering.HmiUnified.ModernUI.Widgets.HmiIOField]`. All failed with "Unable to find type".

**Root cause:** The Openness PDF/manual references an older/different namespace (`ModernUI`). The actual runtime types in V20 live under `Siemens.Engineering.HmiUnified.UI`:
- `Siemens.Engineering.HmiUnified.UI.Shapes.HmiText`
- `Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton`
- `Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField`

**Fix:** Use `$asm.GetType('...')` on the loaded `Siemens.Engineering.dll` assembly to resolve the exact runtime type, rather than relying on PowerShell's type literal syntax which may not find nested namespaces depending on load order.

---

## 23. `ScreenItems.Create<T>()` requires disambiguated reflection

**What happened:** `$screenItems.GetType().GetMethod("Create")` threw `Ambiguous match found` because `HmiScreenItemBaseComposition` has multiple `Create` overloads (generic and non-generic).

**Fix:** Filter for the generic method definition explicitly:

```powershell
$createMethod = $screenItems.GetType().GetMethods() |
    Where-Object { $_.Name -eq "Create" -and $_.IsGenericMethodDefinition } |
    Select-Object -First 1
$generic = $createMethod.MakeGenericMethod($type)
$item = $generic.Invoke($screenItems, @("Name"))
```

---

## 24. `uint32` is required for Width, Height on HMI screen items

**What happened:** `$screen.Width = 1280` threw `Object of type 'System.Int32' cannot be converted to type 'System.UInt32'`.

**Fix:** Always cast screen dimensions to `[uint32]`:

```powershell
$screen.Width  = [uint32]1280
$screen.Height = [uint32]800
```

Same applies to item `Width` and `Height`.

---

## 25. HMI Unified text values must be XML-wrapped `<body><p>text</p></body>`

**What happened:** Setting `$mlt.Items[0].Text = "Motor VFD Control"` threw `The argument 'text' has an invalid format.`

**Root cause:** HMI Unified `MultilingualText` items store rich-text XML internally, not raw strings.

**Fix:** Wrap every text assignment:

```powershell
$mlt.Items[0].Text = "<body><p>Motor VFD Control</p></body>"
```

---

## 26. HMI tag external linkage properties are not consistently named

**What happened:** Attempted to set `$hmiTag.TagAddress = "MotorVFD.Motor_Start"`. The property did not exist on the runtime object.

**Root cause:** The property name for the PLC tag address varies by TIA version and HMI object type. Common names found in the object model: `TagAddress`, `Address`, `PlcTag`. None are guaranteed to exist.

**Fix:** Use defensive reflection to try each candidate:

```powershell
$addrNames = @("TagAddress","Address","PlcTag")
foreach ($an in $addrNames) {
    $ap = $hmiTag.GetType().GetProperty($an)
    if ($ap -and $ap.CanWrite) {
        try { $ap.SetValue($hmiTag, "MotorVFD.Motor_Start", $null); break } catch {}
    }
}
```

Also always set the `Connection` property on the tag when creating external tags.

---

## 27. HMI Unified `HmiSoftware` property names differ from classic `HmiTarget`

**What happened:** Tried `$hmiSoftware.HmiTagTables` and got a null-valued expression; tried `$hmiSoftware.HmiConnections` and also failed.

**Root cause:** The Unified API uses simpler property names:
- Classic: `HmiTarget.TagFolder.TagTables`, `HmiTarget.Connections`
- Unified: `HmiSoftware.TagTables`, `HmiSoftware.Connections`, `HmiSoftware.Tags`

**Fix:** Use the Unified property names. Diagnostic-dump `$hmiSoftware.GetType().GetProperties()` if unsure.

---

## 28. HmiCircle uses CenterX / CenterY / Radius -- not Left/Top/Width/Height

**What happened:** Setting `$circle.Left` / `$circle.Top` / `$circle.Width` / `$circle.Height` on an `HmiCircle` silently does nothing -- the LED renders at (0,0) with default size.

**Root cause:** Unlike rectangles, text, and IO fields, `HmiCircle` exposes geometry as `CenterX` (int), `CenterY` (int), and `Radius` (uint32). The `Left`/`Top`/`Width`/`Height` properties don't exist on the type.

**Fix:** Detect the property set and dispatch:
```powershell
if ($item.GetType().GetProperty('Left')) {
    $item.Left = $L; $item.Top = $T; $item.Width = [uint32]$W; $item.Height = [uint32]$H
} elseif ($item.GetType().GetProperty('CenterX')) {
    $item.CenterX = $L + [int]($W/2); $item.CenterY = $T + [int]($H/2)
    $item.Radius  = [uint32]([int]([Math]::Min($W,$H)/2))
}
```

---

## 29. PowerShell variable names are case-insensitive -- this bites color palettes

**What happened:** A palette had `$Accent = [Color]::FromArgb(...)`, then later code created a rectangle: `$accent = _NewItem ...`. The rectangle assignment silently overwrote the color palette entry, and subsequent `_Place $accent ...` calls placed a Color value -- runtime threw a property-not-found error far from the cause.

**Root cause:** PS treats `$Accent` and `$accent` as the same variable.

**Fix:** Don't reuse palette names for local widget references. Suffix locals (`$accentRect`, `$alarmRect`) or scope colors into a hashtable `$C.Accent`.

---

## 30. Em-dash (and other non-ASCII) in PowerShell source = mojibake at runtime

**What happened:** A build script with `-Text 'a -- b'` (real em-dash) rendered on the HMI as `a a"" b`.

**Root cause:** Windows PowerShell 5.1 opens `.ps1` files as ANSI (CP1252). A script saved as UTF-8 without BOM gets its UTF-8 bytes (e.g. `0xE2 0x80 0x94` for em-dash) misread as CP1252 (`a`+`EUR`+`"`). That mojibake string gets passed verbatim into the `MultilingualText` XML and rendered.

**Fix (pick one):**
- Stick to ASCII in label strings (`-`, `:`, `...`).
- Save scripts as UTF-8 **with BOM** so PS5.1 picks the right decoder.
- Or move to PowerShell 7+, which defaults to UTF-8.

---

## 31. `MappingTable.ConditionType` -- use `Singlebit` for single-bit watch, not `Bitmask`

**What happened:** A `TagDynamization` on `BackColor` of an LED wired to a DWord status word was first written using `Bitmask`. The LED never changed color even though the bit was set.

**Root cause:** `Bitmask` is a Boolean-AND comparator (multiple bits all-must-be-set); `Singlebit` does the bit extraction TIA's runtime expects for "this LED follows bit N." The two condition types are NOT interchangeable.

**Fix:** For one-bit-of-DWord LEDs, set `mt.SetAttribute('ConditionType', 'Singlebit')` and seed exactly 2 entries (off / on). The `Condition` property on entry[1] is a `UInt64` mask = `2^bit`. (`Relevant` is read-only -- TIA auto-syncs it from `Condition`.)

---

## 32. Bit-access in tag paths (`.%X<n>`) is rejected -- always extract via Singlebit MappingTable

**What happened:** Tried every plausible TIA bit-access syntax to bind an LED's `Visible` straight to a bit of a DWord HMI tag: `tag.%X3`, `tag.X3`, `tag[3]`, etc. All rejected by Openness or by the runtime.

**Root cause:** WinCC Unified `TagDynamization.Tag` only accepts whole-tag paths. Bit extraction is the job of the `MappingTable` (see lesson 31). Pre-creating per-bit Bool HMI tags backed by `PlcTag` with bit-access syntax also fails (`set_PlcTag` rejects the syntax).

**Fix:** One DWord HMI tag + one `Singlebit` mapping table per LED. This is the only path that compiles cleanly.

---

## 33. The HMI widget-direction rule: `HmiText` for FB-owned values, `HmiIOField` only for operator setpoints

**What happened:** Used `HmiIOField` with `IOFieldType = Output` for read-only displays (plant name, current MP, jog speed). Operators complained that the values look editable -- the box still renders with a focus border.

**Root cause:** "Output" mode disables typing but does NOT change the visual treatment. To an operator it's indistinguishable from an input.

**Rule (canonical):**
- **Anything sourced FROM the device** (string OR number, OR formatted) -> `HmiText` with `TagDynamization` on the `Text` property.
- **Anything the operator types INTO** (setpoints, target MP, target speed) -> `HmiIOField InputOutput` with `TagDynamization` on `ProcessValue`.
- **`HmiIOField Output` is effectively never the right answer.**

Mnemonic: *"If the operator types into it, it's an IOField. Otherwise it's a Text."*

---

## 34. `[System.Drawing.Color]$Param = $null` is a parser error

**What happened:** A function signature `[System.Drawing.Color]$HeaderColor = $null` failed at parse time.

**Root cause:** `System.Drawing.Color` is a value-type struct -- it cannot be null.

**Fix:** Drop the type constraint on optional Color params; use a runtime `if (-not $HeaderColor) { $HeaderColor = $script:Colors.Default }` instead.

---

## 35. Empty `[string]` parameters need `[AllowEmptyString()]`

**What happened:** `Add-Label -Text ''` (e.g. for a transparent placeholder rectangle) threw "Cannot bind argument to parameter 'Text' because it is an empty string."

**Fix:** Decorate the param: `[Parameter(Mandatory)] [AllowEmptyString()] [string]$Text`.

---

## 36. `${($var.Prop)}` is NOT a valid PowerShell interpolation -- use `$($var.Prop)`

**What happened:** Generated item names like `"eo${($eo.N)}_byte"` came out as `"eo_byte"`, then TIA threw `ValueIsNotUnique` because every row collided on the same name.

**Root cause:** PS only allows simple variable names inside `${...}`. Property expressions need `$(...)`.

**Fix:** `"eo$($eo.N)_byte"`.

---

## 37. `HmiLine.Point1` / `Point2` are value-type accessors -- mutations don't persist

**What happened:** Tried to draw a vertical separator with `HmiLine`. Setting `$line.Point1.X = 100` had no effect at runtime; the line still rendered diagonally from a default position.

**Root cause:** `Point1`/`Point2` return value-type `Point` structs by value. Mutating the returned copy doesn't write back.

**Fix:** Either construct a new `Point` and assign it whole (if the API allows), or just use a thin `HmiRectangle` -- which is what most "lines" should be anyway for crisp rendering.

---

## 38. Font properties are set via `SetAttribute('Size', byte)` / `SetAttribute('Weight', string)`

**What happened:** Tried `$item.Font.Size = 14` and `$item.Font.Weight = 'Bold'` -- both threw "property is read-only."

**Root cause:** `Font` is exposed as a "part" (`HmiFontPart`) whose values are set via `SetAttribute(name, value)`, not direct properties. `Size` requires `[byte]`; `Weight` is a string enum (`'Regular'`, `'Bold'`).

**Fix:**
```powershell
$item.Font.SetAttribute('Size',   [byte]14)
$item.Font.SetAttribute('Weight', 'Bold')
```

The same `SetAttribute` pattern applies to `ForeColor` on some text items, although `ForeColor` is also exposed as a regular settable property on most widgets -- try the property first.

---

## 39. `MultilingualText` accepts `<body><p>text</p></body>` -- no inline CSS

**What happened:** Tried `<body><p style="color:#fff;font-size:14pt">Hello</p></body>` to set inline color/size. TIA rejected the import.

**Root cause:** TIA's `MultilingualText.Text` parser only accepts the plain body/paragraph wrapper. Styling must come from sibling properties (`Font`, `ForeColor`, `HorizontalTextAlignment`), not inline CSS.

**Fix:** Set the text to `<body><p>plain text</p></body>` and apply styling via the widget's own properties (see lesson 38).

---

## 40. Button command scripts: read-modify-write the DWord via `Tags("path").Read()/.Write()`

**What happened:** First button attempt assigned a single Bool tag for a "Jog Up" command. The PLC interface uses a DWord (`move`) where each bit is a different command -- so a Bool-per-button approach can't coexist with hold-modifier and jog-while-pressed semantics.

**Root cause:** Multi-command shared DWords need atomic read-modify-write per button.

**Fix:** Wire the button's events with `HmiButtonEventType` (`Activated` + `Deactivated` for hold, `Tapped` for toggle) and put a script that does:
```javascript
// Hold pattern (Activated)
var v = Tags("MVterminalPressKistler.move").Read();
Tags("MVterminalPressKistler.move").Write(v | <mask>);
// Deactivated
var v = Tags("MVterminalPressKistler.move").Read();
Tags("MVterminalPressKistler.move").Write(v & ~<mask>);
```
For "echo" (button lights up while command is in flight): bind the button's `BackColor` to `send.control` via a Singlebit mapping table on the echoed bit.

---

## 41. Multi-user projects: save via `$session.Save()` -- NOT `$project.Save()`

**What happened:** `$project.Save()` on a multi-user project either threw or silently no-op'd.

**Root cause:** Multi-user projects expose save through the local-session object, not the project.

**Fix:**
```powershell
$session = $tia.LocalSessions[0]
$project = $session.Project
# ... mutations ...
$session.Save()
```

If `LocalSessions` is empty, the project isn't multi-user and `$project.Save()` is correct.

---

## 42. HMI compile: walk up from `HmiSoftware` to find `ICompilable`

**What happened:** `$hmi.GetService([ICompilable])` returned null. Compile attempted on the wrong object.

**Root cause:** `ICompilable` is exposed on the parent device (the HMI station), not on `HmiSoftware` itself.

**Fix:** Walk up `$hmi.Parent` until `GetService<ICompilable>()` returns a non-null provider, then call `.Compile()` on it.

```powershell
$cur = $hmi.Parent; $comp = $null
while ($cur -and -not $comp) {
    $gs = $cur.GetType().GetMethods() | Where-Object { $_.Name -eq 'GetService' -and $_.IsGenericMethodDefinition } | Select-Object -First 1
    if ($gs) { try { $comp = $gs.MakeGenericMethod($iCompilable).Invoke($cur, $null) } catch {} }
    $cur = $cur.Parent
}
$result = $comp.Compile()
```

---

## 43. Layout invariants: enforce proactively at every Add, not just retroactively in a test pass

**What happened:** First HMI build relied on a post-build test suite to catch overlaps, off-screen items, and orphaned children. Errors surfaced only after a 30-second build + compile cycle. Fixing required another full cycle. Iteration was painful.

**Better pattern (verified on Kistler):** Wrap every item-creation call (`Add-Label`, `Add-Button`, `Add-DisplayValue`, etc.) in a helper that:
1. Computes the AABB before TIA is touched.
2. Asserts the AABB is inside screen bounds AND inside the parent card AND doesn't overlap interactive siblings already registered to that card.
3. Throws with a precise, operator-readable message (item name, coordinates, conflicting sibling).
4. Only then creates the item and registers it as a child of the card.

The same invariants are also packaged as a `Test-LayoutSelfCheck` function that runs over the in-memory card/child registry before save. Pre-save validation aborts a broken build before TIA even sees it.

**Result:** Layout bugs fail in <100 ms at the offending call site, not 30 s later in a separate test. See the Kistler design framework (`kistler-design.ps1`) for the reference implementation. Six rules are enforced: screen-bounds, card-card overlap, child-in-card, sibling overlap (interactive widgets only -- HmiRectangle excluded so backgrounds don't poison the test), orphan detector (every item must be registered), text-fits-width heuristic.

---

## 44. Don't rebuild the whole screen for cosmetic fixes -- use surgical post-edits

**What happened:** Found six labels with mojibake em-dash text after build. Reflex was to rebuild the entire screen (slow). Better: a 30-line script that attaches to TIA, finds items by name pattern, mutates only the affected `MultilingualText.Text` xml, calls `$session.Save()`. Sub-second.

**Rule:** If the change touches <10% of items and doesn't alter layout, write a targeted post-edit. Update the build script source so the next full rebuild stays consistent, but don't pay the rebuild cost just to validate the source edit.

Template:
```powershell
foreach ($it in $screen.ScreenItems) {
    if ($it.Name -match '<your pattern>') {
        $mlt = $it.GetType().GetProperty('Text').GetValue($it)
        foreach ($mi in $mlt.Items) { $mi.SetAttribute('Text', '<body><p>new</p></body>') }
    }
}
$session.Save()
```

---

## 45. Verify FB bit maps from XML, not from the FB's text-list -- texts drift

**What happened:** First Kistler UDT bit assignments came from copy-pasting the FB's alarm text list. Multiple bits were off-by-one because the text list had been edited but the FB's coil wiring hadn't been re-synced.

**Root cause:** Text-list comments are documentation; LAD coil networks are the actual behavior. They can disagree, and the FB still compiles.

**Fix:** Extract bit maps directly from the FB XML by tracing each `Coil` back through its preceding `Contact`s to the source operand. A 50-line Python parser (`extract_bit_map.py` in the Kistler memory) does this for an entire FB and produces a ground-truth `{bit -> source_tag}` table.

---

## 46. `EngineeringObjectDisposedException` -- TIA objects expire on UI focus changes

**What happened:** Long-running PowerShell sessions that held onto a `Project` or `HmiSoftware` reference across user activity in the TIA UI started throwing `EngineeringObjectDisposedException` on subsequent property access.

**Root cause:** Some TIA Openness wrappers expire when the user opens a different editor or navigates away in the UI. The reference is now stale.

**Fix:** Treat handles as short-lived. Reattach (`tia.LocalSessions[0].Project`, walk for `HmiSoftware`) at the start of every script run. Don't cache them across user-perceptible time gaps.

---

## 47. PowerShell here-strings and the script's encoding interact badly with TIA XML

**What happened:** A here-string containing UTF-8 special characters (degree sign, non-breaking space) injected into a `MultilingualText.SetAttribute('Text', ...)` produced garbled runtime text.

**Root cause:** Same as lesson 30 -- the PS source file's encoding controls how the literal bytes reach .NET. Once they're wrong inside the script string, every downstream API call propagates the corruption.

**Fix:** Either keep the script ASCII-only and use numeric XML entities (`&#176;` for `°`), or save the script as UTF-8 with BOM. Validate by running `python -c "open(r'...','rb').read()[:200]"` and inspecting the byte sequence.

---