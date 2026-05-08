# Lessons Learned — TIA Portal Openness

This document records the hard-won operational lessons from the first end-to-end Openness automation session. Each item is a real failure or surprise encountered in practice.

### Findings

1. Confirmed TIA Portal V20 is installed.
2. Confirmed TIA Portal Openness V20 assemblies and registry registration are present.
3. Confirmed the target project exists:
   - `C:\Siemens Controls\Testing Project\Testing_Playground\Testing_Playground.ap20`
4. Confirmed the installed API exposes PLC block export/import methods.

### Attempted live test

Target task: create a simple ladder rung in `Main` with one normally open contact driving one output coil.

Result: blocked before project enumeration because the current Windows user is not authorized for TIA Openness.

### Error captured

```text
Siemens.Engineering.EngineeringSecurityException
Owner 'AzureAD\ErnestoPonce' of this process is not member of the windows group 'Siemens TIA Openness'. Please contact your administrator.
```

### Operational notes

- In Allen-Bradley terms the user asked for an `XIC` to output pattern.
- In Siemens LAD the equivalent structure is a normally open contact feeding a coil.
- Once Openness access is unblocked, the next step is to enumerate devices, PLC software, and blocks in the test project before editing logic.

### Next verified action

Add the current user to the `Siemens TIA Openness` local group, sign out, sign back in, then retry the project automation test.

## 2026-04-20 Follow-up

### Retest after group change

1. Confirmed `AzureAD\ErnestoPonce` was added to the local `Siemens TIA Openness` group.
2. Confirmed the current process token still does not show the Openness group via `whoami /groups`.
3. Confirmed Openness still throws the same `EngineeringSecurityException` from the current session.

### Conclusion

The group membership change is correct, but the Windows sign-in session has not been refreshed yet. A full sign-out/sign-in is still required before Openness automation can proceed.

## 2026-04-20 Post-restart retest

### Access retest

1. Confirmed `AzureAD\\ErnestoPonce` remains a member of the local `Siemens TIA Openness` group.
2. Confirmed the current Windows token now includes `Siemens TIA Openness`.
3. Confirmed a direct `TiaPortal` creation test succeeds.

### Project inspection

Target project:

- `C:\Siemens Controls\Testing Project\Testing_Playground\Testing_Playground.ap20`

Verified through Openness:

1. `Devices.Count = 0`
2. `DeviceGroups.Count = 0`
3. `UnguardedDevices.Count = 0`

Verified from the saved `.ap20` file:

1. The file contains project metadata and icon data.
2. No saved PLC, station, block, `Main`, or `OB1` content was found in the project structure.

### Current blocker

The project opens correctly, but there is no PLC device or program block in the saved project, so there is nothing to modify yet. A rung cannot be inserted until a PLC exists and the project contains a saved block such as `Main` or `OB1`.

### Next viable actions

1. Create or save a PLC in the project manually, then retry the rung insertion test.
2. Or create a PLC device through Openness once a target CPU/order number is chosen.

## 2026-04-20 PLC added retest

### Project state after manual update

The project now contains:

1. Station: `S7-1500/ET200MP station_1`
2. PLC software: `PLC_1`
3. Block: `Main (OB)`

### Verified through Openness

1. A reflected `GetService<SoftwareContainer>()` call on the CPU path successfully found `PLC_1`.
2. A reusable console tool was created under `src/TiaPlayground.Tool` to interact with the project more reliably than ad hoc PowerShell.
3. The tool can enumerate blocks when it is able to reach the project session.

### Current blockers

1. Exporting `Main` fails with:

```text
Inconsistent blocks and PLC data types (UDT) cannot be exported.
```

2. Opening the project directly from a new Openness session can fail because the project is already open in TIA Portal.

3. Attaching to an already running TIA Portal process currently fails intermittently with a timeout-based security error:

```text
Siemens.Engineering.EngineeringSecurityException: Security error.

The operation has timed out.
```

### Practical interpretation

At this point the environment and base API access are working, but the live automation path is blocked by project/session state rather than missing installation steps. The two immediate operational issues are:

1. `PLC_1` appears inconsistent and likely needs a successful compile/save cycle.
2. The attach-to-running-TIA path is not stable enough yet to rely on for editing the open project automatically.

### Next viable actions

1. Compile and save the project in the TIA Portal UI, then retry export/import automation.
2. Close the project in TIA Portal before running the tool, so the tool can open the project directly without attach.

### Openness prompt behavior

Repeated `Openness access` popups were verified to correlate with new executable hashes for `TiaPlayground.Tool.exe`.

Observed in registry:

1. `HKLM\SOFTWARE\Siemens\Automation\Openness\20.0\Whitelist\TiaPlayground.Tool.exe\...`
2. Multiple entries exist for the same executable path but with different `FileHash` values.

Practical meaning:

1. TIA Portal authorization is not just path-based.
2. Rebuilding the tool changes the binary hash.
3. A newly built executable can trigger another authorization prompt even when the path stays the same.