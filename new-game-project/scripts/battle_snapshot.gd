extends RefCounted
## Read-only scene adapter. Does not participate in play or save/load yet.
const State = preload("res://scripts/battle_state.gd")
const CARD_FIELDS := [
	"max_health", "statuses", "modifiers", "last_attack_turn", "planned_guard", "plan_attack_bonus",
	"plan_ignore_taunt", "last_evaded_hit", "base_definition", "graveyard_recorded",
]
const PLAN_FIELDS := ["tokens", "auto_save", "saved_round", "committed_round", "unlocked"]
const BOSS_FIELDS := [
	"stage", "changed_round", "pillars_spawned", "pulse_resolved", "last_resolved_round", "last_prepared_round",
]

var _references: Array = []
var _ids: Array[String] = []

func capture(game: Node) -> RefCounted:
	_references.clear()
	_ids.clear()
	var state: RefCounted = State.new()
	_capture_sides(state, game)
	_capture_zones(state, game)
	_capture_progress(state, game)
	_capture_plans(state, game)
	_capture_choice(state, game)
	if is_instance_valid(game.final_boss):
		state.boss = _fields(game.final_boss, BOSS_FIELDS)
	_references.clear()
	_ids.clear()
	return state

func _fields(node: Node, names: Array) -> Dictionary:
	var values: Dictionary = {}
	for field in names:
		var value: Variant = node.get(field)
		values[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	return values

func _capture_sides(state: RefCounted, game: Node) -> void:
	state.sides = {
		"response": {
			"hp": game.player_hp, "max_hp": game.hero_max_hp(), "barrier": game.player_barrier,
			"plan_barrier": game.plan_hero_barrier, "resource": game.preparedness, "resource_cap": game.energy_cap,
			"buffs": game.player_buffs.duplicate(true), "run_buffs": game.player_run_buffs.duplicate(true),
		},
		"disaster": {
			"hp": game.enemy_hp, "max_hp": game.enemy_max_hp, "barrier": 0, "plan_barrier": 0,
			"resource": game.tension, "resource_cap": game.tension_cap,
			"buffs": game.enemy_buffs.duplicate(true), "run_buffs": game.enemy_run_buffs.duplicate(true),
		},
	}

func _reference_id(state: RefCounted, reference: Variant) -> String:
	for i in _references.size():
		if is_same(_references[i], reference):
			return _ids[i]
	var id: String
	if reference is Node:
		id = state.add_card(reference.card_data, _fields(reference, CARD_FIELDS))
	else:
		id = state.add_card(reference)
	_references.append(reference)
	_ids.append(id)
	return id

func _pile(state: RefCounted, definitions: Array) -> Array:
	var ids: Array = []
	for definition in definitions:
		ids.append(_reference_id(state, definition))
	return ids

func _capture_zones(state: RefCounted, game: Node) -> void:
	for card in game.get_hand_cards():
		state.zones.response.hand.append(_reference_id(state, card))
	for side in ["response", "disaster"]:
		var slots: Array = game._response_slots() if side == "response" else game._threat_slots()
		for lane in slots.size():
			var card: Node = game._get_card_in_slot(slots[lane])
			if card != null:
				state.lanes[side][lane] = _reference_id(state, card)
	state.zones.response.draw = _pile(state, game.deck)
	state.zones.response.graveyard = _pile(state, game.player_graveyard)
	state.zones.disaster.hand = _pile(state, game.enemy_hand)
	state.zones.disaster.draw = _pile(state, game.enemy_deck)
	state.zones.disaster.evolution = _pile(state, game.enemy_evolution_deck)

func _capture_progress(state: RefCounted, game: Node) -> void:
	state.round_number = game.turn
	state.phase = int(game.phase)
	state.first_side = "response" if game.player_first else "disaster"
	state.encounter_kind = game.encounter_kind
	state.floor_number = game.run_director.floor_number
	state.adapted_round = game.adapted_round
	state.coin = {"result": game.coin_result, "pick": game.coin_pick}
	state.graveyard_serial = game.graveyard_serial
	state.battle_log = game.battle_log.duplicate()
	state.run_rng_state = str(game.run_director.rng.state)
	# Enemy actions and global RNG state are not exposed by the current scene manager.
	# Leave their data slots unknown rather than changing live rule ownership.

func _slot_address(game: Node, slot: Variant) -> Dictionary:
	if slot == null:
		return {}
	for side in ["response", "disaster"]:
		var slots: Array = game._response_slots() if side == "response" else game._threat_slots()
		var lane := slots.find(slot)
		if lane >= 0:
			return {"side": side, "lane": lane}
	return {}

func _capture_plans(state: RefCounted, game: Node) -> void:
	state.plans = _fields(game.plans, PLAN_FIELDS)
	state.plans.armed = {}
	var armed: Dictionary = game.plans.armed
	if armed.is_empty():
		return
	var targets: Array = []
	for card in armed.targets:
		targets.append(_reference_id(state, card))
	state.plans.armed = {
		"kind": armed.kind, "triggered": armed.triggered, "targets": targets,
		"destination": _slot_address(game, armed.destination),
	}

func _capture_choice(state: RefCounted, game: Node) -> void:
	var action: Dictionary = game.board_input.action
	if action.is_empty() and not is_instance_valid(game.pending_utility):
		return
	state.pending_choice = {
		"kind": action.get("kind", "utility"), "effect": game.pending_effect,
		"source": "", "moving_ally": "", "targets": [],
	}
	var source: Variant = game.pending_utility
	if not is_instance_valid(source):
		source = action.get("source", action.get("card", game.moving_source))
	if is_instance_valid(source):
		state.pending_choice.source = _reference_id(state, source)
	if is_instance_valid(game.moving_ally):
		state.pending_choice.moving_ally = _reference_id(state, game.moving_ally)
	for target in action.get("cards", []):
		state.pending_choice.targets.append(_reference_id(state, target))
	if game.pending_effect != "":
		state.pending_choice.targets = _utility_targets(state, game)

func _utility_targets(state: RefCounted, game: Node) -> Array:
	var choices: Array = []
	match game.pending_effect:
		"tutor": choices = game.deck.filter(func(card): return not game.is_sealed(card))
		"recover": choices = game.recoverable_units()
		"seal": choices = game.enemy_hand.filter(func(card): return not game.is_sealed(card))
		"tax": choices = game.enemy_hand
		"rally", "cleanse": choices = game.board_input.action.get("cards", [])
	return _pile(state, choices)
