# Worked Example: Kistler maXYmos NC Press HMI

A complete worked example of using TIA Portal Openness to build a non-trivial WinCC Unified HMI screen end-to-end against a real PLC FB and UDT. It exists so future sessions never lose the domain knowledge accumulated while bringing up the Kistler maXYmos NC console.

**Nothing here has been paraphrased.** `kistler-reference.md` is the full memory file verbatim. `session-log.md` is the chronological narrative. The scripts are the actual scripts that produced the working `_Kistler_Press_01` screen. Source XML files in `source-xml/` are the ground-truth FB and UDT exports.

---

## Where to start

| If you want to... | Read |
|---|---|
| Understand the device, FB anatomy, UDT, bit maps, build recipe | [`kistler-reference.md`](kistler-reference.md) (1473 lines -- the bible) |
| See *why* the framework looks the way it does and what user feedback shaped it | [`session-log.md`](session-log.md) |
| Use the layout-aware design framework on a new screen | [`scripts/kistler-design.ps1`](scripts/kistler-design.ps1) -- dot-source it |
| See the framework in action | [`scripts/build-kistler-pro-v3.ps1`](scripts/build-kistler-pro-v3.ps1) |
| Re-extract bit maps when the FB changes | [`scripts/extract_bit_map.py`](scripts/extract_bit_map.py) reading [`source-xml/_kistler_fb.xml`](source-xml/_kistler_fb.xml) |
| Verify dynamizations after a build | [`scripts/test-dyn-quick.ps1`](scripts/test-dyn-quick.ps1) |
| Verify layout after a build (external pass) | [`scripts/test-kistler-final.ps1`](scripts/test-kistler-final.ps1) -- mostly subsumed by `Test-LayoutSelfCheck` in the framework |
| Do a surgical post-edit (without rebuilding) | [`scripts/fix-emdash.ps1`](scripts/fix-emdash.ps1) -- template for "find by name pattern, mutate, save" |

---

## Directory layout

```
kistler-example/
├── README.md                      (this file)
├── kistler-reference.md           1473 lines -- full domain bible verbatim
├── session-log.md                 chronological narrative + user feedback
├── kistler_textlist_import.xlsx   text-list import sheet for supervision messages
│
├── scripts/                       canonical scripts (the final framework + audits)
│   ├── kistler-design.ps1         layout-aware HMI design framework
│   ├── build-kistler-pro-v3.ps1   working build script using the framework
│   ├── build-kistler-final.ps1    v2 build script, open-coded (kept for reference patterns)
│   ├── extract_bit_map.py         FB-XML to bit-map extractor (re-run when FB changes)
│   ├── test-kistler-final.ps1     standalone layout test suite (6 tests)
│   ├── test-dyn-quick.ps1         dynamization audit (read-only)
│   ├── fix-emdash.ps1             surgical post-edit example
│   ├── add-kistler-supervisions.ps1   supervision message injector
│   └── improve-kistler.ps1        FB improvement / instrumentation script
│
├── source-xml/                    ground-truth TIA exports (the basis for kistler-reference.md)
│   ├── _kistler_fb.xml            707 KB -- LSicar_KistlerPress FB XML (51 networks)
│   ├── _udt_LDrive_typeKistlerHmi.xml + _clean.xml   HMI UDT (what MVterminalPressKistler is)
│   ├── _udt_LDrive_typeKistlerPressDataRecv.xml + _clean.xml   receive substruct UDT
│   ├── _udt_LDrive_typeKistlerPressDataSend.xml + _clean.xml   send substruct UDT
│   ├── _udt_LDrive_typeKistlerProcessValues.xml + _clean.xml   process values substruct
│   ├── _udt_LDrive_typeKistlerParameters.xml + _clean.xml      parameters substruct
│   ├── _udt_kistler_hmi_full.xml                              full HMI UDT (combined)
│   ├── _kistler_export.xml                                    full project-level export
│   ├── LSicar_KistlerPress_improved.xml                       FB with original improvements
│   └── LSicar_KistlerPress_with_supervisions.xml              FB with supervision XML added
│
├── faceplate/                     deferred SVGHMI faceplate work (kept for future migration)
│   ├── LSicar_KistlerPressFp.svghmi          the V1 faceplate file
│   ├── _kistler_faceplate_v1.svg + .svghmi   earlier faceplate iteration
│   ├── kistler_faceplate.svg                 design SVG source
│   ├── kistler_faceplate_generator.py        Python generator that produces the .svghmi
│   ├── create_kistler_faceplate_tia.ps1      faceplate import attempt v1
│   ├── create_kistler_fp2.ps1                faceplate import attempt v2
│   └── bind-kistler-faceplate.ps1            faceplate binding helper
│
├── notes/                         human-written reference notes that preceded kistler-reference.md
│   ├── KISTLER_FACEPLATE_BUILD_SUMMARY.md
│   └── LDrive_typeKistlerHmi_UDT_DECIPHERED.md
│
└── earlier-builds/                build script lineage (kept so the evolution is traceable)
    ├── build-kistler-pro.ps1                 v2 immediately before the framework refactor
    ├── build-kistler-screen.ps1              v1 first full screen build
    ├── build-kistler-screen-bound.ps1        v1.5 with tag bindings added
    ├── build-kistler-tags-only.ps1           tag-table-only build
    ├── test-kistler-mapping.ps1              mapping experimentation script
    ├── tia_kistler_mastercopy_probe.ps1      mastercopy probe
    └── export-kistler-docs.ps1               doc-export helper
```

---

## Where to look first for a given question

