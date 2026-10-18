# Refactor notes

Use the [refactor plan](refactor-plan.md) for the remaining steps. Sessions 1-3 are complete: behavior fixtures, detached snapshots and read-only battle queries. Session 4 has not started. Damage/status mutation, combat flow and live state ownership remain in scene scripts. Snapshots are not the v1 save format or live-scene restoration.

## Snapshot contracts

`battle_state.gd` stores plain data. `battle_snapshot.gd` reads the scene without creating a second state owner.

- Sides store HP, barriers, resources, battle buffs and run buffs.
- Each side has four ordered lanes. An empty string means an empty lane.
- Cards use snapshot-local string IDs and copied definition/runtime data. Equal independent definitions get distinct IDs. Shared dictionary references retain one ID.
- Hand, draw, evolution and Response graveyard order is preserved. No Disaster graveyard is added.
- Runtime data includes max HP, statuses, modifiers, attack timing, Plan fields, evasion and the graveyard-recorded flag. Current HP, seals and temporary costs remain in the definition.
- Plans and pending choices use card IDs and side/lane addresses instead of Nodes or callbacks. Boss, phase, coin, adaptation and log state are copied.
- IDs are stable across captures of an unchanged scene, not durable identifiers across plays. The adapter adds no metadata to live nodes.
- Snapshot export and loading deep-copy data. Keys and StringNames become strings; integral floats become integers. Fractions remain fractional. Objects, Callables and transforms are rejected.

`actions_used = -1`, `rng_state = ""` and `result = ""` mean unknown. The manager does not expose the local enemy action counter, global battle RNG or a standalone exhaustion result. The director's RNG is stored separately as a string in `run_rng_state`. Future integration must supply authoritative values.

## Behavior to preserve

Disaster draw selects the last unlocked dictionary, but `Array.erase` removes the first equal dictionary. The selected one can remain in the pile when equal copies exist. Preserve this aliasing during extraction.

Off-board synergy also has an existing quirk: lane index -1 considers lane 0 its right neighbor. Do not fix it during a behavior-preserving refactor.

`game.TYPE_CHART` remains an alias of `BattleEngine.TYPE_CHART` for AI and inspection callers. Preview queries must still work without a live battle manager. Query adapters share data only for synchronous reads.

## Parity guard

The engine fixture retains the original-output checksum:

`3a78c90cf0a51ce89f03edab9b9658252b3117a5ac646670eaa0b72692fa3d7e`

It comes from the original calculations before wrapper integration. Keep that independent baseline so comparisons do not become circular. Use the behavior, state and engine smoke fixtures alongside the guards listed for each migration step. Preserve rules and balance while moving ownership.
