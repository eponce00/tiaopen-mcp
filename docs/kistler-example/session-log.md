# Kistler HMI Build -- Session Log

A chronological narrative of the decisions and feedback that shaped the working Kistler maXYmos NC HMI build (`_Kistler_Press_01` screen on `HMI_RT_2`). This log exists so future sessions don't repeat the discovery cycles -- the *why* behind every framework decision is here, not just the *what*.

The technical bible is `kistler-reference.md`. The code is in `scripts/`. This document is the human-readable history.

---

## Session arc

The screen was built across multiple iterations. The big shifts:

1. **v1 / v2 (`build-kistler-screen.ps1`, `build-kistler-screen-bound.ps1`, `build-kistler-tags-only.ps1`, `build-kistler-final.ps1`)** -- open-coded every Openness call. Worked but iteration was slow: bugs surfaced only after a 30-second build + compile cycle, then required another full cycle to fix. Helpful as reference for the long-form invocation pattern.
2. **v3 framework (`scripts/kistler-design.ps1` + `build-kistler-pro-v3.ps1`)** -- layout-aware design framework. Every `Add-*` helper validates AABB-fits-screen + fits-card + no-sibling-overlap + text-fits-width at the call site. Errors fail in <100 ms at the offending line, not 30 s later in a separate test pass. Final clean build: 204 items, 80 dynamizations, 15 button event handlers, 3893 layout assertions, 0 compile errors.

---

## Pivotal user feedback (verbatim) and how it shaped the framework

### "An operator not an engineer will be operating this screen"

Original draft of the status card had engineer-style annotations next to every LED (e.g., "Ready (rcv.status.x2)" so the bit position was visible). Operators don't care which bit it is -- they care whether the press is ready. **All bit annotations were stripped.** Labels became plain English: "Ready", "At Reference", "Sequence Complete".

This drove a related decision: don't display unused/diagnostic bits at all if the operator can't act on them. The status card LEDs only show actionable / status-meaningful bits. Diagnostic bits (`state.x*` for `enableBlock`, `HardwareOK`, etc.) live on a separate hidden panel.

### "Sequence complete LED is overlapping cfg length. I need to know how you missed this test."

The post-build test suite (`test-kistler-final.ps1`) was only checking card-to-card overlap, not items within cards or unregistered items. The `seq_end_led` was an off-framework item placed via `_NewItem` directly and was never registered to a card's child list, so the sibling-overlap test never saw it.

**Resulting framework changes:**
1. Added `Register-Child` requirement -- every item created off-helper must call `Register-Child` immediately.
2. Added an **orphan detector** (T5) -- every `Screen.ScreenItems` entry must be tracked in some card's children. Catches forgotten `Register-Child` calls.
3. Added **sibling-overlap test** (T4) -- pairwise overlap check between interactive widgets within each card. `HmiRectangle` is excluded so card backgrounds don't poison the test.
4. `New-Card` now auto-registers its background + header band + header text as children of itself. Earlier the auto-created header items were orphans.

### "Why is there a weird gap between active alarm section and bottom of screen?"

Alarm panel was placed too high with an arbitrary card height. **Result:** cards now extend to the natural content end + footer margin, not a hardcoded height.

### "Why is there a weird gap between EO objects and trend control?"

Same root cause: hardcoded gaps between cards. **Result:** card positions are computed by stacking + explicit spacing variables, not absolute Y values guessed at design time.

### "Record this learning and how to test for layouts at the end of build."

This produced §22 in `kistler-reference.md` (the six-test layout suite) and `test-kistler-final.ps1` as the standalone implementation. Later merged into `Test-LayoutSelfCheck` inside the framework, so validation runs pre-save and aborts a broken build before TIA sees it.

### "Instead of placing thing and then later relying on testing... Can you be using them while designning so we can speed up this process. Still run the tests at the end but we don't want to find big errors and then it takes you time to fix. Can we proactively do this?"

**This was the trigger for the framework.** Previous approach was build-everything-then-test. New approach: every `Add-*` call:
1. Computes AABB
2. Asserts within screen + within parent card + no sibling overlap + text fits
3. Throws with a precise error message at the offending line if any check fails
4. Only then creates the TIA item and registers it as a child

