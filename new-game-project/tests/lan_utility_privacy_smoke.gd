extends SceneTree
## LAN_PREP_UTILITIES part 3: redaction. A private candidate list (own deck, own graveyard, the Disaster hand)
## goes to the Preparedness view only while its choice is open. The Disaster view carries none of it, before, during or after.

const LanActions = preload("res://scripts/lan_actions.gd")
const LanView = preload("res://scripts/lan_view.gd")
const BattleState = preload("res://scripts/battle_state.gd")

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
	await check_deck_and_graveyard()
	await check_tax()
	await check_lane_choice()
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_utility_privacy_smoke (%d checks)" % checks)
	quit(0)


func unit(id: String) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": 1, "attack": 1, "health": 10}


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 10, "tension_cost": 1}


func spell(id: String, effect: String) -> Dictionary:
	return {"id": id, "name": "Spell " + id, "type": "response", "element": "evac", "cost": 1,
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
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)


func send(msg) -> Dictionary:
	return await LanActions.apply(game, msg, "preparedness")


func choice() -> RefCounted:
	return game.preparedness_actions.utility_choice


func prep_text() -> String:
	return JSON.stringify(LanView.build(game, "preparedness"))


func disaster_text() -> String:
	return JSON.stringify(LanView.build(game, "disaster"))


# None of these words may appear in the Disaster view, whatever the Preparedness side is doing.
const DISASTER_FORBIDDEN := ["pending_choice", "candidates", "utility_pick", "stage", "PDECK", "PGRAVE", "s_tutor",
	"s_recover", "s_tax", "s_rally", "handles"]


func disaster_clean(label: String) -> void:
	var text := disaster_text()
	for word in DISASTER_FORBIDDEN:
		expect(not text.contains(word), "%s: the Disaster view hides %s" % [label, word])
	expect(BattleState.is_plain_data(LanView.build(game, "disaster")), label + ": Disaster view is plain data")


func check_deck_and_graveyard() -> void:
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor"))
	game.add_card_to_hand(spell("s_recover", "recover"))
	game.deck.assign([unit("PDECK_a"), unit("PDECK_b")])
	var dead := put(unit("PGRAVE_a"), game._response_slots()[0])
	game.record_graveyard(dead, "Destroyed")
	dead.current_slot = null
	dead.queue_free()
	await process_frame
	game.enemy_hand.assign([threat("DHAND_a")])
	game.enemy_deck.assign([threat("DDRAW_a")])
	# Before: the Preparedness view has neither list.
	var before := prep_text()
	expect(not before.contains("PDECK") and not before.contains("PGRAVE"), "idle: no deck or graveyard face in the view")
	expect(LanView.build(game, "preparedness").pending_choice.is_empty(), "idle: no pending choice")
	disaster_clean("idle")
	# Tutor open: the candidates are in the Preparedness view, not in the Disaster view.
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok, "tutor: begin")
	var open := prep_text()
	expect(open.contains("PDECK_a") and open.contains("PDECK_b"), "tutor open: the owner sees its deck candidates")
	expect(not open.contains("DHAND") and not open.contains("DDRAW"), "tutor open: no Disaster card in the view")
	disaster_clean("tutor open")
	result = await send({"kind": "utility_cancel", "encounter": choice().encounter, "choice": choice().choice})
	expect(result.ok, "tutor: cancel")
	var after := prep_text()
	expect(not after.contains("PDECK") and not after.contains("PGRAVE"), "tutor closed: the candidates are gone")
	disaster_clean("tutor closed")
	# Recover open.
	result = await send({"kind": "utility", "hand": 1})
	expect(result.ok and choice().stage == "grave", "recover: begin")
	open = prep_text()
	expect(open.contains("PGRAVE_a") and not open.contains("PDECK"), "recover open: only the graveyard is listed")
	disaster_clean("recover open")
	await send({"kind": "utility_pick", "encounter": choice().encounter, "choice": choice().choice,
		"stage": "grave", "handle": 0})
	after = prep_text()
	expect(LanView.build(game, "preparedness").pending_choice.is_empty(), "recover done: no pending choice")
	disaster_clean("recover done")


func check_tax() -> void:
	fixture()
	game.add_card_to_hand(spell("s_tax", "tax"))
	game.enemy_hand.assign([threat("DHAND_a"), threat("DHAND_b")])
	game.enemy_deck.assign([threat("DDRAW_a")])
	game.enemy_evolution_deck.assign([threat("DEVO_a")])
	game.deck.assign([unit("PDECK_a")])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok and choice().stage == "hand", "tax: begin")
	var view: Dictionary = LanView.build(game, "preparedness")
	var text := JSON.stringify(view)
	for word in ["DHAND", "DDRAW", "DEVO", "PDECK"]:
		expect(not text.contains(word), "tax open: the Preparedness view hides " + word)
	expect(view.pending_choice.candidates.size() == 2, "tax open: two blind handles")
	expect(view.pending_choice.candidates.all(func(entry: Dictionary) -> bool: return entry.keys() == ["handle"]),
		"tax open: a candidate is only a handle")
	expect(view.counts.disaster_hand == 2, "tax open: the hand size is the only fact")
	disaster_clean("tax open")
	# The Disaster hand itself still reaches the Disaster view, as always.
	expect(disaster_text().contains("DHAND_a"), "tax open: the Disaster still sees its own hand")


func check_lane_choice() -> void:
	fixture()
	game.add_card_to_hand(spell("s_rally", "rally"))
	put(unit("ally_a"), game._response_slots()[2])
	await send({"kind": "utility", "hand": 0})
	expect(LanView.build(game, "preparedness").pending_choice.handles == [2], "rally open: handles in the owner's view")
	var text := disaster_text()
	for word in ["pending_choice", "handles", "s_rally", "utility_pick"]:
		expect(not text.contains(word), "rally open: the Disaster view hides " + word)
