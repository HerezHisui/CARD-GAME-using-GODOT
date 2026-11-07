extends SceneTree
## LAN_PREP_UTILITIES part 2: single-pick utilities (Rally, Cleanse, Seal, Move) and Emergency Extraction.
## The host opens a pending choice. A pick names a legal handle of the open stage. Nothing is paid before the
## last pick works. Cancel, stale, forged, duplicate and wrong-stage messages change nothing.

const LanActions = preload("res://scripts/lan_actions.gd")
const LanView = preload("res://scripts/lan_view.gd")

var failures := 0
var checks := 0
var game: Node
var director: Node


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
	await check_ally_picks()
	await check_blocked_while_pending()
	await check_forged_and_stale()
	await check_cancel()
	await check_seal()
	await check_move()
	await check_extraction()
	await check_pending_ends()
	await check_flag_off_and_views()
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_utility_picks_smoke (%d checks)" % checks)
	quit(0)


func unit(id: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": cost,
		"attack": 1, "health": 10}


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 10, "tension_cost": 0}


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
	game.plans.unlocked.assign(["brace", "coordinate", "supply", "shelter", "extract"])
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)


func send(msg) -> Dictionary:
	return await LanActions.apply(game, msg, "preparedness")


func choice() -> RefCounted:
	return game.preparedness_actions.utility_choice


# The pick message the client would send for the open choice.
func pick_msg(handle, stage_override = null) -> Dictionary:
	var open: RefCounted = choice()
	return {"kind": "utility_pick", "encounter": open.encounter, "choice": open.choice,
		"stage": open.stage if stage_override == null else stage_override, "handle": handle}


func cancel_msg() -> Dictionary:
	return {"kind": "utility_cancel", "encounter": choice().encounter, "choice": choice().choice}


func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card: Node) -> String: return str(card.card_data.id))


func graveyard_ids() -> Array:
	return game.player_graveyard.map(func(entry: Dictionary) -> String: return str(entry.id))


func lane_card(lane: int) -> Node:
	return game._get_card_in_slot(game._response_slots()[lane])


func threat_card(lane: int) -> Node:
	return game._get_card_in_slot(game._threat_slots()[lane])


func nothing_spent(energy: int, hand: Array) -> bool:
	return game.preparedness == energy and hand_ids() == hand and game.player_graveyard.is_empty()


func check_ally_picks() -> void:
	# Rally: opens a choice without paying, then the pick pays once and adds strength.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	put(unit("a2"), game._response_slots()[2])
	var result: Dictionary = await send({"kind": "utility", "hand": 0, "id": "s_rally"})
	expect(result.ok and choice().active(), "rally: begin opens a choice")
	expect(nothing_spent(5, ["s_rally"]), "rally: begin spends nothing")
	var view: Dictionary = LanView.build(game, "preparedness").pending_choice
	expect(view.stage == "ally" and view.handles == [0, 2] and view.effect == "rally", "rally: view stage and handles")
	expect(view.kind == "utility" and view.source == 0 and view.name == "Spell s_rally", "rally: view names the source")
	expect(view.choice == choice().choice and view.encounter == game.encounter_serial, "rally: view carries the ids")
	result = await send(pick_msg(1))
	expect(not result.ok and result.reason == "bad_handle" and choice().active(), "rally: an empty lane is no handle")
	expect(nothing_spent(5, ["s_rally"]), "rally: refused pick spends nothing")
	result = await send(pick_msg(2))
	expect(result.ok and not choice().active(), "rally: pick accepted, choice closed")
	expect(int(lane_card(2).statuses.get("strength", 0)) == 2 and not lane_card(0).statuses.has("strength"),
		"rally: +2 strength on the chosen ally only")
	expect(game.preparedness == 4 and hand_ids().is_empty() and graveyard_ids() == ["s_rally"], "rally: paid once")
	result = await send(pick_msg(2))
	expect(not result.ok and result.reason == "no_choice" and game.preparedness == 4, "rally: a repeated pick is refused")
	expect(LanView.build(game, "preparedness").pending_choice.is_empty(), "rally: view closes the choice")
	# Cleanse: removes bleed. A powered card also heals.
	fixture()
	var cleanse := spell("s_cleanse", "cleanse")
	cleanse.utility_power = 1
	game.add_card_to_hand(cleanse)
	var sick := put(unit("a1"), game._response_slots()[1])
	sick.card_data.health = 4
	sick.statuses["bleed"] = 2
	await send({"kind": "utility", "hand": 0})
	result = await send(pick_msg(1))
	expect(result.ok and not sick.statuses.has("bleed"), "cleanse: bleed removed")
	# Cleanse heals 3 by itself and 2 more per power: 4 + 3 + 2.
	expect(int(sick.card_data.health) == 9 and game.preparedness == 4, "cleanse: heal 3 + power 2, paid once")
	# No ally, no choice.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	result = await send({"kind": "utility", "hand": 0})
	expect(not result.ok and result.reason == "no_target" and not choice().active(), "rally: no ally, no choice")