Result: bugs that previously took two build cycles to surface and fix now fail in <100 ms at the offending line. The post-build `Test-LayoutSelfCheck` still runs as a belt-and-suspenders before save.

### "Can we just fix those? Don't redo the whole screen."

Six labels rendered with `a-` mojibake because the source `.ps1` used real em-dash characters and PowerShell 5.1 reads `.ps1` files as CP1252. The instinct was a full rebuild. The right answer was a 30-line surgical script (`fix-emdash.ps1`) that attached to TIA, found items matching `_(real|byte)_dash$`, mutated their `MultilingualText.Text` to `<body><p>-</p></body>`, and called `$session.Save()`. **Sub-second instead of 30-second rebuild.**

**Permanent learning (lesson 44 in `../lessons-learned.md`):** if a change touches less than ~10% of items and doesn't alter layout, write a targeted post-edit. Update the build script source so the next full rebuild stays consistent, but don't pay the rebuild cost for cosmetic fixes.

### "Why did you forget already you should be using text field for anything that represents current value. IO fields are only for an input to be sent for example what MP I want to send etc."

This was the **critical widget rule correction**. The prior design (and an earlier line in `kistler-reference.md` §20) said `HmiIOField IOFieldType=Output` was the right choice for read-only numbers. The operator's point: "Output" mode still renders a boxed input control -- it looks editable, which is misleading.

**The canonical rule (now codified in `kistler-reference.md` §23.4 and `../hmi-unified-reference.md` §13):**

> *If the operator types into it, it's an `HmiIOField InputOutput`. Otherwise it's an `HmiText`.*

**Framework change:** `Add-DisplayValue` was rewritten to create `HmiText` with `TagDynamization` on the `Text` property -- not `HmiIOField Output`. `Add-EditableValue` is now the only path that produces an `HmiIOField`, and it always uses `InputOutput`. The framework can't produce a misleading widget by construction.

### "Now do a quick test of all dynamisation quickly just to see if everything is good. Only flag if you see issues don't fix yet."

Produced `test-dyn-quick.ps1` -- a read-only audit that enumerates every `TagDynamization` on the screen and flags anomalies:
- Empty / missing `Tag` attribute
- Tag root that isn't `MVterminalPressKistler.`
- `Singlebit` mappings whose mask isn't a power of 2
- `Singlebit` mappings with != 2 entries
- Property/widget cross-checks (HmiText must bind `Text`; HmiIOField must bind `ProcessValue`)

Final clean run: 80 dynamizations scanned, 0 flags. Established the pattern that **dynamization sanity is a separate post-build check from layout** -- both must pass before declaring done.

---

## Specific bug fixes encountered (and how they bit)

| Symptom | Root cause | Lesson # in `../lessons-learned.md` |
|---|---|---|
| Variable `$Accent` (a color) gets overwritten when later code does `$accent = New-Rect` | PowerShell variable names are case-insensitive | 29 |
| Header text overlaps a right-side badge LED on the same row | Auto-generated header text spans full card width; no way to reserve right side | Fixed by adding `-HeaderTextWidth` parameter to `New-Card` |
| `[System.Drawing.Color] $Param = $null` is a parse error | Color is a value-type struct, can't be null | 34 |
| Mandatory `[string]` param can't accept empty string | Need `[AllowEmptyString()]` attribute | 35 |
| Item names like `eo_byte_1` rendered as `eo_byte_` (number missing) | `${($eo.N)}` doesn't interpolate; needs `$($eo.N)` | 36 |
| Mojibake `a-` on six labels | PS5.1 reads `.ps1` as CP1252; UTF-8 em-dash bytes mis-decoded | 30, 47 |
| `HmiLine` renders diagonally regardless of Point1/Point2 settings | Point1/Point2 are value-type accessors; mutations don't persist | 37 |
| LED never changes color even though bit toggles | First attempt used `Bitmask` ConditionType; correct is `Singlebit` | 31 |
| Status LED bits don't match what operator sees on Kistler panel | Confused `receive.status` (decoded Kistler protocol) with `state` (FB internal diagnostics) | Documented in `kistler-reference.md` §19 |
| Four buttons collide on the same DWord command | Each button hold/toggle needs atomic read-modify-write on the shared DWord | 40 |
| Setting `Font.Size = 14` throws read-only error | Font is exposed via `SetAttribute('Size', byte)` / `SetAttribute('Weight', string)` | 38 |
| Operator complaints: "the read-only fields look editable" | `HmiIOField Output` still renders boxed input | 33 (widget rule correction) |

