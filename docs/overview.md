# TIA Portal Openness Playground

This repository is a working reference for automating Siemens TIA Portal using the **TIA Portal Openness API (V20)**.

The purpose is to capture verified patterns, reusable scripts, and operational lessons so future projects can integrate Openness automation without re-discovering the same blockers from scratch.

## What this repo contains

| Path | Purpose |
|---|---|
| `docs/` | Verified environment setup, API patterns, and lessons learned |
| `scripts/import-main.ps1` | Reusable PowerShell script: attach → import block → compile → export |
| `scripts/hmi-create-motor-screen.ps1` | Reusable PowerShell script: create PLC tags + HMI tags + HMI Unified screen |
| `src/TiaPlayground.Tool/` | .NET Framework 4.8 console helper wrapping the same API flow |
| `tmp/` | Working directory for block XML exports (not committed) |

## Key decisions

- **Target framework: `net48`** — `Siemens.Engineering.dll` targets CLR v4.0.30319; any .NET project referencing it must also target `net48`.
- **Preferred automation host: PowerShell 5.1** — avoids EXE hash-churn that causes repeated Openness authorization popups.
- **Attach to running TIA, do not open projects headlessly** — opening a project that is already open in a UI session fails with a lock error; attaching to the existing UI process is the reliable path.
- **LAD network format** — ladder rung content is embedded XML inside `SW.Blocks.CompileUnit/NetworkSource/FlgNet`; see `openness-patterns.md` for the verified template.

## Related docs

- [Environment setup and access requirements](environment-readiness.md)
- [Openness API patterns and gotchas](openness-patterns.md)
- [Lessons learned from first session](lessons-learned.md)

## Current scope

- Validate the local TIA Portal Openness environment.
- Test small automation tasks against a real TIA Portal project (PLC + HMI Unified).
- Capture findings, blockers, and working patterns as we go.
- Build reusable PowerShell scripts for common engineering tasks.
- Evolve these notes into reusable standards and skill content later.

## Current status

- TIA Portal V20 is installed locally.
- TIA Portal Openness V20 assemblies are installed and registered.
- The first live test project is available at `C:\Siemens Controls\Testing Project\Testing_Playground\Testing_Playground.ap20`.
- PLC automation (attach, import, compile, export) is verified working.
- HMI Unified automation (tags, connections, screens, screen items) is verified working against a live WinCC Unified project.

## Documentation map

- `docs/environment-readiness.md`: verified local machine setup.
- `docs/testing-log.md`: chronological record of tests, outcomes, and blockers.

## Working rule

Only record findings that were actually verified through the machine, the installed TIA Openness API, or a direct test against a project.