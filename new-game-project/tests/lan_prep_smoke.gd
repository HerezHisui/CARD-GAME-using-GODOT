extends SceneTree
## LAN Part D2-b: LanView.build(game, side) for both sides, and redaction both ways.
## LAN Part D2-c: a remote Preparedness client over loopback (host and client in one process),
## its messages through lan_actions.gd, and real mouse clicks on lan_prep_panel.gd.

const LanSession = preload("res://scripts/lan_session.gd")
const LanView = preload("res://scripts/lan_view.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const BattleState = preload("res://scripts/battle_state.gd")

# Not the game port, and not the ports of lan_smoke (24689) or lan_title_smoke (24693).
const TEST_PORT := 24697
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var game: Node
var director: Node
var host: Node
var client: Node
var client_joined := false
var client_lost := false
var host_results: Array = []
var client_rejects: Array = []
var prep_phases: Array = []


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
	prep_phases = [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]
	game.presentation.automated_choice = 0
	await process_frame
	await check_views()
	await check_panel()
	setup_sides()
	await check_connect()
	await check_messages()
	await check_real_clicks()
	await check_client_leaves()
	host.close()
	client.close()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_prep_smoke (%d checks)" % checks)
	quit(0)


# Wait frame by frame until the check is true. Gives up after MAX_FRAMES or 10 seconds.
func wait_until(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	for i in MAX_FRAMES:
		if check.call():
			return true
		if Time.get_ticks_msec() - start > 10000:
			return false
		await process_frame
	return check.call()


func unit(id: String, cost: int) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": cost,
		"attack": 1, "health": 30}


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 30, "tension_cost": 0}


# A Versus Preparedness play phase with energy, Plan tokens and Brace, Coordinate and Medicine.
func fixture() -> void:
	paused = false
	game.clear_battle()
	game.set_seats("local", "local")
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.player_first = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 3
	game.plans.tokens = 2
	game.plans.committed_round = 0
	game.plans.unlocked.assign(["brace", "coordinate", "medicine"])
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)


# --- D2-b: views ---

# Every private card has a marker in its id and name, so a leak shows up in the view text:
# PHAND = Preparedness hand, PDRAW = its deck, DHAND = Disaster hand, DDRAW and DEVO = Disaster decks.
func view_fixture() -> void:
	fixture()
	# A threat in lane 1, played on a Disaster turn, so both lanes hold a public card.
	game._set_phase(game.Phase.ENEMY)
	game.tension = 5
	game.disaster_actions.begin_turn()
	var lane_threat := threat("t_lane")
	game.enemy_hand.assign([lane_threat])
	await game.disaster_actions.play_base(lane_threat, game._threat_slots()[0])
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.add_card_to_hand(unit("LANE_ally", 1))
	expect(game.preparedness_actions.play_card(0, 2).ok, "view: ally played into lane 3")
	game.add_card_to_hand(unit("PHAND_a", 1))
	game.add_card_to_hand(unit("PHAND_dear", 9))
	game.add_card_to_hand({"id": "PHAND_tool", "name": "PHAND Tool", "type": "response", "element": "evac",
		"cost": 0, "effect": "draw", "utility": true})
	game.deck.assign([unit("PDRAW_a", 1), unit("PDRAW_b", 1)])
	game.enemy_hand.assign([threat("DHAND_a"), threat("DHAND_b"), threat("DHAND_c")])
	game.enemy_deck.assign([threat("DDRAW_a")])
	game.enemy_evolution_deck.assign([threat("DEVO_a"), threat("DEVO_b")])


