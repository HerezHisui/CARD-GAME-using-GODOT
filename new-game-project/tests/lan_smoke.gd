extends SceneTree
## LAN Part A: a host and a client in one process on 127.0.0.1.
## Each side gets its own SceneMultiplayer, so the RPC path "LanSession" matches on both.
## LAN Part B: the client view hides the Preparedness hand and every deck, and the panel draws it.
## LAN Part C: the client sends Disaster actions over loopback, the host checks and applies them.

const LanSession = preload("res://scripts/lan_session.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
const LanView = preload("res://scripts/lan_view.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")
const BattleState = preload("res://scripts/battle_state.gd")

# Not the game port, so a running game does not clash with the test.
const TEST_PORT := 24689
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var host: Node
var client: Node
var joined_ids: Array = []
var left_ids: Array = []
var client_joined := false
var client_failed := false
var client_lost := false
var host_pongs: Array = []
var client_pongs: Array = []
var host_results: Array = []
var client_views: Array = []
var client_rejects: Array = []
var turns_ended := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	check_flag_default()
	setup_sides()
	await check_connect()
	await check_ping()
	await check_client_leaves()
	await check_host_closes()
	await check_bad_join()
	host.close()
	client.close()
	await check_view_and_panel()
	await check_actions()
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_smoke (%d checks)" % checks)
	quit(0)


func check_flag_default() -> void:
	expect(VersusMatch.LAN_ENABLED == false, "LAN_ENABLED is false by default")


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
	host.peer_joined.connect(func(id: int) -> void: joined_ids.append(id))
	host.peer_left.connect(func(id: int) -> void: left_ids.append(id))
	host.pong_received.connect(func(n: int) -> void: host_pongs.append(n))
	client.joined_host.connect(func() -> void: client_joined = true)
	client.join_failed.connect(func() -> void: client_failed = true)
	client.host_lost.connect(func() -> void: client_lost = true)
	client.pong_received.connect(func(n: int) -> void: client_pongs.append(n))
	expect(host.process_mode == Node.PROCESS_MODE_ALWAYS, "session keeps running while paused")


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


func check_connect() -> void:
	expect(host.host_game(TEST_PORT) == OK, "host listens")
	expect(host.is_host, "host side is host")
	expect(client.join_game("127.0.0.1", TEST_PORT) == OK, "client starts joining")
	expect(await wait_until(func() -> bool: return client_joined), "client joins host")
	expect(await wait_until(func() -> bool: return joined_ids.size() == 1), "host sees one joiner")
	expect(not client.is_host, "client side is not host")
	expect(not client_failed, "join did not fail")


func check_ping() -> void:
	client.send_ping(7)
	expect(await wait_until(func() -> bool: return client_pongs == [7]), "client ping gets pong 7")
	host.send_ping(42)
	expect(await wait_until(func() -> bool: return host_pongs == [42]), "host ping gets pong 42")


func check_client_leaves() -> void:
	client.close()
	expect(not client.is_open(), "client closed")
	expect(await wait_until(func() -> bool: return left_ids.size() == 1), "host sees client leave")
	expect(left_ids == joined_ids, "same id left as joined")


func check_host_closes() -> void:
	client_joined = false
	expect(client.join_game("127.0.0.1", TEST_PORT) == OK, "client joins again")
	expect(await wait_until(func() -> bool: return client_joined), "client rejoined")
	await host.leave()
	expect(not host.is_open(), "host closed")
	expect(await wait_until(func() -> bool: return client_lost), "client sees host go away")
	client.close()


func check_bad_join() -> void:
	# Nothing listens now, so the join must fail (ENet gives up after its own timeout).
	client_failed = false
	expect(client.join_game("127.0.0.1", TEST_PORT) == OK, "join attempt starts with no host")
	# Wait by clock, not frames: headless frames are very fast.
	var start := Time.get_ticks_msec()
	while not client_failed and Time.get_ticks_msec() - start < 60000:
		await process_frame
	expect(client_failed, "join fails when no host listens")
	client.close()


# --- Part B: client view and panel ---

func disaster_card(id: String, cost: int) -> Dictionary:
	return {"id": id, "name": "Test " + id, "type": "disaster", "element": "fire",
		"cost": cost, "attack": 1, "health": 3, "tension_cost": 1}


# Every hidden card has SECRET in its id and name, so a leak shows up in the view text.
func secret_card(id: String) -> Dictionary:
	return {"id": "SECRET_" + id, "name": "SECRET " + id, "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1}


# A Versus board on the Disaster turn: two threats on lanes 0 and 2, three cards in hand,
# two hidden cards in the Preparedness hand and hidden cards in every deck.
func view_fixture(game: Node) -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.run_director.battle_active = true
	game._set_phase(game.Phase.ENEMY)
	game.tension = 5
	game.disaster_actions.begin_turn()
	var first := disaster_card("t_view_a", 0)
	var second := disaster_card("t_view_b", 0)
	var spell := {"id": "t_view_seal", "name": "Test Seal", "type": "disaster", "element": "fire",
		"utility": true, "effect": "seal", "tension_cost": 1}
	game.enemy_hand.assign([first, second, disaster_card("t_view_base", 0), disaster_card("t_view_evo", 2), spell])
	var lanes: Array = game._threat_slots()
	await game.disaster_actions.play_base(first, lanes[0])
	await game.disaster_actions.play_base(second, lanes[2])
	game.add_card_to_hand(secret_card("hand_a"))
	game.add_card_to_hand(secret_card("hand_b"))
	game.deck.assign([secret_card("draw_a"), secret_card("draw_b"), secret_card("draw_c")])
	game.enemy_deck.assign([secret_card("enemy_draw_a"), secret_card("enemy_draw_b")])
	game.enemy_evolution_deck.assign([secret_card("evo_a")])


func check_view_and_panel() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	await view_fixture(game)
	var view: Dictionary = LanView.build(game)
	check_view_hidden(view)
	check_view_public(game, view)
	check_view_hints(game, view)
	await check_panel(view)
	game._set_phase(game.Phase.PLAYER_PLAY)
	var off_turn: Dictionary = LanView.build(game)
	expect(not off_turn.is_disaster_turn, "view: not the Disaster turn")
	expect(off_turn.hints.all(func(hint: Dictionary) -> bool: return not hint.can_use),
		"view: no card usable off turn")
	game.clear_battle()
	game.queue_free()
	await process_frame


func check_view_hidden(view: Dictionary) -> void:
	expect(BattleState.is_plain_data(view), "view is plain data")
	expect(not JSON.stringify(view).contains("SECRET"), "view has no hidden hand or deck card")
	for key in ["rng_state", "run_rng_state", "pending_choice", "plans", "battle_log", "zones"]:
		expect(not view.has(key), "view drops " + key)
	expect(view.counts.response_hand == 2, "view counts the Preparedness hand")
	expect(view.counts.response_draw == 3, "view counts the Preparedness draw pile")
	expect(view.counts.disaster_draw == 2, "view counts the Disaster draw pile")
	expect(view.counts.disaster_evolution == 1, "view counts the evolution deck")


func check_view_public(game: Node, view: Dictionary) -> void:
	expect(view.is_disaster_turn and view.actions_left == 3, "view: Disaster turn, 3 actions left")
	expect(view.sides.disaster.resource == game.tension, "view shows the tension")
	expect(view.sides.response.hp == game.player_hp, "view shows the Preparedness HP")
	expect(view.disaster_hand.size() == 3, "view keeps the Disaster hand")
	var names: Array = view.disaster_hand.map(func(id: String) -> String: return view.cards[id].definition.id)
	expect(names == ["t_view_base", "t_view_evo", "t_view_seal"], "view: Disaster hand in order")
	var lanes: Array = view.lanes.disaster
	expect(lanes[1] == "" and lanes[3] == "", "view: lanes 2 and 4 are empty")
	expect(view.cards[lanes[0]].definition.id == "t_view_a", "view: lane 1 card")
	expect(view.cards[lanes[2]].definition.id == "t_view_b", "view: lane 3 card")
	expect(view.cards.size() == 5, "view keeps only hand and lane cards")


# The hints must match what disaster_actions offers.
func check_view_hints(game: Node, view: Dictionary) -> void:
	var actions: RefCounted = game.disaster_actions
	var hints: Array = view.hints
	expect(hints.size() == 3, "view: one hint per hand card")
	expect(hints[0].lanes == [1, 3] and hints[0].can_use, "hint: base may go to lanes 2 and 4")
	expect(hints[0].lanes.size() == actions.legal_lanes(game.enemy_hand[0]).size(), "hint: same as legal_lanes")
	expect(hints[1].sacrifices == [0, 2] and hints[1].can_use, "hint: evolution may eat lanes 1 and 3")
	expect(hints[1].lanes.is_empty(), "hint: evolution has no free lane to play on")
	expect(hints[2].needs_target and hints[2].targets == [0, 1], "hint: seal targets both hidden hand cards")
	expect(hints[2].problem == "", "hint: seal has no problem")


func check_panel(view: Dictionary) -> void:
	var panel: Control = LanClientPanel.new()
	root.add_child(panel)
	panel.show_view(view)
	await process_frame
	expect(panel.hand_row.get_child_count() == 3, "panel: 3 hand buttons")
	expect(panel.disaster_row.get_child_count() == 4, "panel: 4 threat lanes")
	expect(panel.response_row.get_child_count() == 4, "panel: 4 response lanes")
	expect(enabled_lanes(panel).is_empty(), "panel: no lane lit before a pick")
	expect(not panel.end_button.disabled, "panel: End Turn on the Disaster turn")
	var picked: Array = []
	panel.hand_pressed.connect(func(index: int) -> void: picked.append(index))
	panel.hand_row.get_child(0).pressed.emit()
	await process_frame
	expect(picked == [0] and enabled_lanes(panel) == [1, 3], "panel: base lights lanes 2 and 4")
	panel.hand_row.get_child(1).pressed.emit()
	await process_frame
	expect(enabled_lanes(panel) == [0, 2], "panel: evolution lights lanes 1 and 3")
	panel.show_reject("busy")
	expect(panel.reject_label.text == "Refused: busy", "panel shows the reject reason")
	panel.queue_free()
	await process_frame


func enabled_lanes(panel: Control) -> Array:
	var lanes: Array = []
	for lane in panel.disaster_row.get_child_count():
		if not panel.disaster_row.get_child(lane).disabled:
			lanes.append(lane)
	return lanes


# --- Part C: Disaster actions over the network ---

func check_actions() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	await connect_for_actions(game)
	actions_fixture(game)
	game.disaster_actions.turn_ended.connect(func() -> void: turns_ended += 1)
	await check_wrong_turn(game)
	await check_bad_messages(game)
	await check_base_and_busy(game)
	await check_evolve(game)
	await check_cast(game)
	await check_spoofed_sender(game)
	await check_end(game)
	await check_real_clicks(game)
	await host.leave()
	client.close()
	game.clear_battle()
	game.queue_free()
	await process_frame


func connect_for_actions(game: Node) -> void:
	host.game = game
	host.action_done.connect(func(result: Dictionary) -> void: host_results.append(result))
	client.view_received.connect(func(view: Dictionary) -> void: client_views.append(view))
	client.event_received.connect(on_client_event)
	client_joined = false
	expect(host.host_game(TEST_PORT) == OK, "C: host listens again")
	expect(client.join_game("127.0.0.1", TEST_PORT) == OK, "C: client joins again")
	expect(await wait_until(func() -> bool: return client_joined and host.disaster_peer != 0),
		"C: the joined client plays the Disaster")


func on_client_event(kind: String, data: Dictionary) -> void:
	if kind == "reject":
		client_rejects.append(data.reason)


# Disaster turn with room for many actions: three bases, one evolution (cost 2) and a seal in hand.
# Two hidden cards in the Preparedness hand for the seal.
func actions_fixture(game: Node) -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.run_director.battle_active = true
	game._set_phase(game.Phase.ENEMY)
	game.tension = 6
	game.disaster_actions.begin_turn()
	game.disaster_actions.action_limit = 10
	var seal := {"id": "c_seal", "name": "Test Seal", "type": "disaster", "element": "fire",
		"utility": true, "effect": "seal", "tension_cost": 1}
	game.enemy_hand.assign([disaster_card("c_a", 0), disaster_card("c_b", 0), disaster_card("c_c", 0),
		disaster_card("c_evo", 2), seal])
	game.add_card_to_hand(secret_card("hand_a"))
	game.add_card_to_hand(secret_card("hand_b"))


# Send one message from the client and wait until the host has handled it. Returns {ok, reason}.
func send(msg) -> Dictionary:
	var before := host_results.size()
	client.request_action(msg)
	if not await wait_until(func() -> bool: return host_results.size() > before):
		return {"ok": false, "reason": "timeout"}
	return host_results[before]


# The definition id of the card in a threat lane, or "" when the lane is empty.
func card_id_in(game: Node, lane: int) -> String:
	var card = game._get_card_in_slot(game._threat_slots()[lane])
	return "" if card == null else str(card.card_data.id)


func hand_ids(game: Node) -> Array:
	return game.enemy_hand.map(func(definition: Dictionary) -> String: return definition.id)


func check_wrong_turn(game: Node) -> void:
	game._set_phase(game.Phase.PLAYER_PLAY)
	var result: Dictionary = await send({"kind": "base", "hand": 0, "lane": 0})
	expect(result.reason == "not_disaster_turn", "C: action on the wrong turn refused")
	expect(await wait_until(func() -> bool: return client_rejects.has("not_disaster_turn")),
		"C: client hears the refusal")
	game._set_phase(game.Phase.ENEMY)
	expect(card_id_in(game, 0) == "" and game.enemy_hand.size() == 5, "C: wrong turn changed nothing")


func check_bad_messages(game: Node) -> void:
	var cases: Array = [
		[5, "bad_message"],
		[{"kind": "fly"}, "bad_message"],
		[{"hand": 0, "lane": 0}, "bad_message"],
		[{"kind": "base", "hand": 99, "lane": 0}, "bad_hand"],
		[{"kind": "base", "hand": -1, "lane": 0}, "bad_hand"],
		[{"kind": "base", "hand": "0", "lane": 0}, "bad_hand"],
		[{"kind": "base", "hand": 0.0, "lane": 0}, "bad_hand"],
		[{"kind": "base", "hand": 0, "lane": 4}, "bad_lane"],
		[{"kind": "base", "hand": 0}, "bad_lane"],
		[{"kind": "base", "hand": 3, "lane": 0}, "not_base"],
		[{"kind": "evolve", "hand": 3, "lane": 0, "sacrifices": "0,1"}, "bad_sacrifice"],
		[{"kind": "evolve", "hand": 3, "lane": 0, "sacrifices": [0, 1]}, "bad_sacrifice"],
		[{"kind": "evolve", "hand": 3, "lane": 0, "sacrifices": [7]}, "bad_sacrifice"],
		[{"kind": "cast", "hand": 4, "target": 9}, "bad_target"],
		[{"kind": "cast", "hand": 4, "target": "0"}, "bad_target"],
		[{"kind": "cast", "hand": 4, "target": -1}, "bad_target"],
	]
	var rejects_before := client_rejects.size()
	for case in cases:
		var result: Dictionary = await send(case[0])
		expect(not result.ok and result.reason == case[1],
			"C: %s refused as %s (got %s)" % [JSON.stringify(case[0]), case[1], result.reason])
	expect(await wait_until(func() -> bool: return client_rejects.size() == rejects_before + cases.size()),
		"C: client hears every refusal")
	expect(game.enemy_hand.size() == 5 and game.disaster_actions.actions_used == 0, "C: bad messages used nothing")
	for lane in 4:
		expect(card_id_in(game, lane) == "", "C: lane %d still empty" % (lane + 1))


func check_base_and_busy(game: Node) -> void:
	var result: Dictionary = await send({"kind": "base", "hand": 0, "lane": 1})
	expect(result.ok, "C: base played over the network")
	expect(card_id_in(game, 1) == "c_a", "C: base is in lane 2")
	# Two quick messages: the second arrives while the first still plays its animation.
	var before := host_results.size()
	client.request_action({"kind": "base", "hand": 0, "lane": 0})
	client.request_action({"kind": "base", "hand": 1, "lane": 2})
	expect(await wait_until(func() -> bool: return host_results.size() >= before + 2), "C: both quick actions answered")
	var reasons: Array = host_results.slice(before).map(func(r: Dictionary) -> String: return r.reason)
	expect(reasons.has("busy") and reasons.has(""), "C: the second quick action is refused as busy")
	expect(card_id_in(game, 0) == "c_b" and card_id_in(game, 2) == "", "C: only the first quick action played")
	expect(hand_ids(game) == ["c_c", "c_evo", "c_seal"], "C: hand after two bases")


func check_evolve(game: Node) -> void:
	var result: Dictionary = await send({"kind": "evolve", "hand": 1, "lane": 2, "sacrifices": [0, 1]})
	expect(result.reason == "bad_slot", "C: evolution outside its sacrifice lanes refused")
	result = await send({"kind": "evolve", "hand": 1, "lane": 0, "sacrifices": [0, 0]})
	expect(result.reason == "bad_sacrifice", "C: the same sacrifice twice refused")
	result = await send({"kind": "evolve", "hand": 1, "lane": 0, "sacrifices": [0, 1]})
	expect(result.ok, "C: evolution played over the network")
	expect(card_id_in(game, 0) == "c_evo" and card_id_in(game, 1) == "", "C: evolution took lane 1, lane 2 freed")
	expect(hand_ids(game) == ["c_c", "c_seal"], "C: hand after the evolution")


func check_cast(game: Node) -> void:
	var target_data: Dictionary = game.get_hand_cards()[1].card_data
	var result: Dictionary = await send({"kind": "cast", "hand": 1, "target": 1})
	expect(result.ok, "C: seal cast on a blind pick")
	expect(game.is_sealed(target_data), "C: the picked Preparedness card is sealed")
	expect(hand_ids(game) == ["c_c"], "C: hand after the seal")


func check_spoofed_sender(game: Node) -> void:
	var real_peer: int = host.disaster_peer
	host.disaster_peer = real_peer + 1000
	var result: Dictionary = await send({"kind": "end", "sender": 1})
	expect(result.reason == "not_disaster_peer", "C: a client that is not the Disaster is refused")
	host.disaster_peer = real_peer
	# A call on the host itself has no network sender. It must not count as the Disaster.
	var before := host_results.size()
	host.send_action({"kind": "end"})
	expect(await wait_until(func() -> bool: return host_results.size() > before), "C: local call answered")
	expect(host_results[before].reason == "not_disaster_peer", "C: a local call is refused")
	expect(turns_ended == 0 and game.phase == game.Phase.ENEMY, "C: refused senders did not end the turn")
	# A sender field in the message changes nothing: the host uses the network id.
	result = await send({"kind": "base", "hand": 0, "lane": 3, "sender": 1, "peer": 1})
	expect(result.ok and card_id_in(game, 3) == "c_c", "C: a sender field in the message is ignored")


func check_end(game: Node) -> void:
	var result: Dictionary = await send({"kind": "end"})
	expect(result.ok and turns_ended == 1, "C: end turn ended the Disaster turn once")
	# The client view follows the board: lanes 1 and 4 full, empty hand.
	expect(await wait_until(func() -> bool: return client.last_view.get("disaster_hand", [0]).is_empty()),
		"C: client view has the empty hand")
	var lanes: Array = client.last_view.lanes.disaster
	expect(lanes[0] != "" and lanes[1] == "" and lanes[2] == "" and lanes[3] != "", "C: client view lanes")
	expect(not JSON.stringify(client.last_view).contains("SECRET"), "C: client view still hides the hand")


# Real mouse clicks on the client panel during a real Disaster turn (_enemy_turn waits for End).
func check_real_clicks(game: Node) -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.lan_remote_disaster = true
	game.run_director.battle_active = true
	game.tension = 5
	game.enemy_deck.clear()
	game.enemy_evolution_deck.clear()
	game.enemy_hand.assign([disaster_card("k_base", 0)])
	# The client screen has no host board, so nothing may sit above the panel: give it the top layer.
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var panel: Control = LanClientPanel.new()
	layer.add_child(panel)
	client.attach_panel(panel)
	var views_before := client_views.size()
	game._enemy_turn()
	expect(await wait_until(func() -> bool: return game.disaster_waiting), "click: Disaster turn waits")
	expect(await wait_until(func() -> bool: return client_views.size() > views_before), "click: client gets a view")
	expect(client.last_view.is_disaster_turn, "click: the view says it is the Disaster turn")
	for i in 3:
		await process_frame
	expect(not game.disaster_seat_on, "click: no Disaster seat on the host")
	expect(not game.run_director.disaster_panel.visible, "click: no Disaster panel on the host")
	expect(not game.run_director.privacy_screen.visible, "click: no privacy cover on the host")
	await click(panel.hand_row.get_child(0))
	expect(client.picked_hand == 0, "click: the hand card is picked")
	var answered := host_results.size()
	await click(panel.disaster_row.get_child(2))
	# Wait for the host's answer: End during the base animation is refused as busy.
	expect(await wait_until(func() -> bool: return host_results.size() > answered), "click: host answered the base")
	expect(card_id_in(game, 2) == "k_base", "click: base played in lane 3")
	expect(await wait_until(func() -> bool: return client.last_view.disaster_hand.is_empty()), "click: view updated")
	for i in 3:
		await process_frame
	await click(panel.end_button)
	expect(await wait_until(func() -> bool: return not game.disaster_waiting), "click: End Turn ended the turn")
	layer.queue_free()
	game.lan_remote_disaster = false
	game.disaster_is_human = false
	await process_frame


# A real mouse click: press and release on the middle of the control.
func click(control: Control) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = control.get_global_rect().get_center()
	press.global_position = press.position
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame
