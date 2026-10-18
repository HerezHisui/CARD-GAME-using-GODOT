extends SceneTree

var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	director.modal.hide()
	director.screen = ""
	director.battle_active = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 40
	game.player_first = true
	game.preparedness = 5
	game.energy_cap = 5
	game._set_phase(game.Phase.PLAYER_PLAY)

func unit(side: String = "response", lane: int = -1, data: Dictionary = {}) -> Node:
	var definition := {"id":"fixture", "name":"Fixture", "type":side, "element":"brace",
		"cost":1, "attack":2, "health":8}
	definition.merge(data, true)
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition)
	if lane >= 0:
		card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	else:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	return card

func placement() -> void:
	fixture()
	for view in [game.DESK_VIEW, game.BOARD_VIEW]:
		game._apply_view(view)
		for slot in game._response_slots():
			var point: Vector2 = game.camera.unproject_position(slot.global_position)
			check(game.slot_at_screen_position(point) == slot, "visible lane center selects the same lane")
	check(game.slot_at_screen_position(Vector2(-1000, -1000)) == null, "outside board rejects placement")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	placement()
	game.clear_battle()
	print("OCT18 CARD LOGIC: %d failures" % failures)
	quit(1 if failures else 0)