func check_views() -> void:
	await view_fixture()
	var prep: Dictionary = LanView.build(game, "preparedness")
	var text := JSON.stringify(prep)
	expect(BattleState.is_plain_data(prep), "prep view is plain data")
	for marker in ["DHAND", "DDRAW", "DEVO", "PDRAW"]:
		expect(not text.contains(marker), "prep view hides " + marker)
	for key in ["rng_state", "run_rng_state", "pending_choice", "plans", "battle_log", "zones", "disaster_hand"]:
		expect(not prep.has(key), "prep view drops " + key)
	expect(prep.side == "preparedness" and prep.is_prep_turn, "prep view: Preparedness turn")
	expect(prep.prep_hand.size() == 3, "prep view keeps the Preparedness hand")
	var names: Array = prep.prep_hand.map(func(id: String) -> String: return prep.cards[id].definition.id)
	expect(names == ["PHAND_a", "PHAND_dear", "PHAND_tool"], "prep view: hand in order")
	expect(prep.counts.disaster_hand == 3 and prep.counts.disaster_draw == 1, "prep view counts the Disaster hand")
	expect(prep.counts.disaster_evolution == 2 and prep.counts.response_draw == 2, "prep view counts the decks")
	expect(prep.energy == 2 and prep.energy_cap == 3 and prep.plan_tokens == 2, "prep view: energy and tokens")
	expect(prep.sides.response.hp == 20 and prep.sides.disaster.hp == 20, "prep view: both HPs")
	expect(prep.cards[prep.lanes.disaster[0]].definition.id == "t_lane", "prep view: threat in lane 1")
	expect(prep.cards[prep.lanes.response[2]].definition.id == "LANE_ally", "prep view: ally in lane 3")
	expect(prep.cards.size() == 5, "prep view keeps only hand and lane cards")
	check_prep_hints(prep)
	check_disaster_view()
	game._set_phase(game.Phase.ENEMY)
	var off_turn: Dictionary = LanView.build(game, "preparedness")
	expect(not off_turn.is_prep_turn, "prep view: not the Preparedness turn")
	expect(off_turn.hints.all(func(hint: Dictionary) -> bool: return not hint.can_play), "prep view: no play off turn")
	expect(off_turn.tactics.all(func(t: Dictionary) -> bool: return not t.available), "prep view: no tactic off turn")
	game._set_phase(game.Phase.PLAYER_PLAY)


# The hints must match what preparedness_actions offers.
func check_prep_hints(prep: Dictionary) -> void:
	var actions: RefCounted = game.preparedness_actions
	var hints: Array = prep.hints
	expect(hints.size() == 3, "prep hint: one per hand card")
	expect(hints[0].can_play and hints[0].lanes == [0, 1, 3], "prep hint: unit may go to the free lanes")
	expect(hints[0].lanes == actions.legal_lanes(0) and hints[0].problem == "", "prep hint: same as legal_lanes")
	expect(not hints[1].can_play and hints[1].problem == "no_energy", "prep hint: too dear")
	expect(not hints[2].can_play and hints[2].problem == "not_supported", "prep hint: utility not over LAN yet")
	var ids: Array = prep.tactics.map(func(t: Dictionary) -> String: return t.id)
	expect(ids == ["brace", "coordinate", "medicine"], "prep hint: one per unlocked tactic")
	expect(prep.tactics[0].available and prep.tactics[0].lanes == [2], "prep hint: Brace on the ally in lane 3")
	expect(prep.tactics[0].name == "Brace" and prep.tactics[0].cost == 1, "prep hint: tactic name and cost")
	expect(prep.armed == "", "prep view: nothing armed")


# The Disaster view of the same board never shows the Preparedness hand or deck.
func check_disaster_view() -> void:
	var view: Dictionary = LanView.build(game, "disaster")
	var text := JSON.stringify(view)
	for marker in ["PHAND_a", "PHAND_dear", "PHAND_tool", "PDRAW", "DDRAW", "DEVO"]:
		expect(not text.contains(marker), "disaster view hides " + marker)
	expect(not view.has("prep_hand") and view.disaster_hand.size() == 3, "disaster view keeps its own hand")
	expect(view.counts.response_hand == 3, "disaster view counts the Preparedness hand")
	expect(JSON.stringify(LanView.build(game)) == text, "build(game) is still the Disaster view")


# --- D2-c: panel ---

func check_panel() -> void:
	var prep: Dictionary = LanView.build(game, "preparedness")
	var panel: Control = LanPrepPanel.new()
	root.add_child(panel)
	panel.show_view(prep)
	await process_frame
	expect(panel.hand_row.get_child_count() == 3, "panel: 3 hand buttons")
	expect(panel.tactic_row.get_child_count() == 3, "panel: 3 tactic buttons")
	expect(panel.response_row.get_child_count() == 4 and panel.disaster_row.get_child_count() == 4, "panel: lanes")
	expect(enabled_lanes(panel).is_empty(), "panel: no lane lit before a pick")
	expect(panel.hand_row.get_child(1).disabled and panel.hand_row.get_child(2).disabled, "panel: bad cards off")
	expect(not panel.end_button.disabled, "panel: End Turn on the Preparedness turn")
	panel.hand_row.get_child(0).pressed.emit()
	await process_frame
	expect(enabled_lanes(panel) == [0, 1, 3], "panel: unit lights the free lanes")
	panel.tactic_row.get_child(0).pressed.emit()
	await process_frame
	expect(enabled_lanes(panel) == [2], "panel: Brace lights the ally lane")
	panel.show_reject("busy")
	expect(panel.reject_label.text == "Refused: busy", "panel shows the reject reason")
	panel.show_match_over("disaster")
	expect(panel.back_button.visible and panel.end_button.disabled, "panel: match over shows Back to title")
	panel.queue_free()
	await process_frame


