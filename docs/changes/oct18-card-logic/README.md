# October 18 card logic implementation

Implemented from `prompt_card_main.md` in `github-publish/new-game-project`, with the changed project files synchronized to the playable mirror.

Items 1-3 and the item 4 picker were present in local commits before this run. They were validated and completed without duplicating their implementation. The original uncommitted picker heading change and its eight-line regression block remain uncommitted in the source repository.

## Changes and per-item patches

Patch files are exact commit diffs for review, not independent branch snapshots. Later items can depend on earlier items. Shared follow-ups are linked where relevant; do not apply a shared patch twice.

### 1. Card placement hitboxes

Use the visible slot footprint under the cursor instead of the dragged card center.

Files: `new-game-project/scripts/card_3d.gd`, `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/tests/card_logic_smoke.gd`, `new-game-project/tests/ui_interaction_smoke.gd`.

Choice: Keep drops restricted to the existing friendly lane boundaries.

Commit summary: `Fix card placement to use the visible lane under the cursor` (`4a48662`).

Diffs: 01.patch (see Git history).

### 2. Draw from the deck menu

Choose the normal draw in the deck picker for exactly 1 energy; playing a Response card pays its listed cost.

Files: `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/tests/card_logic_smoke.gd`.

Choice: Opening or cancelling the picker is free; sealed cards remain unavailable.

Commit summary: `Choose the normal draw from the deck for one energy` (`374cb2a`).

Diffs: 02.patch (see Git history), 02-tests.patch (see Git history), 02-interaction-tests.patch (see Git history).

### 3. Contingency stat timing

Refresh Plan attack labels synchronously when bonuses are applied or removed; hovering never mutates combat stats.

Files: `new-game-project/scripts/card_3d.gd`, `new-game-project/scripts/contingency_rules.gd`, `new-game-project/tests/card_logic_smoke.gd`.

Choice: Armed Plans still activate during combat, preserving their existing timing.

Commit summary: `Refresh Plan attack displays at the point of mutation` (`57f0311`).

Diffs: 03.patch (see Git history).

### 4. Overhead hold-to-inspect

Pick deployed cards by their projected face so holding works during combat in overhead view.

Files: `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/tests/card_logic_smoke.gd`.

Choice: Keep the existing 0.28-second hold and movement cancellation; settle the camera before synthetic test clicks.

Commit summary: `WIP: add screen-space picking for overhead board inspection` (`285bc4b`).

Diffs: 04.patch (see Git history), 04-test.patch (see Git history).

### 5. Starter deck balance

Keep twelve cards: eleven cost 1, and one 2-cost Evacuation Route with relocation and healing.

Files: `new-game-project/data/starter_deck.json`, `new-game-project/tests/blood_pact_inspection_debug_smoke.gd`.

Choice: Use 92%/8% as the nearest ratio with the existing twelve-card size; reduce cheap printed stats.

Commit summary: `Build a twelve-card starter with eleven one-cost cards` (`d6a8376`).

Diffs: 05.patch (see Git history), 05-followup.patch (see Git history).

### 6. Effect text and legal targets

Reject friendly attacks and share modifier/effect descriptions, including the actual upgraded utility amounts.

Files: `new-game-project/scripts/battle_rules.gd`, `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/scripts/run_director.gd`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: Identical effects share text; numeric upgrades and explicit draw counts change the numbers shown.

Commit summary: `Keep modifier descriptions consistent and reject friendly attacks` (`9d2a97c`).

Diffs: 06.patch (see Git history), 06-followup.patch (see Git history).

### 7. Future-only HP-reducing Adaptations

Exempt deployed units from all unit effects of an HP-reducing Adaptation while allowing future deployments to receive it.

Files: `new-game-project/scripts/battle_engine.gd`, `new-game-project/scripts/battle_rules.gd`, `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: Held cards receive the Adaptation; exemptions stack per pick and persist through Continue.

Commit summary: `Apply HP-reducing adaptations only to future deployments` (`19a9810`).

Diffs: 07.patch (see Git history), 07-11-tests.patch (see Git history), 13-followup.patch (see Git history).

### 8. Double attacks

Resolve both strikes, retain a surviving redirected blocker, and hit opposing health when the first strike clears the lane.

Files: `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: Evaluate double-strike eligibility once; stop if the attacker dies or the battle ends.

Commit summary: `Keep double strikes on live targets and carry lethal follow-ups through` (`28ee92f`).

Diffs: 08.patch (see Git history).

### 9. Status damage synergy

Give Containment Lance +2 attack against 3 combined Burn/Poison/Bleed stacks; Last Responder gets +2 against 2 Bleed; Hazmat Team costs 2.

Files: `new-game-project/data/response_expansion.json`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: Reuse the existing condition rules; positive statuses do not contribute and open lanes receive no target-status bonus.

Commit summary: `Give weaker Response cards affordable status-combo roles` (`67f80ff`).

Diffs: 09.patch (see Git history).

### 10. Themed Elite decks

Build Elite base and evolution reserves from the encounter specialty, retaining its enablers and shared-type adjacency bonuses.

