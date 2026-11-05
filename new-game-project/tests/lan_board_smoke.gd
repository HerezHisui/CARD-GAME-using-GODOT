extends SceneTree
## LAN client 3D table (scripts/lan_board_3d.gd). Fake views for both seats, no network.
## Checks the lane cards, the hand order, the lit lanes, the signals the mirror presses, an in-place update,
## and that no mirror card can reach a host rule (group "cards", pickable).

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")

var failures := 0
var checks := 0
var game: Node
var session: Node
var sent: Array = []  # what the mirror pressed, in order


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
	await process_frame
	session = LanSession.new()
	root.add_child(session)
	await check_seat("preparedness")
	await check_seat("disaster")
	check_pick_and_cancel()
	session.queue_free()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_board_smoke (%d checks)" % checks)
	quit(0)


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


func listen(panel: Control) -> void:
	sent.clear()
	panel.hand_pressed.connect(func(index: int) -> void: sent.append(["hand", index]))
	panel.lane_pressed.connect(func(lane: int) -> void: sent.append(["lane", lane]))
	if panel.has_signal("tactic_pressed"):
		panel.tactic_pressed.connect(func(id: String) -> void: sent.append(["tactic", id]))
	panel.end_turn_pressed.connect(func() -> void: sent.append(["end"]))
	panel.back_pressed.connect(func() -> void: sent.append(["back"]))


func lit(lane_side: String) -> Array:
	var slots: Array = game._response_slots() if lane_side == "response" else game._threat_slots()
	var out: Array = []
	for lane in slots.size():
		if slots[lane].visible:
			out.append(lane)
	return out


func check_seat(seat: String) -> void:
	var own := "response" if seat == "preparedness" else "disaster"
	var panel: Control = LanPrepPanel.new() if seat == "preparedness" else LanClientPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	var hud_layer: Node = game.get_node_or_null("HUD")
	var hud_was: bool = hud_layer.visible if hud_layer else true
	game.visible = false  # the idle client game is hidden by the director
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, seat, cover)
	listen(panel)
	var label := seat + ": "
	expect(not board.shown, label + "nothing shown before the first view")
	session.view_received.emit(make_view(seat, 3))
	await process_frame
	expect(board.shown, label + "first view turns the table on")
	expect(not cover.visible and not panel.visible, label + "cover and 2D panel hidden")
	await process_frame
	expect(game.visible, label + "the game is shown")
	expect(hud_layer == null or not hud_layer.visible, label + "game HUD hidden")
	var count := 0
	for lane_side in ["response", "disaster"]:
		for card in board.lane_cards[lane_side]:
			count += 1 if card != null else 0
	expect(count == 4, label + "four lane cards")
	expect(board.lane_cards.response[0] != null and board.lane_cards.response[1] == null, label + "lane places")
	expect(board.lane_cards.disaster[3] != null, label + "threat lane 3")
	expect(board.hand_cards.size() == 3, label + "three hand cards")
	var names: Array = []
	for card in board.hand_cards:
		names.append(card.card_data.name)
	expect(names == ["Hand Zero", "Hand One", "Hand Two"], label + "hand order")
	expect(board.foe_cards.size() == (4 if seat == "preparedness" else 5), label + "opponent hand count")
	check_safe_cards(board, label)
	# In place update: same card, lower health.
	var before: Node3D = board.lane_cards.response[0]
	session.view_received.emit(make_view(seat, 1, 3))
	await process_frame
	expect(board.lane_cards.response[0] == before, label + "same node when the card is the same")
	expect(int(before.card_data.health) == 1, label + "health updated in place")
	# A different card in the lane replaces the node.
	var changed := make_view(seat, 3)
	changed.cards.a = entry(unit("Ally New"))
	session.view_received.emit(changed)
	await process_frame
	expect(board.lane_cards.response[0] != before, label + "node replaced when the card changes")
	expect(board.lane_cards.response[0].card_data.name == "Ally New", label + "new card name")
	await check_clicks(board, seat, own, label)
	session.match_over.emit(seat)
	expect(board.over_box.visible, label + "match over box")
	sent.clear()
	board.click_end()
	expect(sent.is_empty(), label + "no press after match over")
	board.free()
	cover.free()
	panel.free()
	await process_frame
	expect(hud_layer == null or hud_layer.visible == hud_was, label + "HUD restored")
	expect(not game.visible, label + "game hidden again")
	for slot: Node3D in game._response_slots() + game._threat_slots():
		expect(slot.material_override == null, label + "lane look reset")


func check_safe_cards(board: Node, label: String) -> void:
	var all: Array = board.hand_cards + board.foe_cards
	for lane_side in ["response", "disaster"]:
		all += board.lane_cards[lane_side].filter(func(c) -> bool: return c != null)
	for card in all:
		expect(card.preview_only, label + "card is preview only")
		expect(not card.input_ray_pickable, label + "card is not pickable")
		expect(not card.is_in_group("cards"), label + "card is not in group cards")


func check_clicks(board: Node, seat: String, own: String, label: String) -> void:
	board.click_hand(1)
	await process_frame
	expect(sent == [["hand", 1]], label + "click_hand presses hand_pressed")
	expect(lit(own) == [1, 3], label + "lit lanes " + str(lit(own)))
	board.click_lane(0)
	expect(sent.size() == 1, label + "an unlit lane presses nothing")
	board.click_lane(3)
	expect(sent.back() == ["lane", 3], label + "click_lane presses lane_pressed")
	if seat == "preparedness":
		board.click_tactic("brace")
		await process_frame
		expect(sent.back() == ["tactic", "brace"], label + "click_tactic presses tactic_pressed")
		expect(lit(own) == [0, 2], label + "tactic lanes")
		board.click_lane(2)
		expect(sent.back() == ["lane", 2], label + "tactic lane press")
	board.click_end()
	expect(sent.back() == ["end"], label + "click_end presses end_turn_pressed")
	board._cancel_pick(false)
	await process_frame
	expect(lit(own).is_empty(), label + "lanes dark after cancel")


# Right click lets the pick go and tells the session. Not your turn presses nothing.
func check_pick_and_cancel() -> void:
	var panel := LanClientPanel.new()
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "disaster", null)
	listen(panel)
	var view := make_view("disaster", 3)
	view.is_disaster_turn = false
	session.view_received.emit(view)
	board.click_hand(0)
	board.click_end()
	expect(sent.is_empty(), "their turn: no press")
	board.free()
	panel.free()
