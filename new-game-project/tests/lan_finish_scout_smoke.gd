extends SceneTree
## LAN finish part 1: Scout (Hazard Forecast) over LAN with the utilities flag on.
## The cast sets the local intel_revealed flag, the Preparedness view gets a copy of the Disaster hand,
## Tax names its cards while the reveal lasts, and the Disaster view never sees any of it.
## Flag off: Scout stays not_supported. A local (non-remote) seat keeps the host modal.

const LanActions = preload("res://scripts/lan_actions.gd")
const LanView = preload("res://scripts/lan_view.gd")
const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")

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
	await check_flag_off()
	await check_cast()
	await check_tax()
	await check_lifetime()
	await check_board()
	await check_local_seat()
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_finish_scout_smoke (%d checks)" % checks)
	quit(0)


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 10, "tension_cost": 0}


func spell(id: String, effect: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": "Spell " + id, "type": "response", "element": "evac", "cost": cost,
		"utility": true, "effect": effect}


# A Versus Preparedness play phase on a remote seat, flag on or off.
func fixture(flag: bool, seat: String = "remote") -> void:
	paused = false
	game.clear_battle()
	game.set_seats(seat, "local")
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
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	director.intel_revealed = false
	game._set_phase(game.Phase.PLAYER_PLAY)


func send(msg) -> Dictionary:
	return await LanActions.apply(game, msg, "preparedness")


func check_flag_off() -> void:
	fixture(false)
	game.add_card_to_hand(spell("s_scout", "scout", 2))
	game.enemy_hand.assign([threat("t1")])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(not result.ok and result.reason == "not_supported", "off: scout is not_supported")
	expect(not director.intel_revealed and game.preparedness == 5, "off: nothing revealed, nothing spent")
	var prep: Dictionary = LanView.build(game, "preparedness")
	expect(not prep.has("disaster_hand_revealed") and prep.hints[0].problem == "not_supported",
		"off: the view is as before")


func check_cast() -> void:
	fixture(true)
	game.add_card_to_hand(spell("s_scout", "scout", 2))
	game.enemy_hand.assign([threat("t1"), threat("t2")])
	var prep: Dictionary = LanView.build(game, "preparedness")
	expect(prep.hints[0].can_play and prep.hints[0].utility and prep.hints[0].pick == "", "cast: hint is a plain cast")
	expect(not prep.has("disaster_hand_revealed"), "cast: nothing revealed before the cast")
	var result: Dictionary = await send({"kind": "utility", "hand": 0, "target": -1})
	expect(result.ok, "cast: scout is accepted")
	expect(game.preparedness == 3 and game.get_hand_cards().is_empty(), "cast: paid and left the hand")
	expect(director.intel_revealed, "cast: the local intel flag is set")
	expect(not director.modal.visible, "cast: no host modal")
	prep = LanView.build(game, "preparedness")
	expect(prep.has("disaster_hand_revealed") and prep.disaster_hand_revealed.size() == 2,
		"cast: the view has the hand")
	expect(prep.disaster_hand_revealed[0].id == "t1" and prep.disaster_hand_revealed[1].id == "t2",
		"cast: in hand order")
	expect(prep.counts.disaster_hand == 2, "cast: the count is unchanged")
	var text := JSON.stringify(LanView.build(game, "disaster"))
	expect(not text.contains("disaster_hand_revealed") and not text.contains("intel"),
		"cast: nothing in the Disaster view")
	# The copy is a snapshot: a card played later still shows in it.
	game.enemy_hand.pop_back()
	prep = LanView.build(game, "preparedness")
	expect(prep.disaster_hand_revealed.size() == 2, "cast: the copy keeps the hand as it was")
	# A second Scout takes a fresh copy.
	game.add_card_to_hand(spell("s_scout2", "scout", 2))
	result = await send({"kind": "utility", "hand": 0})
	prep = LanView.build(game, "preparedness")
	expect(result.ok and prep.disaster_hand_revealed.size() == 1, "cast: a second Scout takes a new copy")


