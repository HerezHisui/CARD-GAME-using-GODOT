extends SceneTree
## LAN move by drag on the Preparedness client table (lan_board_3d.gd), with real mouse input over loopback.
## Evacuation Route and Lane Marshal open no picker panel: the ally is dragged onto an empty lane, as in hot-seat.
## The host still checks both steps (lan_utility_choice.gd). Esc skips the optional move.
## Crosswind on the Disaster client is covered in lan_crosswind_smoke.gd.

const LanSession = preload("res://scripts/lan_session.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24792
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var game: Node
var director: Node
var host: Node
var client: Node
var panel: Control
var layer: CanvasLayer
var board: Node
var client_joined := false
var host_results: Array = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.presentation.automated_choice = 0
	await process_frame
	await connect_sides()
	fixture()
	var cover := ColorRect.new()
	layer.add_child(cover)
	board = LanBoard3D.new()
	layer.add_child(board)
	board.setup(game, director, client, panel, "preparedness", cover)
	await check_evacuation_route()
	await check_lane_marshal()
	await check_skip()
	board.free()
	panel.free()
	layer.queue_free()
	host.close()
	client.close()
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_move_drag_smoke (%d checks)" % checks)
	quit(0)


func wait_until(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	for i in MAX_FRAMES:
		if check.call():
			return true
		if Time.get_ticks_msec() - start > 10000:
			return false
		await process_frame
	return check.call()


func make_side(side_name: String) -> Node:
	var holder := Node.new()
	holder.name = side_name
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var session: Node = LanSession.new()
	session.name = "LanSession"
	holder.add_child(session)
	return session


func connect_sides() -> void:
	host = make_side("Host")
	client = make_side("Client")
	client.joined_host.connect(func() -> void: client_joined = true)
	host.action_done.connect(func(result: Dictionary) -> void: host_results.append(result))
	host.game = game
	host.host_game(TEST_PORT)
	client.join_game("127.0.0.1", TEST_PORT)
	await wait_until(func() -> bool: return client_joined and host.disaster_peer != 0)
	host.seat_client("preparedness")
	layer = CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	panel = LanPrepPanel.new()
	layer.add_child(panel)
	client.attach_prep_panel(panel)


func unit(id: String, effect: String = "") -> Dictionary:
	var data := {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": 2,
		"attack": 1, "health": 10}
	if not effect.is_empty(): data["effect"] = effect
	return data


func spell(id: String, effect: String) -> Dictionary:
	return {"id": id, "name": "Spell " + id, "type": "response", "element": "evac", "cost": 1,
		"utility": true, "effect": effect}


func put(definition: Dictionary, slot: Node3D) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	card.current_slot = slot
	card.in_hand = false
	return card


func fixture() -> void:
	paused = false
	game.clear_battle()
	game.set_seats("remote", "local")
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.lan_prep_utilities_override = true
	game.player_first = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 5
	game.preparedness = 5
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.hand_container.visible = false


func choice() -> RefCounted:
	return game.preparedness_actions.utility_choice


func lane_card(lane: int) -> Node:
	return game._get_card_in_slot(game._response_slots()[lane])


# Send the board to the client and wait until a NEW view arrives, then let the layout settle.
func publish() -> void:
	var old: Dictionary = client.last_view
	host.send_view()
	await wait_until(func() -> bool: return not is_same(client.last_view, old))
	for i in 3: await process_frame


# Wait until the host has answered this many more messages, then let the next view arrive.
func answered(before: int, count: int = 1) -> bool:
	var ok := await wait_until(func() -> bool: return host_results.size() >= before + count)
	for i in 6: await process_frame
	return ok


func lane_point(lane: int) -> Vector2:
	var slot: Node3D = game._response_slots()[lane]
	return game.camera.unproject_position(slot.to_global(slot.get_aabb().get_center()))


func lit_lanes() -> Array:
	var out: Array = []
	var slots: Array = game._response_slots()
	for lane in slots.size():
		if slots[lane].visible: out.append(lane)
	return out


# A real mouse move and a left press or release at a point.
func mouse_button(point: Vector2, down: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = down
	root.push_input(event, true)
	await process_frame
	await process_frame


# Drag the ally in one lane onto another lane, with real mouse events.
func drag(from_lane: int, to_lane: int) -> void:
	await mouse_button(lane_point(from_lane), true)
	await mouse_button(lane_point(to_lane), false)


func no_move_panel() -> bool:
	return board.choice_box == null and board.hud.find_child("UtilityChoice", true, false) == null


# Evacuation Route: cast, drag the ally onto an empty lane. Paid once, after the move.
func check_evacuation_route() -> void:
	fixture()
	game.add_card_to_hand(spell("s_move", "move"))
	var mover := put(unit("a0"), game._response_slots()[0])
	await publish()
	var before := host_results.size()
	board.click_hand(0)
	await answered(before)
	expect(choice().active() and choice().stage == "ally", "evac: the move opens")
	expect(no_move_panel(), "evac: no picker panel, so nothing covers the Energy plate")
	expect(lit_lanes() == [0], "evac: the ally lane is lit")
	await mouse_button(lane_point(0), true)
	expect(board.move_ally == 0 and lit_lanes() == [1, 2, 3], "evac: pressing the ally lights the empty lanes")
	before = host_results.size()
	await mouse_button(lane_point(2), false)
	expect(await answered(before, 2), "evac: the host answered the ally and the lane")
	expect(lane_card(2) == mover and lane_card(0) == null, "evac: the ally moved to lane 3")
	expect(game.preparedness == 4 and not choice().active(), "evac: paid once, the move is closed")
	expect(lit_lanes().is_empty() and no_move_panel(), "evac: lanes dark again, no panel")


# Lane Marshal: play it, then drag another ally. A drop on a full lane sends nothing.
func check_lane_marshal() -> void:
	fixture()
	var ally := put(unit("a0"), game._response_slots()[0])
	game.add_card_to_hand(unit("marshal", "move_ally"))
	await publish()
	var before := host_results.size()
	client.request_action({"kind": "play", "hand": 0, "lane": 1})
	await answered(before)
	expect(choice().active() and choice().kind == "relocation", "marshal: the move opens after the play")
	expect(no_move_panel() and lit_lanes() == [0], "marshal: no panel, only the other ally is lit")
	before = host_results.size()
	await drag(0, 1)
	for i in 10: await process_frame
	expect(host_results.size() == before and choice().stage == "ally", "marshal: a drop on a full lane sends nothing")
	expect(lane_card(0) == ally, "marshal: the ally stays")
	await drag(0, 3)
	expect(await answered(before, 2), "marshal: the host answered the drag")
	expect(lane_card(3) == ally and lane_card(0) == null and not choice().active(), "marshal: the ally moved to lane 4")
	expect(game.preparedness == 3, "marshal: the move costs nothing more")


# Esc skips the optional move, so the turn cannot get stuck.
func check_skip() -> void:
	fixture()
	var ally := put(unit("a0"), game._response_slots()[0])
	game.add_card_to_hand(unit("marshal", "move_ally"))
	await publish()
	var before := host_results.size()
	client.request_action({"kind": "play", "hand": 0, "lane": 1})
	await answered(before)
	expect(choice().active(), "skip: the move opens")
	before = host_results.size()
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key, true)
	expect(await answered(before), "skip: Esc reaches the host")
	expect(not choice().active() and lane_card(0) == ally, "skip: the move is closed and nothing moved")
	expect(not board.end_button.disabled, "skip: End turn is on again")
