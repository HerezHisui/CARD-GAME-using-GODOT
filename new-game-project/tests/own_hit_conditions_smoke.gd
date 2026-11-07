extends SceneTree
## Heat Seeker, Last Responder and Containment Lance inflict a small status on hit, so their own
## condition is active for the next attack (after the round-end decay).
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
	result.setup(data.duplicate(true))
	result.in_hand = false
	result.current_slot = slot
	result.global_position = slot.global_position + Vector3(0, 0.02, 0)
	result._set_overlay(false)
	return result

func hit_then_decay(id: String) -> void:
	var attacker = card(director.catalog_card(id), game._response_slots()[0])
	# Flood is neutral against every Response element used here, so only the status is tested.
	var target = card({"name": "Wall", "type": "disaster", "element": "flood", "cost": 0, "attack": 1,
		"health": 40}, game._threat_slots()[0])
	check(game.conditional_attack_bonus(attacker, target) == 0, id + ": condition is off before the first hit")
	game.resolve_single_strike(attacker, target, true)
	target.status_upkeep()
	check(game.conditional_attack_bonus(attacker, target) > 0, id + ": condition is on after one hit and a round")
	attacker.queue_free()
	target.queue_free()

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
	for id in ["heat_seeker", "last_responder", "containment_lance"]:
		hit_then_decay(id)
	print("%s: own_hit_conditions %d failures" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