Files: `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: Repeat themed cards to preserve 21 base cards and 14 evolutions including the guardian; the reserve-count follow-up is in item 14.

Commit summary: `Build elite reserves around one shared Disaster type` (`07f39af`).

Diffs: 10.patch (see Git history), 14.patch (see Git history).

### 11. Upgrade tier pacing

Give basic units stats first and introduce drawing, Burn, Poison, or Armor at the second upgrade.

Files: `new-game-project/scripts/run_director.gd`, `new-game-project/tests/balance_rules_smoke.gd`, `new-game-project/tests/variety_smoke.gd`.

Choice: Existing abilities may improve at the first tier; do not add another copy of that improvement at the second tier.

Commit summary: `Defer new upgrade mechanics until the second tier` (`946123c`).

Diffs: 11.patch (see Git history), 07-11-tests.patch (see Git history).

### 12. Armored and Piercing

Armored blocks the Piercing hero hit but takes full Piercing unit damage; Barrier and Plan protection still apply.

Files: `new-game-project/scripts/battle_engine.gd`, `new-game-project/scripts/battle_rules.gd`, `new-game-project/scripts/card_3d.gd`, `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/scripts/run_director.gd`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: An Armored blocker protects the hero for that strike even if killed; preserve modifier arrays and normalize legacy joined strings.

Commit summary: `Let Armored stop Piercing hero hits while taking full unit damage` (`33e720d`).

Diffs: 12.patch (see Git history), 12-followup.patch (see Git history).

### 13. Statless utilities

Remove utility ATK/HP data and face/inspection badges, keeping spells castable, inspectable, and compatible with old saves.

Files: `new-game-project/data/disaster_expansion.json`, `new-game-project/data/response_expansion.json`, `new-game-project/scripts/battle_engine.gd`, `new-game-project/scripts/battle_rules.gd`, `new-game-project/scripts/card_3d.gd`, `new-game-project/scripts/final_boss.gd`, `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/scripts/run_director.gd`, `new-game-project/scripts/run_save.gd`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: Only cards explicitly marked utility are statless; support units retain stats. Internal utility maximum HP is zero.

Commit summary: `Remove unit stats from utilities and normalize old saves` (`3d7a18f`).

Diffs: 13.patch (see Git history), 13-followup.patch (see Git history).

### 14. Weak cheap Disasters

Reduce default 1-Tension units and 1-sacrifice evolutions to at most 2 printed attack including starting Strength and 2 HP; skip their flat encounter stat scaling.

Files: `new-game-project/data/disaster_deck.json`, `new-game-project/data/disaster_expansion.json`, `new-game-project/scripts/card_3d.gd`, `new-game-project/scripts/game_3d_manager.gd`, `new-game-project/scripts/run_director.gd`, `new-game-project/tests/balance_rules_smoke.gd`.

Choice: Venom Surge requires 3 Poison for +2 attack. Scripted boss-pattern hazards have no summon cost and display a BOSS badge.

Commit summary: `Keep cheap Disaster units weak across all encounter tiers` (`464a5ac`).

Diffs: 14.patch (see Git history).

## Validation

All 22 source headless suites below finished with exit code 0 and no script errors or failed assertions in their final logs. The new card-logic and balance suites also passed in the playable mirror. `git diff --check` passed for source and mirror.

Godot: `C:\Users\0stef\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.

Command pattern: `Godot_v4.7.2-stable_win64_console.exe --headless --path <project> --script res://tests/<name>_smoke.gd`.

| Suite | Result |
| --- | --- |
| battle_behavior (see Git history) | Passed |
| battle_engine (see Git history) | Passed |
| battle_state (see Git history) | Passed |
| camera_controls (see Git history) | Passed |
| classroom_integration (see Git history) | Passed |
| expansion (see Git history) | Passed |
| explorer_mode (see Git history) | Passed |
| final_boss (see Git history) | Passed |
| improvements (see Git history) | Passed |
| mechanics (see Git history) | Passed |
| notes4 (see Git history) | Passed |
| coin_rewards (see Git history) | Passed |
| graveyard_save_compatibility (see Git history) | Passed |
| blood_pact_inspection_debug (see Git history) | Passed |
| balance_rules (see Git history) | Passed |
| card_logic (see Git history) | Passed |
| hud_navigation (see Git history) | Passed |
| plans_notes (see Git history) | Passed |
| run (see Git history) | Passed |
| ui_interaction (see Git history) | Passed |
| variety (see Git history) | Passed |
| visual_quality (see Git history) | Passed |

`battle_engine_smoke` includes 63,729 parity comparisons. The new balance suite covers card data, friendly attack rejection, adaptation stacking and actual checkpoint/resume, double attacks, status thresholds, all four Elite themes, upgrade pacing, Piercing/Armor/Barrier interactions, statless utilities, and cheap Disaster scaling across floors and encounter kinds.

Initial failures were resolved: the overhead fixture raced a camera tween; older draw fixtures omitted the new deck confirmation; old starter/adaptation/upgrade assertions expected superseded rules; reward assertions counted decorative textures; the heading assertion ignored uppercase rendering. Early test runs also exposed GDScript type/reserved-word issues, corrected before the passing runs.

No rendered audits or manual playthrough were run, per AGENTS.md. Headless checks validate rules and UI state, not final visual appearance or full-run difficulty.

## Mirror and working tree

[mirror-parity.json](mirror-parity.json) records byte-for-byte verification for the 32 synchronized project files. Three existing source dependencies absent from the mirror (`battle_query_adapter.gd`, `battle_snapshot.gd`, `battle_state.gd`) were restored. The mirror was clean before synchronization. Its unrelated existing `ui_theme.gd` difference was preserved.

Mirror checks: card logic (see Git history), balance (see Git history). Mirror changes remain available in its working tree. Local source implementation commits were created; nothing was pushed.

Validation follow-ups: UI assertion scope (see Git history). Source user edits were preserved separately from the implementation commits.
