# Midnight DRRills Improvements Implementation Plan

**Goal:** Complete the 44 requirements in the supplied Pasted text.txt, with focused validation.
**Architecture:** Extend the current manager, board targeting, presentation and editable UI scenes. Import reusable art and resources. Keep combat resolution and run initialization authoritative.
**Tech stack:** Godot 4.7.2, typed GDScript, PNG textures, glTF binary meshes.
**Spec:** User attachment `c511a21f-8a64-458f-b969-9acd1c95b334/Pasted text.txt`.

## Constraints and decisions

- Work in `github-publish`, branch `main-1`, current HEAD `997eaae`. The other project copy is older.
- Preserve existing edits to README.md, docs/singleplayer.md, RUN_GUIDE.md, and untracked fonts.
- User explicitly requests continuous implementation without routine approvals, commits or pushes. This overrides skill approval/commit gates.
- Use current architecture and narrow edits. No unrelated balance changes. Alarm Sweep costs exactly 4.
- Player sealing affects deployed disaster cards only. Enemy hand locks remain a separate existing mechanic.
- One round means this round when Response plays first, next round when Response plays second. Pending seals do not block current-round actions.
- Coin geometry is authored offline and exported to GLB. Approved artwork determines both face designs.
- Menu theme applies only to the requested overlays. Existing options and callbacks remain intact.

## Checklist

- [x] Inspect copies, instructions, references, current state and tooling.
- [x] 1. Sealing and Alarm Sweep: add focused timing/target/restriction tests; change manager, battle rules/snapshot and card display; validate evolution planner and sacrifice entry point.
- [x] 2. Bottom HUD and menus: derive clean images preserving source files; add dynamic labels; lower bounded controls; cream suspended menu theme; test controls and menu navigation.
- [x] 3. Symbols: inventory ZIP and all effect keys; author imported pixel icons with distinct missing meanings; remove runtime shape generation; fit centered symbol grid and retain tooltips/counts.
- [x] 4. Debug boss encounters and fog: invoke existing run/encounter setup; support each floor boss; map/arena fog respects settings and cleans up; focused smoke checks.
- [x] 5. Approved coin: embedded-material octagonal beveled GLB with raised sun/moon details; replace presentation mesh; test import, geometry and both outcomes.
- [x] 6. Elemental/status particles: reusable textures/materials/scenes; attack windup/impact and status application/tick/persistent lifecycle; honor effects settings and cleanup; focused smoke tests.
- [x] 7. Validation: relevant existing smoke tests, targeted rendered checks of changed screens/assets, diff review. Record exact results and limitations.

## Review focus

- Sealed targets removed, recovered, saved or replaced must not transfer restrictions to another card.
- Both turn orders, pending activation, expiration, automated sacrifice and no-target cancellation.
- Crowded card symbols and bottom controls at 1280x800 and 1440x900.
- Debug entry during overlays must cancel old encounter coroutines and initialize coherent run state.
- Particle and fog cleanup on settings changes, card removal and battle exit; coin cancellation remains safe.

## Execution ledger

- Initial inspection: Godot console executable available in Downloads. No Blender executable found on PATH or Program Files.
- Initial baseline: no product files changed by this task yet.

- Tasks 1–6 complete: board sealing/Alarm Sweep, HUD/menu skin, imported pixel symbols, boss shortcuts/fog, raised sun/moon GLB, integrated GPU attack/status particles.
- Independent review found menu skin loss on resize/inspection restore and VFX surviving battle completion. Both fixed; dedicated regression assertions now pass.
- Validation complete: 23 clean smoke suites, clean import and diff check, targeted Compatibility 1440×900 and Forward+ 1280×800 captures. Two unrelated legacy suite problems were reproduced using the original director and documented, without changing their product behavior.
- Full requirement mapping, commands, artifacts, assumptions and baseline defects: `docs/midnight-improvements-validation.md`.
- User's original README/font work preserved. Relevant existing guide/design instructions updated narrowly. No commits, pushes or package installations.
