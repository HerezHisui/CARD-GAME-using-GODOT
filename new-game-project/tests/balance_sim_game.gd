extends "res://scripts/game_3d_manager.gd"
## Test-only instrumentation. Production decks and combat rules remain untouched.
var smooth_opening := false
var action_ramp := false
var victory_triage := false
var combat_hp_final := 20
var victory_healing := 0
var won := false
var outcome := ""
var opening_blocker := false
var early_hits := [0, 0]
var early_damage := [0, 0]
var damage_by_card := {}
var source_card := ""
var incoming_total := 0

func _wait(_seconds: float) -> void:
	await get_tree().process_frame

func _start_match() -> void:
	if smooth_opening: smooth_opening_hand()
	draw_cards(STARTING_HAND)
	opening_blocker = get_hand_cards().any(func(card): return is_opening_blocker(card.card_data))
	enemy_draw_cards(STARTING_HAND)
	enemy_draw_evolutions(1)
	coin_result = randi_range(0, 1)
	coin_pick = 0
	player_first = coin_result == coin_pick
	_begin_round()

func enemy_action_limit() -> int:
	if action_ramp: return super.enemy_action_limit()
	# Frozen pre-change rule for the control group only.
	var base_actions := 2 if encounter_kind == "battle" else 3
	var maximum := 4 if encounter_kind == "battle" else 5
	return mini(tension, clampi(base_actions + buff_value(false, "energy"), 1, maximum))

func _side_attacks(response_side: bool) -> void:
	var mine = _response_slots() if response_side else _threat_slots()
	var theirs = _threat_slots() if response_side else _response_slots()
	for i in 4:
		var attacker = _get_card_in_slot(mine[i])
		if attacker == null or not attacker.is_alive() or attacker.effective_attack() <= 0: continue
		var defender = _get_card_in_slot(theirs[i])
		resolve_attack(attacker, defender, response_side)
		if phase == Phase.GAME_OVER: return

func resolve_single_strike(attacker: Node, defender: Node, response_side: bool) -> void:
	var open_lane = defender == null or not defender.is_alive()
	source_card = str(attacker.card_data.name) if not response_side else ""
	var before = player_hp
	super.resolve_single_strike(attacker, defender, response_side)
	if not response_side and open_lane and turn <= 2 and player_hp < before:
		early_hits[turn - 1] += 1
		early_damage[turn - 1] += before - player_hp
	source_card = ""

func _damage_side(player_side: bool, amount: int, bypass_barrier: bool = false) -> void:
	var before = player_hp
	super._damage_side(player_side, amount, bypass_barrier)
	if player_side:
		var lost = before - player_hp
		incoming_total += lost
		if lost > 0:
			var key = source_card if source_card != "" else "Other (status/upkeep)"
			damage_by_card[key] = int(damage_by_card.get(key, 0)) + lost

func finish_simulation(victory: bool, reason: String) -> void:
	won = victory
	outcome = reason
	combat_hp_final = player_hp
	_set_phase(Phase.GAME_OVER)
	if victory_triage:
		run_director.battle_finished(victory)
		victory_healing = player_hp - combat_hp_final
	else:
		run_director.battle_active = false

func _check_game_over() -> bool:
	if phase == Phase.GAME_OVER: return true
	if player_hp <= 0 or enemy_hp <= 0:
		finish_simulation(player_hp > 0, "victory" if player_hp > 0 else "hero defeated")
		return true
	return false

func _begin_round() -> void:
	if deck.is_empty() and get_hand_cards().is_empty() and _response_slots().all(func(slot): return _get_card_in_slot(slot) == null):
		finish_simulation(false, "Response exhausted")
		return
	if not (enemy_deck + enemy_hand).any(func(card): return int(card.get("cost", 0)) == 0 and not card.get("utility", false)) and _threat_slots().all(func(slot): return _get_card_in_slot(slot) == null):
		finish_simulation(true, "enemy exhausted")
		return
	super._begin_round()
