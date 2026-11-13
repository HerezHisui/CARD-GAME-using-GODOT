# Covers: Disaster AI scoring moved to disaster_ai.gd gives the same scores, picks and plans as before the move.
extends SceneTree

# Captured on the original game_3d_manager code, before the move (perf-clean M3).
const ORIGINAL_SHA256 := "85dad588199e1f7ddef2e8595384f615e5df54b18e7d068b6b9f8c624623f9bc"

var game: Node
var director: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func make_card(data: Dictionary, slot: Node3D) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(data)
	card.current_slot = slot
	card.in_hand = false
	return card

func fixture(kind: String) -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.player_buffs.clear()
	game.enemy_buffs.clear()
	game.player_hp = 20
	game.enemy_hp = 20
	game.turn = 2
	game.player_first = false
	game.encounter_kind = kind
	director.battle_active = true
	director.modal.hide()
	director.screen = ""
	game._set_phase(game.Phase.PLAYER_PLAY)

## Slot index, so the record holds numbers and not node paths.
func lane(slot: Variant) -> int:
	return game._threat_slots().find(slot)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.new_run()
	var disasters: Array[Dictionary] = []
	game.load_deck_from_json("res://data/disaster_deck.json", disasters)
	game.load_deck_from_json("res://data/disaster_expansion.json", disasters)
	check(disasters.size() > 10, "disaster cards load")
	var results: Array = []
	for kind: String in ["battle", "elite", "boss"]:
		fixture(kind)
		make_card({"name":"Evac", "type":"response", "element":"evac", "cost":1, "attack":2, "health":5},
			game._response_slots()[0])
		make_card({"name":"Douse", "type":"response", "element":"douse", "cost":2, "attack":4, "health":3},
			game._response_slots()[2])
		var ally = make_card({"name":"Flood", "type":"disaster", "element":"flood", "cost":0, "attack":2, "health":4},
			game._threat_slots()[1])
		var weak = make_card({"name":"Weak", "type":"disaster", "element":"fire", "cost":0, "attack":1, "health":1},
			game._threat_slots()[3])
		# Every disaster card in every lane.
		var scores: Array = []
		for definition: Dictionary in disasters:
			for slot: Node3D in game._threat_slots(): scores.append(snappedf(game.score_threat(definition, slot), 0.001))
		results.append([kind, scores])
		# Seeded picks: the regular encounter uses random choices on purpose.
		seed(1234)
		var empty: Array = [game._threat_slots()[0], game._threat_slots()[2]]
		var picks: Array = []
		for definition: Dictionary in disasters.slice(0, 12):
			picks.append(lane(game._pick_smart_threat_slot(empty, definition)))
		results.append(picks)
		seed(99)
		results.append(game.choose_base_threat(disasters.slice(0, 8), empty).get("id", ""))
		# Board value of the live board and of a changed layout.
		var live: Dictionary = {}
		for card: Node in [ally, weak]: live[card.current_slot] = game.live_ai_definition(card)
		results.append(snappedf(game.board_score(live), 0.001))
		var changed: Dictionary = live.duplicate(true)
		changed[game._threat_slots()[0]] = disasters[5]
		results.append(snappedf(game.board_score(changed), 0.001))
		# Evolution plans over the evolution cards.
		var evolutions: Array = disasters.filter(func(card): return int(card.get("cost", 0)) >= 1)
		var plan: Dictionary = game.best_evolution_plan([ally, weak], evolutions)
		results.append([plan.get("card", {}).get("id", ""), lane(plan.get("slot")), snappedf(plan.get("gain", 0.0), 0.001),
			plan.get("sacrifices", []).map(func(card): return lane(card.current_slot))])
	var digest := JSON.stringify(results, "", true).sha256_text()
	print("disaster_ai_smoke digest " + digest)
	check(digest == ORIGINAL_SHA256, "results match the code before the move")
	print("disaster_ai_smoke: %d checks, %d failures" % [checks, failures])
	game.clear_battle()
	if failures > 0:
		quit(1)
		return
	print("PASS: Disaster AI scoring matches the original manager code")
	quit(0)