func check_blocked_while_pending() -> void:
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	game.add_card_to_hand(spell("s_draw", "draw"))
	game.add_card_to_hand(unit("u_plain"))
	put(unit("a0"), game._response_slots()[0])
	game.deck.assign([unit("d1")])
	await send({"kind": "utility", "hand": 0})
	expect(choice().active(), "pending: open")
	var blocked: Array = [
		{"kind": "play", "hand": 2, "lane": 1},
		{"kind": "utility", "hand": 1},
		{"kind": "utility", "hand": 0},
		{"kind": "tactic", "id": "brace", "lane": 0},
		{"kind": "tactic", "id": "shelter"},
		{"kind": "tactic", "id": "extract"},
		{"kind": "end"},
		{"kind": "draw"},
	]
	for msg in blocked:
		var result: Dictionary = await send(msg)
		expect(not result.ok and result.reason in ["choice_pending", "not_draw_phase", "not_remote_prep"],
			"pending: %s is blocked (got %s)" % [JSON.stringify(msg), result.reason])
	expect(game.phase == game.Phase.PLAYER_PLAY and game.plans.tokens == 2 and game.plans.armed.is_empty(),
		"pending: End did not end the turn, no tactic armed")
	expect(nothing_spent(5, ["s_rally", "s_draw", "u_plain"]) and game.deck.size() == 1, "pending: nothing spent")
	var hints: Array = LanView.build(game, "preparedness").hints
	expect(hints.all(func(hint: Dictionary) -> bool: return not hint.can_play), "pending: no hand card is playable")
	expect(LanView.build(game, "preparedness").tactics.all(func(t: Dictionary) -> bool: return not t.available),
		"pending: no tactic is available")
	var first_choice: int = choice().choice
	var result: Dictionary = await send(pick_msg(0))
	expect(result.ok and choice().choice == first_choice, "pending: the pick still works after the blocked tries")


