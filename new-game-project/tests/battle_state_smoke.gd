extends SceneTree
const State = preload("res://scripts/battle_state.gd")
const Snapshot = preload("res://scripts/battle_snapshot.gd")

var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		print("FAIL: " + message)

func definition(id: String, side: String = "response") -> Dictionary:
	return {"id": id, "name": id, "type": side, "element": "evac", "cost": 1, "attack": 2, "health": 8}

func unit(data: Dictionary, lane: int = -1) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(data)
	if lane < 0:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	else:
		card.in_hand = false
		var slots: Array = game._response_slots() if data.type == "response" else game._threat_slots()
		card.current_slot = slots[lane]
	return card

func data_fixture() -> void:
	var state: RefCounted = State.new()
	var original: Dictionary = definition("duplicate")
	var first: String = state.add_card(original, {"statuses": {"burn": 3}})
	var second: String = state.add_card(original)
	check(first != second, "equal definitions receive distinct instance IDs")
	state.zones.response.hand.assign([first, second])
	state.lanes.response[2] = first
	state.round_number = 7
	state.rng_state = "9223372036854775806"
	original.health = 1
	check(state.cards[first].definition.health == 8, "card input is deeply copied")
	var snapshot: Dictionary = state.to_dict()
	var restored: RefCounted = State.new()
	restored.load_snapshot(snapshot)
	check(restored.to_dict() == snapshot, "plain snapshot round-trips every field")
	var json_copy: RefCounted = State.new()
	json_copy.load_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	check(json_copy.to_dict() == snapshot, "JSON round-trip preserves IDs, zones and RNG string")
	restored.cards[first].runtime.statuses.burn = 9
	restored.zones.response.hand.reverse()
	check(state.cards[first].runtime.statuses.burn == 3, "restored runtime is independent")
	check(state.zones.response.hand == [first, second], "restored zones are independent")
	snapshot.cards[first].definition.health = 2
	check(state.cards[first].definition.health == 8, "exported snapshot does not alias the state")
	var next: String = json_copy.add_card(original)
	check(next != first and next != second, "restored serial does not reuse instance IDs")
	check(State.is_plain_data(state.to_dict()), "state recursively contains only plain data")
	var node := Node.new()
	check(not State.is_plain_data({"nested": [node]}), "nested Nodes are rejected")
	node.free()
	check(not State.is_plain_data([Callable(self, "run")]), "Callables are rejected")
	check(not State.is_plain_data(Vector3.ZERO), "scene transforms are rejected")

