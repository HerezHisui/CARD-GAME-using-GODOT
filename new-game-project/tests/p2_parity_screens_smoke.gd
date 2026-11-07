extends SceneTree
## p2-parity Part 3. The LAN client (Player 2) end screen and hover hint match the host:
## the result notice has the host's words and cream result style, and a hovered sealed card shows the
## host's seal tooltip. Fake views, no network, real mouse events.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const CardScript = preload("res://scripts/card_3d.gd")

var failures := 0
var checks := 0
var game: Node
var session: Node
var board: Node
var panel: Control
var backs := 0


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


func entry(definition: Dictionary) -> Dictionary:
	return {"definition": definition, "runtime": {"max_health": int(definition.health), "statuses": {},
		"modifiers": []}}


# Round 2. Hand h0 is sealed until round 4. Foe lane 3 holds a field-sealed threat.
func make_view(match_id: String) -> Dictionary:
	var hint := {"can_play": true, "problem": "", "lanes": [1, 2]}
	var sealed_hand := unit("Sealed Hand")
	sealed_hand.locked_until = 4
	var sealed_threat := unit("Sealed Threat", "disaster")
	sealed_threat.seal_round = 2
	return {
		"match_id": match_id, "round": 2, "first_side": "response", "coin": {}, "side": "preparedness",
		"phase": "play", "turn_side": "preparedness", "is_prep_turn": true, "prep_hand": ["h0", "h1"],
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", "t"]},
		"cards": {"t": entry(sealed_threat), "h0": entry(sealed_hand), "h1": entry(unit("Free Hand"))},
		"hints": [hint, hint],
		"counts": {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8},
		"energy": 3, "energy_cap": 5, "plan_tokens": 0, "armed": "", "tactics": [],
	}


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
	panel.back_pressed.connect(func() -> void: backs += 1)
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	game.run_director.visible = false
	board = LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "preparedness", cover)
	session.view_received.emit(make_view("m1"))
	await frames(10)
	await check_seal_tooltip()
	await check_result("disaster", "DISASTER WINS", "The school was lost.")
	session.view_received.emit(make_view("m2"))
	await frames(3)
	expect(not board.over_box.visible, "new match: the result notice hides")
	await check_result("preparedness", "PREPAREDNESS WINS", "The school is safe.")
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("p2_parity_screens_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: p2_parity_screens_smoke (%d checks)" % checks)
	quit(0)


func hand_point(index: int) -> Vector2:
	var polygon: PackedVector2Array = board._polygon(index, false)
	var sum := Vector2.ZERO
	for point in polygon: sum += point
	return sum / polygon.size()


# Hover a sealed hand card, then a field-sealed foe lane card: the host's text. A free card hides it.
func check_seal_tooltip() -> void:
	await hover(hand_point(0))
	var tip: Label = board.seal_tooltip
	expect(tip.visible and tip.text == CardScript.seal_hint(board.hand_cards[0].card_data, 2),
		"tooltip: a sealed hand card shows the host's hint")
	expect(tip.text.contains("until round 4"), "tooltip: the hand seal names the round")
	expect(root.get_visible_rect().encloses(tip.get_global_rect()), "tooltip: inside the screen")
	await hover(hand_point(1))
	expect(not tip.visible, "tooltip: a free hand card shows none")
	var slot: Node3D = game._threat_slots()[3]
	await hover(game.camera.unproject_position(slot.global_position))
	expect(tip.visible and tip.text.begins_with("Sealed: Active this round"), "tooltip: a sealed lane card")
	board.open_inspection(board.lane_cards.disaster[3])
	await frames(2)
	expect(not tip.visible, "tooltip: hidden under the inspect panel")
	var text: String = board.inspection.find_child("DossierText", true, false).text
	expect(text.contains("Sealed: Active this round"), "inspect: the seal line in THIS COMBAT")
	board.close_inspection()
	await hover(Vector2(20, 360))


# The host's result words, the cream result notice, and Back to title through a real click.
func check_result(winner: String, title: String, note: String) -> void:
	session.match_over.emit(winner)
	await frames(3)
	expect(board.over_box.visible, winner + ": the result notice shows")
	expect(board.over_label.text == title, winner + ": the host's title")
	expect(board.over_note.text == note, winner + ": the host's subtitle")
	var paper: StyleBox = board.over_box.get_theme_stylebox("panel")
	expect(paper is StyleBoxFlat and paper.bg_color == Color("ead3a5"), winner + ": the cream result style")
	expect(board.over_box.find_child("ResultIcon", true, false) != null, winner + ": the result icon")
	expect(root.get_visible_rect().encloses(board.over_box.get_global_rect()), winner + ": inside the screen")
	var before := backs
	await click(board.over_box.find_child("BackButton", true, false))
	expect(backs == before + 1, winner + ": Back to title is pressed")


# Headless has no real cursor, and _process reads the viewport mouse. Set it like lan_testers_batch2_smoke.
func hover(point: Vector2) -> void:
	await move_mouse(point)
	board.mouse = point
	board._update_hover()
	board._update_seal_tooltip()
	await frames(1)
	board.mouse = point
	board._update_hover()
	board._update_seal_tooltip()


func move_mouse(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await frames(3)


func click(control: Control) -> void:
	if control == null:
		expect(false, "click: control exists")
		return
	var center := control.get_global_rect().get_center()
	await move_mouse(center)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.global_position = center
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await frames(3)


func frames(count: int) -> void:
	for i in count:
		await process_frame
