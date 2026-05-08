# TIA Portal Openness — API Patterns

Verified patterns for working with the TIA Portal Openness V20 API from PowerShell.
All examples assume the V20 DLL is loaded first.

---

## 1. Loading the DLL

Always use the explicit version path. Never use a recursive `Get-ChildItem` search — it may resolve the wrong version if multiple TIA versions are installed.

```powershell
$dll = "C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll"
[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null
```

---

## 2. Attaching to a running TIA UI session

Do **not** open the project from scratch with `TiaPortal.Projects.Open()` if TIA Portal is already open with that project. That will fail with a lock/ownership error. Instead, attach to the already-running UI process.

```powershell
$targetTitle = "MyProjectName"   # partial match against MainWindowTitle

$tiaProcess = $null
foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
    if ($p.Mode -ne [Siemens.Engineering.TiaPortalMode]::WithUserInterface) { continue }
    $winProc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ($winProc.MainWindowTitle -match $targetTitle) {
        $tiaProcess = $p
        break
    }
}

$tia = $tiaProcess.Attach()
$project = $tia.Projects[0]
```

---

## 3. Finding PlcSoftware inside a project

`PlcSoftware` is not directly on the `Project`. It lives behind a `SoftwareContainer` service on a `DeviceItem` (the CPU slot). You must walk `project.Devices -> device.DeviceItems -> sub-items` and call `GetService<SoftwareContainer>()` on each one.

In PowerShell, the generic `GetService<T>()` must be invoked via reflection:

```powershell
function Get-PlcSoftware($project) {
    $containerType = [Siemens.Engineering.HW.Features.SoftwareContainer]
    foreach ($device in $project.Devices) {
        $result = Search-DeviceItems $device.DeviceItems $containerType
        if ($result) { return $result }
    }
    return $null
}

function Search-DeviceItems($items, $containerType) {
    foreach ($item in $items) {
        $gsMethod = $item.GetType().GetMethods() |
            Where-Object { $_.Name -eq "GetService" -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 0 } |
            Select-Object -First 1
        if ($gsMethod) {
            try {
                $svc = $gsMethod.MakeGenericMethod($containerType).Invoke($item, $null)
                if ($svc -and $svc.Software -is [Siemens.Engineering.SW.PlcSoftware]) {
                    return $svc.Software
                }
            } catch {}
        }
        $nested = Search-DeviceItems $item.DeviceItems $containerType
        if ($nested) { return $nested }
    }
    return $null
}
```

---

## 4. Importing a block XML

Use `PlcBlockComposition.Import()` with `ImportOptions.Override` to replace an existing block:

```powershell
$plcSoftware.BlockGroup.Blocks.Import(
    [System.IO.FileInfo]::new("C:\path\to\block.xml"),
    [Siemens.Engineering.ImportOptions]::Override
)
```

The XML file must be a valid TIA Openness block export. The import call blocks until TIA finishes processing; it will show a progress dialog in the TIA UI while running.

**If the import dialog hangs at 0%:** the XML network content is invalid or contains a reference TIA cannot resolve. Cancel the dialog and fix the XML before retrying. A `WithDefaults` export of the same block after a successful import gives you the canonical form TIA expects.

---

## 5. Compiling PLC software

`PlcSoftware` does not expose a public `Compile()` method directly. Retrieve the compile capability through `GetService<ICompilable>()`:

```powershell
$compileType = [Siemens.Engineering.Compiler.ICompilable]
$gsMethod = $plcSoftware.GetType().GetMethods() |
    Where-Object { $_.Name -eq "GetService" -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 0 } |
    Select-Object -First 1

$compiler = $gsMethod.MakeGenericMethod($compileType).Invoke($plcSoftware, $null)

# $compiler is a CompileProvider at runtime
$compileResult = $compiler.GetType().GetMethod("Compile").Invoke($compiler, $null)

$state = $compileResult.GetType().GetProperty("State").GetValue($compileResult, $null)
Write-Host "Compile state: $state"   # Success / Warning / Error
```

---

## 6. Exporting a block

```powershell
$block = $plcSoftware.BlockGroup.Blocks.Find("Main")

# Remove existing file first — TIA will NOT overwrite and throws if the file exists
if (Test-Path $outputPath) { Remove-Item $outputPath -Force }

$block.Export(
    [System.IO.FileInfo]::new($outputPath),
    [Siemens.Engineering.ExportOptions]::WithDefaults
)
```

`WithDefaults` excludes read-only metadata. Use `WithReadOnly` if you need timestamps, compile dates, etc.

Export fails with `"Inconsistent blocks cannot be exported"` if the block was modified but not yet compiled successfully. Always compile before exporting.

---

## 7. LAD network XML structure (verified)

A minimal normally-open contact → coil rung uses this `FlgNet` structure inside `SW.Blocks.CompileUnit/NetworkSource`:

