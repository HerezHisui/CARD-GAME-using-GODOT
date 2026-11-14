extends SceneTree
## p2-feel. The LAN client (Player 2) hand feels like the host's: the card lifts at the press, the host's
## sounds play once each (hover, select, cancel, refuse, deploy), the hover does not grow the card, the lift
## takes the host's time, and a played unit leaves the fan at once. Fake views, no network, real input events.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")


## Stands in for the Sfx autoload and counts each sound name. The music helpers stay the real, silent ones.
class SfxStub extends "res://scripts/audio_manager.gd":
	var calls: Array = []

	func play(sound_name: String, _volume_db: float = 0.0) -> void:
		calls.append(sound_name)

	func count(sound_name: String) -> int:
		return calls.count(sound_name)


var failures := 0
var checks := 0
var game: Node
var session: Node
var board: Node
var panel: Control
var sfx: SfxStub
var real_sfx: Node
var sent: Array = []  # [signal name, value] from the hidden panel


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func unit(card_name: String) -> Dictionary:
	return {"name": card_name, "type": "response", "element": "evac", "cost": 1, "attack": 2, "health": 4}


func entry(definition: Dictionary) -> Dictionary:
	return {"definition": definition, "runtime": {"max_health": int(definition.health), "statuses": {},
		"modifiers": [], "planned_guard": 0}}


# Preparedness view: own lane 0 taken, lanes 1 and 2 open for both hand cards.
func make_view() -> Dictionary:
	var hint := {"can_play": true, "problem": "", "lanes": [1, 2]}
	return {
		"round": 2, "first_side": "response", "coin": {}, "side": "preparedness", "phase": "play",
		"turn_side": "preparedness", "is_prep_turn": true, "prep_hand": ["h0", "h1"],
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["a", "", "", ""], "disaster": ["", "", "", ""]},
		"cards": {"a": entry(unit("Ally Feel")), "h0": entry(unit("Hand Feel")), "h1": entry(unit("Hand Two"))},
		"hints": [hint, hint],
		"counts": {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8},
		"energy": 3, "energy_cap": 5, "plan_tokens": 0, "armed": "", "tactics": [],
	}


func run() -> void:
	# Count sounds through the same /root/Sfx path the game uses.
	real_sfx = root.get_node_or_null("Sfx")
	if real_sfx: real_sfx.name = "SfxReal"
	sfx = SfxStub.new()
	sfx.audio_enabled_override = false
	sfx.name = "Sfx"
	root.add_child(sfx)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.run_director.persistence.enabled = false
	await process_frame
	root.size = Vector2i(1280, 720)
	session = LanSession.new()
	root.add_child(session)
	panel = LanPrepPanel.new()
	for signal_name in ["hand_pressed", "lane_pressed"]:
		panel.connect(signal_name, func(value) -> void: sent.append([signal_name, value]))
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	game.run_director.visible = false
	board = LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "preparedness", cover)
	session.view_received.emit(make_view())
	await frames(10)
	check_constants()
	await check_hover()
	await check_lift_and_click()
	await check_cancel()
	await check_wrong_lane()
	await check_play()
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.queue_free()
	sfx.free()
	if real_sfx: real_sfx.name = "Sfx"
	await process_frame
	if failures > 0:
		push_error("p2_feel_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: p2_feel_smoke (%d checks)" % checks)
	quit(0)


# The host lifts a hovered card in 0.14 s (card_3d._apply_hover) and keeps HAND_SCALE.
func check_constants() -> void:
	expect(is_equal_approx(board.HAND_SCALE_HOVER, 1.0), "constants: hover does not grow the card, like the host")
	expect(is_equal_approx(board.HOVER_LIFT_SECONDS, 0.14), "constants: lift time is the host's 0.14 s")
	expect(is_equal_approx(game.run_director.INSPECT_HOLD_SECONDS, 0.28), "constants: hold time is the host's")


func lane_point(lane: int) -> Vector2:
	return game.camera.unproject_position(game._response_slots()[lane].global_position)


