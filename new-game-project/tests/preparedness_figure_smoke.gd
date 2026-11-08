extends SceneTree
## Covers: the Preparedness figure (scripts/preparedness_figure.gd) at the player's seat in single-player,
## local Versus and the LAN client. It must sit on PlayerPosition, have no collision, stay clear of the lanes
## and the Disaster seat hand, and show only from the Disaster seat.
## Rendered frame: run without --headless and add "-- --shot=<folder>" to save a 1280x720 picture.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")

var failures := 0
var checks := 0
var shot_folder := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot_folder = arg.trim_prefix("--shot=")
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func frames(count: int = 3) -> void:
	for i in count: await process_frame


func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await frames()
	check_single_player(game)
	# LAN first: the local match below leaves its coin screen up.
	await check_lan_client(game, "disaster")
	await check_lan_client(game, "preparedness")
	await check_local_versus(game)
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: preparedness_figure_smoke (%d checks)" % checks)
	quit(0)


## The figure's box in world space.
func figure_box(figure: Node3D) -> AABB:
	var mesh := figure.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	return mesh.global_transform * mesh.get_aabb()


## A card-sized box around a lane slot.
func slot_box(slot: Node3D) -> AABB:
	return AABB(slot.global_position - Vector3(0.6, 0.2, 0.8), Vector3(1.2, 0.4, 1.6))


## Seat, collision and lane checks shared by every mode.
func check_place(game: Node, figure: Node3D, label: String) -> void:
	expect(is_instance_valid(figure), label + "figure exists")
	if not is_instance_valid(figure): return
	var seat: Node3D = game.find_child("PlayerPosition", true, false)
	var flat := Vector2(figure.global_position.x - seat.global_position.x,
		figure.global_position.z - seat.global_position.z)
	expect(flat.length() < 0.01, label + "figure stands on PlayerPosition")
	expect(figure.find_children("*", "CollisionObject3D", true, false).is_empty(),
		label + "figure has no collision, so mouse rays pass")
	var box := figure_box(figure)
	var janitor: Node3D = game.opponent_hand.character
	expect(absf(box.size.y - 2.0 * janitor.scale.y) < 0.05, label + "figure is the Janitor's height")
	for slot: Node3D in game._threat_slots() + game._response_slots():
		expect(not box.intersects(slot_box(slot)), label + "figure clear of " + slot.name)


func check_single_player(game: Node) -> void:
	game.clear_battle()
	game.encounter_kind = "battle"
	game.run_director.battle_active = true
	var figure: Node3D = game.opponent_hand.figure
	check_place(game, figure, "Single-player: ")
	expect(not figure.visible, "Single-player: figure hidden from the player's own seat")
	game.run_director.battle_active = false


func check_local_versus(game: Node) -> void:
	var director: Node = game.run_director
	director.start_versus_match()
	director.screen = ""
	director.close_modal()
	game.disaster_is_human = true
	await frames()
	var figure: Node3D = game.opponent_hand.figure
	check_place(game, figure, "Local Versus: ")
	director.versus_hud.update()
	expect(not figure.visible, "Local Versus: hidden on the Preparedness turn")
	# The real seat switch (disaster_seat._wants_seat): a human Disaster waiting on its turn.
	director.battle_active = true
	game.disaster_seat_view = true
	game.phase = game.Phase.ENEMY
	game.disaster_waiting = true
	await frames()
	director.versus_hud.update()
	await frames()
	expect(figure.visible, "Local Versus: shown from the Disaster seat")
	expect(not game.opponent_hand.visible, "Local Versus: the Janitor stays hidden from the Disaster seat")
	var card := {"id": "fixture", "name": "Fixture", "type": "disaster", "cost": 0,
		"attack": 1, "health": 2, "element": "fire", "tension_cost": 0}
	game.enemy_hand.append(card)
	game.disaster_seat._sync_hand()
	await frames()
	expect(not game.disaster_seat.cards.is_empty(), "Local Versus: the Disaster seat hand has a card")
	var box := figure_box(figure)
	for seat_card: Node3D in game.disaster_seat.cards:
		expect(not box.has_point(seat_card.global_position), "Local Versus: figure clear of a Disaster hand card")
	expect(not box.has_point(game.camera.global_position), "Local Versus: the Disaster camera is not inside it")
	await capture("local-versus-disaster-seat")
	game.disaster_waiting = false
	await frames()
	director.versus_hud.update()
	await frames()
	expect(not figure.visible, "Local Versus: hidden again after the Disaster turn")


## A small LAN view with one card per row, enough to turn the client table on.
func make_view(seat: String) -> Dictionary:
	var unit := {"definition": {"name": "Ally", "type": "response", "element": "evac", "cost": 0, "attack": 1,
		"health": 3}, "runtime": {"max_health": 3, "statuses": {}, "modifiers": []}}
	var foe := {"definition": {"name": "Threat", "type": "disaster", "element": "fire", "cost": 0, "attack": 1,
		"health": 3, "tension_cost": 0}, "runtime": {"max_health": 3, "statuses": {}, "modifiers": []}}
	var view := {
		"round": 2, "first_side": "response", "coin": {},
		"sides": {
			"response": {"hp": 14, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 17, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["a", "", "", ""], "disaster": ["x", "", "", ""]},
		"cards": {"a": unit, "x": foe}, "hints": [],
	}
	if seat == "preparedness":
		view.side = "preparedness"
		view.is_prep_turn = true
		view.prep_hand = []
		view.counts = {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8}
		view.energy = 3
		view.energy_cap = 5
		view.plan_tokens = 0
		view.armed = ""
		view.tactics = []
	else:
		view.is_disaster_turn = true
		view.disaster_hand = []
		view.counts = {"response_hand": 5, "response_draw": 9, "disaster_draw": 8}
		view.actions_left = 3
	return view


func check_lan_client(game: Node, seat: String) -> void:
	var label := "LAN client " + seat + ": "
	var session: Node = LanSession.new()
	root.add_child(session)
	var panel: Control = LanPrepPanel.new() if seat == "preparedness" else LanClientPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board: Node = LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, seat, cover)
	session.view_received.emit(make_view(seat))
	await frames()
	expect(board.shown, label + "table is shown")
	if seat == "disaster":
		check_place(game, board.prep_figure, label)
		if is_instance_valid(board.prep_figure):
			expect(board.prep_figure.visible, label + "figure shown from the Disaster seat")
			expect(not figure_box(board.prep_figure).has_point(game.camera.global_position),
				label + "the seat camera is not inside it")
	else:
		expect(board.prep_figure == null, label + "no extra figure at the player's own seat")
		expect(not game.opponent_hand.figure.visible, label + "the game's own figure stays hidden")
	board.queue_free()
	cover.queue_free()
	session.queue_free()
	await frames()


## Saves a 1280x720 frame when a --shot folder is given and the run is not headless.
func capture(shot_name: String) -> void:
	if shot_folder == "" or DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1280, 720)
	# The pass-the-laptop cover would hide the table.
	current_scene.run_director.privacy_screen.hide()
	await frames(8)
	var path := shot_folder.path_join(shot_name + ".png")
	expect(root.get_texture().get_image().save_png(path) == OK, shot_name + " frame saved")