```xml
<FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5">
  <Parts>
    <!-- Operand references (Access) and instructions (Part) are peers in Parts -->
    <Access Scope="Address" UId="21">
      <Address Area="Input" Type="Bool" BitOffset="0" />    <!-- %I0.0 -->
    </Access>
    <Access Scope="Address" UId="22">
      <Address Area="Output" Type="Bool" BitOffset="0" />   <!-- %Q0.0 -->
    </Access>
    <Part Name="Contact" UId="23" />
    <Part Name="Coil"    UId="24" />
  </Parts>
  <Wires>
    <!-- Power rail → Contact input pin -->
    <Wire UId="25"><Powerrail /><NameCon UId="23" Name="in" /></Wire>
    <!-- Contact output → Coil input -->
    <Wire UId="26"><NameCon UId="23" Name="out" /><NameCon UId="24" Name="in" /></Wire>
    <!-- Operand binding: IdentCon goes on the Access side, NameCon "operand" on the Part side -->
    <Wire UId="27"><IdentCon UId="21" /><NameCon UId="23" Name="operand" /></Wire>
    <Wire UId="28"><IdentCon UId="22" /><NameCon UId="24" Name="operand" /></Wire>
  </Wires>
</FlgNet>
```

**Notes:**
- `UId` values must be unique within the CompileUnit but otherwise arbitrary.
- `IdentCon` (identity connection) is always the operand/Access side of an operand wire. `NameCon` with `Name="operand"` is always the instruction pin side.
- `Area` values: `Input` = `%I`, `Output` = `%Q`, `Memory` = `%M`.
- `BitOffset` is the bit address within the byte (0–7 within each byte address).
- To use symbolic tag names instead of absolute addresses, change `Scope="Address"` to `Scope="GlobalVariable"` and replace `<Address>` with a `<Component>` referencing the tag name.

---

## 8. Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `EngineeringSecurityException: not member of group` | User not in `Siemens TIA Openness` Windows group | Add user, sign out, sign in |
| `EngineeringSecurityException: operation timed out` | Authorization popup was not answered | Approve or retry; ensure the TIA window is visible |
| `EngineeringTargetInvocationException: project is locked` | Trying to open a project already open in a UI session | Attach to the UI process instead of opening |
| `Inconsistent blocks cannot be exported` | Block modified but not compiled, or compile failed | Fix errors, compile successfully, then export |
| `File already exists` on export | TIA will not overwrite | Delete the file before calling Export |
| Import dialog hangs at 0% | Invalid XML network content | Cancel, fix the XML, retry |

---

## 9. Working with Local Session projects

When TIA Portal opens a project via **Local Session** (multiuser / `LocalSessions`), `tia.Projects` is empty even though a project is visibly open. The project object is reachable through `LocalSessions[0].Project`.

```powershell
$project = $tia.LocalSessions[0].Project
```

**Check first:** always inspect `$tia.Projects.Count` and `$tia.LocalSessions.Count` before deciding which path to use.

---

## 10. Finding HMI Unified software (`HmiSoftware`)

Use the same device-tree walk as for `PlcSoftware`, but cast to `[Siemens.Engineering.HmiUnified.HmiSoftware]`:

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

## 11. Creating PLC tags programmatically

```powershell
$plcTagTable = $plcSoftware.TagTableGroup.TagTables.Create("MotorVFD")
$plcTagTable.Tags.Create("Motor_Start", "Bool", "")
$plcTagTable.Tags.Create("Motor_SpeedSetpoint", "Real", "")
```

---

## 12. Creating HMI Unified connections and tags

### Connection
```powershell
$conn = $hmiSoftware.Connections.Create("HMI_Connection_1")
```

### Tag table + tags
```powershell
$hmiTagTable = $hmiSoftware.TagTables.Create("MotorVFD")
$hmiTag = $hmiTagTable.Tags.Create("Motor_Start")

# Best-effort external linkage
$connProp = $hmiTag.GetType().GetProperty("Connection")
if ($connProp -and $connProp.CanWrite) {
    $connProp.SetValue($hmiTag, $conn, $null)
}
```

---

## 13. Creating HMI Unified screens and screen items

### Load the assembly to resolve runtime types
```powershell
$asm = [System.Reflection.Assembly]::LoadFrom($dll)
$typeHmiText    = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Shapes.HmiText')
$typeHmiButton  = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Widgets.HmiButton')
$typeHmiIOField = $asm.GetType('Siemens.Engineering.HmiUnified.UI.Widgets.HmiIOField')
```

### Create screen
```powershell
$screen = $hmiSoftware.Screens.Create("MotorControl")
$screen.Width  = [uint32]1280
$screen.Height = [uint32]800
```

### Generic `Create<T>` via reflection
`ScreenItems` has an overloaded generic `Create<T>`. Use reflection to pick the generic definition:

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

---

## 14. Setting text on HMI Unified items (XML format)

HMI Unified `Text` properties are **MultilingualText**, not plain strings. The stored value must be XML-wrapped:

```powershell
$textProp = $item.GetType().GetProperty("Text")
$mlt = $textProp.GetValue($item, $null)
$mlt.Items[0].Text = "<body><p>START</p></body>"
```

**Plain strings fail** with `The argument 'text' has an invalid format.`

For buttons the property is also named `Text` (returns `MultilingualText`), but for the **alternate** pressed state use the `AlternateText` property (also `MultilingualText`).
