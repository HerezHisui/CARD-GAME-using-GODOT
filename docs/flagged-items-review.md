# Flagged items review, 18 October 2026

## 1. Player-only adaptations

Files touched:
- `new-game-project/scripts/run_director.gd`
- `new-game-project/scripts/game_3d_manager.gd`
- `new-game-project/tests/expansion_smoke.gd`
- `new-game-project/tests/improvements_smoke.gd`
- `new-game-project/RUN_GUIDE.md`
- `docs/singleplayer.md`

The round selection screen used to choose an adaptation for the Janitor before
the player chose. The floor reward also picked and applied a separate permanent
adaptation for the Janitor. Both automatic grants are removed. Player choices,
offer restoration, stacking, and battle expiration keep their existing behavior.
The unused enemy adaptation scoring function is removed, and the descriptions
now match the player-only selection behavior.

Distinction: an automatic grant from `Rules.BUFFS` or `Rules.RUN_BUFFS` is a normal
pool adaptation; an effect that explicitly targets both sides would be a dual
effect. No current catalog entry explicitly grants a buff to the other side.

`add_global_buff`, `BattleRules.BONUSES`, and the combat effect code are unchanged.
Existing tradeoffs, such as Overclock's increased incoming damage, still apply.
Enemy buffs already stored in a save are retained: the save does not record
whether they came from automatic selection or an explicit effect.

Commit-message-style summary: `Keep battle and floor adaptations player-only`

The implementation diff appears below.

## 2. Post-battle healing investigation

Files inspected: `new-game-project/scripts/run_director.gd`,
`new-game-project/scripts/game_3d_manager.gd`, `new-game-project/tests/run_smoke.gd`,
and `new-game-project/RUN_GUIDE.md`. No healing code was changed.

The healing is in `RunDirector.battle_finished`, rather than the combat manager.
After a win, normal battles receive up to 3 HP through `healing_gain(3)`, capped
at maximum HP. Elite and boss victories receive no triage. The result banner
explicitly reports this recovery. The `battle_active` guard prevents a repeated
result callback from granting it twice.

This is an intentional balance mechanic in the current implementation:
`RUN_GUIDE.md` documents normal-victory triage, and `run_smoke.gd` checks its cap
on every floor, duplicate callbacks, elite/boss exclusion, and save continuation.
It is separate from the Infirmary rest, shop first aid, event healing, and
Infirmary Network's per-round regeneration.

There is also a separate capped 5 HP recovery in `next_floor`, after selecting
the permanent reward. This can explain healing after a floor boss even though
the boss itself grants no triage.

Decision: retain both healing paths. The supplied document permits removal only
when the trigger is clearly unintended; the current code and tests do not support
that conclusion. Removing either path requires a separate design decision.

Diff: none for healing.

Commit-message-style summary: `Document victory triage and floor recovery`

## Validation

Before editing, these headless suites passed in the source project:
`expansion_smoke.gd`, `improvements_smoke.gd`, `notes4_smoke.gd`, and `run_smoke.gd`.

After editing, those four suites and `oct18_balance_smoke.gd` passed in the source
and playable mirror using Godot 4.7.2. The adaptation tests now check player-only
round and floor grants and unchanged offers after opening the deck. The balance
suite checks adaptation tradeoffs, including deployed-unit exemptions.

An initial new assertion assumed the selected buff had no previous stacks.
The test fixture already applies buffs, so the assertion was corrected to check
that selection adds exactly one stack. The corrected suite passed.

Only the changed runtime files and tests were copied to the playable mirror after
matching them against the source baseline. Its guide had existing differences,
so only the two relevant adaptation paragraphs were edited there.
Unrelated uncommitted mirror changes were preserved.

`git diff --check` passed. No rendered or screenshot audit was run, following
the repository's headless-only validation instruction.

## Implementation diff