func check_forged_and_stale() -> void:
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	var good := pick_msg(0)
	var bad_fields := good.duplicate()
	bad_fields["extra"] = 1
	var missing := good.duplicate()
	missing.erase("stage")
	var cases: Array = [
		[5, "bad_message"],
		[{"kind": "utility_pick"}, "bad_message"],
		[bad_fields, "bad_message"],
		[missing, "bad_message"],
		[pick_msg("0"), "bad_message"],
		[pick_msg(0.0), "bad_message"],
		[pick_msg(null), "bad_message"],
		[pick_msg(0, 5), "bad_message"],
		[pick_msg(0, "field"), "stale_choice"],
		[pick_msg(0, "destination"), "stale_choice"],
		[pick_msg(7), "bad_handle"],
		[pick_msg(-1), "bad_handle"],
		[{"kind": "utility_pick", "encounter": game.encounter_serial - 1, "choice": choice().choice,
			"stage": "ally", "handle": 0}, "stale_choice"],
		[{"kind": "utility_pick", "encounter": game.encounter_serial, "choice": choice().choice - 1,
			"stage": "ally", "handle": 0}, "stale_choice"],
		[{"kind": "utility_pick", "encounter": game.encounter_serial, "choice": choice().choice + 1,
			"stage": "ally", "handle": 0}, "stale_choice"],
		[{"kind": "utility_pick", "encounter": "x", "choice": 1, "stage": "ally", "handle": 0}, "bad_message"],
		[{"kind": "utility_cancel", "encounter": game.encounter_serial, "choice": choice().choice + 1}, "stale_choice"],
		[{"kind": "utility_cancel"}, "bad_message"],
	]
	for case in cases:
		var result: Dictionary = await send(case[0])
		expect(not result.ok and result.reason == case[1],
			"forged: %s refused as %s (got %s)" % [JSON.stringify(case[0]), case[1], result.reason])
	expect(choice().active() and nothing_spent(5, ["s_rally"]), "forged: the choice is still open, nothing spent")
	expect(not lane_card(0).statuses.has("strength"), "forged: no effect applied")
	# An old pick never reaches a new choice: cancel, begin again, send the old message.
	var old := pick_msg(0)
	await send(cancel_msg())
	await send({"kind": "utility", "hand": 0})
	var result: Dictionary = await send(old)
	expect(not result.ok and result.reason == "stale_choice" and choice().active(), "stale: old pick vs new choice")
	expect(nothing_spent(5, ["s_rally"]), "stale: nothing spent")
	# Wrong seat messages never get here: the same kinds from the Disaster seat are refused by the router.
	result = await LanActions.apply(game, pick_msg(0), "disaster")
	expect(not result.ok and choice().active(), "stale: the Disaster seat cannot pick")
	# A new encounter drops the choice and an old message.
	var before: Dictionary = pick_msg(0)
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	result = await send(before)
	expect(not result.ok and result.reason == "stale_choice", "stale: late message after a new encounter")
	expect(choice().active() and nothing_spent(5, ["s_rally"]), "stale: the new encounter's choice is untouched")


func check_cancel() -> void:
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	var first: int = choice().choice
	var result: Dictionary = await send(cancel_msg())
	expect(result.ok and not choice().active() and nothing_spent(5, ["s_rally"]), "cancel: closes, spends nothing")
	result = await send(cancel_msg())
	expect(not result.ok and result.reason == "no_choice", "cancel: a second cancel is refused")
	result = await send({"kind": "utility", "hand": 0})
	expect(result.ok and choice().choice == first + 1, "cancel: casting again is a new choice, not a reroll")
	result = await send(pick_msg(0))
	expect(result.ok and game.preparedness == 4 and graveyard_ids() == ["s_rally"], "cancel: the later cast pays once")
	# Cancel in the second stage of a two-step pick.
	fixture()
	game.add_card_to_hand(spell("s_move", "move"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	await send(pick_msg(0))
	expect(choice().stage == "destination" and choice().ally_lane == 0, "cancel: move is in its second stage")
	result = await send(cancel_msg())
	expect(result.ok and lane_card(0) != null and nothing_spent(5, ["s_move"]), "cancel: second stage spends nothing")


func check_seal() -> void:
	fixture()
	game.add_card_to_hand(spell("s_seal", "seal", 2))
	put(threat("t1"), game._threat_slots()[1])
	var done := put(threat("t3"), game._threat_slots()[3])
	done.card_data.seal_round = game.turn
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok and choice().stage == "field" and choice().handles == [1], "seal: only an unsealed field card")
	result = await send(pick_msg(3))
	expect(result.reason == "bad_handle" and choice().active(), "seal: an already sealed card is no handle")
	result = await send(pick_msg(0))
	expect(result.reason == "bad_handle", "seal: an empty lane is no handle")
	result = await send(pick_msg(1))
	expect(result.ok and int(threat_card(1).card_data.get("seal_round", -1)) == game.turn, "seal: sealed this round")
	expect(game.preparedness == 3 and graveyard_ids() == ["s_seal"], "seal: paid once")
	# Second player order seals next round.
	fixture()
	game.player_first = false
	game.add_card_to_hand(spell("s_seal", "seal", 2))
	put(threat("t0"), game._threat_slots()[0])
	await send({"kind": "utility", "hand": 0})
	await send(pick_msg(0))
	expect(int(threat_card(0).card_data.get("seal_round", -1)) == game.turn + 1, "seal: second side seals next round")
	# No target, no choice.
	fixture()
	game.add_card_to_hand(spell("s_seal", "seal", 2))
	result = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "no_target" and not choice().active() and nothing_spent(5, ["s_seal"]),
		"seal: no field card, no choice")