func hand_point(index: int) -> Vector2:
	var polygon: PackedVector2Array = board._polygon(index, false)
	var sum := Vector2.ZERO
	for point in polygon: sum += point
	return sum / polygon.size()


# One hover sound per new card under the mouse, none while it stays on the same card.
func check_hover() -> void:
	sfx.calls.clear()
	hover(Vector2(640, 40))
	hover(hand_point(0))
	hover(hand_point(0) + Vector2(2, 0))
	expect(board.hovered == 0, "hover: card 0 is hovered")
	expect(sfx.count("card_hover") == 1, "hover: card_hover plays once (got %d)" % sfx.count("card_hover"))
	hover(hand_point(1))
	expect(sfx.count("card_hover") == 2, "hover: a new card plays it again")
	hover(Vector2(640, 40))
	await frames(2)


# Headless has no real cursor, and _process reads the viewport mouse. Set it like p2_parity_screens_smoke.
func hover(point: Vector2) -> void:
	board.mouse = point
	board._update_hover()


# The press lifts the card at once with card_select. A release that did not move still picks the card.
func check_lift_and_click() -> void:
	sfx.calls.clear()
	sent.clear()
	var point := hand_point(0)
	await button(point, true)
	expect(board.held == 0 and board.dragging, "lift: the card is held and lifted at the press, no 8 px wait")
	expect(board.hand_cards[0].art_sprite.render_priority == 100, "lift: the card draws on top at the press")
	expect(sfx.count("card_select") == 1, "lift: card_select plays once")
	await button(point, false)
	expect(sent == [["hand_pressed", 0]], "click: a still release picks the card")
	expect(sfx.count("card_cancel_return") == 0 and sfx.count("invalid_action") == 0, "click: no refuse sound")
	board._cancel_pick(false)
	await frames(3)


# A drag let go away from the lanes goes back with card_cancel_return.
func check_cancel() -> void:
	sfx.calls.clear()
	sent.clear()
	await button(hand_point(1), true)
	await move(Vector2(640, 330))
	await move(Vector2(640, 40))
	await button(Vector2(640, 40), false)
	expect(sfx.count("card_cancel_return") == 1, "cancel: card_cancel_return plays once")
	expect(sfx.count("invalid_action") == 0, "cancel: no invalid_action")
	expect(sent.is_empty(), "cancel: nothing is sent")
	await frames(3)


# A drag let go on a lane that is not open is refused with invalid_action.
func check_wrong_lane() -> void:
	sfx.calls.clear()
	sent.clear()
	await button(hand_point(1), true)
	await move(lane_point(3) + Vector2(0, 40))
	await move(lane_point(3))
	await button(lane_point(3), false)
	expect(sfx.count("invalid_action") == 1, "wrong lane: invalid_action plays once")
	expect(sfx.count("card_cancel_return") == 0, "wrong lane: no cancel sound")
	expect(sent.is_empty(), "wrong lane: nothing is sent")
	await frames(3)


# A drop on an open lane plays unit_deploy once and hides the card at once. A refusal shows it again.
func check_play() -> void:
	sfx.calls.clear()
	sent.clear()
	await button(hand_point(1), true)
	await move(lane_point(1) + Vector2(0, 40))
	await move(lane_point(1))
	await button(lane_point(1), false)
	expect(sent == [["hand_pressed", 1], ["lane_pressed", 1]], "play: the card and lane are sent")
	expect(sfx.count("unit_deploy") == 1, "play: unit_deploy plays once")
	expect(not board.hand_cards[1].visible, "play: the card leaves the fan at once")
	expect(board._hand_at(hand_point(1)) != 1, "play: the hidden card cannot be picked")
	session.event_received.emit("reject", {"reason": "busy"})
	await frames(2)
	expect(board.hand_cards[1].visible, "play: a refusal shows the card again")
	expect(sfx.count("invalid_action") == 1, "play: the refusal plays invalid_action once")
	board._cancel_pick(false)
	await frames(2)


func move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await frames(2)


func button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)
	await frames(2)


func frames(count: int) -> void:
	for i in count:
		await process_frame
