extends SceneTree
## Hot-seat Crosswind: the Disaster presses an ally on the board, drags it, and lets go on an empty lane.
## No panel opens. A drop on an occupied lane or off the lanes moves nothing.

var checks := 0
var failures := 0
var game: Node

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func add_threat(id: String, lane: int) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id": id, "name": id.capitalize(), "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 4})
	card.place_on_slot(game._threat_slots()[lane])
	return card

func point_of(lane: int) -> Vector2:
	return game.camera.unproject_position(game._threat_slots()[lane].global_position)

func mouse(point: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await process_frame

func drag(from_lane: int, to_point: Vector2) -> void:
	await mouse(point_of(from_lane), true)
	await mouse(to_point, false)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.set_seats("local", "local")
	game.run_director.privacy_serial = game.encounter_serial
	game.run_director.privacy_last = "disaster"
	game.run_director.privacy_screen.hide()
	game.disaster_waiting = true
	game._set_phase(game.Phase.ENEMY)
	game.tension = 6
	game.disaster_actions.begin_turn()
	await frames()
	var wind := add_threat("wind", 0)
	var ally := add_threat("ally", 1)
	await frames(20)
	expect(game.disaster_seat.active, "the Disaster seat is on")
	game.disaster_relocation.begin(wind)
	await frames()
	expect(game.disaster_relocation.pending(), "a Crosswind choice is pending")
	expect(game.run_director.screen != "disaster_relocation", "no panel opens in the hot-seat")
	await drag(0, point_of(2))
	expect(game._get_card_in_slot(game._threat_slots()[0]) == wind, "the source cannot be dragged")
	await drag(1, point_of(0))
	expect(game._get_card_in_slot(game._threat_slots()[1]) == ally, "a drop on an occupied lane moves nothing")
	await drag(1, Vector2(5, 5))
	expect(game._get_card_in_slot(game._threat_slots()[1]) == ally, "a drop off the lanes moves nothing")
	expect(game.disaster_relocation.pending(), "the choice stays open after a bad drop")
	await drag(1, point_of(3))
	expect(game._get_card_in_slot(game._threat_slots()[3]) == ally, "the ally lands on the empty lane")
	expect(game._get_card_in_slot(game._threat_slots()[1]) == null, "the old lane is empty")
	expect(not game.disaster_relocation.pending(), "the choice is done")
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	print("%s: crosswind_drag_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