func check_tax() -> void:
	# Without Scout the Tax candidates are blind.
	fixture(true)
	game.add_card_to_hand(spell("s_tax", "tax", 1))
	game.enemy_hand.assign([threat("t1"), threat("t2")])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	var open: Dictionary = LanView.build(game, "preparedness").pending_choice
	expect(result.ok and open.stage == "hand" and open.candidates.size() == 2, "tax: two candidates")
	expect(not open.candidates[0].has("card") and not open.candidates[1].has("card"), "tax: blind without Scout")
	expect(not JSON.stringify(LanView.build(game, "preparedness")).contains("Threat t1"), "tax: no name leaks")
	# With Scout the same pick names its cards.
	fixture(true)
	game.add_card_to_hand(spell("s_scout", "scout", 1))
	game.add_card_to_hand(spell("s_tax", "tax", 1))
	game.enemy_hand.assign([threat("t1"), threat("t2")])
	result = await send({"kind": "utility", "hand": 0})
	expect(result.ok, "tax+scout: scout cast")
	result = await send({"kind": "utility", "hand": 0})
	open = LanView.build(game, "preparedness").pending_choice
	expect(result.ok and open.stage == "hand" and open.candidates.size() == 2, "tax+scout: tax opens")
	expect(open.candidates[0].card.id == "t1" and open.candidates[1].card.id == "t2", "tax+scout: cards are named")
	var disaster_text := JSON.stringify(LanView.build(game, "disaster"))
	expect(not disaster_text.contains("pending_choice") and not disaster_text.contains("candidates"),
		"tax+scout: the Disaster view has no choice")
	var pick: Dictionary = await send({"kind": "utility_pick", "encounter": open.encounter, "choice": open.choice,
		"stage": "hand", "handle": 1})
	expect(pick.ok and int(game.enemy_hand[1].tension_cost) == 1 and int(game.enemy_hand[0].tension_cost) == 0,
		"tax+scout: only the named card is taxed")


func check_lifetime() -> void:
	fixture(true)
	game.add_card_to_hand(spell("s_scout", "scout", 1))
	game.enemy_hand.assign([threat("t1")])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok and LanView.build(game, "preparedness").has("disaster_hand_revealed"), "life: revealed")
	# The local rule ends the reveal by clearing intel_revealed.
	director.intel_revealed = false
	expect(not LanView.build(game, "preparedness").has("disaster_hand_revealed"), "life: ends with the local flag")
	# A flag set again by something else does not bring an old copy back in a new encounter.
	director.intel_revealed = true
	game.encounter_serial += 1
	expect(not LanView.build(game, "preparedness").has("disaster_hand_revealed"), "life: ends with the encounter")
	director.intel_revealed = false
	# Flag off again: the override alone decides.
	fixture(true)
	game.add_card_to_hand(spell("s_scout", "scout", 1))
	await send({"kind": "utility", "hand": 0})
	game.lan_prep_utilities_override = false
	expect(not LanView.build(game, "preparedness").has("disaster_hand_revealed"), "life: nothing with the flag off")
	game.lan_prep_utilities_override = true
	game.set_seats("local", "local")
	expect(not game.preparedness_actions.scout_active(), "life: a local seat never counts")


func check_local_seat() -> void:
	# A local Preparedness seat keeps the host modal and the old behaviour.
	fixture(true, "local")
	game.enemy_hand.assign([threat("t1")])
	game.preparedness_actions.scout_hand = []
	game.add_card_to_hand(spell("s_scout", "scout", 1))
	game.apply_simple_utility(game.get_hand_cards()[0], "scout")
	expect(director.intel_revealed and director.modal.visible, "local: the cast opens the modal")
	expect(game.preparedness_actions.scout_hand.is_empty(), "local: no LAN copy is made")
	director.close_modal()
	director.intel_revealed = false


# The 3D Preparedness table lists the forecast after Scout, and shows nothing before.
func check_board() -> void:
	fixture(true)
	game.add_card_to_hand(spell("s_scout", "scout", 1))
	game.enemy_hand.assign([threat("t1"), threat("t2")])
	var session: Node = LanSession.new()
	root.add_child(session)
	var panel := LanPrepPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, director, session, panel, "preparedness", cover)
	session.view_received.emit(LanView.build(game, "preparedness"))
	await process_frame
	await process_frame
	expect(board.find_child("HazardForecast", true, false) == null, "board: no forecast before Scout")
	await send({"kind": "utility", "hand": 0})
	session.view_received.emit(LanView.build(game, "preparedness"))
	await process_frame
	await process_frame
	var box: Node = board.find_child("HazardForecast", true, false)
	expect(box != null, "board: the forecast shows after Scout")
	var names: Array = []
	if box != null:
		for label in box.find_children("*", "Label", true, false): names.append(label.text)
	expect("Threat t1" in names and "Threat t2" in names, "board: the forecast names the Disaster hand")
	director.intel_revealed = false
	session.view_received.emit(LanView.build(game, "preparedness"))
	await process_frame
	await process_frame
	expect(board.find_child("HazardForecast", true, false) == null, "board: the forecast goes with the reveal")
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.visible = true
	await process_frame