func check_move() -> void:
	fixture()
	var mover := spell("s_move", "move")
	mover.move_heal = 2
	game.add_card_to_hand(mover)
	var ally := put(unit("a0"), game._response_slots()[0])
	ally.card_data.health = 5
	var other := put(unit("a1"), game._response_slots()[1])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok and choice().stage == "ally" and choice().handles == [0, 1], "move: first stage picks an ally")
	result = await send(pick_msg(0))
	expect(result.ok and choice().active() and choice().stage == "destination", "move: second stage opens")
	expect(choice().handles == [2, 3] and nothing_spent(5, ["s_move"]), "move: empty lanes only, still nothing paid")
	var view: Dictionary = LanView.build(game, "preparedness").pending_choice
	expect(view.stage == "destination" and view.ally == 0 and view.handles == [2, 3], "move: view restores stage two")
	result = await send(pick_msg(0, "ally"))
	expect(result.reason == "stale_choice", "move: a repeated ally pick is a stale stage")
	result = await send(pick_msg(1))
	expect(result.reason == "bad_handle", "move: an occupied lane is no destination")
	result = await send(pick_msg(3))
	expect(result.ok and not choice().active(), "move: destination accepted")
	expect(lane_card(3) == ally and lane_card(0) == null and lane_card(1) == other, "move: ally now in lane 4")
	expect(int(ally.card_data.health) == 7, "move: move_heal 2 applied")
	expect(game.preparedness == 4 and hand_ids().is_empty() and graveyard_ids() == ["s_move"], "move: paid once")
	result = await send(pick_msg(3))
	expect(result.reason == "no_choice", "move: a repeated destination pick is refused")
	# The ally leaves between the two stages: nothing is paid.
	fixture()
	game.add_card_to_hand(spell("s_move", "move"))
	var doomed := put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	await send(pick_msg(0))
	doomed.current_slot = null
	doomed.queue_free()
	await process_frame
	result = await send(pick_msg(2))
	expect(not result.ok and not choice().active(), "move: ally gone, the pick fails and the choice closes")
	expect(nothing_spent(5, ["s_move"]), "move: ally gone, nothing paid")
	# No empty lane, no choice.
	fixture()
	game.add_card_to_hand(spell("s_move", "move"))
	for lane in 4: put(unit("f%d" % lane), game._response_slots()[lane])
	result = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "lane_full" and not choice().active(), "move: all lanes full, no choice")


func check_extraction() -> void:
	fixture()
	var ally := put(unit("a1"), game._response_slots()[1])
	var result: Dictionary = await send({"kind": "tactic", "id": "extract"})
	expect(result.ok and choice().active() and choice().kind == "tactic", "extract: begin opens a choice")
	expect(game.plans.tokens == 2 and game.plans.armed.is_empty(), "extract: begin spends no token")
	var view: Dictionary = LanView.build(game, "preparedness").pending_choice
	expect(view.kind == "tactic" and view.effect == "extract" and view.source == -1 and view.handles == [1],
		"extract: view shows the ally stage")
	result = await send(pick_msg(1))
	expect(result.ok and choice().stage == "destination" and choice().handles == [0, 2, 3], "extract: destinations")
	expect(game.plans.tokens == 2, "extract: still no token spent")
	result = await send(pick_msg(1))
	expect(result.reason == "bad_handle", "extract: the ally's own lane is no destination")
	result = await send(pick_msg(2))
	expect(result.ok and game.plans.armed.get("kind", "") == "extract", "extract: armed")
	expect(game.plans.tokens == 1 and game.plans.committed_round == game.turn, "extract: one token spent")
	expect(game.plans.armed.targets[0] == ally and game.plans.armed.destination == game._response_slots()[2],
		"extract: ally and destination kept")
	expect(lane_card(1) == ally, "extract: the ally has not moved yet")
	expect(game.plans.try_extract(ally, 99) and lane_card(2) == ally, "extract: a lethal hit moves it to lane 3")
	result = await send(pick_msg(2))
	expect(result.reason == "no_choice", "extract: a repeated pick is refused")
	# Cancel in either stage, no token.
	fixture()
	put(unit("a1"), game._response_slots()[1])
	await send({"kind": "tactic", "id": "extract", "lane": -1})
	await send(pick_msg(1))
	result = await send(cancel_msg())
	expect(result.ok and game.plans.tokens == 2 and game.plans.armed.is_empty(), "extract: cancel spends nothing")
	# Refusals before a choice opens.
	fixture()
	result = await send({"kind": "tactic", "id": "extract"})
	expect(result.reason == "tactic_unavailable" and not choice().active(), "extract: no ally, no choice")
	put(unit("a1"), game._response_slots()[1])
	result = await send({"kind": "tactic", "id": "extract", "lane": 1})
	expect(result.reason == "bad_lane" and not choice().active(), "extract: a lane in the begin message is refused")
	game.plans.tokens = 0
	result = await send({"kind": "tactic", "id": "extract"})
	expect(result.reason == "tactic_unavailable" and not choice().active(), "extract: no token, no choice")
	game.plans.tokens = 2
	for lane in [0, 2, 3]: put(unit("f%d" % lane), game._response_slots()[lane])
	result = await send({"kind": "tactic", "id": "extract"})
	expect(result.reason == "tactic_unavailable" and not choice().active(), "extract: no empty lane, no choice")
	# A token spent elsewhere between the stages: the last pick fails and spends nothing more.
	fixture()
	put(unit("a1"), game._response_slots()[1])
	await send({"kind": "tactic", "id": "extract"})
	await send(pick_msg(1))
	game.plans.tokens = 0
	result = await send(pick_msg(0))
	expect(not result.ok and result.reason == "tactic_unavailable" and game.plans.armed.is_empty(),
		"extract: token gone, the last pick fails")


