extends SceneTree
## LAN_PREP_UTILITIES part 5: the utility messages over a loopback ENet link (host and client in one process).
## Wrong seat, spoofed sender, forged, stale, repeated, a late message after a new encounter, and a disconnect or a
## reset in every pick stage (lane, second lane, private list, tactic destination). Nothing is paid in any of them.

const LanSession = preload("res://scripts/lan_session.gd")
const LanView = preload("res://scripts/lan_view.gd")

const TEST_PORT := 24742
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var game: Node
var director: Node
var host: Node
var client: Node
var client_joined := false
var client_count := 0
var host_results: Array = []
var client_rejects: Array = []


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
	host = make_side("Host")
	host.action_done.connect(func(result: Dictionary) -> void: host_results.append(result))
	host.game = game
	expect(host.host_game(TEST_PORT) == OK, "host listens")
	await rejoin("disaster")
	await check_wrong_seat()
	host.seat_client("preparedness")
	await check_spoofed_and_forged()
	await check_repeated_and_stale()
	await check_disconnect_in_every_stage()
	await check_resets()
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
	print("PASS: lan_utility_rpc_smoke (%d checks)" % checks)
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


# A fresh client joins and takes the given seat. The old client holder is freed.
func rejoin(seat: String = "preparedness") -> void:
	if client != null and is_instance_valid(client):
		client.close()
		client.get_parent().queue_free()
	client_count += 1
	client = make_side("Client%d" % client_count)
	client_joined = false
	client.joined_host.connect(func() -> void: client_joined = true)
	client.event_received.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "reject": client_rejects.append(data.reason))
	client.join_game("127.0.0.1", TEST_PORT)
	await wait_until(func() -> bool: return client_joined and (host.disaster_peer != 0 or host.prep_peer != 0))
	host.seat_client(seat)


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


# Send one message from the client and wait for the host's answer.
func send(msg) -> Dictionary:
	var before := host_results.size()
	client.request_action(msg)
	if not await wait_until(func() -> bool: return host_results.size() > before):
		return {"ok": false, "reason": "timeout"}
	return host_results[before]


func pick_msg(handle, stage_override = null) -> Dictionary:
	var open: RefCounted = choice()
	return {"kind": "utility_pick", "encounter": open.encounter, "choice": open.choice,
		"stage": open.stage if stage_override == null else stage_override, "handle": handle}


func cancel_msg() -> Dictionary:
	return {"kind": "utility_cancel", "encounter": choice().encounter, "choice": choice().choice}


func unspent(energy: int, hand: Array) -> bool:
	return game.preparedness == energy and hand_ids() == hand and game.player_graveyard.is_empty() \
		and game.plans.tokens == 2 and game.plans.armed.is_empty()


# ------------------------------------------------------------------- seats and senders

func check_wrong_seat() -> void:
	fixture()
	game.add_card_to_hand(spell("s_draw", "draw"))
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	game.deck.assign([unit("d1")])
	# The client holds the Disaster seat. No Preparedness message works from it.
	for msg in [{"kind": "utility", "hand": 0}, {"kind": "utility", "hand": 1},
			{"kind": "tactic", "id": "supply"}, {"kind": "utility_cancel", "encounter": 0, "choice": 1},
			{"kind": "utility_pick", "encounter": 0, "choice": 1, "stage": "ally", "handle": 0}]:
		var result: Dictionary = await send(msg)
		expect(not result.ok and result.reason in ["bad_message", "bad_hand"],
			"seat: the Disaster seat is refused for %s (got %s)" % [msg.kind, result.reason])
	expect(unspent(5, ["s_draw", "s_rally"]) and not choice().active(), "seat: nothing happened")
	host.send_view()
	await wait_until(func() -> bool: return client.last_view.has("disaster_hand"))
	var text := JSON.stringify(client.last_view)
	expect(not text.contains("pending_choice") and not text.contains("s_rally"),
		"seat: the Disaster view over the wire is clean")
	# A Preparedness choice opened on the host is still invisible to the Disaster client.
	choice().begin_utility(game.get_hand_cards()[1], "rally")
	host.send_view()
	await process_frame
	await wait_until(func() -> bool: return client.last_view.has("disaster_hand"))
	text = JSON.stringify(client.last_view)
	for word in ["pending_choice", "handles", "candidates", "s_rally", "utility_pick"]:
		expect(not text.contains(word), "seat: the open choice never reaches the Disaster client: " + word)
	choice().reset()


