# Extract a headless battle model and engine

## Design

Preserve current rules and balance. Move battle decisions out of scene nodes incrementally, keeping manager wrappers until existing callers and smoke tests have migrated.

Inspection found that rules also live in `card_3d.gd`, `contingency_rules.gd`, and `final_boss.gd`. Extracting only the two requested scripts would leave combat dependent on scenes.

### `battle_state.gd`: data only

Use a typed `RefCounted` containing serializable data, without Node references, scene paths, timers, or callbacks:

- **Sides:** hero HP/max HP, barriers, current/capped resources, battle buffs and supplied run buffs.
- **Cards:** unique battle instance ID, copied definition/base definition, current/max HP, modifiers, statuses, last attack round, temporary Plan fields, recovery flags.
- **Zones:** four ordered lanes per side, ordered hands/draw/evolution piles, and the existing Response-only graveyard.
- **Progress:** round, phase, first side, encounter kind/floor, actions used, adaptation checkpoint, result.
- **Pending choices:** effect/source ID and eligible target IDs or lane indices.
- **Special rules:** Plans state and boss stage/intent bookkeeping.
- **Randomness:** explicit battle RNG state. Cosmetic animation randomness remains outside the model.

Keep existing card dictionaries and JSON schemas. Unique instance IDs distinguish duplicate cards; preserve current draw order and duplicate-selection behavior during conversion.

### `battle_engine.gd`: pure queries and transitions

Use static functions on `RefCounted`:

- Queries such as `legal_plays(state, side)`, `calc_damage(...)`, and `choose_enemy_action(state)` do not mutate inputs.
- Commands such as `play_card(...)`, `resolve_choice(...)`, `start_round(...)`, and `advance_combat(...)` return `{state, events, error}`.
- A successful command updates one deep copy of the state. Invalid commands leave the supplied state unchanged.
- Events contain data only: card IDs, lanes, damage, status changes, draws, phase changes, choices, and battle results.
- Resolve combat in small deterministic steps so the manager can animate each attack. A headless runner repeatedly advances those same steps without waiting.
- No loading assets, reading files, `await`, SceneTree access, UI imports, or calls back into the manager.

Retain `battle_rules.gd` for its existing buff definitions, totals, and descriptions. Do not duplicate those tables.

### What stays in the scene/UI layer

**Manager:** card-node registry, spawning/freeing visuals, slot transforms, input gating, dragging/hovering, camera, lighting, animation, sound, HUD refresh, event playback, and encounter cancellation.

**Run director:** title/map/shop/workshop/rewards, collection progression, supplies, floor transitions, modal layout, inspection, and choice presentation. Keep post-victory triage here because it is run progression, triggered once by a battle-result event.

Logical legality belongs to the engine. Modal visibility, active drags, and presentation locks remain additional manager input checks.

## Ordered migration sessions

Each row is one independently testable session and one commit. Existing public methods remain adapters until their callers migrate.

