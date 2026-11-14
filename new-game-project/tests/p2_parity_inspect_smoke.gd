extends SceneTree
## p2-parity Part 1. The LAN client (Player 2) inspects cards like the host: a hold or a right click on a lane
## card, an own hand card or a choice entry opens the same dossier and card face. Esc or a left click outside
## the dossier closes it. Only cards in the view can be inspected. Fake views, no network, real input events.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")

var failures := 0
var checks := 0
var game: Node
var session: Node
var board: Node
var panel: Control
var sent: Array = []  # [signal name, value] from the hidden panel


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func unit(card_name: String, card_type: String = "response") -> Dictionary:
	return {"name": card_name, "type": card_type, "element": "evac" if card_type == "response" else "fire",
		"cost": 1, "attack": 2, "health": 4}


func entry(definition: Dictionary, statuses: Dictionary = {}, guard: int = 0) -> Dictionary:
	return {"definition": definition, "runtime": {"max_health": int(definition.health), "statuses": statuses,
		"modifiers": [], "planned_guard": guard}}


# Preparedness view: own lane 0, foe lane 3, two hand cards. With choice: an open list with a hidden entry.
func make_view(with_choice: bool) -> Dictionary:
	var hint := {"can_play": true, "problem": "", "lanes": [1, 2]}
	var view := {
		"round": 2, "first_side": "response", "coin": {}, "side": "preparedness", "phase": "play",
		"turn_side": "preparedness", "is_prep_turn": true, "prep_hand": ["h0", "h1"],
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["a", "", "", ""], "disaster": ["", "", "", "t"]},
		"cards": {"a": entry(unit("Ally Inspect"), {"burn": 2}, 3), "t": entry(unit("Threat Inspect", "disaster")),
			"h0": entry(unit("Hand Inspect")), "h1": entry(unit("Hand Two"))},
		"hints": [hint, hint],
		"counts": {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8},
		"energy": 3, "energy_cap": 5, "plan_tokens": 0, "armed": "", "tactics": [],
	}
	if with_choice:
		view.pending_choice = {"name": "Tutor", "prompt": "Choose a card.", "stage": "deck", "handles": [0, 1],
			"candidates": [{"handle": 0}, {"handle": 1, "card": unit("Choice Inspect")}]}
	return view


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.run_director.persistence.enabled = false
	await process_frame
	root.size = Vector2i(1280, 720)
	session = LanSession.new()
	root.add_child(session)
	panel = LanPrepPanel.new()
	for signal_name in ["hand_pressed", "lane_pressed", "choice_picked"]:
		panel.connect(signal_name, func(value) -> void: sent.append([signal_name, value]))
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	# The real client hides the director under its layer (lan_title._show_client_panel).
	game.run_director.visible = false
	board = LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "preparedness", cover)
	session.view_received.emit(make_view(false))
	await frames(10)
	await check_lane_hold()
	await check_hand_hold()
	await check_right_click()
	await check_quick_click()
	await check_choice_entries()
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("p2_parity_inspect_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: p2_parity_inspect_smoke (%d checks)" % checks)
	quit(0)


func title_text() -> String:
	if not is_instance_valid(board.inspection): return ""
	var title: Label = board.inspection.find_child("InspectTitle", true, false)
	return title.text if title else ""


func dossier_text() -> String:
	var details: RichTextLabel = board.inspection.find_child("DossierText", true, false)
	return details.text if details else ""


func lane_point(lane_side: String, lane: int) -> Vector2:
	var slots: Array = game._threat_slots() if lane_side == "disaster" else game._response_slots()
	return game.camera.unproject_position(slots[lane].global_position)


func hand_point(index: int) -> Vector2:
	var polygon: PackedVector2Array = board._polygon(index, false)
	var sum := Vector2.ZERO
	for point in polygon: sum += point
	return sum / polygon.size()


# Hold on the opponent's lane card: the dossier opens with its name. The release presses nothing. Esc closes.
func check_lane_hold() -> void:
	sent.clear()
	var point := lane_point("disaster", 3)
	await mouse_button(point, MOUSE_BUTTON_LEFT, true)
	await wait_ms(80)
	expect(not is_instance_valid(board.inspection), "lane hold: nothing opens before the hold time")
	await wait_ms(320)
	expect(title_text() == "THREAT INSPECT", "lane hold: the dossier names the foe lane card")
	expect(board.inspection.find_child("DossierText", true, false) != null, "lane hold: same dossier scene")
	await mouse_button(point, MOUSE_BUTTON_LEFT, false)
	expect(is_instance_valid(board.inspection), "lane hold: the release keeps it open")
	expect(sent.is_empty(), "lane hold: the release sends no press")
	await key(KEY_ESCAPE)
	expect(not is_instance_valid(board.inspection), "lane hold: Esc closes it")


