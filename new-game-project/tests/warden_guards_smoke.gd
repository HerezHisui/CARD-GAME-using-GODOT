extends SceneTree
## Night Watch and Hall Monitor strike the Response tile across from them. Elements follow the final chart.
var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func card(data: Dictionary, slot: Node3D) -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup(data)
	result.in_hand = false
	result.current_slot = slot
	result.global_position = slot.global_position + Vector3(0, 0.02, 0)
	result._set_overlay(false)
	return result

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	paused = false
	game.clear_battle()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.turn = 1
	game.enemy_max_hp = 34
	game.enemy_hp = 34
	game.player_hp = 20
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	var boss: Node = game.final_boss
	var watch = game._get_card_in_slot(game._threat_slots()[1])
	var monitor = game._get_card_in_slot(game._threat_slots()[2])
	check(watch.card_data.name == "Night Watch" and watch.card_data.element == "earthquake", "Night Watch is Earthquake")
	check(monitor.card_data.name == "Hall Monitor" and monitor.card_data.element == "typhoon", "Hall Monitor is Typhoon")
	var friendly := {"name": "Response", "type": "response", "element": "brace", "cost": 1, "attack": 1, "health": 10}
	var across_watch = card(friendly, game._response_slots()[1])
	var across_monitor = card(friendly, game._response_slots()[2])
	var elsewhere = card(friendly, game._response_slots()[0])
	game._damage_side(false, 1)
	check(across_watch.card_data.health == 9, "damaging the Janitor hurts the tile across from Night Watch")
	check(across_monitor.card_data.health == 10 and elsewhere.card_data.health == 10, "other tiles are untouched")
	var played := {"name": "Played", "type": "response", "element": "brace", "cost": 0, "attack": 1, "health": 3}
	var first = card(played, game._response_slots()[3])
	game.on_card_played(first)
	check(across_monitor.card_data.health == 10, "first Response card does not trigger Hall Monitor")
	var second = card(played, game._response_slots()[3])
	game.on_card_played(second)
	check(across_monitor.card_data.health == 9, "second Response card hurts the tile across from Hall Monitor")
	watch.take_damage(99)
	across_watch.card_data.health = 9
	game._damage_side(false, 1)
	check(across_watch.card_data.health == 9, "a dead Night Watch no longer strikes")
	print("%s: warden_guards %d failures" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
