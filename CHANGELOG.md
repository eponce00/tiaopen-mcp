# Changelog

All notable changes to TiaOpen MCP are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **`docs/kistler-example/`** -- complete worked example for a non-trivial WinCC Unified HMI build:
  - `kistler-reference.md` (1473 lines) -- the full Kistler maXYmos NC bible verbatim from memory: device operating modes, MP/page/sequence model, EO types and encoding, cycle handshake, 200-byte fieldbus IN/OUT map, full `LSicar_KistlerPress` FB anatomy (51 networks), FB-verified `LDrive_typeKistlerHmi` UDT bit map (the single source of truth -- bits for `state`/`alarm`/`receive.status`/`send.control`/`move`), SICAR color standard, supervision design, SVGHMI faceplate notes, TIA project structure, canonical HMI build recipe.
  - `scripts/kistler-design.ps1` (589 lines) -- the layout-aware design framework. Every `Add-*` call validates AABB + sibling overlap + text fit at call time; `Test-LayoutSelfCheck` runs all six invariants over the in-memory registry before save.
  - `scripts/build-kistler-pro-v3.ps1` -- the build script that produced the working 204-item / 80-dynamization screen using the framework. 3893 layout assertions pass; compile clean.
  - `scripts/build-kistler-final.ps1` -- the earlier open-coded build (kept for reference).
  - `scripts/extract_bit_map.py` -- the FB-XML bit-map extractor (re-run when the FB changes; ground truth for §19).
  - `scripts/test-kistler-final.ps1` -- the standalone post-build layout test suite.
  - `docs/kistler-example/README.md` -- index of the worked example with question -> section table.
  - `docs/kistler-example/session-log.md` -- chronological narrative of the session: user feedback verbatim, decisions and the bugs that drove each framework change, screen architecture summary, list of deferred work.
  - `docs/kistler-example/scripts/fix-emdash.ps1` -- surgical post-edit example (fixed 6 mojibake labels without a rebuild).
  - `docs/kistler-example/scripts/test-dyn-quick.ps1` -- dynamization audit (read-only): checks prop name vs widget type, tag root, Singlebit mask 2^n, entries count == 2.
  - `docs/kistler-example/scripts/add-kistler-supervisions.ps1`, `improve-kistler.ps1` -- supervision-injection and FB-improvement scripts.
  - `docs/kistler-example/source-xml/` -- ground-truth TIA exports that `kistler-reference.md` was derived from: `_kistler_fb.xml` (707 KB FB XML), `_udt_LDrive_typeKistlerHmi*.xml` and all sub-UDTs (Recv/Send/ProcessValues/Parameters in both raw and `_clean` form), `_udt_kistler_hmi_full.xml`, `_kistler_export.xml`, `LSicar_KistlerPress_improved.xml`, `LSicar_KistlerPress_with_supervisions.xml`.
  - `docs/kistler-example/faceplate/` -- the deferred SVGHMI faceplate work kept for future migration: `LSicar_KistlerPressFp.svghmi`, `_kistler_faceplate_v1.svg/.svghmi`, `kistler_faceplate.svg`, `kistler_faceplate_generator.py`, `create_kistler_faceplate_tia.ps1`, `create_kistler_fp2.ps1`, `bind-kistler-faceplate.ps1`.
  - `docs/kistler-example/notes/` -- human-written reference notes that preceded the consolidated bible: `KISTLER_FACEPLATE_BUILD_SUMMARY.md`, `LDrive_typeKistlerHmi_UDT_DECIPHERED.md`.
  - `docs/kistler-example/earlier-builds/` -- the build-script lineage (v1 / v1.5 / v2 / mapping tests / mastercopy probe / doc exporter) so the framework's evolution is traceable.
  - `docs/kistler-example/kistler_textlist_import.xlsx` -- text-list import sheet for supervision messages.

### Documentation

- **Lessons learned expanded to 47 entries** (`docs/lessons-learned.md`). New material captures real failures from a 200-item WinCC Unified Kistler maXYmos NC screen build:
  - HmiCircle uses `CenterX/CenterY/Radius`, not Left/Top/Width/Height (§28).
  - PowerShell variable name case-insensitivity bites color palettes (§29).
  - Em-dash and other non-ASCII in `.ps1` scripts produce mojibake on the HMI (§30, §47).
  - `MappingTable.ConditionType=Singlebit` is the only path for "LED follows one bit of a DWord" -- `Bitmask` is the wrong condition type (§31).
  - Bit-access syntax in tag paths is rejected everywhere; always extract via the mapping table (§32).
  - The canonical widget-direction rule: `HmiText` for any FB-owned value, `HmiIOField InputOutput` only for operator setpoints. `IOFieldType=Output` is effectively never correct (§33).
  - `[System.Drawing.Color] $Param = $null` is a parser error -- Color is a value-type struct (§34).
  - Empty `[string]` parameters need `[AllowEmptyString()]` (§35).
  - `${($var.Prop)}` does not interpolate -- use `$($var.Prop)` (§36).
  - `HmiLine.Point1/Point2` are value-type accessors -- use a thin rectangle instead (§37).
  - Font properties set via `SetAttribute('Size', byte)` / `SetAttribute('Weight', string)` (§38).
  - `MultilingualText.Text` accepts only `<body><p>plain</p></body>` -- no inline CSS (§39).
  - Hold-pattern button scripts read-modify-write the DWord with the bit mask (§40).
  - Multi-user projects save via `$session.Save()`, not `$project.Save()` (§41).
  - HMI compile lives on the parent device -- walk up from `HmiSoftware.Parent` until `GetService<ICompilable>()` returns non-null (§42).
  - Layout invariants are dramatically faster to enforce proactively at every `Add-*` than retroactively in a post-build test pass (§43).
  - Surgical post-edits (find item by name pattern, mutate, save) beat full rebuilds for cosmetic fixes (§44).
  - Verify FB bit maps from XML coil-tracing, not from FB text-list comments -- they drift (§45).
  - TIA Openness handles can expire on UI focus changes (`EngineeringObjectDisposedException`) -- reattach at every script start (§46).

- **HMI Unified reference (`docs/hmi-unified-reference.md`) expanded** with three new sections:
  - §13: Widget-direction canonical rule with decision matrix.
  - §14: Layout-aware design pattern (proactive AABB validation at every Add, self-check before save).
  - §15: Copy-paste bind recipes for the three most common patterns (bit-to-circle, hold button on DWord bit, FB-to-text read-only display).
  - Six new entries in the Known Limitations table (bit-access rejection, HmiCircle geometry, HmiLine value-type, font SetAttribute, HMI compile parent device, multi-user save).

- **README updated** with badges, a documentation index, a Contributing section that requires lessons-learned updates for new findings, and a clearer mention of HMI Unified capability alongside PLC tooling.

- **Mojibake cleanup** in `docs/lessons-learned.md` -- previously stored em-dashes via double-encoded UTF-8 (`a-` style sequences). Replaced with proper em-dashes.

## [0.1.0]

Initial public release with PLC XML import/export, SCL preflight, block group management, tag-table tooling, instruction reference, and the LAD JSON-to-block generator.