func enabled_lanes(panel: Control) -> Array:
	var lanes: Array = []
	for lane in panel.response_row.get_child_count():
		if not panel.response_row.get_child(lane).disabled:
			lanes.append(lane)
	return lanes


# --- D2-c: messages over loopback ---

# Two subtrees, each with its own multiplayer API.
func make_side(side_name: String) -> Node:
	var holder := Node.new()
	holder.name = side_name
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var session: Node = LanSession.new()
	session.name = "LanSession"
	holder.add_child(session)
	return session


func setup_sides() -> void:
	host = make_side("Host")
	client = make_side("Client")
	client.joined_host.connect(func() -> void: client_joined = true)
	client.host_lost.connect(func() -> void: client_lost = true)
	host.action_done.connect(func(result: Dictionary) -> void: host_results.append(result))
	client.event_received.connect(on_client_event)


func on_client_event(kind: String, data: Dictionary) -> void:
	if kind == "reject":
		client_rejects.append(data.reason)


func check_connect() -> void:
	host.game = game
	expect(host.host_game(TEST_PORT) == OK, "host listens")
	expect(client.join_game("127.0.0.1", TEST_PORT) == OK, "client starts joining")
	expect(await wait_until(func() -> bool: return client_joined and host.disaster_peer != 0), "client joins")
	var id: int = host.disaster_peer
	host.seat_client("preparedness")
	expect(host.prep_peer == id and host.disaster_peer == 0, "the client now plays Preparedness")
	expect(host.seat_of(id) == "preparedness" and host.seat_of(0) == "", "seat_of the client and of a local call")


# Send one message from the client and wait until the host has handled it. Returns {ok, reason}.
func send(msg) -> Dictionary:
	var before := host_results.size()
	client.request_action(msg)
	if not await wait_until(func() -> bool: return host_results.size() > before):
		return {"ok": false, "reason": "timeout"}
	return host_results[before]


func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card: Node) -> String: return card.card_data.id)


func card_id_in(lane: int) -> String:
	var card = game._get_card_in_slot(game._response_slots()[lane])
	return "" if card == null else str(card.card_data.id)


func check_messages() -> void:
	fixture()
	game.set_seats("remote", "local")
	game.add_card_to_hand(unit("m_a", 1))
	game.add_card_to_hand(unit("m_b", 1))
	game.add_card_to_hand(unit("m_dear", 9))
	game.enemy_hand.assign([threat("DHAND_m")])
	game._set_phase(game.Phase.ENEMY)
	var result: Dictionary = await send({"kind": "play", "hand": 0, "lane": 0})
	expect(result.reason == "not_prep_turn", "msg: play on the Disaster turn refused")
	game._set_phase(game.Phase.PLAYER_PLAY)
	await check_bad_messages()
	game.board_input.action = {"kind": "test"}
	result = await send({"kind": "play", "hand": 0, "lane": 0})
	expect(result.reason == "busy", "msg: play refused while the host has a pick open")
	game.board_input.clear()
	result = await send({"kind": "play", "hand": 0, "lane": 1})
	expect(result.ok and card_id_in(1) == "m_a", "msg: unit played into lane 2")
	expect(game.preparedness == 2 and hand_ids() == ["m_b", "m_dear"], "msg: energy paid, hand shorter")
	result = await send({"kind": "play", "hand": 0, "lane": 1})
	expect(result.reason == "lane_full", "msg: full lane refused")
	result = await send({"kind": "tactic", "id": "brace", "lane": 1})
	expect(result.ok and game.plans.armed.get("kind", "") == "brace", "msg: Brace armed on lane 2")
	expect(await wait_until(func() -> bool: return client.last_view.get("armed", "") == "brace"),
		"msg: client view shows Brace armed")
	var text := JSON.stringify(client.last_view)
	expect(client.last_view.side == "preparedness" and not text.contains("DHAND"), "msg: client view hides DHAND")
	await check_spoofed_sender()


