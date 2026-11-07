extends SceneTree
## A1: a remote Preparedness player plays a unit with "On play: move another ally" (Lane Marshal) and then
## moves an ally through a host pick: the ally, then an empty lane. The move is optional. The played unit is
## never the ally. Flag off keeps the old behaviour: no pick opens.

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

func unit(id: String, effect: String = "") -> Dictionary:
	var data := {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": 2,
		"attack": 1, "health": 10}
	if not effect.is_empty(): data["effect"] = effect
	return data

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
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func send(msg) -> Dictionary:
	return await LanActions.apply(game, msg, "preparedness")

func choice() -> RefCounted:
	return game.preparedness_actions.utility_choice

func pick_msg(handle) -> Dictionary:
	var open: RefCounted = choice()
	return {"kind": "utility_pick", "encounter": open.encounter, "choice": open.choice,
		"stage": open.stage, "handle": handle}

func lane_card(lane: int) -> Node:
	return game._get_card_in_slot(game._response_slots()[lane])

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.presentation.automated_choice = 0
	await process_frame
	# The full move: play, pick the ally, pick the lane.
	fixture()
	var ally := put(unit("a0"), game._response_slots()[0])
	game.add_card_to_hand(unit("marshal", "move_ally"))
	var result: Dictionary = await send({"kind": "play", "hand": 0, "lane": 1})
	expect(result.ok, "the unit is played")
	var marshal := lane_card(1)
	expect(game.preparedness == 3, "the unit is paid for once")
	expect(choice().active() and choice().kind == "relocation" and choice().stage == "ally", "a relocation pick opens")
	expect(choice().handles == [0], "only another ally can be moved, not the played unit")
	var view: Dictionary = LanView.build(game, "preparedness").pending_choice
	expect(view.kind == "relocation" and view.stage == "ally" and view.name == "Unit marshal", "the view shows the pick")
	result = await send({"kind": "play", "hand": 0, "lane": 2})
	expect(not result.ok, "no other play while the pick is open")
	result = await send(pick_msg(1))
	expect(result.reason == "bad_handle", "the played unit is refused as the ally")
	result = await send(pick_msg(0))
	expect(result.ok and choice().stage == "destination" and choice().handles == [2, 3], "empty lanes are offered")
	result = await send(pick_msg(1))
	expect(result.reason == "bad_handle", "an occupied lane is no destination")
	result = await send(pick_msg(3))
	expect(result.ok and not choice().active(), "the destination is accepted")
	expect(lane_card(3) == ally and lane_card(0) == null and lane_card(1) == marshal, "the ally moved to lane 4")
	expect(game.preparedness == 3, "the move costs nothing more")
	result = await send(pick_msg(3))
	expect(result.reason == "no_choice", "a repeated pick is refused")
	# Optional: cancel keeps everything where it is.
	fixture()
	ally = put(unit("a0"), game._response_slots()[0])
	game.add_card_to_hand(unit("marshal", "move_ally"))
	await send({"kind": "play", "hand": 0, "lane": 1})
	result = await send({"kind": "utility_cancel", "encounter": choice().encounter, "choice": choice().choice})
	expect(result.ok and not choice().active(), "cancel closes the pick")
	expect(lane_card(0) == ally and lane_card(1) != null and game.preparedness == 3, "cancel keeps the board and the cost")
	# Nothing to move: no pick.
	fixture()
	game.add_card_to_hand(unit("marshal", "move_ally"))
	await send({"kind": "play", "hand": 0, "lane": 1})
	expect(not choice().active(), "a lone unit has nobody to move, so no pick opens")
	# End turn is blocked while the pick is open.
	fixture()
	put(unit("a0"), game._response_slots()[0])
	game.add_card_to_hand(unit("marshal", "move_ally"))
	await send({"kind": "play", "hand": 0, "lane": 1})
	result = await send({"kind": "end"})
	expect(result.reason == "choice_pending", "End turn waits for the pick")
	# A plain unit never opens a pick.
	fixture()
	put(unit("a0"), game._response_slots()[0])
	game.add_card_to_hand(unit("plain"))
	await send({"kind": "play", "hand": 0, "lane": 1})
	expect(not choice().active(), "a unit without the move effect opens no pick")
	# Flag off: the old behaviour, no pick.
	fixture(false)
	put(unit("a0"), game._response_slots()[0])
	game.add_card_to_hand(unit("marshal", "move_ally"))
	result = await send({"kind": "play", "hand": 0, "lane": 1})
	expect(result.ok and not choice().active() and game.board_input.action.is_empty(), "flag off: the move is skipped")
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("%s: lan_relocation_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
