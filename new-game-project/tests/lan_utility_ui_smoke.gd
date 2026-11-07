extends SceneTree
## LAN_PREP_UTILITIES part 4: the Preparedness client UI, with real input over loopback.
## Both screens are driven: the fallback panel (lan_prep_panel.gd) and the 3D table (lan_board_3d.gd).
## No-target casts, lane picks, ally-then-destination, list picks, Cancel, Esc, a refreshed view keeping the choice.

const LanSession = preload("res://scripts/lan_session.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")

const TEST_PORT := 24741
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
var escapes_seen := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


# Counts an Esc that nothing above it handled. The board must swallow an Esc that closes a choice.
class EscCounter extends Node:
	var seen := 0
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: seen += 1


var counter: EscCounter


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.presentation.automated_choice = 0
	await process_frame
	counter = EscCounter.new()
	root.add_child(counter)
	await connect_sides()
	await check_panel_flow()
	await check_panel_flag_off()
	await check_board_flow()
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
	print("PASS: lan_utility_ui_smoke (%d checks)" % checks)
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


func unit(id: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": cost,
		"attack": 1, "health": 10}


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 10, "tension_cost": 1}


func spell(id: String, effect: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": "Spell " + id, "type": "response", "element": "evac", "cost": cost,
		"utility": true, "effect": effect}


func put(definition: Dictionary, slot: Node3D) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	card.current_slot = slot
	card.in_hand = false
	return card


func fixture(flag: bool = true) -> void:
	paused = false
	game.clear_battle()
	game.set_seats("remote", "local")
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.lan_prep_utilities_override = flag
	game.player_first = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 5
	game.preparedness = 5
	game.plans.tokens = 2
	game.plans.committed_round = 0
	game.plans.unlocked.assign(["brace", "supply", "shelter", "extract"])
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)


func choice() -> RefCounted:
	return game.preparedness_actions.utility_choice


func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card: Node) -> String: return str(card.card_data.id))


func lane_card(lane: int) -> Node:
	return game._get_card_in_slot(game._response_slots()[lane])


# Send the board to the client and wait until a NEW view arrives, then let the layout settle.
func publish(_expected_hand: int) -> void:
	var old: Dictionary = client.last_view
	host.send_view()
	await wait_until(func() -> bool: return not is_same(client.last_view, old))
	await process_frame
	await process_frame


# Wait for the host to answer one more message.
func answered(before: int) -> bool:
	var ok := await wait_until(func() -> bool: return host_results.size() > before)
	# The view that follows the answer needs a few frames to reach the client and lay out.
	for i in 6: await process_frame
	return ok