func check_bad_messages() -> void:
	# Legacy fixture: LAN utilities off, so a utility message is not supported.
	game.lan_prep_utilities_override = false
	var cases: Array = [
		[5, "bad_message"],
		[{"kind": "fly"}, "bad_message"],
		[{"kind": "base", "hand": 0, "lane": 0}, "bad_message"],
		[{"kind": "play", "hand": 99, "lane": 0}, "bad_hand"],
		[{"kind": "play", "hand": "0", "lane": 0}, "bad_hand"],
		[{"kind": "play", "hand": 0.0, "lane": 0}, "bad_hand"],
		[{"kind": "play", "hand": 0, "lane": 4}, "bad_lane"],
		[{"kind": "play", "hand": 0}, "bad_lane"],
		[{"kind": "play", "hand": 2, "lane": 0}, "no_energy"],
		[{"kind": "tactic", "id": "nope", "lane": 0}, "bad_tactic"],
		[{"kind": "tactic", "id": "brace", "lane": 0}, "tactic_unavailable"],
		[{"kind": "utility", "hand": 0, "target": -1}, "not_supported"],
	]
	var rejects_before := client_rejects.size()
	for case in cases:
		var result: Dictionary = await send(case[0])
		expect(not result.ok and result.reason == case[1],
			"msg: %s refused as %s (got %s)" % [JSON.stringify(case[0]), case[1], result.reason])
	expect(await wait_until(func() -> bool: return client_rejects.size() == rejects_before + cases.size()),
		"msg: client hears every refusal")
	expect(hand_ids() == ["m_a", "m_b", "m_dear"] and game.preparedness == 3, "msg: bad messages changed nothing")


func check_spoofed_sender() -> void:
	var real_peer: int = host.prep_peer
	host.prep_peer = real_peer + 1000
	var result: Dictionary = await send({"kind": "end"})
	expect(result.reason == "not_prep_peer", "msg: a client that is not the Preparedness seat is refused")
	host.prep_peer = real_peer
	var before := host_results.size()
	host.send_action({"kind": "end"})
	expect(await wait_until(func() -> bool: return host_results.size() > before), "msg: local call answered")
	expect(host_results[before].reason == "not_prep_peer", "msg: a local call is refused")
	expect(game.phase == game.Phase.PLAYER_PLAY, "msg: refused senders did not end the turn")


# --- D2-c: real mouse clicks on the panel, then a whole round ---

func check_real_clicks() -> void:
	fixture()
	# A plain battle round, so the match-end code of Versus is not needed.
	game.encounter_kind = "battle"
	game.set_seats("remote", "local")
	game.add_card_to_hand(unit("k_unit", 1))
	# The client screen has no host board, so nothing may sit above the panel: give it the top layer.
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var panel: Control = LanPrepPanel.new()
	layer.add_child(panel)
	client.attach_prep_panel(panel)
	host.send_view()
	expect(await wait_until(func() -> bool: return client.last_view.get("prep_hand", []).size() == 1),
		"click: client has the one-card hand")
	await process_frame
	await click(panel.hand_row.get_child(0))
	expect(client.picked_hand == 0, "click: the hand card is picked")
	var answered := host_results.size()
	await click(panel.response_row.get_child(2))
	expect(await wait_until(func() -> bool: return host_results.size() > answered), "click: host answered the play")
	expect(card_id_in(2) == "k_unit", "click: unit played in lane 3")
	expect(await wait_until(func() -> bool: return client.last_view.prep_hand.is_empty()), "click: view updated")
	await process_frame
	await click(panel.tactic_row.get_child(0))
	expect(client.picked_tactic == "brace", "click: Brace is picked")
	answered = host_results.size()
	await click(panel.response_row.get_child(2))
	expect(await wait_until(func() -> bool: return host_results.size() > answered), "click: host answered Brace")
	expect(game.plans.armed.get("kind", "") == "brace", "click: Brace armed on lane 3")
	await process_frame
	var start_turn: int = game.turn
	await click(panel.end_button)
	expect(await wait_until(func() -> bool: return game.phase != game.Phase.PLAYER_PLAY), "click: End started the round")
	var next_turn := func() -> bool: return game.turn > start_turn and game.phase in prep_phases
	var frames := 0
	while frames < MAX_FRAMES and not next_turn.call() and game.phase != game.Phase.GAME_OVER:
		frames += 1
		await process_frame
	# The bare battle may end right after the round (no Disaster deck), as in lan_seats_smoke.
	expect(game.turn == start_turn + 1, "click: the round ended and the next turn began")
	expect(await wait_until(func() -> bool: return client.last_view.round == start_turn + 1),
		"click: client view follows the next round")
	layer.queue_free()
	await process_frame


func check_client_leaves() -> void:
	client.close()
	expect(await wait_until(func() -> bool: return host.prep_peer == 0), "leave: host frees the Preparedness seat")


# A real mouse click: move the mouse there first, then press and release on the middle of the control.
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
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame
