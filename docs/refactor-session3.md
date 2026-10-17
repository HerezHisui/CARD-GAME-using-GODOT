# Session 3: read-only calculations

Completed in github-publish only. Session 4 has not started.

## Changes

- Added battle_engine.gd with pure queries for buffs, resource growth, damage scaling,
  seals, status conditions, attack timing, modifiers, synergy, and damage calculation.
- Kept battle_rules.gd as the source of buff totals and definitions.
- Added battle_query_adapter.gd to resolve scene cards and neighboring lanes into plain data.
  It shares read-only dictionaries during synchronous queries and does not maintain another battle state.
- Converted the fourteen manager queries and four card queries listed in Session 3 into thin wrappers.
- Kept game.TYPE_CHART as an alias of BattleEngine.TYPE_CHART for AI and inspection callers.
- Kept previews independent of a live battle manager for modifier, attack, and timing queries.

No balance, status transitions, card data, save logic, or scene presentation changes were made.
The existing off-board synergy behavior is preserved: an off-board index of -1 considers lane 0
as its right neighbor. This session records that behavior rather than correcting it.

## Parity before integration

The resumed test setup uses assign() for the typed modifiers array. The engine test passed
63,729 comparisons against the original manager/card implementations before any wrapper switched.
A second original-code run captured a SHA-256 checksum of the expected outputs, retained in the
test to prevent comparisons becoming circular once both paths delegate to the engine:

`3a78c90cf0a51ce89f03edab9b9658252b3117a5ac646670eaa0b72692fa3d7e`

Coverage includes both sides, all element pairings plus unknown elements, zero/negative attack,
rounding, minimum damage, armor/fragile ordering, battle/run buffs, isolation, living/dead neighbors,
stationary/off-board cards, preview overrides, Plan attack bonuses, Sluggish intervals, Rampaging,
conditions with self/target/null subjects, harmful status totals, seals, and input immutability.
A resource calculation also executes before any scene is instantiated. Engine inputs contain no
scene references; this session's integration parity harness still instantiates the original scene.

## Headless verification

| Suite | Before wrappers | After wrappers |
|---|---|---|
| battle_engine_smoke.gd | PASS, 63,729 comparisons | PASS, same count and original checksum |
| battle_behavior_smoke.gd | PASS | PASS |
| mechanics_smoke.gd | PASS | PASS |
| expansion_smoke.gd | PASS | PASS |
| plans_notes_smoke.gd | PASS | PASS |

All runs used Godot 4.7.2 headlessly. No test failed during the resumed session. The previous
attempt's Engine name collision and typed-array assignment error are resolved. No assertions
were removed to obtain passing results. Logs were written outside the repository under TEMP.
No rendered audits, balance simulations, or mirror syncing were performed.

Session 4 requires a separate request. Damage/status mutation and live state ownership remain
in their existing scripts.