```diff
diff --git a/docs/singleplayer.md b/docs/singleplayer.md
index f894ae9..9b71dbd 100644
--- a/docs/singleplayer.md
+++ b/docs/singleplayer.md
@@ -196 +196 @@ Rally and Cleanse target allies by clicking them on the board. Emergency Exit us
-At the start of rounds 5, 10, 15, ... of each encounter, both sides receive a battle-only adaptation. You choose one of three randomly offered buffs; the Janitor chooses one of the same three, shown on screen. The battle pauses until you choose. Deck viewing preserves the exact offers. Adaptations expire when the encounter ends.
+At the start of rounds 5, 10, 15, ... of each encounter, choose one of three randomly offered battle-only adaptations for your side. The Janitor does not receive an automatic adaptation from this pool. The battle pauses until you choose. Deck viewing preserves the exact offers. Adaptations expire when the encounter ends.
@@ -200 +200 @@ There are fifteen battle adaptations. Strong options have explicit tradeoffs: Gl
-After the first two floor bosses, choose one of three permanent run rewards from an eight-option pool. The Janitor also chooses a permanent reward. These stack across later battles and floors; a new run clears them. Examples include Signal Beacon (extra draws), School Bulwark (health for reduced attack), Buddy System (adjacency bonuses with an isolation penalty), Field School (resources and draws for less health), Hazard Manual (stronger statuses for reduced resources), and Infirmary Network (hero healing for reduced unit attack).
+After the first two floor bosses, choose one of three permanent run rewards from an eight-option pool. The Janitor does not receive an automatic reward from this pool. These stack across later battles and floors; a new run clears them. Examples include Signal Beacon (extra draws), School Bulwark (health for reduced attack), Buddy System (adjacency bonuses with an isolation penalty), Field School (resources and draws for less health), Hazard Manual (stronger statuses for reduced resources), and Infirmary Network (hero healing for reduced unit attack).
diff --git a/new-game-project/RUN_GUIDE.md b/new-game-project/RUN_GUIDE.md
index 88f119d..d02a3ab 100644
--- a/new-game-project/RUN_GUIDE.md
+++ b/new-game-project/RUN_GUIDE.md
@@ -61 +61 @@ Rally and Cleanse target allies by clicking them on the board. Emergency Exit us
-At the start of rounds **5, 10, 15, ...** of each encounter, both sides receive a **battle-only adaptation**. You choose one of three randomly offered buffs; the Janitor chooses one of the same three, shown on screen. The battle pauses until you choose. Deck viewing preserves the exact offers. Adaptations expire when the encounter ends.
+At the start of rounds **5, 10, 15, ...** of each encounter, choose one of three randomly offered **battle-only adaptations** for your side. The Janitor does not receive an automatic adaptation from this pool. The battle pauses until you choose. Deck viewing preserves the exact offers. Adaptations expire when the encounter ends.
@@ -65 +65 @@ There are fifteen battle adaptations. Strong options have explicit tradeoffs: Gl
-After the **first two floor bosses**, choose one of three **permanent run rewards** from an eight-option pool. The Janitor also chooses a permanent reward. These stack across later battles and floors; a new run clears them. Examples include Signal Beacon (extra draws), School Bulwark (health for reduced attack), Buddy System (adjacency bonuses with an isolation penalty), Field School (resources and draws for less health), Hazard Manual (stronger statuses for reduced resources), and Infirmary Network (hero healing for reduced unit attack).
+After the **first two floor bosses**, choose one of three **permanent run rewards** from an eight-option pool. The Janitor does not receive an automatic reward from this pool. These stack across later battles and floors; a new run clears them. Examples include Signal Beacon (extra draws), School Bulwark (health for reduced attack), Buddy System (adjacency bonuses with an isolation penalty), Field School (resources and draws for less health), Hazard Manual (stronger statuses for reduced resources), and Infirmary Network (hero healing for reduced unit attack).
diff --git a/new-game-project/scripts/game_3d_manager.gd b/new-game-project/scripts/game_3d_manager.gd
index 6948723..9509476 100644
--- a/new-game-project/scripts/game_3d_manager.gd
+++ b/new-game-project/scripts/game_3d_manager.gd
@@ -1521,20 +1520,0 @@ func relocate_enemy_ally(source: Node) -> void:
-func choose_ai_buff(options: Array) -> Dictionary:
-	if encounter_kind == "battle": return options.pick_random()
-	var best: Dictionary = options[0]
-	var best_score := -INF
-	var deck_view: Array = enemy_deck + enemy_hand + enemy_evolution_deck
-	for slot in _threat_slots():
-		var card = _get_card_in_slot(slot)
-		if card: deck_view.append(card.card_data)
-	for option in options:
-		var bonus: Dictionary = preload("res://scripts/battle_rules.gd").totals({option.id:1}, {})
-		var score := float(bonus.get("strength", 0)) * 3 + float(bonus.get("health", 0)) * 2 + float(bonus.get("energy", 0)) * 2 + float(bonus.get("draw", 0)) * 2
-		for definition in deck_view:
-			for status in ["burn", "poison", "bleed"]:
-				if definition.get("on_hit", {}).has(status): score += float(bonus.get(status, 0)) * 1.5
-		score += float(bonus.get("piercing", 0)) * 5 + float(bonus.get("regen", 0)) - float(bonus.get("self_bleed", 0)) * 3 - float(bonus.get("sluggish", 0)) * 3 - float(bonus.get("damage_taken", 0)) * 5
-		if score > best_score:
-			best_score = score
-			best = option
-	return best
-
diff --git a/new-game-project/scripts/run_director.gd b/new-game-project/scripts/run_director.gd
index f4a6d94..00ea5c3 100644
--- a/new-game-project/scripts/run_director.gd
+++ b/new-game-project/scripts/run_director.gd
@@ -2001,4 +2001,2 @@ func show_buff_choices(restore_offers: bool = false) -> void:
-	var enemy_choice: Dictionary = game.choose_ai_buff(buff_choices)
-	if not restore_offers and not is_instance_valid(game.final_boss): game.add_global_buff(false, enemy_choice.id)
-	reset_panel("ROUND %d · BATTLE ADAPTATION" % game.turn, "These buffs expire after this battle. The Janitor adaptation is already applied: %s." % enemy_choice.name, "buff")
-	if is_instance_valid(game.final_boss): content.get_child(1).text = "Battle-only adaptations. The final boss keeps its fixed attack pattern."
+	reset_panel("ROUND %d · BATTLE ADAPTATION" % game.turn,
+		"Choose one adaptation for your side. These buffs expire after this battle.", "buff")
@@ -2024 +2022,2 @@ func show_floor_buffs(restore_offers: bool = false) -> void:
-	reset_panel("FLOOR %d CLEARED · PERMANENT REWARD" % floor_number, "Choose one buff for the entire run, then climb to the next floor. The Janitor also adapts permanently.", "floor_buff")
+	reset_panel("FLOOR %d CLEARED · PERMANENT REWARD" % floor_number,
+		"Choose one buff for your side for the entire run, then climb to the next floor.", "floor_buff")
@@ -2034 +2032,0 @@ func select_floor_buff(id: String) -> void:
-	var enemy_choice: Dictionary = game.choose_ai_buff(buff_choices)
@@ -2036 +2033,0 @@ func select_floor_buff(id: String) -> void:
-	game.add_global_buff(false, enemy_choice.id, true)
diff --git a/new-game-project/tests/expansion_smoke.gd b/new-game-project/tests/expansion_smoke.gd
index 355a0e2..6d9e57d 100644
--- a/new-game-project/tests/expansion_smoke.gd
+++ b/new-game-project/tests/expansion_smoke.gd
@@ -171 +171,2 @@ func run() -> void:
-	check(not game.enemy_buffs.is_empty(), "Disaster receives a buff too")
+	check(game.enemy_buffs.is_empty(), "offering adaptations does not buff the Janitor")
+	var offered_buffs: Array = director.buff_choices.duplicate(true)
@@ -176 +177,7 @@ func run() -> void:
-	director.select_buff(director.buff_choices[0].id)
+	check(director.buff_choices == offered_buffs and game.enemy_buffs.is_empty(),
+		"reopening adaptation choices preserves offers without buffing the Janitor")
+	var chosen_id: String = offered_buffs[0].id
+	var previous_stacks: int = game.player_buffs.get(chosen_id, 0)
+	director.select_buff(chosen_id)
+	check(game.player_buffs.get(chosen_id, 0) == previous_stacks + 1 and game.enemy_buffs.is_empty(),
+		"selected adaptation applies only to the player")
diff --git a/new-game-project/tests/improvements_smoke.gd b/new-game-project/tests/improvements_smoke.gd
index c9ed7a0..9e86d76 100644
--- a/new-game-project/tests/improvements_smoke.gd
+++ b/new-game-project/tests/improvements_smoke.gd
@@ -125 +125,2 @@ func run() -> void:
-	check(director.floor_number == 2 and not game.player_run_buffs.is_empty() and not game.enemy_run_buffs.is_empty(), "floor awards persistent buff to both sides")
+	check(director.floor_number == 2 and not game.player_run_buffs.is_empty() and game.enemy_run_buffs.is_empty(),
+		"floor awards a persistent adaptation only to the player")
```
