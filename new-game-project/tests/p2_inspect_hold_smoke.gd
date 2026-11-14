extends SceneTree
## p2-inspect-freeze: a held left click on the LAN client (Player 2) opens the inspect panel and the board
## still answers after it closes. The client board is mounted the real way (lan_title client layer, director
## hidden). Views are fed to the client session. Real input events, every wait capped at MAX_FRAMES.
## Cases: Disaster lane card, Disaster hand card on the other turn and on the own turn, Preparedness hand card,
## Preparedness choice entry. Control: the host's own hold (run_director.begin_inspect_hold).

const MAX_FRAMES := 600
const VersusDecks = preload("res://scripts/versus_decks.gd")

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node
var step := ""


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func unit(card_name: String, card_type: String = "response") -> Dictionary:
	return {"name": card_name, "type": card_type, "element": "evac" if card_type == "response" else "fire",
		"cost": 1, "attack": 2, "health": 4, "tension_cost": 1}


func entry(definition: Dictionary) -> Dictionary:
	return {"definition": definition, "runtime": {"max_health": int(definition.health), "statuses": {},
		"modifiers": []}}


# One view for either seat. own_turn sets whose turn it is. with_choice adds an open Preparedness list.
func make_view(seat: String, own_turn: bool, with_choice: bool = false) -> Dictionary:
	var view := {
		"round": 2, "first_side": "response", "coin": {}, "phase": "play",
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["a", "", "", ""], "disaster": ["", "", "", "t"]},
		"cards": {"a": entry(unit("Ally Hold")), "t": entry(unit("Threat Hold", "disaster")),
			"h0": entry(unit("Hand Hold", "response" if seat == "preparedness" else "disaster")),
			"h1": entry(unit("Hand Other", "response" if seat == "preparedness" else "disaster"))},
	}
	if seat == "preparedness":
		var hint := {"can_play": true, "problem": "", "lanes": [1, 2]}
		view.merge({"side": "preparedness", "turn_side": "preparedness" if own_turn else "disaster",
			"is_prep_turn": own_turn, "prep_hand": ["h0", "h1"], "hints": [hint, hint],
			"counts": {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8},
			"energy": 3, "energy_cap": 5, "plan_tokens": 0, "armed": "", "tactics": []})
		if with_choice:
			view.pending_choice = {"name": "Tutor", "prompt": "Choose a card.", "stage": "deck", "handles": [0, 1],
				"candidates": [{"handle": 0}, {"handle": 1, "card": unit("Choice Hold")}]}
	else:
		var hint := {"can_use": true, "problem": "", "needs_target": false, "lanes": [1, 2], "sacrifices": [],
			"targets": []}
		view.merge({"side": "disaster", "turn_side": "disaster" if own_turn else "preparedness",
			"is_disaster_turn": own_turn, "disaster_hand": ["h0", "h1"], "hints": [hint, hint],
			"counts": {"response_hand": 5, "response_draw": 9, "disaster_draw": 8}, "actions_left": 3})
	return view


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await process_frame
	root.size = Vector2i(1280, 720)
	director.show_title()
	director.ensure_lan_title()
	lan = director.lan_title
	lan._ensure_session()
	# The real client mount: the client layer, the Disaster panel and its board, the director hidden.
	lan._show_client_panel()
	await check_disaster()
	# The host seats this client as Preparedness: a new panel and a new board.
	lan._on_seat("preparedness")
	await check_preparedness()
	lan._close_client_panel()
	await frames(5)
	await check_host_control()
	game.queue_free()
	await frames(5)
	if failures > 0:
		push_error("p2_inspect_hold_smoke: %d of %d checks failed (last step: %s)" % [failures, checks, step])
		quit(1)
		return
	print("PASS: p2_inspect_hold_smoke (%d checks)" % checks)
	quit(0)


func board() -> Node:
	return lan.board_3d


