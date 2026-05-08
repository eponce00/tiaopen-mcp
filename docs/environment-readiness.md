# Environment Setup — TIA Portal Openness

This document captures everything needed to get a Windows machine running TIA Portal Openness automation.

## Required software

| Component | Verified version | Notes |
|---|---|---|
| TIA Portal | V20 Update 4 | Installed under `C:\Program Files\Siemens\Automation\Portal V20` |
| TIA Portal Openness | V20 Update 4 | Ships with TIA Portal, no separate install |
| .NET Framework | 4.8 | Required by `Siemens.Engineering.dll` (CLR v4.0.30319) |
| PowerShell | 5.1 | Built into Windows, no upgrade needed |

## Key file paths

```
C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll
C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.Hmi.dll
```

Always reference the version-specific path above, not a recursive search result. Using the wrong DLL version causes silent failures at attach time.

## Windows group requirement — critical first step

Openness will throw `EngineeringSecurityException` for any user not in the local `Siemens TIA Openness` Windows group:

```text
Owner 'DOMAIN\User' of this process is not member of the windows group
'Siemens TIA Openness'. Please contact your administrator.
```

**Fix** — run from an elevated PowerShell prompt:

```powershell
Add-LocalGroupMember -Group "Siemens TIA Openness" -Member "DOMAIN\YourUsername"
```

**Important:** adding the user to the group is not enough on its own. The running process token does not update until the user signs out and signs back in (or reboots). Verify with:

```powershell
whoami /groups | findstr /i "openness"
```

If the group appears there, the session is ready.

## Openness authorization popups (whitelist / hash check)

Openness maintains an EXE whitelist under:

```
HKLM:\SOFTWARE\Siemens\Automation\Openness\20.0\Whitelist\
```

Each entry stores the approved executable path **and its file hash**. When an EXE is rebuilt, the hash changes and TIA shows a new approval popup even for the same path:

> *"The application TiaPlayground.Tool.exe is attempting to access the TIA Portal. Do you want to grant access?"*

**Mitigation:** use PowerShell 5.1 (`powershell.exe`) as the automation host during development. `powershell.exe` is already whitelisted system-wide and does not change hash on every run. Only switch to a custom EXE for stable/released tooling.

## .NET project setup

For any .NET project that calls the Openness API:

```xml
<PropertyGroup>
  <TargetFramework>net48</TargetFramework>
</PropertyGroup>

<ItemGroup>
  <Reference Include="Siemens.Engineering">
    <HintPath>C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll</HintPath>
    <Private>true</Private>  <!-- copies DLL to output so the assembly resolver finds it -->
  </Reference>
</ItemGroup>
```

Without `<Private>true</Private>` the DLL is not copied to the output directory and the process will crash at runtime when it tries to resolve Siemens types.

## Verified installations

### TIA Portal

- Installed path: `C:\Program Files\Siemens\Automation\Portal V20`
- Status: available

### TIA Portal Openness

- Registry root found: `HKLM:\SOFTWARE\Siemens\Automation\Openness`
- Version-specific registration found for V20 under `HKLM:\SOFTWARE\Siemens\Automation\Openness\20.0`
- Public API assemblies found for V17, V18, V19, and V20
- Main V20 API assembly:
  - `C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll`
- HMI API assembly:
  - `C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.Hmi.dll`

## Runtime and tooling

### .NET

- `.NET Framework 4.8` installed
- `.NET SDK 10.0.300-preview.0.26177.108` installed
- `Siemens.Engineering.dll` reports `ImageRuntimeVersion = v4.0.30319`

Conclusion: Openness-facing projects should target `net48` unless a specific interoperability pattern is introduced.

### PowerShell

- PowerShell version: `5.1.26100.4768`

### Git

- Git version: `2.53.0.windows.3`

## API surface verified locally

The installed XML API documentation confirms the presence of these PLC block operations:

- `Siemens.Engineering.SW.Blocks.PlcBlock.Export(...)`
- `Siemens.Engineering.SW.Blocks.PlcBlock.ExportAsDocuments(...)`
- `Siemens.Engineering.SW.Blocks.PlcBlockComposition.Import(...)`
- `Siemens.Engineering.SW.Blocks.PlcBlockComposition.ImportFromDocuments(...)`

This confirms that block export/import workflows are available through the installed V20 Openness API.

## Current access blocker

- Local Windows group exists: `Siemens TIA Openness`
- Current user at test time: `AzureAD\\ErnestoPonce`
- Initial group membership at test time: empty
- Group membership was later added for `AzureAD\\ErnestoPonce`
- After a full restart, the current logon token includes the Openness group
- Result: Openness can now create a `TiaPortal` instance and open projects

Observed exception:

```text
Owner 'AzureAD\ErnestoPonce' of this process is not member of the windows group 'Siemens TIA Openness'. Please contact your administrator.
```

## Unblock step

Run from an elevated PowerShell session:

```powershell
Add-LocalGroupMember -Group "Siemens TIA Openness" -Member "AzureAD\ErnestoPonce"
```

After that, sign out and sign back in before retrying Openness automation.

Verification note: adding the user to the local group is not enough by itself. The current process token must contain the group membership, and that was still missing in the follow-up check.

Follow-up verification: after restarting the PC, `whoami /groups` showed `Siemens TIA Openness` in the user token and a direct `TiaPortal` construction test succeeded.