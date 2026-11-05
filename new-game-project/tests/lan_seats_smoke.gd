extends SceneTree
## LAN Part D2-a: Preparedness actions in one checked place (scripts/preparedness_actions.gd),
## and seats as data (seat_prep, seat_disaster). Hot-seat keeps both seats local.
## No network here: the checks call the actions the way the LAN host will.

const MAX_FRAMES := 3000

var prep_phases: Array = []  # set in run(), the game enum is not known before

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
	prep_phases = [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]
	game.presentation.automated_choice = 0
	await process_frame
	check_seat_defaults()
	check_play_refusals()
	check_play_ok()
	check_busy()
	check_tactics()
	check_local_brace()
	check_remote_seat_guards()
	await check_end_turn()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_seats_smoke (%d checks)" % checks)
	quit(0)


# A Preparedness play phase with energy, Plan tokens and Brace, Coordinate and Medicine unlocked.
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


func unit(id: String, cost: int) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": cost,
		"attack": 1, "health": 30}


func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card: Node) -> String: return card.card_data.id)


func check_seat_defaults() -> void:
	expect(game.seat_prep == "local" and game.seat_disaster == "local", "seats start local")
	expect(not game.lan_remote_prep and not game.lan_remote_disaster, "no remote flags at start")
	game.set_seats("remote", "local")
	expect(game.lan_remote_prep and not game.lan_remote_disaster, "remote Preparedness seat sets its flag")
	game.set_seats("local", "remote")
	expect(not game.lan_remote_prep and game.lan_remote_disaster, "remote Disaster seat sets its flag")
	game.set_seats("local", "local")
	expect(not game.lan_remote_prep and not game.lan_remote_disaster, "both local again")


func check_play_refusals() -> void:
	fixture()
	var actions: RefCounted = game.preparedness_actions
	game.add_card_to_hand(unit("u_cheap", 1))
	game.add_card_to_hand(unit("u_dear", 9))
	game.add_card_to_hand({"id": "u_tool", "name": "Tool", "type": "response", "element": "evac", "cost": 0,
		"effect": "draw", "utility": true})
	game._set_phase(game.Phase.ENEMY)
	expect(actions.play_card(0, 0).reason == "not_prep_turn", "play refused on the Disaster turn")
	game._set_phase(game.Phase.PLAYER_PLAY)
	for bad in [-1, 3, 1.0, "0", null]:
		expect(actions.play_card(bad, 0).reason == "bad_hand", "bad hand index %s refused" % str(bad))
	for bad in [-1, 4, 0.0, "1"]:
		expect(actions.play_card(0, bad).reason == "bad_lane", "bad lane %s refused" % str(bad))
	expect(actions.play_card(1, 0).reason == "no_energy", "too dear refused")
	expect(actions.play_card(2, 0).reason == "not_supported", "utility card not sent over LAN yet")
	expect(actions.use_utility(2, -1).reason == "not_supported", "use_utility not supported yet")
	expect(hand_ids() == ["u_cheap", "u_dear", "u_tool"] and game.preparedness == 3, "refusals change nothing")
	expect(actions.legal_lanes(0) == [0, 1, 2, 3], "all empty lanes are legal")
	expect(actions.legal_lanes(1).is_empty() and actions.legal_lanes(2).is_empty(), "no lanes for bad cards")


func check_play_ok() -> void:
	var actions: RefCounted = game.preparedness_actions
	var result: Dictionary = actions.play_card(0, 2)
	expect(result.ok and result.reason == "", "cheap unit played into lane 2")
	var placed: Node = game._get_card_in_slot(game._response_slots()[2])
	expect(placed != null and placed.card_data.id == "u_cheap", "the unit sits in lane 2")
	expect(game.preparedness == 2 and hand_ids() == ["u_dear", "u_tool"], "energy paid, card left the hand")
	game.add_card_to_hand(unit("u_next", 1))
	expect(actions.play_card(2, 2).reason == "lane_full", "full lane refused")
	expect(actions.legal_lanes(2) == [0, 1, 3], "full lane is not legal")