| Question | Section in `kistler-reference.md` |
|---|---|
| What does bit X of `state` / `alarm` / `move` / `receive.status` / `send.control` mean? | **§19** (FB-verified ground truth -- always trust this over any other section, including §8 which is deprecated) |
| What widget do I use to display X / make X editable? | **§23.4** ("If the operator types into it, it's an HmiIOField. Otherwise it's an HmiText.") -- supersedes earlier §20 advice |
| How do I run a layout test after build? | **§22** + the built-in `Test-LayoutSelfCheck` in `kistler-design.ps1` |
| How are Kistler EO byte results encoded (pass / fail)? | **§21** (byte = 0 -> pass; byte != 0 -> Kistler fault code -- don't add redundant Result columns) |
| What's the working Openness recipe (attach, build screen, save, compile, button events)? | **§14** |
| How do I extract bits via MappingTable (Singlebit vs Bitmask)? | **§16** |
| What SICAR colors do I use (Light green / Orange / Red / etc.)? | **§17** |
| What does the device do (operating modes, MPs, pages, sequences, cycle flow)? | **§§1-5** |
| What does the 200-byte fieldbus look like? | **§6** (IN + OUT byte.bit tables) |
| What's the FB anatomy (51 networks, Inputs, Outputs)? | **§7** |
| How is supervision (alarms / warnings / messageErrors) designed? | **§10** |
| How do I build an SVGHMI faceplate? | **§11** (deferred -- currently using regular screen) |
| What's the proven HMI build workflow? | **§23** (framework API + skeleton + gotchas + speed rule + verification suite) |

**Conflict resolution rule:** if §19 disagrees with anything else in `kistler-reference.md` (especially §8 which is deprecated), §19 wins -- it was extracted directly from the FB XML by `extract_bit_map.py` reading `source-xml/_kistler_fb.xml`.

---

## Quick recap of the architecture

```
Kistler device  <--200-byte fieldbus-->  LSicar_KistlerPress FB  <--LDrive_typeKistlerHmi[]-->  HMI screen
                                         (51 LAD networks)        (UDT array indexed by                _Kistler_Press_01
                                                                   tecUnitNumber)                     (204 items, 80 binds)
```

- **PLC side:** `LSicar_KistlerPress` (v0.0.8) does the 200-byte DPRD_DAT / DPWR_DAT exchange, runs the cycle handshake, raises supervision messages, and writes to `interfaceHmi[tecUnitNumber]` for the HMI to read.
- **HMI side:** binds to `MVterminalPressKistler` (an instance of `LDrive_typeKistlerHmi`). Reads via `receive.*`, `state`, `alarm`, `send.*`. Writes via `move` (Word, bit-level commands) and the `*Set` setpoint fields.

The critical architecture rule (verified §19): the HMI never writes to `send.*`. `send.*` is FB-owned echo of what was actually transmitted to Kistler. To command the press, write `move` bits and the FB translates them.

---

## What this directory proves

The Kistler build is the source of every HMI-specific lesson now living in `../lessons-learned.md` (§§28-47) and the canonical patterns in `../hmi-unified-reference.md` (§§13-15). If you're debugging an HMI build and a lesson there doesn't make sense in isolation, the working code in `scripts/` + the user feedback in `session-log.md` is the ground truth.

Specifically, this directory is the proof for:

- **The widget rule** -- `Add-DisplayValue` in `kistler-design.ps1` creates `HmiText` (not `HmiIOField Output`) because operators kept misreading boxed-input widgets as editable. See `session-log.md` for the user feedback that drove this.
- **The layout framework** -- 3893 layout assertions catch bugs at call time instead of after a 30-second build+compile cycle. See `New-Card` / `Add-*` / `Test-LayoutSelfCheck`.
- **Singlebit mapping** -- every LED on every status / alarm / send.control / move bit uses `ConditionType=Singlebit` with `Condition = 2^bit` (UInt64) and exactly 2 mapping entries. See `_BindBit` helper.
- **Hold-style button command bus** -- jog buttons use `Activated`+`Deactivated` events on a shared `move` DWord, atomically OR-ing/ANDing the bit mask. See `Add-Button`.
- **FB-verified bit maps** -- `extract_bit_map.py` reading `source-xml/_kistler_fb.xml` is the only authoritative source for which bit means what. Don't trust the FB's text-list comments -- they drift from the actual coil wiring.
- **Surgical post-edits over rebuilds** -- `fix-emdash.ps1` is the canonical example of "find by name pattern, mutate, save". Sub-second instead of 30-second rebuild.
- **Dynamization audit as separate post-build gate** -- `test-dyn-quick.ps1` is read-only and validates every binding (property name vs widget type, tag root, Singlebit mask is 2^n, entries == 2). Last clean run: 80 dynamizations, 0 flags.

---

## Files explicitly preserved even though deferred

- `faceplate/*` -- SVGHMI faceplate work. Regular screen approach won this session, but the V20 faceplate import path is unblocked future work. Keeping the design SVG + the Python generator + the import attempts so the next session doesn't start from scratch.
- `earlier-builds/*` -- the build script lineage. The framework wasn't invented from scratch; each predecessor solved one piece. Keeping them so the evolution is traceable and so anyone debugging a specific dynamization pattern can see the long-form pre-framework version.
- `notes/*` -- human-written reference notes that preceded the consolidated `kistler-reference.md`. Some details (especially the UDT field-by-field deciphering in `LDrive_typeKistlerHmi_UDT_DECIPHERED.md`) read differently from the final bible and are useful for triangulating intent.

---

## Verification

Every file in this directory was copied byte-for-byte from the working `C:\Users\MudasserWahab\Claude Code` build environment. SHA-256 confirmed. If anything looks off, compare against the source there before assuming corruption.