func check_pending_ends() -> void:
	# The phase leaves play: the choice closes by itself.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	var msg := pick_msg(0)
	game._set_phase(game.Phase.ENEMY)
	expect(not choice().active(), "ends: leaving the play phase closes the choice")
	var result: Dictionary = await send(msg)
	expect(not result.ok and nothing_spent(5, ["s_rally"]), "ends: a late pick spends nothing")
	# The source leaves the hand: the choice closes.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	choice().source.in_hand = false
	expect(not choice().active(), "ends: a source that left the hand closes the choice")
	# Energy or a seal changes before the last pick: refused, closed, nothing paid.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	game.preparedness = 0
	result = await send(pick_msg(0))
	expect(result.reason == "no_energy" and not choice().active(), "ends: energy gone, the pick fails")
	expect(not lane_card(0).statuses.has("strength") and hand_ids() == ["s_rally"], "ends: nothing applied")
	# A reset (disconnect or match end) closes it.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	choice().reset()
	expect(not choice().active() and LanView.build(game, "preparedness").pending_choice.is_empty(),
		"ends: reset closes it")
	# Game over closes it too.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	game._set_phase(game.Phase.GAME_OVER)
	expect(not choice().active(), "ends: game over closes the choice")


func check_flag_off_and_views() -> void:
	fixture(false)
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "not_supported" and not choice().active(), "off: rally is not_supported")
	for msg in [{"kind": "utility_pick", "encounter": 0, "choice": 1, "stage": "ally", "handle": 0},
			{"kind": "utility_cancel", "encounter": 0, "choice": 1}]:
		result = await send(msg)
		expect(result.reason == "bad_message", "off: %s is an unknown message" % msg.kind)
	result = await send({"kind": "tactic", "id": "extract"})
	expect(result.reason == "not_supported", "off: Extraction is not_supported")
	expect(not LanView.build(game, "preparedness").has("pending_choice"), "off: the view has no pending_choice key")
	# The Disaster view never carries it.
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("a0"), game._response_slots()[0])
	await send({"kind": "utility", "hand": 0})
	var text := JSON.stringify(LanView.build(game, "disaster"))
	for word in ["pending_choice", "s_rally", "handles", "utility_pick"]:
		expect(not text.contains(word), "views: the Disaster view hides " + word)
	var prep: Dictionary = LanView.build(game, "preparedness")
	expect(prep.hints[0].utility and prep.hints[0].pick == "ally" and not prep.hints[0].can_play,
		"views: a utility hint names its first stage; it is blocked while open")
