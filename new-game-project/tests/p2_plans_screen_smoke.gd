extends SceneTree
## p2-plans: the Preparedness Plans screen is the same for every seat.
## Host (P1 Preparedness): the real Plans button opens run_director.show_plans.
## Client (P2 Preparedness): the real Plans icon box opens the same screen, built from the view.
## Both: title, subtitle, status, tiles (title and description), ARMED line and Return are compared.
## Real clicks and a real Esc key. A host Disaster seat does not open the Preparedness plans.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")

var failures := 0
var checks := 0
var game: Node
var director: Node
var session: Node
var sent: Array = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func frames(count: int) -> void:
	for i in count: await process_frame


func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(2)


func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(2)


## The words of a Plans screen content box, in order, for comparing host and client.
func screen_texts(box: Node) -> Dictionary:
	var tiles: Array = []
	for tile in box.get_node("Scroll/List").get_children():
		if tile.is_queued_for_deletion(): continue
		tiles.append([tile.get_node("Box/PickButton").text, tile.get_node("Box/Details").text,
			tile.get_node("Box/PickButton").disabled])
	var armed: Label = box.get_node_or_null("Armed")
	return {
		"title": box.get_child(0).text, "subtitle": box.get_child(1).text,
		"status": box.get_node("Status").text, "tiles": tiles,
		"armed": armed.text if armed != null and armed.visible else "",
		"return": box.get_node("ReturnButton").text,
	}


## Host: P1 is Preparedness on its own turn, with 1 Plan, Brace (no ally, so off) and Emergency Shelter.
func host_setup() -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.set_seats("local", "remote")
	director.battle_active = true
	director.close_modal()
	game.plans.unlocked.assign(["brace", "shelter"])
	game.plans.tokens = 1
	game.plans.committed_round = -1
	game.plans.armed = {}
	game._set_phase(game.Phase.PLAYER_PLAY)
	await frames(5)


func check_host() -> Dictionary:
	await host_setup()
	expect(director.plans_button.visible and not director.plans_button.disabled, "host: the Plans button is on")
	await click(director.plans_button)
	expect(director.screen == "plans" and director.modal.visible, "host: the Plans button opens the screen")
	var texts := screen_texts(director.content)
	await key(KEY_ESCAPE)
	expect(director.screen != "plans" and not director.modal.visible, "host: Esc closes the screen")
	await click(director.plans_button)
	expect(director.screen == "plans", "host: the screen opens again")
	await click(director.content.get_node("ReturnButton"))
	expect(director.screen != "plans", "host: Return closes the screen")
	await click(director.plans_button)
	var shelter: Button = director.content.get_node("Scroll/List").get_child(1).get_node("Box/PickButton")
	await click(shelter)
	expect(director.screen != "plans" and str(game.plans.armed.get("kind", "")) == "shelter",
		"host: picking Emergency Shelter arms it and closes the screen")
	# P1 is the Disaster now (P2 plays Preparedness): the host's P key must not open the Preparedness plans.
	game.set_seats("remote", "local")
	await frames(2)
	await key(KEY_P)
	expect(director.screen != "plans", "host Disaster seat: P does not open the Preparedness plans")
	game.set_seats("local", "local")
	game.clear_battle()
	director.battle_active = false
	await frames(2)
	return texts


## The view a P2 Preparedness client gets in the same state as the host check.
func client_view(armed: String) -> Dictionary:
	return {
		"match_id": "plans", "round": 1, "first_side": "response", "coin": {}, "side": "preparedness",
		"phase": "play", "turn_side": "preparedness", "is_prep_turn": true, "prep_hand": [],
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 3},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 3},
		},
		"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", ""]},
		"cards": {}, "hints": [],
		"counts": {"disaster_hand": 3, "disaster_draw": 9, "response_draw": 8},
		"energy": 3, "energy_cap": 3, "plan_tokens": 1, "armed": armed,
		"tactics": [
			{"id": "brace", "name": "Brace", "cost": 1, "available": false, "lanes": []},
			{"id": "shelter", "name": "Emergency Shelter", "cost": 1, "available": true, "lanes": [],
				"no_ally": true},
		],
	}


func check_client(host: Dictionary) -> void:
	session = LanSession.new()
	root.add_child(session)
	var panel := LanPrepPanel.new()
	panel.tactic_pressed.connect(func(id: String) -> void: sent.append(id))
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, director, session, panel, "preparedness", cover)
	session.view_received.emit(client_view(""))
	await frames(5)
	expect(not board.plans_open(), "client: the Plans screen starts closed")
	await click(board.plans_toggle)
	expect(board.plans_open(), "client: the Plans icon box opens the screen")
	var box: Node = board.plans_panel.get_node("ModalScroll/Content")
	var texts := screen_texts(box)
	for part in ["title", "subtitle", "status", "armed", "return"]:
		expect(texts[part] == host[part], "client %s matches the host (%s / %s)" % [part, texts[part], host[part]])
	expect(texts.tiles.size() == 2, "client: one tile per tactic")
	expect(texts.tiles == host.tiles, "client tiles match the host (%s / %s)" % [texts.tiles, host.tiles])
	expect(root.get_visible_rect().encloses(board.plans_panel.get_global_rect()), "client: the screen fits")
	await key(KEY_ESCAPE)
	expect(not board.plans_open(), "client: Esc closes the screen")
	await click(board.plans_toggle)
	await click(box.get_node("ReturnButton"))
	expect(not board.plans_open(), "client: Return closes the screen")
	await click(board.plans_toggle)
	await click(board.tactic_tile_button("shelter"))
	expect(sent == ["shelter"], "client: picking a tile sends the tactic like the old list")
	expect(not board.plans_open(), "client: picking a tile closes the screen")
	# The ARMED line follows the view, in the host's words.
	session.view_received.emit(client_view("shelter"))
	await frames(2)
	await click(board.plans_toggle)
	expect(screen_texts(box).armed == "ARMED: Emergency Shelter", "client: the ARMED line names the tactic")
	await key(KEY_ESCAPE)
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	await frames(2)


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await frames(3)
	root.size = Vector2i(1280, 720)
	var host := await check_host()
	expect(host.title == director.PLANS_TITLE and host.status == "PLANS 1 / 2", "host: title and status")
	await check_client(host)
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("p2_plans_screen_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: p2_plans_screen_smoke (%d checks)" % checks)
	quit(0)