func check_spoofed_and_forged() -> void:
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	var result: Dictionary = await send({"kind": "utility", "hand": 0, "id": "s_rally"})
	expect(result.ok and choice().active(), "rpc: begin accepted from the Preparedness seat")
	expect(await wait_until(func() -> bool: return client.last_view.get("pending_choice", {}).has("stage")),
		"rpc: the client view carries the choice")
	var open: Dictionary = client.last_view.pending_choice
	expect(open.stage == "ally" and open.handles == [0] and open.choice == choice().choice, "rpc: stage and handles")
	# A sender that is not the Preparedness seat.
	var real_peer: int = host.prep_peer
	host.prep_peer = real_peer + 1000
	result = await send(pick_msg(0))
	expect(result.reason == "not_prep_peer" and choice().active() and game.preparedness == 5,
		"rpc: spoofed sender refused")
	host.prep_peer = real_peer
	# A local call (sender 0) is refused too.
	var before := host_results.size()
	host.send_action(pick_msg(0))
	await wait_until(func() -> bool: return host_results.size() > before)
	expect(host_results[before].reason == "not_prep_peer" and choice().active(), "rpc: a local call is refused")
	# Forged messages over the wire.
	var cases: Array = [
		[7, "bad_message"],
		[{"kind": "utility_pick"}, "bad_message"],
		[{"kind": "utility_pick", "encounter": game.encounter_serial, "choice": choice().choice, "stage": "ally",
			"handle": 0, "extra": true}, "bad_message"],
		[pick_msg(0.0), "bad_message"],
		[pick_msg("0"), "bad_message"],
		[pick_msg(1), "bad_handle"],
		[pick_msg(0, "field"), "stale_choice"],
		[{"kind": "utility_pick", "encounter": game.encounter_serial + 1, "choice": choice().choice,
			"stage": "ally", "handle": 0}, "stale_choice"],
		[{"kind": "utility_cancel", "encounter": game.encounter_serial, "choice": choice().choice - 1}, "stale_choice"],
		[{"kind": "utility", "hand": 0}, "choice_pending"],
		[{"kind": "end"}, "choice_pending"],
	]
	var rejects_before := client_rejects.size()
	for case in cases:
		result = await send(case[0])
		expect(not result.ok and result.reason == case[1],
			"rpc: %s refused as %s (got %s)" % [JSON.stringify(case[0]), case[1], result.reason])
	expect(await wait_until(func() -> bool: return client_rejects.size() == rejects_before + cases.size()),
		"rpc: the client hears every refusal")
	expect(choice().active() and unspent(5, ["s_rally"]), "rpc: the choice survived every forged message")
	result = await send(cancel_msg())
	expect(result.ok and not choice().active() and unspent(5, ["s_rally"]), "rpc: cancel over the wire")
	expect(await wait_until(func() -> bool: return client.last_view.get("pending_choice", {"x": 1}).is_empty()),
		"rpc: the client view drops the choice after the cancel")


func check_repeated_and_stale() -> void:
	# Two picks sent back to back: the first pays, the second finds no choice.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	var msg := pick_msg(0)
	var before := host_results.size()
	client.request_action(msg)
	client.request_action(msg)
	expect(await wait_until(func() -> bool: return host_results.size() >= before + 2), "repeat: both answered")
	expect(host_results[before].ok and host_results[before + 1].reason == "no_choice",
		"repeat: the second pick is no_choice")
	var strength: int = int(lane_card(0).statuses.get("strength", 0))
	expect(game.preparedness == 4 and game.player_graveyard.size() == 1 and strength == 2,
		"repeat: paid once, applied once")
	# A begin sent twice: one choice, the second is blocked.
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor", 2))
	game.add_card_to_hand(spell("s_tutor2", "tutor", 2))
	game.deck.assign([unit("t_a"), unit("t_b")])
	before = host_results.size()
	client.request_action({"kind": "utility", "hand": 0})
	client.request_action({"kind": "utility", "hand": 0})
	await wait_until(func() -> bool: return host_results.size() >= before + 2)
	expect(host_results[before].ok and host_results[before + 1].reason == "choice_pending",
		"repeat: a second begin is blocked")
	var first_choice: int = choice().choice
	var old := pick_msg(0)
	await send(cancel_msg())
	# The old pick must not hit the choice opened next.
	await send({"kind": "utility", "hand": 1})
	expect(choice().active() and choice().choice == first_choice + 1, "stale: a new choice has a new id")
	var result: Dictionary = await send(old)
	expect(result.reason == "stale_choice" and choice().active() and unspent(5, ["s_tutor", "s_tutor2"]),
		"stale: the old pick is refused, the new choice is untouched")
	# A late message after a new encounter.
	var late := pick_msg(0)
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor", 2))
	game.deck.assign([unit("t_a")])
	await send({"kind": "utility", "hand": 0})
	result = await send(late)
	expect(result.reason == "stale_choice" and choice().active(), "stale: a late message after a new encounter")
	expect(game.preparedness == 5 and hand_ids() == ["s_tutor"], "stale: the new encounter is unchanged")
	await send(cancel_msg())