func check_busy() -> void:
	var actions: RefCounted = game.preparedness_actions
	game.board_input.action = {"kind": "test"}
	expect(actions.play_card(2, 0).reason == "busy", "play refused while a pick is open")
	expect(actions.use_tactic("brace", 2).reason == "busy", "tactic refused while a pick is open")
	expect(actions.end_turn().reason == "busy", "end refused while a pick is open")
	game.board_input.clear()


func check_tactics() -> void:
	var actions: RefCounted = game.preparedness_actions
	for bad in [7, "nope", "extract_x", null]:
		expect(actions.use_tactic(bad, 2).reason == "bad_tactic", "bad tactic %s refused" % str(bad))
	expect(actions.use_tactic("brace", 0).reason == "bad_lane", "tactic on an empty lane refused")
	expect(actions.use_tactic("brace", 9).reason == "bad_lane", "tactic on a bad lane refused")
	var result: Dictionary = actions.use_tactic("brace", 2)
	expect(result.ok and game.plans.armed.get("kind", "") == "brace", "Brace armed on lane 2")
	expect(actions.use_tactic("coordinate", 2).reason == "tactic_unavailable", "one tactic per round")


func check_local_brace() -> void:
	fixture()
	game.add_card_to_hand(unit("u_local", 1))
	expect(game.preparedness_actions.play_card(0, 1).ok, "local fixture unit played")
	var ally: Node = game._get_card_in_slot(game._response_slots()[1])
	director.select_brace()
	expect(game.board_input.action.get("kind", "") != "", "local Brace opens the ally pick")
	director.arm_brace(ally)
	expect(game.plans.armed.get("kind", "") == "brace" and game.board_input.action.is_empty(),
		"local Brace still arms through the pick")


func check_remote_seat_guards() -> void:
	fixture()
	game.add_card_to_hand(unit("u_remote", 1))
	game.set_seats("remote", "local")
	expect(not game.can_player_act(), "host input cannot act for a remote Preparedness seat")
	expect(not game.try_play_card(game.get_hand_cards()[0]), "host drag cannot play for a remote seat")
	director.select_brace()
	expect(game.board_input.action.is_empty(), "host cannot open a tactic pick for a remote seat")
	game._on_end_turn_pressed()
	expect(game.phase == game.Phase.PLAYER_PLAY, "host End Turn does nothing for a remote seat")
	expect(game.preparedness_actions.play_card(0, 0).ok, "the remote seat still plays by action")
	game.set_seats("local", "local")
	expect(game.can_player_act(), "local seat can act again")


func check_end_turn() -> void:
	fixture()
	var actions: RefCounted = game.preparedness_actions
	game._set_phase(game.Phase.ENEMY)
	expect(actions.end_turn().reason == "not_prep_turn", "end refused on the Disaster turn")
	game._set_phase(game.Phase.PLAYER_PLAY)
	director.modal.show()
	expect(actions.end_turn().reason == "host_busy", "end refused while the host has a window open")
	director.modal.hide()
	# A plain battle round, so the match-end code of Versus is not needed. One unit keeps the board alive.
	game.encounter_kind = "battle"
	game.add_card_to_hand(unit("u_end", 1))
	expect(actions.play_card(0, 0).ok, "end fixture unit played")
	game.set_seats("remote", "local")
	var start_turn: int = game.turn
	expect(actions.end_turn().ok, "remote end accepted")
	expect(game.phase != game.Phase.PLAYER_PLAY, "the round started")
	var frames := 0
	while frames < MAX_FRAMES and not (game.turn > start_turn and game.phase in prep_phases):
		if game.phase == game.Phase.GAME_OVER: break
		frames += 1
		await process_frame
	expect(game.turn == start_turn + 1, "the round ended and the next turn began")
	game.set_seats("local", "local")