func scene_fixture() -> void:
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.run_director.battle_active = true
	game.run_director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.turn = 7
	game.player_first = false
	game.player_hp = 13
	game.enemy_hp = 17
	game.enemy_max_hp = 25
	game.player_barrier = 2
	game.plan_hero_barrier = 1
	game.energy_cap = 6
	game.preparedness = 4
	game.tension_cap = 8
	game.tension = 5
	game.player_buffs.burn = 2
	game.enemy_run_buffs.glass = 1
	game.coin_pick = 0
	game.coin_result = 1
	game.adapted_round = 5
	game.run_director.floor_number = 2
	var duplicate: Dictionary = definition("duplicate")
	unit(duplicate)
	unit(duplicate)
	for lane in 4:
		unit(definition("response_%d" % lane), lane)
		unit(definition("disaster_%d" % lane, "disaster"), lane)
	game.deck.assign([duplicate.duplicate(true), duplicate.duplicate(true), definition("last")])
	game.deck[1].locked_until = 9
	var shared: Dictionary = definition("shared", "disaster")
	game.enemy_deck.assign([definition("equal", "disaster"), shared])
	game.enemy_hand.assign([shared])
	game.enemy_evolution_deck.append(definition("evolution", "disaster"))
	game.player_graveyard.append({"id": "fallen", "recovered": true, "graveyard_id": 3, "statuses": {"bleed": 2}})
	game.graveyard_serial = 3
	var ally: Node = game._get_card_in_slot(game._response_slots()[1])
	ally.card_data.health = 5
	ally.statuses = {"burn": 4, "strength": 2}
	ally.last_attack_turn = 6
	ally.planned_guard = 2
	ally.plan_attack_bonus = 1
	ally.plan_ignore_taunt = true
	ally.last_evaded_hit = true
	game.plans.tokens = 2
	game.plans.armed = {
		"kind": "extract", "triggered": false, "targets": [ally], "destination": game._response_slots()[3],
	}
	game.pending_utility = game.get_hand_cards()[0]
	game.pending_effect = "tutor"
	game.board_input.pick("Choose", [ally], Callable(self, "run"), Callable())
	game.final_boss = preload("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.stage = 2
	game.final_boss.last_prepared_round = 7
	game.log_event("Snapshot fixture")

func adapter_fixture() -> void:
	scene_fixture()
	var adapter: RefCounted = Snapshot.new()
	var state: RefCounted = adapter.capture(game)
	var hand: Array = state.zones.response.hand
	check(hand.size() == 2 and hand[0] != hand[1], "duplicate live cards retain separate IDs")
	check(state.lanes.response.size() == 4 and state.lanes.disaster.size() == 4, "both rows have four lanes")
	for lane in 4:
		var id: String = state.lanes.response[lane]
		check(state.cards[id].definition.id == "response_%d" % lane, "Response lane order is preserved")
		id = state.lanes.disaster[lane]
		check(state.cards[id].definition.id == "disaster_%d" % lane, "Disaster lane order is preserved")
	var draw: Array = state.zones.response.draw
	check(draw[0] != draw[1] and state.cards[draw[2]].definition.id == "last", "draw order and duplicates survive")
	check(state.cards[draw[1]].definition.locked_until == 9, "temporary seals survive capture")
	check(state.zones.disaster.hand[0] == state.zones.disaster.draw[1], "existing dictionary alias is retained by ID")
	var ally_id: String = state.lanes.response[1]
	var runtime: Dictionary = state.cards[ally_id].runtime
	check(runtime.statuses == {"burn": 4, "strength": 2}, "live statuses survive capture")
	check(runtime.last_attack_turn == 6 and runtime.max_health == 8, "attack round and max health survive")
	check(runtime.planned_guard == 2 and runtime.plan_attack_bonus == 1, "temporary Plan values survive")
	check(runtime.plan_ignore_taunt and runtime.last_evaded_hit, "temporary rule flags survive")
	check(state.sides.response.hp == 13 and state.sides.disaster.max_hp == 25, "side health is mapped")
	check(state.sides.response.resource == 4 and state.sides.disaster.resource_cap == 8, "resources are mapped")
	check(state.sides.response.buffs.burn == 2 and state.sides.disaster.run_buffs.glass == 1, "buffs are mapped")
	check(state.round_number == 7 and state.first_side == "disaster" and state.floor_number == 2, "progress is mapped")
	check(state.coin == {"pick": 0, "result": 1} and state.adapted_round == 5, "coin and adaptation survive")
	check(state.plans.armed.targets == [ally_id], "Plan targets use card IDs")
	check(state.plans.armed.destination == {"side": "response", "lane": 3}, "Plan slot uses side/lane address")
	check(state.pending_choice.source == hand[0], "pending utility references hand instance ID")
	check(state.pending_choice.targets == [draw[0], draw[2]], "tutor targets preserve order and exclude seals")
	check(state.boss.stage == 2 and state.boss.last_prepared_round == 7, "boss bookkeeping survives")
	var fallen: String = state.zones.response.graveyard[0]
	check(state.cards[fallen].definition.recovered and state.graveyard_serial == 3, "graveyard metadata survives")
	check(state.zones.disaster.graveyard.is_empty(), "no Disaster graveyard is invented")
	check(State.is_plain_data(state.to_dict()), "scene snapshot has no Nodes, Callables or transforms")
	check(adapter.capture(game).to_dict() == state.to_dict(), "unchanged capture produces stable local IDs")
	var restored: RefCounted = State.new()
	restored.load_snapshot(JSON.parse_string(JSON.stringify(state.to_dict())))
	check(restored.to_dict() == state.to_dict(), "full scene data round-trips through JSON")
	state.cards[ally_id].runtime.statuses.burn = 99
	state.sides.response.buffs.burn = 99
	state.cards[draw[0]].definition.health = 1
	check(game._get_card_in_slot(game._response_slots()[1]).statuses.burn == 4, "snapshot does not mutate live status")
	check(game.player_buffs.burn == 2 and game.deck[0].health == 8, "snapshot does not mutate live buffs or pile")
	check(game.get_hand_cards().size() == 2 and game.pending_utility != null, "capture does not resolve live choices")

func run() -> void:
	data_fixture()
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	adapter_fixture()
	game.clear_battle()
	await process_frame
	print("%s: battle_state_smoke.gd" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