func check_disaster() -> void:
	lan.session.view_received.emit(make_view("disaster", false))
	await frames(10)
	expect(is_instance_valid(board()) and board().shown, "disaster: the client board is shown")
	await hold_case("disaster lane card", lane_point("disaster", 3), "THREAT HOLD")
	await hold_case("disaster hand card, other turn", hand_point(0), "HAND HOLD")
	lan.session.view_received.emit(make_view("disaster", true))
	await frames(5)
	await hold_case("disaster hand card, own turn", hand_point(0), "HAND HOLD")
	await hold_case("disaster own lane card, own turn", lane_point("disaster", 3), "THREAT HOLD")
	await check_real_cards("disaster", VersusDecks.DISASTER_FILES)


func check_preparedness() -> void:
	await frames(3)
	lan.session.view_received.emit(make_view("preparedness", true))
	await frames(10)
	expect(is_instance_valid(board()) and board().side == "preparedness", "prep: the client board is remounted")
	await hold_case("prep hand card, own turn", hand_point(0), "HAND HOLD")
	await hold_case("prep foe lane card", lane_point("disaster", 3), "THREAT HOLD")
	lan.session.view_received.emit(make_view("preparedness", true, true))
	await frames(5)
	var named: Button = board().choice_box.find_child("ChoiceEntry1", true, false)
	expect(named != null, "prep choice: the named entry is there")
	if named != null: await hold_case("prep choice entry", named.get_global_rect().get_center(), "CHOICE HOLD")
	await check_real_cards("preparedness", VersusDecks.PREP_FILES)


# Every real card of the side, in the hand and in a lane: the panel builds fully (dossier and card face).
# A runtime error here would stop the editor's game window at a debugger break, which looks like a freeze.
func check_real_cards(seat: String, files: Array) -> void:
	var own := "response" if seat == "preparedness" else "disaster"
	var hand_key := "prep_hand" if seat == "preparedness" else "disaster_hand"
	for path: String in files:
		for definition: Dictionary in VersusDecks._load_file(path):
			step = "real card %s: %s" % [seat, str(definition.get("name", "?"))]
			var view := make_view(seat, true)
			var health := int(definition.get("health", 1))
			view.cards["r"] = {"definition": definition, "runtime": {"max_health": health, "statuses": {},
				"modifiers": []}}
			view[hand_key] = ["r", "h1"]
			if not definition.get("utility", false): view.lanes[own][1] = "r"
			lan.session.view_received.emit(view)
			await frames(1)
			var targets: Array = [board().hand_cards[0], definition.duplicate(true)]
			if is_instance_valid(board().lane_cards[own][1]): targets.append(board().lane_cards[own][1])
			for target in targets:
				board().open_inspection(target)
				var row: Node = null
				if is_instance_valid(board().inspection): row = board().inspection.get_node("Center/Row")
				expect(row != null and row.get_child_count() == 2 and board().inspection_dossier != null,
					step + ": the panel builds fully (%s)" % ("dict" if target is Dictionary else "card"))
				board().close_inspection()
	await frames(2)


# Press, wait for the panel, release, Esc, click outside. Then the board must still answer.
func hold_case(label: String, point: Vector2, title: String) -> void:
	step = label + ": press"
	print("step: ", step)
	await motion(point)
	await button(point, MOUSE_BUTTON_LEFT, true)
	step = label + ": wait for the hold"
	var opened := await wait_until(func() -> bool: return is_instance_valid(board().inspection))
	expect(opened, label + ": the hold opens the panel")
	expect(title_text() == title, label + ": the panel names the card (got '%s')" % title_text())
	step = label + ": release"
	await button(point, MOUSE_BUTTON_LEFT, false)
	expect(is_instance_valid(board().inspection), label + ": the release keeps it open")
	step = label + ": Esc"
	await key(KEY_ESCAPE)
	expect(not is_instance_valid(board().inspection), label + ": Esc closes it")
	expect(not is_instance_valid(lan.esc_menu), label + ": Esc does not open the menu")
	step = label + ": click outside"
	var outside := Vector2(640, 40)
	await button(outside, MOUSE_BUTTON_LEFT, true)
	await button(outside, MOUSE_BUTTON_LEFT, false)
	expect(not is_instance_valid(board().inspection), label + ": a click outside opens nothing")
	# The same hold again, closed by a click outside the dossier this time.
	step = label + ": second hold"
	await motion(point)
	await button(point, MOUSE_BUTTON_LEFT, true)
	expect(await wait_until(func() -> bool: return is_instance_valid(board().inspection)),
		label + ": a second hold opens again")
	await button(point, MOUSE_BUTTON_LEFT, false)
	step = label + ": close by click outside"
	await button(Vector2(20, 360), MOUSE_BUTTON_LEFT, true)
	expect(not is_instance_valid(board().inspection), label + ": a click outside the dossier closes it")
	await button(Vector2(20, 360), MOUSE_BUTTON_LEFT, false)
	expect(not board().suppress_release, label + ": the closing release is used up")
	await check_alive(label, title)
	board()._cancel_pick(false)


