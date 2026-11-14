extends SceneTree
## A8: an identical LAN view repaints nothing and keeps the tactic buttons. A changed card or tactic refreshes
## only what changed. Resource-only changes keep the tactic buttons.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")

var failures := 0
var checks := 0
var game: Node
var session: Node

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)

func unit(card_name: String, health := 3) -> Dictionary:
	return {"name": card_name, "type": "response", "element": "evac", "cost": 0, "attack": 1, "health": health}

func entry(definition: Dictionary, health := -1) -> Dictionary:
	var copy := definition.duplicate(true)
	if health >= 0: copy.health = health
	return {"definition": copy, "runtime": {"max_health": int(definition.health), "statuses": {}, "modifiers": []}}

func make_view(ally_health: int, energy: int, brace_available: bool = true) -> Dictionary:
	return {
		"round": 2, "first_side": "response", "coin": {},
		"sides": {
			"response": {"hp": 14, "max_hp": 20, "barrier": 0, "resource": energy, "resource_cap": 5},
			"disaster": {"hp": 17, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["a", "b", "", ""], "disaster": ["", "", "", ""]},
		"cards": {"a": entry(unit("Ally One"), ally_health), "b": entry(unit("Ally Two")),
			"h0": entry(unit("Hand Zero"))},
		"hints": [{"can_play": true, "problem": "", "lanes": [2, 3]}],
		"side": "preparedness", "is_prep_turn": true, "prep_hand": ["h0"],
		"counts": {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8},
		"energy": energy, "energy_cap": 5, "plan_tokens": 0, "armed": "",
		"tactics": [{"id": "brace", "name": "Brace", "cost": 1, "available": brace_available, "lanes": [0, 1]}],
	}

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	session = LanSession.new()
	root.add_child(session)
	var panel := LanPrepPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "preparedness", cover)
	session.view_received.emit(make_view(3, 3))
	await process_frame
	var card: Node3D = board.lane_cards.response[0]
	var other: Node3D = board.lane_cards.response[1]
	var button: Button = board.tactic_tile_button("brace")
	var face_before: int = card.get_meta("lan_signature")
	var other_before: int = other.get_meta("lan_signature")
	session.view_received.emit(make_view(3, 3))
	await process_frame
	expect(board.tactic_tile_button("brace") == button, "an identical view keeps the tactic button")
	expect(card.get_meta("lan_signature") == face_before, "an identical view keeps the card signature")
	session.view_received.emit(make_view(3, 2))
	await process_frame
	expect(board.tactic_tile_button("brace") == button, "an energy-only change keeps the tactic button")
	expect(card.get_meta("lan_signature") == face_before and other.get_meta("lan_signature") == other_before,
		"an energy-only change repaints no card")
	session.view_received.emit(make_view(1, 2))
	await process_frame
	expect(int(card.card_data.health) == 1 and card.get_meta("lan_signature") != face_before, "a health change repaints that card")
	expect(other.get_meta("lan_signature") == other_before, "the other card is not repainted")
	session.view_received.emit(make_view(1, 2, false))
	await process_frame
	var rebuilt: Button = board.tactic_tile_button("brace")
	expect(rebuilt != button and rebuilt.disabled, "a changed tactic rebuilds the buttons")
	board.queue_free()
	session.queue_free()
	game.queue_free()
	await process_frame
	print("%s: lan_view_refresh_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