func click(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = motion.position
	press.global_position = motion.position
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


# A real mouse move and a left press (down) or release at a point.
func press_at(point: Vector2, down: bool) -> void:
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


func click_at(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.position = point
	press.global_position = point
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func press_escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key, true)
	await process_frame


func enabled_buttons(row: Control) -> Array:
	var lanes: Array = []
	for lane in row.get_child_count():
		if not row.get_child(lane).disabled: lanes.append(lane)
	return lanes


# The point on screen where a lane of the given row sits.
func lane_point(lane: int, response: bool) -> Vector2:
	var slot: Node3D = (game._response_slots() if response else game._threat_slots())[lane]
	return game.camera.unproject_position(slot.to_global(slot.get_aabb().get_center()))


func send_wait(call: Callable) -> void:
	var before := host_results.size()
	await call.call()
	await answered(before)


# ------------------------------------------------------------------- the fallback panel

func check_panel_flow() -> void:
	# Draw: a no-target cast with one click.
	fixture()
	game.add_card_to_hand(spell("s_draw", "draw"))
	game.deck.assign([unit("d1"), unit("d2"), unit("d3")])
	await publish(1)
	expect(not panel.hand_row.get_child(0).disabled, "panel: the castable Draw is enabled")
	expect("Not available" not in panel.hand_row.get_child(0).text, "panel: no LAN excuse on Draw")
	var before := host_results.size()
	await click(panel.hand_row.get_child(0))
	expect(await answered(before), "panel: host answered the Draw")
	expect(game.preparedness == 4 and hand_ids().size() == 2 and not choice().active(), "panel: Draw cast once")
	await publish(2)
	# Rally: lanes light, a lane click picks, one payment.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	put(unit("a3"), game._response_slots()[3])
	await publish(1)
	before = host_results.size()
	await click(panel.hand_row.get_child(0))
	expect(await answered(before), "panel: host answered the begin")
	expect(await wait_until(func() -> bool: return client.last_view.get("pending_choice", {}).has("stage")),
		"panel: choice arrived")
	await process_frame
	expect(choice().active() and game.preparedness == 5, "panel: begin spent nothing")
	expect(panel.choice_cancel.visible and panel.choice_label.visible, "panel: prompt and Cancel shown")
	expect("Choose a deployed ally" in panel.choice_label.text, "panel: the prompt")
	expect(enabled_buttons(panel.response_row) == [0, 3], "panel: only ally lanes light")
	expect(enabled_buttons(panel.disaster_row).is_empty(), "panel: the Disaster row stays dark for a Rally")
	expect(panel.end_button.disabled, "panel: End Turn is off while a choice is open")
	# A refreshed view keeps the choice open.
	await publish(1)
	expect(panel.choice_cancel.visible and enabled_buttons(panel.response_row) == [0, 3],
		"panel: refreshed view restores the choice")
	before = host_results.size()
	await click(panel.response_row.get_child(3))
	expect(await answered(before), "panel: host answered the pick")
	expect(int(lane_card(3).statuses.get("strength", 0)) == 2 and game.preparedness == 4 and not choice().active(),
		"panel: Rally picked and paid once")
	expect(await wait_until(func() -> bool: return not panel.choice_cancel.visible), "panel: the choice closes")
	# Cancel.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await publish(1)
	before = host_results.size()
	await click(panel.hand_row.get_child(0))
	await answered(before)
	await wait_until(func() -> bool: return panel.choice_cancel.visible)
	before = host_results.size()
	await click(panel.choice_cancel)
	expect(await answered(before), "panel: host answered Cancel")
	expect(not choice().active() and game.preparedness == 5 and hand_ids() == ["s_rally"], "panel: Cancel spent nothing")
	expect(await wait_until(func() -> bool: return not panel.choice_cancel.visible), "panel: Cancel closes the choice")
	# Seal picks a Disaster lane.
	fixture()
	game.add_card_to_hand(spell("s_seal", "seal", 2))
	put(threat("t1"), game._threat_slots()[1])
	await publish(1)
	before = host_results.size()
	await click(panel.hand_row.get_child(0))
	await answered(before)
	await wait_until(func() -> bool: return panel.choice_cancel.visible)
	expect(enabled_buttons(panel.disaster_row) == [1] and enabled_buttons(panel.response_row).is_empty(),
		"panel: Seal lights the Disaster lane only")
	before = host_results.size()
	await click(panel.disaster_row.get_child(1))
	expect(await answered(before), "panel: host answered the Seal pick")
	expect(int(game._get_card_in_slot(game._threat_slots()[1]).card_data.get("seal_round", -1)) == game.turn,
		"panel: field card sealed")
	# Move: ally then destination.
	fixture()
	game.add_card_to_hand(spell("s_move", "move"))
	var mover := put(unit("a0"), game._response_slots()[0])
	await publish(1)
	before = host_results.size()
	await click(panel.hand_row.get_child(0))
	await answered(before)
	await wait_until(func() -> bool: return panel.choice_cancel.visible)
	before = host_results.size()
	await click(panel.response_row.get_child(0))
	await answered(before)
	expect(await wait_until(func() -> bool: return client.last_view.pending_choice.get("stage", "") == "destination"),
		"panel: the second stage arrives")
	await process_frame
	expect(enabled_buttons(panel.response_row) == [1, 2, 3] and game.preparedness == 5,
		"panel: empty lanes light, still unpaid")
	before = host_results.size()
	await click(panel.response_row.get_child(2))
	expect(await answered(before), "panel: host answered the destination")
	expect(lane_card(2) == mover and game.preparedness == 4, "panel: ally moved, paid once")
	# Tutor: the candidates are buttons with faces. A click picks.
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor", 2))
	game.deck.assign([unit("t_a"), unit("t_b")])
	await publish(1)
	before = host_results.size()
	await click(panel.hand_row.get_child(0))
	await answered(before)
	await wait_until(func() -> bool: return panel.choice_row.get_child_count() == 2)
	var first_text: String = panel.choice_row.get_child(0).text
	var second_text: String = panel.choice_row.get_child(1).text
	expect(first_text.begins_with("Unit t_a") and second_text.begins_with("Unit t_b"),
		"panel: deck candidates show their cards")
	before = host_results.size()
	await click(panel.choice_row.get_child(1))
	expect(await answered(before), "panel: host answered the Tutor pick")
	expect(hand_ids() == ["t_b"] and game.preparedness == 3, "panel: Tutor picked and paid once")
	# Tax is blind.
	fixture()
	game.add_card_to_hand(spell("s_tax", "tax", 2))
	game.enemy_hand.assign([threat("SECRET_a"), threat("SECRET_b")])
	await publish(1)
	before = host_results.size()
	await click(panel.hand_row.get_child(0))
	await answered(before)
	await wait_until(func() -> bool: return panel.choice_row.get_child_count() == 2)
	expect(panel.choice_row.get_child(0).text == "Hidden card 1" and panel.choice_row.get_child(1).text == "Hidden card 2",
		"panel: Tax entries are blind")
	var shown := ""
	for node in [panel.choice_row, panel.hand_row, panel.response_row, panel.disaster_row, panel.tactic_row]:
		for child in node.get_children(): shown += str(child.text)
	expect(not shown.contains("SECRET") and not panel.choice_label.text.contains("SECRET"),
		"panel: no Disaster face on screen")
	before = host_results.size()
	await click(panel.choice_cancel)
	await answered(before)
	# Tactics: Supply needs no ally, Extraction is ally then destination.
	fixture()
	game.deck.assign([unit("d1")])
	put(unit("a1"), game._response_slots()[1])
	await publish(0)
	var supply_button: Button = panel.tactic_row.get_child(1)
	expect(not supply_button.disabled and "Not available" not in supply_button.text, "panel: Supply Line is playable")
	before = host_results.size()
	await click(supply_button)
	expect(await answered(before), "panel: host answered Supply Line")
	expect(game.plans.armed.get("kind", "") == "supply" and game.plans.tokens == 1, "panel: Supply armed with one click")
	fixture()
	put(unit("a1"), game._response_slots()[1])
	await publish(0)
	before = host_results.size()
	await click(panel.tactic_row.get_child(3))
	await answered(before)
	await wait_until(func() -> bool: return panel.choice_cancel.visible)
	expect(enabled_buttons(panel.response_row) == [1] and game.plans.tokens == 2,
		"panel: Extraction asks for the ally first")
	before = host_results.size()
	await click(panel.response_row.get_child(1))
	await answered(before)
	await wait_until(func() -> bool: return client.last_view.pending_choice.get("stage", "") == "destination")
	await process_frame
	before = host_results.size()
	await click(panel.response_row.get_child(3))
	expect(await answered(before), "panel: host answered the Extraction destination")
	expect(game.plans.armed.get("kind", "") == "extract" and game.plans.tokens == 1, "panel: Extraction armed")


# Flag off: the panel keeps its excuses and shows no choice widgets.
func check_panel_flag_off() -> void:
	fixture(false)
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await publish(1)
	expect(panel.hand_row.get_child(0).disabled and "Not available in LAN" in panel.hand_row.get_child(0).text,
		"off: the utility keeps its LAN excuse")
	for index in [1, 2, 3]:
		expect("Not available in LAN" in panel.tactic_row.get_child(index).text, "off: tactic %d keeps its excuse" % index)
	expect(not panel.choice_label.visible and not panel.choice_row.visible and not panel.choice_cancel.visible,
		"off: no choice widgets")
	expect(not client.last_view.has("pending_choice"), "off: the view has no pending_choice")


# ------------------------------------------------------------------- the 3D table

func check_board_flow() -> void:
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	game.add_card_to_hand(spell("s_draw", "draw"))
	game.add_card_to_hand(spell("s_seal", "seal", 2))
	game.add_card_to_hand(spell("s_tutor", "tutor", 2))
	game.add_card_to_hand(spell("s_tax", "tax", 2))
	game.deck.assign([unit("d1"), unit("d2")])
	game.enemy_hand.assign([threat("SECRET_a")])
	put(unit("a0"), game._response_slots()[0])
	put(unit("a2"), game._response_slots()[2])
	put(threat("t1"), game._threat_slots()[1])
	game.hand_container.visible = false
	var cover := ColorRect.new()
	layer.add_child(cover)
	board = LanBoard3D.new()
	layer.add_child(board)
	board.setup(game, director, client, panel, "preparedness", cover)
	await publish(5)
	expect(board.shown and board.hand_cards.size() == 5, "board: shown with the five-card hand")
	# Draw: dropping a spell is one cast. Use the real click path.
	board.click_hand(1)
	var before := host_results.size()
	await answered(before)
	expect(game.preparedness == 4 and hand_ids().size() == 6 and "s_draw" not in hand_ids(),
		"board: Draw cast through click_hand")
	await publish(6)
	# Rally: click the card, lit lanes, a real mouse click on a lit lane.
	var rally_index := hand_ids().find("s_rally")
	board.click_hand(rally_index)
	before = host_results.size()
	await answered(before)
	await settle_box()
	expect(is_instance_valid(board.choice_box) and board.choice_box.name == "UtilityChoice", "board: the choice box is up")
	expect(board.choice_box.find_child("ChoiceCancel", true, false) != null, "board: the box has Cancel")
	expect(lit_lanes(true) == [0, 2] and lit_lanes(false).is_empty(),
		"board: ally lanes light, the Disaster row stays dark")
	expect(board.end_button.disabled, "board: End Turn is off while a choice is open")
	# A press on an unlit lane does nothing.
	var results_before := host_results.size()
	await click_at(lane_point(1, true))
	expect(host_results.size() == results_before and choice().active(), "board: an unlit lane sends nothing")
	# A refreshed view keeps the box.
	await publish(6)
	expect(is_instance_valid(board.choice_box) and lit_lanes(true) == [0, 2], "board: refreshed view restores the choice")
	await process_frame
	before = host_results.size()
	await click_at(lane_point(2, true))
	expect(await answered(before), "board: a real click on a lit lane sent the pick")
	expect(int(lane_card(2).statuses.get("strength", 0)) == 2 and not choice().active(), "board: Rally applied")
	await wait_until(func() -> bool: return board.choice_box == null)
	expect(lit_lanes(true).is_empty(), "board: lanes dark again")
	await publish(5)
	# Seal lights the Disaster row and a real click on it picks.
	board.click_hand(hand_ids().find("s_seal"))
	before = host_results.size()
	await answered(before)
	await settle_box()
	expect(lit_lanes(false) == [1] and lit_lanes(true).is_empty(), "board: Seal lights the Disaster lane")
	before = host_results.size()
	await click_at(lane_point(1, false))
	expect(await answered(before), "board: the click on the Disaster lane sent the pick")
	expect(int(game._get_card_in_slot(game._threat_slots()[1]).card_data.get("seal_round", -1)) == game.turn,
		"board: sealed")
	await wait_until(func() -> bool: return board.choice_box == null)
	expect(lit_lanes(false).is_empty(), "board: the Disaster row goes dark again")
	game.preparedness = 5
	game.deck.assign([unit("e1"), unit("e2")])
	await publish(4)
	# Tutor: candidate buttons in the box. Esc cancels first, nothing spent.
	board.click_hand(hand_ids().find("s_tutor"))
	before = host_results.size()
	await answered(before)
	await settle_box()
	var entry_0: Button = board.choice_box.find_child("ChoiceEntry0", true, false)
	var entry_1: Button = board.choice_box.find_child("ChoiceEntry1", true, false)
	expect(entry_0.text == "Unit e1" and entry_1.text == "Unit e2", "board: Tutor lists the deck cards")
	var energy: int = game.preparedness
	escapes_seen = counter.seen
	before = host_results.size()
	await press_escape()
	expect(await answered(before), "board: Esc sent a cancel")
	expect(counter.seen == escapes_seen, "board: the Esc was swallowed, no leave menu")
	expect(not choice().active() and game.preparedness == energy, "board: Esc cancelled, nothing spent")
	await wait_until(func() -> bool: return board.choice_box == null)
	# Esc with no choice open is not swallowed.
	escapes_seen = counter.seen
	await press_escape()
	expect(counter.seen == escapes_seen + 1, "board: Esc with no choice reaches the menu handler")
	# The game's own menu opened and paused the tree. Close it, as the leave menu would be closed.
	director.close_modal()
	paused = false
	await publish(4)
	# Tutor again, pick through the box.
	board.click_hand(hand_ids().find("s_tutor"))
	before = host_results.size()
	await answered(before)
	await settle_box()
	before = host_results.size()
	await click(board.choice_box.find_child("ChoiceEntry1", true, false))
	expect(await answered(before), "board: the Tutor entry button sent the pick")
	expect("e2" in hand_ids() and game.preparedness == energy - 2, "board: Tutor picked and paid once")
	game.preparedness = 5
	await publish(4)
	# Tax is blind on the table too. Right click cancels.
	board.click_hand(hand_ids().find("s_tax"))
	before = host_results.size()
	await answered(before)
	await settle_box()
	expect(board.choice_box.find_child("ChoiceEntry0", true, false).text == "Hidden card 1", "board: Tax entry is blind")
	energy = game.preparedness
	before = host_results.size()
	await click_at(Vector2(600, 300), MOUSE_BUTTON_RIGHT)
	expect(await answered(before), "board: right click sent a cancel")
	expect(not choice().active() and game.preparedness == energy and "s_tax" in hand_ids(), "board: right click cancelled")
	await wait_until(func() -> bool: return board.choice_box == null)
	# Tactics: Supply is one click, Extraction is two picks.
	await publish(4)
	game.plans.tokens = 2
	game.plans.committed_round = 0
	await publish(4)
	var extract_button: Button = board.tactic_box.get_node("Tactic_extract")
	expect(not extract_button.disabled and extract_button.tooltip_text == "", "board: Extraction is playable")
	board.click_tactic("extract")
	before = host_results.size()
	await answered(before)
	expect(board.choice_box == null, "board: Extraction opens no picker panel, it is a drag")
	expect(lit_lanes(true) == [0, 2] and game.plans.tokens == 2, "board: Extraction lights the allies, no token yet")
	board.click_tactic("brace")
	expect(is_instance_valid(board.note) and board.note_head.text == "Can't do that",
		"board: other tactics wait for the choice")
	# Drag the ally in lane 1 onto the empty lane 4: the host gets the ally, then the lane.
	before = host_results.size()
	await press_at(lane_point(0, true), true)
	expect(lit_lanes(true) == [1, 3], "board: the empty lanes light while the ally is dragged")
	await press_at(lane_point(3, true), false)
	expect(await wait_until(func() -> bool: return host_results.size() >= before + 2),
		"board: the drag sent both picks")
	for i in 6: await process_frame
	expect(game.plans.armed.get("kind", "") == "extract" and game.plans.tokens == 1, "board: Extraction armed")
	# Supply is one click.
	game.plans.armed.clear()
	game.plans.tokens = 2
	game.plans.committed_round = 0
	await publish(4)
	board.click_tactic("supply")
	before = host_results.size()
	await answered(before)
	expect(game.plans.armed.get("kind", "") == "supply", "board: Supply Line armed by one click")


func lit_lanes(response: bool) -> Array:
	var slots: Array = game._response_slots() if response else game._threat_slots()
	var out: Array = []
	for lane in slots.size():
		if slots[lane].visible: out.append(lane)
	return out


# Wait for the choice box to exist, then let its layout settle so a real click lands on the right button.
func settle_box() -> void:
	await wait_until(func() -> bool: return board.choice_box != null)
	for i in 4: await process_frame