# After a close the board reads the mouse again: a right click on a hand card opens it, Esc closes it.
# (Headless cannot test hover: _process reads the real mouse position, which push_input does not move.)
func check_alive(label: String, title: String) -> void:
	step = label + ": board answers"
	board()._cancel_pick(false)
	# The card picker covers the hand, so a choice case clicks its own entry again.
	var point := hand_point(1)
	var want := "HAND OTHER"
	var named: Button = null
	if is_instance_valid(board().choice_box): named = board().choice_box.find_child("ChoiceEntry1", true, false)
	if named != null:
		point = named.get_global_rect().get_center()
		want = title
	await button(point, MOUSE_BUTTON_RIGHT, true)
	await button(point, MOUSE_BUTTON_RIGHT, false)
	expect(title_text() == want, label + ": the board still answers a right click after the close")
	await key(KEY_ESCAPE)
	expect(not is_instance_valid(board().inspection), label + ": Esc closes the right click panel")


func check_host_control() -> void:
	step = "host control"
	print("step: ", step)
	root.size = Vector2i(1440, 900)
	director.new_run()
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.set_process(false)
	game.add_card_to_hand(director.collection[0])
	var card: Node = game.get_hand_cards()[0]
	await frames(2)
	var point := Vector2(600, 650)
	# The host hold reads Input.is_mouse_button_pressed, so this press goes through Input (like ui_interaction).
	host_mouse(point, true)
	await frames(1)
	card._start_drag()
	director.begin_inspect_hold(card, true)
	var opened := await wait_until(func() -> bool: return director.screen == "inspect")
	expect(opened, "host control: the hold opens the inspect screen")
	host_mouse(point, false)
	await frames(2)
	expect(director.screen == "inspect", "host control: the release keeps it open")
	await key(KEY_ESCAPE)
	expect(director.screen != "inspect" and not paused, "host control: Esc closes it")
	director.battle_active = false
	game.set_process(true)


func host_mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func title_text() -> String:
	if not is_instance_valid(board().inspection): return ""
	var title: Label = board().inspection.find_child("InspectTitle", true, false)
	return title.text if title else ""


func lane_point(lane_side: String, lane: int) -> Vector2:
	var slots: Array = game._threat_slots() if lane_side == "disaster" else game._response_slots()
	return game.camera.unproject_position(slots[lane].global_position)


func hand_point(index: int) -> Vector2:
	var polygon: PackedVector2Array = board()._polygon(index, false)
	var sum := Vector2.ZERO
	for point in polygon: sum += point
	return sum / polygon.size()


func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await frames(2)


func button(point: Vector2, index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT and pressed else 0
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


# Waits until the check is true, at most MAX_FRAMES frames. Prints the step when the cap is hit.
func wait_until(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	for i in MAX_FRAMES:
		if check.call(): return true
		# The client hold counts real ms. Headless frames are faster, so each waited frame is at least 1 ms.
		OS.delay_msec(1)
		await process_frame
	print("step hit the %d frame cap: %s (%d ms)" % [MAX_FRAMES, step, Time.get_ticks_msec() - start])
	return check.call()


func frames(count: int) -> void:
	for i in count:
		await process_frame
