extends SceneTree
var checks := 0
var failures := 0
var game: Node
const Match = preload("res://scripts/versus_match.gd")
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + label)
func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.run_director.persistence.enabled = false
	game.encounter_kind = "versus"
	game.run_director.battle_active = true
	game.run_director.screen = ""
	game.run_director.modal.hide()
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.phase = game.Phase.PLAYER_PLAY
	for disaster: bool in [false, true]:
		game.set_seats("remote" if disaster else "local", "local" if disaster else "remote")
		game.disaster_waiting = disaster
		game.phase = game.Phase.ENEMY if disaster else game.Phase.PLAYER_PLAY
		game._apply_view(game.DESK_VIEW)
		for i in 3: await process_frame
		var own: Array = game._threat_slots() if disaster else game._response_slots()
		var foe: Array = game._response_slots() if disaster else game._threat_slots()
		for i in 4:
			var a: Vector2 = game.camera.unproject_position(own[i].global_position)
			var b: Vector2 = game.camera.unproject_position(foe[i].global_position)
			print("seat ", disaster, " lane ", i, " own ", a, " foe ", b)
			if Match.SIDE_BY_SIDE_CAMERA:
				expect(a.x < b.x, "local lane left of opponent for both seats")
			else:
				expect(a.y > b.y, "checkpoint local lane below opponent")
		check_plates("host " + str(disaster), game._player_hp_ui, game._enemy_hp_ui,
			game.run_director.versus_hud.energy_plate, game.run_director.versus_hud.tension_plate)
	game.disaster_waiting = false
	game.phase = game.Phase.PLAYER_PLAY
	game.set_seats("local", "local")
	for i in 3: await process_frame
	game._apply_view(game.DESK_VIEW)
	expect(game.get_node("CameraPivot").rotation_degrees == game.DESK_VIEW.rot, "hotseat camera unchanged")
	game.encounter_kind = "battle"
	game.set_seats("remote", "local")
	game._apply_view(game.DESK_VIEW)
	expect(game.get_node("CameraPivot").rotation_degrees == game.DESK_VIEW.rot, "singleplayer unchanged")
	game.set_seats("local", "local")
	game.run_director.battle_active = false
	for i in 3: await process_frame
	var session = load("res://scripts/lan_session.gd").new()
	root.add_child(session)
	for seat: String in ["preparedness", "disaster"]:
		var path := "lan_prep_panel" if seat == "preparedness" else "lan_client_panel"
		var panel = load("res://scripts/" + path + ".gd").new()
		root.add_child(panel)
		var board = load("res://scripts/lan_board_3d.gd").new()
		root.add_child(board)
		board.setup(game, game.run_director, session, panel, seat)
		session.view_received.emit(make_view(seat, 3))
		for i in 40: await process_frame
		var disaster := seat == "disaster"
		var own: Array = game._threat_slots() if disaster else game._response_slots()
		var foe: Array = game._response_slots() if disaster else game._threat_slots()
		for i in 4:
			var a: Vector2 = game.camera.unproject_position(own[i].global_position)
			var b: Vector2 = game.camera.unproject_position(foe[i].global_position)
			if Match.SIDE_BY_SIDE_CAMERA:
				expect(a.x < b.x, seat + " client local lane on left")
				expect(a.y < root.get_visible_rect().size.y * 0.65, seat + " lanes above hand")
			else:
				expect(a.y > b.y, seat + " checkpoint local lane below opponent")
		var shared: Dictionary = Match.seat_camera(disaster)
		if not Match.SIDE_BY_SIDE_CAMERA: shared = board.SEAT_VIEW if disaster else game.DESK_VIEW
		check_plates("client " + seat, board.me_plate.box, board.foe_plate.box,
			board.resource_plate, board.foe_resource)
		expect(game.get_node("CameraPivot").rotation_degrees.is_equal_approx(shared.rot), seat + " shared camera")
		for side in board.lane_cards:
			for c in board.lane_cards[side]:
				if not is_instance_valid(c): continue
				var center: Vector2 = game.camera.unproject_position(c.global_position)
				var top: Vector2 = game.camera.unproject_position(c.global_position - c.global_basis.z * 0.1)
				expect(top.y < center.y, seat + " lane card reads upright")
		var hand: Vector2 = game.camera.unproject_position(board.hand_cards[0].global_position)
		expect(hand.y > root.get_visible_rect().size.y * 0.65, seat + " hand at bottom")
		board.queue_free()
		panel.queue_free()
		await process_frame
	session.queue_free()
	game.queue_free()
	await process_frame
	print("side_by_side_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func unit(card_name: String, health := 3) -> Dictionary:
	return {"name": card_name, "type": "response", "element": "evac", "cost": 0, "attack": 1, "health": health}


func threat(card_name: String, health := 3) -> Dictionary:
	return {"name": card_name, "type": "disaster", "element": "fire", "cost": 0, "attack": 1, "health": health,
		"tension_cost": 0}


func entry(definition: Dictionary, health := -1) -> Dictionary:
	var copy := definition.duplicate(true)
	if health >= 0:
		copy.health = health
	var runtime := {"max_health": int(definition.health), "statuses": {}, "modifiers": []}
	return {"definition": copy, "runtime": runtime}


# A view with two cards per row, a hand of three, and hints that allow lanes 1 and 3.
func make_view(seat: String, ally_health: int, round_number := 2) -> Dictionary:
	var cards := {
		"a": entry(unit("Ally One"), ally_health), "b": entry(unit("Ally Two")),
		"x": entry(threat("Threat One")), "y": entry(threat("Threat Two")),
		"h0": entry(unit("Hand Zero")), "h1": entry(unit("Hand One")), "h2": entry(unit("Hand Two")),
	}
	var view := {
		"round": round_number, "first_side": "response", "coin": {},
		"sides": {
			"response": {"hp": 14, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 17, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["a", "", "b", ""], "disaster": ["x", "", "", "y"]},
		"cards": cards,
	}
	var hints := []
	for i in 3:
		if seat == "preparedness":
			hints.append({"can_play": true, "problem": "", "lanes": [1, 3]})
		else:
			hints.append({"can_use": true, "problem": "", "needs_target": false, "lanes": [1, 3],
				"sacrifices": [], "targets": []})
	view.hints = hints
	if seat == "preparedness":
		view.side = "preparedness"
		view.is_prep_turn = true
		view.prep_hand = ["h0", "h1", "h2"]
		view.counts = {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8}
		view.energy = 3
		view.energy_cap = 5
		view.plan_tokens = 0
		view.armed = ""
		view.tactics = [{"id": "brace", "name": "Brace", "cost": 1, "available": true, "lanes": [0, 2]}]
	else:
		view.is_disaster_turn = true
		view.disaster_hand = ["h0", "h1", "h2"]
		view.counts = {"response_hand": 5, "response_draw": 9, "disaster_draw": 8}
		view.actions_left = 3
	return view

func check_plates(label: String, hp_left: Control, hp_right: Control, resource_a: Control,
		resource_b: Control) -> void:
	print(label, " HP y=", hp_left.global_position.y, "/", hp_right.global_position.y,
		" resource y=", resource_a.global_position.y, "/", resource_b.global_position.y)
	expect(is_equal_approx(hp_left.global_position.y, hp_right.global_position.y), label + " HP same top")
	expect(is_equal_approx(resource_a.global_position.y, resource_b.global_position.y), label + " resource same top")
	expect(hp_left.global_position.y >= 60, label + " HP below navigation")
	expect(resource_a.global_position.y >= hp_left.global_position.y + hp_left.size.y, label + " resources below HP")
