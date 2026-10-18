# Refactor notes

What each refactor session changed. The plan is in refactor-plan.md.

## Session 1: battle behavior fixtures

Date: 2026-10-17

Added `new-game-project/tests/battle_behavior_smoke.gd` against the existing scene-backed rules.
No production rules, scenes, card data, or save formats were changed. Session 2 has not started.

The fixtures use small explicit card dictionaries and reset battle state between cases. They cover:

- Damage effectiveness and rounding, defenses, no immediate counterattack, no overkill, and Piercing.
- Burn/Poison upkeep before regeneration and Bleed after attacking.
- Last-unlocked-first drawing, sealed cards, hand capacity, and equal duplicate dictionaries.
- Tutor cancellation/confirmation, payment, graveyard recording, and temporary tax expiry.
- Actual End Turn, round/first-side progression, resource refill, drawing, and Floor 1 action limits.
- Actual sacrifice removal, draw/Burn rewards, major evolution entry, and insufficient sacrifices.

One existing draw behavior is deliberately pinned: Disaster drawing selects the last unlocked dictionary,
but `Array.erase` removes the first equal dictionary. The selected last dictionary can therefore remain
in the pile when equal copies exist. This session records that behavior without changing it.

### Headless validation

Run from `new-game-project` with Godot 4.7.2:

```powershell
godot --headless --path . --script res://tests/battle_behavior_smoke.gd
```

The eight Session 1 guard suites were run before and after adding the fixtures:

| Suite | Before | After |
|---|---|---|
| mechanics_smoke.gd | PASS | PASS |
| expansion_smoke.gd | PASS | PASS |
| contingency_plans_smoke.gd | PASS | PASS |
| board_targeting_plans_and_events_smoke.gd | PASS | PASS |
| map_sorting_caps_and_saves_smoke.gd | PASS | PASS |
| explorer_mode_smoke.gd | PASS | PASS |
| final_boss_smoke.gd | PASS | PASS |
| hover_graveyard_smoke.gd | PASS | PASS |

The new behavior suite passed. No baseline failures were observed in the eight guard suites.
Each test runs in its own headless process; the new suite has no capture or simulation output.

Validation used the current working tree, which already contained unrelated uncommitted game changes.
Those changes are excluded from the Session 1 commit. Results do not claim that the older committed
game revision alone supports these fixtures.

Only `github-publish` was modified. Mirror comparison and synchronization were skipped as requested.
No rendered viewport checks were run.

## Session 2: battle data and snapshot adapters

Date: 2026-10-17

Added `battle_state.gd`, a detached `RefCounted` data container, and `battle_snapshot.gd`, a read-only
adapter from the existing manager and cards. The adapter is currently exercised only by tests.
No existing production files, combat functions, save/load behavior, or card data were changed.
Session 3 has not started.

### Snapshot contract

- Sides hold health, barriers, resources, battle buffs, and supplied run buffs.
- Both lane arrays have exactly four positions. An empty string represents an empty lane.
- Cards have snapshot-local string IDs and copied definition/runtime dictionaries. Independent equal
  definitions receive distinct IDs. An existing shared dictionary reference across piles retains one ID,
  preserving the duplicate-draw alias characterized in Session 1.
- Hand, draw, evolution, and Response graveyard order is preserved. There is no new Disaster graveyard.
- Live runtime includes base definition, max health, statuses, modifiers, last attack round, Plan fields,
  evasion, and graveyard-recorded flags. Current HP and temporary costs/seals remain in the definition.
- Plans refer to card IDs and `{side, lane}` destinations. Pending choices contain IDs rather than
  Nodes or callbacks. Boss bookkeeping, round/phase, coin, adaptation, log, and graveyard serial are copied.
- IDs are stable for repeated captures of an unchanged scene, not durable live identifiers across plays.
  The adapter does not assign metadata to live nodes or install a competing state owner.
- `to_dict()` and `load_snapshot()` deep-copy data. JSON keys and integral numeric values are normalized;
  StringName keys introduced by GDScript dictionary property syntax become strings. Fractional numbers
  remain fractional. Objects, Callables, and scene transforms are rejected.

The state reserves `actions_used = -1`, `rng_state = ""`, and `result = ""` as unknown values.
The manager exposes neither the enemy loop's local action counter nor the global battle RNG state,
and it does not retain a standalone result value for exhaustion endings. This session does not invent
those values or change rule ownership to obtain them. The director's separate RNG state is copied to
`run_rng_state` as a string. Future engine sessions must supply authoritative battle values.

This is a data snapshot round-trip, not live-scene restoration or a replacement for the v1 save format.
Those integrations remain scheduled for Session 9.

### Validation

All checks used Godot 4.7.2 with `--headless --path new-game-project --script res://tests/<name>.gd`.

| Suite | Before | After |
|---|---|---|
| map_sorting_caps_and_saves_smoke.gd | PASS | PASS |
| graveyard_save_compatibility_smoke.gd | PASS | PASS |
| battle_behavior_smoke.gd | PASS | PASS |
| battle_state_smoke.gd | New | PASS |

The new suite covers dictionary/JSON round-trips, duplicate IDs, four-lane ordering, shared references,
deep-copy isolation, side/progress mappings, statuses, pending choices, Plan slot conversion, boss fields,
graveyard metadata, and exclusion of Node/Callable/transform values.

No existing failures were observed. The first run of the new suite exposed numeric JSON comparison
and StringName-key issues in the new code. Both were corrected by normalizing copied data; the next
run passed with no script errors. No existing tests were weakened.

Only `github-publish` was changed. No mirror synchronization, rendered audits, or simulations were run.

## Session 3: read-only calculations

Completed in github-publish only. Session 4 has not started.

### Changes

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

### Parity before integration

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

### Headless verification

| Suite | Before wrappers | After wrappers |
|---|---|---|
| battle_engine_smoke.gd | PASS, 63,729 comparisons | PASS, same count and original checksum |
| battle_behavior_smoke.gd | PASS | PASS |
| mechanics_smoke.gd | PASS | PASS |
| expansion_smoke.gd | PASS | PASS |
| contingency_plans_smoke.gd | PASS | PASS |

All runs used Godot 4.7.2 headlessly. No test failed during the resumed session. The previous
attempt's Engine name collision and typed-array assignment error are resolved. No assertions
were removed to obtain passing results. Logs were written outside the repository under TEMP.
No rendered audits, balance simulations, or mirror syncing were performed.

Session 4 requires a separate request. Damage/status mutation and live state ownership remain
in their existing scripts.