# Hold on an own hand card: it opens and the release does not pick the card. A click outside closes it.
func check_hand_hold() -> void:
	sent.clear()
	var point := hand_point(0)
	await mouse_button(point, MOUSE_BUTTON_LEFT, true)
	await wait_ms(400)
	expect(title_text() == "HAND INSPECT", "hand hold: the dossier names the hand card")
	await mouse_button(point, MOUSE_BUTTON_LEFT, false)
	expect(sent.is_empty(), "hand hold: the release does not pick the card")
	expect(board.selected == -1 and board.held == -1, "hand hold: no pick and no drag")
	var outside := Vector2(20, 360)
	await mouse_button(outside, MOUSE_BUTTON_LEFT, true)
	expect(not is_instance_valid(board.inspection), "hand hold: a click outside the dossier closes it")
	await mouse_button(outside, MOUSE_BUTTON_LEFT, false)
	expect(sent.is_empty(), "hand hold: the closing click presses nothing")


# Right click on the own lane card: same panel, with its statuses and plan protection from the view.
func check_right_click() -> void:
	sent.clear()
	await mouse_button(lane_point("response", 0), MOUSE_BUTTON_RIGHT, true)
	await mouse_button(lane_point("response", 0), MOUSE_BUTTON_RIGHT, false)
	expect(title_text() == "ALLY INSPECT", "right click: opens on the own lane card")
	var text := dossier_text() if is_instance_valid(board.inspection) else ""
	expect("Burn 2" in text, "right click: the view's statuses show")
	expect("Plan protection: 3" in text, "right click: the view's plan protection shows")
	await key(KEY_ESCAPE)
	expect(not is_instance_valid(board.inspection), "right click: Esc closes it")
	await mouse_button(Vector2(640, 40), MOUSE_BUTTON_RIGHT, true)
	await mouse_button(Vector2(640, 40), MOUSE_BUTTON_RIGHT, false)
	expect(not is_instance_valid(board.inspection), "right click: empty table opens nothing")


# A quick click still picks a hand card, as before.
func check_quick_click() -> void:
	sent.clear()
	var point := hand_point(1)
	await mouse_button(point, MOUSE_BUTTON_LEFT, true)
	await mouse_button(point, MOUSE_BUTTON_LEFT, false)
	await wait_ms(400)
	expect(not is_instance_valid(board.inspection), "quick click: no inspect")
	expect(sent.size() == 1 and sent[0] == ["hand_pressed", 1], "quick click: the card is picked")
	board._cancel_pick(false)


# Choice entries: a named card opens on right click and on hold. A hidden entry never opens.
func check_choice_entries() -> void:
	session.view_received.emit(make_view(true))
	await frames(5)
	sent.clear()
	var hidden: Button = board.choice_box.find_child("ChoiceEntry0", true, false)
	await mouse_button(hidden.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, true)
	await mouse_button(hidden.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, false)
	await wait_ms(400)
	expect(not is_instance_valid(board.inspection), "choice: a hidden card cannot be inspected")
	var named: Button = board.choice_box.find_child("ChoiceEntry1", true, false)
	var point := named.get_global_rect().get_center()
	await mouse_button(point, MOUSE_BUTTON_RIGHT, true)
	await mouse_button(point, MOUSE_BUTTON_RIGHT, false)
	expect(title_text() == "CHOICE INSPECT", "choice: right click opens the named card")
	expect(board.hud.get_child(-1) == board.inspection, "choice: the panel draws above the choice list")
	await key(KEY_ESCAPE)
	named = board.choice_box.find_child("ChoiceEntry1", true, false)
	point = named.get_global_rect().get_center()
	await mouse_button(point, MOUSE_BUTTON_LEFT, true)
	await wait_ms(400)
	expect(title_text() == "CHOICE INSPECT", "choice: hold opens the named card")
	await mouse_button(point, MOUSE_BUTTON_LEFT, false)
	await frames(3)
	expect(sent.is_empty(), "choice: the release after a hold picks nothing")
	await key(KEY_ESCAPE)
	expect(not is_instance_valid(board.inspection), "choice: Esc closes it")
	named = board.choice_box.find_child("ChoiceEntry1", true, false)
	await mouse_button(named.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
	await mouse_button(named.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, false)
	expect(sent.size() == 1 and sent[0] == ["choice_picked", 1], "choice: a quick click still picks")


func mouse_button(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)
	await frames(2)


func key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await frames(2)


## p2-feel: the hold timer runs on game time like the host, so wait in game time (frames, capped), not the clock.
func wait_ms(ms: int) -> void:
	var waited := 0.0
	var count := 0
	while waited * 1000.0 < ms and count < 600:
		await process_frame
		waited += root.get_process_delta_time()
		count += 1


func frames(count: int) -> void:
	for i in count:
		await process_frame