# ------------------------------------------------------------------- disconnect and reset

# The client leaves while the choice is open. The host closes the choice and keeps the cards and tokens.
func leave_and_check(label: String, energy: int, hand: Array) -> void:
	expect(choice().active(), label + ": the choice is open before the client leaves")
	client.close()
	expect(await wait_until(func() -> bool: return host.prep_peer == 0), label + ": the host frees the seat")
	expect(not choice().active(), label + ": the choice closed")
	expect(unspent(energy, hand), label + ": nothing was paid")
	# A new client sees a clean board with no choice.
	await rejoin()
	host.send_view()
	var has_view: bool = await wait_until(func() -> bool: return client.last_view.has("pending_choice"))
	expect(has_view, label + ": the new client has a view")
	expect(client.last_view.pending_choice.is_empty(), label + ": the new client has no stale choice")
	var old_pick := {"kind": "utility_pick", "encounter": 0, "choice": 1, "stage": "ally", "handle": 0}
	var result: Dictionary = await send(old_pick)
	expect(not result.ok and result.reason == "no_choice", label + ": an old pick finds no choice")


func check_disconnect_in_every_stage() -> void:
	# Lane stage.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	await leave_and_check("lane stage", 5, ["s_rally"])
	# Second stage of a move.
	fixture()
	game.add_card_to_hand(spell("s_move", "move"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	await send(pick_msg(0))
	expect(choice().stage == "destination", "move stage: the second stage is open")
	await leave_and_check("move stage", 5, ["s_move"])
	expect(lane_card(0) != null, "move stage: the ally did not move")
	# Private list stage.
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor", 2))
	game.deck.assign([unit("t_a")])
	await send({"kind": "utility", "hand": 0})
	await leave_and_check("list stage", 5, ["s_tutor"])
	expect(game.deck.size() == 1, "list stage: the deck is whole")
	# Blind Tax stage.
	fixture()
	game.add_card_to_hand(spell("s_tax", "tax", 2))
	game.enemy_hand.assign([threat("h_a")])
	await send({"kind": "utility", "hand": 0})
	await leave_and_check("tax stage", 5, ["s_tax"])
	expect(int(game.enemy_hand[0].tension_cost) == 1, "tax stage: the Disaster card kept its cost")
	# Extraction destination stage.
	fixture()
	put(unit("a1"), game._response_slots()[1])
	await send({"kind": "tactic", "id": "extract"})
	await send(pick_msg(1))
	expect(choice().stage == "destination", "extract stage: the destination stage is open")
	await leave_and_check("extract stage", 5, [])


func check_resets() -> void:
	# A new encounter (clear_battle) closes an open choice at once.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	var serial: int = game.encounter_serial
	game.clear_battle()
	expect(game.encounter_serial == serial + 1 and not choice().active(), "reset: a new encounter closes the choice")
	# The match ends while a choice is open.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	var msg := pick_msg(0)
	game._set_phase(game.Phase.GAME_OVER)
	var result: Dictionary = await send(msg)
	expect(not result.ok and game.preparedness == 5 and hand_ids() == ["s_rally"],
		"reset: a pick after the match ended spends nothing")
	# The host closes the session while a choice is open.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	expect(choice().active(), "reset: open before the host closes")
	host.close()
	expect(not choice().active(), "reset: closing the host session closes the choice")
	expect(unspent(5, ["s_rally"]), "reset: nothing was paid")
