extends SceneTree
## Run against the original methods before changing wrappers, then rerun after extraction.
const BattleEngine = preload("res://scripts/battle_engine.gd")
const Adapter = preload("res://scripts/battle_query_adapter.gd")
# Captured from original manager/card implementations before switching the wrappers.
const ORIGINAL_RESULTS_SHA256 := "3a78c90cf0a51ce89f03edab9b9658252b3117a5ac646670eaa0b72692fa3d7e"
var failures := 0
var comparisons := 0
var game: Node
var parity_hash := HashingContext.new()

func _initialize() -> void:
	parity_hash.start(HashingContext.HASH_SHA256)
	call_deferred("run")

func same(actual: Variant, expected: Variant, label: String) -> void:
	comparisons += 1
	parity_hash.update(var_to_bytes(expected))
	if actual != expected:
		failures += 1
		print("FAIL: " + label + " expected " + str(expected) + " got " + str(actual))

func unit(side: String, lane: int) -> Node:
	var result: Node = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup({"name": "Query fixture", "type": side, "cost": 1, "attack": 3, "health": 8,
		"element": "evac" if side == "response" else "earthquake"})
	result.current_slot = (game._response_slots() if side == "response" else game._threat_slots())[lane]
	result.in_hand = false
	return result

func compare_card(card: Node, target: Node) -> void:
	var context := Adapter.context(game)
	var data := Adapter.card(game, card)
	var defender := Adapter.card(game, target)
	var before: Array = [context.duplicate(true), data.duplicate(true), defender.duplicate(true)]
	for modifier in ["armored", "fragile", "SLUGGISH", "piercing", "rampaging", "unknown"]:
		same(BattleEngine.has_modifier(context, data, modifier), card.has_modifier(modifier), "modifier")
		same(BattleEngine.definition_has_modifier(data.card_data, modifier),
			game.definition_has_modifier(card.card_data, modifier), "definition modifier")
	same(BattleEngine.synergy_bonus(context, data), game._synergy_bonus(card), "synergy")
	same(BattleEngine.attack_bonus(context, data), game.attack_bonus(card), "attack bonus")
	same(BattleEngine.effective_attack(context, data), card.effective_attack(), "effective attack")
	for amount in [-1, 0, 1, 3, 8]:
		same(BattleEngine.adjusted_damage(context, data, amount), card.adjusted_damage(amount), "adjusted damage")
	for round_number in [1, 2, 3, 4, 6]:
		same(BattleEngine.can_attack(context, data, round_number), card.can_attack(round_number), "attack timing")
	for status in ["any", "burn", "poison", "bleed", "strength", "unknown"]:
		same(BattleEngine.status_stacks(data.statuses, status), game.status_stacks(card, status), "statuses")
		same(BattleEngine.status_stacks(null, status), game.status_stacks(null, status), "null statuses")
	for condition in [{}, {"status": "any"}, {"subject": "self", "status": "strength", "threshold": 2}]:
		same(BattleEngine.condition_met(condition, data.statuses, defender.statuses),
			game.condition_met(condition, card, target), "condition")
		same(BattleEngine.condition_met(condition, data.statuses, null),
			game.condition_met(condition, card, null), "null condition")
	for opponent in [target, null]:
		var other: Variant = null if opponent == null else defender
		same(BattleEngine.conditional_attack_bonus(data, other), game.conditional_attack_bonus(card, opponent), "bonus")
		same(BattleEngine.attack_strikes(data, other), game.attack_strikes(card, opponent), "strikes")
	same(BattleEngine.calc_damage(context, data, defender), game._calc_damage(card, target), "damage")
	same([context, data, defender], before, "queries leave all inputs unchanged")

func run() -> void:
	# This first assertion runs without any scene: the engine accepts only plain data.
	var plain := {"response": {"buffs": {}, "run_buffs": {}},
		"disaster": {"buffs": {}, "run_buffs": {}}, "player_first": true}
	same(BattleEngine.resource_growth(plain, true), 1, "scene-free resource query")
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.clear_battle()
	var response := unit("response", 0)
	var neighbor := unit("response", 1)
	var disaster := unit("disaster", 0)
	var elements := ["evac", "douse", "clearance", "brace", "flood", "earthquake", "typhoon", "fire", ""]
	for mode in range(8):
		game.player_buffs = {"overclock": mode % 3, "isolation": 1, "strength": mode - 2,
			"energy": mode % 2, "damage_taken": mode % 3, "synergy": 1, "piercing": 1, "sluggish": 1}
		game.enemy_buffs = {"strength": 2, "isolation": 1, "damage_taken": 1}
		game.player_run_buffs = {"overclock": 1, "strength": 1}
		game.enemy_run_buffs = {"energy": 2, "synergy": 1}
		game.player_first = mode % 2 == 0
		response.current_slot = null if mode == 1 else game._response_slots()[mode % 4]
		response.preview_only = mode >= 6
		response.card_data.attack = mode - 2
		response.card_data.health = 0 if mode == 4 else 8
		response.card_data.armor_value = 3
		response.card_data.modifier = "armored"
		response.card_data.modifiers = ["fragile"]
		response.modifiers.assign(["armored", "fragile", "rampaging", "sluggish"] if mode % 2 == 0 else [])
		response.last_attack_turn = -1 if mode == 0 else 2
		response.plan_attack_bonus = mode % 3
		response.statuses = {"strength": 2, "burn": mode, "poison": 1, "bleed": 1, "barrier": 3}
		disaster.statuses = {"burn": mode, "poison": 1, "strength": 10}
		response.card_data.condition = {"subject": "self" if mode % 2 else "target",
			"status": "any", "threshold": 3, "bonus": 2, "strikes": 3}
		response.card_data.status_bonus = 2
		if mode == 7:
			response.card_data.preview_attack = -2
		neighbor.card_data.health = 0 if mode == 3 else 8
		for side in [true, false]:
			var context := Adapter.context(game)
			same(BattleEngine.overclock_stacks(context, side), game.overclock_stacks(side), "overclock")
			same(BattleEngine.resource_growth(context, side), game.resource_growth(side), "growth")
			for amount in [0, 1, 3, 4]:
				same(BattleEngine.incoming_damage(context, side, amount), game.incoming_damage(side, amount), "incoming")
			for id in ["strength", "isolation", "energy", "overclock", "unknown"]:
				same(BattleEngine.buff_value(context, side, id), game.buff_value(side, id), "buff value")
		for locked in [0, game.turn, game.turn + 1]:
			same(BattleEngine.is_sealed({"locked_until": locked}, game.turn),
				game.is_sealed({"locked_until": locked}), "seal boundary")
		for attack_element in elements:
			response.card_data.element = attack_element
			neighbor.card_data.element = "brace" if mode == 2 else attack_element
			for defend_element in elements:
				disaster.card_data.element = defend_element
				compare_card(response, disaster)
				compare_card(disaster, response)
		var context := Adapter.context(game)
		for definition in [{}, {"type": "response"}, {"type": "disaster"}]:
			same(BattleEngine.buffs_for(context, definition), game.buffs_for(definition), "buff totals")
	var checksum := parity_hash.finish().hex_encode()
	if checksum != ORIGINAL_RESULTS_SHA256:
		failures += 1
		print("FAIL: original results checksum changed: " + checksum)
	game.queue_free()
	await process_frame
	print(("PASS: " if failures == 0 else "FAIL: ") + "battle_engine_smoke (%d comparisons)" % comparisons)
	quit(0 if failures == 0 else 1)