---

## Final screen architecture (working build)

`MVterminalPressKistler` is an instance of `LDrive_typeKistlerHmi` (the UDT in `source-xml/_udt_LDrive_typeKistlerHmi_clean.xml`). The HMI binds to it.

**Header ribbon (y=0..72)** -- plant identifier, operating state, tec unit number.

**Left rail:**
- `status_card` -- the press status LEDs (Ready, Drive Enabled, Automatic, At Standstill, At Home, At Reference, Waiting, Sequence Complete, Result OK) bound to `receive.status` bits per §19.
- `alarm_card` -- alarm LEDs bound to `alarm` bits per §19.

**Center:**
- `setpoint_card` -- operator entry fields (`HmiIOField InputOutput` on `*Set` fields: `serverJogSpeedSet`, `serverJogMaxForceSet`, `cfgMpNumSet`, etc.).
- `command_card` -- hold-style buttons writing to `move` Word bits (Jog Fwd/Back, Run Sequence, Home, Reference, Resume After Wait, Clear Faults). Each button echoes the corresponding `send.control` bit via `BackColor` Singlebit binding.
- `process_card` -- live force/displacement values from `receive.PVcurrentValueX/Y`.
- `eo_card` -- six rows of EO values: three real columns (PV_EO1..3), three byte columns (PV_E04..06). Byte = 0 is pass; non-zero is Kistler fault code (§21).

**Right:**
- `echo_card` -- "Current (from device)" vs "Sent to device" side-by-side echo table. Confirms the command bus is reaching Kistler.
- `trend_card` -- (placeholder for force/displacement trend; future work).

**Layout invariants verified:** 3893 assertions pass before save.

---

## Things explicitly deferred (not done, not lost)

1. **SVGHMI faceplate** -- the regular screen approach won. Faceplate files are preserved in `faceplate/` for future migration (`LSicar_KistlerPressFp.svghmi`, `kistler_faceplate.svg`, `kistler_faceplate_generator.py`). The Openness import path for V20 SVGHMI is blocked on schema availability -- see `kistler-reference.md` §13.
2. **Trend control** -- placeholder card on screen; native WinCC Unified trend integration deferred.
3. **Additional alarm LEDs** -- currently 8; could add Home Timeout (`alarm.x7`) and Ref Timeout (`alarm.x8`) for parity with CycleTimeout (`alarm.x6`).
4. **Promotion to Screen Type (faceplate)** -- blocked on faceplate import schema (`kistler-reference.md` §14 footnote).

---

## Files this session touched in `Claude Code/`

- Created / heavily edited:
  - `kistler-design.ps1` (the framework)
  - `build-kistler-pro-v3.ps1` (the consumer)
  - `test-dyn-quick.ps1` (this session's dynamization audit)
  - `fix-emdash.ps1` (this session's surgical post-fix)
- Memory updates (`kistler_final.md`):
  - §16 -- Singlebit vs Bitmask
  - §17 -- SICAR colors
  - §18 -- screen state checkpoint
  - §19 -- FB-verified UDT bit map (single source of truth)
  - §20 -- canonical widget pattern (later superseded by §23.4)
  - §21 -- EO byte = result encoding
  - §22 -- layout test suite (six tests)
  - §23 -- HMI build recipe (proven workflow)
- Repo updates (this directory + parents):
  - `../lessons-learned.md` -- expanded from §27 to §47 (20 new lessons)
  - `../hmi-unified-reference.md` -- new §§13-15 (widget rule, layout pattern, bind recipes) + 6 new known-limitations
  - `../../README.md` -- badges, documentation index, contributing pointers
  - `../../CHANGELOG.md` -- complete log of this session's additions
  - `./README.md` -- this directory's index
  - `./session-log.md` -- this file