| Session | Functions/data moved or adapted | Main risk | Guards and acceptance |
|---|---|---|---|
| **1. Establish behavior fixtures** | Move nothing. Add small state fixtures and characterization assertions around damage, draw order, utilities, round progression, and sacrifices. Record relevant source/mirror differences without overwriting unrelated work. | Mistaking existing behavior for a refactor regression. | Run `mechanics_smoke.gd`, `expansion_smoke.gd`, `plans_notes_smoke.gd`, `notes3_smoke.gd`, `notes4_smoke.gd`, `explorer_mode_smoke.gd`, `final_boss_smoke.gd`, and `hover_graveyard_smoke.gd` headlessly. Record existing failures before proceeding. |
| **2. Introduce battle data and adapters** | Add `BattleState`; map manager fields and card runtime fields to IDs/zones. Add snapshot conversion used by tests, initially without changing ownership. Convert slot references to side/lane indices. | Losing duplicate cards, transient statuses, or zone order. | New `battle_state_smoke.gd`: round-trip fixtures, duplicate IDs, four-lane occupancy, deep-copy isolation, and no Node/Callable values. Existing `notes4_smoke.gd` and `graveyard_save_compatibility_smoke.gd` guard persistence fields. |
| **3. Extract read-only calculations** | Manager: `overclock_stacks`, `resource_growth`, `incoming_damage`, `buffs_for`, `buff_value`, `attack_bonus`, `is_sealed`, `status_stacks`, `condition_met`, `conditional_attack_bonus`, `attack_strikes`, `_calc_damage`, `_synergy_bonus`, `definition_has_modifier`. Card: rule portions of `has_modifier`, `effective_attack`, `adjusted_damage`, `can_attack`. Move `TYPE_CHART` into the engine. | Changed rounding, minimum damage, isolation/synergy, or attack timing. | New `battle_engine_smoke.gd` compares old and extracted query results before switching wrappers. Run `mechanics_smoke.gd`, `expansion_smoke.gd`, `plans_notes_smoke.gd`. Queries must leave their inputs unchanged. |
| **4. Extract card damage and statuses** | Card: rule portions of `heal`, `take_damage`, `_die`, `add_modifier`, `add_status`, `status_upkeep`, `after_attack`, `cleanse`. Manager: rule portions of `_damage_side`, `record_graveyard`, `destroyed_response_units`, `recoverable_units`, `recovered_definition`. Keep visual portions in place. | Wrong prevention order, duplicate death records, periodic damage bypass changes. | Engine fixtures for armor → damage scaling → guard → barrier → extraction → HP/death; Burn/Poison/regen/Bleed order; recovery once per unit. Run `plans_notes_smoke.gd`, `hover_graveyard_smoke.gd`, `graveyard_save_compatibility_smoke.gd`, `final_boss_smoke.gd`. |
| **5. Extract drawing, plays, and utility choices** | Manager: rule portions of `draw_cards`, `enemy_draw_cards`, `enemy_draw_evolutions`, `prepare_card_data`, `is_opening_blocker`, `smooth_opening_hand`, `try_play_card`, `on_card_played`, `apply_formation_effect`, `try_utility`, `consume_utility`, `complete_utility_choice`, `increase_cost`, `expire_tax`. Convert relocation completion into an engine command; keep drag selection/cancellation UI outside. | Charging canceled effects, stale targets, hand overflow, or changing utility placement requirements. | Engine tests verify occupied/wrong-side lanes, seals, insufficient resources, canceled choices, tutor/recovery duplicates, tax expiry, and opening smoothing. Run `mechanics_smoke.gd`, `expansion_smoke.gd`, `notes3_smoke.gd`, `hover_graveyard_smoke.gd`, `explorer_mode_smoke.gd`. |
| **6. Extract Disaster decisions and evolution** | `enemy_action_limit`, `best_disruption_target`, `choose_base_threat`, `_pick_smart_threat_slot`, `score_threat`, `live_ai_definition`, `board_score`, `best_evolution_plan`, `relocate_enemy_ally`, `choose_ai_buff`, `sacrifice_reward`, `major_evolution_entry`, and rule portions of `enemy_utility`/`_enemy_turn`. | Altering normal AI randomness, elite/boss scoring, sacrifice ordering, or action/Tension accounting. | Compare decisions under fixed RNG states; verify the board-presence penalty, sacrifice rewards before removal, and evolution entry effects. Run `improvements_smoke.gd`, `variety_smoke.gd`, `expansion_smoke.gd`, `explorer_mode_smoke.gd`, plus new engine cases for each migrated branch. |
| **7. Extract Plans and Warden rules** | Plans: `bank_unused_energy`, `eligible`, `can_arm`, `coordination_targets`, `arm`, `try_extract`, `apply_combat`, `finish_combat`. Boss: rule portions of `accept_damage`, `pillars`, `guardian`, `redirect_target`, `on_card_destroyed`, `prepare_round`, `settle_curses`, `hit_lane`, `resolve_intent`; convert spawning into card-created events. | Extraction during damage, boss stage transitions, repeated intents, or temporary bonuses surviving combat. | Run `plans_notes_smoke.gd`, `notes3_smoke.gd`, `blood_pact_inspection_debug_smoke.gd`, `final_boss_smoke.gd`. Add scene-free fixtures for each boss stage and each unlocked Plan. Keep descriptions and presentation wrappers outside. |
| **8. Extract round/combat orchestration** | Rule portions of `_begin_round`, `continue_round`, `_apply_round_modifiers`, `_begin_player_turn`, `_on_draw_button_pressed`, `_on_end_turn_pressed`, `_combat`, `_side_attacks`, `resolve_attack`, `resolve_single_strike`, `resolve_blood_pact`, `_check_game_over`, `add_global_buff`. Manager consumes events instead of deciding results. Director buff screens submit choices instead of applying combat effects directly. | Attack order, follow-up targeting, double result delivery, or round advancement during canceled animation. | Engine replay covers both first sides, every lane, Sluggish, Piercing, no overkill, Blood Pact, adaptation pauses, exhaustion, and boss intents. Run the relevant suites above plus `run_smoke.gd`. Same commands/RNG must produce identical state and events twice. |
| **9. Make state authoritative and finish integration** | Remove transitional snapshot ownership. Manager/card methods become engine-command or query adapters. Update save checkpoint/resume to serialize battle data through a legacy-v1 adapter. Update director/debug mutations to use explicit engine commands. Remove superseded rule implementations only after callers migrate. | Dual state ownership, broken old saves, or scene nodes applying rules a second time. | Run `battle_state_smoke.gd`, `battle_engine_smoke.gd`, `notes4_smoke.gd`, `graveyard_save_compatibility_smoke.gd`, `ui_interaction_smoke.gd`, and `run_smoke.gd` headlessly. Verify legacy saves and resumed battles, then sync changed files and repeat affected checks in the mirror. |

## Acceptance and working rules

- Add a scene-free test runner that preloads only the state, engine, and data rules. It must finish normal, elite, and Warden fixtures without instantiating the game scene or cards.
- Preserve formulas, card counts, existing limits, effect order, and gameplay choices. Unexpected existing behavior is recorded separately, not corrected during extraction.
- During migration, use one-way adapters. Never maintain independently mutable model and node copies as competing sources of truth.
- Save compatibility retains the existing stable checkpoint boundaries. Do not begin saving mid-animation or pending targeting decisions.
- Before and after each session, run its listed headless guards. Do not weaken assertions merely to pass. No rendered audits, screenshots, simulations, or edits are part of this planning turn.
- Implement in the publish source, synchronize only verified changes to the playable mirror, and commit each finished session. Stop and report if a step fails twice.

No files were changed and no tests were run for this plan.
